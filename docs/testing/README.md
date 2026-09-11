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
| ChatGPT / Codex | Unsent-prompt analysis, one-line and wrapped geometry, emoji offsets, correction, focus changes, window movement and resizing, and minimize/restore. |

Configured applications that were unavailable in this environment remain unvalidated: Perplexity, Webex, Safari Technology Preview, Firefox, Edge, Opera, and Vivaldi.

## Native macOS input driver

`Scripts/macos-e2e-driver.swift` provides the small native-input layer needed when an app-targeted AX action is not equivalent to user input:

```bash
xcrun swift Scripts/macos-e2e-driver.swift self-test
xcrun swift Scripts/macos-e2e-driver.swift editors BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift focused-element-state BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift check-editor BUNDLE_ID "exact value"
xcrun swift Scripts/macos-e2e-driver.swift check-editor-trimmed BUNDLE_ID "rich-text value"
xcrun swift Scripts/macos-e2e-driver.swift focused-geometry BUNDLE_ID LOCATION LENGTH
xcrun swift Scripts/macos-e2e-driver.swift click-editor BUNDLE_ID X Y
xcrun swift Scripts/macos-e2e-driver.swift paste-app BUNDLE_ID "draft only"
xcrun swift Scripts/macos-e2e-driver.swift clear-editor BUNDLE_ID EXPECTED_UTF16_LENGTH
xcrun swift Scripts/macos-e2e-driver.swift press-self-chat BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift press-app BUNDLE_ID LABEL
xcrun swift Scripts/macos-e2e-driver.swift press-menu BUNDLE_ID LABEL
xcrun swift Scripts/macos-e2e-driver.swift shortcut-app BUNDLE_ID command-0
xcrun swift Scripts/macos-e2e-driver.swift shortcut-app com.apple.TextEdit option-control-w
xcrun swift Scripts/macos-e2e-driver.swift shortcut-app com.apple.TextEdit option-shift-r
xcrun swift Scripts/macos-e2e-driver.swift window-state BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift window-set BUNDLE_ID X Y WIDTH HEIGHT
xcrun swift Scripts/macos-e2e-driver.swift window-minimize BUNDLE_ID
xcrun swift Scripts/macos-e2e-driver.swift window-restore BUNDLE_ID
```

The driver activates and verifies the target process, refuses text containing line breaks, preserves and restores the clipboard around paste input, checks exact UTF-16 lengths before clearing, rejects clicks outside the target application or on send-like controls, and consumes oracle-provided Quartz coordinates. `press-self-chat` accepts only explicit self markers such as `(You)`, `Saved Messages`, and `Message yourself`; if an app omits those AX labels, require a tightly cropped visual confirmation before a guarded coordinate click. Shortcuts are deliberately whitelisted; the usage output lists supported combinations, including the default Compose and Quick Rewrite shortcuts above. Verify configured bindings and that shortcuts are enabled before relying on them. Keep host-app orchestration in Computer Use and assertions in `Scripts/e2e-state.py`; add a scenario layer only if repeated tests prove these direct commands insufficient.

If Computer Use reports a capture failure for TextWarden's overlay-only state, do not infer that the pill is absent. Verify its current frame in the oracle or logs, use the guarded `click-textwarden` helper where native input is authorized, then capture the opened Compose or suggestion panel. During September 2026 checks, app-targeted shortcut events inserted characters into TextEdit instead of invoking TextWarden's global shortcut; the native helper exercised the intended event path. Restore the exact fixture after any such mismatch. Do not count successful helper execution alone as a pass: verify the resulting UI and editor value.

## Application canaries

### Feature-specific AI quality

`AIInteractionTests` separates draft generation, selected-text editing, simplification, and style suggestions. These opt-in tests use independent synthetic text and the installed on-device model, not a hosted provider. Each quality call retains its input, output, and repetition in XCTest attachments. Ordinary `make test` runs the deterministic prompt/lifecycle checks without requiring Apple Intelligence.

```bash
TEST_RUNNER_TEXTWARDEN_TEST_AI=1 TEST_RUNNER_TEXTWARDEN_TEST_AI_FEATURE_QUALITY=1 \
  xcodebuild test -scheme TextWarden -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:TextWardenTests/AIInteractionTests \
  -resultBundlePath /private/tmp/textwarden-feature-quality-new.xcresult
xcrun xcresulttool export attachments \
  --path /private/tmp/textwarden-feature-quality-new.xcresult \
  --output-path /private/tmp/textwarden-feature-quality-new-attachments
```

Use a new result path for each run. Preserve failures rather than weakening assertions to match the output. Review the retained text for meaning, naturalness, and instruction following; lexical assertions alone cannot establish those properties. Report each feature separately. English has priority, with German/French editing probes; these small probes are not a claim of complete language coverage.

