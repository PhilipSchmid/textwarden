const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");
const vm = require("node:vm");

function event() {
  const listeners = [];
  return { addListener(fn) { listeners.push(fn); }, async emit(...args) { for (const fn of listeners) await fn(...args); } };
}

function harness() {
  const sent = [], delivered = [], timers = []; let connections = 0;
  const native = { onMessage: event(), onDisconnect: event(), postMessage(message) { sent.push(message); }, disconnect() {} };
  const chrome = {
    action: { onClicked: event(), async setBadgeText() {} },
    scripting: { async executeScript() {} },
    runtime: { id: "test-extension", getURL(path) { return `chrome-extension://test-extension/${path}`; }, onMessage: event(), onConnect: event(), connectNative() { connections++; return native; } },
    tabs: { onUpdated: event(), async get(id) { return { id, active: true, windowId: 1, url: "https://example.com/editor?private-query" }; } },
    windows: { async get() { return { focused: true }; } },
  };
  vm.runInNewContext(readFileSync(require.resolve("../background.js"), "utf8"), { chrome, URL, crypto: { randomUUID: () => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }, setTimeout(fn) { timers.push(fn); return fn; }, clearTimeout(fn) { const index = timers.indexOf(fn); if (index !== -1) timers.splice(index, 1); } });
  function port(tabID, url = "https://example.com/editor?private-query", incognito = false) {
    return { name: "textwarden-editor", sender: { id: "test-extension", frameId: 0, tab: { id: tabID, incognito }, url }, onMessage: event(), onDisconnect: event(), disconnected: false,
      postMessage(message) { delivered.push({ tabID, message }); }, disconnect() { this.disconnected = true; } };
  }
  return { chrome, native, sent, delivered, port, timers, connections: () => connections, async ready() { await native.onMessage.emit({ version: 1, kind: "configuration", session: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }); sent.length = 0; delivered.length = 0; } };
}

test("native routing derives origin from Chrome and rejects cross-tab session reuse", async () => {
  const h = harness();
  const a = h.port(1), b = h.port(2);
  await h.chrome.runtime.onConnect.emit(a);
  await h.chrome.runtime.onConnect.emit(b);
  const message = { version: 1, kind: "snapshot", session: "12345678-1234-4234-8234-123456789012", revision: 1, origin: "https://forged.example", text: "We has a report." };
  await a.onMessage.emit(message);
  await h.ready();
  await a.onMessage.emit(message);
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].origin, "https://example.com");
  await b.onMessage.emit(message);
  assert.equal(h.sent.length, 1);
  await h.native.onMessage.emit({ ...message, kind: "result", errors: [] });
  assert.equal(h.delivered[0].tabID, 1);
  await a.onDisconnect.emit();
  assert.equal(h.sent.at(-1).kind, "release");
});

test("private pages, privileged URLs, and oversized text do not reach the native app", async () => {
  const h = harness();
  const privatePort = h.port(1, "https://example.com", true);
  await h.chrome.runtime.onConnect.emit(privatePort);
  assert.equal(privatePort.disconnected, true);
  const privileged = h.port(2, "chrome://settings");
  await h.chrome.runtime.onConnect.emit(privileged);
  assert.equal(privileged.disconnected, true);
  const normal = h.port(3);
  await h.chrome.runtime.onConnect.emit(normal);
  await normal.onMessage.emit({ version: 1, kind: "snapshot", session: "12345678-1234-4234-8234-123456789012", text: "x".repeat(20001) });
  await normal.onMessage.emit({ version: 1, kind: "replace", session: "12345678-1234-4234-8234-123456789012" });
  await normal.onMessage.emit({ version: 1, kind: "configuration", session: "12345678-1234-4234-8234-123456789012", action: "pauseBrowser" });
  assert.equal(h.sent.length, 0);
});

test("replacements and grammar shortcuts require the active tab and window", async () => {
  const h = harness();
  const p = h.port(1);
  await h.chrome.runtime.onConnect.emit(p);
  const message = { version: 1, kind: "snapshot", session: "12345678-1234-4234-8234-123456789012", revision: 1, text: "We has a report." };
  await p.onMessage.emit(message);
  await h.ready();
  await p.onMessage.emit(message);
  h.chrome.tabs.get = async () => ({ active: false, windowId: 1 });
  for (const kind of ["replace", "request"]) await h.native.onMessage.emit({ ...message, kind, action: "grammar" });
  assert.equal(h.delivered.length, 1);
  assert.equal(h.delivered[0].message.kind, "status");
  assert.match(h.delivered[0].message.status, /Nothing was changed/);
  h.delivered.length = 0;
  h.chrome.tabs.get = async () => ({ id: 1, active: true, windowId: 1, url: "https://example.com/editor?private-query" });
  h.chrome.windows.get = async () => ({ focused: false });
  for (const kind of ["replace", "request"]) await h.native.onMessage.emit({ ...message, kind, action: "grammar" });
  assert.equal(h.delivered.length, 1);
  assert.equal(h.delivered[0].message.kind, "status");
  h.delivered.length = 0;
  h.chrome.windows.get = async () => ({ focused: true });
  await h.native.onMessage.emit({ ...message, kind: "request", action: "grammar" });
  assert.equal(h.delivered.length, 1);
  assert.equal(h.delivered[0].message.action, "grammar");
});

