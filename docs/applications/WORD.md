# TextWarden for Microsoft Word on macOS

TextWarden adds local grammar checking and writing assistance to editable Microsoft Word documents. A dedicated parser keeps Word’s ribbon out of the analysis, while a dedicated strategy positions grammar underlines against document ranges.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Microsoft Word for macOS |
| Bundle ID | `com.microsoft.Word` |
| App type | Native Microsoft Office app |
| Checked content | Focused editable document text |
| Visual underlines | Enabled |
| Content parser | `WordContentParser` |
| Positioning | Dedicated `WordStrategy` |
| Correction method | Focus the editor, select the range, then paste with `Command-V` |

## Document detection and extraction

`WordContentParser` accepts document text areas and text-bearing document containers. It rejects toolbar and ribbon controls, menu elements, popup buttons, and font selectors such as “Aptos (Body).” If focus lands on another Office element, the parser can search the window for the document text area.

Document text is read from `AXValue`. The positioning strategy treats Word’s editor as a flat text element rather than depending on child text runs.

## Underline positioning

`WordStrategy` converts grammar ranges to UTF-16, then queries the document element with `AXBoundsForRange`. For issues spanning multiple lines, it uses line-specific bounds and returns them to the overlay; otherwise it uses the single range result.

Invalid or unusually small geometry is rejected. Word uses a 300 ms analysis debounce and does not require a separate typing pause. Formatting interactions clear cached positions because they can change line wrapping.

The source notes that direct range positioning was tested with Word 16.104 and later. TextWarden does not enforce a minimum Word version at runtime, so older versions may work but are not guaranteed by the current implementation.

## Corrections and formatting

Direct `AXValue` replacement is not considered reliable in Word. TextWarden focuses the document element, selects the issue, verifies the clipboard content, activates Word, and pastes with `Command-V`. The previous clipboard string is restored when available.

This path is designed to let Word inherit surrounding formatting. Complex document formatting is still controlled by Word, so preservation is not guaranteed for every structure.

## Troubleshooting

- Click inside the document body. Ribbon controls and font fields are filtered deliberately.
- If the document is open but no text is monitored, move focus into the body so TextWarden can find the document text element.
- If an older Word build returns bad bounds, the indicator may show an issue without a usable underline.
- After editing around an existing issue, wait for fresh analysis before applying its correction. The Office path searches the live document for the analyzed text before falling back to the recorded range.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/WordBehavior.swift`
- `Sources/ContentParsers/WordContentParser.swift`
- `Sources/Positioning/Strategies/WordStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
