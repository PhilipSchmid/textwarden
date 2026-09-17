const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");
const vm = require("node:vm");

function event() {
  const listeners = [];
  return { addListener(fn) { listeners.push(fn); }, emit(...args) { for (const fn of listeners) fn(...args); } };
}
async function harness({ noReceiver = false, url = "https://example.com/editor", manifest = { version_name: "0.5.2", version: "0.5.2.38" } } = {}) {
  const elements = new Map(), timers = new Map(), sent = [];
  const element = id => {
    if (!elements.has(id)) elements.set(id, { dataset: {}, hidden: false, disabled: false, textContent: "", setAttribute(name, value) { this[name] = value; }, listeners: {}, addEventListener(name, fn) { this.listeners[name] = fn; } });
    return elements.get(id);
  };
  const tools = ["rewrite"].map(tool => { const e = element(tool); e.dataset.tool = tool; return e; });
  const pauses = ["Paused for 1 Hour", "Paused for 24 Hours", "Paused Until Resumed"].map(pause => { const e = element(pause); e.dataset.pause = pause; return e; });
  const port = { onMessage: event(), onDisconnect: event(), postMessage(message) { sent.push(message); } };
  const chrome = {
    runtime: { id: "extension", onMessage: event(), getManifest: () => manifest, connect: () => port },
    tabs: { query: async () => [{ id: 1, url }], sendMessage: async () => noReceiver ? undefined : ({ enabled: true, pageUnderlines: true, hasEditor: true, hasSelection: true, issueCount: 2, status: "2 suggestions" }) },
  };
  vm.runInNewContext(readFileSync(require.resolve("../popup.js"), "utf8"), {
    chrome, URL, crypto: { randomUUID: () => "popup-session" }, window: { close() {} },
    document: { getElementById: element, querySelectorAll: selector => selector === "[data-pause]" ? pauses : tools, documentElement: { dataset: {} } },
    setTimeout(fn, delay) { timers.set(fn, delay); return fn; }, clearTimeout(fn) { timers.delete(fn); },
  });
  await new Promise(setImmediate);
  const reply = (extra = {}) => port.onMessage.emit({ version: 1, kind: "configuration", session: "popup-session", pageEnabled: true, siteEnabled: true, appVersion: "0.5.2", appBuild: "38", ...extra });
  return { element, timers, sent, port, reply, chrome, tools };
}
function assertUnavailable(h) {
  for (const id of ["enabled", "underlines", "website", "settings", "rewrite"]) assert.equal(h.element(id).disabled, true, id);
}

test("popup disables stale controls on connection loss and recovers only after app configuration", async () => {
  const h = await harness();
  assertUnavailable(h);
  h.reply();
  assert.equal(h.element("connection").textContent, "Connected to Mac app");
  assert.equal(h.element("underlines").disabled, false);
  h.port.onMessage.emit({ version: 1, kind: "connection", status: "disconnected", detail: "Open TextWarden and reconnect." });
  assertUnavailable(h);
  assert.equal(h.element("status").textContent, "Open TextWarden and reconnect.");
  assert.equal(h.element("reconnect").hidden, false);
  h.element("reconnect").listeners.click();
  assert.equal(h.sent.at(-1).action, "connect");
  assert.equal(h.element("connection").dataset.state, "connecting");
  h.port.onMessage.emit({ version: 1, kind: "connection", status: "connected" });
  assertUnavailable(h);
  h.reply();
  assert.equal(h.element("rewrite").disabled, false);
  assert.equal(h.element("reconnect").hidden, true);
  assert.equal(h.timers.size, 0);
});

test("configuration timeout fails closed; extension reload never offers a dead reconnect button", async () => {
  const h = await harness();
  for (const [callback, delay] of [...h.timers]) { assert.equal(delay, 8000); callback(); }
  assertUnavailable(h);
  assert.match(h.element("status").textContent, /not responding/);
  h.reply();
  h.port.onDisconnect.emit();
  assertUnavailable(h);
  assert.equal(h.element("reconnect").hidden, true);
  assert.match(h.element("status").textContent, /Close and reopen/);
  // A late editor status update cannot restore controls or the dead reconnect action.
  h.chrome.runtime.onMessage.emit({ target: "textwarden-popup", page: { enabled: true, hasEditor: true, hasSelection: true } }, { id: "extension", tab: { id: 1 }, frameId: 0 });
  assertUnavailable(h);
});

test("paused app keeps writing tools disabled and provides a contextual recovery action", async () => {
  const h = await harness();
  h.reply({ appPaused: true, browserBundleID: "com.brave.Browser" });
  assert.equal(h.element("pauseNotice").hidden, false);
  assert.equal(h.element("resume").textContent, "Resume in Brave");
  for (const tool of h.tools) assert.equal(tool.disabled, true);
  h.element("resume").listeners.click();
  assert.equal(h.sent.at(-1).action, "resumeBrowser");
  h.reply({ globalPaused: true });
  h.element("resume").listeners.click();
  assert.equal(h.sent.at(-1).action, "settings");
});

