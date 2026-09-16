const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");
const vm = require("node:vm");
const source = readFileSync(require.resolve("../content.js"), "utf8");

function harness() {
  class Element {
    constructor(attributes = {}) { this.attributes = attributes; this.labels = []; this.children = []; }
    getAttribute(name) { return this.attributes[name] ?? null; }
    closest(selector) {
      if (selector === "form") return this.form;
      if (selector.includes("readonly")) return this.attributes.readonly ? this : null;
      if (selector.includes("data-private")) return ["data-private", "data-sensitive"].some(key => key in this.attributes) || this.attributes.spellcheck === "false" ? this : null;
      return null;
    }
    querySelectorAll() { return this.children; }
  }
  class Input extends Element {
    get type() { return this.attributes.type || "text"; }
    get inputMode() { return this.attributes.inputmode || ""; }
    get spellcheck() { return this.attributes.spellcheck !== "false"; }
    get value() { throw new Error("Sensitive value was read"); }
    get selectionStart() { throw new Error("Sensitive selection was read"); }
  }
  class Textarea extends Element {}
  let observer, released = 0;
  const sent = [];
  const context = vm.createContext({
    HTMLElement: Element, HTMLInputElement: Input, HTMLTextAreaElement: Textarea,
    document: { querySelectorAll: () => [], getElementById: id => id === "code-label" ? { textContent: "Verification code" } : null },
    MutationObserver: class { constructor(callback) { this.callback = callback; this.records = []; observer = this; } observe() {} takeRecords() { return this.records.splice(0); } },
    field: null, session: "session", revision: 1, policySession: "policy",
    release: () => { released++; context.field = null; },
    port: { postMessage: message => sent.push(message) },
  });
  const functions = source.slice(source.indexOf("  const sensitiveFields"), source.indexOf("  function connectionLost("))
    + source.slice(source.indexOf("  function selectionRange("), source.indexOf("  function render("))
    + source.slice(source.indexOf("  function receive("), source.indexOf('  document.addEventListener("focusin"'));
  vm.runInContext(functions, context);
  return { context, Input, Element, observer, sent, released: () => released, run: code => vm.runInContext(code, context) };
}

test("sensitive inputs are rejected before reading text, selection, geometry or sending requests", () => {
  const h = harness();
  for (const attributes of [
    { type: "password" }, { autocomplete: "section-login current-password" },
    { autocomplete: "new-password" }, { autocomplete: "one-time-code" },
    { autocomplete: "cc-number" }, { autocomplete: "cc-csc" },
    { name: "code" }, { name: "passcode" }, { name: "otp" }, { name: "totp" }, { name: "pin" }, { id: "verificationCode" },
    { placeholder: "One time code" }, { "aria-label": "Recovery phrase" },
    { name: "api_key" }, { id: "access-token" }, { name: "iban" },
    { inputmode: "numeric" }, { "data-private": "" }, { spellcheck: "false" },
    { "aria-labelledby": "code-label" },
  ]) {
    h.context.field = new h.Input(attributes);
    assert.equal(h.run("eligible(field)"), null, JSON.stringify(attributes));
    assert.equal(h.run("extract().text"), "");
    assert.equal(h.run("selectionRange()"), null);
    assert.equal(h.run("measure().text"), "");
    h.run('send("snapshot", { text: "must not leave" })');
    h.run('send("rewrite", { text: "must not leave" })');
  }
  assert.equal(h.sent.length, 0);
  const labelled = new h.Input(); labelled.labels = [{ textContent: "Two-factor authentication code" }];
  h.context.field = labelled; assert.equal(h.run("eligible(field)"), null);
  const login = new h.Input(); login.form = { querySelector: () => ({}) };
  h.context.field = login; assert.equal(h.run("eligible(field)"), null);
});

test("ordinary prose remains eligible but revealed passwords and protected rich text do not", () => {
  const h = harness(), normal = new h.Input({ name: "message" });
  h.context.field = normal; assert.equal(h.run("eligible(field)"), normal);
  h.observer.records.push({ attributeName: "type", oldValue: "password", target: normal });
  assert.equal(h.run("eligible(field)"), null, "pending mutation must protect a revealed password immediately");
  assert.equal(h.run("eligible(field)"), null, "revealed password stays protected");
  const root = new h.Element(); root.isContentEditable = true;
  root.children = [new h.Input({ autocomplete: "one-time-code" })];
  h.context.field = root; assert.equal(h.run("eligible(field)"), null);
});

test("a late correction cannot focus or edit a field that became sensitive", () => {
  const h = harness();
  h.context.field = new h.Input({ autocomplete: "one-time-code" });
  h.run('receive({version: 1, kind: "replace", session: "session", revision: 1, text: "secret", replacement: "edited", start: 0, end: 6})');
  assert.equal(h.released(), 1);
  assert.equal(h.sent.length, 0);
  h.context.field = new h.Input({ name: "password" });
  h.observer.callback([]);
  assert.equal(h.released(), 2, "attribute changes revoke the editor session");
});
