#!/bin/bash
set -e

# Build script for Rust grammar engine universal binary
# Creates fat binary supporting both Intel (x86_64) and Apple Silicon (arm64)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GRAMMAR_ENGINE_DIR="$PROJECT_ROOT/GrammarEngine"
TARGET_DIR="$GRAMMAR_ENGINE_DIR/target"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Rust grammar engine...${NC}"

# Check if we're in Xcode build
if [ -n "$ACTION" ] && [ "$ACTION" = "clean" ]; then
    echo -e "${YELLOW}Cleaning Rust build artifacts...${NC}"
    cd "$GRAMMAR_ENGINE_DIR"
    cargo clean
    exit 0
fi

cd "$GRAMMAR_ENGINE_DIR"

# Determine build configuration
if [ "$CONFIGURATION" = "Release" ]; then
    CARGO_BUILD_FLAG="--release"
    BUILD_DIR="release"
else
    CARGO_BUILD_FLAG=""
    BUILD_DIR="debug"
fi

echo -e "${GREEN}Building for x86_64-apple-darwin (${BUILD_DIR})...${NC}"
cargo build $CARGO_BUILD_FLAG --target x86_64-apple-darwin

echo -e "${GREEN}Building for aarch64-apple-darwin (${BUILD_DIR})...${NC}"
cargo build $CARGO_BUILD_FLAG --target aarch64-apple-darwin

# Determine paths based on build type
X86_LIB="$TARGET_DIR/x86_64-apple-darwin/${BUILD_DIR}/libgrammar_engine.a"
ARM_LIB="$TARGET_DIR/aarch64-apple-darwin/${BUILD_DIR}/libgrammar_engine.a"

UNIVERSAL_LIB="$TARGET_DIR/libgrammar_engine_universal.a"

echo -e "${GREEN}Creating universal binary...${NC}"
lipo -create "$X86_LIB" "$ARM_LIB" -output "$UNIVERSAL_LIB"

# Verify the universal binary
echo -e "${GREEN}Verifying universal binary architectures:${NC}"
lipo -info "$UNIVERSAL_LIB"

echo -e "${GREEN}✓ Rust grammar engine build complete${NC}"
echo -e "  Universal binary: $UNIVERSAL_LIB"
