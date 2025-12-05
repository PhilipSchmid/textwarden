# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with TextWarden.

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

1. Style checking is disabled by default - enable it in Settings
2. Ensure an AI model is downloaded and loaded
3. Check that the text meets minimum length requirements
4. Try using the keyboard shortcut (`Cmd+Control+S`) to trigger a manual check

### High memory or CPU usage

1. Check Settings > Statistics for resource usage information
2. If using AI style checking, the model requires additional memory
3. Try restarting TextWarden from the menu bar

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
2. Go to the **Advanced** tab
3. Click **Export Diagnostics**
4. Save the diagnostic package

The exported package includes:
- Application logs
- System information (macOS version, hardware)
- TextWarden configuration (no personal data)
- Performance metrics
- Crash reports (if any)

**Note**: The diagnostic export does not include any of your text or personal writing - only technical information needed for troubleshooting. We recommend extracting the ZIP file and reviewing its contents before uploading to ensure you're comfortable sharing the included information.

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
