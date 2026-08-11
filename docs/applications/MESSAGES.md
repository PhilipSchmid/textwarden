# TextWarden for Apple Messages on macOS

TextWarden adds local grammar checking and writing assistance to the Apple Messages compose field. Messages is a Mac Catalyst app, so TextWarden combines several positioning methods with extra checks for conversation changes and sent messages.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Apple Messages |
| Bundle ID | `com.apple.MobileSMS` |
| App type | Mac Catalyst |
| Checked content | Focused message composer |
| Visual underlines | Enabled |
| Content parser | Generic |
| Positioning | `TextMarker` → `RangeBounds` → `LineIndex` → `InsertionPoint` → `FontMetrics` |
| Correction method | Accessibility selection with keyboard-based replacement |

## Catalyst handling

Messages can report imperfect range geometry on wrapped text, especially after emoji or other multi-codepoint characters. TextWarden starts with text-marker and direct range queries, then falls back to line, insertion-point, and font-metric calculations.

The monitored compose frame is also used as a signal:

- A movement greater than 10 points is treated as a likely conversation switch. TextWarden clears old results and rechecks after 200 ms.
- A height decrease greater than 5 points is treated as a likely sent message and clears the old errors.
- A height increase greater than 5 points invalidates underline positions while the field grows.

A 500 ms validation timer compares the current compose text with the analyzed text because Catalyst notifications are not always sufficient on their own.

## Corrections

Messages is configured for browser-style replacement rather than direct `AXValue` replacement. TextWarden selects the issue and uses keyboard input in the frontmost app. It validates current text and error positions before changing anything, then performs a full reanalysis.

The compose field is treated as plain text; there is no app-specific rich-text preservation path.

## Troubleshooting

- Pause after switching conversations. Results from the previous compose field are cleared before the new text is analyzed.
- If a multiline underline looks slightly offset after emoji, the Catalyst API may have returned imperfect X coordinates. Editing the text or changing focus forces fresh positioning.
- If a sent message leaves an indicator behind, focus the empty composer; periodic validation should clear stale results on its next pass.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/MessagesBehavior.swift`
- `Sources/AppConfiguration/MessengerBehavior.swift`
- `Sources/App/AnalysisCoordinator+WindowTracking.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
