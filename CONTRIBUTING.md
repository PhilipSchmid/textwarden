# Quickstart: Gnau Development Setup

**Purpose**: Get a development environment running for Gnau grammar checker

**Time**: ~20 minutes

---

## Prerequisites

### Required Software

1. **macOS 15.7+ (Sequoia or later)**
   - Check version: `sw_vers`
   - Gnau targets macOS 15.7+ exclusively

2. **Xcode 15+**
   - Install from Mac App Store or https://developer.apple.com/xcode/
   - Verify: `xcodebuild -version`
   - Install Command Line Tools: `xcode-select --install`

3. **Rust 1.75+**
   - Install via rustup: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
   - Verify: `rustc --version` (should be 1.75 or later)
   - Add macOS targets: `rustup target add x86_64-apple-darwin aarch64-apple-darwin`

4. **Homebrew (for dependencies)**
   - Install: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
   - Verify: `brew --version`

---

## Clone Repository

```bash
git clone https://github.com/YOUR_USERNAME/gnau.git
cd gnau
git checkout 001-grammar-checking  # Development branch
```

---

## Rust Grammar Engine Setup

### 1. Navigate to Grammar Engine

```bash
cd GrammarEngine
```

### 2. Install Dependencies

```bash
cargo build --release
```

This downloads Harper and swift-bridge dependencies, compiles Rust code.

**Expected output**:
```
   Compiling harper v0.5.x
   Compiling swift-bridge v1.0.x
   Compiling grammar-engine v0.1.0
    Finished release [optimized] target(s) in 45.2s
```

### 3. Run Rust Tests

```bash
cargo test
```

**Expected output**:
```
running 12 tests
test tests::test_analyze_text_basic ... ok
test tests::test_analyze_text_empty ... ok
test tests::test_performance_under_20ms ... ok
...
test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
```

### 4. Generate Universal Binary

```bash
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
lipo -create \
  target/x86_64-apple-darwin/release/libgrammar_engine.a \
  target/aarch64-apple-darwin/release/libgrammar_engine.a \
  -output target/libgrammar_engine_universal.a
```

This creates a universal binary supporting both Intel and Apple Silicon Macs.

---

## Swift Application Setup

### 1. Open Xcode Project

```bash
cd ..  # Return to repo root
open Gnau.xcodeproj
```

### 2. Configure Build Settings

1. Select **Gnau** target in Xcode
2. Go to **Build Settings**
3. Search for "Library Search Paths"
4. Add: `$(SRCROOT)/GrammarEngine/target`
5. Search for "Other Linker Flags"
6. Add: `-lgrammar_engine_universal`

### 3. Link Rust Library

1. Select **Gnau** target → **General** tab
2. Under **Frameworks, Libraries, and Embedded Content**, click **+**
3. Click **Add Other...** → **Add Files...**
4. Navigate to `GrammarEngine/target/libgrammar_engine_universal.a`
5. Select **Do Not Embed**

### 4. Build Swift Code

Press **⌘B** (Cmd+B) to build the project.

**Expected output in Xcode console**:
```
Build Succeeded
```

If build fails with "library not found", ensure step 2 and 3 completed correctly.

---

## Grant Accessibility Permissions (Development)

Gnau requires Accessibility permissions to monitor text in other applications.

### Option 1: Grant to Xcode (Recommended for Development)

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the lock icon (🔒) and authenticate
3. Click **+** button
4. Navigate to `/Applications/Xcode.app` and add it
5. Enable checkbox next to Xcode

Now apps run from Xcode inherit Accessibility permissions.

### Option 2: Grant to Built App

1. Build and run Gnau from Xcode (⌘R)
2. When prompted, click "Open System Settings"
3. Enable Gnau in Accessibility list
4. Restart Gnau

---

## Run Tests

### Swift Tests

1. In Xcode, press **⌘U** (Cmd+U) to run all tests
2. View results in **Test Navigator** (⌘6)

**Test suites**:
- `Unit/`: Swift logic tests
- `Integration/`: Accessibility API tests (requires permissions)
- `Contract/`: Rust-Swift FFI boundary tests
- `Performance/`: Latency and memory benchmarks

### Rust Tests

```bash
cd GrammarEngine
cargo test
```

---

## Run Gnau

### From Xcode

1. Select **Gnau** scheme
2. Press **⌘R** (Cmd+R) to run
3. Menu bar icon should appear (look for Gnau icon in top-right)
4. Click icon → **Preferences** to verify UI loads

### From Terminal (Release Build)

```bash
cd ~/Library/Developer/Xcode/DerivedData/Gnau-*/Build/Products/Release/
open Gnau.app
```

---

## Verify Grammar Checking Works

1. Open **TextEdit** (bundled with macOS)
2. Type: "The team are working on multiple project"
3. Expected: Red underlines appear under "team are" and "multiple project"
4. Hover over underlined text
5. Expected: Suggestion popover appears with corrections

