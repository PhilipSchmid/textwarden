const extensionAPI = globalThis.browser ?? chrome;
const sessions = new Map(), clients = new Set();
const toolbarStates = new Map();
let native, retryTimer, attempts = 0, ready = false;
const handshake = crypto.randomUUID();
const configurationActions = new Set(["status", "connect", "pausePageRule", "resumePage", "pauseSite", "resumeSite", "pauseBrowser", "resumeBrowser", "settings", "websites", "globalPause", "browserPause"]);

function address(value) {
  const url = new URL(value);
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) throw new Error();
  return { origin: url.origin, pageURL: url.origin + url.pathname };
}
function setToolbar(tabId, state = "Open to check this page") {
  if (toolbarStates.get(tabId)?.state === state) return;
  toolbarStates.set(tabId, { state });
  const paused = state.startsWith("Paused") || state === "Mac app unavailable";
  const template = extensionAPI.runtime.getURL("").startsWith("safari-web-extension:") ? "-dark" : "";
  const icon = `toolbar${paused ? "-paused" : ""}${template}`;
  extensionAPI.action.setIcon({ tabId, path: { 16: `${icon}-16.png`, 32: `${icon}.png` } }).catch(() => {});
  extensionAPI.action.setTitle({ tabId, title: `TextWarden (${state})` }).catch(() => {});
}
async function updateToolbar(entry, message) {
  const previous = { ...toolbarStates.get(entry.tabID) }, connection = native;
  toolbarStates.set(entry.tabID, previous);
  const tab = await extensionAPI.tabs.get(entry.tabID).catch(() => null);
  if (!ready || native !== connection || !tab || tab.incognito || sessions.get(message.session) !== entry || toolbarStates.get(entry.tabID) !== previous) return;
  try { if (address(tab.url).pageURL !== entry.pageURL || message.pageURL !== entry.pageURL) return; } catch { return; }
  const state = message.globalPaused ? "Paused everywhere" : message.appPaused ? "Paused in this browser"
    : message.siteEnabled === false ? "Paused on this website" : message.pageEnabled === false ? "Paused on this page" : "Checking enabled";
  setToolbar(entry.tabID, state);
}
async function syncPage(tabID) {
  const tab = await extensionAPI.tabs.get(tabID);
  if (!tab.active || tab.incognito) return;
  address(tab.url);
  await extensionAPI.scripting.executeScript({ target: { tabId: tabID }, files: ["content.js"] });
}
function notifyConnection(status, detail) {
  for (const port of clients) {
    try { port.postMessage({ version: 1, kind: "connection", status, detail }); } catch {}
  }
}
function connectionError(error = "") {
  if (/not found|forbidden|not registered/i.test(error)) return "Open TextWarden to configure the connection automatically. If needed, use Try Again in Settings \u2192 Browser.";
  return "TextWarden is not responding. Open the app or choose Reconnect.";
}
function refreshSessions(connection) {
  // Re-read current editors; never replay cached text, edits, or already-applied settings.
  for (const [session, entry] of sessions) {
    if (entry.control) {
      connection.postMessage({ ...entry.configuration, origin: entry.origin, pageURL: entry.pageURL });
      entry.configuration = { ...entry.configuration, action: "status", pause: undefined };
    } else entry.port.postMessage({ version: 1, kind: "request", session, action: "refresh" });
  }
}
// Safari's native extension replies to individual requests; keep each profile's
// message queue private instead of broadcasting editor text through dispatchMessage.
function nativePort() {
  if (!extensionAPI.runtime.getURL("").startsWith("safari-web-extension:")) return extensionAPI.runtime.connectNative("io.textwarden.browser");
  const client = crypto.randomUUID(), messages = new Set(), disconnected = new Set();
  let closed = false, polling = false, sending = Promise.resolve();
  async function request(action, message) {
    const response = await extensionAPI.runtime.sendNativeMessage("io.textwarden.browser", { client, action, ...(message ? { message } : {}) });
    if (!response || response.error) throw new Error("Mac app unavailable");
    return response;
  }
  function close() {
    if (closed) return;
    closed = true;
    request("close").catch(() => {});
    for (const listener of disconnected) listener();
  }
  async function poll() {
    if (polling) return;
    polling = true;
    try {
      while (!closed) {
        const response = await request("poll");
        if (closed) return;
        for (const message of response.messages ?? []) for (const listener of messages) listener(message);
      }
    } catch { close(); }
  }
  return {
    onMessage: { addListener: listener => messages.add(listener) },
    onDisconnect: { addListener: listener => disconnected.add(listener) },
    postMessage(message) {
      if (closed) throw new Error("Mac app unavailable");
      sending = sending.then(() => { if (closed) throw new Error(); return request("send", message); }).then(() => { void poll(); }).catch(close);
    },
    disconnect: close,
  };
}
function connectNative(launch = false) {
  if (native) return native;
  clearTimeout(retryTimer); retryTimer = null;
  const connection = nativePort();
  native = connection; ready = false;
  let healthTimer;
  function probe(launch = false) {
    if (native !== connection) return;
    healthTimer = setTimeout(() => {
      disconnect("TextWarden did not respond.");
      connection.disconnect();
    }, 8000);
    connection.postMessage({ version: 1, kind: "configuration", session: handshake, action: launch ? "connect" : "status" });
  }
  notifyConnection("connecting", "Connecting to TextWarden\u2026");
  connection.onMessage.addListener(async (message) => {
    if (native !== connection) return;
    if (message.version === 1 && message.session === handshake && message.kind === "configuration") {
      clearTimeout(healthTimer);
      const recovering = !ready;
      ready = true; attempts = 0;
      if (recovering) { notifyConnection("connected"); refreshSessions(connection); }
      // Health checks contain no editor text and never rerun analysis or replay edits.
      healthTimer = setTimeout(() => probe(), 5000);
      return;
    }
    if (message.kind === "status" && message.action === "policyChanged") { refreshSessions(connection); return; }
    const entry = sessions.get(message.session);
    if (!entry) return;
    if (message.version === 1 && message.kind === "configuration" && typeof message.pageEnabled === "boolean") {
      void updateToolbar(entry, message);
    }
    if (entry.control && entry.syncPage && message.kind === "configuration" && typeof message.pageEnabled === "boolean") {
      entry.syncPage = false;
      syncPage(entry.tabID).catch(() => {});
    }
    if (["replace", "request"].includes(message.kind)) {
      const tab = await extensionAPI.tabs.get(entry.tabID).catch(() => null);
      const window = tab && await extensionAPI.windows.get(tab.windowId).catch(() => null);
      if (!tab?.active || !window?.focused) {
        if (message.kind === "replace" && native === connection && sessions.get(message.session) === entry) {
          try { entry.port.postMessage({ version: 1, kind: "status", session: message.session, action: "editFailed", status: "Return to this editor and try again. Nothing was changed." }); } catch {}
        }
        return;
      }
      try { if (address(tab.url).pageURL !== entry.pageURL) return; } catch { return; }
    }
    if (native !== connection || sessions.get(message.session) !== entry) return;
    try { entry.port.postMessage(message); } catch { sessions.delete(message.session); }
  });
  function disconnect(error) {
    clearTimeout(healthTimer);
    if (native !== connection) return;
    native = undefined; ready = false;
    for (const tabID of toolbarStates.keys()) setToolbar(tabID, "Mac app unavailable");
    notifyConnection("disconnected", connectionError(error));
    // Brief app restarts recover automatically. Missing registration needs setup, not endless retries.
    if (clients.size && attempts < 3 && !/not found|forbidden|not registered/i.test(error)) {
      retryTimer = setTimeout(() => connectNative(), 500 * 2 ** attempts++);
    }
  }
  connection.onDisconnect.addListener(() => disconnect(extensionAPI.runtime.lastError?.message ?? ""));
  probe(launch);
  return connection;
}

