# ChatGPT Integration

This document describes how TextWarden handles ChatGPT, OpenAI's Electron-based desktop application.

## Overview

ChatGPT (`com.openai.chat`) is an Electron app that provides a native desktop experience for OpenAI's ChatGPT. TextWarden uses direct AX APIs for fast, accurate positioning.

TextWarden provides:
1. Visual underlines for grammar errors
2. Text replacement via browser-style selection + paste
3. Fast analysis with minimal debounce delay

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `com.openai.chat` |
| Category | Electron |
| Parser Type | Generic |
| Text Replacement | Browser-style (selection + keyboard paste) |
| Visual Underlines | Supported |

### Positioning Strategy

ChatGPT uses `AXBoundsForRange` as the primary positioning method:

1. **RangeBounds** (primary) - Direct `AXBoundsForRange` queries for pixel-perfect positioning
2. **TextMarker** - Fallback using Apple's text marker API
3. **ElementTree** - Child element traversal
4. **LineIndex** - Line-based calculation as last resort

**Why RangeBounds works:** Unlike some Electron apps, ChatGPT's accessibility implementation properly supports `AXBoundsForRange`, allowing direct position queries without cursor manipulation.

### Text Replacement

ChatGPT uses browser-style text replacement:

```swift
textReplacementMethod: .browserStyle  // Selection + Cmd+V paste
```

**Replacement Flow:**
1. Select error text using AX selection APIs
2. Copy suggestion to clipboard
3. Paste via Cmd+V keyboard event

### Font Configuration

```swift
FontConfig(
    defaultSize: 16,
    fontFamily: nil,  // System font
    spacingMultiplier: 1.0
)
horizontalPadding: 12
```

## Performance Optimizations

### Fast Debounce

ChatGPT uses the default 50ms debounce (not the 1.0s Chromium debounce):

```swift
requiresTypingPause: false  // Uses rangeBounds, no cursor manipulation needed
```

This means underlines appear almost instantly after typing stops, unlike apps that require cursor-based positioning.

### AX Notification Handling

```swift
delaysAXNotifications: true  // ChatGPT batches AX notifications
```

ChatGPT batches accessibility notifications, so TextWarden uses keyboard-based typing detection for more responsive updates.

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (line ~173)
- `Sources/Positioning/Strategies/RangeBoundsStrategy.swift`: Primary positioning strategy

## Debugging

### Positioning Issues

If underlines appear misaligned:

```
ChatGPT uses RangeBoundsStrategy (AXBoundsForRange)
Check logs for strategy selection and bounds calculation
```

Typical log output:
```
PositionResolver: Trying rangeBounds for ChatGPT
RangeBoundsStrategy: SUCCESS - bounds from AXBoundsForRange
```

### Text Replacement

Browser-style replacement logs:
```
AnalysisCoordinator: Using browser-style text replacement
```

## Known Limitations

1. **Plain text only** - ChatGPT input doesn't support rich text formatting
2. **Delayed AX notifications** - Uses keyboard detection for typing awareness
3. **Electron quirks** - Requires full re-analysis after replacement due to fragile byte offsets
