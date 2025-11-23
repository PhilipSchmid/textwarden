#!/bin/bash

# Quick Smoke Test for TextWarden
# Automated checks for critical functionality

set -e

echo "🚀 TextWarden Quick Smoke Test"
echo "========================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

# Helper function for test results
pass() {
    echo -e "  ${GREEN}✅ PASS${NC} - $1"
    ((PASSED++))
}

fail() {
    echo -e "  ${RED}❌ FAIL${NC} - $1"
    ((FAILED++))
}

info() {
    echo -e "  ${BLUE}ℹ️  INFO${NC} - $1"
}

# Test 1: Check if TextWarden is built
echo -e "${YELLOW}Test 1: Build Check${NC}"
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/TextWarden-*/Build/Products/Debug/TextWarden.app"
if ls $APP_PATH 1> /dev/null 2>&1; then
    APP=$(ls -d $APP_PATH | head -1)
    pass "TextWarden.app found at: ${APP}"
else
    fail "TextWarden.app not found. Run 'xcodebuild -project TextWarden.xcodeproj -scheme TextWarden build' first"
    exit 1
fi

# Test 2: Check Info.plist configuration
echo -e "${YELLOW}Test 2: Info.plist Configuration${NC}"
if /usr/libexec/PlistBuddy -c "Print :LSUIElement" "${APP}/Contents/Info.plist" | grep -q "true"; then
    pass "LSUIElement set to true (menu bar app)"
else
    fail "LSUIElement not set correctly"
fi

# Test 3: Check bundle version
echo -e "${YELLOW}Test 3: Version Information${NC}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Contents/Info.plist")
info "App version: $VERSION"

# Test 4: Check Rust library
echo -e "${YELLOW}Test 4: Rust Library Check${NC}"
if [ -f "GrammarEngine/target/universal/release/libgrammar_engine.a" ]; then
    pass "Rust universal library exists"
elif [ -f "GrammarEngine/target/release/libgrammar_engine.a" ]; then
    info "Rust library exists (single architecture)"
else
    fail "Rust library not found. Run './Scripts/build-rust.sh' first"
fi

# Test 5: Check if app is signed
echo -e "${YELLOW}Test 5: Code Signing${NC}"
if codesign -v "${APP}" 2>&1 | grep -q "valid on disk"; then
    pass "App is properly code signed"
else
    info "Code signing status unclear (may still work)"
fi

# Test 6: Check if TextWarden is running
echo -e "${YELLOW}Test 6: Runtime Check${NC}"
if pgrep -x "TextWarden" > /dev/null; then
    info "TextWarden is currently running (PID: $(pgrep -x TextWarden))"
    echo "  Manual checks:"
    echo "  - [ ] Menu bar icon visible?"
    echo "  - [ ] Open TextEdit and type: 'This are a test'"
    echo "  - [ ] Does grammar popover appear?"
else
    info "TextWarden not running. Launch from: ${APP}"
fi

# Test 7: Check preferences
echo -e "${YELLOW}Test 7: Preferences Check${NC}"
if defaults read com.philipschmid.TextWarden 2>/dev/null | grep -q "isEnabled"; then
    pass "Preferences exist"
    info "To view: defaults read com.philipschmid.TextWarden"
else
    info "No preferences found (expected for fresh install)"
fi

# Test 8: Check accessibility permission
echo -e "${YELLOW}Test 8: Accessibility Permission${NC}"
# Note: Can't reliably check this via script, need manual verification
info "Check manually: System Settings → Privacy & Security → Accessibility"
echo "  Is TextWarden in the list and enabled?"

# Summary
echo ""
echo "================================"
echo -e "${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"
echo "================================"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All automated checks passed!${NC}"
    echo ""
    echo "Manual Testing Checklist:"
    echo "  1. [ ] Launch TextWarden"
    echo "  2. [ ] Onboarding appears (if no permission)"
    echo "  3. [ ] Grant permission"
    echo "  4. [ ] Open TextEdit"
    echo "  5. [ ] Type: 'This are a test'"
    echo "  6. [ ] Grammar popover appears"
    echo "  7. [ ] Click suggestion"
    echo "  8. [ ] Text is corrected"
    echo ""
    echo "For comprehensive testing: See TESTING_GUIDE.md"
else
    echo -e "${RED}⚠️  Some checks failed. Review above.${NC}"
    exit 1
fi
