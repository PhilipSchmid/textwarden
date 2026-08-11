# TextWarden for WhatsApp on macOS

TextWarden adds local grammar checking and writing assistance to the WhatsApp message composer. Its Mac Catalyst integration includes stale-text protection for conversation switches.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | WhatsApp for macOS |
| Bundle ID | `net.whatsapp.WhatsApp` |
| App type | Mac Catalyst |
| Checked content | Focused message composer |
| Visual underlines | Enabled |
| Content parser | Generic |
| Positioning | `TextMarker` → `RangeBounds` → `LineIndex` → `InsertionPoint` → `FontMetrics` |
| Correction method | Accessibility selection with keyboard-based replacement |

## Conversation and stale-text handling

WhatsApp may continue returning the previous composer text for a short time after the user changes conversations. TextWarden watches the compose frame and treats a movement greater than 10 points as a likely conversation switch. It clears the old overlays, waits 500 ms, and reads the text again.

If the new Accessibility value is identical to the text from the prior conversation, TextWarden treats it as stale and skips that reanalysis. A later text change or focus event supplies the fresh value.

The shared Catalyst monitoring also handles composer size changes:

- A height decrease greater than 5 points clears errors when a message was likely sent.
- A height increase greater than 5 points invalidates old underline positions.
- A 500 ms validation timer compares live text with the last analysis.

## Corrections

WhatsApp uses browser-style replacement. TextWarden selects the reported range, activates WhatsApp, and uses keyboard input rather than trusting direct `AXValue` replacement. It checks the live text before applying the correction and reanalyzes afterward.

The composer is treated as plain text. WhatsApp’s message-markup syntax is not handled as rich text by this integration.

## Troubleshooting

- Wait briefly after changing chats. The 500 ms delay is intentional and avoids attaching old results to a new conversation.
- If no reanalysis occurs after a switch, the Accessibility API probably returned the old text. Typing or refocusing the composer triggers another read.
- If an underline drifts after emoji or wrapping, edit the text or change focus to invalidate cached geometry.
- If a correction is rejected after a conversation switch, wait for the next analysis rather than retrying against the old underline.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/WhatsAppBehavior.swift`
- `Sources/AppConfiguration/MessengerBehavior.swift`
- `Sources/App/AnalysisCoordinator+WindowTracking.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
