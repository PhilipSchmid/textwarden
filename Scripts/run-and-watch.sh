#!/bin/bash

# Run TextWarden and watch logs in real-time

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Find the app dynamically from DerivedData (exclude Index.noindex)
APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData/TextWarden-"* -name "TextWarden.app" -path "*/Build/Products/Debug/TextWarden.app" 2>/dev/null | grep -v "Index.noindex" | head -1)

echo -e "${GREEN}🚀 TextWarden Runner with Live Logs${NC}"
echo "================================"
echo ""

# 1. Check if app exists
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ TextWarden.app not found!${NC}"
    echo "Build it first:"
    echo "  make build"
    echo "  or: xcodebuild -project TextWarden.xcodeproj -scheme TextWarden build"
    exit 1
fi

# 2. Kill existing instance
if pgrep -x "TextWarden" > /dev/null; then
    echo -e "${YELLOW}⚠️  TextWarden is already running (PID: $(pgrep -x TextWarden))${NC}"
    echo -ne "Killing it... "
    killall TextWarden
    sleep 1
    echo "✅"
fi

# 3. Start log streaming in background
echo -e "${BLUE}📊 Starting log stream...${NC}"
echo ""

# Start the log stream in background
(log stream --predicate 'processImagePath CONTAINS "TextWarden" AND NOT (subsystem CONTAINS "Preview")' --style compact 2>/dev/null || \
 log stream --predicate 'processImagePath CONTAINS "TextWarden"' --style compact 2>/dev/null) | \
 grep -v "PreviewsMessagingOS" | \
 grep -v "DTDeveloperKit" &

LOG_PID=$!

# Give log stream a moment to start
sleep 1

# 4. Launch the app
echo -e "${GREEN}🚀 Launching TextWarden...${NC}"
echo "App path: $APP_PATH"
echo ""
echo -e "${YELLOW}Watch for these key log messages:${NC}"
echo "  🚀 Application launched"
echo "  📍 Menu bar controller initialized"
echo "  🔐 Accessibility permission status"
echo "  🎬 Button clicked"
echo "  ⏱️  Starting permission polling"
echo "  ✅ Permission granted"
echo ""

# Launch the executable directly in the background
"$APP_PATH/Contents/MacOS/TextWarden" &>/dev/null &

echo -e "${GREEN}✅ TextWarden launched!${NC}"
echo ""
echo -e "${YELLOW}What to do now:${NC}"
echo "  1. Look for the menu bar icon (top-right corner)"
echo "  2. If onboarding appears, click 'Get Started'"
echo "  3. Watch for permission dialog"
echo "  4. After granting permission, open TextEdit"
echo "  5. Type: 'This are a test'"
echo ""
echo -e "${BLUE}Press Ctrl+C to stop watching logs${NC}"
echo ""

# Wait for log stream or user interrupt
wait $LOG_PID 2>/dev/null
