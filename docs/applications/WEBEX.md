# Cisco WebEx Integration

This document describes how TextWarden handles Cisco WebEx chat, including compose area detection and positioning strategy.

## Overview

Cisco WebEx (bundle ID: `Cisco-Systems.Spark`) uses native macOS Cocoa text views for its chat interface. This provides excellent accessibility API support, with standard `AXBoundsForRange` working correctly for underline positioning.

TextWarden supports:
- Chat compose area (message input field)
- Automatic filtering of sent messages (read-only content)

## Element Detection

### Compose Area vs Sent Messages

WebEx displays both editable compose area and read-only sent messages as text elements. TextWarden must distinguish between them to avoid grammar-checking already-sent messages.

**Compose area identifiers:**
- `AXIdentifier`: `ConversationInputTextView`
- Parent `AXIdentifier`: `Spark Text View`

**Sent messages:**
- Generic `AXIdentifier`: `_NS:xxx` format
- Located in `MessagesView` table
- Read-only (not editable)

### Detection Logic

The `WebExContentParser.isComposeElement()` method checks:

1. Element role must be `AXTextArea` or `AXTextField`
2. Either:
   - Element has `AXIdentifier` = `ConversationInputTextView`, OR
   - Parent has `AXIdentifier` = `Spark Text View`

```swift
// Check AXIdentifier - compose area has "ConversationInputTextView"
if identifier == "ConversationInputTextView" {
    return true  // This is the compose area
}

// Check parent hierarchy for "Spark Text View"
if parentId == "Spark Text View" {
    return true  // This is also compose area
}

return false  // Sent message or other element
```

### Monitoring Filter

When user clicks on a sent message, TextWarden:
1. Detects the element is not a compose area via `shouldMonitorElement()`
2. Clears current monitoring and hides overlays
3. Does NOT analyze the sent message text

This prevents showing grammar errors on messages that can no longer be edited.

## Positioning Strategy

TextWarden uses `WebExStrategy` for WebEx positioning:

### Approach

1. Verify element is compose area (via `isComposeElement()`)
2. Convert grapheme indices to UTF-16 (for emoji support)
3. Call `AXBoundsForRange` directly on the element
4. Return bounds or `nil` to let fallback chain continue

### UTF-16 Conversion

WebEx uses native Cocoa APIs which expect UTF-16 indices. Emojis cause position drift without conversion:

```swift
// Emoji "😉" is 1 grapheme but 2 UTF-16 code units
// Without conversion, underlines shift left after each emoji
let utf16Range = TextIndexConverter.graphemeToUTF16Range(errorRange, in: text)
```

### Typing Pause

WebEx is configured with `requiresTypingPause: true`:
- Waits 450ms after typing stops before analyzing
- Hides underlines during active typing
- Reduces CPU load and prevents flagging incomplete words

## Text Replacement

WebEx uses standard `AXSetValue` for text replacement:
- `textReplacementMethod: .standard`
- No special handling required
- Formatting is not applicable (plain text input)

## Behavior Configuration

WebEx uses the `WebExBehavior` specification for overlay behavior:

| Behavior | Value |
|----------|-------|
| Underline show delay | 0.1s |
| Bounds validation | Require positive origin |
| Popover hover delay | 0.3s |
| Popover auto-hide | 3.0s |
| Hide on scroll | Yes |
| Analysis debounce | 0.5s |
| UTF-16 text indices | No |

**Known Quirks:** None - WebEx has excellent AX API support.

## Implementation Files

- `Sources/AppConfiguration/Behaviors/WebExBehavior.swift`: Behavior specification
- `Sources/ContentParsers/WebExContentParser.swift`: Content parsing and element filtering
  - `isComposeElement()`: Distinguish compose area from sent messages
  - `shouldMonitorElement()`: Filter for TextMonitor
  - `detectUIContext()`: Returns "compose" for valid elements

- `Sources/Positioning/Strategies/WebExStrategy.swift`: Underline positioning
  - `canHandle()`: Bundle ID and compose element check
  - `calculateGeometry()`: UTF-16 conversion + AXBoundsForRange

- `Sources/AppConfiguration/AppRegistry.swift`: App configuration
  - WebEx-specific settings and feature flags

## Debugging

### Element Detection

Check if compose area is correctly identified:

```
WebExContentParser: Accepting compose area (ConversationInputTextView)
```

If sent messages trigger analysis:

```
WebExContentParser: Rejecting - not a compose element
TextMonitor: Parser rejected element for Cisco-Systems.Spark - clearing monitoring
```

### Positioning

Successful positioning logs:

```
WebExStrategy: Calculating for range {5, 4} in text length 20
WebExStrategy: Converted range {5, 4} to UTF-16 {5, 4}
WebExStrategy: SUCCESS - bounds: (150, 800, 40, 18)
```

If positioning fails (lets chain continue):

```
WebExStrategy: AXBoundsForRange failed - letting chain continue
```

### Typing Detection

When `requiresTypingPause` is active:

```
TypingDetector: AX text change notification received
ErrorOverlay: Hiding underlines during typing (Cisco WebEx)
```

## Known Behaviors

### AX Notification Source

WebEx fires `AXValueChanged` notifications from sent messages when clicked. TextWarden's callback validates the notification source matches the monitored element to avoid analyzing wrong text.

### Emoji Positioning

Without UTF-16 conversion, each emoji would shift subsequent underlines left by one position. The strategy converts grapheme cluster indices to UTF-16 code unit indices before querying bounds.

## References

- [macOS Accessibility API Documentation](https://developer.apple.com/documentation/accessibility)
- [Cisco WebEx](https://www.webex.com/)
