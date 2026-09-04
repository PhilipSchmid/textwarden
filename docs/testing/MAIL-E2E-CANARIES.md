# Apple Mail live E2E canaries

These scenarios exercise TextWarden against a real Apple Mail compose window using the shared [macOS E2E workflow](README.md). They are intentionally safe to run on a dedicated macOS test account: never add a recipient, never press Return in a field that can submit, and never click Send.

## Enable the state oracle

The oracle is dormant unless the environment flag is present when TextWarden launches. It writes text-free, deduplicated JSON state to the current user's private temporary directory.

```bash
make build
make install
make kill
open --env TEXTWARDEN_E2E_STATE=1 /Applications/TextWarden.app

python3 Scripts/e2e-state.py check
python3 Scripts/e2e-state.py show
```

When testing is complete, quit the E2E-launched instance and start TextWarden normally:

```bash
make run-only
```

The snapshot includes application and AX element identity, text length, error ranges and categories, presentation visibility, geometry status, replacement state, runtime health, and recent AX/overlay events. `grammarUnderlineHitPoints` contains global Quartz, top-left-origin coordinates that can be passed directly to `CGEvent` for deterministic pointer tests. It never includes captured text, lint IDs, error messages, suggested replacements, clipboard contents, or account data.

Always correlate three observations:

1. Mail's Accessibility tree and focused element.
2. `textwarden-e2e-state.json`.
3. A full-display screenshot that includes both Mail and TextWarden-owned windows.

Before running any canary, validate the driver itself: a coordinate click in Mail must change `activeApplication.bundleIdentifier` to `com.apple.mail` and produce the expected focused Mail element. Stop the run if only Mail's AX-focused element changes. That interaction did not follow the same frontmost-application path as a physical user click and cannot validate TextWarden's activation behavior.

Pointer preflight is separate. A click or move over a reported underline hit point must first advance `lastPointerEventAt` with `lastPointerEvent` set to `leftMouseDown` or `mouseMoved`, then change `suggestionPopoverVisible`, `suggestionPopoverRange`, or `overlayAlpha`. If the host app receives the click but the pointer event does not advance, the driver bypassed the global `NSEvent` path and cannot validate hover, click-to-open, native-popover, or pointer-fade behavior. The current Codex Computer Use backend can drive app-level AX focus and text changes, but its app-targeted pointer actions do not satisfy this preflight; use a driver that emits globally observable pointer events for MAIL-03 through MAIL-05.

## Fixture

- Use a new unsent draft with no recipients.
- Subject: `Testing wrong writting`
- Body: `This are a definitly bad sentnce with the wrong worrds. Flarble, test.`
- Keep the draft local throughout the run.
- Record the TextWarden commit, macOS build, Mail version, display scale, and enabled Apple Writing Tools settings.

## Scenarios

| ID | Actions | Required observations |
|---|---|---|
| MAIL-01 | Activate another app, then coordinate-click the Mail body. | Mail becomes frontmost; the body AX element and TextWarden `monitoredElement` are present; analysis generation advances; body errors, indicator, and underlines appear after settling. |
| MAIL-02 | Coordinate-click the subject, wait for analysis, then coordinate-click the body. | Monitored element identity changes twice; subject presentation is cleared before body presentation appears; body error count and ranges replace the subject state. |
| MAIL-03 | Apply a TextWarden correction in the subject, then coordinate-click the body. | Replacement timestamps advance; the corrected subject error and popover disappear; the body is reacquired after Mail's focus bounce; no subject underline remains over the body. |
| MAIL-04 | Apply a TextWarden correction in the body. | Mail text changes exactly once; replacement grace begins and ends; analysis generation advances; the corrected range, locked highlight, and suggestion popover disappear while unrelated errors remain. |
| MAIL-05 | Open Apple's native spelling suggestion for an invalid word, then dismiss it. | TextWarden does not cover the native popover; its state records the native-popover transition when detectable; underlines and indicator recover after dismissal without changing Mail text. |
| MAIL-06 | Scroll the body until one error leaves the visible area, then scroll back. | Overlay hides or recalculates according to Mail behavior; off-screen ranges are not drawn; visible underlines and the indicator recover after scrolling settles. |
| MAIL-07 | Resize and move the compose window, then minimize and restore it. | Overlay frame follows the visible editor; no underline is drawn outside Mail; hidden state does not leave a stale popover; presentation recovers after restore. |
| MAIL-08 | Open two recipient-free compose windows and alternate between their subject and body fields. | Active Mail PID may remain unchanged, but the host focused element and TextWarden monitored identity follow the selected window; errors never cross between drafts. |
| MAIL-09 | Add an invalid word after an emoji and apply its correction. | Error ranges remain aligned in UTF-16; geometry confidence stays usable; only the selected range changes and formatting is preserved. |
| MAIL-10 | Focus To, Cc, the message list, and a read-only message before returning to the draft body. | Non-composition fields are never analyzed; overlays and popovers clear outside the composer; the original body is reacquired and reanalyzed on return. |

MAIL-05 and pointer-fade assertions require a driver capable of controlled pointer movement. Do not replace them with direct AX value mutation because that bypasses the user event sequence being tested.

## TextEdit baseline

Use a disposable document and verify that TextWarden reports `Full support`, an `AXTextArea`, `RangeBounds` geometry, and matching analysis/underline/indicator counts. If TextEdit is paused in the user's preferences, restore that preference after the test.

1. Type `This are a definitly bad sentnce with wrong worrds zqxvtestt` without saving.
2. Wait until the snapshot segment length is `60`; require four spelling ranges, four underlines, and indicator count `4`.
3. Append and remove ` badspelll` ten times; after every edit, poll until the segment length and all three counts agree.
4. Alternate activation between TextEdit and the recipient-free Mail draft five times; require the app, monitored role, segment length, findings, underlines, and indicator to converge after every switch.
5. Clear the document and require zero findings, zero underlines, and a hidden indicator before closing it without retaining test text.

The live baseline on 2026-09-04 converged in about 0.5–0.6 seconds per TextEdit edit and 0.3–0.5 seconds after each Mail field or application transition. Treat those as observations, not hard-coded timing assertions; poll the state oracle with a bounded timeout.

## Pass criteria

A scenario passes only when all three observation channels agree. Screenshot appearance alone is not sufficient.

- The expected app and editor are focused.
- The host AX value contains the expected local fixture text.
- TextWarden monitors the same editor and completes a newer analysis generation.
- Error ranges and displayed counts match the fixture.
- Every visible underline lies within the compose field.
- Indicator and popover visibility match the interaction.
- Applied corrections preserve surrounding text, formatting, selection, and clipboard contents.
- Old underlines, locked highlights, and popovers disappear after focus or text changes.
- No recipient is added and no message is sent.

Run each canary 20 consecutive times before treating a timing-sensitive fix as stable. On failure, preserve the action sequence, host AX state, TextWarden snapshot, full-display screenshot, and relevant log interval.
