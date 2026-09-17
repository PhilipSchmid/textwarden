# TextWarden Browser Extension (Preview)

Adds browser underlines and TextWarden’s native writing tools to Chrome, Brave, Firefox, Zen, and Safari. Grammar and AI processing stay in the Mac app.

## Install

Use a preview-enabled TextWarden build, or build from source with `make run`. Open Settings → Browser → Install Extension to find the bundled files or Safari settings. The local connection is configured automatically.

| Browser | Installation | Updates |
| --- | --- | --- |
| Chrome / Brave | Enable Developer mode in `chrome://extensions` or `brave://extensions`, then Load unpacked from the revealed folder. | Reload the extension and affected pages after an update. |
| Firefox / Zen | Load Temporary Add-on in `about:debugging`; select the revealed `manifest.json`. | Load it again after each browser restart. |
| Safari | Enable TextWarden in Safari → Settings → Extensions. | Updates with the Mac app. |

Signed, notarized Safari builds need no Developer mode. Unsigned builds require [Apple’s development setup](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension). The preview has no store listings or permanent Mozilla signature.

## Use

Click the toolbar feather on a page, then focus an editor. Access uses temporary `activeTab` permission: a different origin, including a different port, needs another click. Returning through browser history may also require one. Saved rules do not grant browser access.

- Check this page saves a rule for its scheme, host, port, and case-sensitive path. Queries and fragments are ignored.
- Pause site covers every path on that origin, for one hour, 24 hours, or until resumed.
- Show underlines applies to the current document. Global and per-browser pauses remain in the Mac app.

Text fields and simple rich-text editors support corrections and Undo. Google Docs, ProseMirror, Quill, Lexical, cross-origin frames, and shadow-root editors are not supported yet. AI Compose and Rewrite require macOS 26+, Apple Intelligence, and Style checking enabled.

Opening the toolbar starts TextWarden when needed. A lost connection clears stale indicators and disables writing actions; recovery requests fresh text rather than replaying old edits. Use Open TextWarden & reconnect if automatic recovery fails. Settings → Browser also offers Try Again to repair registration.

## Security and privacy

- No network listener. Chrome, Brave, Firefox, and Zen use Native Messaging with an exact extension allowlist, then an owner-only Unix socket (`0700` directory, `0600` socket). The app and helper verify the peer user and code signature; the helper also verifies the launching browser. Safari uses a private app-group socket and replies only to the requesting extension context.
- Passwords, revealed-password fields, one-time codes, PINs, credential-labelled fields, payment autocomplete fields, and private or spellcheck-disabled editors are excluded before reading. Private tabs and privileged browser pages are excluded too. Eligibility is rechecked before sending text or applying edits.
- Corrections require the active page, matching session, revision, and source text. Messages are capped at 1 MiB and editors at 20,000 UTF-16 units. Text stays in memory and is released when the session ends.

Ordinary fields can still contain sensitive writing; pause those pages or sites. Saved page paths can contain sensitive identifiers even though queries and fragments are discarded. These protections do not cover a compromised browser or operating system. The preview’s public manifest key fixes its identity; it does not authenticate its publisher.

## Development and distribution

Run `make test-browser` for automated checks. Serve the editor fixtures with:

```sh
python3 -m http.server 8766 --bind 127.0.0.1 --directory BrowserExtension/tests
```

Open `http://127.0.0.1:8766/editors.html`. Reload the extension and page after JavaScript changes.

`Info.plist` supplies the version. `make release` packages the Chromium preview ZIP and Firefox `-unsigned.zip`; Safari is embedded in the app. `make release-upload` verifies the ZIPs against the release tag before uploading them with the DMG.

Chrome/Brave store distribution requires the Chrome Web Store. Permanent Firefox/Zen installation requires a [Mozilla-signed XPI](https://extensionworkshop.com/documentation/publish/signing-and-distribution-overview/); unlisted signing allows GitHub distribution. The unsigned ZIP is signing input, not an installer. No self-distributed update manifest is configured, so signed XPI updates would remain manual. Keep extension IDs stable when preparing store or signed releases.

See [BUILD.md](../BUILD.md) for build prerequisites and [ARCHITECTURE.md](../ARCHITECTURE.md) for the app integration.
