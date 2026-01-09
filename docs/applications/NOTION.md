# Notion Integration

This document describes how TextWarden handles Notion, an Electron-based productivity and note-taking application.

## Overview

Notion (`notion.id`, `com.notion.id`, `com.notion.desktop`) is an Electron app built on Chromium. TextWarden uses child element tree traversal for accurate underline positioning - the same approach used for Slack and Teams.

TextWarden provides:
1. Visual underlines for grammar errors (partial - see [Virtualization Details](#virtualization-details))
2. Text replacement via browser-style selection + paste
3. Dedicated content parser for UI element filtering

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle IDs | `notion.id`, `com.notion.id`, `com.notion.desktop` |
| Category | Electron |
| Parser Type | Notion (dedicated) |
| Text Replacement | Browser-style (selection + keyboard paste) |
| Visual Underlines | Partial (~50% of blocks) |

### Positioning Strategy

Notion uses the dedicated NotionStrategy:

1. **TextPart Tree Traversal** - Query `AXBoundsForRange` on child `AXStaticText` elements
2. **Skip virtualized blocks** - Blocks without AX children get no underline (but error still tracked)

**Why this approach:** Notion's parent `AXTextArea` returns invalid bounds `(0, y, 0, 0)` for `AXBoundsForRange` queries. Only child `AXStaticText` elements return valid bounds. Due to React/Electron virtualization, ~50% of blocks don't expose these children.

- **Exposed blocks (~50%)**: Pixel-perfect underlines via child element bounds
- **Virtualized blocks (~50%)**: No underline drawn (error still appears in indicator)

### AX Tree Structure

Notion's accessibility tree follows this pattern:

```
AXTextArea (main text area)
└── AXGroup (block container)
    └── AXTextArea (content area)
        └── AXStaticText "Your actual text content..."
            └── AXBoundsForRange(0, N) → ✅ WORKS!
```

Key insight: The parent AXTextArea's `AXBoundsForRange` is broken, but child `AXStaticText` elements return valid bounds.

### Text Replacement

Notion uses browser-style text replacement:

```swift
textReplacementMethod: .browserStyle  // Selection + Cmd+V paste
```

**Replacement Flow:**
1. Select error text using AX selection APIs
2. Copy suggestion to clipboard
3. Paste via Cmd+V keyboard event

### Content Parser

Notion has a dedicated `NotionContentParser` that handles:

- **UI Element Filtering** - Removes "Add icon", "Type '/' for commands", page icons, and other Notion UI text from analysis
- **Block Type Filtering** - Uses allow-list approach to only analyze plain text blocks (see below)
- **Text Offset Calculation** - Tracks character offset from filtered UI elements for accurate position mapping
- **Block Type Detection** - Identifies headers, callouts, toggles via `AXRoleDescription`

```swift
parserType: .notion
```

**Filtered UI Elements:**
- "Add icon", "Add cover", "Add comment"
- "Type '/' for commands" (various quote styles)
- "Write, press 'space' for AI..."
- "Press Enter to continue with an empty page"
- Page icon emojis (1-3 character emoji-only lines)

**Block Type Filtering (Allow-List):**

TextWarden uses an allow-list approach to determine which Notion blocks are analyzed for grammar errors. Only text inside these container types is checked:

| Allowed | Description |
|---------|-------------|
| `group` | Generic containers |
| `text entry area` | Standard text blocks |
| `heading` | Header blocks (H1, H2, H3) |
| `text` | AXStaticText elements |

Text inside other block types is automatically excluded from grammar checking:

| Excluded | Reason |
|----------|--------|
| `figure` | Code blocks - syntax, not prose |
| `blockquote` | Quoted text (may be from external sources) |
| `Tick box` | To-do items (often fragments) |
| `button` | UI elements |

This allow-list approach is more robust than an exclude-list because unknown block types (tables, embeds, etc.) are automatically excluded.

**Code Block Detection:**

Code blocks use a secondary detection method via the zero-width space marker (U+200B). Notion inserts U+200B after code block content, which TextWarden uses to identify and filter code content when it's virtualized (no AX element exposed).

### Font Configuration

```swift
FontConfig(
    defaultSize: 16,
    fontFamily: nil,  // System font
    spacingMultiplier: 1.0
)
horizontalPadding: 0
```

### Block Types

Notion's block types are detected via `AXRoleDescription`:

| Block Type | Role Description | Font Size |
|------------|------------------|-----------|
| H1 Header | `notion-header-block` | 30pt |
| H2 Header | `notion-sub_header-block` | 24pt |
| H3 Header | `notion-sub_sub_header-block` | 20pt |
| Text Block | `notion-text-block` | 16pt |
| Callout | `notion-callout-block` | 15pt |
| Toggle | `notion-toggle-block` | 16pt |
| Page | `notion-page-block` | 16pt |

## Timing Behavior

### Typing Pause Required

Notion uses a 1.0s debounce before analysis:

```swift
requiresTypingPause: true  // Wait for typing pause before querying AX tree
```

This delay prevents interfering with active typing and allows Notion's AX tree to stabilize.

### AX Notifications

```swift
delaysAXNotifications: true  // Notion batches AX notifications
```

Notion batches accessibility notifications, so TextWarden uses keyboard-based typing detection for more responsive updates.

## Behavior Configuration

Notion uses the `NotionBehavior` specification for overlay behavior:

| Behavior | Value |
|----------|-------|
| Underline show delay | 0.15s |
| Bounds validation | Require stable (0.25s) |
| Popover hover delay | 0.3s |
| Popover auto-hide | 3.0s |
| Hide on scroll | Yes |
| Analysis debounce | 1.0s |
| Line height compensation | ×1.1 |
| UTF-16 text indices | Yes |

**Known Quirks:**
- `chromiumEmojiWidthBug` - Emoji width calculation issues
- `virtualizedText(50%)` - Only ~50% of blocks exposed to AX
- `webBasedRendering` - Web-based text rendering
- `batchedAXNotifications` - Notifications are batched
- `requiresBrowserStyleReplacement` - Needs clipboard+paste
- `requiresFullReanalysisAfterReplacement` - Fragile byte offsets

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (Notion section)
- `Sources/AppConfiguration/Behaviors/NotionBehavior.swift`: Behavior specification
- `Sources/ContentParsers/NotionContentParser.swift`: UI element filtering and text preprocessing
- `Sources/Positioning/Strategies/NotionStrategy.swift`: Child element tree traversal positioning
- `Scripts/notion_ax_explorer.swift`: Diagnostic script for AX tree analysis

## Debugging

### Positioning Issues

If underlines appear misaligned, check logs for TextPart building:

```
NotionStrategy uses child element AXBoundsForRange
Check logs for TextPart building and bounds queries
```

Typical log output for exposed blocks (underline drawn):
```
NotionStrategy: Built 5 TextParts
NotionStrategy: AXBoundsForRange on child SUCCESS: (951, 404, 38, 19)
NotionStrategy: SUCCESS (textpart-tree) - bounds: (...)
```

For virtualized blocks (no underline):
```
NotionStrategy: No TextPart for range {87, 4} - block is virtualized, skipping underline (error still in indicator)
```

### UI Element Filtering

If errors appear in page titles or UI placeholders:

```
NotionContentParser: Filtered UI elements, original: 150 chars, remaining: 100 chars, leading offset: 50
```

### Running Diagnostics

Use the diagnostic script to analyze Notion's AX tree:

```bash
# Click in a Notion text block first, then run:
swift Scripts/notion_ax_explorer.swift
```

## Known Limitations

1. **1.0s analysis delay** - Required for AX tree stability; underlines appear after typing pause
2. **Block-based structure** - Each Notion block is separate in the AX tree; multi-block selections not supported
3. **Electron quirks** - Requires full re-analysis after replacement due to fragile byte offsets
4. **Batched AX notifications** - Uses keyboard detection for typing awareness
5. **Scrolled content** - TextPart bounds are validated against visible element frame; scrolled-out errors won't show underlines
6. **Block virtualization** - Notion doesn't expose all text blocks as AX children. Blocks created by pressing Enter may be "virtualized" (present in text but without AXStaticText elements). Errors in these blocks are detected but **no underline is drawn** (see UX Decision below).

### Virtualization Details

When you press Enter in Notion, it creates a new block. However, Notion's accessibility tree doesn't always expose these blocks:

- **Exposed blocks (~50%)**: Have `AXStaticText` children with working `AXBoundsForRange` → Pixel-perfect underline positioning
- **Virtualized blocks (~50%)**: No `AXStaticText` children despite text being in `AXValue` → **No underline drawn**

**Shift+Enter** (soft line break within a block) works correctly since it doesn't create a new block.

**Technical reason**: Notion uses React/Electron with DOM virtualization for performance. Only "active" or recently-edited blocks are fully exposed to the accessibility API.

### UX Decision: Skip Underlines for Virtualized Blocks

For errors in virtualized blocks, TextWarden intentionally **does not draw underlines** rather than showing inaccurate positions. This is a deliberate UX decision:

1. **Interpolated positions are often 10-20px off** - visibly wrong and confusing
2. **Errors still appear in the error indicator** - users can see the count and fix via menu
3. **Clicking the indicator shows all errors** - including those without visual underlines
4. **Better to show nothing than something wrong** - maintains user trust

**Result**: In Notion, you may see fewer underlines than the error count indicates. This is expected behavior for blocks that Notion hasn't exposed to the accessibility API.

**Workaround**: Click into a virtualized block (start typing or editing) - this often causes Notion to expose it to the AX tree, enabling accurate underline positioning on the next analysis cycle

## Related Apps

Notion follows the same Chromium/Electron pattern as:
- **Slack** - SlackStrategy with Quill Delta format
- **Teams** - TeamsStrategy with child element traversal
