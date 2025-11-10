# Gnau Testing Checklist

This document provides comprehensive manual testing procedures for the Gnau grammar checker.

## Prerequisites

- [ ] macOS 13.0+ (Sequoia)
- [ ] Accessibility permissions granted
- [ ] Test applications installed (TextEdit, Pages, Notes, VS Code, Slack)

---

## Phase 11: Manual Testing Checklist

### T131-T135: Core Application Testing

#### T131: TextEdit Testing
- [ ] Open TextEdit
- [ ] Type: "The team are working on multiple project"
- [ ] Verify red underline appears under "are" and "project"
- [ ] Hover over error - verify popover shows
- [ ] Verify suggestions: "is" for "are", "projects" for "project"
- [ ] Click suggestion - verify text is corrected
- [ ] Type more text - verify real-time detection (<20ms)

**Expected Result**: Grammar errors detected, suggestions work, corrections apply cleanly

#### T132: Pages Testing
- [ ] Open Pages
- [ ] Create new document
- [ ] Type test sentences with errors
- [ ] Verify Gnau suggestions don't conflict with Pages built-in checker
- [ ] Test with formatted text (bold, italic)
- [ ] Verify underlines render correctly

**Expected Result**: Works alongside Pages grammar checker without conflicts

#### T133: Notes Testing
- [ ] Open Notes app
- [ ] Create new note
- [ ] Type sentences with grammar errors
- [ ] Verify detection and suggestions work
- [ ] Test with bullet points and numbered lists
- [ ] Verify formatting preserved after correction

**Expected Result**: Grammar checking works in structured notes

#### T134: Slack Testing
- [ ] Open Slack
- [ ] Navigate to any channel
- [ ] Type message with grammar error
- [ ] Verify detection in message compose field
- [ ] Apply suggestion
- [ ] Send message - verify correction persisted

**Expected Result**: Works in web-based text fields

#### T135: Mail.app Testing
- [ ] Open Mail
- [ ] Compose new email
- [ ] Type email body with errors
- [ ] Verify detection and correction
- [ ] Test subject line separately
- [ ] Send email - verify corrections preserved

**Expected Result**: Full email composition support

---

### T136-T140: Code Editor Testing

#### T136: VS Code Testing
- [ ] Open VS Code
- [ ] Open Git commit message editor (Cmd+Shift+G)
- [ ] Type commit message with grammar error
- [ ] Verify detection works
- [ ] Verify code blocks are excluded from checking
- [ ] Verify URLs are not flagged as errors

**Expected Result**: Smart detection in commit messages, code excluded

#### T137: Terminal Testing
- [ ] Open Terminal app
- [ ] Use `git commit` to open editor
- [ ] Type commit message with errors
- [ ] Verify grammar checking active
- [ ] Test multi-line commit messages

**Expected Result**: Works in terminal-based editors

#### T138: Code Block Exclusion
Test text with code blocks:
```
This is a description with grammar error.

```javascript
const foo = bar; // this should not be checked
```

Another paragraph to check.
```

- [ ] Verify only prose is checked
- [ ] Verify code blocks ignored
- [ ] Verify inline `code` ignored

**Expected Result**: Code patterns excluded

---

### T139-T142: Edge Cases

#### T139: Empty Text Handling
- [ ] Open TextEdit
- [ ] Delete all text
- [ ] Verify no errors or crashes
- [ ] Type single character
- [ ] Verify no false positives

**Expected Result**: Graceful handling of empty/minimal text

#### T140: Special Characters
- [ ] Type text with emojis: "The cat 🐱 are happy"
- [ ] Type text with accents: "Café résumé naïve"
- [ ] Type text with symbols: "Price: $50 (50% off!)"
- [ ] Verify detection works correctly

**Expected Result**: Proper Unicode handling

#### T141: Very Long Text
- [ ] Paste 10,000-word document
- [ ] Verify initial analysis <500ms
- [ ] Edit a paragraph in middle
- [ ] Verify incremental analysis <20ms
- [ ] Check memory usage <100MB

**Expected Result**: Performance targets met

#### T142: Rapid Typing
- [ ] Type continuously without pausing
- [ ] Verify no lag or UI blocking
- [ ] Verify all errors eventually detected
- [ ] Verify no dropped characters

**Expected Result**: Smooth typing experience

---

### T143-T146: Per-App Settings

#### T143: Disable App
- [ ] Open Preferences → Applications
- [ ] Find TextEdit in list
- [ ] Toggle OFF
- [ ] Type in TextEdit - verify NO suggestions
- [ ] Toggle ON
- [ ] Verify suggestions return immediately

**Expected Result**: Per-app control works instantly

#### T144: Multiple Apps
- [ ] Disable TextEdit
- [ ] Enable Pages
- [ ] Switch between apps
- [ ] Verify correct behavior per app

**Expected Result**: Settings respected per application

#### T145: Application Discovery
- [ ] Open new application (not in list)
- [ ] Type text with errors
- [ ] Check Preferences - verify app auto-discovered
- [ ] Verify app name and icon shown

**Expected Result**: Automatic app discovery

#### T146: Search Filter
- [ ] Open Preferences → Applications
- [ ] Type "text" in search
- [ ] Verify only matching apps shown
- [ ] Clear search
- [ ] Verify all apps return

**Expected Result**: Search works correctly

---

### T147: Custom Vocabulary

