# TextWarden for Perplexity on macOS

TextWarden adds local grammar checking and writing assistance to the Perplexity macOS desktop app. It checks focused prompt text, shows grammar underlines, and applies corrections through Accessibility-based selection and paste.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Perplexity for macOS |
| Bundle ID | `ai.perplexity.mac` |
| App type | Electron |
| Checked content | Focused editable prompt text |
| Visual underlines | Enabled |
| Content parser | Generic |
| Positioning | `AnchorSearch` → `TextMarker` → `ElementTree` |
| Correction method | Select the text, then paste with `Command-V` |

## How the integration works

Perplexity does not provide dependable full-range geometry on its root editor. `AnchorSearchStrategy` probes nearby characters until it finds one with valid Accessibility bounds, then measures the text between that anchor and the grammar error. Text-marker and child-tree positioning remain available as fallbacks.

The strategy converts offsets to UTF-16 before querying the Accessibility API, which keeps positions aligned after emoji and other multi-unit characters.

Perplexity batches accessibility notifications, so TextWarden also watches keyboard activity. The app behavior uses a 1-second analysis debounce and requests a full reanalysis after corrections.

## Corrections

The prompt is treated as plain text. TextWarden uses browser-style selection and paste, including special handling for a replacement at position zero. Selection is validated when possible; an unsafe or stale selection is rejected.

## Troubleshooting

- Click in the prompt editor first. Read-only answers and other unfocused text are not the intended editing surface.
- If an underline appears late, allow the 1-second analysis debounce to finish.
- If positioning is unavailable for a range, the Perplexity editor did not expose a usable anchor or fallback element.
- If a correction says the text changed, wait for reanalysis before trying again.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/PerplexityBehavior.swift`
- `Sources/Positioning/Strategies/AnchorSearchStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
