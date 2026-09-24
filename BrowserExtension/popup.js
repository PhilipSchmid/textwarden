const extensionAPI = globalThis.browser ?? chrome;
const $ = (id) => document.getElementById(id);
let tab, origin, native, configuration, page = { enabled: false, pageUnderlines: true }, pending;
let connectionState = "connecting", connectionDetail = "Connecting to the TextWarden app on this Mac…";
const session = crypto.randomUUID();

function render() {
  const supported = Boolean(origin), connected = Boolean(configuration);
  const pageEnabled = configuration?.pageEnabled ?? page.enabled;
  $("enabled").disabled = !supported || !connected || configuration?.siteEnabled === false;
  $("enabled").checked = pageEnabled;
  $("underlines").disabled = !supported || !connected || !pageEnabled;
  $("underlines").checked = page.pageUnderlines;
  const sitePaused = configuration?.siteEnabled === false, siteInherited = Boolean(configuration?.siteInherited);
  $("websiteLabel").textContent = sitePaused ? "Website paused" : "Pause this website";
  $("website").hidden = !sitePaused || siteInherited;
  $("website").disabled = !supported || !connected || siteInherited;
  $("sitePauseMenu").hidden = !supported || !connected || sitePaused || siteInherited;
  for (const button of document.querySelectorAll("[data-pause]")) button.disabled = $("sitePauseMenu").hidden;
  $("siteScope").textContent = sitePaused && configuration.sitePausedUntil
    ? `Paused until ${new Date(configuration.sitePausedUntil * 1000).toLocaleString([], { weekday: "short", hour: "numeric", minute: "2-digit" })}`
    : sitePaused ? "Paused until resumed"
    : origin ? `All pages on ${new URL(origin).host}` : "All pages on this website";
  $("siteScope").title = $("siteScope").textContent;
  $("websiteRules").hidden = !configuration?.siteInherited;
  $("settings").disabled = !connected;
  const browserName = ({ "com.google.Chrome": "Google Chrome", "com.brave.Browser": "Brave", "org.mozilla.firefox": "Firefox", "app.zen-browser.zen": "Zen", "com.apple.Safari": "Safari" })[configuration?.browserBundleID] ?? "this browser";
  const paused = configuration?.appPaused || configuration?.globalPaused;
  $("pauseNotice").hidden = !paused;
  $("pauseText").textContent = configuration?.globalPaused ? "Grammar checking is paused for all applications." : `TextWarden is paused in ${browserName}.`;
  $("resume").textContent = configuration?.globalPaused ? "Open TextWarden settings…" : `Resume in ${browserName}`;
  $("connection").dataset.state = connected ? "connected" : connectionState;
  $("connection").textContent = connected ? "Connected to Mac app" : connectionState === "connecting" ? "Connecting to Mac app…" : "Mac app unavailable";
  $("reconnect").hidden = connected || connectionState === "connecting" || !native;
  $("status").textContent = !connected ? connectionDetail
    : !supported ? "This page does not allow TextWarden. Open a regular web page to use writing tools."
    : !configuration.siteEnabled ? "Checking is paused for this website."
    : paused ? ""
    : !pageEnabled ? "Checking is paused for this page."
    : "";
  $("status").hidden = !$("status").textContent;
  $("rewrite").disabled = !pageEnabled || !page.hasEditor || !page.hasSelection || !connected || paused || !configuration.siteEnabled;
  $("rewrite").hidden = $("rewrite").disabled;
  document.documentElement.dataset.theme = configuration?.theme ?? "System";
}

function fail(message) { $("error").textContent = message; $("error").hidden = false; }
function unavailable(detail) {
  clearTimeout(pending);
  pending = null; configuration = null; connectionState = "disconnected"; connectionDetail = detail;
  render();
}
async function pageCommand(action, extra = {}) {
  return extensionAPI.tabs.sendMessage(tab.id, { target: "textwarden-page", action, ...extra }, { frameId: 0 });
}
function configure(action, pause) {
  if (!native) return;
  if (action === "connect") { connectionState = "connecting"; connectionDetail = "Connecting to the TextWarden app on this Mac…"; render(); }
  // Bound configuration requests even if the helper connects but the app stalls.
  if (!pending) pending = setTimeout(() => unavailable("TextWarden is not responding. Writing tools are unavailable. Open the app and try again."), 8000);
  try { native.postMessage({ version: 1, kind: "configuration", session, action, ...(pause ? { pause } : {}), tabID: tab.id, ...(origin ? { origin } : {}) }); }
  catch { unavailable("The extension was updated. Close and reopen this menu."); }
}