test("replacement cannot outlive its editor while checking window focus", async () => {
  const h = harness(), p = h.port(1);
  await h.chrome.runtime.onConnect.emit(p);
  const message = { version: 1, kind: "snapshot", session: "12345678-1234-4234-8234-123456789012", revision: 1, text: "We has a report." };
  await p.onMessage.emit(message);
  await h.ready();
  await p.onMessage.emit(message);
  let resolveWindow;
  h.chrome.windows.get = () => new Promise((resolve) => { resolveWindow = resolve; });
  const pending = h.native.onMessage.emit({ ...message, kind: "replace" });
  await new Promise(setImmediate);
  await p.onMessage.emit({ ...message, kind: "release" });
  resolveWindow({ focused: true });
  await pending;
  assert.equal(h.delivered.length, 0);
});

test("editor focus notifications cannot discard an in-flight replacement", async () => {
  const h = harness(), p = h.port(1);
  await h.chrome.runtime.onConnect.emit(p);
  const message = { version: 1, kind: "snapshot", session: "12345678-1234-4234-8234-123456789012", revision: 1, text: "We has a report." };
  await p.onMessage.emit(message);
  await h.ready();
  await p.onMessage.emit(message);
  let resolveWindow;
  h.chrome.windows.get = () => new Promise(resolve => { resolveWindow = resolve; });
  const pending = h.native.onMessage.emit({ ...message, kind: "replace" });
  await new Promise(setImmediate);
  await p.onMessage.emit({ ...message, kind: "focus" });
  resolveWindow({ focused: true });
  await pending;
  assert.equal(h.delivered.length, 1);
  assert.equal(h.delivered[0].message.kind, "replace");
});

