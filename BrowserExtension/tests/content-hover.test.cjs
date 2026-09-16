const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");
const vm = require("node:vm");

test("pill presses preserve eligible editor focus without touching sensitive fields", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf('  toolbar.addEventListener("pointerdown"'), source.indexOf('  window.addEventListener("pointermove"'));
  let press, prevented = 0, focused = 0;
  const editor = { focus(options) { assert.equal(options.preventScroll, true); focused++; } };
  const context = vm.createContext({
    field: editor, eligible: value => value, drag: null, suppressClick: false,
    toolbar: { addEventListener(name, callback) { press = callback; },
      getBoundingClientRect: () => ({ left: 10, top: 20 }), classList: { remove() {} } },
  });
  vm.runInContext(handler, context);
  const event = { button: 0, pointerId: 1, clientX: 15, clientY: 25, preventDefault() { prevented++; } };
  press(event);
  assert.equal(prevented, 1); assert.equal(focused, 1);
  assert.equal(context.drag.id, 1, "focus preservation must not disable dragging");
  context.eligible = () => null;
  press(event);
  assert.equal(focused, 1, "a field that became sensitive must not be focused");
  press({ ...event, button: 2 });
  assert.equal(prevented, 2, "leave the right-click menu intact");
});

test("drag click suppression expires even when the browser emits no click", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  function finishDrag("), source.indexOf('  window.addEventListener("pointerup"'));
  const pending = [];
  const context = vm.createContext({
    drag: { id: 1, moved: true }, suppressClick: false, position: null,
    innerWidth: 1000, innerHeight: 800, guide: { hidden: false },
    toolbar: { getBoundingClientRect: () => ({ left: 8, top: 300, width: 36, height: 108 }),
      hasPointerCapture: () => false, classList: { remove() {}, add() {} } },
    scheduleRender() {}, setTimeout(fn, delay) { assert.equal(delay, 0); pending.push(fn); },
  });
  vm.runInContext(handler, context);
  context.finishDrag({ pointerId: 1 });
  assert.equal(context.suppressClick, true, "the immediate drag-generated click is suppressed");
  assert.equal(context.position.edge, "left");
  pending.forEach(fn => fn());
  assert.equal(context.suppressClick, false, "the next user click must remain usable");
  assert.equal(context.guide.hidden, true);
});

test("toolbar actions run once without a Safari document-focus event", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  function runPendingTool("), source.indexOf("  const observer ="));
  const calls = [];
  let receive;
  const context = vm.createContext({
    pendingTool: "rewrite", enabled: true, document: { hidden: false, hasFocus: () => false },
    field: { isConnected: true },
    extensionAPI: { runtime: { id: "extension", onMessage: { addListener: handler => { receive = handler; } } } },
    requestAnimationFrame() { throw new Error("Toolbar actions cannot depend on a background page animation frame"); },
    menu: { hidden: false }, grammar: () => calls.push("grammar"), requestTool: kind => calls.push(kind),
  });
  vm.runInContext(handler, context);
  for (const action of ["rewrite", "compose", "grammar"]) {
    receive({ target: "textwarden-page", action: "tool", tool: action }, { id: "extension" }, response => assert.equal(response.queued, true));
    context.runPendingTool();
  }
  assert.deepEqual(calls, ["rewrite", "compose", "grammar"]);
  assert.equal(context.menu.hidden, true);
  context.pendingTool = "rewrite"; context.document.hidden = true;
  context.runPendingTool(); context.document.hidden = false; context.runPendingTool();
  context.pendingTool = "compose"; context.enabled = false;
  context.runPendingTool(); context.enabled = true; context.runPendingTool();
  assert.equal(calls.length, 3, "hidden or disabled requests must be discarded, never replayed");
});

