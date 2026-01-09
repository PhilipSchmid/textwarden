# Apple Mail Integration

This document describes how TextWarden handles Apple Mail's compose windows, including positioning strategy and format-preserving text replacement.

## Overview

Apple Mail uses WebKit for its compose windows, providing rich text editing capabilities. TextWarden supports:

1. **Compose body (AXWebArea)** - WebKit-based rich text area for email content
2. **Subject field** - Standard text field (handled by generic strategies)

The compose body requires special handling due to WebKit's unique accessibility API behavior.

## Accessibility API Behavior

### Compose Detection

Mail's UI includes multiple contexts where text appears:
- **Main viewer** - Reading emails (read-only, should be skipped)
- **Sidebar/list** - Email list and folders (read-only, should be skipped)
- **Compose window** - Writing new emails (editable, should be monitored)

The `MailContentParser` distinguishes these by checking:
- `AXWebArea` with `AXValueIsSettable = true` indicates a compose window
- Parent window title or presence of "main viewer" indicators

### WebKit Element Structure

Mail's compose body exposes text through child `AXStaticText` elements:

```
[AXWebArea] description="message body"
  └─ [AXStaticText] value="Hello,"
  └─ [AXGroup]
       └─ [AXStaticText] value="How about "
       └─ [AXStaticText] value="meeting"
       └─ [AXStaticText] value=" tomorrow?"
  └─ [AXGroup]
       └─ [AXStaticText] value="Regards,"
  └─ [AXGroup]
       └─ [AXStaticText] value="Philip"
```

Each paragraph is typically wrapped in an `AXGroup`, with text runs as `AXStaticText` children.

### UTF-16 Index Conversion

Mail's WebKit accessibility APIs use UTF-16 code units (not grapheme clusters):

- Emoji like `👋` = 1 grapheme but 2 UTF-16 units
- Error positions from Harper are in grapheme clusters
- All range-based API calls require conversion via `TextIndexConverter.graphemeToUTF16Range()`

## Positioning Strategy

TextWarden uses a dedicated `MailStrategy` for positioning:

### Approach

1. Convert grapheme cluster indices to UTF-16 code units
2. Create TextMarkers for start and end positions using `AXTextMarkerForIndex`
3. Query bounds using `AXBoundsForRange` with UTF-16 indices
4. Convert Quartz screen coordinates to Cocoa coordinates

### TextMarker-Based Selection

Mail's WebKit properly supports TextMarker APIs:

```swift
// Create markers for positions
let startMarker = AXTextMarkerForIndex(element, startIndex)
let endMarker = AXTextMarkerForIndex(element, endIndex)

// Create marker range
let markerRange = AXTextMarkerRangeForUnorderedTextMarkers(element, [startMarker, endMarker])

// Set selection
AXUIElementSetAttributeValue(element, "AXSelectedTextMarkerRange", markerRange)
```

### Coordinate Conversion

WebKit may return bounds in either layout coordinates or screen coordinates. The strategy detects this heuristically:

- Small X values (< 200px) likely indicate layout coordinates
- `AccessibilityBridge.convertLayoutRectToScreen()` handles conversion when needed

## Text Replacement

### Broken AX APIs

Mail's WebKit accessibility APIs for text replacement are non-functional:

| API | Behavior |
|-----|----------|
| `AXReplaceRangeWithText` | Returns error -25212 (kAXErrorNoValue) |
| `AXSelectedText` (set) | Returns success but **silently fails** - text unchanged |
| `AXValue` (set) | Returns success but **silently fails** - text unchanged |

### TextWarden Implementation

Uses selection + keyboard typing to preserve formatting:

1. **Select text** using `AXSelectedTextMarkerRange` (works correctly)
2. **Activate Mail** to ensure keyboard events are received
3. **Type replacement** using `CGEvent` keyboard simulation
4. **Inherit formatting** - typed text takes on the formatting of the selection

This is standard behavior for rich text editors on macOS.

### Why This Preserves Formatting

When you select formatted text (e.g., bold) and type, the new characters inherit the formatting attributes of the selection. This is standard behavior in rich text editors.

