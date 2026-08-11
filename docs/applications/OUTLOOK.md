# TextWarden for Microsoft Outlook on macOS

TextWarden adds local grammar checking and writing assistance to Microsoft Outlook compose windows. It checks subject lines and new message text while ignoring recipients, the ribbon, and quoted replies.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Microsoft Outlook for macOS |
| Bundle ID | `com.microsoft.Outlook` |
| App type | Native Microsoft Office app |
| Checked content | Subject field and editable compose body |
| Ignored content | To/Cc/Bcc fields, ribbon controls, font selectors, menus, quoted replies |
| Visual underlines | Enabled |
| Content parser | `OutlookContentParser` |
| Positioning | Dedicated `OutlookStrategy` |
| Correction method | Focus the editor, select the range, then paste with `Command-V` |

## Compose detection and extraction

`OutlookContentParser` accepts subject fields identified by their Accessibility metadata and editable body text areas. It rejects address fields, toolbar and ribbon descendants, menu controls, and font selectors such as “Aptos (Body).” When Outlook focuses a static-text child instead of the editor, the parser searches siblings, parents, and the compose window for the actual text area.

Text is read with `AXValue`. The parser deliberately avoids parameterized string queries in Outlook because those calls are unsafe in the Office accessibility framework. Reply and forward text is passed through the same quote stripping used for Apple Mail, so only the new message above a recognized quote marker is analyzed.

Outlook’s configuration defers text extraction and uses a 500 ms analysis debounce. Accessibility watchdog checks prevent repeated calls while Outlook is unresponsive.

## Underline positioning

Outlook has two positioning paths:

- The subject `AXTextField` uses `AXBoundsForRange` with UTF-16 conversion.
- The compose-body `AXTextArea` first uses direct bounds with Outlook’s grapheme-based offsets. If that fails or returns suspicious geometry, the strategy maps child `AXStaticText` runs and queries the matching child.

Geometry outside the compose frame is rejected. Frame validation stays enabled because opening or closing Outlook’s Copilot panel can move the editor.

## Corrections and formatting

Direct Accessibility value replacement can strip Outlook’s rich-text formatting. TextWarden follows the Office replacement path instead: focus the editor, set `AXSelectedTextRange`, place the correction on the clipboard, activate Outlook, and paste. It verifies that the clipboard still contains the intended suggestion before sending `Command-V`.

Quoted content is not included in the analyzed source, so corrections target the new compose text rather than the message history.

## Troubleshooting

- Click in the subject or message body. Recipient fields and ribbon controls are ignored intentionally.
- If the Copilot panel changes the compose layout, wait for frame validation to reposition the overlays.
- If Outlook temporarily stops responding to Accessibility calls, TextWarden’s watchdog may pause analysis rather than block the app.
- After editing around an existing issue, wait for fresh analysis before applying its correction. The Office path searches the live message for the analyzed text before falling back to the recorded range.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/OutlookBehavior.swift`
- `Sources/ContentParsers/OutlookContentParser.swift`
- `Sources/Positioning/Strategies/OutlookStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