test("pill hover opens the full grammar view while underline hover stays compact", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  // Exercise the actual handlers without constructing an unrelated page DOM.
  const handlers = source.slice(source.indexOf("  function startHover("), source.indexOf("  function updateUI("));
  const events = new Map(), styleEvents = new Map(), timers = new Map(), sent = [];
  let nextTimer = 0;
  const context = vm.createContext({
    presentation: { hoverEnabled: true, hoverDelay: 250 },
    drag: null, hoverSuppressed: false, hoveredIssue: null, hoverTimer: null,
    session: "editor", revision: 1, issues: [{ id: 0 }], menu: { hidden: true },
    toolButtons: [[{ addEventListener: (name, handler) => styleEvents.set(name, handler) }, "style"]],
    suggestions: { addEventListener: (name, handler) => events.set(name, handler) },
    send: (kind, payload) => sent.push({ kind, ...payload }),
    highlightWord() {},
    setTimeout: (handler, delay) => { assert.equal(delay, 250); timers.set(++nextTimer, handler); return nextTimer; },
    clearTimeout: id => timers.delete(id),
  });
  vm.runInContext(handlers, context);
  function flush() { const pending = [...timers.values()]; timers.clear(); pending.forEach(handler => handler()); }

  vm.runInContext("startHover(issues[0])", context);
  assert.equal(sent.length, 0);
  flush();
  assert.equal(sent.at(-1).action, "hover");

  // The same first error must not make a pill hover reuse the compact view.
  events.get("pointerenter")();
  flush();
  assert.equal(sent.at(-1).action, "indicatorHover");
  events.get("pointermove")();
  assert.equal(sent.at(-1).kind, "hoverKeep");
  events.get("pointerleave")();
  assert.equal(sent.at(-1).kind, "hoverEnd");

  vm.runInContext("startHover(issues[0])", context);
  flush();
  assert.equal(sent.at(-1).action, "hover");

  events.get("pointerleave")();
  events.get("pointerenter")();
  context.revision++;
  const before = sent.length;
  flush();
  assert.equal(sent.length, before, "stale hover must not open a popover");
  events.get("pointerleave")();
  styleEvents.get("pointerenter")();
  flush();
  assert.equal(sent.at(-1).action, "styleHover");
  assert.equal(sent.at(-1).errorID, undefined);
  const requests = sent.filter(message => message.action === "styleHover").length;
  styleEvents.get("pointermove")();
  flush();
  assert.equal(sent.filter(message => message.action === "styleHover").length, requests, "pointer movement must not start duplicate AI requests");
  styleEvents.get("pointerleave")();
  context.presentation.hoverEnabled = false;
  events.get("pointerenter")();
  assert.equal(timers.size, 0);
});


test("pill geometry follows its edge and viewport size, without cursor coordinates", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  function indicatorGeometry("), source.indexOf("  function connect("));
  const sent = [];
  const context = vm.createContext({
    toolbar: { hidden: false, getBoundingClientRect: () => ({ left: 900, top: 160, width: 40, height: 80 }) },
    innerWidth: 1000, innerHeight: 800, position: undefined,
    field: null, session: "editor", revision: 1, port: { postMessage: message => sent.push(message) },
  });
  vm.runInContext(handler, context);
  for (const edge of ["right", "left", "top", "bottom"]) {
    context.position = { edge };
    for (const action of ["indicator", "indicatorHover", "style", "styleHover"]) {
      vm.runInContext(`send("show", { action: "${action}" })`, context);
      assert.deepEqual(JSON.parse(JSON.stringify(sent.at(-1).indicator)), { x: .9, y: .2, width: .04, height: .1, edge });
    }
    for (const kind of ["compose", "readability"]) {
      context.send(kind);
      assert.deepEqual(JSON.parse(JSON.stringify(sent.at(-1).indicator)), { x: .9, y: .2, width: .04, height: .1, edge });
    }
  }
  vm.runInContext('send("show", { action: "hover" })', context);
  assert.equal(sent.at(-1).indicator, undefined, "underline hovers retain their own placement");
});


test("reinjection refreshes policy without duplicating the active content script", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const startup = source.slice(0, source.indexOf("  let port,")) + "})();";
  let removed = 0, refreshed = 0, recovered = 0;
  const context = vm.createContext({ chrome: {}, requestPolicy() { refreshed++; }, checkConnection(userInitiated) { assert.equal(userInitiated, true); recovered++; }, document: {
    querySelectorAll: selector => {
      assert.equal(selector, "textwarden-overlay");
      return [{ remove: () => removed++ }, { remove: () => removed++ }];
    },
  } });
  vm.runInContext(startup, context);
  assert.equal(removed, 2);
  vm.runInContext(startup, context);
  assert.equal(removed, 2, "repeated activation must keep the live overlay");
  assert.equal(refreshed, 1, "repeat injection must refresh policy");
  assert.equal(recovered, 1, "explicit activation must also check for a stale paused-page port");
});