- [ ] Open Preferences → Dictionary
- [ ] Add custom word: "SwiftUI"
- [ ] Type sentence: "SwiftUI are great framework"
- [ ] Verify "SwiftUI" not flagged
- [ ] Verify "are" still flagged (should be "is")
- [ ] Add 1000 words - verify limit enforced
- [ ] Try adding 1001st word - verify error message
- [ ] Remove word - verify it gets flagged again

**Expected Result**: Custom dictionary works, 1000-word limit enforced

---

### T148: Keyboard Navigation

- [ ] Trigger error popover
- [ ] Press **Cmd+1** - verify first suggestion applied
- [ ] Trigger another error with 3 suggestions
- [ ] Press **Cmd+2** - verify second suggestion applied
- [ ] Trigger error with multiple errors
- [ ] Press **↓** - verify next error shown
- [ ] Press **↑** - verify previous error shown
- [ ] Press **Esc** - verify popover closes

**Expected Result**: All keyboard shortcuts work

---

### T149: Accessibility Testing

#### VoiceOver Testing
- [ ] Enable VoiceOver (Cmd+F5)
- [ ] Trigger error popover
- [ ] Verify error message announced
- [ ] Tab through suggestions
- [ ] Verify each suggestion announced
- [ ] Verify severity announced (Error/Warning/Info)
- [ ] Navigate to Preferences
- [ ] Verify all controls have labels

**Expected Result**: Full VoiceOver support

#### Dynamic Type Testing
- [ ] System Settings → Accessibility → Display
- [ ] Set text size to largest
- [ ] Open Gnau popover
- [ ] Verify text scales correctly
- [ ] Verify popover remains usable
- [ ] Open Preferences
- [ ] Verify all text readable

**Expected Result**: Supports largest text sizes

#### High Contrast Testing
- [ ] System Settings → Accessibility → Display
- [ ] Enable "Increase Contrast"
- [ ] Trigger error popover
- [ ] Verify severity indicators visible
- [ ] Verify colors have sufficient contrast

**Expected Result**: Usable in high contrast mode

---

### T150: Reliability Testing

#### Permission Revocation
- [ ] With Gnau running, open System Settings
- [ ] Security & Privacy → Accessibility
- [ ] Uncheck Gnau
- [ ] Verify Gnau detects revocation
- [ ] Verify menu bar icon changes
- [ ] Re-enable permission
- [ ] Verify Gnau resumes automatically

**Expected Result**: Graceful permission handling

#### Crash Recovery
- [ ] Force quit Gnau (Cmd+Option+Esc)
- [ ] Relaunch Gnau
- [ ] Verify restart indicator briefly shown
- [ ] Verify app resumes normally
- [ ] Check preferences preserved

**Expected Result**: Clean recovery from crashes

#### Memory Leak Testing
- [ ] Run Gnau for 1 hour
- [ ] Analyze 50+ documents
- [ ] Monitor memory in Activity Monitor
- [ ] Verify memory <100MB
- [ ] Verify no steady growth

**Expected Result**: No memory leaks, stable footprint

---

## Performance Validation

### Instruments Profiling

#### Time Profiler (T147)
```bash
# Record 30-second session
instruments -t "Time Profiler" -D profile.trace /path/to/Gnau.app

# Analyze hot paths
# Verify Harper analysis <500ms for 10K words
# Verify incremental analysis <20ms
```

#### Allocations (T147)
```bash
# Record memory allocations
instruments -t "Allocations" -D allocations.trace /path/to/Gnau.app

# Check for:
# - Memory leaks (should be 0)
# - Steady-state memory <100MB
# - No unbounded growth
```

#### Leaks (T147)
```bash
# Detect memory leaks
instruments -t "Leaks" -D leaks.trace /path/to/Gnau.app

# Verify: 0 leaks reported
```

---

## Final Validation Checklist

### Functional Requirements
- [ ] All 5 user stories work as specified
- [ ] Real-time detection <20ms
- [ ] Suggestion application works
- [ ] Error dismissal works
- [ ] Per-app settings work
- [ ] Custom vocabulary works
- [ ] Onboarding flow works
- [ ] Permission handling works

### Performance Requirements
- [ ] 10K word analysis <500ms
- [ ] Incremental analysis <20ms
- [ ] Memory usage <100MB
- [ ] No UI blocking
- [ ] No dropped characters

### Accessibility Requirements
- [ ] VoiceOver support complete
- [ ] Keyboard navigation works
- [ ] Dynamic Type supported
- [ ] High contrast mode works
- [ ] Color-blind friendly indicators

### Reliability Requirements
- [ ] Crash recovery works
- [ ] Permission revocation handled
- [ ] No memory leaks
- [ ] Graceful error handling
- [ ] Structured logging active

---

## Known Limitations

Document any known limitations or edge cases discovered during testing:

1. **Large Documents**: Initial analysis of 20K+ words may take >1 second
2. **Rich Text**: Complex formatting may affect error positioning
3. **Web Apps**: Some web-based editors may have limited AX support
4. **Terminal**: Terminal.app has limited Accessibility API support

---

## Sign-Off

### Testing Completed By
- **Name**: _________________
- **Date**: _________________
- **Build**: _________________

### Issues Found
| # | Severity | Description | Status |
|---|----------|-------------|--------|
| 1 |          |             |        |
| 2 |          |             |        |

### Final Approval
- [ ] All tests passed
- [ ] All critical issues resolved
- [ ] Performance targets met
- [ ] Accessibility validated
- [ ] Ready for release

**Approved By**: _________________ **Date**: _________________
