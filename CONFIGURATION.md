# TextWarden Configuration Guide

Open **Preferences** from the TextWarden menu bar icon to change grammar checking, app support, appearance, Apple Intelligence features, and diagnostics.

## General

### Grammar checking state

The global **Grammar checking** menu has four states:

- **Active**
- **Paused for 1 Hour**
- **Paused for 24 Hours**
- **Paused Until Resumed**

The same pause durations are available per app under **Preferences → Applications**.

### Launch at login

Enable **Launch at Login** to start TextWarden when you sign in to your Mac. This uses the standard macOS login-item mechanism.

### Accessibility permission

TextWarden needs Accessibility permission to read editable text, position overlays, and apply corrections in other apps. Grant it under **System Settings → Privacy & Security → Accessibility**. TextWarden does not need this permission to edit text inside its own Sketch Pad.

## Updates

Update controls live under **Preferences → About**. TextWarden uses [Sparkle](https://sparkle-project.org/) with an HTTPS appcast, EdDSA update signatures, Apple code signing, and notarized release builds.

- **Automatically check for updates on launch:** Enables Sparkle's scheduled checks. When enabled, the interval is 24 hours.
- **Include experimental releases:** Adds the `experimental` channel, which carries alpha, beta, and release-candidate builds as well as stable releases.
- **Check for Updates:** Runs a manual check immediately.

Onboarding asks whether to enable automatic checks and saves that choice. Update checks do not send the text you write.

## Grammar and Spell Checking

### English dialect

Choose American, British, Canadian, Australian, or Indian English. The dialect changes Harper's spelling and grammar rules.

### Grammar categories

Under **Preferences → Grammar**, you can enable or disable Harper categories individually. They cover spelling, typos, grammar and agreement, punctuation, capitalization, repetition, word choice, usage, regional forms, formatting, and style-related rules.

All categories are enabled by default. The punctuation category also exposes four rule switches:

- Oxford comma
- Ellipsis formatting
- Unclosed quotes
- Dash usage

### Custom vocabulary

Add project terms, product names, or proper nouns to the custom dictionary so they are no longer flagged. You can also add a flagged term from its suggestion popover.

The Grammar tab includes optional predefined word lists. They are enabled by default:

| Word list | Included terms |
| --- | --- |
| Internet Abbreviations | More than 3,200 common abbreviations |
| Gen Z Slang | More than 270 modern terms |
| IT & Tech Terminology | More than 10,000 technical terms |
| Brand & Company Names | More than 2,400 names |
| Person Names | More than 100,000 international first names |
| Surnames | More than 150,000 US Census surnames |

Matching is case-insensitive. You can also enable **Import macOS learned words**, which asks `NSSpellChecker` about words learned through the system **Learn Spelling** command. TextWarden's own custom words remain separate from the macOS dictionary.

### Language detection

Language detection is off by default. Enable **Ignore selected languages** to prevent English grammar checks in passages confidently detected as a selected language.

The searchable selector contains all 69 non-English languages supported by the bundled detector. Search by English name, native name, or ISO 639-3 code. Selected languages appear first when the search field is empty.

TextWarden detects language once per semantic segment, such as a sentence, paragraph, or list item. If more than 60% of all substantive segments are reliably detected as any selected language, it skips Harper and English readability analysis for the document. Otherwise it suppresses Harper errors only inside reliably matched segments. English and unselected passages in mixed-language documents remain checked.

Uncertain detections fail open: TextWarden keeps checking the passage. This is most likely with very short, ambiguous, or closely related language samples. The feature prevents false positives; it does not translate or proofread non-English text.

## Readability

Readability analysis is on by default and does not require Apple Intelligence. For text with at least 30 words, TextWarden calculates a Flesch Reading Ease score and checks sentence complexity against the selected audience.

### Target audience

| Audience | Minimum score | Intended reader |
| --- | ---: | --- |
| Accessible | 65 | Broad audience, roughly eighth-grade reading level |
| General | 50 | Average adult reader |
| Professional | 40 | Business and professional readers |
| Technical | 30 | Readers familiar with specialized material |
| Academic | 20 | Graduate-level or academic readers |

**General** is the default. A sentence is eligible for a complexity underline when it has at least 12 words and scores more than 10 points below the selected threshold.

Turn off **Show Complexity Underlines** if you want the overall score without violet dashed sentence underlines.

## Apple Intelligence Features

AI Style Suggestions and AI Compose require macOS 26 or later, a supported Apple Silicon Mac, and Apple Intelligence enabled in System Settings. TextWarden uses Apple's Foundation Models framework on-device. The feature is unavailable on Intel Macs, but Harper grammar checking and readability scoring continue to work.

### AI Style Suggestions

AI style suggestions are off by default. Once enabled, TextWarden runs style analysis after grammar analysis with a three-second debounce, a 50-character minimum, and a 30-second minimum interval between automatic checks. You can trigger a check immediately with `⌥⌃S`; selected text is checked by itself, otherwise TextWarden checks the full field.

Choose one writing style:

- **Default:** Clear, natural writing
- **Concise:** Less repetition and filler
- **Formal:** Professional vocabulary and complete sentences
- **Casual:** Conversational phrasing
- **Business:** Direct, action-oriented writing

The **Creativity** control has three presets:

- **Consistent:** Greedy sampling for repeatable output
- **Balanced:** Temperature `0.3` and the default setting
- **Creative:** Temperature `0.5` for more variation

The selected preset is used for manual style checks. Automatic style checks currently use Balanced.

TextWarden filters model output before showing it. Suggestions must point to exact source text, change that text, avoid overlapping ranges, and pass app-level safety checks before replacement.

### AI Compose

AI Compose generates text from an instruction. Open it from the writing section of the floating indicator or press `⌥⌃W`. If text is selected, it can be included as context; otherwise TextWarden may include nearby document text. The instruction remains the primary input.

Generated text can be inserted into the active field or copied. Retry uses a different sampling seed and a higher temperature to produce another version.

## Sketch Pad

Sketch Pad is TextWarden's built-in editor. Open it from the menu bar or press `⌥⌃N`.

It provides:

- Real-time Harper grammar and spell checking
- Readability scores and sentence analysis
- Apple Intelligence style suggestions and quick rewrites when available
- An insights sidebar grouped by correctness, style, and clarity
- Undo and redo
- Line-number, current-line, invisible-character, and line-wrapping controls
- Automatic document saving

AI quick actions apply to the selection when one exists, or the full document otherwise. The current actions are Professional, Friendly, Concise, and Refine.

## Appearance

### Suggestion popover

- **Position:** Auto, Above, or Below
- **Show on hover:** Opens suggestions when the pointer rests over an underline or indicator
- **Text size:** 10–20 pt; 13 pt by default
- **Theme:** System, Light, or Dark for the preferences window
- **Overlay Theme:** System, Light, or Dark for popovers and indicators

### Underlines

**Show error underlines** controls grammar and spelling underlines globally. Thickness ranges from 1 to 5 pt and defaults to 2 pt. TextWarden hides underlines when the error count exceeds the configured threshold; the threshold ranges from 1 to 20 and defaults to 10.

An app must expose usable character geometry for underlines to appear. The floating indicator remains available when only error counts and suggestions can be shown.

### Floating indicator

The default position can be Top Left, Top Right, Center Left, Center Right, Bottom Left, or Bottom Right. It defaults to Center Right. Drag the indicator along the window edge to remember a different position for a specific app.

**Always show indicator** keeps a green checkmark visible when there are no issues. **Hover delay** ranges from 0 to 1,000 ms in 50 ms steps and defaults to instant.

## Application and Website Controls

### Supported applications

Apps with dedicated TextWarden configurations are enabled by default. The registry includes Slack, Teams, Claude, ChatGPT, Perplexity, supported browsers, Notion, Apple Mail, Messages, Notes, TextEdit, Reminders, Calendar, Pages, WhatsApp, Telegram, Microsoft Word, PowerPoint, Outlook, Webex, and Proton Mail.

See the [supported-app matrix](README.md#supported-apps) and [application notes](docs/applications/README.md) for known limitations.

### Other applications

Before TextWarden reads text in an app without a dedicated configuration, it asks whether to **Try Safely** or **Keep Paused**. A safe trial uses the floating indicator and copy-only fixes; underlines and direct edits stay off. You can change this choice under **Preferences → Applications**. TextWarden can profile the app's Accessibility capabilities locally and cache a strategy recommendation for seven days, but results still depend on the editor.

### Terminal applications

Terminal, iTerm2, Hyper, Warp, Alacritty, Kitty, WezTerm, and Ghostty are paused until resumed by default. You can enable one manually, though command output and code tend to produce noisy suggestions.

### Per-app controls

Each discovered app can be Active, paused for one hour, paused for 24 hours, or paused until resumed. The underline button disables visual underlines for that app without turning off grammar checking.

### Website exclusions

Under **Preferences → Websites**, add a domain to disable TextWarden in browser text fields on that site. Exact domains such as `github.com` and wildcard patterns such as `*.google.com` are supported.

## Keyboard Shortcuts

All shortcuts can be changed under **Preferences → General**. They can also be disabled together with **Enable keyboard shortcuts**.

| Action | Default shortcut |
| --- | --- |
| Toggle TextWarden | `⌥⌃T` |
| Fix all grammar errors with one suggestion | `⌥⌃A` |
| Show grammar suggestions | `⌥⌃G` |
| Show style suggestions | `⌥⌃Y` |
| Show AI Compose | `⌥⌃W` |
| Show readability | `⌥⌃R` |
| Run style check | `⌥⌃S` |
| Open or close Sketch Pad | `⌥⌃N` |

When a suggestion popover is open:

| Action | Default shortcut |
| --- | --- |
| Accept the current suggestion | `Tab` |
| Dismiss the popover | `⌥Esc` |
| Previous suggestion | `⌥←` |
| Next suggestion | `⌥→` |
| Apply suggestion 1, 2, or 3 | `⌥1`, `⌥2`, or `⌥3` |

## Diagnostics and Logging

### Runtime health

Open **Preferences → Diagnostics** to see TextWarden's current state for the active application. The runtime-health card shows whether checking is active, limited, recovering, or paused, along with the last successful check and detected support capabilities. When TextWarden can recover automatically or needs an action from you, the relevant control appears in the same card.

### Log levels

TextWarden writes to macOS Unified Logging at these levels: Trace, Debug, Info, Warning, Error, and Critical. Info is the default.

File logging is optional. Its default path is:

```text
~/Library/Logs/TextWarden/textwarden.log
```

Most Info-level messages record metadata, but warning and error diagnostics for failed or stale replacements can include short text fragments. Debug and Trace logs may contain more analyzed text. Use verbose logging only while investigating a problem, and review any log before sharing it.

### Debug overlays

The Diagnostics tab can draw text-field bounds, CGWindow coordinates, Cocoa coordinates, and character-position markers. These tools help identify Accessibility and coordinate-conversion problems. Leave them off during normal use.

### Export Diagnostics

**Preferences → Diagnostics → Export Diagnostics** creates a ZIP containing:

- `diagnostic_overview.json` with system, permission, settings, application-state, statistics, performance, and Apple Intelligence metadata
- Sanitized current and rotated TextWarden log files, when present
- Up to ten recent TextWarden `.crash` or `.ips` reports, when present

The settings dump omits custom-dictionary entries and ignored rule or error text. Website and per-app underline overrides are recorded as counts, while the selected language exclusions are listed by name. Log sanitization anonymizes `/Users/<name>/` paths and removes lines containing common secret keywords. Logs and Apple crash reports can still contain sensitive context, so extract and inspect the ZIP before sharing it.

### Reset options

The Diagnostics tab can reset all settings, clear the custom dictionary, clear ignored rules or error text, and reset milestone prompts. Statistics have a separate reset control under **Preferences → Statistics**. **Reset All Settings** relaunches TextWarden and shows onboarding again.

## Getting Help

- Choose **Preferences → About → Replay Tutorial** to review the floating control, suggestions, and quick actions.
- Read [Troubleshooting](TROUBLESHOOTING.md).
- [Open a bug report](https://github.com/PhilipSchmid/textwarden/issues/new/choose).
- Use [GitHub Discussions](https://github.com/PhilipSchmid/textwarden/discussions) for feature requests and questions.