test("reconnecting content hides its pill until fresh results restore checking", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  function updateUI("), source.indexOf("  function requestPolicy("));
  const item = () => ({ classList: { toggle() {} }, setAttribute() {}, replaceChildren() {} });
  const styleButton = item();
  const context = vm.createContext({
    enabled: true, field: {}, reconnectNeeded: false, issues: [{ id: 1 }], checkingEnabled: true,
    presentation: { styleEnabled: true }, toolbar: { classList: { toggle() {} }, style: { setProperty() {} } },
    suggestions: item(), styleButton, toolButtons: [[styleButton, "style"]], status: { textContent: "" },
    host: { style: { setProperty() {} } }, pageState: () => ({}), lastPageState: {},
    createIcon() {}, icons: {},
  });
  vm.runInContext(handler, context);
  context.updateUI(); assert.equal(context.toolbar.hidden, false);
  context.reconnectNeeded = true; context.checkingEnabled = false; context.issues = [];
  context.updateUI(); assert.equal(context.toolbar.hidden, true, "do not overlay a disabled pill on the native fallback");
  context.reconnectNeeded = false; context.checkingEnabled = true; context.issues = [{ id: 1 }];
  context.updateUI(); assert.equal(context.toolbar.hidden, false, "fresh results restore the extension pill");
  context.enabled = false;
  context.updateUI(); assert.equal(context.toolbar.hidden, true, "page pauses still hide it");
});

test("scroll and resize cannot restore a reconnecting pill", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  function render("), source.indexOf("  function receive("));
  const context = vm.createContext({
    frame: 1, marks: { replaceChildren() {} }, wordTargets: [{}], enabled: true,
    reconnectNeeded: true, field: { isConnected: true }, document: { hidden: false },
    toolbar: { hidden: false }, menu: { hidden: false },
    eligible() { throw new Error("Reconnect rendering must stop before editor geometry is read"); },
  });
  vm.runInContext(handler, context);
  context.render();
  assert.equal(context.toolbar.hidden, true);
  assert.equal(context.menu.hidden, true);
  assert.equal(context.wordTargets.length, 0);
});

test("connection loss clears stale grammar, AI progress, and queued writing actions", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  function connectionLost("), source.indexOf("  function connect("));
  let cleared = 0, updated = 0;
  const context = vm.createContext({
    reconnectNeeded: false, checkingEnabled: true, issues: [{}], pendingTool: "compose", rewriting: true,
    hoverTimer: 1, hoveredIssue: {}, presentation: { styleLoading: true, styleCount: 3 },
    marks: { replaceChildren() { cleared++; } }, status: {}, clearTimeout() {}, updateUI() { updated++; },
  });
  vm.runInContext(handler + '\nconnectionLost("Mac app unavailable");', context);
  assert.equal(context.checkingEnabled, false);
  assert.equal(context.reconnectNeeded, true);
  assert.equal(context.issues.length, 0);
  assert.equal(context.pendingTool, null);
  assert.equal(context.presentation.styleLoading, false);
  assert.equal(context.presentation.styleCount, null);
  assert.equal(context.hoveredIssue, null);
  assert.equal(cleared, 1);
  assert.equal(updated, 1);
});


test("word hover uses visible text bounds without intercepting editor input", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  function hoverWord("), source.indexOf('  window.addEventListener("pointermove", (event) => {\n    if (event.isTrusted'));
  const field = {}, host = {}, broad = { id: 1, start: 0, end: 30 }, word = { id: 2, start: 4, end: 7 };
  const shown = [];
  const context = vm.createContext({
    enabled: true, checkingEnabled: true, showUnderlines: true, pageUnderlines: true, frame: null,
    field, host, issues: [broad, word], hoveredIssue: null, eligible: value => value,
    wordTargets: [broad, word].map(issue => ({ issue, rect: { left: 10, top: 20, right: 40, bottom: 40 } })),
    startHover: issue => { shown.push(issue.id); context.hoveredIssue = `underline:${issue.id}`; },
    endHover: () => { context.hoveredIssue = null; },
  });
  vm.runInContext(handler, context);
  const event = { buttons: 0, clientX: 25, clientY: 22, composedPath: () => [field] };
  context.hoverWord(event);
  assert.deepEqual(shown, [2], "the top of the word opens the most specific issue");
  context.hoverWord({ ...event, clientY: 19 });
  assert.equal(context.hoveredIssue, null, "outside visible word bounds ends hover");
  for (const patch of [{ buttons: 1 }, { composedPath: () => [{}] }, { composedPath: () => [host] }]) {
    context.hoverWord({ ...event, ...patch });
  }
  assert.equal(shown.length, 1, "selection drags, covering elements and pill events are untouched");
  for (const key of ["enabled", "checkingEnabled", "showUnderlines", "pageUnderlines"]) {
    context[key] = false; context.hoverWord(event); context[key] = true;
  }
  context.frame = 1; context.hoverWord(event); context.frame = null;
  context.eligible = () => null; context.hoverWord(event); context.eligible = value => value;
  context.issues = []; context.hoverWord(event);
  assert.equal(shown.length, 1, "paused, hidden, stale, pending geometry and sensitive fields cannot hover");
});

test("hover highlights every visible line of only the current issue", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const targets = [1, 2, 2].map(id => ({ issue: { id }, highlight: { hidden: true } }));
  const context = vm.createContext({ wordTargets: targets });
  vm.runInContext(source.slice(source.indexOf("  function highlightWord("), source.indexOf("  function hoverWord(")), context);
  context.highlightWord(2);
  assert.deepEqual(targets.map(target => target.highlight.hidden), [true, false, false]);
  context.highlightWord(null);
  assert.ok(targets.every(target => target.highlight.hidden));
});


test("Safari editor health recovers an unloaded background without replaying text", async () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  let healthPending ="), source.indexOf("  function connect("));
  const field = {}, calls = [];
  let answer = { known: true, ready: true };
  const context = vm.createContext({
    enabled: true, reconnectNeeded: false, field, port: { disconnect() { calls.push("disconnect"); } }, policySession: "policy",
    document: { hidden: false, hasFocus: () => false }, eligible: value => value,
    extensionAPI: { runtime: { async sendMessage(message) { calls.push(message); return answer; } } },
    setTimeout() { return 1; }, clearTimeout() {},
    connectionLost(detail) { calls.push(detail); }, requestPolicy() { calls.push("policy"); },
  });
  vm.runInContext(handler, context);
  await vm.runInContext("checkConnection()", context);
  assert.equal(calls.length, 1, "visible editors must retain their connection while a native popover has focus");
  assert.equal(calls[0].text, undefined);
  context.reconnectNeeded = true;
  await vm.runInContext("checkConnection()", context);
  assert.equal(calls.at(-1), "policy", "a healthy connection must recover a previous transient timeout");
  context.reconnectNeeded = false;
  calls.length = 0;
  await vm.runInContext("checkConnection()", context);
  assert.equal(calls.length, 1, "healthy editors must not request repeated analysis");
  answer = { known: false, ready: false };
  await vm.runInContext("checkConnection()", context);
  assert.ok(calls.includes("disconnect"));
  assert.equal(calls.at(-1), "policy");
  assert.equal(context.port, null);
  calls.length = 0;
  context.document.hidden = true;
  await vm.runInContext("checkConnection()", context);
  assert.equal(calls.length, 0, "hidden tabs must not keep backgrounds awake");
  context.document.hidden = false;
  context.eligible = () => null;
  await vm.runInContext("checkConnection()", context);
  assert.equal(calls.length, 0, "sensitive fields must not trigger connection checks");
  context.enabled = false; context.field = null;
  context.port = { disconnect() { calls.push("disconnect"); } };
  await vm.runInContext("checkConnection()", context);
  assert.equal(calls.length, 0, "paused pages must not keep backgrounds awake");
  await vm.runInContext("checkConnection(true)", context);
  assert.ok(calls.includes("disconnect"), "explicit toolbar activation must repair a paused page's stale port");
  assert.equal(calls.at(-1), "policy");
  assert.equal(calls[0].text, undefined, "recovery must not read or send editor text");
});


test("restoring policy after connection loss rechecks the current editor", () => {
  const source = readFileSync(require.resolve("../content.js"), "utf8");
  const handler = source.slice(source.indexOf("  function focus("), source.indexOf("  function changed("));
  const field = {};
  let checks = 0;
  const context = vm.createContext({ field, enabled: true, reconnectNeeded: true, eligible: x => x, changed() { checks++; } });
  vm.runInContext(handler, context);
  context.focus(field);
  assert.equal(checks, 1);
  context.reconnectNeeded = false;
  context.focus(field);
  assert.equal(checks, 1, "ordinary policy refresh must not rerun analysis");
  context.enabled = false;
  context.reconnectNeeded = true;
  context.focus(field);
  assert.equal(checks, 1, "a paused editor must not restart analysis");
});
