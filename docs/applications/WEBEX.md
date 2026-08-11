# TextWarden for Cisco Webex on macOS

TextWarden adds local grammar checking and writing assistance to the Cisco Webex chat composer. A dedicated content parser keeps sent messages and meeting controls out of the analysis path.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Cisco Webex for macOS |
| Bundle ID | `Cisco-Systems.Spark` |
| App type | Native macOS |
| Checked content | Chat compose field |
| Ignored content | Sent messages and non-editor controls |
| Visual underlines | Enabled |
| Content parser | `WebExContentParser` |
| Positioning | Dedicated `WebExStrategy` |
| Correction method | Standard Accessibility replacement, with keyboard fallback |

## Compose-field detection

Webex exposes sent messages and the editor through nearby parts of the Accessibility tree. `WebExContentParser` accepts only a text area or text field whose identifier is `ConversationInputTextView`, or whose parent identifier is `Spark Text View`.

Clicking a sent message therefore does not start grammar checking. If focus moves from the composer to a rejected element, TextWarden clears the monitored element and hides its overlays.

## Underline positioning

`WebExStrategy` verifies the compose element, converts grammar-engine offsets to UTF-16, and queries `AXBoundsForRange` directly. Invalid or unusually small bounds are rejected.

The app requires a typing pause and uses a 500 ms analysis debounce. Underlines hide during scroll and are recalculated after scrolling ends.

## Corrections

Webex uses the standard native replacement path. TextWarden first tries Accessibility selection and `AXSelectedText` replacement. If Webex rejects that operation, it can fall back to keyboard navigation and paste.

The compose field is configured as plain text; there is no Webex-specific rich-text replacement path.

## Troubleshooting

- Make sure focus is in the chat composer. Clicking a sent message intentionally clears TextWarden’s monitoring.
- If the composer is not recognized, inspect `AXIdentifier`; the parser currently expects `ConversationInputTextView` or a `Spark Text View` parent.
- Pause for half a second after typing before expecting the final underline positions.
- If text after emoji is misaligned, capture logs from `WebExStrategy`; its range query should use UTF-16 conversion.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/WebExBehavior.swift`
- `Sources/ContentParsers/WebExContentParser.swift`
- `Sources/Positioning/Strategies/WebExStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
