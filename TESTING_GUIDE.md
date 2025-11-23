# Gnau Comprehensive Testing Guide

## Pre-Test Setup

### Prerequisites
- [ ] macOS 13.0+ (Ventura or later)
- [ ] TextEdit or Pages installed
- [ ] Terminal access for viewing logs
- [ ] System Settings access

### Reset Testing Environment

To test the onboarding flow from scratch:

1. **Remove Gnau from Accessibility permissions**:
   ```bash
   # Open System Settings
   open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
   ```
   - Find "Gnau" in the list
   - Uncheck it (or remove it if needed)
   - Close System Settings

2. **Quit Gnau completely**:
   ```bash
   # Kill all instances
   killall Gnau
   ```

3. **Clear preferences** (optional, for full reset):
   ```bash
   # Remove user preferences
   defaults delete com.philipschmid.Gnau 2>/dev/null || true

   # Clear application support folder
   rm -rf ~/Library/Application\ Support/Gnau/
   ```

---

## Test Suite 1: First-Time Setup (User Story 2)

### Test 1.1: Fresh Install Onboarding

**Goal**: Verify onboarding flow completes in <5 minutes

**Steps**:
1. [ ] Launch Gnau from Xcode or Finder
2. [ ] **VERIFY**: Menu bar icon appears (text.badge.checkmark)
3. [ ] **VERIFY**: Onboarding window appears automatically
4. [ ] **VERIFY**: Window shows "Welcome to Gnau" with shield icon
5. [ ] **VERIFY**: All text is visible (no cutoff at top/bottom)
6. [ ] **VERIFY**: Three features listed:
   - Privacy First
   - Real-time Checking
   - System-wide

**Expected**: ✅ Window displays correctly with all content visible

---

### Test 1.2: Permission Request Dialog

**Steps**:
1. [ ] Click "Get Started" button
2. [ ] **VERIFY**: macOS system permission dialog appears
3. [ ] **VERIFY**: Dialog mentions "Accessibility" or "assistive access"
4. [ ] **VERIFY**: Dialog has "Deny" and "Open System Settings" buttons

**Expected**: ✅ Native macOS permission dialog appears

**Screenshot Opportunity**: Take screenshot of permission dialog

---

### Test 1.3: Permission Grant via System Settings

**Steps**:
1. [ ] In permission dialog, click "Open System Settings"
2. [ ] **VERIFY**: System Settings opens to Privacy & Security → Accessibility
3. [ ] **VERIFY**: Onboarding window shows "Permission Request" step with instructions
4. [ ] **VERIFY**: Polling indicator shows "Waiting for permission..."
5. [ ] **START TIMER** ⏱️
6. [ ] In System Settings, click the lock to unlock (enter password)
7. [ ] Find "Gnau" in the list and check the checkbox
8. [ ] **STOP TIMER** ⏱️ (Should detect within 1 second)
9. [ ] **VERIFY**: Onboarding auto-advances to "Verification" step
10. [ ] **VERIFY**: Green checkmark shows "Permission Granted!"

**Expected**: ✅ Detection within 1 second, auto-dismiss works

**Timing Check**: Permission detection should be <1 second

---

### Test 1.4: Verification Step

**Steps**:
1. [ ] **VERIFY**: Verification step shows:
   - Green checkmark icon
   - "Permission Granted!" heading
   - Test instructions (3 steps)
2. [ ] **VERIFY**: "Done" button is visible and enabled
3. [ ] Click "Done"
4. [ ] **VERIFY**: Onboarding window closes
5. [ ] **VERIFY**: Menu bar icon remains visible

**Expected**: ✅ Clean transition, window closes properly

---

### Test 1.5: Onboarding Timeout Handling

**Reset**: Remove Gnau from Accessibility again

**Steps**:
1. [ ] Launch Gnau
2. [ ] Click "Get Started"
3. [ ] Click "Open System Settings" in permission dialog
4. [ ] **DO NOT grant permission**
5. [ ] **WAIT**: Let 5+ minutes pass (or reduce `maxWaitTime` in code for faster testing)
6. [ ] **VERIFY**: After 5 minutes, "Having trouble?" message appears
7. [ ] **VERIFY**: "Retry" button appears
8. [ ] **VERIFY**: "Cancel" button appears
9. [ ] Click "Retry"
10. [ ] **VERIFY**: System Settings reopens

**Expected**: ✅ Timeout warning appears, retry works

**Skip if time-limited**: Reduce timeout in code to 30 seconds for faster testing

