# TextWarden for Microsoft PowerPoint on macOS

TextWarden adds local grammar checking and writing assistance to PowerPoint speaker notes. PowerPoint does not expose slide text boxes as editable text through the macOS Accessibility tree used by TextWarden.

## Support summary

| Item | Speaker notes | Slide text boxes |
|------|---------------|------------------|
| Grammar checking | Supported | Not supported |
| Visual underlines | Supported | Not supported |
| One-click corrections | Supported | Not supported |

| Integration detail | Current behavior |
|--------------------|------------------|
| Bundle ID | `com.microsoft.Powerpoint` |
| App type | Native Microsoft Office app |
| Content parser | `PowerPointContentParser` |
| Positioning | Dedicated `PowerPointStrategy` |
| Correction method | Focus the notes editor, select the range, then paste with `Command-V` |

## Why support is limited to speaker notes

The Notes editor is exposed as an Accessibility text element with an `AXValue` and usable range bounds. TextWarden can extract its text, analyze it, and place underlines.

Slide text boxes are not exposed as editable text elements in the Accessibility tree observed by the app. Without the source text and character ranges, TextWarden cannot analyze or position corrections safely. The integration does not infer text from the rendered slide.

`PowerPointContentParser` filters toolbar, ribbon, font, menu, and popup controls so Office interface labels are not mistaken for presentation content.

## Underline positioning

`PowerPointStrategy` converts the grammar range to UTF-16 and asks the notes element for `AXBoundsForRange`. It first tries line-specific bounds for an issue spanning multiple lines, then falls back to one combined range.

PowerPoint uses a 300 ms analysis debounce and does not require a separate typing pause. Focus-bounce protection keeps the existing notes editor monitored when focus briefly moves to a non-editable Office element.

## Corrections and formatting

PowerPoint uses the Office replacement path because direct value replacement is not reliable. TextWarden focuses the notes editor, sets its selected range, prepares the clipboard, activates PowerPoint, and pastes. The clipboard value is verified before the paste is sent.

Rich-text layout changes trigger position refreshes. PowerPoint controls the final formatting inherited by pasted text.

## Troubleshooting

- Show the Notes pane and click inside the notes text. Slide-canvas focus cannot provide grammar checking.
- If a click on the ribbon briefly removes focus, TextWarden keeps a valid monitored notes element when it can still read its value.
- If the Notes editor returns no range bounds, TextWarden omits the underline rather than estimating a slide position.
- Presenter view and slide-show content are outside the supported Notes editing path.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/PowerPointBehavior.swift`
- `Sources/ContentParsers/PowerPointContentParser.swift`
- `Sources/Positioning/Strategies/PowerPointStrategy.swift`
- `Sources/Accessibility/TextMonitor.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
