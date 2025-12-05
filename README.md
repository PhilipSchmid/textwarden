
# TextWarden

**Grammar checking that respects your privacy.**

TextWarden checks your spelling and grammar while you type - in any app on your Mac. Unlike other tools, everything runs locally on your computer. Your writing never leaves your device. Beyond basic grammar checking, TextWarden also offers optional AI-powered style suggestions using a local language model running entirely on your Mac.

<p align="center">
  <img src="Assets/textwarden_logo.svg" alt="TextWarden Logo" width="320" height="320">
</p>

## Core Principles

**Private by Design**
Your text stays on your Mac. There are no cloud servers, no accounts, and no data collection. TextWarden works completely offline.

**Blazingly Fast**
Grammar checking powered by Harper, a high-performance Rust-based engine. Checks complete in milliseconds, so you never notice any delay while typing.

**Works Across Apps**
TextWarden integrates with most macOS applications through the Accessibility API. It works well with Apple Mail, Apple Notes, Pages, Safari, and many other apps. Some applications with limited accessibility support may have reduced functionality - see [Known Limitations](#known-limitations) for details.

**Simple and Unobtrusive**
A small indicator appears when issues are found. Click to see suggestions. Accept with one click or keyboard shortcut. That's it.

## Getting Started

1. Download TextWarden
2. Grant Accessibility permission when prompted (required to read text in other apps)
3. Start typing - TextWarden works automatically in the background

## Features

### Real-Time Grammar and Spelling

TextWarden continuously monitors your writing and highlights errors as you type. Corrections appear in a popover with one-click apply. Supported error categories include:

- Spelling mistakes and typos
- Grammar errors (subject-verb agreement, tense, etc.)
- Punctuation issues
- Capitalization errors
- Word choice and commonly confused words
- Redundant phrases
- Style improvements

You can enable or disable specific categories in Settings to customize which types of errors are flagged.

### AI-Powered Style Suggestions (Opt-In)

Beyond rule-based grammar checking, TextWarden offers intelligent style suggestions powered by a local AI model running entirely on your Mac. This feature is disabled by default and can be enabled in Settings. The AI analyzes your writing and suggests improvements for clarity, conciseness, and readability - all without sending your text to any server.

Style analysis can be triggered in two ways:

- **Keyboard shortcut**: Press `Cmd+Control+S` (customizable) to run a style check on demand
- **Automatic**: Enable automatic style checking in Settings to analyze text as you type

When using the keyboard shortcut with text selected, only the selected portion is analyzed. Without a selection, the entire text field is analyzed.

Available writing styles: Default, Concise, Formal, Casual, and Business. You can also adjust the confidence threshold to control how many suggestions appear.

### Multilingual Support

TextWarden uses sentence-level language detection to avoid false positives when you mix languages. Each sentence is analyzed independently - if a sentence is detected as German, Spanish, or another non-English language, grammar errors in that sentence are automatically suppressed. This is useful when writing emails that include foreign names, quotes, or phrases like "Freundliche Grüsse" or "Merci beaucoup".

Supported languages for detection include: Spanish, French, German, Italian, Portuguese, Dutch, Russian, Chinese, Japanese, Korean, Arabic, Hindi, Turkish, Swedish, and Vietnamese.

### Custom Dictionary

Add words that TextWarden doesn't recognize to your personal dictionary. This is useful for technical terms, proper nouns, or specialized vocabulary specific to your field. Words in your custom dictionary will never be flagged as spelling errors.

### App-Specific Controls

Control exactly where TextWarden runs:

- Enable or disable checking for specific applications
- Pause checking temporarily (1 hour, 24 hours, or indefinitely)
- Per-app pause controls for fine-grained management
- Disable checking for specific websites when using browsers

### Dialect Support

Choose your preferred English dialect:

- American English
- British English
- Canadian English
- Australian English

TextWarden adjusts spelling and grammar rules accordingly (e.g., "color" vs "colour").

### Website-Specific Controls

When using browsers, TextWarden can be disabled for specific websites. This is useful for sites with custom editors or where you don't want grammar checking enabled.

### Usage Statistics

TextWarden tracks your writing statistics locally, including total errors found, corrections applied, and style suggestions accepted. View your statistics in Settings to see how TextWarden is helping improve your writing over time. All statistics stay on your device.

### Additional Features

- **Internet abbreviations**: Recognizes common abbreviations like "btw", "afaik", "imo" without flagging them
- **Gen Z slang**: Optionally recognize modern internet slang
- **IT terminology**: Built-in dictionary of technical terms, programming languages, and tech company names
- **Keyboard shortcuts**: Customizable shortcuts for common actions
- **Menu bar integration**: Quick access to pause, resume, and settings
- **Launch at login**: Optionally start TextWarden when you log in

## Known Limitations

TextWarden is a privacy-focused, local-first tool with certain trade-offs:

- **macOS only**: Currently only available for Apple Silicon Macs (M1 or later)
- **English only**: Grammar checking is limited to English due to Harper's current language support (though other languages are detected and ignored)
- **Accessibility API constraints**: Some apps with custom text rendering or limited accessibility support may not work correctly
- **Text formatting**: When applying corrections in some apps (e.g., Slack), text formatting (bold, italic, inline code) may not be preserved due to accessibility API limitations
- **Visual underlines**: Not all applications support visual error underlines; the floating indicator always works as a fallback

### Looking for More?

If you need cross-platform support (Windows, Linux, iOS, Android), grammar checking in languages other than English, or a more polished experience with commercial support, consider [Grammarly](https://www.grammarly.com). They offer an excellent product with broad application support and a refined user experience that has been developed over many years. TextWarden focuses specifically on privacy and local processing, which comes with the trade-offs mentioned above.

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 14 or later

## Privacy

TextWarden never sends your text anywhere. The only network activity is downloading AI models (optional), which you can also download manually. Block TextWarden in your firewall and it works exactly the same - all grammar and style checking runs locally on your Mac.

## Credits

TextWarden is built on excellent open source projects:

- [Harper](https://github.com/Automattic/harper) - Fast, privacy-focused grammar checker
- [mistral.rs](https://github.com/EricLBuehler/mistral.rs) - Local LLM inference engine
- [swift-bridge](https://github.com/chinedufn/swift-bridge) - Rust/Swift interoperability
- [whichlang](https://github.com/quickwit-oss/whichlang) - Language detection
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Global keyboard shortcuts for macOS
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) - Launch at login functionality

Special thanks to [VoiceInk](https://github.com/Beingpax/VoiceInk) for the inspiration on leveraging local LLMs in macOS apps. VoiceInk is a fantastic voice-to-text tool - highly recommended.

## Troubleshooting

If you encounter issues with TextWarden, see our [Troubleshooting Guide](TROUBLESHOOTING.md) for help with common problems and how to collect diagnostic information.

## Support

- **Bug reports**: Please [open an issue](https://github.com/philipschmid/textwarden/issues/new/choose) with diagnostic information (see [Troubleshooting Guide](TROUBLESHOOTING.md))
- **Feature requests**: Use [GitHub Discussions](https://github.com/philipschmid/textwarden/discussions) to suggest new features
- **Questions**: Check existing discussions or start a new one

## License

Apache License 2.0
