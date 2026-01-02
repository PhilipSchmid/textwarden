# TextWarden Configuration Guide

This guide explains all the settings available in TextWarden and how they affect your experience. Access settings via the TextWarden menu bar icon → **Preferences**.

## Table of Contents

- [Table of Contents](#table-of-contents)
- [General Settings](#general-settings)
- [Updates](#updates)
- [Grammar \& Language](#grammar--language)
- [Custom Vocabulary](#custom-vocabulary)
- [Style Checking (Apple Intelligence)](#style-checking-apple-intelligence)
- [Appearance](#appearance)
- [Application Controls](#application-controls)
  - [Supported Applications](#supported-applications)
  - [Other Applications](#other-applications)
  - [Terminal Applications](#terminal-applications)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Advanced Settings](#advanced-settings)
- [Troubleshooting Tips](#troubleshooting-tips)
- [Getting Help](#getting-help)

---

## General Settings

### Launch at Login

**What it does:** Automatically starts TextWarden when you log into your Mac.

**Recommendation:** Enable this for always-on grammar checking without having to remember to launch the app.

---

## Updates

TextWarden uses [Sparkle](https://sparkle-project.org) for secure, automatic updates. Update settings are found in **Preferences → About**.

### How Updates Work

When you check for updates (manually or automatically), TextWarden:
1. Securely connects to the update server over HTTPS
2. Downloads an update feed signed with EdDSA cryptographic signatures
3. Compares your version against available releases
4. If a newer version is available, shows a dialog with release notes and options to update now or skip

All updates are code-signed by the developer and notarized by Apple, ensuring they haven't been tampered with.

### Automatically Check for Updates

**What it does:** When enabled, TextWarden checks for updates once every 24 hours in the background. If an update is found, you'll see a notification.

**Default:** Disabled (opt-in for privacy)

**Recommendation:** Enable this to stay up to date with bug fixes and new features without having to remember to check manually.

### Include Experimental Releases

**What it does:** Opts you into the experimental update channel, which includes pre-release versions (alpha and beta builds) in addition to stable releases.

**What you'll get:**
- **Stable channel (default):** Only production releases (e.g., 1.0.0, 1.1.0)
- **Experimental channel:** Pre-release versions (e.g., 0.1.0-alpha.3, 1.1.0-beta.1) plus stable releases

**When to enable:**
- You want to try new features before they're officially released
- You're willing to report bugs and provide feedback
- You understand that experimental releases may have rough edges

**When to keep disabled:**
- You prefer stability over new features
- You rely on TextWarden for critical work

**Note:** Experimental releases go through the same code signing and notarization process as stable releases—they're not less secure, just less tested.

### Manual Update Check

Click **Check for Updates** in the About section to immediately check for available updates. This shows the update dialog if a newer version is available, or confirms you're up to date.

---

## Grammar & Language

### English Dialect

**What it does:** Determines spelling and grammar rules. For example, "colour" vs "color", "analyse" vs "analyze".

**Options:**
- American English
- British English
- Canadian English
- Australian English

**Recommendation:** Choose the dialect matching your audience or workplace standards.

### Language Detection

**What it does:** When enabled, TextWarden detects non-English sentences and skips them. This prevents false errors when you write in multiple languages.

**Excluded Languages:** If language detection is on, you can specify which languages to ignore (e.g., German, French, Spanish).

**Recommendation:** Enable if you frequently mix languages. Otherwise, leave it off for faster processing.

### Grammar Categories

**What it does:** Choose which types of errors TextWarden flags.

**Categories include:**
- **Spelling** - Misspelled words
- **Grammar** - Subject-verb agreement, tense consistency
- **Punctuation** - Missing or incorrect punctuation
- **Style** - Wordiness, passive voice, clichés
- **Capitalization** - Proper nouns, sentence starts
- **Repetition** - Repeated words like "the the"

**Recommendation:** Enable all categories initially. Disable specific ones only if they generate too many unwanted suggestions for your writing style.

---

## Custom Vocabulary

### Your Words

**What it does:** Words you add here will never be flagged as spelling errors. Useful for names, technical terms, brand names, and jargon specific to your field.

**How to add words:**
1. Click "Add Word" and type the term
2. Or right-click any flagged word → "Add to Dictionary"

### Built-in Word Lists

TextWarden includes optional word lists you can enable:

- **Internet Abbreviations** - Common online terms (lol, btw, imo, etc.)
- **Gen Z Slang** - Modern slang terms (vibe, slay, bussin, etc.)
- **IT Terminology** - Technical terms (kubernetes, nginx, oauth, etc.)
- **Brand Names** - Company and product names (iPhone, LinkedIn, etc.)
- **Person Names** - Common first and last names

**Recommendation:** Enable the lists matching your typical writing context. Developers might enable IT Terminology; social media managers might enable Internet Abbreviations and Gen Z Slang.

### macOS System Dictionary

**What it does:** Respects words you've already taught to macOS via "Learn Spelling" in other apps (like Safari, Mail, or Pages). This avoids having to add the same words twice.

**How it works:** TextWarden checks each flagged word against macOS's spell checker to see if you've previously learned it.

**Note:** This is read-only. Words you add via TextWarden go into TextWarden's own Custom Dictionary (below), not the macOS system dictionary.

**Default:** Enabled

**Recommendation:** Keep enabled to automatically respect words you've already taught to macOS. Disable only if you want TextWarden to use a completely separate dictionary.

---

## Style Checking (Apple Intelligence)

> **Requires:** macOS 26 (Tahoe) or later with Apple Intelligence enabled

### Enable Apple Intelligence Features

**What it does:** Activates AI-powered features using Apple Intelligence:
- **Style Suggestions** - Get suggestions for clearer, more effective phrasing
- **AI Compose** - Generate text from instructions by clicking the pen icon in the indicator

Style checking runs automatically after grammar analysis with smart rate limiting. You can also trigger it manually via keyboard shortcut or by clicking the style section of the indicator.

**What you'll see:** When enabled, you may get suggestions like "Consider rephrasing for clarity" or "This could be more concise."

### Writing Style

**What it does:** Tailors suggestions to match your intended tone.

**Options:**
- **Default** - Balanced improvements for general writing
- **Formal** - Professional tone, complete sentences, suitable for business documents
- **Casual** - Friendly, conversational, good for emails to friends or social media
- **Business** - Clear, action-oriented, ideal for professional communication
- **Concise** - Removes filler words and unnecessary verbosity

**Recommendation:** Match this to your current task. Switch between styles as needed—formal for reports, casual for Slack messages.

### Temperature Preset

**What it does:** Controls how creative vs. consistent the AI suggestions are.

**Options:**
- **Consistent** - Same input produces same suggestions (deterministic)
- **Balanced** - Slight variation while maintaining accuracy
- **Creative** - More varied suggestions, still appropriate for writing tasks

**Recommendation:** Use Consistent for professional documents where you want predictable results. Use Balanced for everyday writing.

---

## Appearance

### App Theme

**What it does:** Controls the overall look of TextWarden's interface.

**Options:**
- **System** - Follows your Mac's appearance setting
- **Light** - Always light mode
- **Dark** - Always dark mode

### Overlay Theme

**What it does:** Controls the appearance of suggestion popovers and indicators.

**Options:**
- **System** - Matches your Mac's appearance
- **Light** - Light background for popovers
- **Dark** - Dark background for popovers

### Suggestion Opacity

**What it does:** How transparent the suggestion popover appears.

**Range:** 50% (more transparent) to 100% (fully opaque)

**Recommendation:** If popovers feel too prominent, reduce opacity. If they're hard to read, increase it.

### Text Size

**What it does:** Size of text in suggestion popovers.

**Range:** Small to Large

**Recommendation:** Adjust based on your display and visual preferences.

### Underline Thickness

**What it does:** Thickness of the wavy underlines shown under errors.

**Range:** Thin to Thick

**Recommendation:** Thicker lines are more noticeable but may feel intrusive. Find your balance.

### Indicator

#### Default Position

**What it does:** Where the floating indicator appears relative to the text field.

**Options:**
- **Auto** - TextWarden chooses based on available space
- **Top Right** - Above and to the right
- **Bottom Right** - Below and to the right
- **Top Left** - Above and to the left
- **Bottom Left** - Below and to the left

You can drag the indicator to any position along the window border, and positions are remembered per application.

#### Always Show Indicator

**What it does:** When enabled, the indicator remains visible even when there are no grammar errors or style suggestions, displaying a green checkmark as confirmation that everything is fine.

**Why you'd enable it:** Provides constant visual feedback about your text quality. When Apple Intelligence is enabled, also gives quick mouse access to Style Check and AI Compose features.

**Default:** Off. The indicator only appears when there are grammar errors or style suggestions.

---

## Application Controls

TextWarden organizes applications into two categories based on their support level.

### Supported Applications

**What they are:** Applications that TextWarden has been tested and optimized for. These have dedicated configuration profiles that ensure accurate underline positioning and proper text replacement.

**Default behavior:** Active (grammar checking enabled)

**Examples:** Slack, Claude, Safari, Apple Mail, Microsoft Word, Apple Notes, and many more. See the full list in Settings → Applications.

### Other Applications

**What they are:** Applications discovered on your system that don't have a dedicated configuration profile. Grammar checking may work, but visual underlines might be inaccurate.

**Default behavior:** Paused indefinitely on first discovery. This prevents unexpected behavior in apps where TextWarden hasn't been tested.

**How to enable:** You can manually set any "Other" application to Active in Settings → Applications. Your choice persists across restarts.

**Request support:** Want TextWarden to fully support an app you use? Click the "Request" button in the Other Applications section to submit a feature request.

### Terminal Applications

**What they are:** Command-line applications like Terminal, iTerm2, Warp, and others.

**Default behavior:** Paused indefinitely. Grammar checking in terminals typically produces false positives from command output, error messages, and code snippets.

**How to enable:** You can manually enable any terminal if desired, though this isn't recommended.

### Per-App Settings

**Options for each app:**
- **Active** - TextWarden monitors and checks text
- **Paused for 1 Hour** - Temporarily disabled, automatically resumes
- **Paused for 24 Hours** - Temporarily disabled, automatically resumes
- **Paused Until Resumed** - Disabled until you manually re-enable

**Use cases:**
- Pause for apps where you intentionally write unconventionally
- Pause during presentations or screen sharing
- Enable an "Other" application you want to try with TextWarden

### Visual Underlines Toggle

Each application row has an underline button (U) that lets you enable or disable visual error underlines for that specific app, independent of grammar checking. This is useful when:
- You want grammar checking but find underlines distracting
- An app has positioning issues that make underlines inaccurate

### Global Pause

**What it does:** Quickly pause TextWarden across all applications.

**How to use:** Click the menu bar icon → select a pause duration

**Options:**
- 15 minutes
- 1 hour
- 4 hours
- Until tomorrow
- Indefinitely

---

## Keyboard Shortcuts

TextWarden supports global keyboard shortcuts that work in any application.

### Available Shortcuts

| Action | Default | Description |
|--------|---------|-------------|
| Toggle TextWarden | ⌥⌃T | Enable/disable grammar checking globally |
| Run Style Check | ⌥⌃S | Trigger manual style analysis |
| Fix All Obvious | ⌥⌃A | Apply all single-suggestion fixes at once |
| Show Suggestions | ⌥⌃G | Toggle the suggestion popover |
| Accept Suggestion | Tab | Apply the current suggestion |
| Dismiss Suggestion | ⌥Esc | Dismiss without applying |
| Previous Suggestion | ⌥← | Navigate to previous error |
| Next Suggestion | ⌥→ | Navigate to next error |
| Apply Suggestion 1 | ⌥1 | Apply first suggestion option |
| Apply Suggestion 2 | ⌥2 | Apply second suggestion option |
| Apply Suggestion 3 | ⌥3 | Apply third suggestion option |

### Customizing Shortcuts

1. Open Preferences → Shortcuts tab
2. Click on any shortcut to record a new key combination
3. Press your desired keys
4. Click elsewhere to confirm

**Tip:** Choose shortcuts that don't conflict with your most-used applications.

**Known Conflicts:**
- **Apple Mail**: `⌥⌃A` (Fix All Obvious) may conflict with some application shortcuts. Consider customizing if needed.

---

## Advanced Settings

These settings are found in **Preferences → Diagnostics**.

### Logging Configuration

**What it does:** Controls what information TextWarden records for diagnostics.

**Log Levels:**
- **Error** - Only serious problems
- **Warning** - Potential issues
- **Info** - General operation info
- **Debug** - Detailed technical info
- **Trace** - Everything (generates large log files)

**File Logging:** When enabled, writes logs to disk for later review. You can choose a custom log file location or use the default (`~/Library/Logs/TextWarden/textwarden.log`).

**Recommendation:** Keep at "Warning" or "Info" for normal use. Enable "Debug" only when troubleshooting issues.

### Debug Overlays

**What it does:** Shows colored borders around detected text fields. Useful for troubleshooting positioning issues.

**Options:**
- **Text Field Bounds** - Where TextWarden thinks the text area is
- **Window Coordinates** - Raw window position data
- **Cocoa Coordinates** - Converted screen coordinates

**Recommendation:** Keep disabled unless troubleshooting. These are developer tools.

---

## Troubleshooting Tips

**Suggestions aren't appearing:**
1. Check that TextWarden is running (look for the menu bar icon)
2. Verify the app isn't paused (icon should not show a pause indicator)
3. Ensure the current application isn't in the paused list

**Too many suggestions:**
1. Disable grammar categories that don't apply to your writing
2. Add frequently-flagged terms to your custom dictionary
3. Enable appropriate word lists (IT Terminology, etc.)

**Style checking unavailable:**
1. Requires macOS 26 (Tahoe) or later
2. Apple Intelligence must be enabled in System Settings → Apple Intelligence & Siri
3. Requires an Apple Silicon Mac (M1 or later)

**Underlines in wrong position:**
1. Try a different application if possible—some apps have limited accessibility support
2. Check Debug Overlays to see what TextWarden detects
3. Report the issue with a diagnostic export (Help → Export Diagnostics)

---

## Getting Help

- **Troubleshooting Guide:** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Report Issues:** [GitHub Issues](https://github.com/philipschmid/textwarden/issues)
- **Export Diagnostics:** Help → Export Diagnostics (includes logs, settings, no personal text)
