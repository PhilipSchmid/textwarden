# Telegram Integration

This document describes how TextWarden handles Telegram, a native macOS application with custom text views.

## Overview

Telegram (`ru.keepcoder.Telegram`) is a native macOS app built with Swift. Unlike the Catalyst messenger apps (Messages, WhatsApp), Telegram supports standard macOS accessibility APIs more reliably, enabling simpler text replacement.

TextWarden provides:
1. Visual underlines for grammar errors
2. Direct text replacement via standard AX APIs
3. Rich text format support

## Technical Details

### App Type

| Property | Value |
|----------|-------|
| Bundle ID | `ru.keepcoder.Telegram` |
| Category | Native macOS |
| Parser Type | Generic |
| Text Replacement | Standard (direct AX setValue) |
| Visual Underlines | Supported |
| Formatted Text | Supported |

### Positioning Strategy

Telegram uses a strategy chain with `AXBoundsForRange` as the primary approach:

1. **RangeBounds** (primary) - Direct `AXBoundsForRange` queries for pixel-perfect positioning
2. **LineIndex** - Fallback using line bounds and character index calculation
3. **FontMetrics** - Text measurement as last resort

**UTF-16 Handling:** Telegram's `AXNumberOfCharacters` returns UTF-16 code units (emojis count as 2), while Swift strings use grapheme clusters. The `RangeBoundsStrategy` handles this conversion automatically.

### Text Replacement

Unlike Catalyst apps, Telegram supports **standard AX text replacement**:

```swift
textReplacementMethod: .standard  // Direct AXSetValue works
```

**Benefits:**
- Faster replacement (no keyboard simulation)
- More reliable (direct API call)
- Simpler implementation

### Font Configuration

```swift
FontConfig(
    defaultSize: 13,
    fontFamily: nil,  // System font
    spacingMultiplier: 1.0
)
horizontalPadding: 0
```

## Messenger Behavior

While Telegram shares the `MessengerBehavior` infrastructure, it requires less special handling than Catalyst apps:

### Conversation Switch Detection

Same detection mechanism as other messengers:

1. Element position changes significantly (>10px) → conversation was switched
2. Hide all overlays and clear errors
3. Wait for UI to settle (0.15s delay - shorter than Catalyst apps)
4. Re-extract text and trigger fresh analysis

### Message Sent Detection

When a message is sent:

1. Text field shrinks (height decreases >5px)
2. TextWarden detects this and clears all errors

### AX Notifications

Unlike Catalyst apps, Telegram sends AX notifications more reliably:

```swift
delaysAXNotifications: false  // Notifications sent promptly
```

This means TextWarden can rely more on event-driven updates rather than polling.

## Rich Text Support

Telegram supports rich text formatting in the compose field:

```swift
supportsFormattedText: true
```

When users apply formatting (bold, italic, etc.), TextWarden:
1. Detects the formatted text via accessibility attributes
2. Applies corrections without disrupting formatting (via direct AX setValue)

## Behavior Configuration

Telegram uses the `TelegramBehavior` specification for overlay behavior:

| Behavior | Value |
|----------|-------|
| Underline show delay | 0.1s |
| Bounds validation | Require positive origin |
| Popover hover delay | 0.3s |
| Popover auto-hide | 3.0s |
| Hide on scroll | Yes |
| Analysis debounce | 0.3s |
| UTF-16 text indices | Yes |

**Known Quirks:** None - Telegram has excellent AX API support.

## Implementation Files

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration (line ~436)
- `Sources/AppConfiguration/Behaviors/TelegramBehavior.swift`: Behavior specification
- `Sources/AppConfiguration/MessengerBehavior.swift`: Shared messenger patterns
- `Sources/App/AnalysisCoordinator+WindowTracking.swift`: Conversation switch detection

## Debugging

### Positioning Issues

If underlines appear misaligned:

```
Telegram uses LineIndexStrategy (AXBoundsForRange unsupported)
Check logs for line calculation and font metrics
```

Typical log output:
```
LineIndexStrategy: Line 0 for char index 5
LineIndexStrategy: Calculating X from font metrics
```

### Strategy Selection

```
PositionResolver: Trying LineIndexStrategy for Telegram
LineIndexStrategy: SUCCESS - bounds calculated
```

### Text Replacement

Standard replacement logs:
```
AnalysisCoordinator: Using standard AX text replacement
```

## Comparison with Catalyst Messengers

| Feature | Telegram | Messages/WhatsApp |
|---------|----------|-------------------|
| App Type | Native macOS | Mac Catalyst |
| Text Replacement | Standard AX | Browser-style |
| AXBoundsForRange | Supported | Works (with quirks) |
| Positioning | RangeBounds | TextMarker/RangeBounds |
| AX Notifications | Reliable | Unreliable |
| Conversation Switch Delay | 0.15s | 0.2-0.5s |
| Format Support | Yes | No |

## Known Limitations

1. **Formatting lost on replacement** - When applying corrections, text formatting (bold, italic) is not preserved. The replacement text will be plain text.
2. **UTF-16 character counting** - `AXNumberOfCharacters` uses UTF-16 units, so emojis count as 2; strategy handles this automatically
3. **Sticker/media messages** - TextWarden only checks text content, not media descriptions