If no underlines appear:
- Check Accessibility permissions granted (Step 4)
- Check Xcode console for error messages
- Verify Harper compiled successfully (`cargo test` passes)

---

## Development Workflow

### Make Changes to Rust Code

1. Edit files in `GrammarEngine/src/`
2. Run `cargo test` to verify changes
3. Rebuild Rust library: `cargo build --release`
4. Rebuild Swift in Xcode (⌘B)
5. Run app (⌘R)

### Make Changes to Swift Code

1. Edit files in `Sources/`
2. Build in Xcode (⌘B)
3. Run tests (⌘U)
4. Run app (⌘R)

### Modify FFI Interface

1. Edit `GrammarEngine/src/bridge.rs` (Rust)
2. Rebuild Rust: `cargo build --release`
3. swift-bridge auto-generates Swift code
4. Rebuild Swift (may require cleaning build folder: **Product** → **Clean Build Folder**)

---

## Performance Profiling

### Profile with Instruments

1. In Xcode, **Product** → **Profile** (⌘I)
2. Select **Time Profiler** template
3. Click **Record**
4. Perform grammar checking actions in Gnau
5. Stop recording
6. Analyze hotspots (look for Rust FFI overhead, Harper analysis time)

**Performance targets**:
- Grammar analysis: <20ms (95th percentile)
- Launch time: <2 seconds
- Memory footprint: <100MB

### Run Performance Tests

```bash
xcodebuild test -scheme Gnau -only-testing:GnauTests/PerformanceTests
```

View results in Xcode → **Test Navigator** → **Performance** tab.

---

## Debugging Tips

### Enable Rust Debug Symbols

Edit `GrammarEngine/Cargo.toml`:
```toml
[profile.release]
debug = true
```

Rebuild Rust library. Now Instruments shows Rust function names.

### Enable Verbose Logging

In Swift code, use `os_log` for debugging:
```swift
import os.log

let logger = Logger(subsystem: "com.gnau.app", category: "grammar")
logger.debug("Analyzed text: \(textSegment.content)")
```

View logs in **Console.app** (filter by "com.gnau.app").

### Debug Accessibility API Issues

```swift
import Cocoa

let trusted = AXIsProcessTrusted()
print("Accessibility trusted: \(trusted)")
```

If `false`, app cannot monitor text. Grant permissions (see Step 4).

---

## Common Issues

### Issue: "Library not found for -lgrammar_engine_universal"

**Solution**:
1. Ensure Rust library built: `cd GrammarEngine && cargo build --release`
2. Check Xcode **Build Settings** → **Library Search Paths** includes `$(SRCROOT)/GrammarEngine/target`
3. Clean build folder: **Product** → **Clean Build Folder**
4. Rebuild: **⌘B**

### Issue: No grammar errors detected in TextEdit

**Solution**:
1. Check Accessibility permissions granted
2. Verify Rust tests pass: `cd GrammarEngine && cargo test`
3. Check Xcode console for error messages
4. Try typing: "He walk slowly" (simple verb tense error)

### Issue: App crashes on launch

**Solution**:
1. Check Info.plist has `LSUIElement = 1` (menu bar app, no dock icon)
2. Ensure Rust library linked correctly (Step 3 of Swift Setup)
3. View crash log in **Console.app** → **Crash Reports**

---

## Next Steps

- Read [data-model.md](./data-model.md) to understand data structures
- Read [contracts/grammar-engine-ffi.md](./contracts/grammar-engine-ffi.md) for FFI API
- Explore `Sources/` directory for Swift code architecture
- Run `cargo doc --open` in `GrammarEngine/` for Rust documentation

---

## Getting Help

- **GitHub Issues**: https://github.com/YOUR_USERNAME/gnau/issues
- **Discussions**: https://github.com/YOUR_USERNAME/gnau/discussions
- **Contributing**: See [CONTRIBUTING.md](../CONTRIBUTING.md)

---

## Automation Script (Optional)

Save this as `dev-setup.sh` for one-command setup:

```bash
#!/bin/bash
set -e

echo "🔧 Setting up Gnau development environment..."

# Check prerequisites
command -v rustc >/dev/null 2>&1 || { echo "❌ Rust not installed. Run: curl https://sh.rustup.rs -sSf | sh"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "❌ Xcode not installed"; exit 1; }

# Build Rust
echo "📦 Building Rust grammar engine..."
cd GrammarEngine
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
lipo -create \
  target/x86_64-apple-darwin/release/libgrammar_engine.a \
  target/aarch64-apple-darwin/release/libgrammar_engine.a \
  -output target/libgrammar_engine_universal.a

# Run Rust tests
echo "🧪 Running Rust tests..."
cargo test

# Build Swift
echo "📱 Building Swift app..."
cd ..
xcodebuild -scheme Gnau -configuration Debug build

echo "✅ Setup complete! Open Gnau.xcodeproj in Xcode to continue."
```

Run: `chmod +x dev-setup.sh && ./dev-setup.sh`
