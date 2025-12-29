# Application-Specific Documentation

This folder contains detailed documentation for applications that require special handling in TextWarden.

## Contents

| Application | Description |
|-------------|-------------|
| [CHATGPT.md](CHATGPT.md) | ChatGPT Electron app, RangeBounds positioning, fast 50ms debounce |
| [CLAUDE.md](CLAUDE.md) | Claude Electron app, ChromiumStrategy cursor-based positioning, dedicated parser |
| [MAIL.md](MAIL.md) | Apple Mail WebKit compose, TextMarker-based positioning, keyboard-based format-preserving replacement |
| [NOTION.md](NOTION.md) | Notion Electron app, child element tree traversal, UI element filtering |
| [MESSAGES.md](MESSAGES.md) | Apple Messages Mac Catalyst app, conversation switch detection, browser-style replacement |
| [OUTLOOK.md](OUTLOOK.md) | Microsoft Outlook compose windows, AXBoundsForRange positioning, browser-style replacement |
| [PERPLEXITY.md](PERPLEXITY.md) | Perplexity Electron app, AnchorSearch positioning, fast 50ms debounce |
| [SLACK.md](SLACK.md) | Quill Delta format, Chromium Pickle, child element selection, format-preserving replacement |
| [TEAMS.md](TEAMS.md) | Microsoft Teams Chromium-based compose, child element tree traversal, formatting exclusions |
| [TELEGRAM.md](TELEGRAM.md) | Telegram native macOS app, RangeBounds positioning, standard AX text replacement |
| [WEBEX.md](WEBEX.md) | Cisco WebEx chat, compose area detection, UTF-16 conversion for emoji support |
| [WHATSAPP.md](WHATSAPP.md) | WhatsApp Mac Catalyst app, stale AX data handling, conversation switch detection |

## Adding New Documentation

When adding special handling for a new application:

1. Create `<APP_NAME>.md` in this folder
2. Document the app-specific format/protocol
3. Explain any special parsing or replacement logic
4. Add a link in the table above
5. Update the reference in [ARCHITECTURE.md](../../ARCHITECTURE.md)