extensionAPI.runtime.onConnect.addListener((port) => {
  const sender = port.sender;
  const control = port.name === "textwarden-popup" && sender?.id === extensionAPI.runtime.id && !sender.tab && sender.url === extensionAPI.runtime.getURL("popup.html");
  if (!control && (port.name !== "textwarden-editor" || !sender?.tab?.id || sender.tab.incognito || sender.frameId !== 0)) { port.disconnect(); return; }
  let origin;
  if (!control) {
    try { const url = new URL(sender.url); if (!["https:", "http:"].includes(url.protocol)) throw new Error(); origin = url.origin; }
    catch { port.disconnect(); return; }
  }
  clients.add(port);
  port.onMessage.addListener(async (message) => {
    if (message.version !== 1 || typeof message.session !== "string" || !/^[a-f\d-]{36}$/i.test(message.session) || message.session === handshake) return;
    const owner = sessions.get(message.session);
    if (owner && owner.port !== port) return;
    if (control) {
      if (message.kind !== "configuration" || !configurationActions.has(message.action)) return;
      const tab = await extensionAPI.tabs.get(message.tabID).catch(() => null);
      if (!clients.has(port) || !tab?.active) return;
      let site, pageURL;
      try { if (!tab.incognito) ({ origin: site, pageURL } = address(tab.url)); } catch {}
      if (["pauseSite", "resumeSite", "pausePageRule", "resumePage"].includes(message.action) && !site) return;
      const configuration = { version: 1, kind: "configuration", session: message.session, action: message.action === "connect" ? "status" : message.action, pause: message.pause };
      const entry = { port, control: true, tabID: tab.id, origin: site, pageURL, configuration, syncPage: message.action !== "status" };
      sessions.set(message.session, entry);
      if (message.action === "connect" && !ready) { attempts = 0; const old = native; native = undefined; old?.disconnect(); }
      if (site && message.action === "connect") syncPage(tab.id).catch(() => {});
      connectNative(message.action === "connect");
      if (ready) {
        native.postMessage({ ...configuration, origin: site, pageURL });
        entry.configuration = { ...configuration, action: "status", pause: undefined };
      }
      return;
    }
    if (!["pageStatus", "snapshot", "invalidate", "show", "hoverEnd", "hoverKeep", "applied", "release", "compose", "rewrite", "readability", "selection", "focus", "blur", "pausePage"].includes(message.kind)) return;
    if (message.text !== undefined && (typeof message.text !== "string" || message.text.length > 20000)) return;
    const tab = await extensionAPI.tabs.get(sender.tab.id).catch(() => null);
    if (!clients.has(port) || !tab || (message.kind !== "release" && message.kind !== "blur" && !tab.active)) return;
    let current;
    try { current = address(tab.url); if (current.origin !== origin) return; } catch { return; }
    const existing = sessions.get(message.session);
    if (existing && existing.port !== port) return;
    // Focus and selection messages must not invalidate replies awaiting a window check.
    // A new page or disconnected editor still gets a new identity.
    if (!existing || existing.pageURL !== current.pageURL) sessions.set(message.session, { port, tabID: sender.tab.id, ...current });
    connectNative();
    if (ready) native.postMessage(message.kind === "pageStatus"
      ? { version: 1, kind: "configuration", session: message.session, action: "status", ...current }
      : { ...message, ...current });
    if (message.kind === "release") sessions.delete(message.session);
  });
  port.onDisconnect.addListener(() => {
    // Chrome closes editor ports when a document enters its back/forward cache.
    void extensionAPI.runtime.lastError;
    clients.delete(port);
    for (const [session, entry] of sessions) {
      if (entry.port !== port) continue;
      if (!entry.control && ready) { try { native?.postMessage({ version: 1, kind: "release", session }); } catch {} }
      sessions.delete(session);
    }
    if (!clients.size) {
      clearTimeout(retryTimer); retryTimer = null; attempts = 0;
      const old = native; native = undefined; ready = false; old?.disconnect();
    }
  });
});

