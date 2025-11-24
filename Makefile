# Makefile for TextWarden Grammar Checker
# macOS-native grammar checker with Rust + Swift

.PHONY: help build run test clean reset logs quick-test install dev all

# Default target
.DEFAULT_GOAL := help

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Project paths
PROJECT := TextWarden.xcodeproj
SCHEME := TextWarden
CONFIGURATION := Debug
BUILD_DIR := $(HOME)/Library/Developer/Xcode/DerivedData/TextWarden-*/Build/Products/$(CONFIGURATION)
APP_NAME := TextWarden.app
RUST_DIR := GrammarEngine

##@ General

help: ## Display this help message
	@echo "$(GREEN)TextWarden Grammar Checker - Build Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "$(BLUE)Usage:$(NC)\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Building

build-rust: ## Build Rust grammar engine (universal binary)
	@echo "$(BLUE)🦀 Building Rust grammar engine...$(NC)"
	@./Scripts/build-rust.sh
	@echo "$(GREEN)✅ Rust build complete$(NC)"

build-swift: ## Build Swift/Xcode project
	@echo "$(BLUE)🍎 Building Swift app...$(NC)"
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) build | grep -E "(error:|warning:|Building|Linking|^Build|SUCCEEDED|FAILED)" || true
	@if xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) build 2>&1 | grep -q "BUILD SUCCEEDED"; then \
		echo "$(GREEN)✅ Swift build complete$(NC)"; \
	else \
		echo "$(RED)❌ Swift build failed$(NC)"; \
		exit 1; \
	fi

build: build-rust build-swift ## Build everything (Rust + Swift)

rebuild: clean build ## Clean and rebuild everything

##@ Running

run: ## Build, install to /Applications, and run with live logs
	@echo "$(GREEN)🚀 Building and running TextWarden...$(NC)"
	@make -s build-swift
	@make -s install
	@make -s run-only

run-only: ## Run TextWarden from /Applications without rebuilding
	@echo "$(GREEN)🚀 Launching TextWarden from /Applications...$(NC)"
	@if pgrep -x "TextWarden" > /dev/null; then \
		echo "$(YELLOW)⚠️  TextWarden is already running (PID: $$(pgrep -x TextWarden))$(NC)"; \
		echo "Killing it..."; \
		killall TextWarden; \
		sleep 1; \
	fi
	@open /Applications/TextWarden.app
	@echo "$(GREEN)✅ TextWarden launched from /Applications$(NC)"
	@echo "$(BLUE)Watch logs with: make logs$(NC)"

xcode: ## Open in Xcode
	@echo "$(BLUE)📱 Opening Xcode...$(NC)"
	@open $(PROJECT)

##@ Testing

test: test-rust quick-test ## Run all tests (Rust unit tests + Swift smoke tests)

test-rust: ## Run Rust library tests
	@echo "$(BLUE)🦀 Running Rust tests...$(NC)"
	@export PATH="$$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$$PATH" && \
	 cd $(RUST_DIR) && cargo test --lib && echo "$(GREEN)✅ Rust tests passed$(NC)"

update-terminology: ## Regenerate IT terminology wordlist from sources
	@echo "$(BLUE)📝 Regenerating IT terminology wordlist...$(NC)"
	@cd $(RUST_DIR)/it_terminology_extraction/scripts && ./regenerate_wordlist.sh
	@echo "$(GREEN)✅ Terminology wordlist updated$(NC)"

quick-test: ## Run automated smoke tests
	@echo "$(BLUE)🧪 Running quick tests...$(NC)"
	@./Scripts/quick-test.sh

reset: ## Reset app to fresh state (clear permissions & preferences)
	@echo "$(YELLOW)🔄 Resetting TextWarden to fresh state...$(NC)"
	@./Scripts/test-reset.sh

test-guide: ## Open comprehensive testing guide
	@echo "$(BLUE)📖 Opening testing guide...$(NC)"
	@if command -v bat > /dev/null 2>&1; then \
		bat TESTING_GUIDE.md; \
	elif command -v less > /dev/null 2>&1; then \
		less TESTING_GUIDE.md; \
	else \
		cat TESTING_GUIDE.md; \
	fi

##@ Development

dev: ## Full dev cycle: clean, build, install, and run from /Applications
	@make -s clean
	@make -s build
	@make -s install
	@make -s run-only

logs: ## Watch live logs from running TextWarden instance (TextWarden subsystem only)
	@echo "$(BLUE)📊 Watching TextWarden logs (Ctrl+C to stop)...$(NC)"
	@log stream --predicate 'subsystem == "com.textwarden.app"' --style compact --color always 2>/dev/null || \
	 log stream --predicate 'subsystem == "com.textwarden.app"' --style compact 2>&1

