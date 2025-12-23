# Slack Integration

This document describes how TextWarden handles Slack's rich text formatting, including format-preserving text replacement.

## Overview

Slack uses [Quill Delta](https://quilljs.com/docs/delta/) format internally to represent rich text. When copying text from Slack, the formatting information is stored in the clipboard using Chromium's custom data format (`org.chromium.web-custom-data`).

TextWarden leverages this to:
1. Detect exclusion zones (mentions, links, code blocks, blockquotes)
2. Apply grammar corrections while preserving formatting (bold, italic, inline code, etc.)

## Quill Delta Format

Quill Delta represents text as an array of operations (`ops`). Each operation has:
- `insert`: The text content (string) or embedded object (dict)
- `attributes`: Optional formatting (bold, italic, code, etc.)

**Example:**
```json
{
  "ops": [
    {"insert": "This is "},
    {"attributes": {"bold": true}, "insert": "bold"},
    {"insert": " and "},
    {"attributes": {"italic": true}, "insert": "italic"},
    {"insert": " text.\n"}
  ]
}
```

### Embedded Objects and Exclusions

Slack uses embedded objects and attributes for special content. Some are **excluded** from grammar checking, others are **checked with formatting preserved**:

**Excluded from grammar checking:**
- **Mentions**: `{"insert": {"slackmention": {"id": "U123", "label": "@user"}}}`
- **Channels**: `{"insert": {"slackmention": {"id": "C456", "label": "#channel"}}}`
- **Emoji**: `{"insert": {"slackemoji": {"name": "smile"}}}`
- **Links**: `{"insert": "text", "attributes": {"link": "https://..."}}`
- **Code blocks**: `{"attributes": {"code-block": true}, ...}`
- **Blockquotes**: `{"attributes": {"blockquote": true}, ...}`

**Checked with formatting preserved:**
- **Bold**: `{"attributes": {"bold": true}, "insert": "text"}`
- **Italic**: `{"attributes": {"italic": true}, "insert": "text"}`
- **Inline code**: `{"attributes": {"code": true}, "insert": "text"}`
- **Strikethrough**: `{"attributes": {"strike": true}, "insert": "text"}`

Inline code is checked because users often use it for emphasis on regular text, not just actual code.

## Chromium Pickle Format

Slack (Electron/Chromium) stores Quill Delta in the clipboard using `org.chromium.web-custom-data` pasteboard type with Chromium's Pickle serialization format.

### Structure

```
[uint32 payload_size]      // Size of everything after this header
[uint32 num_entries]       // Number of key-value entries
[Entry 0]
[Entry 1]
...
```

Each entry:
```
[uint32 type_char_count]   // Character count (NOT byte count)
[UTF-16LE type_string]     // Type identifier (e.g., "slack/texty")
[padding to 4-byte align]
[uint32 value_char_count]  // Character count (NOT byte count)
[UTF-16LE value_string]    // Value (e.g., Quill Delta JSON)
[padding to 4-byte align]
```

### Important: Character Count vs Byte Count

Chromium stores **character count**, not byte count. Since UTF-16LE uses 2 bytes per character:
```swift
let byteCount = charCount * 2
```

### Slack's Type Identifier

Slack uses `slack/texty` as the type for Quill Delta content (not `Quill.Delta`).

### Example Pickle Data

For text "Hello **BOLD** world!":
```
00000000: 74 01 00 00  // payload_size = 372
00000004: 02 00 00 00  // num_entries = 2
// Entry 0: plain text
00000008: 16 00 00 00  // type chars = 22 ("public.utf8-plain-text")
0000000c: 70 00 75 00 62 00 6c 00 ...  // UTF-16LE type
...
// Entry 1: Quill Delta
000000xx: 0b 00 00 00  // type chars = 11 ("slack/texty")
000000xx: 73 00 6c 00 61 00 63 00 ...  // UTF-16LE type
000000xx: xx xx xx xx  // value chars
000000xx: 7b 00 22 00 6f 00 70 00 ...  // UTF-16LE JSON
```

## Format-Preserving Replacement

When applying a grammar correction in Slack, TextWarden preserves formatting by:

1. **Getting the Quill Delta** (in priority order):
   - Cached Quill Delta from clipboard monitoring
   - Current clipboard content (if matches current text)
   - Trigger Cmd+A + Cmd+C (fallback, more intrusive)

2. **Applying the correction** to the Quill Delta JSON:
   - Find the op containing the error
   - Replace text within that op
   - Attributes (bold, italic, etc.) remain attached to the op

3. **Writing back to clipboard**:
   - Build new Pickle with corrected Quill Delta
   - Write both plain text and Pickle to clipboard

4. **Pasting**:
   - Cmd+A to select all
   - Cmd+V to paste (Slack reads the Pickle and preserves formatting)

### Example: Correcting "errror" to "error" in Bold Text

**Before:**
```json
{"ops":[{"insert":"This is "},{"attributes":{"bold":true},"insert":"errror"},{"insert":" text\n"}]}
```

**After:**
```json
{"ops":[{"insert":"This is "},{"attributes":{"bold":true},"insert":"error"},{"insert":" text\n"}]}
```

The `attributes: {"bold": true}` stays attached - only the `insert` value changes.

### Multi-Op Corrections

If an error spans multiple ops (e.g., starts in bold, ends in normal text), the correction falls back to plain text replacement. This is a safety measure to avoid complex formatting merges.

## Clipboard Monitoring

TextWarden monitors the clipboard while Slack is active. When the user copies text from Slack:

1. Clipboard change detected via `NSPasteboard.changeCount`
2. Check for `org.chromium.web-custom-data` type
3. Parse Pickle and extract Quill Delta JSON
4. Cache both the JSON and corresponding plain text

This cached data is used for format-preserving replacement, avoiding the need to trigger Cmd+A + Cmd+C.

### Cache Matching

Before using cached Quill Delta, TextWarden verifies the plain text matches:
```swift
if cachedQuillDeltaPlainText == currentText {
    // Safe to use cached delta
}
```

If the text has changed (user edited after copying), the cache is stale and we fall back to Cmd+A + Cmd+C.

## Fallback Behavior

Format-preserving replacement gracefully degrades:

| Scenario | Behavior |
|----------|----------|
| Cached Quill Delta matches | Use cache (fastest, non-intrusive) |
| Clipboard has matching Quill Delta | Use clipboard (non-intrusive) |
| No Quill Delta available | Trigger Cmd+A + Cmd+C |
| Error spans multiple ops | Fall back to plain text |
| Pickle parsing fails | Fall back to plain text |
| Any other failure | Fall back to plain text |

Plain text replacement works correctly but strips formatting from the entire message. Format-preserving replacement is best-effort.

## Implementation Files

- `Sources/ContentParsers/SlackContentParser.swift`: Main implementation
  - `parseChromiumPickle()`: Pickle parser
  - `buildChromiumPickle()`: Pickle writer
  - `applyFormatPreservingReplacement()`: Main replacement logic
  - `applyTextCorrection()`: Quill Delta modification
  - `checkClipboardForQuillDelta()`: Clipboard monitoring

## Debugging

Enable debug logging to see format-preserving replacement in action:

```
SlackContentParser: Cached Quill Delta JSON (110 chars) for format-preserving replacement
SlackContentParser: Using cached Quill Delta (matches current text)
SlackContentParser: Applied correction to Quill Delta op 1
SlackContentParser: Format-preserving replacement completed successfully
```

If you see "falling back to plain text replacement", check:
1. Is Quill Delta on clipboard? (Copy from Slack first)
2. Does cached text match current text?
3. Does error span multiple formatting ops?

## Known Limitations

### Emoji Positioning

Visual underlines are automatically disabled when emojis are present in the text. This is a deliberate trade-off due to a Chromium accessibility limitation.

**Root Cause:**
- Slack renders emojis as `[AXImage]` elements that are NOT included in `AXValue` text
- However, Chromium's text marker APIs (`AXSelectedTextMarkerRange`, `AXBoundsForTextMarkerRange`) DO count these embedded images in their position indices
- This creates a mismatch: when we set selection at position X (based on `AXValue`), Chromium interprets it as a different position because it counts emojis we can't see
- The position drift increases with each emoji, making correction unreliable

**Detection Method:**
```swift
// Compare AXNumberOfCharacters (includes emojis) with text.count (excludes emojis)
if AXNumberOfCharacters > text.count {
    // Emojis detected - disable visual underlines
}
```

**User Impact:**
- Error indicator (badge with count) still shows correctly
- Users can click the indicator to see all errors
- Grammar corrections still work via the popover
- Only the inline underlines are hidden

**Why Not Fix It:**
Various approaches were attempted:
1. UTF-16 conversion: Didn't help because emojis aren't in the text string
2. Selection offset adjustment: Can't reliably determine emoji positions
3. Proportional offset estimation: Too imprecise with multiple emojis
4. AXNumberOfCharacters comparison: Gives total count but not positions

The Chromium accessibility API doesn't provide a way to map between `AXValue` positions and text marker positions when embedded objects exist.

## References

- [Quill Delta Format](https://quilljs.com/docs/delta/)
- [Chromium Pickle Format](https://chromium.googlesource.com/chromium/src/+/main/base/pickle.h)
