# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with TextWarden.

## Installation Issues

### App doesn't launch when double-clicked

TextWarden is a menu bar app (no dock icon), which can cause silent launch failures on first run. Try these solutions in order:

#### Solution 1: Right-click to Open (Recommended)

Since TextWarden runs in the menu bar only, the standard Gatekeeper approval dialog may not appear. Force the approval:

1. Right-click (or Control-click) on `/Applications/TextWarden.app`
2. Select **"Open"** from the context menu
3. Click **"Open"** in the dialog that appears
4. Look for the TextWarden icon in your menu bar

#### Solution 2: Remove Quarantine Attribute

Downloaded files have a quarantine attribute that triggers Gatekeeper. Remove it:

```bash
xattr -cr /Applications/TextWarden.app
```

Then double-click the app or right-click → Open.

#### Solution 3: Clean Installation (After Upgrade)

If you upgraded by dragging over an existing installation, the old app's attributes may cause conflicts:

```bash
# 1. Quit TextWarden if running
killall TextWarden 2>/dev/null

# 2. Remove the old installation completely
rm -rf /Applications/TextWarden.app

# 3. Reinstall from the DMG
# Mount the DMG and drag TextWarden to Applications

# 4. Register the new app with LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister /Applications/TextWarden.app

# 5. Right-click → Open for first launch
```

#### Solution 4: Check System Logs

If the app still doesn't launch, check for errors:

```bash
# Check for recent TextWarden-related logs
log show --predicate 'process == "TextWarden" OR subsystem == "io.textwarden.TextWarden"' --last 5m

# Check for Gatekeeper blocks
log show --predicate 'subsystem == "com.apple.launchservices" AND eventMessage CONTAINS "TextWarden"' --last 5m
```

**Verify your installation is properly signed:**
```bash
spctl -a -vv /Applications/TextWarden.app
```
Should show: `accepted` and `source=Notarized Developer ID`

If it shows `rejected` or `origin=Apple Development`, you have a development build installed.

### "TextWarden is damaged" or similar Gatekeeper warnings

1. Remove the quarantine attribute:
   ```bash
   xattr -cr /Applications/TextWarden.app
   ```
2. Right-click → Open to approve through Gatekeeper

## Common Issues

### TextWarden doesn't detect text in an application

1. **Check Accessibility permissions**: Go to System Settings > Privacy & Security > Accessibility and ensure TextWarden is enabled
2. **Check if the app is disabled**: Open TextWarden settings and verify the application isn't in your disabled list
3. **Restart the application**: Some apps need to be restarted after granting accessibility permissions
4. **Check Known Limitations**: Some applications have limited accessibility support - see the [Known Limitations](README.md#known-limitations) section

### The floating indicator doesn't appear

1. Ensure grammar checking isn't paused (check the menu bar icon)
2. Verify the application isn't disabled in settings
3. Check if the website is disabled (for browser-based text fields)
4. The indicator only appears when errors are found - try typing a deliberate misspelling

### Style suggestions aren't working

1. Style checking is disabled by default - enable it in Settings → Style
2. Requires macOS 26 (Tahoe) or later with Apple Intelligence enabled in System Settings
3. Style checking only runs on text longer than ~50 characters
4. Try using the keyboard shortcut (`Option+Control+S`) to trigger a manual check

### High memory or CPU usage

1. Check Settings > Statistics for resource usage information
2. If using AI style checking, the model requires additional memory
3. Try restarting TextWarden from the menu bar

### How to reset settings or re-run onboarding

**Via the app:**
1. Open TextWarden Settings
2. Go to the **Diagnostics** tab
3. Click **Reset All Settings** - this will restart the app and show the onboarding wizard

**Via Terminal (for developers):**
```bash
# Reset only the onboarding flag
defaults delete io.textwarden.TextWarden hasCompletedOnboarding

# Or reset all preferences
defaults delete io.textwarden.TextWarden
```
Then restart TextWarden to see the changes.

### Visual underlines appear misaligned

Visual underlines rely on macOS Accessibility APIs to determine character positions. Not all applications expose accurate positioning data.

**Supported applications**: Visual underlines have been tested and calibrated for:
- Slack, Claude, ChatGPT, Perplexity
- Safari and other Chromium-based browsers (Chrome, Edge, Arc, Brave, Comet)
- Apple Mail, Apple Messages
- Telegram, WhatsApp, Webex
- Microsoft Outlook

For other applications (including Notion, Microsoft Teams, Word, PowerPoint), the floating error indicator works as a fallback. If you'd like visual underlines for a specific app that isn't listed above, please open a [feature request](https://github.com/philipschmid/textwarden/discussions) describing the app and how you use it.

**If underlines appear offset in a supported app**:

1. **Enable trace logging**: In Settings > Diagnostics, set the log level to "Trace" to capture detailed positioning data. Note: Debug and Trace levels may include portions of analyzed text for troubleshooting purposes.
2. **Check the logs**: Look at `~/Library/Logs/TextWarden/textwarden.log` for entries from positioning strategies (InsertionPointStrategy, ChromiumStrategy, etc.)
3. **Multi-monitor setups**: If underlines appear correct on your primary display but offset on external monitors, this may be a coordinate conversion issue
4. **Report the issue**: Use Export Diagnostics (which includes the trace logs) and include:
   - The application name and version
   - Whether you're using an external monitor
   - Screenshots showing the misalignment

## Collecting Diagnostic Information

When reporting issues, please include diagnostic information to help us investigate.

### Log Files

TextWarden logs are stored at:
```
~/Library/Logs/TextWarden/textwarden.log
```

You can configure the log level in Settings under the Advanced section.

### Export Diagnostics

The easiest way to collect all diagnostic information is to use the built-in export feature:

1. Open TextWarden Settings
2. Go to the **Diagnostics** tab
3. Click **Export Diagnostics**
4. Save the diagnostic package

The exported package includes:
- Application logs
- System information (macOS version, hardware)
- TextWarden configuration (no personal data)
- Performance metrics
- Crash reports (if any)

**Note**: At the default log level (Info), the diagnostic export does not include any of your text or personal writing - only technical information needed for troubleshooting. If you've enabled Debug or Trace logging for troubleshooting, the logs may contain portions of analyzed text. Consider switching back to Info level before exporting if this is a concern. We recommend extracting the ZIP file and reviewing its contents before uploading to ensure you're comfortable sharing the included information.

## Reporting Issues

When opening a bug report, please include:

1. **Diagnostic export**: Use the Export Diagnostics feature described above
2. **Screenshots**: If the issue is visual, include screenshots showing the problem
3. **Steps to reproduce**: Describe exactly what you were doing when the issue occurred
4. **Expected vs actual behavior**: What did you expect to happen, and what happened instead?
5. **Application context**: Which application were you using when the issue occurred?

### Opening an Issue

1. Go to [GitHub Issues](https://github.com/philipschmid/textwarden/issues/new/choose)
2. Select the **Bug Report** template
3. Fill in the requested information
4. Attach your diagnostic export and any screenshots

### Feature Requests

For feature requests, please use [GitHub Discussions](https://github.com/philipschmid/textwarden/discussions) instead of issues. This allows for community discussion and voting on ideas.

## Getting Help

- Check existing [GitHub Issues](https://github.com/philipschmid/textwarden/issues) to see if your problem has been reported
- Browse [GitHub Discussions](https://github.com/philipschmid/textwarden/discussions) for questions and answers
- Review the [README](README.md) for feature documentation
