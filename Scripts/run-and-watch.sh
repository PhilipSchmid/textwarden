#!/bin/bash

# Run Gnau and watch logs in real-time

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/Gnau-azzjcqpbioaartckrqvohqnqkfno/Build/Products/Debug/Gnau.app"

echo -e "${GREEN}🚀 Gnau Runner with Live Logs${NC}"
echo "================================"
echo ""

# 1. Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Gnau.app not found!${NC}"
    echo "Build it first:"
    echo "  xcodebuild -project Gnau.xcodeproj -scheme Gnau build"
    exit 1
fi

# 2. Kill existing instance
if pgrep -x "Gnau" > /dev/null; then
    echo -e "${YELLOW}⚠️  Gnau is already running (PID: $(pgrep -x Gnau))${NC}"
    echo -ne "Killing it... "
    killall Gnau
    sleep 1
    echo "✅"
fi

# 3. Start log streaming in background
echo -e "${BLUE}📊 Starting log stream...${NC}"
echo ""

# Start the log stream in background
(log stream --predicate 'processImagePath CONTAINS "Gnau" AND NOT (subsystem CONTAINS "Preview")' --style compact 2>/dev/null || \
 log stream --predicate 'processImagePath CONTAINS "Gnau"' --style compact 2>/dev/null) | \
 grep -v "PreviewsMessagingOS" | \
 grep -v "DTDeveloperKit" &

LOG_PID=$!

# Give log stream a moment to start
sleep 1

# 4. Launch the app
echo -e "${GREEN}🚀 Launching Gnau...${NC}"
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

open "$APP_PATH"

echo -e "${GREEN}✅ Gnau launched!${NC}"
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
