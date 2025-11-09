# Building Gnau

## ✅ Automated Setup Complete

The Xcode project is **fully configured** and ready to build. No manual setup required!

### What's Been Configured:

- ✅ Xcode project with macOS App target (macOS 15.7+)
- ✅ Source files organized in `Sources/` directory
- ✅ Rust grammar engine in `GrammarEngine/`
- ✅ Build script phase: "Build Rust Grammar Engine" (runs before Swift compilation)
- ✅ Library linking: `libgrammar_engine_universal.a` (x86_64 + arm64)
- ✅ App sandbox: Disabled (required for Accessibility API)
- ✅ Custom Info.plist with `LSUIElement=1` (menu bar app)
- ✅ SwiftLint and Clippy configured

---

## Prerequisites

Before building, ensure you have:

1. **Xcode 15+** (full version, not just command line tools)
   ```bash
   xcodebuild -version
   ```

2. **Rust 1.75+** with macOS targets
   ```bash
   # Install Rust
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

   # Add macOS targets
   rustup target add x86_64-apple-darwin aarch64-apple-darwin
   ```

---

## Building

### Option 1: Build in Xcode (Recommended)

1. Open `Gnau.xcodeproj` in Xcode
2. Select **Gnau** scheme
3. Press **⌘B** (Cmd+B) to build

**Expected:**
- Rust builds first (you'll see "Building Rust grammar engine..." in build log)
- Swift compilation follows
- App builds successfully

### Option 2: Build from Command Line

```bash
xcodebuild -project Gnau.xcodeproj -scheme Gnau -configuration Debug build
```

---

## First Build

The first build will:
1. Download Harper and swift-bridge dependencies (~2 minutes)
2. Compile Rust for x86_64 and arm64 (~3 minutes)
3. Create universal binary (`lipo`)
4. Compile Swift code
5. Link everything together

**Total time:** ~5 minutes for first build, <30 seconds for incremental builds.

---

## Troubleshooting

### "Rust targets not installed"

```bash
rustup target add x86_64-apple-darwin aarch64-apple-darwin
```

### "Permission denied: Scripts/build-rust.sh"

```bash
chmod +x Scripts/build-rust.sh
```

### "Library not found"

The Rust build script should create the library automatically. If it doesn't:

```bash
# Manual build
cd GrammarEngine
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
lipo -create \
  target/x86_64-apple-darwin/release/libgrammar_engine.a \
  target/aarch64-apple-darwin/release/libgrammar_engine.a \
  -output target/libgrammar_engine_universal.a
```

---

## Running

Once built:

1. In Xcode: Press **⌘R** (Cmd+R)
2. Menu bar icon should appear (🔍 or custom icon)
3. Grant Accessibility permissions when prompted

---

## Development Workflow

### Making Changes

**Rust changes:**
1. Edit `GrammarEngine/src/*.rs`
2. Build in Xcode (⌘B) - Rust rebuilds automatically
3. Test changes

**Swift changes:**
1. Edit `Sources/**/*.swift`
2. Build in Xcode (⌘B)
3. Test changes

### Running Tests

**Swift tests:**
```bash
⌘U in Xcode
# or
xcodebuild test -scheme Gnau
```

**Rust tests:**
```bash
cd GrammarEngine
cargo test
```

---

## What's Next?

Once the project builds successfully, you're ready for:

1. **Phase 2**: Implement Rust FFI layer (Harper integration)
2. **Phase 3**: Implement Swift UI and Accessibility integration
3. **Testing**: Unit, integration, and performance tests

The project structure is ready for development!
