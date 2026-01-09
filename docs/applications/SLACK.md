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

When applying a grammar correction in Slack, TextWarden preserves formatting through a partial-selection approach that targets only the error word, not the entire message.

### Child Element Selection (Critical Implementation Detail)

Slack's `AXTextArea` root element ignores `AXSelectedTextRange` attribute changes - setting selection on it returns success but has no effect. However, child elements (`AXStaticText`) DO respect selection changes.

**The approach:**

1. **Find child element containing the error text**:
   - Traverse the accessibility tree to find `AXStaticText` children
   - Sort by element height (prefer smaller paragraph-level elements over document-level)
   - Find the element containing the target error text

2. **Select within the child element**:
   - Calculate the UTF-16 offset of the error within the child element's text
   - Set `AXSelectedTextRange` on the child element (not the root)
   - Validate selection via `AXSelectedText` to confirm the correct text is selected

3. **Copy selected text to get formatting**:
   - Cmd+C to copy the selected word
   - Extract Quill Delta from clipboard to get formatting attributes (bold, italic, etc.)

4. **Create replacement with formatting**:
   - Build new Quill Delta with the suggestion text and extracted formatting
   - Write both plain text and Pickle to clipboard

5. **Paste replacement**:
   - Cmd+V to paste (replaces selection with formatted text)
   - Formatting is preserved because the new Quill Delta includes the same attributes

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

This cached data is used for format-preserving replacement.

## Fallback Behavior

Format-preserving replacement gracefully degrades:

| Scenario | Behavior |
|----------|----------|
| Child element selection + copy succeeds | Format preserved (optimal path) |
| Child element not found | Fall back to plain text |
| Selection validation fails | Fall back to plain text |
| Pickle parsing fails | Fall back to plain text |
| Any other failure | Fall back to plain text |

Plain text replacement works correctly but formatting is lost for the replaced word only. The rest of the message retains formatting since we use partial selection.

## Behavior Configuration

Slack uses the `SlackBehavior` specification for overlay behavior:

| Behavior | Value |
|----------|-------|
| Underline show delay | 0.1s |
| Popover hover delay | 0.3s |
| Popover auto-hide | 3.0s |
| Hide on scroll | No (unreliable scroll events) |
| Analysis debounce | 1.0s |
| Line height compensation | +2.0pt |
| UTF-16 text indices | Yes |

**Known Quirks:**
- `chromiumEmojiWidthBug` - Emoji width calculation issues
- `negativeXCoordinates` - Some elements have negative X
- `hasConflictingNativePopover` - Native popover detection required
- `unreliableScrollEvents` - Scroll events don't fire reliably
- `webBasedRendering` - Web-based text rendering
- `requiresBrowserStyleReplacement` - Needs clipboard+paste
- `requiresSelectionValidationBeforePaste` - Validate selection before paste
- `hasSlackFormatPreservingReplacement` - Quill Delta format support
- `hasFormattingToolbarNearCompose` - Formatting toolbar near compose area

## Implementation Files

- `Sources/AppConfiguration/Behaviors/SlackBehavior.swift`: Behavior specification
- `Sources/ContentParsers/SlackContentParser.swift`: Content parsing and text replacement
  - `extractUsingCFRange()`: AXBackgroundColor-based exclusion detection
  - `detectLinks()`: Link detection via AXLink child elements
  - `getAttributedStringAdaptive()`: Adaptive chunk sizing for AX API
  - `mergeAdjacentExclusions()`: Merge fragmented exclusion ranges
  - `parseChromiumPickle()`: Pickle parser
  - `buildChromiumPickle()`: Pickle writer
  - `applyFormatPreservingReplacement()`: Main replacement logic using child element selection
  - `findChildElementContainingText()`: Find child element for partial selection
  - `collectTextElements()`: Traverse AX tree to find text elements
  - `extractFormattingForText()`: Extract formatting attributes from Quill Delta
  - `checkClipboardForQuillDelta()`: Clipboard monitoring

- `Sources/Positioning/Strategies/SlackStrategy.swift`: Underline positioning
  - `buildTextPartMap()`: AX tree traversal for text runs
  - `calculateSubElementBounds()`: AXBoundsForRange on child elements

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
SlackContentParser: Attempting partial-selection replacement at 0-5
SlackContentParser: Found target text in child element (size 32) at offset 0
SlackContentParser: Child selection validated - text matches 'errror'
SlackContentParser: Got Quill Delta from clipboard
SlackContentParser: Extracted formatting: ["bold": 1]
SlackContentParser: Replacement completed successfully
```

If you see "fallbackToPlainText", check the logs for:
1. "Could not find child element" - The text element wasn't found in the AX tree
2. "Child selection validation failed" - Selection was set but wrong text was selected
3. "Could not get child element text" - AX API failed to read child element's text

## Popover Detection

TextWarden automatically fades error underlines when Slack's native popovers (channel previews, @mention previews) are displayed to avoid visual clutter.

### Technical Approach

Slack uses [React Modal](https://github.com/reactjs/react-modal) for hover popovers. TextWarden detects these by polling the accessibility tree for elements with `AXDOMClassList` containing `ReactModal__Content`.

**Detection flow:**
1. When underlines are shown in Slack, start polling every 100ms
2. Search the AX tree for `AXGroup` elements with `ReactModal__Content` class
3. When found: hide any open TextWarden popovers and fade underlines to 15% opacity
4. When gone: restore underlines to 100% opacity

### Why This Approach

Alternative approaches were considered:

| Approach | Issue |
|----------|-------|
| `AXObserver` notifications | Slack's Electron app doesn't fire notifications for modal appearance |
| Window-based detection | Popovers render inside the main Slack window, not as separate windows |
| Size-based heuristics | Too fragile; other UI elements match popover dimensions |
| Mouse position tracking | Can't reliably detect if user is interacting with popover content |

The `ReactModal__Content` class is a reliable identifier since it's part of React Modal's public API.

### Implementation

- `ErrorOverlayWindow.startSlackPopoverDetection()`: Starts the 100ms polling timer
- `ErrorOverlayWindow.hasReactModalPopover()`: Returns true if a ReactModal element exists
- `ErrorOverlayWindow.findReactModalElement()`: Recursively searches AX tree for the modal

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
