# TextWarden Browser Extension (Preview)

This development preview connects Chrome, Brave, Firefox, Zen, and Safari editors to the local TextWarden app. Open its toolbar menu to enable the preview for the current origin. It uses temporary `activeTab` access, not persistent access to every website. Navigating to another origin (including a different port) requires another toolbar click; returning through browser history can require it too. Saved page rules do not grant browser access. Password fields and incognito tabs are excluded.

## Install locally

1. Use a preview-enabled TextWarden build, or run `make run` to build and install it from source, including its native messaging helper and preview extension.
2. Open **Settings → Browser** and expand **Install Extension** for your browser. Chrome and Brave use **Load unpacked** with Developer mode enabled. Firefox and Zen use **Load Temporary Add-on** in `about:debugging`; choose the extension manifest. Safari uses its Extensions settings to enable the extension embedded in TextWarden. TextWarden configures the local connection automatically.
3. Open a web page, click **TextWarden Browser Extension (Preview)** in your browser’s extensions menu, leave **Check this page** enabled, and focus an editor. The menu offers **Resume in your browser** when checking is paused.

Chrome/Brave use [unpacked installation](https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world#load-unpacked); Firefox/Zen use [temporary installation](https://extensionworkshop.com/documentation/develop/temporary-installation-in-firefox/). Safari’s signed, notarized app needs no Developer mode. For unsigned development builds, follow [Apple’s development setup](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension); Safari ignores unsigned extensions by default.

In Zen, open the settings icon at the right of the address bar, then click the TextWarden feather under **Extensions**.

Settings reveals the matching bundled files: `BrowserExtension` for Chrome/Brave and `BrowserExtension-Firefox` for Firefox/Zen. Developers can also load this repository’s shared `BrowserExtension` directory, but browser-specific manifest warnings are expected there. The manifest’s public key keeps the preview ID identical across folders and builds. TextWarden registers that exact ID at startup and refreshes the helper path after app updates. Settings confirms a live connection; it cannot determine whether an idle extension is installed. Older previews without the fixed ID must be removed and loaded again once.

Grammar uses TextWarden's existing settings and dictionary. AI Compose and Rewrite require macOS 26 or later, Apple Intelligence, and Style checking enabled. Readability uses the configured target audience. Native messaging stays on this Mac; no HTTP grammar service is exposed.

## Page controls

The toolbar popup shows the current website, connection state, and available writing tools. **Check this page** saves a rule for the exact scheme, host, non-default port, and case-sensitive path. Query strings and fragments are ignored and never stored. The rule survives reloads and app restarts. **Show underlines** affects only the current document. Pausing an enabled page also suppresses the native browser fallback until that page is resumed or closed. **Pause site** offers one hour, 24 hours, or until resumed and saves an origin rule covering every path on that scheme, host, and port. Existing domain and wildcard rules still cover all ports and schemes as before. A wildcard rule links to Website settings instead of silently enabling other sites.

The indicator uses the native pill dimensions, animated orientation changes, and the same inward-fading placement guide during dragging. Its three sections are: Grammar, Style & Clarity, and Compose. Hovering or clicking Style & Clarity requests on-device suggestions for the current editor and reuses the result until the text changes. Hovering an underlined word highlights it and opens the native suggestion popover with TextWarden’s configured hover delay. Drag the pill to a viewport edge; top and bottom positions are horizontal. Position lasts for the current document. Right-click opens the same toolbar popup. Global and per-browser pause controls stay in the macOS app; a paused popup explains the state and offers a recovery action. The separate Readability button is removed from the browser menu as well. Native readability functionality remains available through TextWarden’s existing commands. Quick Rewrite remains available in the toolbar menu and through its keyboard shortcut.

## Scope

The preview handles textareas, spellcheck-enabled text inputs, and basic `contenteditable` editors. It renders browser underlines and opens TextWarden's native writing windows. Replacements verify the source text and preserve the browser's undo stack. The app waits for the browser’s acknowledgement and updated analysis before advancing the existing suggestion popover; it does not hide and recreate it between corrections. AI edits also verify the original selection.

Editors can cancel replacements through `beforeinput`; TextWarden rechecks the text and selection after that event. Underlines respect the global toggle, the browser's per-app override, thickness, and error-count threshold. The **Suggestions** button remains available when underlines are hidden.

Google Docs, editor frameworks such as ProseMirror/Quill/Lexical, cross-origin frames, and shadow-root editors need separate adapters and are not supported by this preview. Other fields continue to use TextWarden's existing macOS integration. All five browsers share the editor implementation. Safari uses its embedded app extension for native messages; Firefox and Zen use a background script instead of a Chromium service worker. These are development previews. Standard-editor correction, Undo, native writing tools, and website pause/resume have been exercised locally in all five browsers on macOS 27. This does not establish compatibility with every website or older macOS releases. Store listings and permanent Mozilla signing remain pending.

## Connection and releases

One native connection serves the popup and editors. Opening the toolbar menu starts the registered TextWarden app when needed. Brief app restarts retry automatically and request fresh editor snapshots; old text and edits are not replayed. Launching TextWarden repairs missing or outdated registration automatically. If that fails, **Settings → Browser** offers **Try Again**. Background retries do not relaunch an app the user has quit. A five-second, text-free health probe detects a stalled app after an eight-second response deadline. Disconnection disables writing actions and clears stale grammar and AI indicators. If recovery times out, use **Open TextWarden & reconnect**.

`Info.plist` is the version source. Builds derive numeric `major.minor.patch.build` versions; the popup displays the matching Mac app’s exact version.

Use the bundled folder with Chrome's **Load unpacked**, then open TextWarden. No extension ID or pairing step is required. This is still a developer-mode preview, not a one-click installation. Normal Chrome/Brave distribution requires the Chrome Web Store. Permanent Firefox/Zen installation requires a Mozilla-signed XPI; an unlisted signed XPI can be distributed on GitHub. The unsigned ZIP is a signing input, not a production installer. Safari travels with the signed and notarized Mac app and still requires enabling in Safari. No store listing or Mozilla signature is included in this preview. Chrome does not automatically reload unpacked extensions after an app update: click **Reload** in `chrome://extensions`, then reload affected web pages. The toolbar menu reports mismatched app and extension versions.

### Future Firefox and Zen signing

For permanent installation, submit the Firefox `-unsigned.zip` from the release to [Mozilla’s Developer Hub](https://addons.mozilla.org/developers/addon/submit/distribution), choose self-distribution, and download the signed XPI after validation. This uses Mozilla’s browser sign-in; no signing credentials need to be stored in this repository. Install the returned XPI in Firefox and Zen to verify Mozilla accepts its signature before attaching it to the matching GitHub release. Keep the manifest ID and version unchanged. [Mozilla’s signing guide](https://extensionworkshop.com/documentation/publish/signing-and-distribution-overview/) covers the review and signing process.

Self-distributed updates need an HTTPS update manifest; this preview does not configure one. Until that is added, users must install each newly signed XPI themselves. Chrome/Brave unpacked previews likewise require manual reloads after updates. Safari updates with the Mac app.

## Security and privacy boundary

The browser launches the bundled helper through Native Messaging with an exact extension-origin allowlist. The helper uses an owner-only Unix socket (`0700` directory, `0600` socket); both endpoints verify the peer user and Apple code signature against TextWarden’s signing team and expected executable identifiers. The helper also verifies its launching browser’s vendor signature. Safari uses a private app-group socket and returns messages only to the requesting extension context. There is no network listener. Editor text is held in memory for local analysis, and released when its session ends. URL queries and fragments are stripped; page rules retain the scheme, host, port, and path, which can still contain sensitive identifiers.

The worker validates browser-supplied tab identity and session ownership. Replacements require the active page, matching revision and source text. Messages are bounded to 1 MiB; editor text is limited to 20,000 UTF-16 units. Password and revealed-password fields, one-time codes, PINs, credential-labelled fields, payment autocomplete fields, and explicitly private or spellcheck-disabled editors are excluded before reading text or selection. Eligibility is checked again before sending text or applying a correction, and a field becoming sensitive releases its session. Private tabs and privileged browser pages are also excluded. Ordinary editable fields can still contain sensitive text; users should pause those pages or sites.

These checks reject unrelated same-user clients but do not protect a compromised browser or operating system. The unpacked preview's public extension key identifies it but does not authenticate its publisher; store distribution and signed app releases are separate supply-chain protections.

## Check changes

Run `make test-browser` with Node.js and Python 3 installed. For manual checks:

```sh
python3 -m http.server 8766 --bind 127.0.0.1 --directory BrowserExtension/tests
```

Open `http://127.0.0.1:8766/editors.html`, enable the preview, and exercise corrections, undo, Unicode, rich-text formatting, scrolling, empty editors, and rejected edits. Check the page switch, whole-site pause, native settings link, selected-text tools, quick-close activation, and a narrow browser window. Use the fixture’s navigation buttons to verify paused paths without reloading, and browser Back to check restored documents. After applying a correction, move directly onto another underline: its native popover should open on the first movement without flickering. Reload the extension and then the fixture page after changing its JavaScript.

To stop using the preview, remove it from `chrome://extensions`. TextWarden’s local registration grants access only to its fixed extension ID and is maintained while the app is installed.

The manifest key is public identification material, not a secret or a signature. Keep it stable across preview releases. When creating the Chrome Web Store listing, align the bundled key and native registration with the store-assigned public key before publishing.

Brave uses the same preview files as Chrome. Open `brave://extensions` to load or reload them. TextWarden registers each browser automatically and keeps their connection status, application pauses, and editor ownership separate.
