
# TextWarden

**Grammar checking that respects your privacy.**

TextWarden checks your spelling and grammar while you type - in any app on your Mac. Unlike other tools, everything runs locally on your computer. Your writing never leaves your device.

<p align="center">
  <img src="Assets/textwarden_logo.svg" alt="TextWarden Logo" width="320" height="320">
</p>

<p align="center">
  <a href="https://github.com/philipschmid/textwarden/releases">
    <img src="https://user-images.githubusercontent.com/37590873/219133640-8b7a0179-20a7-4e02-8887-fbbd2eaad64b.png" alt="Download for macOS" width="250">
  </a>
</p>

> [!NOTE]
> **Beta Software**: TextWarden is currently in beta and may contain bugs. If you encounter any issues, please [report them](#support) so they can be fixed.

## Why TextWarden?

**Private by Design**
Your text stays on your Mac. No cloud servers, no accounts, no data collection. Works completely offline.

**Blazingly Fast**
Powered by Harper, a high-performance Rust-based grammar engine. Checks complete in milliseconds.

**Works Everywhere**
Integrates with most macOS apps through the Accessibility API - Mail, Notes, Pages, Safari, Slack, and more.

**Simple and Unobtrusive**
A small indicator appears when issues are found. Click to see suggestions. Accept with one click. That's it.

## Features

- **Real-time grammar and spelling** - Catches errors as you type
- **AI-powered style suggestions** - Apple Intelligence for clarity and readability improvements (macOS 26+)
- **Multilingual awareness** - Detects non-English sentences and ignores them (no false positives on foreign phrases)
- **Custom dictionary** - Add your own technical terms and proper nouns
- **Dialect support** - American, British, Canadian, or Australian English
- **App controls** - Enable, disable, or pause checking per application
- **Automatic updates** - Stay current with optional update checks

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 15 or later
- macOS 26+ for AI-powered style suggestions (Apple Intelligence)

## Getting Started

1. Download the latest version from the [Releases page](https://github.com/philipschmid/textwarden/releases)
2. Move TextWarden to your Applications folder and open it
3. Grant Accessibility permission when prompted (required to read text in other apps)
4. Start typing - TextWarden works automatically in the background

For detailed explanations of all settings and how they affect your experience, see the **[Configuration Guide](CONFIGURATION.md)**.

> **Note on Default Settings**: TextWarden's default settings are opinionated based on my own application usage. If you'd like to see different defaults or have suggestions for improvements, I'm happy to consider changes - please [open a discussion](https://github.com/philipschmid/textwarden/discussions) to share your thoughts.

## Feature Details

### Real-Time Grammar and Spelling

TextWarden continuously monitors your writing and highlights errors as you type. Corrections appear in a popover with one-click apply. Supported error categories include:

- Spelling mistakes and typos
- Grammar errors (subject-verb agreement, tense, etc.)
- Punctuation issues
- Capitalization errors
- Word choice and commonly confused words
- Redundant phrases

You can enable or disable specific categories in Settings.

### AI-Powered Style Suggestions

Beyond rule-based grammar checking, TextWarden offers intelligent style suggestions powered by a local AI model running entirely on your Mac. This feature is disabled by default and can be enabled in Settings.

Style analysis can be triggered in two ways:

- **Keyboard shortcut**: Press `Cmd+Control+S` (customizable) to run a style check on demand
- **Automatic**: Enable automatic style checking in Settings to analyze text as you type

When using the keyboard shortcut with text selected, only the selected portion is analyzed. Without a selection, the entire text field is analyzed.

Available writing styles: Default, Concise, Formal, Casual, and Business.

### Multilingual Support

TextWarden uses sentence-level language detection to avoid false positives when you mix languages. Each sentence is analyzed independently - if a sentence is detected as German, Spanish, or another non-English language, grammar errors in that sentence are automatically suppressed. This is useful when writing emails that include foreign phrases like "Freundliche Grüsse" or "Merci beaucoup".

Supported languages for detection: Spanish, French, German, Italian, Portuguese, Dutch, Russian, Chinese, Japanese, Korean, Arabic, Hindi, Turkish, Swedish, and Vietnamese.

### App and Website Controls

Control exactly where TextWarden runs:

- Enable or disable checking for specific applications
- Pause checking temporarily (1 hour, 24 hours, or indefinitely)
- Disable checking for specific websites when using browsers

### Additional Features

- **Custom dictionary** - Add technical terms, proper nouns, or specialized vocabulary
- **Dialect support** - American, British, Canadian, or Australian English spelling rules
- **Internet abbreviations** - Recognizes "btw", "afaik", "imo" without flagging them
- **IT terminology** - Built-in dictionary of 10,000+ technical terms and company names
- **Brand names** - 2,400+ company/brand names (Fortune 500, Forbes 2000, global brands)
- **Person names** - 100,000+ international first names (US SSA + worldwide sources)
- **Surnames** - 150,000+ last names from US Census data
- **Usage statistics** - Track errors found and corrections applied (stored locally)
- **Keyboard shortcuts** - Customizable shortcuts for common actions
- **Menu bar integration** - Quick access to pause, resume, and settings
- **Launch at login** - Optionally start TextWarden when you log in

### Automatic Updates

TextWarden can automatically check for updates and notify you when a new version is available. Enable automatic update checks in Settings → Advanced.

To receive early access to new features, enable the **experimental channel** in Settings. This includes alpha, beta, and release candidate versions.

## Known Limitations

TextWarden is a privacy-focused, local-first tool with certain trade-offs:

- **macOS only** - Currently only available for Apple Silicon Macs (M1 or later). There are no plans to support Windows or Linux - approximately 95% of TextWarden's development effort goes into macOS-specific integration: precise cursor positioning via the Accessibility API, pixel-perfect error underline placement, seamless text replacement that preserves formatting, and per-application behavior tuning. These deep OS integrations don't translate to other platforms.
- **English only** - Grammar checking limited to English (Harper's current language support)
- **Accessibility API constraints** - Some apps with custom text rendering may not work correctly
- **Text formatting** - When applying corrections in some apps, formatting (bold, italic) may not be preserved
- **Visual underlines** - Not all applications support visual error underlines; see [Tested Applications](#tested-applications) for details and the [Troubleshooting Guide](TROUBLESHOOTING.md#visual-underlines-appear-misaligned) for help
- **Mac Catalyst apps** - Apps like Apple Messages and WhatsApp are iOS apps running on macOS via Mac Catalyst. Apple's accessibility bridge for Catalyst is incomplete - standard text positioning APIs (`AXBoundsForRange`, `AXRangeForLine`) return invalid data. TextWarden uses font-metrics-based positioning as a fallback, which may be less precise for multi-line text with soft wrapping. Additionally, in WhatsApp, undoing a correction may require pressing Cmd+Z twice due to how WhatsApp's undo stack handles text replacement

### Looking for More?

If you need cross-platform support (Windows, Linux, iOS, Android), grammar checking in languages other than English, or a more polished experience with commercial support, consider [Grammarly](https://www.grammarly.com). They offer an excellent product with broad application support and a refined user experience that has been developed over many years. TextWarden focuses specifically on privacy and local processing, which comes with the trade-offs mentioned above.

## Privacy

TextWarden never sends your text anywhere. The only network activity is downloading AI models (optional), which you can also download manually. Block TextWarden in your firewall and it works exactly the same.

## AI Assistance

The majority of TextWarden's code was generated using Anthropic's Claude, with human oversight, review, and testing throughout the development process.

## Credits

Built on excellent open source projects:

- [Harper](https://github.com/Automattic/harper) - Fast, privacy-focused grammar checker
- [swift-bridge](https://github.com/chinedufn/swift-bridge) - Rust/Swift interoperability
- [whichlang](https://github.com/quickwit-oss/whichlang) - Language detection
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Global keyboard shortcuts for macOS
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) - Launch at login functionality

## Troubleshooting

See the [Troubleshooting Guide](TROUBLESHOOTING.md) for help with common problems and how to collect diagnostic information.

### Tested Applications

TextWarden uses the macOS Accessibility API and works with most applications. Visual underlines (showing errors directly in the text) have been specifically tested and calibrated for:

| Application | Grammar Checking | Visual Underlines |
|-------------|-----------------|-------------------|
| **Slack** | Full | Full |
| **Safari** | Full | Full |
| **Chrome, Comet** | Full | Full |
| **Apple Mail** | Full | Full |
| **Apple Messages** | Full | Full |
| **Notion** | Full | Full |
| **Telegram** | Full | Full |
| **WhatsApp** | Full | Full |
| **Webex** | Full | Full |
| **Microsoft Word** | Full | Indicator only* |
| **Microsoft PowerPoint** | Notes only** | Indicator only* |
| **Microsoft Excel** | Not supported | N/A |
| **Microsoft Teams** | Full | Indicator only* |
| **Terminal apps** (iTerm2, Terminal.app, Warp) | Full | Indicator only* |

*\*These apps use a floating indicator instead of inline underlines due to accessibility API limitations. Microsoft Word crashes (EXC_BAD_INSTRUCTION in mso99) when applications query parameterized accessibility attributes like AXBoundsForRange, so visual underlines are disabled.*

*\*\*PowerPoint exposes only the Notes section via the macOS Accessibility API. Slide text boxes are not accessible programmatically, so grammar checking is limited to speaker notes.*

**Other applications**: TextWarden works with most apps that support standard text editing. Grammar checking and the floating error indicator work broadly; visual underlines may vary. [Request support](https://github.com/philipschmid/textwarden/discussions) for additional apps.

### Support

- **Bug reports**: [Open an issue](https://github.com/philipschmid/textwarden/issues/new/choose) with diagnostic information
- **Feature requests**: Use [GitHub Discussions](https://github.com/philipschmid/textwarden/discussions)
- **Questions**: Check existing discussions or start a new one

## License

Apache License 2.0