extensionAPI.tabs.onUpdated.addListener((tabId, change) => {
  if (change.status === "loading" || change.url) {
    toolbarStates.delete(tabId);
    setToolbar(tabId);
  }
  if (change.status === "loading") extensionAPI.action.setBadgeText({ tabId, text: "" }).catch(() => {});
  if (change.status === "complete" || change.url) {
    // activeTab grants only the user-authorized origin. Injection fails closed on other sites.
    syncPage(tabId).catch(() => {});
  }
});
extensionAPI.tabs.onRemoved.addListener(tabId => toolbarStates.delete(tabId));

extensionAPI.runtime.onMessage.addListener((message, sender, respond) => {
  const page = sender.id === extensionAPI.runtime.id && sender.tab?.id && !sender.tab.incognito && sender.frameId === 0;
  if (message.target !== "textwarden-background") return;
  if (message.action === "health" && page) {
    const entry = sessions.get(message.session);
    respond({ known: entry?.tabID === sender.tab.id && !entry.control, ready });
    return;
  }
  if (message.action === "menu" && page) {
    extensionAPI.tabs.get(sender.tab.id).then((tab) => {
      if (tab.active) return extensionAPI.action.openPopup({ windowId: tab.windowId });
    }).then(() => respond({ ok: true })).catch(() => respond({ error: "Open TextWarden from your browser\u2019s toolbar." }));
    return true;
  }
});
