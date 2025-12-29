# Apple Pages Integration

This document describes how TextWarden handles Apple Pages, the native macOS word processor from the iWork suite.

## Overview

Apple Pages (`com.apple.iWork.Pages`) is a native macOS application. TextWarden provides full grammar checking and visual underlines using the RangeBounds positioning strategy and Office-style text replacement.

TextWarden provides:
1. Visual underlines for grammar errors
2. Text replacement via Office-style selection + keyboard paste
3. Generic content parser (no dedicated parser needed)

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `com.apple.iWork.Pages` |
| Category | Native |
| Parser Type | Generic |
| Text Replacement | Office-style (focus + selection + Cmd+V paste) |
| Visual Underlines | Full support |

### Positioning Strategy

Pages uses the RangeBoundsStrategy:

```swift
preferredStrategies: [.rangeBounds, .lineIndex, .fontMetrics]
```

**Why this approach:** Pages exposes text in standard `AXTextArea` elements where `AXBoundsForRange` works reliably for position queries. No dedicated strategy is needed.

### AX Tree Structure

Pages' accessibility tree for text editing:

```
AXApplication (Pages)
└── AXWindow
    └── AXSplitGroup
        └── AXScrollArea (document canvas)
            └── AXLayoutArea (when editing a text box)
                └── AXTextArea (text content)
                    └── AXValue: "Your document text..."
                    └── AXBoundsForRange(0, N) → ✅ WORKS!
```

Key insight: When clicking in a text box to edit, Pages exposes the text via `AXTextArea`. The document canvas (`AXScrollArea`) itself doesn't expose text content until you enter edit mode.

### Text Replacement

Pages uses Office-style text replacement (same as Microsoft Word):

```swift
textReplacementMethod: .browserStyle  // Routes through Office-style path
```

**Why Office-style:** Standard AX `setValue` on `AXSelectedText` reports success but doesn't actually change the text in Pages. The clipboard-based approach with explicit focus works reliably.

**Replacement Flow:**
1. Focus the text element via `AXFocusedAttribute`
2. Set selection range via `AXSelectedTextRangeAttribute` (grapheme indices)
3. Activate the Pages app to ensure keyboard events reach it
4. Copy suggestion to clipboard
5. Paste via Cmd+V keyboard event
6. Restore original clipboard contents

### Font Configuration

```swift
FontConfig(
    defaultSize: 12,
    fontFamily: nil,  // System font
    spacingMultiplier: 1.0
)
horizontalPadding: 0
```

## Timing Behavior

### Typing Pause

Pages does not require a typing pause:

```swift
requiresTypingPause: false  // AX APIs respond quickly
```

### AX Notifications

```swift
delaysAXNotifications: false  // Pages sends AX notifications promptly
```

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (Pages section)
- `Sources/App/AnalysisCoordinator+TextReplacement.swift`: Office-style replacement path

## Debugging

### Positioning Issues

If underlines appear misaligned:

```
Pages uses RangeBoundsStrategy with direct AXBoundsForRange queries
Check logs for bounds calculations and coordinate conversion
```

Typical log output:
```
RangeBoundsStrategy: Successfully calculated bounds: (X, Y, W, H)
PositionResolver: Strategy RangeBounds succeeded with confidence 0.9
```

### Text Replacement

Office-style replacement logs:
```
Office-style: Using focused clipboard replacement at X-Y for Pages
Office: Selection set successfully
Office: Activated Pages
Office: Pasted via Cmd+V
```

## Known Limitations

1. **Edit mode required** - Text is only accessible when actively editing a text box (clicking in the document canvas)
2. **Formatting preservation** - Text replacement uses clipboard paste which generally preserves formatting
3. **Headers/Footers** - Currently monitors main document text; header/footer text boxes work the same way when editing

## Related Apps

Pages is part of the Apple iWork suite:
- **Keynote** - May work similarly (not yet tested)
- **Numbers** - Spreadsheet cells may have different AX structure (not tested)
