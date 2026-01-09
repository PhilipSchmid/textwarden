# Claude Integration

This document describes how TextWarden handles Claude, Anthropic's Electron-based desktop application.

## Overview

Claude (`com.anthropic.claudefordesktop`) is an Electron app that provides a native desktop experience for Anthropic's Claude AI. TextWarden uses a dedicated positioning strategy that traverses the AX tree to find child elements with accurate bounds.

TextWarden provides:
1. Visual underlines for grammar errors
2. Text replacement via browser-style selection + paste
3. Dedicated content parser for Claude-specific handling
4. Tree-traversal positioning for pixel-perfect underlines

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

Claude uses a dedicated `ClaudeStrategy` for accurate positioning:

**Key insight:** Claude's main `AXTextArea` returns garbage for `AXBoundsForRange`, BUT child `AXStaticText` elements have VALID bounds. ClaudeStrategy traverses the tree to find these child elements.

**How it works:**
1. Traverse the AX tree to collect all `AXStaticText` children
2. Map each segment's position in the full text
3. Find the segment containing the error
4. Query `AXBoundsForRange` on that specific child element

**Why not ChromiumStrategy:** Claude's `AXVisibleCharacterRange` always returns the full text range regardless of scroll position, making scroll detection impossible. This breaks the caching mechanisms that ChromiumStrategy relies on.

### Text Replacement

Claude uses browser-style text replacement:

```swift
textReplacementMethod: .browserStyle  // Selection + Cmd+V paste
```

**Replacement Flow:**
1. Find child element containing the error text
2. Select error range within the child element (UTF-16 indices)
3. Copy suggestion to clipboard
4. Paste via Cmd+V keyboard event

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

### Typing Pause Detection

ClaudeStrategy includes built-in typing detection:

```swift
/// Minimum time text must be stable before measuring
private static let typingPauseThreshold: TimeInterval = 0.3
```

This prevents measuring bounds while the user is actively typing, which could cause flickering.

### AX Notifications

```swift
delaysAXNotifications: false  // Claude sends AX notifications promptly
```

Claude sends accessibility notifications reliably without batching.

## Behavior Configuration

Claude uses the `ClaudeBehavior` specification for overlay behavior:

| Behavior | Value |
|----------|-------|
| Underline show delay | 0.1s |
| Popover hover delay | 0.3s |
| Popover auto-hide | 3.0s |
| Hide on scroll | Yes |
| Analysis debounce | 1.0s |
| UTF-16 text indices | Yes |

**Known Quirks:**
- `chromiumEmojiWidthBug` - Emoji width calculation issues
- `webBasedRendering` - Web-based text rendering
- `requiresBrowserStyleReplacement` - Needs clipboard+paste
- `requiresFullReanalysisAfterReplacement` - Fragile byte offsets

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration
- `Sources/AppConfiguration/Behaviors/ClaudeBehavior.swift`: Behavior specification
- `Sources/ContentParsers/ClaudeContentParser.swift`: Dedicated parser
- `Sources/Positioning/Strategies/ClaudeStrategy.swift`: Tree-traversal positioning strategy

## Debugging

### Positioning Issues

If underlines appear misaligned or at wrong positions:

```
ClaudeStrategy uses tree traversal to find AXStaticText children
Check logs for segment collection and bounds queries
```

Typical log output:
```
ClaudeStrategy: Built fresh segments (9 segments)
ClaudeStrategy: Found bounds in segment at offset 214, local range {51, 5}
ClaudeStrategy: Found bounds (969.0, 313.0, 39.0, 21.0) for range {265, 5}
```

### Text Replacement

Browser-style replacement logs:
```
Claude: Using context '7 day' for single-char selection (offset: 1)
Claude: Adjusted selection to single char at offset 52
```

### Scroll Issues

If underlines appear after scrolling away from the text:

```
ClaudeStrategy cannot detect scroll (AXVisibleCharacterRange always returns full text)
Bounds are recalculated fresh on each request to avoid stale cache
```

## Known Limitations

1. **No caching** - Claude's AX tree is unpredictable during scroll, so bounds are always recalculated fresh
2. **Scroll detection impossible** - `AXVisibleCharacterRange` always returns full text range
3. **Plain text only** - Claude input doesn't support rich text formatting
4. **Electron quirks** - Requires full re-analysis after replacement due to fragile byte offsets
