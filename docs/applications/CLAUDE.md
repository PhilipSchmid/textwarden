# Claude Integration

This document describes how TextWarden handles Claude, Anthropic's Electron-based desktop application.

## Overview

Claude (`com.anthropic.claudefordesktop`) is an Electron app that provides a native desktop experience for Anthropic's Claude AI. Due to AX API quirks, TextWarden uses cursor-based positioning for accurate underline placement.

TextWarden provides:
1. Visual underlines for grammar errors
2. Text replacement via browser-style selection + paste
3. Dedicated content parser for Claude-specific handling

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `com.anthropic.claudefordesktop` |
| Category | Electron |
| Parser Type | Claude (dedicated) |
| Text Replacement | Browser-style (selection + keyboard paste) |
| Visual Underlines | Supported |

### Positioning Strategy

Claude uses the ChromiumStrategy which requires cursor manipulation:

1. **Chromium** (primary) - Selection-based marker range positioning
2. **TextMarker** - Apple's text marker API
3. **RangeBounds** - Direct `AXBoundsForRange` queries
4. **ElementTree** - Child element traversal
5. **LineIndex** - Line-based calculation as last resort

**Why ChromiumStrategy:** Claude's `AXBoundsForRange` returns inconsistent results in some scenarios. The ChromiumStrategy sets a temporary selection to get accurate bounds via `AXBoundsForTextMarkerRange`, then restores the original cursor position.

### Text Replacement

Claude uses browser-style text replacement:

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

## Dedicated Content Parser

Claude has a dedicated `ClaudeContentParser` that handles:

- **Selection offset calculation** - Adjusts for newline handling differences
- **UTF-16 index conversion** - Proper emoji and special character support
- **Text extraction** - Optimized for Claude's AX tree structure

```swift
parserType: .claude  // Dedicated parser without Slack's newline quirks
```

## Timing Behavior

### Typing Pause Required

Claude uses a 1.0s debounce before analysis:

```swift
requiresTypingPause: true  // ChromiumStrategy requires cursor manipulation
```

This delay is necessary because:
1. ChromiumStrategy temporarily moves the cursor to measure positions
2. Moving the cursor during active typing would interfere with user input
3. The 1.0s pause ensures typing has stopped before position queries

### AX Notifications

```swift
delaysAXNotifications: false  // Claude sends AX notifications promptly
```

Unlike ChatGPT, Claude sends accessibility notifications reliably.

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (line ~143)
- `Sources/ContentParsers/ClaudeContentParser.swift`: Dedicated parser
- `Sources/Positioning/Strategies/ChromiumStrategy.swift`: Primary positioning strategy

## Debugging

### Positioning Issues

If underlines appear misaligned:

```
Claude uses ChromiumStrategy (selection-based marker positioning)
Check logs for cursor save/restore and selection range
```

Typical log output:
```
ChromiumStrategy: Saving cursor position
ChromiumStrategy: Setting selection for grapheme range (5, 10)
ChromiumStrategy: Restoring cursor position
```

### Text Replacement

Browser-style replacement logs:
```
AnalysisCoordinator: Using browser-style text replacement
```

## Known Limitations

1. **1.0s analysis delay** - Required for cursor-based positioning; underlines appear after typing pause
2. **Plain text only** - Claude input doesn't support rich text formatting
3. **Cursor flicker** - Brief cursor movement during position measurement (usually not visible)
4. **Electron quirks** - Requires full re-analysis after replacement due to fragile byte offsets
