# Slack Integration

This document describes how TextWarden handles Slack's rich text formatting, including format-preserving text replacement.

## Overview

Slack uses [Quill Delta](https://quilljs.com/docs/delta/) format internally to represent rich text. When copying text from Slack, the formatting information is stored in the clipboard using Chromium's custom data format (`org.chromium.web-custom-data`).

TextWarden leverages this to:
1. Detect exclusion zones (mentions, channels, code blocks, blockquotes, links) via Accessibility APIs
2. Apply grammar corrections while preserving formatting (bold, italic, inline code, etc.)

## Exclusion Detection via Accessibility APIs

TextWarden uses multiple AX APIs to detect content that should be excluded from grammar checking:

### AXBackgroundColor Detection

Slack applies `AXBackgroundColor` attributes to styled content, which TextWarden detects via `AXAttributedStringForRange`:

- **Mentions** (@user): Light blue background
- **Channels** (#channel): Light blue background
- **Inline code**: Gray background (backticks)
- **Block code**: Gray background (triple backticks)

### Link Detection via AXLink Elements

Links (URLs) don't have `AXBackgroundColor` in Slack. Instead, they appear as `AXLink` child elements in the accessibility tree. TextWarden traverses the element tree to find these:

```
[AXTextArea]
  └─ [AXLink]
       └─ [AXStaticText] value: "https://example.com"
```

The link text is extracted from the `AXStaticText` child and matched against the main text to determine the exclusion range.

### Adaptive Chunk Sizing

Slack's AX API has a quirk where `AXAttributedStringForRange` fails with error -25212 when ranges extend near the text end. TextWarden handles this with adaptive chunk sizing:

```swift
let chunkSizes = [100, 50, 25, 10, 5, 1]
// Try progressively smaller chunks until one succeeds
```

This ensures reliable detection even for edge cases near text boundaries.

### Range Merging

Since chunks may split exclusion zones, TextWarden merges adjacent ranges after collection:

```
Before merge: [54-69, 94-100, 100-106]  // #development split at chunk boundary
After merge:  [54-69, 94-106]           // Properly merged
```

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
- **Inline code**: `{"attributes": {"code": true}, "insert": "text"}`
- **Code blocks**: `{"attributes": {"code-block": true}, ...}`
- **Blockquotes**: `{"attributes": {"blockquote": true}, ...}`

**Checked with formatting preserved:**
- **Bold**: `{"attributes": {"bold": true}, "insert": "text"}`
- **Italic**: `{"attributes": {"italic": true}, "insert": "text"}`
- **Strikethrough**: `{"attributes": {"strike": true}, "insert": "text"}`

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

- `Sources/ContentParsers/SlackContentParser.swift`: Content parsing and text replacement
  - `extractUsingCFRange()`: AXBackgroundColor-based exclusion detection
  - `detectLinks()`: Link detection via AXLink child elements
  - `getAttributedStringAdaptive()`: Adaptive chunk sizing for AX API
  - `mergeAdjacentExclusions()`: Merge fragmented exclusion ranges
  - `parseChromiumPickle()`: Pickle parser
  - `buildChromiumPickle()`: Pickle writer
  - `applyFormatPreservingReplacement()`: Main replacement logic
  - `applyTextCorrection()`: Quill Delta modification
  - `checkClipboardForQuillDelta()`: Clipboard monitoring

- `Sources/Positioning/Strategies/SlackStrategy.swift`: Underline positioning
  - `buildTextPartMap()`: AX tree traversal for text runs
  - `calculateSubElementBounds()`: AXBoundsForRange on child elements
  - `calculateFallbackGeometry()`: Font measurement fallback

## Debugging

### Exclusion Detection

Exclusion detection logs summary information without revealing user content:

```
SlackContentParser: Extracting exclusions via Accessibility APIs
SlackContentParser: CFRange method found 5 exclusions
SlackContentParser: Detected 6 total exclusion ranges
AnalysisCoordinator: Filtered 6 errors in Slack exclusion zones
```

If exclusions aren't being detected:
1. Is the content actually styled? (mentions should show blue background in Slack)
2. Check for AX API errors in logs (error -25212 = range issue)
3. Verify `AXNumberOfCharacters` matches expected text length
4. For links: check if AXLink elements appear in the element tree dump

### Format-Preserving Replacement

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

## Positioning Strategy

TextWarden uses a dedicated positioning strategy for Slack (`SlackStrategy`) that provides pixel-perfect underline positioning.

### Technical Approach

Slack's main `AXTextArea` element doesn't support standard `AXBoundsForRange` queries (returns invalid data). However, child `AXStaticText` elements DO support `AXBoundsForRange` with local range offsets.

**Strategy:**
1. Traverse the AX children tree to find all `AXStaticText` elements (text runs)
2. Build a TextPart map: character ranges → visual frames + element references
3. For each error, find the overlapping TextPart(s)
4. Query `AXBoundsForRange` on the child element with local range offset
5. Fall back to font measurement only if AX query fails

### Click-Based Position Recheck

Slack's AX tree updates asynchronously after user interactions. TextWarden monitors mouse clicks and triggers a debounced position recheck (200ms delay) to ensure underlines stay aligned when the user navigates or edits text.

### Emoji Handling

Emojis in Slack are rendered as `[AXImage]` elements. The positioning strategy handles this gracefully:
- TextPart mapping naturally excludes non-text elements
- Bounds queries on text runs return accurate positions regardless of surrounding emojis
- Visual underlines remain accurate in text containing emojis

## References

- [Quill Delta Format](https://quilljs.com/docs/delta/)
- [Chromium Pickle Format](https://chromium.googlesource.com/chromium/src/+/main/base/pickle.h)
