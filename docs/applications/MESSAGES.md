# Apple Messages Integration

This document describes how TextWarden handles Apple Messages, a Mac Catalyst application.

## Overview

Apple Messages (`com.apple.MobileSMS`) is a Mac Catalyst app - an iOS app running on macOS via Apple's Catalyst framework. This affects how accessibility APIs behave compared to native macOS apps.

TextWarden provides:
1. Visual underlines for grammar errors
2. Text replacement via browser-style selection + paste
3. Conversation switch detection with automatic re-analysis

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `com.apple.MobileSMS` |
| Category | Mac Catalyst |
| Parser Type | Generic |
| Text Replacement | Browser-style (selection + keyboard paste) |
| Visual Underlines | Supported |

### Positioning Strategy

Messages uses a strategy chain for positioning:

1. **TextMarker** (primary) - Apple's text marker API
2. **RangeBounds** - `AXBoundsForRange` with UTF-16 adjustment for emojis
3. **LineIndex** - Fallback for wrapped lines
4. **InsertionPoint** - Cursor-based positioning
5. **FontMetrics** - Text measurement as last resort

**Known Quirk:** Catalyst apps return slightly inaccurate X coordinates on wrapped lines with multi-codepoint characters (emojis). Y coordinates are correct. `RangeBoundsStrategy` handles this with UTF-16 index adjustment.

### Text Replacement

Messages uses browser-style text replacement because Catalyst apps have incomplete AX text manipulation support - standard `AXSetValue` doesn't work reliably.

**Replacement Flow:**
1. Select error text using AX selection APIs
2. Copy suggestion to clipboard
3. Paste via Cmd+V keyboard event

### Font Configuration

```swift
FontConfig(
    defaultSize: 13,
    fontFamily: "SF Pro",
    spacingMultiplier: 1.0
)
horizontalPadding: 5
```

## Messenger Behavior

Messages shares behavioral patterns with other messenger apps (WhatsApp, Telegram) via `MessengerBehavior`:

### Conversation Switch Detection

TextWarden detects conversation switches by monitoring the text input element's position:

1. Element position changes significantly (>10px) → conversation was switched
2. Hide all overlays and clear errors
3. Wait for UI to settle (0.2s delay)
4. Re-extract text and trigger fresh analysis

### Message Sent Detection

When a message is sent:

1. Text field shrinks (height decreases >5px)
2. TextWarden detects this and clears all errors
3. Indicators and underlines are hidden

### Text Validation Timer

Mac Catalyst apps don't reliably send `kAXValueChangedNotification`. TextWarden uses a timer-based polling approach:

- Poll interval: 500ms
- Compares current text with last analyzed text
- Triggers re-analysis or clears errors as needed

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (line ~367)
- `Sources/AppConfiguration/MessengerBehavior.swift`: Shared messenger patterns
- `Sources/App/AnalysisCoordinator+WindowTracking.swift`: Conversation switch and message sent detection

## Debugging

### Positioning Issues

If underlines appear misaligned:

```
Messages uses strategy chain: textMarker → rangeBounds → lineIndex
Check logs for strategy selection and coordinate conversion
```

### Conversation Switch

Conversation switch detection logs:

```
Element monitoring: Element position changed by Xpx in Mac Catalyst app - triggering re-analysis (conversation switch)
```

### Message Sent

Message sent detection logs:

```
Element monitoring: Text field shrunk by Xpx in Mac Catalyst app - clearing errors
```

## Known Limitations

1. **Emoji positioning** - Multi-codepoint emojis may cause slight X-coordinate inaccuracy on wrapped lines
2. **No format support** - Messages input is plain text only (no bold/italic)
3. **Typing detection** - Text field height growing triggers position cache invalidation