oslogs: ## Watch ALL system logs from TextWarden process (includes Foundation, etc.)
	@echo "$(BLUE)📊 Watching ALL TextWarden system logs - includes low-level frameworks (Ctrl+C to stop)...$(NC)"
	@echo "$(YELLOW)⚠️  This includes Foundation and other system framework logs$(NC)"
	@log stream --predicate 'processImagePath CONTAINS "TextWarden"' --style compact --color always 2>/dev/null || \
	 log stream --predicate 'process == "TextWarden"' --style compact 2>&1

kill: ## Kill running TextWarden instance
	@if pgrep -x "TextWarden" > /dev/null; then \
		echo "$(YELLOW)⚠️  Killing TextWarden (PID: $$(pgrep -x TextWarden))...$(NC)"; \
		killall TextWarden; \
		echo "$(GREEN)✅ TextWarden terminated$(NC)"; \
	else \
		echo "$(BLUE)ℹ️  TextWarden is not running$(NC)"; \
	fi

status: ## Check if TextWarden is running and show stats
	@echo "$(BLUE)📊 TextWarden Status$(NC)"
	@echo "━━━━━━━━━━━━━━"
	@if pgrep -x "TextWarden" > /dev/null; then \
		echo "$(GREEN)✅ Running$(NC) (PID: $$(pgrep -x TextWarden))"; \
		echo ""; \
		echo "Memory usage:"; \
		ps -o pid,rss,vsz,command -p $$(pgrep -x TextWarden) | tail -1; \
		echo ""; \
		echo "CPU usage:"; \
		top -pid $$(pgrep -x TextWarden) -l 1 -stats pid,cpu,time | tail -1; \
	else \
		echo "$(RED)❌ Not running$(NC)"; \
	fi
	@echo ""
	@echo "Permission status:"
	@defaults read com.philipschmid.TextWarden 2>/dev/null && echo "$(GREEN)✅ Preferences exist$(NC)" || echo "$(YELLOW)⚠️  No preferences found$(NC)"

##@ Cleaning

clean-rust: ## Clean Rust build artifacts
	@echo "$(YELLOW)🧹 Cleaning Rust build...$(NC)"
	@cd $(RUST_DIR) && cargo clean
	@echo "$(GREEN)✅ Rust clean complete$(NC)"

clean-swift: ## Clean Xcode build artifacts
	@echo "$(YELLOW)🧹 Cleaning Xcode build...$(NC)"
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) clean | grep -E "(Cleaning|Clean.Remove|^Clean)" || true
	@echo "$(GREEN)✅ Xcode clean complete$(NC)"

clean-derived: ## Remove Xcode DerivedData
	@echo "$(YELLOW)🧹 Removing DerivedData...$(NC)"
	@rm -rf ~/Library/Developer/Xcode/DerivedData/TextWarden-*
	@echo "$(GREEN)✅ DerivedData removed$(NC)"

clean: clean-swift ## Clean build artifacts (Swift only, keeps Rust)

clean-all: clean-rust clean-swift clean-derived ## Deep clean everything including Rust

##@ Installation & Distribution

install: build ## Build and install to Applications folder
	@echo "$(BLUE)📦 Installing TextWarden...$(NC)"
	@APP=$$(ls -d $(BUILD_DIR)/$(APP_NAME) 2>/dev/null | head -1); \
	if [ -z "$$APP" ]; then \
		echo "$(RED)❌ App not found. Build first: make build$(NC)"; \
		exit 1; \
	fi; \
	if [ -d "/Applications/$(APP_NAME)" ]; then \
		echo "$(YELLOW)⚠️  Removing existing installation...$(NC)"; \
		rm -rf "/Applications/$(APP_NAME)"; \
	fi; \
	cp -R "$$APP" /Applications/; \
	echo "$(GREEN)✅ Installed to /Applications/$(APP_NAME)$(NC)"

uninstall: ## Remove TextWarden from Applications folder
	@echo "$(YELLOW)🗑️  Uninstalling TextWarden...$(NC)"
	@if [ -d "/Applications/$(APP_NAME)" ]; then \
		rm -rf "/Applications/$(APP_NAME)"; \
		echo "$(GREEN)✅ Uninstalled$(NC)"; \
	else \
		echo "$(BLUE)ℹ️  Not installed in /Applications$(NC)"; \
	fi

##@ Debugging

debug-build: ## Build with verbose output
	@echo "$(BLUE)🔍 Building with verbose output...$(NC)"
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) build

debug-rust: ## Check Rust build status
	@echo "$(BLUE)🦀 Rust Build Status$(NC)"
	@echo "━━━━━━━━━━━━━━━━━━"
	@if [ -f "$(RUST_DIR)/target/universal/release/libgrammar_engine.a" ]; then \
		echo "$(GREEN)✅ Universal library exists$(NC)"; \
		ls -lh $(RUST_DIR)/target/universal/release/libgrammar_engine.a; \
	elif [ -f "$(RUST_DIR)/target/release/libgrammar_engine.a" ]; then \
		echo "$(YELLOW)⚠️  Single-arch library exists$(NC)"; \
		ls -lh $(RUST_DIR)/target/release/libgrammar_engine.a; \
	else \
		echo "$(RED)❌ No library found. Run: make build-rust$(NC)"; \
	fi

