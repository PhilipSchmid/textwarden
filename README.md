# TextWarden: Private Grammar Checker for macOS

[![CI](https://github.com/PhilipSchmid/textwarden/actions/workflows/ci.yml/badge.svg)](https://github.com/PhilipSchmid/textwarden/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/PhilipSchmid/textwarden)](https://github.com/PhilipSchmid/textwarden/releases/latest)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-brightgreen.svg)](https://github.com/PhilipSchmid/textwarden/releases/latest)

TextWarden is a free, open-source grammar checker and writing assistant for macOS. It checks English spelling, grammar, punctuation, and style while you type.

**Nothing you type is sent anywhere.** Your writing never leaves your Mac: not for grammar checking, not for AI features, and not for analytics. There is no account to create and no subscription.

<p align="center">
  <img src="Assets/textwarden_logo.svg" alt="TextWarden macOS grammar checker logo" width="320" height="320">
</p>

<p align="center">
  <a href="https://github.com/PhilipSchmid/textwarden/releases/latest">
    <img src="Assets/download-macos-button.png" alt="Download TextWarden for macOS" width="180">
  </a>
</p>

> [!NOTE]
> TextWarden is under active development. Apps do not all share text with macOS in the same way, so underlines and corrections may work differently from one app to another. If something breaks, please [open a bug report](https://github.com/PhilipSchmid/textwarden/issues/new/choose).

## Why TextWarden?

- **Your writing stays on your Mac:** Grammar checks run locally with [Harper](https://github.com/Automattic/harper), and optional AI features use Apple Intelligence on your Mac. TextWarden never uploads your text or prompts.
- **Works in many Mac apps:** Check writing in Apple apps, browsers, chat apps, web-based editors, and Microsoft Office.
- **Fast feedback:** TextWarden underlines errors when an app provides the location of each word. Otherwise, a small floating indicator shows the suggestions.
- **No account or subscription:** Download the app and grant Accessibility permission. Your usage statistics and custom dictionary stay on your Mac.

## Features

- Real-time English grammar, spelling, punctuation, capitalization, and word-choice suggestions
- One-click corrections and a **Fix All** command for clear-cut errors
- American, British, Canadian, Australian, and Indian English dialects
- Custom vocabulary, the macOS learned-word dictionary, and optional word lists for technical terms, names, brands, abbreviations, and slang
- Optional detection of selected non-English languages to avoid false positives in multilingual documents
- Readability scores and sentence-complexity underlines for text with at least 30 words
- Per-app pause controls, per-app underline controls, and website exclusions
- A built-in Sketch Pad for focused drafting and revision
- Optional automatic updates, with a separate channel for experimental releases

### Apple Intelligence writing tools

On macOS 26 or later, a compatible Mac with an Apple M-series chip can use Apple's built-in, on-device AI for:

- Style suggestions for clear, concise, formal, casual, or business writing
- AI Compose, which generates text from an instruction and optional document context
- Sentence simplification and readability tips
- Quick actions in Sketch Pad for professional, friendly, concise, or refined rewrites

These features are off by default. Grammar checking, spell checking, custom dictionaries, language detection, and readability scoring do not require Apple Intelligence.

## Requirements

- macOS 14 Sonoma or later
- An Intel or Apple Silicon Mac
- Accessibility permission, so TextWarden can read and update text in other apps

Apple Intelligence features additionally require macOS 26, a supported Mac with an Apple M-series chip, and Apple Intelligence enabled in System Settings.

## Install TextWarden

1. Download the latest TextWarden installer (`.dmg`) from [GitHub Releases](https://github.com/PhilipSchmid/textwarden/releases/latest).
2. Drag TextWarden into the Applications folder and open it.
3. Grant Accessibility permission when macOS asks.
4. Start typing in a supported app.

The download works on both Intel and Apple Silicon Macs. To avoid overlapping suggestions, turn off the other app's built-in spelling and grammar checker when you use TextWarden there.

See the [Configuration Guide](CONFIGURATION.md) for every setting and the [Troubleshooting Guide](TROUBLESHOOTING.md) if the app, indicator, or underlines do not behave as expected.

## How It Works

After you grant permission, TextWarden reads the text field you are typing in and checks it locally with the bundled Harper grammar checker. Suggestions appear as underlines or in a small floating indicator beside the app.

When Apple Intelligence features are enabled, TextWarden gives the current text or selection to Apple's on-device AI. TextWarden does not operate a grammar or AI server.

## Supported Apps

TextWarden is tuned for the apps below. Some apps give macOS less information about their text fields than others, so the exact experience varies.

| Application | Grammar checking | Visual underlines |
| --- | --- | --- |
| Slack | Full | Full |
| Claude | Full | Full |
| ChatGPT | Full | Full |
| Perplexity | Full | Full |
| Safari | Full | Indicator only[^browsers] |
| Chrome and Comet | Full | Indicator only[^browsers] |
| Apple Mail | Full | Full |
| Apple Notes | Full | Full |
| Apple Messages | Full | Full |
| Apple Calendar | Full | Full |
| Apple Pages | Full | Full |
| Apple Reminders | Full | Full |
| TextEdit | Full | Full |
| Notion | Full | Partial[^notion] |
| Telegram | Full | Full |
| WhatsApp | Full | Full |
| Webex | Full | Full |
| Microsoft Word | Full | Full |
| Microsoft PowerPoint | Notes only[^powerpoint] | Notes only[^powerpoint] |
| Microsoft Outlook | Full | Full |
| Microsoft Teams | Full | Full |
| Proton Mail | Full | Full |
| Microsoft Excel | Not supported | Not available |

[^notion]: Notion does not make every text block available to macOS at once, so some errors appear in the indicator without an underline. See [Notion support notes](docs/applications/NOTION.md).
[^powerpoint]: PowerPoint lets TextWarden read speaker notes, but not text boxes on slides. See [PowerPoint support notes](docs/applications/POWERPOINT.md).
[^browsers]: Browser editors can be checked and corrected, but TextWarden currently disables visual underlines for the browser app category.

TextWarden recognizes Safari, Chrome, Firefox, Microsoft Edge, Opera, Arc, Brave, Vivaldi, and Comet. Website editors vary, especially editors with formatting controls. TextWarden pauses in unrecognized apps until you enable them in **Preferences → Applications**. The floating indicator can still show suggestions when an app does not provide the exact on-screen position of each word.

Terminal apps are paused by default because command output and source code produce poor grammar-checking results.

## Privacy: Nothing You Write Leaves Your Mac

TextWarden does not send your writing anywhere. It has no cloud grammar service, remote AI model, analytics, telemetry, advertising, or automatic crash reporting. Your text, AI prompts, corrections, custom vocabulary, settings, usage statistics, logs, and diagnostic reports stay on your Mac.

Grammar checks, language detection, and readability scores run inside TextWarden. Optional AI features run on your Mac through Apple Intelligence. Nothing is uploaded for processing.

If you enable update checks, TextWarden downloads release information from GitHub. The update check does not upload your writing, prompts, usage data, logs, or diagnostics.

Logs can contain parts of your writing, especially with Debug or Trace logging enabled, but they remain on your Mac. TextWarden only creates a diagnostic ZIP when you ask it to, and it never uploads that file for you. Review the file yourself before choosing to share it.

## Known Limitations

- Grammar checking is English-only. Language detection suppresses checks for selected non-English languages; it does not proofread those languages.
- Some custom text editors do not give macOS enough information for accurate underlines or safe corrections.
- A correction can remove formatting in apps that only let TextWarden replace the entire text field.
- Apple Intelligence style and composition features are unavailable on Intel Macs and on macOS releases before 26.
- TextWarden is a macOS app. There are no Windows, Linux, iOS, or Android versions.

## Project Documentation

- [Configuration](CONFIGURATION.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Building from source](BUILD.md)
- [Contributing](CONTRIBUTING.md)
- [Architecture](ARCHITECTURE.md)
- [Apple Foundation Models integration](docs/FOUNDATION_MODELS.md)
- [Application-specific notes](docs/applications/README.md)

## Credits

TextWarden uses [Harper](https://github.com/Automattic/harper), an open-source English grammar checker written in Rust. It also depends on [swift-bridge](https://github.com/chinedufn/swift-bridge), [whichlang](https://github.com/quickwit-oss/whichlang), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern), [Sparkle](https://sparkle-project.org), [swift-markdown](https://github.com/apple/swift-markdown), [STTextView](https://github.com/krzyzanowskim/STTextView), and [ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI).

The codebase was developed with substantial AI assistance and human review. The TextWarden logo was created with [Recraft](https://www.recraft.ai/).

## Support the Project

TextWarden is maintained as a side project. If it helps your writing, you can support its development:

<a href="https://buymeacoffee.com/textwarden"><img src="Assets/bmc-button-black.png" alt="Support TextWarden on Buy Me a Coffee" height="40"></a>

- [Report a bug](https://github.com/PhilipSchmid/textwarden/issues/new/choose)
- [Request a feature or ask a question](https://github.com/PhilipSchmid/textwarden/discussions)

## License

TextWarden is available under the [Apache License 2.0](LICENSE).