extensionAPI.runtime.onMessage.addListener((message, sender) => {
  if (sender.id !== extensionAPI.runtime.id || sender.tab?.id !== tab?.id || sender.frameId !== 0 || message.target !== "textwarden-popup") return;
  if (!message.page || typeof message.page !== "object") return;
  page = message.page; render();
});

$("version").textContent = `v${extensionAPI.runtime.getManifest().version_name ?? extensionAPI.runtime.getManifest().version}`;
$("reconnect").addEventListener("click", () => { $("error").hidden = true; configure("connect"); });
$("enabled").addEventListener("change", () => configure($("enabled").checked ? "resumePage" : "pausePageRule"));
$("underlines").addEventListener("change", async () => {
  try { page = await pageCommand("underlines", { value: $("underlines").checked }); }
  catch { fail("Reload this page to reconnect TextWarden."); }
  render();
});
$("website").addEventListener("click", () => configure("resumeSite"));
for (const button of document.querySelectorAll("[data-pause]")) button.addEventListener("click", () => {
  $("sitePauseMenu").hidden = true;
  configure("pauseSite", button.dataset.pause);
});
$("websiteRules").addEventListener("click", () => configure("websites"));
$("resume").addEventListener("click", () => configure(configuration?.globalPaused ? "settings" : "resumeBrowser"));
$("settings").addEventListener("click", () => configure("settings"));
$("rewrite").addEventListener("click", async () => {
  try {
    const result = await pageCommand("tool", { tool: "rewrite" });
    if (!result?.queued) throw new Error();
    window.close();
  } catch { fail("Return to the text field and select text, then try again."); }
});

(async () => {
  [tab] = await extensionAPI.tabs.query({ active: true, currentWindow: true });
  try {
    const url = new URL(tab?.url);
    if (!tab.incognito && ["http:", "https:"].includes(url.protocol)) origin = url.origin;
  } catch {}
  $("site").textContent = origin ? new URL(origin).host : "Unavailable on this page";
  $("pagePath").hidden = !origin;
  $("pagePath").textContent = origin ? new URL(tab.url).pathname : "";
  $("site").title = $("site").textContent;
  $("pagePath").title = $("pagePath").textContent;
  $("siteScope").textContent = origin ? `All pages on ${new URL(origin).host}` : "All pages on this website";
  if (origin) page = (await pageCommand("status").catch(() => null)) ?? page;
  render();
  native = extensionAPI.runtime.connect({ name: "textwarden-popup" });
  native.onMessage.addListener((message) => {
    if (message.version !== 1) return;
    if (message.kind === "connection") {
      if (message.status !== "connected") {
        unavailable(message.detail);
        connectionState = message.status === "connecting" ? "connecting" : "disconnected";
        render();
      }
      return;
    }
    if (message.kind !== "configuration" || message.session !== session) return;
    clearTimeout(pending); pending = null;
    configuration = message; connectionState = "connected"; $("error").hidden = true; render();
    const manifest = extensionAPI.runtime.getManifest();
    const version = manifest.version_name ?? manifest.version;
    const matches = message.appVersion && message.appBuild
      && manifest.version === `${message.appVersion.split("-")[0]}.${message.appBuild}`
      && (!manifest.version_name || message.appVersion === version);
    if (matches) $("version").textContent = `v${message.appVersion}`;
    else if (message.appVersion) fail(`Extension ${manifest.version} · Mac app ${message.appVersion} (build ${message.appBuild ?? "unknown"}). Install both from the same release.`);
  });
  native.onDisconnect.addListener(() => {
    void extensionAPI.runtime.lastError;
    native = null;
    unavailable("The extension was updated. Close and reopen this menu.");
    $("reconnect").hidden = true;
  });
  configure("connect");
})().catch(() => unavailable("The extension could not connect. Close and reopen this menu on a regular web page."));
