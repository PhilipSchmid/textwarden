# Microsoft Word Integration

This document describes how TextWarden handles Microsoft Word, the native macOS Office application.

## Overview

Microsoft Word (`com.microsoft.Word`) is a native macOS application that uses Microsoft's Office framework (mso99). TextWarden provides full grammar checking and visual underlines using a dedicated positioning strategy.

TextWarden provides:
1. Visual underlines for grammar errors
2. Text replacement via browser-style selection + paste
3. Dedicated content parser for toolbar/ribbon filtering

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `com.microsoft.Word` |
| Category | Native |
| Parser Type | Word (dedicated) |
| Text Replacement | Browser-style (selection + keyboard paste) |
| Visual Underlines | Full support (Word 16.104+) |

### Positioning Strategy

Word uses the dedicated WordStrategy:

```swift
preferredStrategies: [.word]
```

**Why this approach:** Word's AXTextArea is a flat element containing all document text (no child elements unlike Outlook). The `AXBoundsForRange` API works reliably on Word 16.104+ for direct position queries. If the dedicated strategy fails, the PositionResolver automatically falls back to other strategies.

### AX Tree Structure

Word's accessibility tree is straightforward:

```
AXApplication (Microsoft Word)
└── AXWindow
    └── AXSplitGroup
        └── AXScrollArea
            └── AXTextArea (document body)
                └── AXValue: "Your document text..."
                └── AXBoundsForRange(0, N) → ✅ WORKS!
```

Key insight: Unlike Outlook (which has AXStaticText children), Word exposes all text in a single AXTextArea element. All standard AX APIs work directly on this element.

### Text Replacement

Word uses browser-style text replacement:

```swift
textReplacementMethod: .browserStyle  // Selection + Cmd+V paste
```

**Why browser-style:** Standard AX `setValue` doesn't work reliably for Word. The clipboard-based approach preserves formatting.

**Replacement Flow:**
1. Select error text using AX selection APIs
2. Copy suggestion to clipboard
3. Paste via Cmd+V keyboard event
4. Original formatting is preserved

### Content Parser

Word has a dedicated `WordContentParser` that handles:

- **Toolbar/Ribbon Filtering** - Excludes toolbar controls from monitoring
- **Font Selector Filtering** - Filters "Aptos (Body)" and similar dropdown values
- **Document Element Detection** - Validates AXTextArea is the document, not UI

```swift
parserType: .word
```

**Filtered UI Elements:**
- Toolbar and ribbon controls
- Font selector dropdowns
- Menu items and popups
- Elements with toolbar ancestors (up to 10 levels deep)

### Font Configuration

```swift
FontConfig(
    defaultSize: 12,
    fontFamily: nil,  // System font
    spacingMultiplier: 1.0
)
horizontalPadding: 4
```

## Timing Behavior

### Typing Pause

Word does not require a typing pause:

```swift
requiresTypingPause: false  // AX APIs are fast enough for real-time
```

### AX Notifications

```swift
delaysAXNotifications: false  // Word sends AX notifications promptly
```

Word's accessibility implementation is responsive and reliable.

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (Word section)
- `Sources/ContentParsers/WordContentParser.swift`: Toolbar/ribbon filtering
- `Sources/Positioning/Strategies/WordStrategy.swift`: Direct AXBoundsForRange positioning

## Debugging

### Positioning Issues

If underlines appear misaligned:

```
WordStrategy uses direct AXBoundsForRange on document AXTextArea
Check logs for bounds queries and coordinate conversion
```

Typical log output:
```
WordStrategy: Calculating for range {5, 7} in text length 264
WordStrategy: SUCCESS - bounds: (123.0, 456.0, 78.0, 20.0)
```

### Content Parser

If errors appear in toolbar or font selector:

```
WordContentParser: Checking element - role: AXTextArea, subrole: ...
WordContentParser: Rejecting - toolbar/ribbon element
```

## Known Limitations

1. **Formatting preservation** - Text replacement uses clipboard paste which generally preserves formatting, but complex formatting may occasionally be affected
2. **Large documents** - Very large documents may have slower AX API responses
3. **Headers/Footers** - Currently monitors main document body; header/footer editing uses same strategy

## Version Compatibility

Visual underlines require Word 16.104 or later. Earlier versions may have AX API limitations.

| Word Version | Grammar Checking | Visual Underlines |
|--------------|-----------------|-------------------|
| 16.104+ | Full | Full |
| Earlier | Full | May vary |

## Related Apps

Word shares patterns with other Microsoft Office applications:
- **Outlook** - OutlookStrategy with child element traversal (compose body has AXStaticText children)
- **PowerPoint** - Limited to Notes section (slide text not accessible via AX API)
- **Excel** - Not supported (spreadsheet cells have different AX structure)