debug-swift: ## Show Xcode build paths
	@echo "$(BLUE)🍎 Swift Build Status$(NC)"
	@echo "━━━━━━━━━━━━━━━━━━"
	@APP=$$(ls -d $(BUILD_DIR)/$(APP_NAME) 2>/dev/null | head -1); \
	if [ -n "$$APP" ]; then \
		echo "$(GREEN)✅ App found$(NC)"; \
		echo "Path: $$APP"; \
		echo ""; \
		/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$$APP/Contents/Info.plist" | xargs echo "Version:"; \
		/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$$APP/Contents/Info.plist" | xargs echo "Menu bar app:"; \
	else \
		echo "$(RED)❌ App not found. Run: make build$(NC)"; \
	fi

console: ## Open Console.app filtered to TextWarden
	@echo "$(BLUE)📊 Opening Console.app...$(NC)"
	@open -a Console
	@osascript -e 'tell application "Console" to activate'
	@echo "$(YELLOW)Filter by: process:TextWarden$(NC)"

##@ Shortcuts

all: build ## Alias for 'make build'

check: status ## Alias for 'make status'

start: run ## Alias for 'make run'

stop: kill ## Alias for 'make kill'

restart: ## Kill and restart TextWarden
	@make -s kill
	@sleep 1
	@make -s run-only

##@ Documentation

docs: ## Open all documentation
	@echo "$(BLUE)📚 Documentation Files$(NC)"
	@echo "━━━━━━━━━━━━━━━━━━━"
	@echo "• README: Less common usage"
	@echo "• TESTING_GUIDE.md: Comprehensive testing (80+ tests)"
	@echo "• QUICK_TEST_CHECKLIST.md: 5-minute smoke test"
	@echo "• VERIFICATION.md: Implementation status"
	@echo ""
	@echo "$(YELLOW)Opening QUICK_TEST_CHECKLIST.md...$(NC)"
	@cat QUICK_TEST_CHECKLIST.md

version: ## Show version information
	@echo "$(BLUE)TextWarden Version Information$(NC)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━"
	@grep "CFBundleShortVersionString" Info.plist -A1 | grep string | sed 's/<[^>]*>//g' | xargs echo "App version:"
	@rustc --version 2>/dev/null | xargs echo "Rust:" || echo "Rust: not found"
	@swift --version 2>/dev/null | head -1 | xargs echo "Swift:" || echo "Swift: not found"
	@xcodebuild -version 2>/dev/null | head -1 | xargs echo "Xcode:" || echo "Xcode: not found"

##@ CI/CD

ci: clean build test ## Run full CI pipeline (clean, build, test)
	@echo "$(GREEN)✅ CI pipeline complete$(NC)"

pre-commit: ## Run pre-commit checks
	@echo "$(BLUE)🔍 Running pre-commit checks...$(NC)"
	@echo "Checking Swift formatting..."
	@if command -v swiftlint > /dev/null 2>&1; then \
		swiftlint --quiet; \
		echo "$(GREEN)✅ SwiftLint passed$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  SwiftLint not installed (optional)$(NC)"; \
	fi
	@echo "Checking Rust formatting..."
	@cd $(RUST_DIR) && cargo fmt --check && echo "$(GREEN)✅ Rust formatting passed$(NC)" || echo "$(YELLOW)⚠️  Run: cd $(RUST_DIR) && cargo fmt$(NC)"
	@echo "Running Rust tests..."
	@cd $(RUST_DIR) && cargo test --quiet && echo "$(GREEN)✅ Rust tests passed$(NC)"
	@echo "$(GREEN)✅ Pre-commit checks complete$(NC)"

##@ Quick Recipes

5min-test: build run-only ## Build and run with test instructions
	@sleep 3
	@echo ""
	@echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(GREEN)🧪 5-Minute Smoke Test$(NC)"
	@echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(YELLOW)1. Check menu bar icon$(NC) (top-right corner)"
	@echo "$(YELLOW)2. If onboarding appears:$(NC) Click 'Get Started'"
	@echo "$(YELLOW)3. Grant permission$(NC) in System Settings"
	@echo "$(YELLOW)4. Open TextEdit$(NC)"
	@echo "$(YELLOW)5. Type:$(NC) This are a test"
	@echo "$(YELLOW)6. Verify:$(NC) Popover appears with suggestions"
	@echo ""
	@echo "$(BLUE)Press Ctrl+C in the log window to stop$(NC)"
	@echo ""

fresh-start: clean-all reset build run ## Complete fresh start (deep clean + reset + build + run)
