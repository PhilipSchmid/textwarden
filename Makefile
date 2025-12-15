# Makefile for TextWarden Grammar Checker
# macOS-native grammar checker with Rust + Swift

.PHONY: help build build-rust build-swift \
        run run-only install uninstall \
        test test-rust clean clean-all clean-derived \
        ci-check fmt lint logs kill status reset xcode version \
        release release-alpha release-beta release-rc release-upload

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
CONFIGURATION := Release
BUILD_DIR := $(HOME)/Library/Developer/Xcode/DerivedData/TextWarden-*/Build/Products/$(CONFIGURATION)
APP_NAME := TextWarden.app
RUST_DIR := GrammarEngine

##@ Help

help: ## Show this help message
	@echo "$(GREEN)TextWarden - Build Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "$(BLUE)Usage:$(NC) make $(YELLOW)<target>$(NC)\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Building

build: build-rust build-swift ## Build the project

build-rust: ## Build Rust library
	@echo "$(BLUE)🦀 Building Rust grammar engine...$(NC)"
	@./Scripts/build-rust.sh
	@echo "$(GREEN)✅ Rust build complete$(NC)"

build-swift: ## Build Swift app
	@echo "$(BLUE)🍎 Building Swift app...$(NC)"
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) build 2>&1 | \
		grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" || true
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) build 2>&1 | \
		grep -q "BUILD SUCCEEDED" && echo "$(GREEN)✅ Swift build complete$(NC)" || \
		(echo "$(RED)❌ Swift build failed$(NC)" && exit 1)

##@ Running

run: build install run-only ## Build, install, and run

run-only: ## Run from /Applications (no build)
	@if pgrep -x "TextWarden" > /dev/null; then \
		killall TextWarden && sleep 1; \
	fi
	@open /Applications/TextWarden.app
	@echo "$(GREEN)✅ TextWarden launched$(NC)"

kill: ## Stop TextWarden
	@if pgrep -x "TextWarden" > /dev/null; then \
		killall TextWarden; \
		echo "$(GREEN)✅ Stopped$(NC)"; \
	else \
		echo "$(BLUE)Not running$(NC)"; \
	fi

status: ## Show app status
	@if pgrep -x "TextWarden" > /dev/null; then \
		echo "$(GREEN)✅ Running$(NC) (PID: $$(pgrep -x TextWarden))"; \
	else \
		echo "$(RED)Not running$(NC)"; \
	fi

logs: ## Watch app logs
	@echo "$(BLUE)Watching logs (Ctrl+C to stop)...$(NC)"
	@log stream --predicate 'subsystem == "com.textwarden.app"' --style compact --color always 2>/dev/null || \
	 log stream --predicate 'subsystem == "com.textwarden.app"' --style compact

##@ Testing

test: test-rust ## Run all tests

test-rust: ## Run Rust tests
	@echo "$(BLUE)🦀 Running Rust tests...$(NC)"
	@cd $(RUST_DIR) && cargo test
	@echo "$(GREEN)✅ Tests passed$(NC)"

##@ Installation

install: ## Install to /Applications (requires build first)
	@echo "$(BLUE)📦 Installing...$(NC)"
	@APP=$$(ls -d $(BUILD_DIR)/$(APP_NAME) 2>/dev/null | head -1); \
	if [ -z "$$APP" ]; then \
		echo "$(RED)❌ Build first: make build$(NC)"; \
		exit 1; \
	fi; \
	rm -rf "/Applications/$(APP_NAME)" 2>/dev/null || true; \
	cp -R "$$APP" /Applications/; \
	echo "$(GREEN)✅ Installed$(NC)"

uninstall: ## Remove from /Applications
	@rm -rf "/Applications/$(APP_NAME)" 2>/dev/null || true
	@echo "$(GREEN)✅ Uninstalled$(NC)"

##@ Cleaning

clean: ## Clean Swift build
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>&1 | grep -E "^Clean" || true
	@echo "$(GREEN)✅ Cleaned$(NC)"

clean-all: ## Clean everything (Rust + Swift + DerivedData)
	@cd $(RUST_DIR) && cargo clean
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>&1 | grep -E "^Clean" || true
	@rm -rf ~/Library/Developer/Xcode/DerivedData/TextWarden-*
	@echo "$(GREEN)✅ All cleaned$(NC)"

