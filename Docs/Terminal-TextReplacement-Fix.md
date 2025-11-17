# Terminal Text Replacement Fix (T044-Terminal)

## Problem Summary

Terminal text replacement for grammar suggestions was failing. When users clicked a suggestion in Terminal.app, the corrected text was being inserted **before** the incorrect text instead of replacing it.

## Root Cause

**Wrong virtual key codes were being used for keyboard simulation.**

The bug originated from using incorrect virtual key codes:
- Used key code `11` (0x0B) for Ctrl+K, which is actually the **B key**
- This sent **Ctrl+B** instead of **Ctrl+K**
- The K key is actually code `40` (0x28)

## Timeline of Debugging

1. **Initial symptom**: Text was duplicated ("Cilium.Ciliium")
2. **First attempt**: Tried using AX API - completely unreliable in Terminal.app
3. **Second attempt**: Used CGEventPost with arrow keys - became ANSI escape sequences
4. **Third attempt**: Used Ctrl+A and Ctrl+K - Ctrl+A worked but Ctrl+K failed
5. **Fourth attempt**: Tried AppleScript - hit permission issues (requires Automation permission)
6. **Root cause discovery**: Realized key code 11 is B, not K
7. **Final fix**: Used correct key code 40 for K key

## Solution

### 1. Created Virtual Key Code Constants

Created `VirtualKeyCodes.swift` with named constants to prevent future errors:

```swift
enum VirtualKeyCode {
    static let a: CGKeyCode = 0x00  // A key
    static let k: CGKeyCode = 0x28  // K key (40 decimal) - NOT 11!
    static let v: CGKeyCode = 0x09  // V key
}
```

### 2. Fixed Terminal Replacement Strategy

Terminal replacement now works correctly:
1. **Ctrl+A** (key 0): Move cursor to beginning of command line
2. **Ctrl+K** (key 40): Delete from cursor to end of line
3. **Cmd+V** (key 9): Paste corrected text from clipboard

### 3. macOS Control Modifier Bug Workaround

CGEventPost has a documented bug where the Control modifier flag doesn't work unless you also add the SecondaryFn flag:

```swift
var adjustedFlags = flags
if flags.contains(.maskControl) {
    adjustedFlags.insert(.maskSecondaryFn)
}
```

**Reference**: https://stackoverflow.com/questions/27484330/simulate-keypress-using-swift

## Testing

### Regression Tests

Created `VirtualKeyCodeTests.swift` with tests to prevent this bug from recurring:

```swift
func testKeyCodeForK() {
    XCTAssertEqual(VirtualKeyCode.k, 0x28, "K key must be code 0x28 for Ctrl+K to work")
    XCTAssertNotEqual(VirtualKeyCode.k, 0x0B, "K key must NOT be 0x0B - that's the B key!")
}
```

### Manual Testing

Tested in Terminal.app:
1. Type misspelled word (e.g., "Ciliium")
2. Click grammar suggestion
3. ✅ Incorrect word is replaced with correct word
4. ✅ No duplication occurs

## Files Modified

### Core Changes
- `Sources/App/AnalysisCoordinator.swift`: Fixed Terminal replacement logic
- `Sources/App/VirtualKeyCodes.swift`: **NEW** - Virtual key code constants

### Testing
- `Tests/Unit/VirtualKeyCodeTests.swift`: **NEW** - Regression tests

## Key Learnings

1. **Never use magic numbers for key codes** - Use named constants
2. **Terminal.app's AX API is unreliable** - Use keyboard simulation instead
3. **CGEventPost has Control modifier bug** - Requires SecondaryFn flag workaround
4. **Virtual key codes are physical positions** - Not character meanings
5. **Always verify key codes** - Easy to confuse similar codes

## Virtual Key Code Reference

Common keys used in this project:
- A key: `0x00` (0 decimal)
- V key: `0x09` (9 decimal)
- **B key**: `0x0B` (11 decimal) ⚠️ Easy to confuse with K!
- **K key**: `0x28` (40 decimal) ✅ Correct code

Full reference: `/System/Library/Frameworks/Carbon.framework/.../HIToolbox.framework/.../Events.h`

## Future Improvements

- [ ] Add integration tests for Terminal text replacement
- [ ] Consider caching CGEventSource instead of creating each time
- [ ] Add telemetry to track Terminal replacement success rate
- [ ] Test with other terminal emulators (iTerm2, Warp, etc.)

## Related Issues

- T044: Text replacement system
- T044-Terminal: Terminal-specific text replacement
