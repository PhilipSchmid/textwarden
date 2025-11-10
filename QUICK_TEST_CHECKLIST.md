# Gnau Quick Test Checklist

## 🚀 Getting Started

### 1. Run Quick Automated Check
```bash
cd /Users/phisch/git/github.com/philipschmid/gnau
./Scripts/quick-test.sh
```

### 2. Reset for Fresh Test (Optional)
```bash
./Scripts/test-reset.sh
```

---

## ✅ 5-Minute Smoke Test

### Phase 1: Onboarding (2 min)
- [ ] Launch Gnau from Xcode or `/Build/Products/Debug/Gnau.app`
- [ ] ✅ Menu bar icon appears (text.badge.checkmark)
- [ ] ✅ Onboarding window appears
- [ ] ✅ All text visible (no cutoff)
- [ ] Click "Get Started"
- [ ] ✅ **Permission dialog appears** ← KEY TEST
- [ ] Click "Open System Settings"
- [ ] ✅ System Settings opens to Accessibility
- [ ] Enable Gnau in the list
- [ ] ✅ **Window auto-advances to verification** ← KEY TEST
- [ ] ✅ Green checkmark shows
- [ ] Click "Done"

### Phase 2: Grammar Detection (2 min)
- [ ] Open **TextEdit** (fresh document)
- [ ] Type: `This are a test`
- [ ] ✅ **Popover appears** ← KEY TEST
- [ ] ✅ Shows suggestion "is"
- [ ] ✅ Has Apply/Dismiss/Ignore buttons
- [ ] Click "Apply" or press Enter
- [ ] ✅ Text changes to "This is a test"
- [ ] ✅ Popover closes

### Phase 3: Additional Features (1 min)
- [ ] Type: `She dont care`
- [ ] Press **Escape** key
- [ ] ✅ Popover dismisses
- [ ] Type again: `She dont care`
- [ ] Press **Down Arrow** (if multiple suggestions)
- [ ] ✅ Selection changes
- [ ] Press **Enter**
- [ ] ✅ Suggestion applies

---

## 🔍 Critical Features to Verify

### Must Work:
1. ✅ Permission dialog appears on first launch
2. ✅ Auto-detection within 1 second of granting permission
3. ✅ Grammar errors detected in TextEdit
4. ✅ Popover appears near cursor
5. ✅ Suggestions can be applied
6. ✅ Keyboard navigation works (Enter, Escape, Arrows)

### Should Work:
7. ✅ Multiple errors handled sequentially
8. ✅ Dismiss removes error for current session
9. ✅ Ignore rule works permanently
10. ✅ Menu bar icon → Quit works

---

## 🐛 Common Issues & Fixes

### Issue: No permission dialog appears
**Fix**: Add this call in OnboardingView.swift:
```swift
case .welcome:
    permissionManager.requestPermission()  // ← Must be here
    currentStep = .permissionRequest
```

### Issue: Content cut off at top
**Fix**: Wrap in ScrollView, set proper frame size (550x550)

### Issue: Grammar not detecting
**Debug**:
```bash
# Check logs
log stream --predicate 'processImagePath contains "Gnau"' --level debug

# Check permission
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

### Issue: Popover doesn't appear
**Check**:
1. TextMonitor receiving text changes?
2. AnalysisCoordinator triggering?
3. Harper engine returning errors?
4. Filters not blocking errors?

---

## 📝 Test Apps to Try

**High Priority:**
- [ ] TextEdit (built-in)
- [ ] Mail (built-in)
- [ ] Messages (built-in)

**Medium Priority:**
- [ ] Pages (if installed)
- [ ] Safari text fields
- [ ] Notes

**Low Priority:**
- [ ] VS Code
- [ ] Slack
- [ ] Any other text apps

---

## 🎯 Performance Checks

### Speed Test
Type this and observe response time:
```
The quick brown fox jumps over the lazy dog. This are a test.
```
- [ ] ✅ Error detected within 20ms (feels instant)
- [ ] ✅ No lag or delay

### Memory Test
```bash
# Check memory usage
top -pid $(pgrep Gnau) -stats pid,command,mem
```
- [ ] ✅ Memory < 100MB
- [ ] ✅ CPU near 0% when idle

### Long Document Test
1. Paste 1000+ words in TextEdit
2. [ ] ✅ No freezing
3. [ ] ✅ UI remains responsive
4. [ ] ✅ Grammar checking still works

---

## 📊 Test Result Summary

**Date**: ___________
**macOS Version**: ___________
**Gnau Version**: 1.0

### Results:
- [ ] ✅ **PASS** - Onboarding works
- [ ] ✅ **PASS** - Grammar detection works
- [ ] ✅ **PASS** - Suggestion application works
- [ ] ✅ **PASS** - Keyboard navigation works
- [ ] ✅ **PASS** - Performance acceptable

### Issues Found:
1. _________________________________
2. _________________________________
3. _________________________________

### Notes:
_________________________________
_________________________________
_________________________________

---

## 🆘 Need Help?

**View detailed logs:**
```bash
# Console logs
log stream --predicate 'processImagePath contains "Gnau"' --level debug

# Or use Console.app
# Filter by: process:Gnau
```

**Check current state:**
```bash
# View preferences
defaults read com.philipschmid.Gnau

# Check if running
ps aux | grep Gnau

# Check permission
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT * FROM access WHERE service='kTCCServiceAccessibility';"
```

**Full reset:**
```bash
./Scripts/test-reset.sh
```

**Comprehensive testing:**
See `TESTING_GUIDE.md` for 80+ detailed test cases.

---

## ✨ Success Criteria

The MVP is ready if:
- ✅ Onboarding completes in <5 minutes
- ✅ Grammar errors detected in <20ms
- ✅ Suggestions apply correctly
- ✅ Works in TextEdit, Mail, Pages
- ✅ No crashes during normal use
- ✅ Memory stays <100MB
- ✅ CPU usage minimal

**If all pass**: 🎉 **MVP READY FOR RELEASE!**