test("page activation finishes in the worker after the popup has closed", async () => {
  const h = harness(), actions = [];
  h.chrome.tabs.get = async (id) => ({ id, active: true, url: "https://example.com", incognito: false });
  let finishInjection;
  h.chrome.scripting.executeScript = options => new Promise((resolve) => { finishInjection = () => { actions.push(options); resolve(); }; });
  const popup = h.port(4);
  popup.name = "textwarden-popup";
  popup.sender = { id: "test-extension", url: h.chrome.runtime.getURL("popup.html") };
  await h.chrome.runtime.onConnect.emit(popup);
  await popup.onMessage.emit({ version: 1, kind: "configuration", session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", action: "connect", tabID: 4 });
  await popup.onDisconnect.emit();
  await new Promise(setImmediate);
  assert.equal(actions.length, 0);
  finishInjection();
  await new Promise(setImmediate);
  assert.equal(actions.length, 1);
  assert.equal(actions[0].target.tabId, 4);
  assert.equal(actions[0].files[0], "content.js");
});


test("one connection serves popup and editor, then reconnects without replaying editor text", async () => {
  const h = harness(), p = h.port(1);
  await h.chrome.runtime.onConnect.emit(p);
  const snapshot = { version: 1, kind: "snapshot", session: "12345678-1234-4234-8234-123456789012", text: "We has a report." };
  await p.onMessage.emit(snapshot);
  assert.equal(h.sent[0].action, "status");
  await h.ready();
  const popup = h.port(2);
  popup.name = "textwarden-popup";
  popup.sender = { id: "test-extension", url: h.chrome.runtime.getURL("popup.html") };
  h.chrome.tabs.get = async id => ({ id, active: true, windowId: 1, url: "https://example.com" });
  await h.chrome.runtime.onConnect.emit(popup);
  await popup.onMessage.emit({ version: 1, kind: "configuration", session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", action: "connect", tabID: 1 });
  assert.equal(h.connections(), 1);
  assert.equal(h.sent.at(-1).action, "status");
  await popup.onMessage.emit({ version: 1, kind: "configuration", session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", action: "browserPause", pause: "Paused for 1 Hour", tabID: 1 });
  assert.equal(h.sent.at(-1).action, "browserPause");
  h.sent.length = 0; h.delivered.length = 0;
  await h.native.onDisconnect.emit();
  assert.equal(h.delivered[0].message.status, "disconnected");
  h.timers.shift()();
  assert.equal(h.connections(), 2);
  assert.equal(h.sent[0].action, "status");
  assert.ok(h.sent.every(message => message.text === undefined));
  await h.native.onMessage.emit({ version: 1, kind: "configuration", session: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" });
  assert.ok(h.delivered.some(entry => entry.message.action === "refresh"));
  assert.ok(h.sent.every(message => message.action === "status")); // Do not extend an earlier pause after reconnecting.
  assert.ok(h.sent.every(message => message.text === undefined));
});

test("popup explicitly requests app launch; missing registration does not retry", async () => {
  const h = harness(), p = h.port(1);
  p.name = "textwarden-popup";
  p.sender = { id: "test-extension", url: h.chrome.runtime.getURL("popup.html") };
  h.chrome.tabs.get = async id => ({ id, active: true, url: "https://example.com" });
  await h.chrome.runtime.onConnect.emit(p);
  await p.onMessage.emit({ version: 1, kind: "configuration", session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", action: "connect", tabID: 1 });
  assert.equal(h.sent[0].action, "connect");
  h.chrome.runtime.lastError = { message: "Specified native messaging host not found." };
  await h.native.onDisconnect.emit();
  assert.equal(h.timers.length, 0);
  assert.match(h.delivered.at(-1).message.detail, /Settings → Browser/);
});


test("page identity preserves ports and paths, strips secrets, and rejects edits after navigation", async () => {
  const h = harness(), p = h.port(1, "http://localhost:8766/Editor?token=private#selection");
  h.chrome.tabs.get = async id => ({ id, active: true, windowId: 1, url: "http://localhost:8766/Editor?token=private#selection" });
  await h.chrome.runtime.onConnect.emit(p);
  const message = { version: 1, kind: "snapshot", session: "12345678-1234-4234-8234-123456789012", revision: 1, text: "We has a report." };
  await p.onMessage.emit(message); await h.ready(); await p.onMessage.emit(message);
  assert.equal(h.sent.at(-1).origin, "http://localhost:8766");
  assert.equal(h.sent.at(-1).pageURL, "http://localhost:8766/Editor");
  h.chrome.tabs.get = async id => ({ id, active: true, windowId: 1, url: "http://localhost:8766/other" });
  await h.native.onMessage.emit({ ...message, kind: "replace" });
  assert.equal(h.delivered.length, 0);
});

test("health probes do not replay work, and a stalled app disables every client", async () => {
  const h = harness(), p = h.port(1);
  await h.chrome.runtime.onConnect.emit(p);
  await p.onMessage.emit({ version: 1, kind: "snapshot", session: "12345678-1234-4234-8234-123456789012", text: "We has a report." });
  await h.ready();
  h.timers.shift()(); // Healthy connection's next probe.
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].action, "status");
  assert.equal(h.sent[0].text, undefined);
  await h.native.onMessage.emit({ version: 1, kind: "configuration", session: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" });
  assert.equal(h.delivered.length, 0, "health response must not refresh editors or start analysis");
  h.timers.shift()(); // Next probe gets no response.
  h.timers.shift()(); // Eight-second deadline.
  assert.equal(h.delivered.at(-1).message.status, "disconnected");
  assert.match(h.delivered.at(-1).message.detail, /not responding/);
});

test("a native helper that never completes its handshake has a bounded deadline", async () => {
  const h = harness(), p = h.port(1);
  await h.chrome.runtime.onConnect.emit(p);
  await p.onMessage.emit({ version: 1, kind: "pageStatus", session: "12345678-1234-4234-8234-123456789012" });
  h.timers.shift()();
  assert.equal(h.delivered.at(-1).message.status, "disconnected");
  assert.equal(h.timers.length, 1, "only the bounded retry remains scheduled");
});


test("health probes stop when the last client disconnects", async () => {
  const h = harness(), p = h.port(1);
  await h.chrome.runtime.onConnect.emit(p);
  await p.onMessage.emit({ version: 1, kind: "pageStatus", session: "12345678-1234-4234-8234-123456789012" });
  await h.ready();
  const pending = h.timers.shift();
  await p.onDisconnect.emit();
  h.sent.length = 0;
  pending();
  assert.equal(h.sent.length, 0);
  assert.equal(h.timers.length, 0);
});


test("editor health reveals only whether the sender owns its current session", async () => {
  const h = harness(), port = h.port(1);
  const session = "12345678-1234-4234-8234-123456789012";
  await h.chrome.runtime.onConnect.emit(port);
  await port.onMessage.emit({ version: 1, kind: "pageStatus", session });
  await h.ready();
  const replies = [];
  const message = { target: "textwarden-background", action: "health", session };
  await h.chrome.runtime.onMessage.emit(message, port.sender, response => replies.push(response));
  assert.equal(replies.at(-1).known, true);
  assert.equal(replies.at(-1).ready, true);
  await h.chrome.runtime.onMessage.emit(message, h.port(2).sender, response => replies.push(response));
  assert.equal(replies.at(-1).known, false);
  await h.chrome.runtime.onMessage.emit(message, h.port(1, "https://example.com", true).sender, response => replies.push(response));
  assert.equal(replies.length, 2, "private tabs must not query session state");
});
