const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");
const vm = require("node:vm");
const source = readFileSync(require.resolve("../background.js"), "utf8");
const transport = source.slice(source.indexOf("function nativePort()"), source.indexOf("function connectNative("));
const flush = () => new Promise(resolve => setImmediate(resolve));

test("Safari sends in order, isolates connections, and never delivers after disconnect", async () => {
  const calls = [], polls = new Map(); let serial = 0;
  const context = vm.createContext({ crypto: { randomUUID: () => `client-${++serial}` }, extensionAPI: { runtime: {
    getURL: () => "safari-web-extension://example/",
    sendNativeMessage: async (_, request) => {
      calls.push(request);
      if (request.action === "poll") return new Promise(resolve => polls.set(request.client, resolve));
      return { ok: true };
    },
  } } });
  vm.runInContext(transport, context);
  const a = vm.runInContext("nativePort()", context), b = vm.runInContext("nativePort()", context);
  const delivered = []; let disconnected = 0;
  a.onMessage.addListener(message => delivered.push(message));
  a.onDisconnect.addListener(() => disconnected++);
  a.postMessage({ kind: "configuration" }); a.postMessage({ kind: "snapshot" });
  b.postMessage({ kind: "configuration" });
  await flush();
  assert.deepEqual(calls.filter(call => call.client === "client-1" && call.action === "send").map(call => call.message.kind), ["configuration", "snapshot"]);
  assert.ok(polls.has("client-1") && polls.has("client-2"));
  polls.get("client-1")({ messages: [{ kind: "result" }] }); await flush();
  assert.equal(delivered.length, 1);
  a.disconnect(); a.disconnect();
  polls.get("client-1")({ messages: [{ kind: "replace" }] }); await flush();
  assert.equal(delivered.length, 1); assert.equal(disconnected, 1);
  assert.throws(() => a.postMessage({ kind: "snapshot" }), /unavailable/);
  assert.equal(calls.filter(call => call.client === "client-1" && call.action === "close").length, 1);
  b.disconnect(); polls.get("client-2")({ messages: [] }); await flush();
});

test("Safari native failure closes the connection and discards queued edits", async () => {
  const calls = [];
  const context = vm.createContext({ crypto: { randomUUID: () => "client" }, extensionAPI: { runtime: {
    getURL: () => "safari-web-extension://example/",
    sendNativeMessage: async (_, request) => { calls.push(request); return { error: "Mac app unavailable" }; },
  } } });
  vm.runInContext(transport, context);
  const port = vm.runInContext("nativePort()", context); let closed = 0;
  port.onDisconnect.addListener(() => closed++);
  port.postMessage({ kind: "configuration" }); port.postMessage({ kind: "snapshot" });
  await flush();
  assert.equal(closed, 1);
  assert.deepEqual(calls.map(call => call.action), ["send", "close"]);
});
