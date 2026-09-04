# macOS live end-to-end testing

TextWarden's live canaries combine a real host application with a small, text-free state oracle. They test behavior that unit tests cannot reproduce reliably: macOS focus changes, Accessibility notifications, range geometry, global pointer events, scrolling, app activation, and correction insertion.

## Test layers

1. **Host application:** use macOS Computer Use to create a disposable local document, type a known fixture, inspect the application's Accessibility tree, and capture the host window.
2. **TextWarden oracle:** launch TextWarden with `TEXTWARDEN_E2E_STATE=1`, then use `Scripts/e2e-state.py` to validate and poll its private JSON snapshot.
3. **Native input preflight:** pointer, wheel, and window-motion cases require globally observable macOS events. An app-targeted Accessibility action is not equivalent to physical input unless the snapshot records the expected pointer or overlay transition.

This is intentionally not a scenario framework. The host UI changes between application releases; keeping actions in Computer Use and assertions in one dependency-free command-line tool makes failures inspectable without maintaining a second UI abstraction.

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

The snapshot contains bundle identifiers, AX role and identity, UTF-16 lengths and ranges, counts, visibility, geometry strategy, replacement timestamps, runtime health, and recent event names. It excludes captured text, messages, suggestions, lint identifiers, clipboard contents, and account data. `check` rejects unexpected permissions, ownership, schema, or text-bearing keys.

Poll for state convergence instead of sleeping for a fixed duration. Always compare the oracle with the current host AX value. An application-only screenshot cannot prove TextWarden's separate overlay windows; use the oracle or a full-display capture when visual confirmation is required.

## Driver preflights

- After an application switch, require both the host and `activeApplication.bundleIdentifier` to identify the target application. An AX-focused element alone does not prove a physical activation path.
- Before a hover or underline click assertion, move to a reported `grammarUnderlineHitPoints` coordinate and require `lastPointerEventAt` to advance. These are global Quartz coordinates.
- Before a scroll assertion, require a real viewport change and a new overlay transition. The current Computer Use app-targeted scroll moves Pages but does not enter TextWarden's global event monitor.
- Treat application activation, focused editor identity, analysis, visible underlines, indicator count, and popover state as separate assertions.

## Safe fixtures and cleanup

- Prefer a new local document. For communication apps, leave all recipients empty and never invoke Send.
- Record and restore any preference changed for the run.
- Clear fixture text before closing. If an app cannot discard reversibly, save the cleared document under a unique path in `/private/tmp`, close it, then remove that exact path.
- Quit the opt-in TextWarden instance, remove the state file, and relaunch normally.
- Trace logs can contain test text. Restore the previous log settings and remove only logs created for the run.

## Coverage sequence

| Order | Application | Why it is next |
|---|---|---|
| Baseline | TextEdit | Simplest native `AXTextArea`; isolates the harness from app-specific behavior. |
| Completed | Apple Mail | WebKit compose body, subject/body focus bounces, native spelling UI, and send-sensitive cleanup. |
| Completed | Apple Pages | Native rich text, direct range bounds, focus-and-paste correction, zoom, multi-page scrolling, and header/body focus. |
| **Next** | Microsoft Word | Local unsaved document; exercises Office document ranges, focus-and-paste replacement, formatting preservation, zoom, scroll, and window geometry. |
| Then | Chrome with a local `contenteditable` fixture | Browser category behavior and indicator-only presentation without transmitting text. |
| Then | Notion | Electron block editors and intentionally partial underline coverage. Use a dedicated test page because edits may sync. |
| Then | Slack | Electron rich text, formatting exclusions, native popovers, and draft recovery. Use a dedicated workspace/channel and never send. |
| Then | Outlook and PowerPoint | Office/WebKit compose behavior and speaker-notes-only coverage after the Word driver is stable. |
| Later | Messages, Teams, Telegram, WhatsApp, Webex, Proton Mail | Communication-specific focus and stale-content cases require dedicated accounts and stronger no-send guards. |

## Next pull request: deterministic macOS input

Add one small test-only native driver, compiled on demand, rather than app-specific automation in production code. It should:

- activate an exact bundle identifier and verify its PID;
- emit global move, click, and wheel events;
- read, move, resize, minimize, and restore the focused AX window;
- capture the original frame and restore it even after a failed assertion;
- accept oracle-provided Quartz points instead of hard-coded screen offsets;
- refuse send controls and require a disposable document marker for destructive editor actions.

Use the driver first against the existing TextEdit, Mail, and Pages canaries. Do not add a scenario DSL, screenshot service, or app plug-in layer unless repeated tests show that the direct commands are insufficient.

## Application canaries

- [Apple Mail](MAIL-E2E-CANARIES.md)
- [Apple Pages](PAGES-E2E-CANARIES.md)