---

## Test Suite 2: Real-Time Grammar Detection (User Story 1)

### Test 2.1: Basic Grammar Error Detection

**Prerequisites**: Accessibility permission granted

**Steps**:
1. [ ] Open TextEdit (fresh document)
2. [ ] Type slowly: `This are a test`
3. [ ] **OBSERVE**: Does error get detected?
4. [ ] **VERIFY**: Popover appears near cursor
5. [ ] **VERIFY**: Error shows "subject-verb agreement" or similar
6. [ ] **VERIFY**: Suggestions appear (e.g., "is" instead of "are")

**Expected**: ✅ Error detected, popover shows suggestions

**Debug if failing**: Check Console.app for Gnau logs

---

### Test 2.2: Performance - Detection Speed

**Goal**: Verify <20ms detection time

**Steps**:
1. [ ] In TextEdit, type: `The quick brown fox jumps over the lazy dog.`
2. [ ] Add error: `The team are working on this.`
3. [ ] **OBSERVE**: Time between typing and popover appearance
4. [ ] **ESTIMATE**: Should feel instant (<20ms = imperceptible)

**Expected**: ✅ Nearly instant detection

**Performance Check**: Detection should feel immediate, not delayed

---

### Test 2.3: Suggestion Application

**Steps**:
1. [ ] Type in TextEdit: `This are wrong`
2. [ ] **WAIT**: For popover to appear
3. [ ] **VERIFY**: Popover shows suggestions
4. [ ] **VERIFY**: "Apply" button is visible
5. [ ] Click first suggestion (likely "is")
6. [ ] **VERIFY**: Text changes from "This are wrong" to "This is wrong"
7. [ ] **VERIFY**: Popover disappears
8. [ ] **VERIFY**: No more errors shown for that text

**Expected**: ✅ Suggestion applies correctly, text updated

---

### Test 2.4: Keyboard Navigation in Popover

**Steps**:
1. [ ] Type error: `She dont like it`
2. [ ] **WAIT**: For popover
3. [ ] Press **Down Arrow** key
4. [ ] **VERIFY**: Selection moves to next suggestion (if multiple)
5. [ ] Press **Up Arrow** key
6. [ ] **VERIFY**: Selection moves back
7. [ ] Press **Enter** key
8. [ ] **VERIFY**: Selected suggestion is applied
9. [ ] Type new error: `I has a problem`
10. [ ] Press **Escape** key
11. [ ] **VERIFY**: Popover dismisses

**Expected**: ✅ All keyboard shortcuts work

---

### Test 2.5: Dismiss Error (Session-Based)

**Steps**:
1. [ ] Type error: `They was here`
2. [ ] **WAIT**: For popover
3. [ ] Click "Dismiss" button
4. [ ] **VERIFY**: Popover closes
5. [ ] **VERIFY**: Error no longer highlighted
6. [ ] **DO NOT QUIT GNAU**
7. [ ] Delete the text and retype: `They was here`
8. [ ] **VERIFY**: Error does NOT reappear (dismissed for session)
9. [ ] **QUIT** Gnau completely
10. [ ] **RELAUNCH** Gnau
11. [ ] Type again: `They was here`
12. [ ] **VERIFY**: Error REAPPEARS (session-based dismissal)

**Expected**: ✅ Session-based dismissal works, reappears after restart

---

### Test 2.6: Ignore Rule Permanently

**Steps**:
1. [ ] Type error: `He dont care`
2. [ ] **WAIT**: For popover
3. [ ] Note the rule ID (shown in popover)
4. [ ] Click "Ignore this rule permanently" button
5. [ ] **VERIFY**: Popover closes
6. [ ] Delete text and retype: `He dont care`
7. [ ] **VERIFY**: Error does NOT appear
8. [ ] Type different text with same rule: `She dont care`
9. [ ] **VERIFY**: Error does NOT appear (rule ignored)
10. [ ] **QUIT AND RELAUNCH** Gnau
11. [ ] Type again: `He dont care`
12. [ ] **VERIFY**: Error still does NOT appear (permanent)

**Expected**: ✅ Permanent rule dismissal persists across restarts

**Check Preferences**: Verify rule saved in UserDefaults

---

### Test 2.7: Severity Filtering

**Steps**:
1. [ ] Type text with multiple error types (mix grammar + style)
2. [ ] **OBSERVE**: Which severity levels appear (error/warning/info)
3. [ ] **VERIFY**: Different colors for severities:
   - Red indicator = Error
   - Yellow = Warning
   - Blue = Info
