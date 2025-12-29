# Microsoft Teams Integration

This document describes how TextWarden handles Microsoft Teams' compose windows, including positioning strategy and formatted content detection.

## Overview

Microsoft Teams is a Chromium-based Electron app with the same AX tree structure as Slack. TextWarden uses the same tree traversal approach for precise text positioning.

**Key Discovery**: While Teams' main AXTextArea doesn't support AXBoundsForRange (returns garbage), child AXStaticText elements DO support it - the exact same pattern as Slack.

## Accessibility API Behavior

### Main Element Limitations (Broken)

| API | Behavior |
|-----|----------|
| `AXBoundsForRange` | Returns `(0, y, 0, 0)` - no X position or width |
| `AXBoundsForTextMarkerRange` | Returns entire window frame |

### Child Element Support (Working)

| API | Behavior |
|-----|----------|
| `AXBoundsForRange` on AXStaticText children | Returns correct bounds |
| `AXFrame` on child elements | Returns valid visual frames |
| `AXAttributedStringForRange` | Works for formatting detection |

## Positioning Strategy

TextWarden uses a dedicated `TeamsStrategy` for positioning:

### Approach

1. **Traverse AX tree** to find all AXStaticText elements (text runs)
2. **Build TextPart map**: character ranges to visual frames + element references
3. **For each error**, find overlapping TextPart(s)
4. **Query AXBoundsForRange** on the child element with local range offset
5. **Convert coordinates** from Quartz to Cocoa

### Tree Structure

Teams' editor hierarchy:

```
[AXTextArea] (main compose element)
  └─ [AXGroup] (paragraph)
       └─ [AXStaticText] value="Hello "
       └─ [AXStrongStyleGroup] (bold text)
            └─ [AXStaticText] value="world"
       └─ [AXStaticText] value="!"
  └─ [AXGroup] (another paragraph)
       └─ [AXCodeStyleGroup] (inline code)
            └─ [AXStaticText] value="code"
```

### TextPart Mapping

```swift
private struct TextPart {
    let text: String           // "Hello "
    let range: NSRange         // (0, 6)
    let frame: CGRect          // Visual bounds
    let element: AXUIElement   // Reference for AXBoundsForRange
}
```

## Formatted Content Handling

Teams supports rich text formatting. TextWarden detects and handles formatted content:

### Content EXCLUDED from Grammar Checking

