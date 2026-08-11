# TextWarden for ChatGPT on macOS

TextWarden adds local grammar checking and writing assistance to the ChatGPT macOS desktop app. It monitors the focused prompt editor, draws grammar underlines, and applies selected corrections through the macOS Accessibility API.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | ChatGPT for macOS |
| Bundle ID | `com.openai.chat` |
| App type | Electron |
| Checked content | Focused editable prompt text |
| Visual underlines | Enabled |
| Content parser | Generic |
| Positioning | `RangeBounds` → `TextMarker` → `ElementTree` → `LineIndex` |
| Correction method | Select the text, then paste with `Command-V` |

## How the integration works

ChatGPT exposes usable `AXBoundsForRange` results on its editor, so TextWarden starts with direct range positioning. It converts grammar-engine offsets to the UTF-16 ranges expected by macOS accessibility APIs, then falls back through text-marker and child-tree strategies if the direct query fails.

ChatGPT batches some accessibility notifications. TextWarden keeps keyboard-based typing detection enabled and performs a full reanalysis after a correction so old Electron offsets are not reused.

The configuration does not require the separate cursor-positioning pause used by some Electron apps. The behavior profile still uses a 1-second analysis debounce to let the editor settle.

## Corrections

The prompt editor is treated as plain text. TextWarden selects the reported range, validates the selection when the accessibility API exposes it, places the correction on the clipboard, activates ChatGPT, and pastes. If selection cannot be trusted, the replacement stops instead of changing the wrong text.

## Troubleshooting

- Click inside the prompt editor before expecting an underline. TextWarden only monitors editable focused content.
- If an underline disappears while scrolling, pause briefly. The behavior hides stale overlays during scrolling and recalculates them afterward.
- If a correction reports that the text changed, wait for the new analysis. This is a safety check against replacing stale offsets.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/ChatGPTBehavior.swift`
- `Sources/Positioning/Strategies/RangeBoundsStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
