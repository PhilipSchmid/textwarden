# Contributing to TextWarden

Thank you for your interest in contributing to TextWarden! This guide will help you get started with development.

## Prerequisites

### Required Software

1. **macOS 26+** (Tahoe or later)
   ```bash
   sw_vers  # Check your version
   ```

2. **Xcode 26+** with Command Line Tools
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

5. **Pandoc** (for building Help documentation)
   ```bash
   brew install pandoc
   pandoc --version  # Verify installation
   ```

### Verify Setup

Run these commands to ensure everything is installed correctly:

```bash
sw_vers                           # macOS 26+
xcodebuild -version               # Xcode 26+
rustc --version                   # Rust 1.75+
pandoc --version                  # Pandoc (any recent version)
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
3. Generate Help documentation from markdown files (using Pandoc)
4. Build the Swift application linking against the Rust library

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
│       └── bridge.rs     # Swift-Rust FFI
└── Tests/                # Test suites
```

For a comprehensive understanding of the codebase architecture, design patterns, threading model, and coding principles, see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

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

4. **Testing onboarding flow**:
   ```bash
   make reset-onboarding  # Reset onboarding flag
   make run               # Restart app to see onboarding wizard
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

### Automatic Capability Detection

When TextWarden encounters an unknown application (no pre-configured settings), it automatically profiles the app's accessibility capabilities by probing:

- **Positioning APIs**: AXBoundsForRange, AXBoundsForTextMarkerRange, AXLineForIndex, AXRangeForLine
- **Text replacement**: Whether AXValue is settable (standard vs browser-style replacement)

Based on these probes, TextWarden automatically:
- Selects the best positioning strategies
- Chooses the appropriate text replacement method
- Enables/disables visual underlines

This means most apps work without any configuration. You only need to add custom AppRegistry entries for apps that:
1. Have quirks not detectable by probing (e.g., apps that crash on certain AX calls like Word)
2. Need specific font configurations for accurate underline positioning
3. Require special behavioral flags (typing pause, notification delays)

Profiles are cached to disk (`~/Library/Application Support/TextWarden/strategy-profiles.json`) for 7 days.

To see what TextWarden detected for an app, check the logs (Debug mode):
```
StrategyProfiler: Profiled com.example.app:
  Positioning:
    - BoundsForRange: supported (width:true, height:true, notFrame:true)
    - TextMarkerRange: unsupported
    - LineForIndex: supported, RangeForLine: supported
  Recommendations:
    - Strategies: [rangeBounds, lineIndex, fontMetrics]
    - Visual underlines: enabled
```

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

Only add to AppRegistry if the automatic detection doesn't work correctly, or if an app needs special handling that can't be auto-detected (crashes, font config, behavioral flags).

Edit `Sources/AppConfiguration/AppRegistry.swift`:

```swift
static let myApp = AppConfiguration(
    identifier: "myapp",
    displayName: "My App",
    bundleIDs: ["com.example.myapp"],
    category: .electron,  // .native, .electron, .browser, .custom
    parserType: .generic,
    fontConfig: FontConfig(defaultSize: 14, fontFamily: nil, spacingMultiplier: 1.0),
    horizontalPadding: 8,
    features: AppFeatures(
        visualUnderlinesEnabled: true,  // false if positioning APIs don't work
        textReplacementMethod: .browserStyle,
        requiresTypingPause: true,
        supportsFormattedText: false,
        childElementTraversal: true,
        delaysAXNotifications: false,
        focusBouncesDuringPaste: false,
        requiresFullReanalysisAfterReplacement: true,
        defersTextExtraction: false,
        requiresFrameValidation: false,
        hasTextMarkerIndexOffset: false
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
| `.custom` | Apps with unique behavior | Fully custom configuration |

## Code Style

- **Swift**: Follow existing patterns, use `Logger` instead of `print()`
- **Rust**: Run `cargo fmt` and `cargo clippy`
- **Comments**: Explain "why", not "what"
- **No force unwraps** (`!`) on external data
- **Use centralized constants**: `TimingConstants` for delays, `GeometryConstants` for bounds, `UIConstants` for UI sizing. Never use magic numbers like `0.5` directly - add a named constant instead. See `Sources/AppConfiguration/TimingConstants.swift` for examples.

For detailed coding principles, threading guidelines, and common pitfalls, see **[ARCHITECTURE.md](ARCHITECTURE.md#design-principles)**.

### Logging Guidelines

TextWarden processes sensitive user text, so proper logging hygiene is critical:

**Never log user content:**
```swift
// BAD - leaks user text
Logger.debug("Processing text: '\(userText)'")
Logger.debug("Error in: \(errorText)")
Logger.debug("Suggestion: \(suggestion.originalText) → \(suggestion.suggestedText)")

// GOOD - log metadata only
Logger.debug("Processing text (\(userText.count) chars)")
Logger.debug("Error at range \(error.start)-\(error.end)")
Logger.debug("Applied suggestion (\(suggestion.suggestedText.count) chars)")
```

**Use appropriate log levels:**
- `trace` - High-frequency events (mouse movement, per-character processing)
- `debug` - Routine operations useful for debugging
- `info` - Significant milestones (app launch, analysis complete)
- `warning` - Recoverable issues (API fallbacks, timeouts)
- `error` - Failures that affect functionality
- `critical` - Unrecoverable errors

**Use the appropriate category:**
- `Logger.general` - Default, general application logs
- `Logger.permissions` - Permission checks and changes
- `Logger.analysis` - Grammar/style analysis operations
- `Logger.accessibility` - Accessibility API interactions
- `Logger.ffi` - Rust FFI calls
- `Logger.llm` - Apple Intelligence / LLM operations
- `Logger.ui` - UI updates and positioning
- `Logger.performance` - Performance measurements
- `Logger.errors` - Error conditions
- `Logger.lifecycle` - App lifecycle events
- `Logger.rust` - Logs forwarded from Rust code

**Use consistent prefixes** for log messages:
```swift
Logger.debug("AppleIntelligence: Analysis complete", category: Logger.llm)
Logger.debug("TextMonitor: Focus changed", category: Logger.accessibility)
Logger.debug("AnalysisCoordinator: Started analysis", category: Logger.analysis)
```

Log volume is tracked in the Diagnostics view (by severity), so avoid excessive logging that could impact performance or storage.

## Submitting Changes

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `make ci-check`
5. Submit a pull request

## Getting Help

- [GitHub Issues](https://github.com/philipschmid/textwarden/issues) for bugs
- [GitHub Discussions](https://github.com/philipschmid/textwarden/discussions) for questions and feature requests
