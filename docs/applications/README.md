# Application-Specific Documentation

This folder contains detailed documentation for applications that require special handling in TextWarden.

## Contents

| Application | Description |
|-------------|-------------|
| [MAIL.md](MAIL.md) | Apple Mail WebKit compose, TextMarker-based positioning, keyboard-based format-preserving replacement |
| [OUTLOOK.md](OUTLOOK.md) | Microsoft Outlook compose windows, AXBoundsForRange positioning, browser-style replacement |
| [SLACK.md](SLACK.md) | Quill Delta format, Chromium Pickle, child element selection, format-preserving replacement |
| [TEAMS.md](TEAMS.md) | Microsoft Teams Chromium-based compose, child element tree traversal, formatting exclusions |
| [WEBEX.md](WEBEX.md) | Cisco WebEx chat, compose area detection, UTF-16 conversion for emoji support |

## Adding New Documentation

When adding special handling for a new application:

1. Create `<APP_NAME>.md` in this folder
2. Document the app-specific format/protocol
3. Explain any special parsing or replacement logic
4. Add a link in the table above
5. Update the reference in [ARCHITECTURE.md](../../ARCHITECTURE.md)
