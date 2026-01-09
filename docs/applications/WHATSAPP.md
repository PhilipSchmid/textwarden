# WhatsApp Integration

This document describes how TextWarden handles WhatsApp, a Mac Catalyst application with known accessibility API quirks.

## Overview

WhatsApp (`net.whatsapp.WhatsApp`) is a Mac Catalyst app - an iOS app running on macOS via Apple's Catalyst framework. It shares many characteristics with Apple Messages but has additional challenges with stale accessibility data.

TextWarden provides:
1. Visual underlines for grammar errors
2. Text replacement via browser-style selection + paste
3. Conversation switch detection with stale data handling
4. Automatic re-analysis after conversation changes

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `net.whatsapp.WhatsApp` |
| Category | Mac Catalyst |
| Parser Type | Generic |
| Text Replacement | Browser-style (selection + keyboard paste) |
| Visual Underlines | Supported |

### Positioning Strategy

WhatsApp uses the same strategy chain as Messages:

1. **TextMarker** (primary) - Apple's text marker API
2. **RangeBounds** - `AXBoundsForRange` with UTF-16 adjustment
3. **LineIndex** - Fallback for wrapped lines
4. **InsertionPoint** - Cursor-based positioning
5. **FontMetrics** - Text measurement as last resort

### Text Replacement

WhatsApp uses browser-style text replacement because Catalyst apps have incomplete AX text manipulation support.

**Replacement Flow:**
1. Select error text using AX selection APIs
2. Copy suggestion to clipboard
3. Paste via Cmd+V keyboard event

### Font Configuration

```swift
FontConfig(
    defaultSize: 14,
    fontFamily: nil,  // System font
    spacingMultiplier: 1.0
)
horizontalPadding: 5
```

## Messenger Behavior

WhatsApp shares behavioral patterns with other messenger apps via `MessengerBehavior`, but has additional handling for stale AX data.

### Stale Data Issue

**Known Problem:** WhatsApp's accessibility API is notorious for returning stale text after conversation switches. When switching from Conversation A to Conversation B, the AX API may still return Conversation A's text for several hundred milliseconds.

**TextWarden's Solution:**

1. Longer delay after conversation switch (0.5s vs 0.2s for Messages)
2. Stale data detection: If text after switch equals text before switch, skip re-analysis
3. Let user interaction trigger fresh analysis instead

```swift
// From MessengerBehavior.swift
static func conversationSwitchDelay(for bundleID: String) -> TimeInterval {
    switch bundleID {
    case whatsAppBundleID:
        return 0.5  // WhatsApp needs longer delay
    case messagesBundleID:
        return 0.2
    default:
        return 0.2
    }
}
```

### Conversation Switch Detection

1. Element position changes significantly (>10px) → conversation was switched
2. Hide all overlays and clear errors
3. Wait for UI to settle (0.5s delay - longer than other apps)
4. Re-extract text and check for stale data
5. If text unchanged (stale), skip re-analysis
6. If text different (valid), trigger fresh analysis

### Message Sent Detection

When a message is sent:

1. Text field shrinks (height decreases >5px)
2. TextWarden detects this and clears all errors
3. Indicators and underlines are hidden

### Text Validation Timer

Like other Catalyst apps, WhatsApp doesn't reliably send AX notifications:

- Poll interval: 500ms
- Compares current text with last analyzed text
- Grace period after conversation switch (0.6s) to prevent race conditions

## Behavior Configuration

WhatsApp uses the `WhatsAppBehavior` specification for overlay behavior:

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
- `requiresBrowserStyleReplacement` - Needs clipboard+paste
- `requiresFullReanalysisAfterReplacement` - AX state changes after paste

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (line ~402)
- `Sources/AppConfiguration/Behaviors/WhatsAppBehavior.swift`: Behavior specification
- `Sources/AppConfiguration/MessengerBehavior.swift`: Shared messenger patterns including stale data handling
- `Sources/App/AnalysisCoordinator+WindowTracking.swift`: Conversation switch detection

## Debugging

### Stale Data Detection

When stale data is detected after conversation switch:

```
Messenger: Text unchanged after conversation switch (X chars) - skipping re-analysis (stale AX data)
```

### Positioning Issues

If underlines appear misaligned:

```
WhatsApp uses strategy chain: textMarker → rangeBounds → lineIndex
Check logs for strategy selection and coordinate conversion
```

### Conversation Switch

Conversation switch detection logs:

```
Element monitoring: Element position changed by Xpx in Mac Catalyst app - triggering re-analysis (conversation switch)
```

## Known Limitations

1. **Stale AX data** - Switching conversations may show errors from previous conversation briefly; TextWarden handles this with extended delays and stale detection
2. **No format support** - WhatsApp input is plain text only (formatting applied server-side via markdown)
3. **AX notification unreliability** - Uses timer-based polling instead of AX notifications
4. **Emoji positioning** - Multi-codepoint emojis may cause slight positioning inaccuracy

## Comparison with Apple Messages

| Feature | WhatsApp | Messages |
|---------|----------|----------|
| Conversation switch delay | 0.5s | 0.2s |
| Stale data detection | Yes | No |
| AX notification reliability | Poor | Poor |
| Format preservation | N/A (plain text) | N/A (plain text) |
