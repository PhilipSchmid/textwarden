# Gnau

A privacy-first, offline grammar checker for macOS.

## What is Gnau?

Gnau is a native macOS application that provides real-time grammar checking across all your applications—from TextEdit and Pages to VS Code and Slack. It runs entirely on your device with zero network access, ensuring your writing stays private.

## Why Gnau?

**Privacy First**
- All processing happens locally on your Mac
- Zero network access—your text never leaves your device
- No telemetry, no analytics, no cloud services

**System-Wide**
- Works in any application that supports macOS Accessibility API
- No browser extensions or app-specific plugins needed
- Seamless experience across your entire workflow

**Fast & Lightweight**
- Grammar analysis completes in under 20ms for typical sentences
- Memory footprint under 100MB
- No UI blocking—checks run asynchronously in the background

**Native macOS Experience**
- Built with Swift and SwiftUI
- Follows Apple Human Interface Guidelines
- Supports Dark Mode, VoiceOver, and Dynamic Type

## How It Works

Gnau uses the [Harper](https://github.com/elijah-potter/harper) grammar engine (Rust-based, rule-driven) for grammar analysis. The application integrates with macOS using:

- **Accessibility API**: Monitors text changes across applications
- **Swift/Rust FFI**: High-performance bridge via swift-bridge
- **Native UI**: SwiftUI for preferences and suggestion popovers

## Installation

```bash
brew install --cask gnau
```

After installation, grant Accessibility permissions in **System Settings → Privacy & Security → Accessibility**.

## Features

- Real-time grammar error detection
- Contextual suggestions with explanations
- Application-specific control (enable/disable per app)
- Custom vocabulary (up to 1000 words)
- Severity-based error highlighting (critical/warning/style)
- Keyboard shortcuts for quick corrections

## Requirements

- macOS 13.0 (Ventura) or later
- Intel (x86_64) or Apple Silicon (arm64)

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions.

**Tech Stack:**
- Swift 5.9+ (application layer)
- Rust 1.75+ (grammar engine)
- Harper v0.5+ (grammar rules)
- swift-bridge 1.0+ (FFI)
- SwiftUI + AppKit (UI)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Follow the setup guide in [CONTRIBUTING.md](CONTRIBUTING.md)
4. Write tests for new functionality
5. Ensure code passes SwiftLint and Clippy
6. Submit a pull request

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.

## Why "Gnau"?

Gnau (pronounced "now") is derived from the Welsh word "gnau" meaning "to know" or "to recognize"—fitting for a tool that recognizes grammar patterns in your writing.
