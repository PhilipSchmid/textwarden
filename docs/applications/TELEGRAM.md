# TextWarden for Telegram on macOS

TextWarden adds local grammar checking and writing assistance to Telegram’s native macOS message composer. Telegram exposes standard Accessibility ranges, so this integration uses the shared native positioning and correction paths.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Telegram for macOS |
| Bundle ID | `ru.keepcoder.Telegram` |
| App type | Native macOS |
| Checked content | Focused editable message text |
| Visual underlines | Enabled |
| Content parser | Generic |
| Positioning | `RangeBounds` → `LineIndex` → `FontMetrics` |
| Correction method | Standard Accessibility selection/replacement, with keyboard fallback |

## How the integration works

TextWarden first asks Telegram for direct bounds for the issue range. The shared range strategy converts text offsets to UTF-16 before calling the Accessibility API, which keeps underlines aligned after emoji. Line-based and font-metric strategies remain available if direct bounds fail.

Telegram’s behavior profile uses a 300 ms analysis debounce and hides underlines during scrolling. It does not register any Telegram-specific Accessibility quirks.

## Corrections and formatting

TextWarden tries the standard native path: select the UTF-16 range and replace `AXSelectedText`. If Telegram rejects either operation, TextWarden falls back to keyboard navigation and paste.

Telegram is marked as supporting formatted text so formatting changes trigger position refreshes. There is no Telegram-specific format-preserving replacement implementation, so rich-text preservation should not be assumed for every correction.

## Troubleshooting

- Click in the message composer before expecting analysis. Media, stickers, and read-only conversation content are outside the text-editing path.
- If formatting changes move text, click back into the composer; TextWarden clears cached positions after formatting interactions.
- If a correction falls back to keyboard navigation, keep Telegram frontmost until the operation finishes.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/TelegramBehavior.swift`
- `Sources/Positioning/Strategies/RangeBoundsStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
