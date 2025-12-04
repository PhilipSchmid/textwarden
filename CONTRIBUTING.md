# Quickstart: TextWarden Development Setup

**Purpose**: Get a development environment running for TextWarden grammar checker

**Time**: ~20 minutes

---

## Prerequisites

### Required Software

1. **macOS 15.7+ (Sequoia or later)**
   - Check version: `sw_vers`
   - TextWarden targets macOS 15.7+ exclusively

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
git clone https://github.com/YOUR_USERNAME/textwarden.git
cd textwarden
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
open TextWarden.xcodeproj
```

### 2. Configure Build Settings

1. Select **TextWarden** target in Xcode
2. Go to **Build Settings**
3. Search for "Library Search Paths"
4. Add: `$(SRCROOT)/GrammarEngine/target`
5. Search for "Other Linker Flags"
6. Add: `-lgrammar_engine_universal`

### 3. Link Rust Library

1. Select **TextWarden** target → **General** tab
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

TextWarden requires Accessibility permissions to monitor text in other applications.

### Option 1: Grant to Xcode (Recommended for Development)

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the lock icon (🔒) and authenticate
3. Click **+** button
4. Navigate to `/Applications/Xcode.app` and add it
5. Enable checkbox next to Xcode

Now apps run from Xcode inherit Accessibility permissions.

### Option 2: Grant to Built App

1. Build and run TextWarden from Xcode (⌘R)
2. When prompted, click "Open System Settings"
3. Enable TextWarden in Accessibility list
4. Restart TextWarden

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

## Run TextWarden

### From Xcode

1. Select **TextWarden** scheme
2. Press **⌘R** (Cmd+R) to run
3. Menu bar icon should appear (look for TextWarden icon in top-right)
4. Click icon → **Preferences** to verify UI loads

### From Terminal (Release Build)

```bash
cd ~/Library/Developer/Xcode/DerivedData/TextWarden-*/Build/Products/Release/
open TextWarden.app
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

## Adding LLM Models

TextWarden uses a dual-architecture for LLM model definitions: a primary Rust configuration with a Swift fallback. Both must be kept in sync.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Model Configuration                       │
├─────────────────────────────────────────────────────────────┤
│  PRIMARY: GrammarEngine/src/llm/config.rs (Rust)            │
│           ↓ via FFI                                         │
│  FALLBACK: Sources/GrammarBridge/ModelManager.swift (Swift) │
│           (used when FFI unavailable during app startup)    │
└─────────────────────────────────────────────────────────────┘
```

### Step-by-Step: Adding a New Model

#### 1. Find a Compatible Model

TextWarden uses **GGUF quantized models** via mistral.rs. Look for models on HuggingFace:

- Search for the model name + "GGUF"
- Recommended quantization: `Q4_K_M` (good balance of size/quality)
- Recommended size: 1-3B parameters (fast inference on macOS)
- Check license compatibility
- **IMPORTANT**: Verify GGUF architecture compatibility (see below)

**Supported GGUF Architectures** (mistral.rs):
| Architecture | Example Models |
|--------------|----------------|
| Llama | Llama 3.2, Llama 3.1, Llama 2 |
| Phi2 | Phi-2 |
| Phi3 | Phi-3, Phi-3.5 |
| Starcoder2 | StarCoder2 |
| Qwen2 | Qwen 2, Qwen 2.5 |
| Qwen3 | Qwen 3 |
| Qwen3MoE | Qwen 3 MoE variants |

**Not Supported** (GGUF format):
- Gemma, Gemma 2 (use safetensors format only)
- SmolLM, SmolLM2, SmolLM3 (use safetensors format only)
- Mistral (ironically, only safetensors supported in mistral.rs)

Example sources:
- https://huggingface.co/bartowski (popular GGUF conversions)
- https://huggingface.co/TheBloke (another popular source)
- Original model repos with GGUF releases

#### 2. Gather Model Information

You'll need:
- **id**: Short identifier (e.g., `"qwen2.5-1.5b"`)
- **name**: Display name (e.g., `"Qwen 2.5 1.5B"`)
- **filename**: Exact GGUF filename from HuggingFace
- **download_url**: Direct download URL to the GGUF file
- **size_bytes**: File size in bytes (check HuggingFace for exact size)
- **context_length**: Model's context window size
- **speed_rating**: 1.0-10.0 (higher = faster, based on benchmarks)
- **quality_rating**: 1.0-10.0 (higher = better output quality)
- **languages**: Array of ISO 639-1 language codes supported
- **description**: Brief description for UI
- **tier**: Model category (see below)

#### 3. Choose the Model Tier

```rust
pub enum ModelTier {
    Lightweight,  // Fast, small models for quick suggestions
    Balanced,     // Good balance of speed and quality (default)
    Accurate,     // High quality, may be slower
}
```

#### 4. Add to Rust Configuration

Edit `GrammarEngine/src/llm/config.rs`:

```rust
// Add to AVAILABLE_MODELS array (maintain order by tier, then quality)
ModelConfig {
    id: "your-model-id",
    name: "Your Model Name",
    filename: "model-file-q4_k_m.gguf",
    download_url: "https://huggingface.co/.../resolve/main/model-file-q4_k_m.gguf",
    size_bytes: 2_000_000_000,  // ~2.0 GB
    context_length: 8192,
    speed_rating: 7.5,
    quality_rating: 8.0,
    languages: &["en", "de", "fr"],  // Languages supported
    description: "Brief description for users.",
    tier: ModelTier::Balanced,
},
```

#### 5. Add to Swift Fallback

Edit `Sources/GrammarBridge/ModelManager.swift`:

```swift
// Add to defaultModelConfigs array (same order as Rust)
ModelConfig(
    id: "your-model-id",
    name: "Your Model Name",
    vendor: "VendorName",
    filename: "model-file-q4_k_m.gguf",
    downloadUrl: "https://huggingface.co/.../resolve/main/model-file-q4_k_m.gguf",
    sizeBytes: 2_000_000_000,  // Must match Rust
    speedRating: 7.5,
    qualityRating: 8.0,
    languages: ["en", "de", "fr"],
    isMultilingual: true,  // true if languages.count > 1
    description: "Brief description for users.",
    tier: .balanced,
    isDefault: false  // Only one model should be default
),
```

#### 6. Verify Build

```bash
# Test Rust compilation
cd GrammarEngine && cargo check

