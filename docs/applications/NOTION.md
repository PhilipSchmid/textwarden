# TextWarden for Notion on macOS

TextWarden adds local grammar checking and writing assistance to the Notion desktop app. The integration filters Notion interface text and uses exposed block children for grammar underlines.

## Support summary

| Item | Current behavior |
|------|------------------|
| Application | Notion Desktop |
| Bundle IDs | `notion.id`, `com.notion.id`, `com.notion.desktop` |
| App type | Electron |
| Checked content | Supported editable page blocks |
| Visual underlines | Partial; configured estimate is about 50% of blocks |
| Content parser | `NotionContentParser` |
| Positioning | Dedicated `NotionStrategy` |
| Correction method | Select the text, then paste with `Command-V` |

## What TextWarden checks

Notion mixes page content, block controls, placeholders, and decorative text in one Accessibility value. `NotionContentParser` removes known interface strings such as “Add icon” and command placeholders. It also excludes content in disallowed block containers, including detected to-do items and blockquotes.

Code blocks are detected through Notion’s zero-width-space boundary marker. Bulleted and numbered list items are also filtered by the current parser. Replaced ranges keep their scalar length so grammar-engine offsets still map back to the source text.

The allow-list accepts generic groups, text-entry areas, headings, and static text. Unknown container roles are skipped instead of being treated as prose.

## Why underline coverage is partial

Notion’s root text value can contain blocks that have no corresponding `AXStaticText` child. `NotionStrategy` builds a map from exposed child text to source ranges and asks each child for local `AXBoundsForRange` geometry.

When a block has no usable child element, TextWarden still keeps the grammar error in the indicator but marks visual positioning unavailable. It does not estimate a location because an incorrect underline is worse than no underline. The behavior model records this as roughly 50% visual coverage, not as a per-page guarantee.

Bounds are also rejected when they fall outside the visible editor frame. Scrolled-out content can remain in the Accessibility value even when it is not safe to draw.

## Timing and corrections

Notion requires a typing pause and uses a 1-second analysis debounce. Accessibility notifications are batched, so TextWarden also uses keyboard activity to know when the editor is changing.

Corrections use browser-style selection and paste. The integration treats content as plain text for replacement and performs a full reanalysis afterward.

## Troubleshooting

- If the indicator lists an error without an underline, that block is probably present in the root text but absent from Notion’s child Accessibility tree.
- Wait one second after typing before judging underline coverage.
- Lists, to-do items, code blocks, blockquotes, and unknown block types may be skipped by design.
- If a correction cannot verify its selection, TextWarden cancels it instead of changing another block.

## Implementation

- `Sources/AppConfiguration/AppRegistry.swift`
- `Sources/AppConfiguration/Behaviors/NotionBehavior.swift`
- `Sources/ContentParsers/NotionContentParser.swift`
- `Sources/Positioning/Strategies/NotionStrategy.swift`
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`
