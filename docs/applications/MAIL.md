# TextWarden for Apple Mail on macOS

TextWarden adds local grammar checking and writing assistance to Apple Mail compose windows. It checks subject lines and new message text while ignoring recipient fields, Mail navigation, and read-only messages.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Apple Mail |
| Bundle ID | `com.apple.mail` |
| App type | Native macOS app with a WebKit compose body |
| Checked content | Subject field and editable message body |
| Ignored content | To/Cc/Bcc fields, search, sidebar, message list, read-only preview, quoted replies |
| Visual underlines | Enabled |
| Content parser | `MailContentParser` |
| Positioning | Dedicated `MailStrategy` |
| Correction method | WebKit selection followed by direct keyboard typing |

## Compose detection and text extraction

Mail exposes both editable and read-only content through similar Accessibility roles. `MailContentParser` accepts a subject field when its metadata identifies it as the subject. For message bodies, it looks for an editable ancestor, a settable value, or a compose-window structure. Read-only preview panes and list content are rejected.

For the WebKit body, extraction tries `AXValue`, then `AXStringForRange`, then child `AXStaticText` elements. The range API is preferred because it preserves the newline positions used by Mail’s bounds API.

Quoted replies, forwarded-message headers, and common meeting-invite boilerplate are removed before analysis. The patterns cover the localized attribution formats implemented in `MailContentParser`; only text before the first recognized quote marker is checked.

## Underline positioning

`MailStrategy` converts grammar-engine offsets to UTF-16 using the text returned by Mail itself. It asks `AXBoundsForRange` for the first and last character of the issue, combines those bounds, and converts layout coordinates to screen coordinates when WebKit returns local geometry.

The app behavior uses a 500 ms analysis debounce. Underlines hide during scrolling and are recalculated afterward.

## Corrections and formatting

Mail’s direct Accessibility replacement calls are not trusted: the tested APIs either fail or report success without changing the message. TextWarden instead selects the range with `AXSelectedTextMarkerRange`, falling back to `AXSelectedTextRange`, activates Mail, and types the replacement.

Typing into the selection lets Mail inherit the surrounding rich-text formatting. TextWarden then clears cached geometry and reanalyzes the compose body because WebKit offsets may have changed.

## Troubleshooting

- Click inside the subject or message body. Recipient and search fields are ignored on purpose.
- If existing reply text is not checked, that is expected. TextWarden stops analysis at the first recognized quote or forwarded-message marker.
- If an underline is offset after an emoji, capture Accessibility logs for `MailStrategy`; its conversion should be based on `AXStringForRange` and UTF-16 units.
- A correction needs Accessibility permission because TextWarden selects and types into Mail on your behalf.

For repeatable live regression coverage, see [Apple Mail live E2E canaries](../testing/MAIL-E2E-CANARIES.md).

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/MailBehavior.swift`
- `Sources/ContentParsers/MailContentParser.swift`
- `Sources/Positioning/Strategies/MailStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
