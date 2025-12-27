# Microsoft Outlook Integration

This document describes how TextWarden handles Microsoft Outlook's compose windows, including the positioning strategy for visual underlines.

## Overview

Microsoft Outlook uses native macOS components for its text editing interfaces. TextWarden supports two distinct compose contexts:

1. **Subject field (AXTextField)** - Standard text field for email subjects
2. **Compose body (AXTextArea)** - Rich text area for email content

Both element types support the `AXBoundsForRange` accessibility API, enabling pixel-perfect underline positioning.

## Accessibility API Behavior

### Subject Field (AXTextField)

The subject field behaves like a standard macOS text field:
- `AXBoundsForRange` returns accurate character bounds
- No child elements (text is directly in the field)
- Simple positioning with direct API calls

### Compose Body (AXTextArea)

The compose body has a more complex structure:
- `AXBoundsForRange` works on the main element and returns valid bounds
- Contains child elements: `AXGroup` → `AXStaticText` (text runs)
- Child `AXStaticText` elements also support `AXBoundsForRange`

**Example AX tree structure:**
```
[AXTextArea] frame=905,439 755x40
  [AXGroup] frame=906,439 753x39
    [AXStaticText] value='This is a test message...'
    [AXStaticText] value='TextWarden'
    [AXStaticText] value=' properly works together...'
```

## Positioning Strategy

TextWarden uses a dedicated `OutlookStrategy` for Outlook positioning:

### Approach

1. **Primary method**: Use `AXBoundsForRange` directly on the focused element
2. **Fallback 1**: Tree traversal - query bounds on child `AXStaticText` elements
3. **Fallback 2**: Font metrics calculation using Aptos font configuration

### Strategy Selection

The strategy uses element role to determine behavior:
- `AXTextField` (subject) → Direct `AXBoundsForRange`
- `AXTextArea` (body) → Try direct bounds, fall back to tree traversal if needed

### Font Configuration

Outlook uses the Aptos font family by default:
- **Font size**: 12pt
- **Spacing multiplier**: 1.5x (Aptos renders wider than system fonts)
- **Horizontal padding**: 20px (left margin with Copilot sparkle icon)

## Text Replacement

Outlook requires browser-style text replacement to preserve formatting:

### Why AXSetValue Doesn't Work

- `AXSetValue` technically works (text is changed)
- **However, it strips all rich text formatting** (headings, bold, italic, etc.)
- Outlook's compose body is a WebKit-based editor (`ms-outlook-mac-text-editor`)
- Other AX replacement APIs (`AXReplaceRangeWithText`, `AXSelectedText` set) return success but don't actually modify text

### TextWarden Implementation

Uses clipboard-based approach (selection + keyboard paste) to preserve formatting (like Word and PowerPoint)

## Element Filtering

The `OutlookContentParser` identifies valid compose elements by:

### Accepted Elements
- `AXTextArea` (compose body)
- `AXTextField` with "subject" in description/identifier
- Text fields with substantial content (>3 chars)

### Rejected Elements
- Toolbar/ribbon controls (`AXToolbar`, `AXButton`, etc.)
- Font selectors (elements with "font", "Aptos", etc.)
- Menu items and popups
- Address fields (To, Cc, Bcc)
- Elements with toolbar ancestors

## Known Behaviors

### Copilot Integration

When Outlook Copilot is active:
- The element frame may change dynamically
- TextWarden uses `requiresFrameValidation` to detect frame changes
- `defersTextExtraction` prevents AX call accumulation during rapid typing

### mso99 Framework Considerations

Unlike Word and PowerPoint, Outlook's compose editor doesn't crash on parameterized AX queries. This may be due to a different underlying text engine (Word/PowerPoint use mso99 for document editing).

## Implementation Files

- `Sources/Positioning/Strategies/OutlookStrategy.swift`: Positioning strategy
  - `calculateSubjectFieldGeometry()`: Subject field positioning
  - `calculateComposeBodyGeometry()`: Body positioning with fallbacks
  - `calculateTreeTraversalFallback()`: Child element bounds lookup
  - `calculateFontMetricsFallback()`: Font measurement as last resort

- `Sources/ContentParsers/OutlookContentParser.swift`: Element detection
  - `isComposeElement()`: Validate compose context
  - `extractText()`: Safe text extraction (avoids mso99 crashes)
  - `findComposeElement()`: Locate compose body from focused element

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration
  - `preferredStrategies: [.outlook]`: Dedicated strategy only
  - Feature flags for Copilot compatibility

## Debugging

### Position Calculation

Enable debug logging to see positioning in action:

```
OutlookStrategy: Compose body - trying AXBoundsForRange
OutlookStrategy: Body SUCCESS (AXBoundsForRange) - bounds: (906, 500, 35, 20)
```

If you see "trying tree traversal", the direct API failed:

```
OutlookStrategy: Body AXBoundsForRange returned small width (2px) - trying tree traversal
OutlookStrategy: Built 3 TextParts
OutlookStrategy: Body SUCCESS (tree) - bounds: (906, 500, 35, 20)
```

### Element Detection

Check if elements are correctly identified:

```
OutlookContentParser: Checking element - role: AXTextArea, desc: , id: , title:
OutlookContentParser: Accepting - AXTextArea (compose body)
```

### AX Diagnostic Script

Run this diagnostic to inspect Outlook's AX API:

```swift
// Test AXBoundsForRange on focused element
let positions = [(0, 1), (0, 5), (5, 5)]
for (loc, len) in positions {
    if let bounds = testBoundsForRange(element, location: loc, length: len) {
        print("Range(\(loc),\(len)): width=\(bounds.width)px")
    }
}
```

## References

- [macOS Accessibility API Documentation](https://developer.apple.com/documentation/accessibility)
- [Microsoft Office Accessibility](https://support.microsoft.com/en-us/accessibility)
