
# TextWarden

**Grammar checking that respects your privacy.**

TextWarden checks your spelling and grammar while you type - in any app on your Mac. Unlike other tools, everything runs locally on your computer. Your writing never leaves your device.

<p align="center">
  <img src="Assets/textwarden_logo.svg" alt="TextWarden Logo" width="320" height="320">
</p>

<p align="center">
  <a href="https://github.com/philipschmid/textwarden/releases">
    <img src="Assets/download-macos-button.png" alt="Download for macOS" width="180">
  </a>
</p>

> [!WARNING]
> **Alpha Software**: TextWarden is in early development and you will encounter bugs. For example, some visual underlines might be misaligned, some suggestions might not be perfect, or certain applications may not work as expected. Much like printers and projectors that still mysteriously fail on first try after decades of existence, macOS Accessibility APIs and the apps that implement them each have their own quirks that require app-specific tuning. That said, it should be stable enough for daily use and I'd love for you to try it! Your bug reports help make TextWarden better for everyone. Found something broken? [Report it here](#support).

## Why TextWarden?

**Private by Design**
Your text stays on your Mac. No cloud servers, no accounts, no data collection. Works completely offline.

**Blazingly Fast**
Powered by [Harper](https://github.com/automattic/harper), a high-performance Rust-based grammar engine.

**Works Everywhere**
Integrates with most macOS apps through the Accessibility API - Mail, Outlook, Teams, Slack, and more.

**Simple and Unobtrusive**
A small indicator and/or underline appears when issues are found. Click to see suggestions. Accept with one click. That's it.

## Features

- **Real-time grammar and spelling** - Catches errors as you type
- **AI-powered style suggestions** - Apple Intelligence ([Foundation Models](https://developer.apple.com/documentation/FoundationModels)) for clarity and readability improvements (macOS 26+)
- **Multilingual awareness** - Detects non-English sentences and ignores them (no false positives on foreign phrases)
- **Custom dictionary** - Add your own technical terms and proper nouns
- **Dialect support** - American, British, Canadian, or Australian English
- **App controls** - Enable, disable, or pause checking per application
- **Automatic updates** - Stay current with optional update checks

## Requirements

- macOS 26 (Tahoe) or later
- Any Mac that supports macOS 26 (Intel or Apple Silicon)

> **Note for Intel Mac users**: TextWarden runs on Intel Macs, but **AI-powered style suggestions are not available**. Apple Intelligence requires Apple Silicon (M1 or later) due to the Neural Engine hardware. Grammar and spelling checking work fully on Intel Macs.

## Getting Started

1. Download the latest release from the [Releases page](https://github.com/philipschmid/textwarden/releases)
   - The DMG is a **Universal binary** that works on both Intel and Apple Silicon Macs
2. Move TextWarden to your Applications folder and open it
3. Grant Accessibility permission when prompted (required to read text in other apps)
4. Start typing - TextWarden works automatically in the background

For detailed explanations of all settings and how they affect your experience, see the **[Configuration Guide](CONFIGURATION.md)**.

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

- **Keyboard shortcut**: Press `Option+Control+S` (customizable) to run a style check on demand
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

- **macOS only** - Available for Intel and Apple Silicon Macs running macOS 26+. There are no plans to support Windows or Linux - approximately 98% of TextWarden's development effort goes into macOS-specific integration: precise cursor positioning via the Accessibility API, pixel-perfect error underline placement, seamless text replacement that preserves formatting, and per-application behavior tuning. These deep OS integrations don't translate to other platforms.
- **Style suggestions require Apple Silicon** - AI-powered style suggestions use Apple Intelligence, which requires the Neural Engine in M1 chips or later. Intel Macs can use all grammar and spelling features but won't have access to style suggestions.
- **English only** - Grammar checking limited to English (Harper's current language support)
- **Accessibility API constraints** - Some apps with custom text rendering may not work correctly
- **Text formatting** - When applying corrections in some apps, formatting (bold, italic) may not be preserved
- **Visual underlines** - Not all applications support visual error underlines; see [Tested Applications](#tested-applications) for details and the [Troubleshooting Guide](TROUBLESHOOTING.md#visual-underlines-appear-misaligned) for help

### Looking for More?

If you need cross-platform support (Windows, Linux, iOS, Android), grammar checking in languages other than English, consider:

- **[Grammarly](https://www.grammarly.com)** - Excellent product with broad application support and a refined user experience developed over many years
- **[LanguageTool](https://languagetool.org/)** - "Open-source" grammar checker with support for 30+ languages, available as browser extensions and desktop apps

TextWarden focuses specifically on privacy, local processing, and full transparency as an open-source project - which comes with the trade-offs mentioned above.

## Privacy

TextWarden never sends your text anywhere. All grammar checking and style analysis happens on-device using Harper (grammar) and Apple Intelligence (style suggestions). Block TextWarden in your firewall and it works exactly the same (except for automatic update checks).

## AI Declaration

The majority of TextWarden's code was generated using Anthropic's Claude, with human oversight, review, and testing throughout the development process.

The TextWarden logo was created with [Recraft](https://www.recraft.ai/) - an amazing AI image generation tool with background removal, image vectorization, and more. Highly recommended for creating app icons and design assets.

## Credits

### Harper - The Grammar Engine

TextWarden is powered by [Harper](https://writewithharper.com/), an open-source grammar checker built in Rust by Automattic. Harper is what makes TextWarden fast and private - it runs entirely on your device without sending text to any server.

If you need grammar checking **inside your browser** with full support for rich text editors, form fields, and web apps, check out [Harper's Chrome Extension](https://writewithharper.com/). Unlike TextWarden (which uses macOS Accessibility APIs from outside the browser), Harper's extension runs directly in the browser with full DOM and JavaScript access - this means better integration with complex web applications like Google Docs, Gmail compose, and other rich text editors.

- **Harper Website**: [writewithharper.com](https://writewithharper.com/)
- **Harper Source Code**: [github.com/Automattic/harper](https://github.com/Automattic/harper)

### VoiceInk - Voice-to-Text

I used [VoiceInk](https://tryvoiceink.com?atp=Ylsxyh&sub1=tw) extensively while developing TextWarden. It saved me countless hours by letting me dictate AI prompts, documentation, and commit messages instead of typing everything. Like TextWarden, it runs entirely locally on your Mac. *(Referral link - helps support TextWarden's development)*

### Other Open Source Projects

- [swift-bridge](https://github.com/chinedufn/swift-bridge) - Rust/Swift interoperability
- [whichlang](https://github.com/quickwit-oss/whichlang) - Language detection
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Global keyboard shortcuts for macOS
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) - Launch at login functionality
- [ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI) - Confetti animations

## Support the Project

TextWarden is a side project built during evenings and weekends. If you find it useful, you can support its development:

<a href="https://buymeacoffee.com/textwarden"><img src="Assets/bmc-button-black.png" alt="Buy Me a Coffee" height="40"></a>

**Tip:** If you have an open issue or feature request, include the GitHub link in your message - supporters' requests get prioritized!

## Troubleshooting

See the [Troubleshooting Guide](TROUBLESHOOTING.md) for help with common problems and how to collect diagnostic information.

### Tested Applications

TextWarden uses the macOS Accessibility API and works with most applications. Visual underlines (showing errors directly in the text) have been specifically tested and calibrated for:

| Application | Grammar Checking | Visual Underlines |
|-------------|-----------------|-------------------|
| **Slack** | Full | Full |
| **Claude** | Full | Full |
| **ChatGPT** | Full | Full |
| **Perplexity** | Full | Full |
| **Safari** | Full | Full |
| **Chrome, Comet** | Full | Full |
| **Apple Mail** | Full | Full |
| **Apple Notes** | Full | Full |
| **Apple Messages** | Full | Full |
| **Apple Pages** | Full | Full |
| **TextEdit** | Full | Full |
| **Notion** | Full | Partial** |
| **Telegram** | Full | Full |
| **WhatsApp** | Full | Full |
| **Webex** | Full | Full |
| **Microsoft Word** | Full | Full |
| **Microsoft PowerPoint** | Notes only*** | Indicator only* |
| **Microsoft Outlook** | Full | Full |
| **Microsoft Excel** | Not supported | N/A |
| **Microsoft Teams** | Full | Full |

*\*PowerPoint uses a floating indicator instead of inline underlines due to accessibility API limitations (crashes on parameterized accessibility attribute queries).*

*\*\*Notion: Underlines appear for ~50% of text blocks. Due to Notion's React/Electron virtualization, some blocks aren't exposed in the accessibility tree. Errors in virtualized blocks show in the indicator count but without underlines. Shift+Enter (soft breaks) work; Enter (new blocks) may not. See [Notion documentation](docs/applications/NOTION.md) for details.*

*\*\*\*PowerPoint exposes only the Notes section via the macOS Accessibility API. Slide text boxes are not accessible programmatically, so grammar checking is limited to speaker notes.*

> [!NOTE]
> Terminal apps are not supported as their accessibility APIs typically don't expose text content in a way that's useful for grammar checking.

**Other applications**: TextWarden works with most apps that support standard text editing. Grammar checking and the floating error indicator work broadly; visual underlines may vary. [Request support](https://github.com/philipschmid/textwarden/discussions) for additional apps.

### Support

- **Bug reports**: [Open an issue](https://github.com/philipschmid/textwarden/issues/new/choose) with diagnostic information
- **Feature requests**: Use [GitHub Discussions](https://github.com/philipschmid/textwarden/discussions)
- **Questions**: Check existing discussions or start a new one

For enterprise licensing arrangements or if best-effort community support isn't sufficient, contact [sales@textwarden.io](mailto:sales@textwarden.io).

## License

Apache License 2.0