# Test full build
cd .. && make build
```

#### 7. Test the Model

1. Build and run TextWarden
2. Go to Preferences → Models
3. Verify the new model appears in the list
4. Download the model
5. Select it as active
6. Test style suggestions in a text editor

### Checklist for Adding Models

- [ ] Model ID is unique and follows naming convention (`vendor-size`)
- [ ] Filename exactly matches HuggingFace file
- [ ] Download URL is direct link to GGUF file (ends in `.gguf`)
- [ ] Size in bytes is accurate (check HuggingFace)
- [ ] Both Rust and Swift configs are in sync
- [ ] Model is placed in correct position (by tier, then quality)
- [ ] `cargo check` passes
- [ ] `make build` succeeds
- [ ] Model appears in Preferences UI
- [ ] Model downloads successfully
- [ ] Model generates reasonable suggestions

### Automatic Statistics Tracking

When you add a new model, statistics are automatically tracked:
- **UserStatistics.swift**: Tracks usage per modelId via `StyleLatencySample`
- **DiagnosticsView.swift**: Includes model info in diagnostic exports

No additional code changes needed - the model ID is tracked automatically.

### Current Models

| ID | Name | Size | Tier | Languages | Architecture |
|----|------|------|------|-----------|--------------|
| qwen2.5-1.5b | Qwen 2.5 1.5B | ~1.0 GB | Balanced | 29+ | Qwen2 |
| qwen3-4b | Qwen 3 4B | ~2.3 GB | Accurate | 100+ | Qwen3 |
| phi3-mini | Phi-3 Mini | ~2.3 GB | Accurate | en | Phi3 |
| qwen3-1.7b | Qwen 3 1.7B | ~1.0 GB | Balanced | 100+ | Qwen3 |
| llama-3.2-3b | Llama 3.2 3B | ~2.0 GB | Balanced | 8 | Llama |
| llama-3.2-1b | Llama 3.2 1B | ~0.8 GB | Lightweight | 8 | Llama |
| qwen3-0.6b | Qwen 3 0.6B | ~378 MB | Lightweight | 100+ | Qwen3 |

---

## Adding Application Support

TextWarden uses a centralized `AppConfiguration` system to define app-specific behavior. To add support for a new application:

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    AppRegistry                               │
│  (Single source of truth for all app configurations)        │
├─────────────────────────────────────────────────────────────┤
│  - slack: AppConfiguration     (underlines enabled)         │
│  - teams: AppConfiguration     (underlines disabled)        │
│  - browsers: AppConfiguration  (underlines disabled)        │
│  - notion: AppConfiguration    (underlines enabled)         │
│  - terminals: AppConfiguration (underlines disabled)        │
│  - default: AppConfiguration   (fallback for unknown apps)  │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  ContentParserFactory          PositionResolver             │
│  (selects parser by app)       (selects strategies by app)  │
└─────────────────────────────────────────────────────────────┘
```

