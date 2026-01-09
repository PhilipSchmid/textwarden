# Perplexity Integration

This document describes how TextWarden handles Perplexity, an Electron-based AI search desktop application.

## Overview

Perplexity (`ai.perplexity.mac`) is an Electron app that provides AI-powered search and answers. TextWarden uses anchor-based positioning for accurate underline placement.

TextWarden provides:
1. Visual underlines for grammar errors
2. Text replacement via browser-style selection + paste
3. Fast analysis with minimal debounce delay

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `ai.perplexity.mac` |
| Category | Electron |
| Parser Type | Generic |
| Text Replacement | Browser-style (selection + keyboard paste) |
| Visual Underlines | Supported |

### Positioning Strategy

Perplexity uses AnchorSearchStrategy as the primary positioning method:

1. **AnchorSearch** (primary) - Searches for anchor points in the AX tree
2. **TextMarker** - Apple's text marker API as fallback
3. **ElementTree** - Child element traversal

**Why AnchorSearch:** Perplexity's `AXBoundsForRange` and ChromiumStrategy don't return reliable results. The AnchorSearchStrategy finds positioning anchors through alternative AX queries.

### Text Replacement

Perplexity uses browser-style text replacement:

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

Perplexity uses the default 50ms debounce (not the 1.0s Chromium debounce):

```swift
requiresTypingPause: false  // Uses anchorSearch, no cursor manipulation needed
```

This means underlines appear almost instantly after typing stops.

### AX Notification Handling

```swift
delaysAXNotifications: true  // Electron app batches AX notifications
```

Perplexity batches accessibility notifications, so TextWarden uses keyboard-based typing detection for more responsive updates.

## Behavior Configuration

Perplexity uses the `PerplexityBehavior` specification for overlay behavior:

| Behavior | Value |
|----------|-------|
| Underline show delay | 0.1s |
| Bounds validation | Require within screen |
| Popover hover delay | 0.3s |
| Popover auto-hide | 3.0s |
| Hide on scroll | Yes |
| Analysis debounce | 1.0s |
| UTF-16 text indices | Yes |

**Known Quirks:**
- `chromiumEmojiWidthBug` - Emoji width calculation issues
- `webBasedRendering` - Web-based text rendering
- `batchedAXNotifications` - Notifications are batched
- `requiresBrowserStyleReplacement` - Needs clipboard+paste
- `requiresFullReanalysisAfterReplacement` - Fragile byte offsets
- `requiresDirectTypingAtPosition0` - Special handling for position 0

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (line ~203)
- `Sources/AppConfiguration/Behaviors/PerplexityBehavior.swift`: Behavior specification
- `Sources/Positioning/Strategies/AnchorSearchStrategy.swift`: Primary positioning strategy

## Debugging

### Positioning Issues

If underlines appear misaligned:

```
Perplexity uses AnchorSearchStrategy
Check logs for anchor point detection
```

Typical log output:
```
PositionResolver: Trying anchorSearch for Perplexity
AnchorSearchStrategy: Found anchor at position X
```

### Text Replacement

Browser-style replacement logs:
```
AnalysisCoordinator: Using browser-style text replacement
```

## Related Apps

Perplexity also has a browser called **Perplexity Comet** (`ai.perplexity.comet`), which is handled by the generic browser configuration.

## Known Limitations

1. **Plain text only** - Perplexity input doesn't support rich text formatting
2. **Delayed AX notifications** - Uses keyboard detection for typing awareness
3. **Electron quirks** - Requires full re-analysis after replacement due to fragile byte offsets
4. **Limited positioning APIs** - AXBoundsForRange doesn't work reliably, uses anchor search instead