test("website pause choices send the selected duration and expose a resume action", async () => {
  const h = await harness(); h.reply();
  h.element("website").listeners.click();
  assert.equal(h.element("sitePauseMenu").hidden, false);
  h.element("Paused for 1 Hour").listeners.click();
  assert.equal(h.sent.at(-1).action, "pauseSite");
  assert.equal(h.sent.at(-1).pause, "Paused for 1 Hour");
  assert.equal(h.element("sitePauseMenu").hidden, true);
  h.reply({ siteEnabled: false, pageEnabled: false, sitePausedUntil: Date.now() / 1000 + 3600 });
  assert.match(h.element("siteScope").textContent, /^Paused until /);
  assert.equal(h.element("enabled").disabled, true);
  h.element("website").listeners.click();
  assert.equal(h.sent.at(-1).action, "resumeSite");
});

test("a page without a content-script receiver still connects and fails closed until configured", async () => {
  const h = await harness({ noReceiver: true });
  assertUnavailable(h);
  assert.equal(h.sent.at(-1).action, "connect");
  h.reply();
  assert.equal(h.element("connection").textContent, "Connected to Mac app");
  assert.equal(h.element("rewrite").disabled, true);
  assert.equal(h.element("underlines").disabled, false);
  assert.equal(h.element("status").hidden, true);
  assert.equal(h.element("rewrite").hidden, true);
});

test("Firefox release versions match the app build without version_name", async () => {
  const h = await harness({ manifest: { version: "0.6.0.40" } });
  h.reply({ appVersion: "0.6.0-beta.1", appBuild: "40" });
  assert.equal(h.element("version").textContent, "v0.6.0-beta.1");
  h.reply({ appVersion: "0.6.0-beta.1", appBuild: "41" });
  assert.match(h.element("error").textContent, /Install both from the same release/);
});

test("named extension versions still detect different app builds", async () => {
  const h = await harness();
  h.reply();
  assert.equal(h.element("error").hidden, true);
  h.reply({ appBuild: "39" });
  assert.equal(h.element("error").hidden, false);
  assert.match(h.element("error").textContent, /0\.5\.2\.38/);
  assert.match(h.element("error").textContent, /build 39/);
  h.reply();
  assert.equal(h.element("error").hidden, true);
});

// Truncated visual labels must retain the address without exposing URL credentials or tokens.
test("address hover labels preserve host, port and path without query or fragment", async () => {
  const path = "/documents/" + "long-path/".repeat(40) + "editor";
  const h = await harness({ url: `https://user:password@example.com:8443${path}?token=private#secret` });
  h.reply();
  assert.equal(h.element("site").title, "example.com:8443");
  assert.equal(h.element("pagePath").title, path);
  assert.equal(h.element("siteScope").title, "All pages on example.com:8443");
});


test("rewrite appears only for a selection in an enabled editor; healthy status stays quiet", async () => {
  const h = await harness(); h.reply();
  assert.equal(h.element("status").hidden, true);
  assert.equal(h.element("rewrite").hidden, false);
  const sender = { id: "extension", tab: { id: 1 }, frameId: 0 };
  h.chrome.runtime.onMessage.emit({ target: "textwarden-popup", page: { enabled: true, hasEditor: true, hasSelection: false } }, sender);
  assert.equal(h.element("rewrite").hidden, true);
  h.chrome.runtime.onMessage.emit({ target: "textwarden-popup", page: { enabled: true, hasEditor: true, hasSelection: true } }, sender);
  assert.equal(h.element("rewrite").hidden, false);
  h.reply({ siteEnabled: false, pageEnabled: false });
  assert.equal(h.element("rewrite").hidden, true);
  assert.equal(h.element("websiteLabel").textContent, "Resume website");
  assert.equal(h.element("website").dataset.paused, "true");
  assert.equal(h.element("siteScope").textContent, "Paused until resumed");
  assert.equal(h.element("status").hidden, false);
});


test("contextual rewrite retains the existing editor command and reports failed handoff", async () => {
  const h = await harness(); h.reply();
  let command;
  h.chrome.tabs.sendMessage = async (tabID, message) => { command = { tabID, ...message }; return { queued: true }; };
  await h.element("rewrite").listeners.click();
  assert.deepEqual(JSON.parse(JSON.stringify(command)), { tabID: 1, target: "textwarden-page", action: "tool", tool: "rewrite" });
  h.chrome.tabs.sendMessage = async () => ({ queued: false });
  await h.element("rewrite").listeners.click();
  assert.equal(h.element("error").hidden, false);
  assert.match(h.element("error").textContent, /Return to the text field/);
});