After changing Compose, use the existing native driver and Computer Use in a disposable TextEdit document:

1. With no selection and deliberately incorrect surrounding text, draft a sentence using different facts. Verify the draft follows only the instruction, then Cancel and check the source is unchanged.
2. Repeat and Insert at the cursor; verify the existing text was not replaced.
3. Select a sentence between untouched prefix/suffix text. Fix its grammar, retry, review, and Insert; verify numbers, negation, timing, and the exact replacement boundary.
4. Change the instruction/style, Clear, and close during generation. No stale result may appear on reopening. A failed retry must retain the last reviewed result and must not permit insertion while pending.
5. Restore temporary shortcuts and the synthetic document. Keep API quality evidence separate from these editor-interaction checks.

### Quick Rewrite

The opt-in multilingual regression covers sentences and phrases in English, German,
French, Spanish, Italian, Portuguese, Dutch, and Japanese, plus ambiguous fragments,
numbers, and emoji. It retains synthetic source/result attachments and distinguishes
proposals from safe language-related declines. A matching detector label alone does
not establish semantic fidelity; inspect the retained text as well.

```bash
TEST_RUNNER_TEXTWARDEN_TEST_REWRITE_LANGUAGES=1 xcodebuild test \
  -scheme TextWarden -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:TextWardenTests/QuickRewriteTests/testLiveRewritePreservesSentenceAndPhraseLanguages
```

On 2026-09-11, the unguarded baseline changed a Portuguese sentence toward Spanish
and rewrote the ambiguous word `Gift` as Swedish `Gifta sig`, in both Default and
Concise styles. After the language guard, the expanded 48-case run (24 selections,
two styles, Consistent sampling) returned 38 same-language or unchanged results and
declined 10 uncertain inputs. The phrase `se estará presente` is shared by Portuguese
and Spanish: its capitalization-only result remains valid Portuguese despite the
detector's Spanish label. TextEdit also preserved the French language and emoji-bearing
boundary markers after Apply, and left the Portuguese regression unchanged when declined.
These are bounded regression checks, not a guarantee for all languages or model versions.

Use the [visual regression checks](QUICK-REWRITE-UI.md) for review-panel sizing,
keyboard actions, timeout behavior, and synthetic screenshots across text lengths,
font sizes, and appearances. These run independently of model quality.

Run the opt-in local Foundation Models check with:

```bash
TEST_RUNNER_TEXTWARDEN_TEST_AI=1 xcodebuild test -scheme TextWarden \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:TextWardenTests/QuickRewriteTests
```

For live interaction checks, create a disposable TextEdit document and a recipientless Mail draft. Select a sentence containing deliberate mistakes, invoke **Quick Rewrite Selected Text**, and verify that only that selection changes. Repeat in Mail's subject and body, with emoji before the selection, repeated identical phrases, and multiple paragraphs. Verify the configured writing style and editor Undo. Repeat with the pill hidden, no selection, and a custom shortcut; disable keyboard shortcuts and confirm the action does not run. Remap conflicting shortcuts before testing so another application cannot intercept the selection.

During generation, move the caret, select a different phrase, edit the text, switch fields/windows/apps, and invoke the shortcut again. Each case must leave the original text intact. Check that the progress status does not take focus, errors remain readable, and clipboard contents survive paste-based replacements. Passing the model check alone does not establish host-app compatibility.

Every changed Quick Rewrite now requires review. For the ordinary path, use `Before. We are currently in the process of reviewing 17 reports. After.` and select only the middle sentence. For the transformation warning, use `Before. The children's, coats are hanging by the stairs. After.` instead. Model outcomes can change: verify that the **Original / Rewrite** review actually opens, inspect any warning and proposed text, and confirm that the editor is unchanged before approval. Never approve a button blindly or count unchanged output as a tested preview.

1. Apply the reviewed correction with Return, then repeat using the Apply button. Assert the complete document, including both sentinels, with `check-editor`; verify editor Undo restores the source.
2. Reset the fixture, obtain a fresh review, then select `Before.`. Verify cancellation and the unchanged complete document. Re-selecting the old sentence must not revive the request.
3. Obtain another fresh review, press Escape, and verify cancellation without replacement.
4. Restore the original fixture, style, creativity, and shortcut settings. Record which review reason and actions were actually exercised.

Debug logs distinguish shortcut requests, activation rejection, generation, unchanged results, review decisions, and replacement failures. These are fixed diagnostic labels, not source or response text. Read them alongside the native editor and panel state; a model-availability line or stale E2E snapshot is not an outcome.

- [Apple Mail](MAIL-E2E-CANARIES.md)
- [Apple Pages](PAGES-E2E-CANARIES.md)
