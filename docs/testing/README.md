# macOS live end-to-end testing

TextWarden's live canaries combine a real host application with a small, text-free state oracle. They test behavior that unit tests cannot reproduce reliably: macOS focus changes, Accessibility notifications, range geometry, global pointer events, scrolling, app activation, and correction insertion.

## Test layers

1. **Host application:** use macOS Computer Use when available, plus the checked-in native driver for guarded input, to create a disposable local document or unsent self-draft, type a known fixture, inspect the application's Accessibility tree, and capture only the minimum required part of the host window.
2. **TextWarden oracle:** launch TextWarden with `TEXTWARDEN_E2E_STATE=1`, then use `Scripts/e2e-state.py` to validate and poll its private JSON snapshot.
3. **Native input preflight:** pointer, wheel, and window-motion cases require globally observable macOS events. An app-targeted Accessibility action is not equivalent to physical input unless the snapshot records the expected pointer or overlay transition.

This is intentionally not a scenario framework. The host UI changes between application releases; keep app-specific navigation in Computer Use and promote only repeated, semantic operations to the dependency-free driver. One-off AX probes, screenshots, compiled binaries, and fixtures belong in `/private/tmp`, not the repository.

## Start and inspect a run

```bash
make build
make install
make kill
open --env TEXTWARDEN_E2E_STATE=1 /Applications/TextWarden.app

python3 Scripts/e2e-state.py check
python3 Scripts/e2e-state.py wait \
  --expect state.activeApplication.bundleIdentifier=com.apple.iWork.Pages \
  --expect state.monitoredElement.role=AXTextArea \
  --expect state.analysis.grammarErrors.length=4 \
  --expect state.presentation.grammarUnderlineCount=4 \
  --expect state.presentation.indicatorGrammarErrorCount=4
```

`make run` restarts TextWarden without `TEXTWARDEN_E2E_STATE`. After every rebuild, stop that instance and repeat the final `open --env` command before making oracle assertions.

The snapshot contains bundle identifiers, AX role and identity, UTF-16 lengths and ranges, counts, visibility, overlay and indicator frames in Quartz coordinates, geometry strategy, replacement timestamps, runtime health, and recent event names. It excludes captured text, messages, suggestions, lint identifiers, clipboard contents, and account data. `check` rejects unexpected permissions, ownership, schema, or text-bearing keys.

Poll for state convergence instead of sleeping for a fixed duration. Always compare the oracle with the current host AX value. An application-only screenshot cannot prove TextWarden's separate overlay windows; use the oracle or a full-display capture when visual confirmation is required.

## Driver preflights

- After an application switch, require both the host and `activeApplication.bundleIdentifier` to identify the target application. An AX-focused element alone does not prove a physical activation path.
- Before a hover or underline click assertion, move to a reported `grammarUnderlineHitPoints` coordinate and require `lastPointerEventAt` to advance. These are global Quartz coordinates.
- Before a scroll assertion, require a real viewport change and a new overlay transition. The current Computer Use app-targeted scroll moves Pages but does not enter TextWarden's global event monitor.
- Treat application activation, focused editor identity, analysis, visible underlines, indicator count, and popover state as separate assertions.

## Safe fixtures and cleanup

- Prefer a new local document. In communication apps, use only an explicitly verified self-chat or a recipientless/self-addressed draft. Never open another person or group conversation, and never invoke Send.
- Record and restore any preference changed for the run.
- Clear fixture text before closing. If an app cannot discard reversibly, save the cleared document under a unique path in `/private/tmp`, close it, then remove that exact path.
- Quit the opt-in TextWarden instance, remove the state file, and relaunch normally.
- Trace logs can contain test text. Restore the previous log settings and remove only logs created for the run.

## Live coverage