4. [ ] Note which severities show by default

**Expected**: ✅ Different severities visible with color coding

**Future Enhancement**: Test severity filtering in Preferences (not yet implemented)

---

### Test 2.8: Multiple Errors in Same Text

**Steps**:
1. [ ] Type: `This are a example of bad grammer`
   (Contains: "are" → "is", "a example" → "an example", "grammer" → "grammar")
2. [ ] **VERIFY**: Popover appears for first error
3. [ ] Apply or dismiss first error
4. [ ] **VERIFY**: Popover appears for second error
5. [ ] **VERIFY**: All errors are eventually addressable

**Expected**: ✅ Multiple errors handled sequentially

---

### Test 2.9: Long Document Performance

**Goal**: Verify no freezing with large documents

**Steps**:
1. [ ] Open TextEdit
2. [ ] Paste large text (1000+ words):
   ```
   # Use lorem ipsum or any long text
   # Or generate with: https://www.lipsum.com/
   ```
3. [ ] **OBSERVE**: Does UI remain responsive?
4. [ ] Scroll through document
5. [ ] Make small edit near bottom
6. [ ] **VERIFY**: No freezing or lag
7. [ ] **VERIFY**: Grammar checking still works

**Expected**: ✅ Smooth performance, no UI blocking

**Performance Target**: Document should load and analyze without perceptible lag

---

## Test Suite 3: Application Compatibility

### Test 3.1: TextEdit

**Steps**:
1. [ ] Open TextEdit
2. [ ] Create new document
3. [ ] Type error: `I seen it yesterday`
4. [ ] **VERIFY**: Grammar checking works

**Expected**: ✅ Works in TextEdit

---

### Test 3.2: Pages

**Steps**:
1. [ ] Open Pages
2. [ ] Create new document
3. [ ] Type error: `I seen it yesterday`
4. [ ] **VERIFY**: Grammar checking works (or note issues)

**Expected**: ✅ Works in Pages (or document compatibility issues)

---

### Test 3.3: Mail

**Steps**:
1. [ ] Open Mail.app
2. [ ] Compose new email
3. [ ] Type error in body: `I seen it yesterday`
4. [ ] **VERIFY**: Grammar checking works

**Expected**: ✅ Works in Mail

---

### Test 3.4: Messages

**Steps**:
1. [ ] Open Messages
2. [ ] Open conversation or create new
3. [ ] Type error: `I seen it yesterday`
4. [ ] **VERIFY**: Grammar checking works

**Expected**: ✅ Works in Messages

---

### Test 3.5: Safari (Web Forms)

**Steps**:
1. [ ] Open Safari
2. [ ] Go to any website with text input (e.g., Gmail, Twitter)
3. [ ] Type error in text field: `I seen it yesterday`
4. [ ] **VERIFY**: Grammar checking works (or note limitations)

**Expected**: ⚠️ May have limitations depending on web app structure

---

## Test Suite 4: Menu Bar & UI

### Test 4.1: Menu Bar Icon

**Steps**:
1. [ ] **VERIFY**: Menu bar icon is visible (top-right of screen)
2. [ ] **VERIFY**: Icon is `text.badge.checkmark` symbol
3. [ ] **VERIFY**: Icon changes color in dark/light mode
4. [ ] Click menu bar icon
5. [ ] **VERIFY**: Menu appears with options:
   - TextWarden Grammar Checker (disabled header)
   - Preferences...
   - About Gnau
   - Quit Gnau

**Expected**: ✅ Menu bar icon functional with all menu items

---

### Test 4.2: About Dialog

**Steps**:
1. [ ] Click menu bar icon → "About Gnau"
2. [ ] **VERIFY**: About panel appears
3. [ ] **VERIFY**: Shows app name "Gnau"
4. [ ] **VERIFY**: Shows version "1.0"
5. [ ] **VERIFY**: Shows copyright notice
6. [ ] Close about panel

**Expected**: ✅ About dialog shows correct information

---

### Test 4.3: Preferences Window

**Steps**:
1. [ ] Click menu bar icon → "Preferences..." (or Cmd+,)
2. [ ] **VERIFY**: Preferences window opens
3. [ ] **NOTE**: Current implementation status (may be placeholder)

**Expected**: ⚠️ Preferences window exists (content TBD in Phase 5)

---

### Test 4.4: Quit Application

