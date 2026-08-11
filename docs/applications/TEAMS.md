# TextWarden for Microsoft Teams on macOS

TextWarden adds local grammar checking and writing assistance to the Microsoft Teams message composer. Teams uses an Electron accessibility tree in which child text runs provide better geometry than the root editor.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Microsoft Teams for macOS |
| Bundle ID | `com.microsoft.teams2` |
| App type | Electron/Chromium |
| Checked content | Editable message text |
| Excluded content | Detected code, blockquotes, URLs, mentions, and channels |
| Visual underlines | Enabled |
| Content parser | `TeamsContentParser` |
| Positioning | Dedicated `TeamsStrategy` |
| Correction method | Verified Accessibility selection followed by paste |

## Content filtering

`TeamsContentParser` excludes ranges that Teams exposes as special content:

- Background-colored attributed ranges catch mentions, channels, and code spans.
- `AXLink` children identify HTTP and HTTPS URLs.
- `AXCodeStyleGroup` identifies code containers.
- `AXBlockQuoteLevel` identifies blockquotes.
- Child text beginning with `@` or `#` provides a mention/channel fallback.

Bold, italic, underline, and strikethrough are not exclusions. The parser reads attributed text in adaptive chunks and caches results until the source text changes.

## Underline positioning

The root Teams text area does not return dependable `AXBoundsForRange` geometry. `TeamsStrategy` traverses up to ten levels of children, maps valid `AXStaticText` runs to the full message, and queries each matching child with a local range.

For errors spanning more than one child, TextWarden combines the child bounds. It rejects geometry outside the visible editor frame, including zero-frame or scrolled-out results. The app uses only the dedicated Teams strategy, so missing child geometry produces no underline rather than a guessed position.

Teams requires a typing pause and uses a 1-second analysis debounce. Formatting changes clear the child map so underlines are rebuilt against the new layout.

## Corrections

Teams uses browser-style replacement. TextWarden finds a child containing the exact issue, sets its selection, and checks the selected text before pasting. After a correction, it performs a full reanalysis because Chromium offsets and child elements may have changed.

There is no Teams-specific Quill Delta replacement path. Richly formatted messages are checked, but formatting preservation depends on Teams’ behavior for the selected paste.

## Troubleshooting

- Pause typing before expecting underlines; the child tree is queried only after the editor settles.
- If the indicator shows an issue without an underline, Teams did not expose a usable visible child for that range.
- Code, blockquotes, links, mentions, and channels may be skipped by design.
- A rejected correction indicates selection verification failed. TextWarden stops rather than pasting into an unverified range.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/TeamsBehavior.swift`
- `Sources/ContentParsers/TeamsContentParser.swift`
- `Sources/Positioning/Strategies/TeamsStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