### 1. Add Configuration to AppRegistry

Edit `Sources/AppConfiguration/AppRegistry.swift`:

```swift
// Add a new static configuration
static let myNewApp = AppConfiguration(
    identifier: "mynewapp",
    displayName: "My New App",
    bundleIDs: ["com.example.mynewapp"],
    category: .electron,  // .native, .electron, .browser, .terminal, or .custom
    parserType: .generic, // Use existing parser or create new one
    fontConfig: FontConfig(
        defaultSize: 14,
        fontFamily: nil,
        spacingMultiplier: 1.0
    ),
    horizontalPadding: 8,
    features: AppFeatures(
        visualUnderlinesEnabled: true,  // Set false if AX APIs broken
        textReplacementMethod: .browserStyle,
        requiresTypingPause: true,      // Set false if underlines disabled
        supportsFormattedText: false,
        childElementTraversal: true,
        delaysAXNotifications: false
    )
)

// Register in registerBuiltInConfigurations()
private func registerBuiltInConfigurations() {
    register(.slack)
    register(.teams)
    register(.browsers)
    register(.notion)
    register(.terminals)
    register(.myNewApp)  // Add this line
}
```

### 2. Choose the Right Category

| Category | Use For | Default Behavior |
|----------|---------|------------------|
| `.native` | Standard macOS apps (TextEdit, Notes) | Standard AX APIs, underlines enabled, standard text replacement |
| `.electron` | Electron apps (Slack, Notion, VSCode) | TextMarker strategy, keyboard-based text replacement |
| `.browser` | Web browsers (Chrome, Safari) | Underlines disabled, keyboard-based text replacement |
| `.terminal` | Terminal emulators | Underlines disabled |
| `.custom` | Apps needing unique handling | All strategies enabled |

### 3. Decide on Visual Underlines

Not all apps support accurate character positioning via accessibility APIs. Test the app's AX implementation:

```swift
// Test in code or use Accessibility Inspector
AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForRange", rangeValue, &bounds)
```

| AX API Behavior | Recommendation |
|-----------------|----------------|
| Returns accurate bounds | `visualUnderlinesEnabled: true` |
| Returns garbage/zero values | `visualUnderlinesEnabled: false` |
| Returns window frame instead | `visualUnderlinesEnabled: false` |

**When underlines are disabled**: Text analysis still works, and the floating error indicator provides corrections. This is better than showing inaccurate underlines.

**When underlines are disabled**: Also set `requiresTypingPause: false` since there's no need to wait for positioning API queries.

### 4. Configure Text Replacement Method

The `textReplacementMethod` in `AppFeatures` controls how corrections are applied:

| Method | Use When | How It Works |
|--------|----------|--------------|
| `.standard` | AX API works reliably | Uses `AXUIElementSetAttributeValue` directly |
| `.browserStyle` | AX API fails silently | Selects text, copies to clipboard, pastes replacement |

Most Electron and browser apps need `.browserStyle` because their AX API accepts setValue calls but doesn't actually update the DOM.

### 5. Optional: Create Custom Parser

If the app needs special text handling, create a new parser in `Sources/ContentParsers/`:

```swift
class MyNewAppContentParser: ContentParser {
    let bundleIdentifier: String
    let parserName = "MyNewApp"

    private var config: AppConfiguration {
        AppRegistry.shared.configuration(for: bundleIdentifier)
    }

    // Implement ContentParser protocol methods...
}
```

Then add the parser type to `AppConfiguration.swift` and `ContentParserFactory.swift`.

### 6. Find Bundle Identifier

To find an app's bundle identifier:

```bash
osascript -e 'id of app "AppName"'
# or
mdls -name kMDItemCFBundleIdentifier /Applications/AppName.app
```

### 7. Test

```bash
make ci-check  # Verify build
# Run app and test in the new application
```

### Currently Supported Apps