**Steps**:
1. [ ] Click menu bar icon → "Quit Gnau" (or Cmd+Q)
2. [ ] **VERIFY**: Application quits
3. [ ] **VERIFY**: Menu bar icon disappears
4. [ ] **VERIFY**: All windows close

**Expected**: ✅ Clean shutdown

---

## Test Suite 5: Edge Cases & Error Handling

### Test 5.1: Permission Revoked While Running

**Steps**:
1. [ ] Ensure Gnau is running with permission granted
2. [ ] Open System Settings → Privacy & Security → Accessibility
3. [ ] **UNCHECK** Gnau while app is running
4. [ ] Return to TextEdit
5. [ ] Type error: `This are wrong`
6. [ ] **OBSERVE**: What happens?
7. [ ] **VERIFY**: Error message or graceful degradation
8. [ ] **RE-ENABLE** permission
9. [ ] **VERIFY**: Grammar checking resumes

**Expected**: ✅ App handles permission loss gracefully

**Debug**: Check logs for permission loss detection

---

### Test 5.2: App Switch During Analysis

**Steps**:
1. [ ] Open TextEdit, type long paragraph
2. [ ] Quickly switch to another app (Cmd+Tab)
3. [ ] **VERIFY**: No crashes
4. [ ] Switch back to TextEdit
5. [ ] **VERIFY**: Grammar checking still works

**Expected**: ✅ No crashes on app switching

---

### Test 5.3: Empty Text Input

**Steps**:
1. [ ] Open TextEdit
2. [ ] Leave document empty
3. [ ] **VERIFY**: No popover appears
4. [ ] **VERIFY**: No errors in console

**Expected**: ✅ Handles empty input gracefully

---

### Test 5.4: Special Characters

**Steps**:
1. [ ] Type text with emojis: `I seen 😀 it yesterday`
2. [ ] Type text with symbols: `This are @ test #hashtag`
3. [ ] Type text with accents: `This are café résumé`
4. [ ] **VERIFY**: Grammar checking works correctly
5. [ ] **VERIFY**: Text replacement preserves special chars

**Expected**: ✅ Handles Unicode and special characters

---

### Test 5.5: Very Fast Typing

**Steps**:
1. [ ] Open TextEdit
2. [ ] Type very quickly: `thisisatestthisisatestthisisatest`
3. [ ] Add errors rapidly: `I seen I seen I seen`
4. [ ] **VERIFY**: No crashes
5. [ ] **VERIFY**: Errors eventually detected
6. [ ] **VERIFY**: No duplicate popovers

**Expected**: ✅ Handles rapid input without issues

---

## Test Suite 6: Performance & Resource Usage

### Test 6.1: Memory Usage

**Steps**:
1. [ ] Open Activity Monitor
2. [ ] Find "Gnau" process
3. [ ] **RECORD**: Initial memory usage (should be <100MB)
4. [ ] Type in TextEdit for 5 minutes
5. [ ] Check grammar in multiple apps
6. [ ] **RECORD**: Memory after extended use
7. [ ] **VERIFY**: No significant memory leaks

**Expected**: ✅ Memory usage remains <100MB, no leaks

**Performance Target**: Memory usage should be stable, not continuously growing

---

### Test 6.2: CPU Usage

**Steps**:
1. [ ] Open Activity Monitor
2. [ ] Find "Gnau" process
3. [ ] **OBSERVE**: CPU % when idle (should be ~0%)
4. [ ] Type in TextEdit
5. [ ] **OBSERVE**: CPU % during typing (brief spikes OK)
6. [ ] **VERIFY**: CPU returns to ~0% when not typing

**Expected**: ✅ Low CPU usage, returns to idle quickly

---

### Test 6.3: Battery Impact

**MacBook only**:
1. [ ] Disconnect from power
2. [ ] Use Gnau normally for 30 minutes
3. [ ] Check battery percentage drop
4. [ ] **VERIFY**: Reasonable battery consumption

**Expected**: ✅ Minimal battery impact

---

## Test Suite 7: Crash Recovery & Stability

### Test 7.1: Force Quit and Restart

**Steps**:
1. [ ] Run Gnau normally
2. [ ] Force quit via Activity Monitor or `killall Gnau`
3. [ ] **WAIT**: 5 seconds
4. [ ] Relaunch Gnau
5. [ ] **VERIFY**: Launches correctly
6. [ ] **VERIFY**: Preferences retained
7. [ ] **VERIFY**: Ignored rules still ignored

