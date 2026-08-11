# TextWarden for Claude Desktop on macOS

TextWarden adds local grammar checking and writing assistance to Claude Desktop. Claude’s Electron editor needs a dedicated Accessibility-tree strategy for accurate grammar underlines.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Claude Desktop |
| Bundle ID | `com.anthropic.claudefordesktop` |
| App type | Electron |
| Checked content | Focused prompt text |
| Visual underlines | Enabled |
| Content parser | `ClaudeContentParser` |
| Positioning | Dedicated `ClaudeStrategy` |
| Correction method | Select the text, then paste with `Command-V` |

## Why Claude needs a dedicated strategy

Claude’s root text area does not return trustworthy `AXBoundsForRange` geometry. Its child `AXStaticText` elements do. `ClaudeStrategy` rebuilds a map of those children, finds the child containing the grammar error, and asks that child for local range bounds.

If no matching child exists, the strategy reports the underline as unavailable. It does not fall through to estimated positioning that could draw underlines in the wrong place.

Claude also reports its visible range as the full text, which makes scroll-based cache invalidation unreliable. TextWarden therefore rebuilds the child map for each positioning request. A 300 ms stability check prevents bounds queries while typing; the app behavior uses a 1-second analysis debounce.

## Text offsets and corrections

`ClaudeContentParser` adjusts selection offsets for newlines and uses UTF-16 conversion for Chromium selection APIs. It does not replace the editor’s text extraction; standard Accessibility text reading remains in use.

Corrections use browser-style selection and `Command-V`. TextWarden reanalyzes after each replacement because Electron byte and selection offsets can change.

## Troubleshooting

- Pause typing before expecting an underline. Bounds are intentionally skipped while Claude’s editor is changing.
- Scrolling forces fresh geometry. A short delay before underlines return is expected.
- If the indicator shows an issue without an underline, Claude did not expose a usable child text element for that range.
- If a correction cannot verify its selection, TextWarden cancels it rather than risking a change elsewhere in the prompt.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/ClaudeBehavior.swift`
- `Sources/ContentParsers/ClaudeContentParser.swift`
- `Sources/Positioning/Strategies/ClaudeStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
