# TextWarden for Apple Pages on macOS

TextWarden adds local grammar checking and writing assistance to editable text in Apple Pages. Pages uses the shared native parser and positioning strategies, plus a focused paste path for corrections.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Apple Pages |
| Bundle ID | `com.apple.iWork.Pages` |
| App type | Native macOS |
| Checked content | Focused editable document text |
| Visual underlines | Enabled |
| Content parser | Generic |
| Positioning | `RangeBounds` → `LineIndex` → `FontMetrics` |
| Correction method | Focus the editor, select the range, then paste with `Command-V` |

## Underline positioning

Pages exposes document text through standard Accessibility text elements. TextWarden starts with `AXBoundsForRange`, including UTF-16 conversion inside the shared strategy, then falls back to line-based and measured positioning when direct geometry is unavailable.

The app behavior uses a 300 ms analysis debounce, does not require an additional typing pause, and hides underlines while scrolling. Formatting shortcuts and formatting controls trigger position refreshes because rich text can move the document layout.

## Corrections and formatting

Pages can report success for direct Accessibility replacement without changing the document. TextWarden therefore uses its Office-style path:

1. Focus the current editor.
2. Set the selected text range.
3. Put the correction on the clipboard.
4. Activate Pages and paste with `Command-V`.

The clipboard is checked immediately before paste, and the previous clipboard string is restored afterward when one was available. Pasting into the selected rich-text range is intended to preserve the surrounding formatting, but Pages remains responsible for the final formatting result.

## Troubleshooting

- Click into editable document text. TextWarden follows the focused Accessibility element and does not scan an unfocused page.
- If underlines move after a font or paragraph change, click back into the text or use the formatting shortcut again to trigger a position refresh.
- Keep Pages frontmost until a correction finishes; the focused replacement path sends `Command-V` to the active app.
- After editing around an existing issue, wait for fresh analysis before applying its correction. The focused paste path searches the live document for the analyzed text before falling back to the recorded range.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/PagesBehavior.swift`
- `Sources/Positioning/Strategies/RangeBoundsStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