**Expected**: ✅ Clean restart, preferences preserved

---

### Test 7.2: System Restart

**Steps**:
1. [ ] Run Gnau, ignore some rules
2. [ ] Restart macOS
3. [ ] After restart, launch Gnau
4. [ ] **VERIFY**: Ignored rules still ignored
5. [ ] **VERIFY**: All preferences retained

**Expected**: ✅ Survives system restart

---

## Test Results Summary

### Test Completion Checklist

**User Story 2: First-Time Setup**
- [ ] T1.1: Fresh install onboarding
- [ ] T1.2: Permission request dialog
- [ ] T1.3: Permission grant via System Settings
- [ ] T1.4: Verification step
- [ ] T1.5: Onboarding timeout handling

**User Story 1: Real-Time Grammar Detection**
- [ ] T2.1: Basic grammar error detection
- [ ] T2.2: Performance - Detection speed
- [ ] T2.3: Suggestion application
- [ ] T2.4: Keyboard navigation
- [ ] T2.5: Dismiss error (session-based)
- [ ] T2.6: Ignore rule permanently
- [ ] T2.7: Severity filtering
- [ ] T2.8: Multiple errors
- [ ] T2.9: Long document performance

**Application Compatibility**
- [ ] T3.1: TextEdit
- [ ] T3.2: Pages
- [ ] T3.3: Mail
- [ ] T3.4: Messages
- [ ] T3.5: Safari

**Menu Bar & UI**
- [ ] T4.1: Menu bar icon
- [ ] T4.2: About dialog
- [ ] T4.3: Preferences window
- [ ] T4.4: Quit application

**Edge Cases**
- [ ] T5.1: Permission revoked while running
- [ ] T5.2: App switch during analysis
- [ ] T5.3: Empty text input
- [ ] T5.4: Special characters
- [ ] T5.5: Very fast typing

**Performance**
- [ ] T6.1: Memory usage
- [ ] T6.2: CPU usage
- [ ] T6.3: Battery impact (MacBook)

**Stability**
- [ ] T7.1: Force quit and restart
- [ ] T7.2: System restart

---

## Known Issues / Notes

Record any issues found during testing:

1. **Issue**:
   - **Steps to Reproduce**:
   - **Expected**:
   - **Actual**:
   - **Severity**: Critical / High / Medium / Low

2. **Issue**:
   - **Steps to Reproduce**:
   - **Expected**:
   - **Actual**:
   - **Severity**: Critical / High / Medium / Low

---

## Acceptance Criteria Verification

### User Story 1 - Real-time Grammar Detection
- [ ] ✅ Errors detected within 20ms
- [ ] ✅ Popover displays with suggestions
- [ ] ✅ Apply button replaces text correctly
- [ ] ✅ Multiple errors handled sequentially
- [ ] ✅ Ignore rule permanently works

### User Story 2 - First-Time Setup
- [ ] ✅ Menu bar icon appears on launch
- [ ] ✅ Clear permission instructions
- [ ] ✅ Auto-detect permission grant
- [ ] ✅ Grammar checking activates immediately
- [ ] ✅ Setup completes in <5 minutes

---

## Debug Commands

### View Console Logs
```bash
# Watch Gnau logs in real-time
log stream --predicate 'processImagePath contains "Gnau"' --level debug

# Or use Console.app
# Filter: process:Gnau
```

### Check Permission Status
```bash
# Check if Gnau has accessibility permission
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT * FROM access WHERE service='kTCCServiceAccessibility' AND client LIKE '%Gnau%';"
```

### Reset Preferences
```bash
# Clear all preferences
defaults delete com.philipschmid.Gnau

# List current preferences
defaults read com.philipschmid.Gnau
```

### Check Build Info
```bash
# Get app version
defaults read /Users/phisch/Library/Developer/Xcode/DerivedData/TextWarden-*/Build/Products/Debug/TextWarden.app/Contents/Info.plist CFBundleShortVersionString
```

---

## Quick Smoke Test (5 minutes)

For rapid verification:

1. [ ] Launch Gnau → Onboarding appears
2. [ ] Click "Get Started" → Permission dialog appears
3. [ ] Grant permission → Verification step shows
4. [ ] Click "Done" → Window closes
5. [ ] Open TextEdit
6. [ ] Type: `This are a test`
7. [ ] Popover appears with suggestions
8. [ ] Click suggestion → Text fixed
9. [ ] Menu bar icon → Quit works

**If all pass**: ✅ Core functionality working