- **Code blocks** (triple backticks) - detected via AXCodeStyleGroup subrole
- **Inline code** (single backticks) - detected via AXBackgroundColor
- **Blockquotes** - detected via AXBlockQuoteLevel attribute
- **Links/URLs** - detected via AXLink child elements
- **Mentions** (@user) - detected via AXBackgroundColor or @ prefix
- **Channels** (#channel) - detected via AXBackgroundColor or # prefix

### Content INCLUDED for Grammar Checking

- **Bold text** - grammar errors should be flagged
- **Italic text** - grammar errors should be flagged
- **Underlined text** - grammar errors should be flagged
- **Strikethrough text** - grammar errors should be flagged

### Detection Methods

1. **AXAttributedStringForRange** - Check for AXBackgroundColor attribute
   - Mentions, channels, and code have colored backgrounds

2. **AXCodeStyleGroup subrole** - Inline code blocks

3. **AXBlockQuoteLevel attribute** - Blockquotes (level > 0)

4. **AXLink child elements** - URLs and hyperlinks

5. **Text pattern matching** - @ and # prefixes for mentions/channels

## Text Replacement

Teams uses browser-style replacement with child element selection (same as Slack):

### Approach

1. **Find child element** containing the error text via `findChildElementContainingText()`
2. **Set selection** on the child element using `AXSelectedTextRange` (not on root element)
3. **Validate selection** by checking `AXSelectedText` matches expected error text
4. **Paste replacement** via clipboard (Cmd+V)

### Selection Validation

Before pasting, TextWarden validates that the selection actually worked:

- If `AXSelectedText` matches the expected error text → proceed with paste
- If mismatch (e.g., error scrolled out of view) → abort and show user message

This prevents incorrect replacements when the error is not visible in the compose area.

### Scrolled-Out Content

When an error is scrolled out of view:

- The child element may not be in the AX tree or selection may fail silently
- TextWarden detects this via selection validation
- Shows a status message: "Scroll to see this error first"
- Does NOT paste to prevent inserting at wrong location

## Configuration

From `AppRegistry.swift`:

```swift
static let teams = AppConfiguration(
    identifier: "teams",
    displayName: "Microsoft Teams",
    bundleIDs: ["com.microsoft.teams2"],
    category: .electron,
    parserType: .teams,
    preferredStrategies: [.teams],  // Dedicated strategy
    features: AppFeatures(
        visualUnderlinesEnabled: true,   // Now enabled!
        textReplacementMethod: .browserStyle,
        requiresTypingPause: true,       // Wait for AX tree to stabilize
        supportsFormattedText: true,
        childElementTraversal: true,
        requiresFullReanalysisAfterReplacement: true
    )
)
```

## Implementation Files

- `Sources/Positioning/Strategies/TeamsStrategy.swift`: Positioning strategy
  - `buildTextPartMap()`: AX tree traversal for text runs
  - `findBoundsForRange()`: Lookup error bounds in TextPart map
  - `calculateSubElementBounds()`: AXBoundsForRange on child element

- `Sources/ContentParsers/TeamsContentParser.swift`: Element detection
  - `extractExclusions()`: Detect formatted content to exclude
  - `detectLinks()`: Find AXLink child elements
  - `detectCodeStyleGroups()`: Find AXCodeStyleGroup subroles
  - `detectBlockQuotes()`: Check AXBlockQuoteLevel attribute

## Debugging

### Position Calculation

```
TeamsStrategy: Calculating for range (10, 5) in text length 50
TeamsStrategy: Built 8 TextParts
TeamsStrategy: AXBoundsForRange on child SUCCESS: (450, 300, 35, 16)
TeamsStrategy: SUCCESS (textpart-tree) - bounds: (450, 500, 35, 16)
```

### Exclusion Detection

```
TeamsContentParser: Extracting exclusions via Accessibility APIs
TeamsContentParser: AXBackgroundColor found 2 exclusions
TeamsContentParser: Found code block at 25-35
TeamsContentParser: Detected 3 total exclusion ranges
```

## Comparison with Slack

| Feature | Slack | Teams |
|---------|-------|-------|
| App Type | Electron/Chromium | Electron/Chromium |
| Main element AXBoundsForRange | Broken | Broken |
| Child AXStaticText | Working | Working |
| Strategy | SlackStrategy | TeamsStrategy |
| Code detection | AXCodeStyleGroup | AXCodeStyleGroup |
| Bold/formatting | AXStrongStyleGroup | AXStrongStyleGroup |
| Link detection | AXLink | AXLink |

## Known Behaviors

### AX Tree Async Updates

Teams' AX tree updates asynchronously after user interactions. The `requiresTypingPause: true` setting ensures we wait for the tree to stabilize before querying positions.

### Scroll Handling

Teams has scrollable compose areas. TextWarden handles scrolling:

- **On scroll start**: Underlines are hidden immediately to prevent misalignment
- **After scroll stops** (300ms debounce): Positions are recalculated and underlines redrawn
- **Formatting changes** (Cmd+B/I/U): Strategy cache is cleared, positions recalculated

### Multi-Line Errors

For errors spanning multiple TextParts (across paragraph boundaries), TeamsStrategy unions the bounds of all overlapping parts.

### Cache Management

TeamsStrategy maintains a TextPart cache for performance:

- Cache key: text hash + element frame
- Cache is cleared on:
  - Formatting changes (bold, italic, etc.)
  - Scroll events
  - Position refresh requests

## References

- [Chromium Accessibility](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/accessibility/)
- [Electron Accessibility](https://www.electronjs.org/docs/latest/tutorial/accessibility)
