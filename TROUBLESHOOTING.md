# TextWarden Troubleshooting

Use this guide when the macOS grammar checker does not launch, cannot read a text field, shows stale suggestions, or places underlines incorrectly.

## TextWarden Does Not Launch

TextWarden is a menu bar app and does not show a Dock icon. After opening it, look for the feather icon in the menu bar.

### Open the downloaded app once

1. Move `TextWarden.app` to `/Applications`.
2. Control-click the app and choose **Open**.
3. Confirm **Open** in the macOS dialog.

Official release DMGs are signed with Developer ID and notarized by Apple. Check the installed copy:

```bash
spctl --assess --type execute --verbose=4 /Applications/TextWarden.app
codesign --verify --deep --strict --verbose=2 /Applications/TextWarden.app
```

Gatekeeper should report that the app is accepted and identify a notarized Developer ID source. If verification fails, delete the copy through Finder and download the latest DMG again from [GitHub Releases](https://github.com/PhilipSchmid/textwarden/releases/latest).

### Check launch logs

```bash
log show \
  --predicate 'process == "TextWarden" OR subsystem == "io.textwarden.TextWarden"' \
  --last 5m
```

For a local development build, use [BUILD.md](BUILD.md) and make sure the build completed before launching.

## Accessibility Permission

TextWarden needs Accessibility permission to monitor and edit text in other apps.

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Enable TextWarden.
3. Restart the host app whose text you want to check.

If permission remains stuck, remove TextWarden from the list, launch `/Applications/TextWarden.app` again, and grant access to that exact copy. Rebuilt or differently signed apps can appear as a new identity to macOS.

## Text Is Not Being Checked

Check these in order:

1. Confirm TextWarden is active in its menu bar menu.
2. Open **Preferences → Applications** and check the current app. For an unrecognized app, choose **Try Safely** to use the indicator and copy-only fixes, or leave it paused.
3. In a browser, open **Preferences → Websites** and make sure the current domain is not excluded.
4. Type into an editable field, not rendered page text, a PDF, or a non-editable preview.
5. Try a deliberate error such as `This are wrong.`

Some editors expose their text incompletely through macOS Accessibility APIs. The [supported-app matrix](README.md#supported-apps) and [application notes](docs/applications/README.md) describe known exceptions.

## The Floating Indicator Is Missing

By default, the indicator appears only when TextWarden has something to show. If you want a constant status marker, enable **Preferences → General → Always show indicator**.

If it still does not appear:

- Confirm global and per-app checking are active.
- Confirm the current website is not excluded.
- Check that Accessibility permission is granted.
- Try an obvious spelling or grammar error.
- Switch focus to another field and back.

## Suggestions or Underlines Are Stale

TextWarden validates the source text, focused app, Accessibility element, and analysis generation before applying asynchronous grammar results. If old results remain visible:

1. Move focus to another editable field and back.
2. Pause and resume TextWarden from the menu bar.
3. Restart TextWarden.
4. Export diagnostics and report the host app, the field type, and the sequence that left stale UI behind.

Do not apply a correction when the suggestion's quoted source no longer matches the field.

## Visual Underlines Are Missing or Misaligned

Underlines depend on character bounds exposed by the host app. Grammar checking and the floating indicator can work even when precise bounds do not.

TextWarden has dedicated positioning support for the apps listed in [Supported Apps](README.md#supported-apps). Notion is partial because some virtualized blocks are absent from its Accessibility tree. PowerPoint support is limited to speaker notes because slide text boxes are not exposed.

For an offset in a supported editor:

1. Note the app version, field type, display arrangement, and display scaling.
2. Test on the primary display and an external display if available.
3. Open **Preferences → Diagnostics** and enable the relevant bounds overlay.
4. Set logging to Trace only long enough to reproduce the problem.
5. Export diagnostics, return logging to Info, and inspect the ZIP before sharing it.

You can disable underlines for one app under **Preferences → Applications** while keeping grammar suggestions in the floating indicator.

## A Correction Changes Formatting or the Wrong Text

Text replacement differs by app. Native editors may allow a direct Accessibility range replacement; browser, Electron, and WebKit editors may require selection and paste.

If formatting changes or the wrong range is selected:

1. Undo with `⌘Z` immediately.
2. Copy the suggestion instead of applying it if the popover offers that fallback.
3. Record whether the field contains links, mentions, lists, emoji, or rich formatting.
4. File a bug with a minimal example and diagnostic export.

TextWarden aborts a replacement when its selection validation fails. A recurring failure usually means the host editor needs an app-specific replacement strategy.

## Apple Intelligence Features Are Unavailable

AI Style Suggestions, AI Compose, sentence simplification, and AI readability tips require:

- macOS 26 or later
- A supported Apple Silicon Mac
- Apple Intelligence enabled under **System Settings → Apple Intelligence & Siri**
- The on-device model downloaded and ready

Open **Preferences → Style** to see the current availability state. **Model Not Ready** is temporary; wait for macOS to finish preparing the model, then choose **Check Again**.

Style suggestions are off by default. After you enable them, automatic analysis waits for at least 50 characters, a three-second typing pause, and the 30-second rate limit. Press `⌥⌃S` for a manual style check.

Harper grammar and spelling, language detection, and Flesch readability scoring do not require Apple Intelligence.

## High CPU or Memory Use

1. Open **Preferences → Statistics** to inspect recorded resource usage.
2. Pause AI Style Suggestions and compare usage.
3. Return Debug or Trace logging to Info.
4. Restart TextWarden.
5. If the problem returns in one host app, export diagnostics and include that app and field type in the report.

## Reset Settings or Onboarding

From **Preferences → Diagnostics**, you can reset all settings, clear the custom dictionary, clear ignored rules or error text, and reset milestone prompts. Statistics have a separate reset control under **Preferences → Statistics**. **Reset All Settings** relaunches the app and shows onboarding.

Developers can reset onboarding only:

```bash
defaults delete io.textwarden.TextWarden hasCompletedOnboarding
```

Or remove all TextWarden preferences:

```bash
defaults delete io.textwarden.TextWarden
```

Restart TextWarden after using either command. Deleting the full preferences domain resets user choices; it does not remove the application.

## Logs

TextWarden always uses macOS Unified Logging. Optional file logging writes to:

```text
~/Library/Logs/TextWarden/textwarden.log
```

Stream live unified logs with:

```bash
log stream \
  --predicate 'subsystem == "io.textwarden.TextWarden"' \
  --style compact
```

Info is the default level and most Info messages record metadata. Warning and error diagnostics for failed or stale replacements can include short text fragments, while Debug and Trace may include more analyzed text. Review logs before sharing them.

## Export Diagnostics

Open **Preferences → Diagnostics → Export Diagnostics**. The ZIP can include:

- System, permission, configuration, app-state, usage, performance, and Apple Intelligence metadata
- Sanitized TextWarden file logs, including rotated logs
- Up to ten recent TextWarden crash reports

The exporter anonymizes user-directory paths in logs and removes log lines containing common secret keywords. This is a safeguard, not a guarantee. Logs and macOS crash reports can contain sensitive context. Extract and inspect the archive before uploading it.

## Report a Bug

[Open the bug report form](https://github.com/PhilipSchmid/textwarden/issues/new/choose) and include:

- TextWarden version from **Preferences → About**
- macOS version and Mac model
- Host application and version
- Exact reproduction steps
- Expected and actual behavior
- Screenshots for visual problems
- A reviewed diagnostic export when relevant

Use [GitHub Discussions](https://github.com/PhilipSchmid/textwarden/discussions) for feature requests and questions.