## Element Filtering

The `MailContentParser` identifies valid compose elements:

### Accepted Elements

- `AXWebArea` with `description = "message body"` and `AXValueIsSettable = true`
- Must be in a compose window (not the main viewer)

### Rejected Elements

- Main viewer web areas (reading emails)
- Sidebar and list elements
- Search fields
- Toolbar and menu elements

### Compose Window Detection

```swift
// Check if this is a compose window (not viewer)
let isSettable = AXUIElementIsAttributeSettable(element, kAXValueAttribute)
let description = getStringAttribute(element, kAXDescriptionAttribute)

if role == "AXWebArea" && description == "message body" && isSettable {
    // This is a compose window
}
```

## Known Behaviors

### AXNumberOfCharacters Not Available

Mail's WebKit doesn't support `AXNumberOfCharacters`. Text length is obtained by:

1. Trying `AXStringForRange` with a large range (100,000)
2. The API returns the actual text up to the document length

### Paragraph Structure

Mail wraps paragraphs in `AXGroup` elements. Text runs within paragraphs appear as separate `AXStaticText` children. This affects how text is traversed but not positioning.

### Formatting Refresh

When users apply formatting (bold, italic, etc.), text layout changes. TextWarden handles this via:

- **Keyboard shortcuts** (Cmd+B, Cmd+I, Cmd+U) - detected and trigger position refresh
- **Toolbar buttons** - detected via click monitoring, triggers debounced refresh

## Behavior Configuration

Mail uses the `MailBehavior` specification for overlay behavior:

| Behavior | Value |
|----------|-------|
| Underline show delay | 0.1s |
| Bounds validation | Require within screen |
| Popover hover delay | 0.3s |
| Popover auto-hide | 3.0s |
| Hide on scroll | Yes |
| Analysis debounce | 0.5s |
| UTF-16 text indices | Yes |

**Known Quirks:**
- `focusBouncesDuringPaste` - Focus changes during paste operations
- `requiresBrowserStyleReplacement` - Needs clipboard+paste
- `requiresFullReanalysisAfterReplacement` - AX state changes after paste
- `usesMailReplaceRangeAPI` - Special Mail replacement handling

## Implementation Files

- `Sources/AppConfiguration/Behaviors/MailBehavior.swift`: Behavior specification
- `Sources/Positioning/Strategies/MailStrategy.swift`: Positioning strategy
  - `calculateGeometry()`: UTF-16 conversion and bounds calculation
  - `getBoundsForRange()`: WebKit bounds with coordinate conversion
  - `convertToUTF16Range()`: Grapheme to UTF-16 index conversion

- `Sources/ContentParsers/MailContentParser.swift`: Element detection and text replacement
  - `isComposeElement()`: Validate compose context vs viewer
  - `extractText()`: Text extraction with fallback for missing `AXNumberOfCharacters`
  - `selectTextForReplacement()`: TextMarker-based selection
  - `replaceText()`: Returns false to force keyboard fallback

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration
  - `preferredStrategies: [.mail]`: Dedicated strategy only
  - `supportsFormattedText: true`: Enables formatting detection

## Debugging

### Position Calculation

```
MailStrategy: Calculating for range (10, 5) in text length 50
MailStrategy: Converted grapheme [10, 5] to UTF-16 [10, 5]
MailStrategy: SUCCESS - bounds: (950, 400, 35, 16)
```

### Text Replacement

```
MailContentParser: replaceText - Mail's AX APIs are broken, using keyboard fallback
MailContentParser: selectTextForReplacement range: 10-15
MailContentParser: Selection via AXSelectedTextMarkerRange succeeded
```

### Element Detection

```
MailContentParser: Checking element - role: AXWebArea, desc: message body
MailContentParser: Accepting - web area AXValue is settable (composition)
MailContentParser: AXStringForRange succeeded (127 chars)
```

## References

- [WebKit Accessibility](https://webkit.org/accessibility/)
- [macOS Accessibility API Documentation](https://developer.apple.com/documentation/accessibility)
