# Microsoft PowerPoint Integration

This document describes how TextWarden handles Microsoft PowerPoint on macOS.

## Overview

Microsoft PowerPoint (`com.microsoft.Powerpoint`) is a native macOS application. TextWarden provides grammar checking and visual underlines for the **Notes section only**.

**Important Limitation:** Slide text boxes are NOT accessible via macOS Accessibility API. This is a limitation of Microsoft's PowerPoint implementation, not TextWarden.

## What Works

| Feature | Notes Section | Slide Text Boxes |
|---------|---------------|------------------|
| Grammar checking | ✅ Yes | ❌ No |
| Visual underlines | ✅ Yes | ❌ No |
| Text replacement | ✅ Yes | ❌ No |
| Error indicator capsule | ✅ Yes | ❌ No |

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `com.microsoft.Powerpoint` |
| Category | Native macOS |
| Parser Type | PowerPoint (dedicated) |
| Text Replacement | Browser-style (selection + keyboard paste) |
| Visual Underlines | Supported (Notes only) |

### Accessibility API Findings

PowerPoint's accessibility tree exposes different levels of access for different areas:

**Notes Section:**
- Accessible via `AXTextArea` element
- Full `AXBoundsForRange` support for precise underline positioning
- `AXValue` contains the notes text
- Parent chain: `AXLayoutItem` (desc="Slide Notes") → `AXLayoutArea` (desc="Notes Pane")

**Slide Editor:**
- Returns `AXLayoutArea` with `AXNumberOfCharacters: 0`
- Text boxes are NOT exposed, even when editing
- No `AXTextArea` or `AXTextField` children appear
- This is consistent whether clicking, double-clicking, or actively editing text

### Why Slide Text is Inaccessible

Microsoft's PowerPoint implementation does not expose slide content through macOS Accessibility APIs. Testing confirms:

1. **No text elements in slide area** - The "Slide Editor Pane" `AXLayoutArea` has 0 children
2. **No focused element changes** - Clicking into a text box doesn't create accessible text elements
3. **Element at position returns layout area** - Even hovering over visible text returns the parent `AXLayoutArea`, not a text element
4. **System-wide checks confirm** - Both app-level and system-wide accessibility queries return no text content

This appears to be a deliberate design choice by Microsoft - likely because slide content uses a custom rendering system that doesn't integrate with macOS accessibility.

### Positioning Strategy

TextWarden uses a dedicated `PowerPointStrategy` for the Notes section:

```swift
preferredStrategies: [.powerpoint]
```

**How it works:**
1. Detect Notes `AXTextArea` via `PowerPointContentParser.isSlideElement()`
2. Use direct `AXBoundsForRange` queries for character-level positioning
3. Support multi-line bounds for errors spanning multiple lines
4. Convert Quartz coordinates to Cocoa for accurate overlay positioning

### Text Replacement

PowerPoint uses browser-style text replacement:

```swift
textReplacementMethod: .browserStyle  // Selection + Cmd+V paste
```

Standard `AXValue` setting doesn't work reliably, so corrections are applied via:
1. Select the error range in the Notes text area
2. Copy the suggestion to clipboard
3. Paste via simulated Cmd+V

### Font Configuration

```swift
FontConfig(
    defaultSize: 18,      // Notes default font size
    fontFamily: nil,      // System font
    spacingMultiplier: 1.0
)
horizontalPadding: 4
```

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration
- `Sources/ContentParsers/PowerPointContentParser.swift`: Content parser for Notes detection
- `Sources/Positioning/Strategies/PowerPointStrategy.swift`: AXBoundsForRange-based positioning

## Usage Tips

1. **Use the Notes section** - This is where TextWarden can help with grammar checking
2. **Notes appear below the slide** - Make sure the Notes pane is visible (View → Notes)
3. **Speaker notes benefit from proofreading** - Catch typos before your presentation

## Comparison with Other Apps

| App | Text Accessible? | Underlines? | Strategy |
|-----|------------------|-------------|----------|
| PowerPoint Notes | ✅ Yes | ✅ Yes | PowerPointStrategy |
| PowerPoint Slides | ❌ No | ❌ No | N/A |
| Word | ✅ Yes | ✅ Yes | WordStrategy |
| Outlook | ✅ Yes | ✅ Yes | OutlookStrategy |

## Debugging

### Notes Section Not Working

If grammar checking isn't working in Notes:

1. **Ensure Notes pane is visible** - View → Notes
2. **Click inside the Notes area** - The cursor should be in the notes text
3. **Check logs for PowerPointStrategy**:
   ```
   PowerPointStrategy: Calculating for range...
   PowerPointStrategy: SUCCESS - bounds: ...
   ```

### Common Log Messages

```
PowerPointContentParser: Accepting - AXTextArea (Notes)
PowerPointStrategy: SUCCESS - bounds: (951.0, 812.0, 26.0, 16.0)
```

## Known Limitations

1. **Slide text not accessible** - Microsoft limitation, cannot be worked around
2. **Presenter view** - May not work in presenter/slideshow mode
3. **Embedded objects** - Text in shapes, SmartArt, etc. not accessible

## References

- [Microsoft Office Accessibility](https://support.microsoft.com/en-us/office/accessibility-support-for-powerpoint-9d2b646d-0b79-4135-a570-b8c7ad33ac2f)
- This behavior is consistent with how Grammarly handles PowerPoint on macOS (Notes only)
