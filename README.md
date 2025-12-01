
# TextWarden

**Grammar checking that respects your privacy.**

TextWarden checks your spelling and grammar while you type - in any app on your Mac. Unlike online tools, everything runs locally on your computer. Your writing never leaves your device.

<p align="center">
  <img src="Assets/textwarden_logo.svg" alt="TextWarden Logo" width="320" height="320">
</p>

## Core Principles

**Private by Design**
Your text stays on your Mac. There are no cloud servers, no accounts, and no data collection. TextWarden works completely offline.

**Blazingly Fast**
Grammar checking powered by Harper, a high-performance Rust-based engine. Checks complete in milliseconds, so you never notice any delay while typing.

**Works Across Apps**
TextWarden integrates with most macOS applications through the Accessibility API. It works well with Apple Mail, Apple Notes, Pages, Safari, and many other apps. Some applications with limited accessibility support (certain Electron apps or custom text rendering) may have reduced functionality.

**Simple and Unobtrusive**
A small indicator appears when issues are found. Click to see suggestions. Accept with one click or keyboard shortcut. That's it.

## Getting Started

1. Download TextWarden
2. Grant Accessibility permission when prompted (required to read text in other apps)
3. Start typing - TextWarden works automatically in the background

## Features

- Real-time grammar and spelling checks (English only)
- Automatic language detection - non-English text is ignored, not flagged
- One-click corrections
- Custom dictionary for words you use often
- Control which apps TextWarden monitors

## AI-Powered Style Suggestions

Beyond basic grammar checking, TextWarden offers intelligent style suggestions powered by a local AI model running entirely on your Mac. Get recommendations for clearer phrasing, better word choices, and improved readability - all without sending your text to any server. The AI runs on your hardware using Apple Silicon's neural engine, keeping your writing private while providing smart suggestions that go beyond simple rule-based checks.

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 14 or later (optimized for macOS 26)

## Privacy

TextWarden never sends your text anywhere. The only network activity is downloading AI models (optional), which you can also download manually. Block TextWarden in your firewall and it works exactly the same - all grammar checking runs locally on your Mac.

## Credits

TextWarden is built on excellent open source projects:

- [Harper](https://github.com/Automattic/harper) - Fast, privacy-focused grammar checker
- [mistral.rs](https://github.com/EricLBuehler/mistral.rs) - Local LLM inference engine
- [swift-bridge](https://github.com/chinedufn/swift-bridge) - Rust/Swift interoperability
- [whichlang](https://github.com/quickwit-oss/whichlang) - Language detection
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Global keyboard shortcuts for macOS
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) - Launch at login functionality

## License

Apache License 2.0