##@ CI/CD

ci-check: ## Run CI checks locally (use before pushing)
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)Running CI checks...$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(YELLOW)[1/4] Checking formatting...$(NC)"
	@cd $(RUST_DIR) && cargo fmt --check
	@echo "$(GREEN)✅ OK$(NC)"
	@echo ""
	@echo "$(YELLOW)[2/4] Running Clippy...$(NC)"
	@cd $(RUST_DIR) && cargo clippy --all-targets -- -D warnings
	@echo "$(GREEN)✅ OK$(NC)"
	@echo ""
	@echo "$(YELLOW)[3/4] Running tests...$(NC)"
	@cd $(RUST_DIR) && cargo test
	@echo "$(GREEN)✅ OK$(NC)"
	@echo ""
	@echo "$(YELLOW)[4/4] Building...$(NC)"
	@make -s build
	@echo ""
	@echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(GREEN)✅ All checks passed! Safe to push.$(NC)"
	@echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"

fmt: ## Format Rust code
	@cd $(RUST_DIR) && cargo fmt
	@echo "$(GREEN)✅ Formatted$(NC)"

lint: ## Run Clippy linter
	@cd $(RUST_DIR) && cargo clippy --all-targets -- -D warnings
	@echo "$(GREEN)✅ Lint passed$(NC)"

##@ Utilities

xcode: ## Open in Xcode
	@open $(PROJECT)

reset: ## Reset app state (clear preferences)
	@./Scripts/test-reset.sh
	@echo "$(GREEN)✅ Reset complete$(NC)"

version: ## Show version info
	@echo "$(BLUE)Versions:$(NC)"
	@grep "CFBundleShortVersionString" Info.plist -A1 2>/dev/null | grep string | sed 's/<[^>]*>//g' | xargs echo "  App:" || echo "  App: unknown"
	@rustc --version 2>/dev/null | sed 's/rustc /  Rust: /' || echo "  Rust: not found"
	@xcodebuild -version 2>/dev/null | head -1 | sed 's/Xcode /  Xcode: /' || echo "  Xcode: not found"

clean-derived: ## Clean Xcode DerivedData
	@rm -rf ~/Library/Developer/Xcode/DerivedData/TextWarden-*
	@echo "$(GREEN)✅ DerivedData cleaned$(NC)"

##@ Releasing

# VERSION can be passed: make release VERSION=0.2.0
VERSION ?=

release: ## Build and prepare a production release (requires confirmation)
	@./Scripts/release.sh release $(VERSION)

release-alpha: ## Build alpha release (e.g., 0.2.0-alpha.1)
	@if [ -z "$(VERSION)" ]; then \
		CURRENT=$$(./Scripts/release.sh version | cut -d' ' -f1 | sed 's/-.*//'); \
		echo "$(YELLOW)Tip: make release-alpha VERSION=$${CURRENT}-alpha.1$(NC)"; \
		exit 1; \
	fi
	@./Scripts/release.sh release $(VERSION)

release-beta: ## Build beta release (e.g., 0.2.0-beta.1)
	@if [ -z "$(VERSION)" ]; then \
		CURRENT=$$(./Scripts/release.sh version | cut -d' ' -f1 | sed 's/-.*//'); \
		echo "$(YELLOW)Tip: make release-beta VERSION=$${CURRENT}-beta.1$(NC)"; \
		exit 1; \
	fi
	@./Scripts/release.sh release $(VERSION)

release-rc: ## Build release candidate (e.g., 0.2.0-rc.1)
	@if [ -z "$(VERSION)" ]; then \
		CURRENT=$$(./Scripts/release.sh version | cut -d' ' -f1 | sed 's/-.*//'); \
		echo "$(YELLOW)Tip: make release-rc VERSION=$${CURRENT}-rc.1$(NC)"; \
		exit 1; \
	fi
	@./Scripts/release.sh release $(VERSION)

release-upload: ## Upload prepared release to GitHub
	@./Scripts/release.sh upload $(VERSION)

release-notes: ## Generate release notes from git commits
	@./Scripts/release.sh notes
