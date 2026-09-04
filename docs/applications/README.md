# TextWarden app integrations for macOS

TextWarden is a private macOS grammar checker and writing assistant. These guides explain the app-specific Accessibility API work needed to show grammar underlines and apply corrections in supported desktop apps.

## Integration guides

| Application | TextWarden integration |
|-------------|------------------------|
| [ChatGPT](CHATGPT.md) | Direct range positioning in the ChatGPT prompt editor |
| [Claude](CLAUDE.md) | Child-element positioning in Claude Desktop |
| [Apple Mail](MAIL.md) | Subject and compose-body checking with WebKit-aware replacement |
| [Apple Messages](MESSAGES.md) | Catalyst positioning and conversation-change handling |
| [Notion](NOTION.md) | Block-aware filtering with partial visual underline coverage |
| [Microsoft Outlook](OUTLOOK.md) | Subject and message-body checking with Office-safe replacement |
| [Apple Pages](PAGES.md) | Native document positioning with focused clipboard replacement |
| [Perplexity](PERPLEXITY.md) | Anchor-based positioning in the Perplexity prompt editor |
| [Microsoft PowerPoint](POWERPOINT.md) | Grammar checking in speaker notes |
| [Slack](SLACK.md) | Rich-text exclusions and format-aware replacement in the message composer |
| [Microsoft Teams](TEAMS.md) | Child-element positioning and formatted-content exclusions |
| [Telegram](TELEGRAM.md) | Native range positioning in the message composer |
| [Cisco Webex](WEBEX.md) | Compose-field detection that ignores sent messages |
| [WhatsApp](WHATSAPP.md) | Catalyst positioning with stale-text protection |
| [Microsoft Word](WORD.md) | Direct document-range positioning with Office-safe replacement |

TextWarden also supports apps that work through shared native or browser configurations. The main [README](../../README.md#supported-apps) has the full support table.

For repeatable host-application checks, driver preflights, cleanup rules, and the prioritized test sequence, see [macOS live end-to-end testing](../testing/README.md).

## Adding an integration guide

Document behavior that is backed by `AppRegistry`, an `AppBehavior`, a content parser, or a positioning strategy. Include the bundle identifier, monitored editing surface, correction method, known limits, and implementation files. Avoid version guarantees unless the application enforces them at runtime.
