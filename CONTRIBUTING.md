# Contributing to TextWarden

Thank you for your interest in contributing to TextWarden! This guide will help you get started with development.

## Prerequisites

### Required Software

1. **macOS 14+** (Sonoma or later)
   ```bash
   sw_vers  # Check your version
   ```

2. **Xcode 15+** with Command Line Tools
   ```bash
   # Install from Mac App Store, then:
   xcode-select --install
   xcodebuild -version  # Verify installation
   ```

3. **Rust 1.75+** with both macOS targets (Intel and Apple Silicon)

   Install Rust via [rustup](https://www.rust-lang.org/tools/install), then add the required targets:
   ```bash
   # Add required targets for universal binary
   rustup target add x86_64-apple-darwin aarch64-apple-darwin

   # Verify installation
   rustc --version
   rustup target list --installed
   ```

4. **Homebrew** (for additional build tools if needed) - [brew.sh](https://brew.sh)

### Verify Setup

Run these commands to ensure everything is installed correctly:

```bash
sw_vers                           # macOS 14+
xcodebuild -version               # Xcode 15+
rustc --version                   # Rust 1.75+
```

## Quick Start

```bash
# Clone the repository
git clone https://github.com/philipschmid/textwarden.git
cd textwarden

# Build everything (Rust universal binary + Swift app)
make build

# Run tests
make test

# Open in Xcode
open TextWarden.xcodeproj
```

The `make build` command will:
1. Build the Rust grammar engine for both Intel and Apple Silicon
2. Create a universal binary using `lipo`
3. Build the Swift application linking against the Rust library

## Project Structure

```
textwarden/
├── Sources/              # Swift application code
│   ├── App/              # Main application logic
│   ├── UI/               # SwiftUI views
│   ├── Accessibility/    # macOS Accessibility API integration
│   ├── Positioning/      # Error underline positioning strategies
│   ├── ContentParsers/   # App-specific text parsing
│   └── AppConfiguration/ # Per-app configuration registry
├── GrammarEngine/        # Rust grammar checking engine
│   └── src/
│       ├── analyzer.rs   # Harper integration
│       ├── llm/          # LLM model configuration
│       └── bridge.rs     # Swift-Rust FFI
└── Tests/                # Test suites
```

## Development Workflow

### Making Changes

1. **Rust changes** (`GrammarEngine/`):
   ```bash
   cd GrammarEngine
   cargo test          # Run tests
   cargo check         # Quick compilation check
   cd .. && make build # Rebuild everything
   ```

2. **Swift changes** (`Sources/`):
   - Build in Xcode (⌘B)
   - Run tests (⌘U)

3. **Before committing**:
   ```bash
   make ci-check  # Runs formatting, linting, tests, and build
   ```

### Accessibility Permissions

TextWarden requires Accessibility permissions to monitor text in other applications. When you first run the app, macOS will prompt you to grant permissions. You can also enable it manually:

1. System Settings → Privacy & Security → Accessibility
2. Enable TextWarden in the list

## Adding Application Support

TextWarden uses two configuration systems for applications:

1. **AppRegistry** (`Sources/AppConfiguration/`) - Technical behavior like positioning strategies and text replacement methods
2. **UserPreferences** (`Sources/Models/UserPreferences.swift`) - Default pause/hidden states

Most applications work out of the box with the default configuration. You only need to add custom configuration if an app requires special handling.

### Finding Bundle Identifiers

The easiest way is to use TextWarden's Settings → Applications list. Each app shows its bundle identifier with a copy icon next to it.

Alternatively, use the terminal:
```bash
osascript -e 'id of app "AppName"'
# or
mdls -name kMDItemCFBundleIdentifier /Applications/AppName.app
```

### Adding Default Paused or Hidden Applications

Some applications should be paused or hidden by default because grammar checking isn't useful or causes false positives. Edit `Sources/Models/UserPreferences.swift`:

**Hidden by default** - Apps that don't appear in the Applications list (system utilities, background services):
```swift
static let defaultHiddenApplications: Set<String> = [
    // ... existing entries ...
    "com.example.myapp",  // My App - reason for hiding
]
```

**Paused by default** - Apps shown in the list but paused (user can enable):
```swift
static let defaultPausedApplications: Set<String> = [
    "com.apple.iCal",     // Apple Calendar
    "com.example.myapp",  // My App - reason for pausing
]
```

**Terminal applications** - Special category, always paused to avoid false positives from command output:
```swift
static let terminalApplications: Set<String> = [
    // ... existing entries ...
    "com.example.terminal",  // My Terminal
]
```

### Adding Custom App Behavior

Only add to AppRegistry if an app needs special technical handling (positioning, text replacement, etc.).

Edit `Sources/AppConfiguration/AppRegistry.swift`:

```swift
static let myApp = AppConfiguration(
    identifier: "myapp",
    displayName: "My App",
    bundleIDs: ["com.example.myapp"],
    category: .electron,  // .native, .electron, .browser, .terminal
    parserType: .generic,
    fontConfig: FontConfig(defaultSize: 14, fontFamily: nil, spacingMultiplier: 1.0),
    horizontalPadding: 8,
    features: AppFeatures(
        visualUnderlinesEnabled: true,  // false if positioning APIs don't work
        textReplacementMethod: .browserStyle,
        requiresTypingPause: true,
        supportsFormattedText: false,
        childElementTraversal: true,
        delaysAXNotifications: false
    )
)

// Register in registerBuiltInConfigurations()
private func registerBuiltInConfigurations() {
    // ... existing registrations ...
    register(.myApp)
}
```

### Testing Accessibility APIs

Use Accessibility Inspector (Xcode → Open Developer Tool) to test if the app's accessibility APIs return valid character bounds. If `AXBoundsForRange` returns garbage values, set `visualUnderlinesEnabled: false`.

### App Categories

| Category | Use For | Notes |
|----------|---------|-------|
| `.native` | Standard macOS apps | Full functionality |
| `.electron` | Electron apps (Slack, VSCode) | May need custom positioning |
| `.browser` | Web browsers | Underlines usually disabled |
| `.terminal` | Terminal emulators | Text parsing only |

## Adding AI Models

TextWarden supports GGUF-quantized language models for style suggestions via [mistral.rs](https://github.com/EricLBuehler/mistral.rs). Model configurations are defined in both Rust and Swift (kept in sync).

### Supported Architectures

Models must be supported by mistral.rs. Currently supported architectures include:

- Llama (Llama 2, 3, 3.1, 3.2)
- Qwen2, Qwen3
- Phi2, Phi3

See the [mistral.rs documentation](https://github.com/EricLBuehler/mistral.rs#supported-models) for the full list of supported model architectures.

### Adding a New Model

1. **Find a compatible GGUF model** on HuggingFace (e.g., from [bartowski](https://huggingface.co/bartowski))
   - Must be a supported architecture (see above)
   - Recommended: Q4_K_M quantization, 1-3B parameters

2. **Add to Rust** (`GrammarEngine/src/llm/config.rs`):
   ```rust
   ModelConfig {
       id: "model-id",
       name: "Model Name",
       filename: "model-q4_k_m.gguf",
       download_url: "https://huggingface.co/.../resolve/main/model-q4_k_m.gguf",
       size_bytes: 1_000_000_000,
       context_length: 8192,
       speed_rating: 7.5,
       quality_rating: 8.0,
       languages: &["en"],
       description: "Brief description.",
       tier: ModelTier::Balanced,
   },
   ```

3. **Add to Swift** (`Sources/GrammarBridge/ModelManager.swift`):
   ```swift
   ModelConfig(
       id: "model-id",
       name: "Model Name",
       vendor: "Vendor",
       filename: "model-q4_k_m.gguf",
       downloadUrl: "https://huggingface.co/.../resolve/main/model-q4_k_m.gguf",
       sizeBytes: 1_000_000_000,
       speedRating: 7.5,
       qualityRating: 8.0,
       languages: ["en"],
       isMultilingual: false,
       description: "Brief description.",
       tier: .balanced,
       isDefault: false
   ),
   ```

4. **Verify**: `make ci-check`

## Code Style

- **Swift**: Follow existing patterns, use `Logger` instead of `print()`
- **Rust**: Run `cargo fmt` and `cargo clippy`
- **Comments**: Explain "why", not "what"
- **No force unwraps** (`!`) on external data

## Submitting Changes

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `make ci-check`
5. Submit a pull request

## Getting Help

- [GitHub Issues](https://github.com/philipschmid/textwarden/issues) for bugs
- [GitHub Discussions](https://github.com/philipschmid/textwarden/discussions) for questions and feature requests