| App | Underlines | Notes |
|-----|------------|-------|
| Native macOS apps | ✅ | TextEdit, Notes, Mail, etc. |
| Slack | ✅ | ChromiumStrategy for positioning |
| Notion | ✅ | ElementTreeStrategy for positioning |
| Microsoft Teams | ❌ | WebView2 AX APIs broken |
| Web Browsers | ❌ | Too many DOM variations |
| Terminal apps | ❌ | Not useful for command input |

---

## Performance Profiling

### Profile with Instruments

1. In Xcode, **Product** → **Profile** (⌘I)
2. Select **Time Profiler** template
3. Click **Record**
4. Perform grammar checking actions in TextWarden
5. Stop recording
6. Analyze hotspots (look for Rust FFI overhead, Harper analysis time)

**Performance targets**:
- Grammar analysis: <20ms (95th percentile)
- Launch time: <2 seconds
- Memory footprint: <100MB

### Run Performance Tests

```bash
xcodebuild test -scheme TextWarden -only-testing:TextWardenTests/PerformanceTests
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

let logger = Logger(subsystem: "com.textwarden.app", category: "grammar")
logger.debug("Analyzed text: \(textSegment.content)")
```

View logs in **Console.app** (filter by "com.textwarden.app").

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

- **GitHub Issues**: https://github.com/YOUR_USERNAME/textwarden/issues
- **Discussions**: https://github.com/YOUR_USERNAME/textwarden/discussions
- **Contributing**: See [CONTRIBUTING.md](../CONTRIBUTING.md)

---

## Automation Script (Optional)

Save this as `dev-setup.sh` for one-command setup:

```bash
#!/bin/bash
set -e

echo "🔧 Setting up TextWarden development environment..."

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
xcodebuild -scheme TextWarden -configuration Debug build

echo "✅ Setup complete! Open TextWarden.xcodeproj in Xcode to continue."
```

Run: `chmod +x dev-setup.sh && ./dev-setup.sh`

---

## Releasing

Releases are built and signed locally using Sparkle for auto-updates.

### Prerequisites

- Sparkle EdDSA private key in macOS Keychain (generated via `generate_keys`)
- `gh` CLI authenticated with GitHub

### Release Workflow

```bash
# 1. Test with a pre-release first
make release-alpha VERSION=0.2.0-alpha.1

# 2. Review the changes
git log -1 && git diff HEAD~1

# 3. Push to remote
git push && git push --tags

# 4. Upload to GitHub
make release-upload VERSION=0.2.0-alpha.1

# 5. When ready for production (requires typing "release" to confirm)
make release VERSION=0.2.0
git push && git push --tags
make release-upload VERSION=0.2.0
```

### What Happens

`make release VERSION=x.y.z`:
1. Updates `Info.plist` with version and increments build number
2. Builds Rust (with LLM) and archives Swift app
3. Creates signed DMG in `releases/`
4. Signs DMG with Sparkle EdDSA key
5. Updates `appcast.xml` with new release entry
6. Commits changes and creates git tag `vx.y.z`

`make release-upload VERSION=x.y.z`:
1. Creates GitHub release with auto-generated notes from commits
2. Uploads DMG as release asset

### Version Types

| Type | Example | Confirmation |
|------|---------|--------------|
| Alpha | `0.2.0-alpha.1` | None |
| Beta | `0.2.0-beta.1` | None |
| RC | `0.2.0-rc.1` | None |
| Production | `0.2.0` | Must type "release" |

### Make Targets

| Target | Description |
|--------|-------------|
| `make release VERSION=x.y.z` | Build and prepare release |
| `make release-alpha VERSION=x.y.z-alpha.1` | Build alpha (hints version format) |
| `make release-beta VERSION=x.y.z-beta.1` | Build beta |
| `make release-rc VERSION=x.y.z-rc.1` | Build release candidate |
| `make release-upload VERSION=x.y.z` | Upload to GitHub |
| `make release-notes` | Preview release notes |
| `make version` | Show current version |

### Release Notes

Release notes are auto-generated from git commits since the last tag. **You don't need to run anything manually** - notes are generated automatically during `make release` (for appcast.xml) and `make release-upload` (for GitHub release).

Each entry includes:
- Commit message (subject line)
- Short hash linking to GitHub commit
- Author name

Use `make release-notes` to **preview** what will be included before releasing. Write meaningful commit messages as they appear directly in the changelog.
