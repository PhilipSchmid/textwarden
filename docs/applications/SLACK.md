# TextWarden for Slack on macOS

TextWarden adds local grammar checking and writing assistance to the Slack message composer. Slack’s Electron editor needs dedicated parsing, positioning, selection validation, and rich-text clipboard handling.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Slack for macOS |
| Bundle ID | `com.tinyspeck.slackmacgap` |
| App type | Electron/Chromium |
| Checked content | Editable message text |
| Excluded content | Detected mentions, channels, links, inline code, code blocks, and blockquotes |
| Visual underlines | Enabled |
| Content parser | `SlackContentParser` |
| Positioning | Dedicated `SlackStrategy` |
| Correction method | Verified child selection with format-aware paste; plain-text or copy fallback when needed |

## Content filtering

Slack exposes message formatting through several Accessibility representations. TextWarden combines them instead of relying on visible punctuation:

- `AXBackgroundColor` ranges identify special spans such as mentions, channels, and code.
- `AXLink` children identify URLs.
- `AXCodeStyleGroup` and `AXBlockQuoteLevel` provide tree-based fallbacks for code and blockquotes.
- Mention and channel child text is recognized by `@` and `#` prefixes when richer attributes are missing.

Attributed text is read in adaptive chunks from 200 characters down to one. Adjacent ranges are merged so an exclusion split across two queries remains one span.

If the clipboard already contains Slack’s `org.chromium.web-custom-data`, the parser can also read its Quill Delta data. Clipboard monitoring records later Slack copies without changing the clipboard by itself. Bold, italic, underline, and strikethrough prose remain eligible for grammar checking.

## Underline positioning

Slack’s root composer does not provide consistently reliable range bounds. `SlackStrategy` traverses the Accessibility tree, maps child `AXStaticText` runs to source ranges, and queries `AXBoundsForRange` on the matching child. When no mapped child overlaps the issue, it makes a tightly validated root-range query as a fallback. Suspicious multiline geometry is rejected.

Slack is configured to use only this dedicated strategy. If neither child geometry nor the validated root fallback is safe, TextWarden keeps the issue in its indicator instead of guessing an underline position.

Slack scroll notifications are treated as unreliable. TextWarden watches bounds movement rather than hiding underlines on every scroll event. Periodic frame validation also catches movement in the message-edit modal.

## Format-aware corrections

TextWarden first converts the grammar engine’s scalar offsets to Swift and UTF-16 ranges. It then searches child elements for the exact error text and reads `AXSelectedText` back to verify the selection.

For the format-aware path, TextWarden:

1. Saves the current clipboard.
2. Copies the verified Slack selection to obtain its Quill Delta attributes.
3. Builds replacement clipboard data with the suggestion and retained attributes.
4. Activates Slack, pastes, and restores the previous clipboard.

If formatting data is unavailable, the same verified selection can use plain text. If only the unreliable root element contains the target, TextWarden offers a copy action for manual paste. A failed verification never proceeds with automatic replacement.

## Native popovers and scrolling

Slack uses an `AXPopover` for its own formatting and suggestion UI. TextWarden hides its popover when that native popover is detected, avoiding overlapping controls.

The behavior does not hide overlays on Slack’s unreliable scroll-start events. Instead, it uses a 10-point bounds-movement threshold and clears strategy caches when layout changes are detected.

## Troubleshooting

- An issue without an underline means Slack did not expose safe geometry for that range. The indicator can still show the issue.
- “Could not select text” means selection verification failed. Click near the word, let Slack settle, and retry after reanalysis.
- Text containing mentions or links may only exist on the root element. In that case, use the offered copy action and paste manually.
- In an edited message, scrolling can move the composer with the history. Frame validation should relocate the overlay after the layout settles.
- TextWarden uses the clipboard briefly for corrections and restores the previous clipboard after the format-aware path completes.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/SlackBehavior.swift`
- `Sources/ContentParsers/SlackContentParser.swift`
- `Sources/Positioning/Strategies/SlackStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
- `Tests/Unit/SlackStrategyValidationTests.swift`
