#!/bin/bash

# Test Reset Script for Gnau
# Resets the app to fresh state for testing onboarding

set -e

echo "🧪 Gnau Test Reset Script"
echo "========================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Kill running instances
echo -e "${YELLOW}1. Killing any running Gnau instances...${NC}"
killall Gnau 2>/dev/null || echo "  ℹ️  No running instances found"
sleep 1

# 2. Clear preferences
echo -e "${YELLOW}2. Clearing preferences...${NC}"
defaults delete com.philipschmid.Gnau 2>/dev/null && echo "  ✅ Preferences cleared" || echo "  ℹ️  No preferences found"

# 3. Clear application support
echo -e "${YELLOW}3. Clearing application support folder...${NC}"
if [ -d ~/Library/Application\ Support/Gnau/ ]; then
    rm -rf ~/Library/Application\ Support/Gnau/
    echo "  ✅ Application support cleared"
else
    echo "  ℹ️  No application support folder found"
fi

# 4. Check accessibility permission status
echo -e "${YELLOW}4. Checking Accessibility permission status...${NC}"
if grep -q "Gnau" "/Library/Application Support/com.apple.TCC/TCC.db" 2>/dev/null; then
    echo -e "  ${RED}⚠️  Gnau still has Accessibility permission${NC}"
    echo "  📝 To fully reset, manually remove from:"
    echo "     System Settings → Privacy & Security → Accessibility"
    echo ""
    read -p "  Press Enter to open System Settings..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
else
    echo "  ✅ No Accessibility permission found"
fi

echo ""
echo -e "${GREEN}✅ Reset complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. If needed, remove Gnau from Accessibility in System Settings"
echo "  2. Launch Gnau from Xcode or Finder"
echo "  3. Follow TESTING_GUIDE.md for comprehensive testing"
echo ""
echo "Quick smoke test:"
echo "  ./Scripts/quick-test.sh"
echo ""
