const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");
const vm = require("node:vm");
const source = readFileSync(require.resolve("../content.js"), "utf8");

function harness({ beforeinput = () => true, throws = false } = {}) {
  const original = "😀 Café We has reviewed 17 reports.";
  const sent = [], commands = [];
  class Textarea {
    value = original; isConnected = true;
    focus() {}
    setSelectionRange(start, end) { this.start = start; this.end = end; }
    dispatchEvent(event) { return beforeinput(this, event); }
  }
  const field = new Textarea();
  const context = vm.createContext({
    field, session: "editor", revision: 2, checkedText: original, policySession: "policy",
    location: { origin: "https://example.com", pathname: "/editor" }, policyURL: "https://example.com/editor",
    eligible: element => element.sensitive ? null : element,
    extract: () => ({ text: field.value }), selectionRange: () => ({ start: field.start, end: field.end }),
    document: { hidden: false, execCommand(command, ui, value) {
      commands.push(command);
      if (throws) throw new Error("Editor rejected command");
      field.value = field.value.slice(0, field.start) + value + field.value.slice(field.end);
    } },
    HTMLTextAreaElement: Textarea, HTMLInputElement: class {}, InputEvent: class { constructor(type, options) { Object.assign(this, { type }, options); } },
    applyingReplacement: false, hoverSuppressed: false, issues: [{}], timer: null,
    observer: { takeRecords() {} }, marks: { replaceChildren() {} }, clearTimeout() {}, endHover() {},
    send: (kind, message) => sent.push({ kind, ...message }), changed() {}, updateUI() {}, scheduleRender() {},
    status: {}, menu: { hidden: true }, editFailure: null,
  });
  vm.runInContext(source.slice(source.indexOf("  function receive("), source.indexOf('  document.addEventListener("focusin"')), context);
  const message = { version: 1, kind: "replace", session: "editor", revision: 2, text: original,
    start: original.indexOf("has"), end: original.indexOf("has") + 3, replacement: "have" };
  return { field, context, sent, commands, apply: overrides => context.receive({ ...message, ...overrides }) };
}

test("correction uses UTF-16 offsets and acknowledges only the exact edited text", () => {
  const h = harness(); h.apply();
  assert.equal(h.field.value, "😀 Café We have reviewed 17 reports.");
  assert.deepEqual(h.commands, ["insertText"]);
  assert.equal(h.sent.at(-1).status, "ok");
  assert.equal(h.sent.at(-1).text, h.field.value);
  assert.equal(h.context.revision, 3);
});

test("stale source, revision, page, and AI selection never execute an edit", () => {
  for (const overrides of [{ text: "stale" }, { revision: 1 }, { start: -1 }, { selectionRequired: true }]) {
    const h = harness(); h.apply(overrides); assert.equal(h.commands.length, 0);
  }
  const h = harness(); h.context.policyURL = "https://example.com/old"; h.apply();
  assert.equal(h.commands.length, 0);
});

test("beforeinput cancellation and editor changes cannot be overwritten", () => {
  for (const beforeinput of [() => false, field => { field.value = "A newer draft"; return true; }, field => { field.sensitive = true; return true; }]) {
    const h = harness({ beforeinput }); h.apply();
    assert.equal(h.commands.length, 0);
    assert.equal(h.sent.at(-1).status, "failed");
    assert.equal(h.context.applyingReplacement, false);
  }
});

test("an editing command failure releases suppression and reports failure", () => {
  const h = harness({ throws: true });
  assert.doesNotThrow(() => h.apply());
  assert.equal(h.context.applyingReplacement, false);
  assert.equal(h.sent.at(-1).status, "failed");
  assert.equal(h.context.menu.hidden, false);
});