| Application | Validated behavior |
|---|---|
| TextEdit | Native `AXTextArea` baseline, analysis, underlines, correction, and window lifecycle. |
| Apple Mail | WebKit body, subject/body focus changes, native spelling UI, correction, and no-send cleanup. |
| Apple Messages | New-message recipient/body focus, self-addressed draft, correction, and no-send cleanup. |
| Apple Notes | Local note editing, analysis, underlines, correction, and cleanup. |
| Apple Reminders | Disposable reminder title, correction, and removal. |
| Apple Calendar | Disposable event title, correction, and removal. |
| Apple Pages | Native rich text, range geometry, correction, zoom, scrolling, and header/body focus. |
| Microsoft Word | Office document ranges, correction, formatting preservation, zoom, scrolling, and window geometry. |
| Chrome | Local `contenteditable` analysis, indicator presentation, correction, focus changes, and window lifecycle. |
| Safari | Local `contenteditable` analysis, underlines, correction, and cleanup. |
| Brave | Isolated local `contenteditable` analysis and cleanup. |
| Comet | Isolated-profile local `contenteditable` analysis and cleanup. |
| Notion | Block editing, sidebar hide/show, navigation, correction, scrolling, and window lifecycle. |
| Slack | Draft analysis, workspace switcher and sidebar changes, navigation, native popovers, correction, and no-send cleanup. |
| Microsoft Teams | Self-chat draft analysis, calibrated single-line positioning, correction, and no-send cleanup. |
| Microsoft Outlook | Subject/body focus, Editor pane resize, correction, move/resize, minimize/restore, and no-send cleanup. |
| Microsoft PowerPoint | Speaker Notes analysis, missing AX notification fallback, Notes hide/show, slide-canvas exclusion, correction, and minimize/restore. Slide text remains inaccessible through AX. |
| Telegram | Saved Messages navigation, native `AXTextArea` analysis, correction, and no-send cleanup. |
| WhatsApp | Visually verified Message Yourself draft, New Chat search-to-composer focus recovery, correction, and no-send cleanup. |
| Proton Mail | Recipientless rich-text body, structural-newline handling, correction, and draft cleanup. |
| Claude Desktop | Temporarily activated from its preserved pause state, unsent-prompt analysis, correction, cleanup, and exact preference restoration. |

Configured applications that were unavailable in this environment remain unvalidated: ChatGPT, Perplexity, Webex, Safari Technology Preview, Firefox, Edge, Opera, and Vivaldi. The installed `/Applications/ChatGPT.app` is Codex (`com.openai.codex`), not the configured ChatGPT application (`com.openai.chat`).

## Native macOS input driver

`Scripts/macos-e2e-driver.swift` provides the small native-input layer needed when an app-targeted AX action is not equivalent to user input:

```bash
xcrun swift Scripts/macos-e2e-driver.swift self-test
xcrun swift Scripts/macos-e2e-driver.swift editors BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift focused-element-state BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift check-editor BUNDLE_ID "exact value"
xcrun swift Scripts/macos-e2e-driver.swift check-editor-trimmed BUNDLE_ID "rich-text value"
xcrun swift Scripts/macos-e2e-driver.swift click-editor BUNDLE_ID X Y
xcrun swift Scripts/macos-e2e-driver.swift paste-app BUNDLE_ID "draft only"
xcrun swift Scripts/macos-e2e-driver.swift clear-editor BUNDLE_ID EXPECTED_UTF16_LENGTH
xcrun swift Scripts/macos-e2e-driver.swift press-self-chat BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift press-app BUNDLE_ID LABEL
xcrun swift Scripts/macos-e2e-driver.swift press-menu BUNDLE_ID LABEL
xcrun swift Scripts/macos-e2e-driver.swift shortcut-app BUNDLE_ID command-0
xcrun swift Scripts/macos-e2e-driver.swift window-state BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift window-set BUNDLE_ID X Y WIDTH HEIGHT
xcrun swift Scripts/macos-e2e-driver.swift window-minimize BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift window-restore BUNDLE_ID
```

The driver activates and verifies the target process, refuses text containing line breaks, preserves and restores the clipboard around paste input, checks exact UTF-16 lengths before clearing, rejects clicks outside the target application or on send-like controls, and consumes oracle-provided Quartz coordinates. `press-self-chat` accepts only explicit self markers such as `(You)`, `Saved Messages`, and `Message yourself`; if an app omits those AX labels, require a tightly cropped visual confirmation before a guarded coordinate click. Navigation shortcuts are deliberately whitelisted (`command-0` and `command-n`). Keep host-app orchestration in Computer Use and assertions in `Scripts/e2e-state.py`; add a scenario layer only if repeated tests prove these direct commands insufficient.

## Application canaries

- [Apple Mail](MAIL-E2E-CANARIES.md)
- [Apple Pages](PAGES-E2E-CANARIES.md)
