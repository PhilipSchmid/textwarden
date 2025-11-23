# Launch at Login Migration Guide

This document outlines the migration from the custom `LoginItemManager` to the `LaunchAtLogin-Modern` Swift package.

## Overview

TextWarden is migrating to use [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) for handling launch-at-login functionality. This provides a simpler, more maintainable solution compared to our custom implementation.

## Benefits of LaunchAtLogin-Modern

1. **Code Reduction**: ~77 lines of custom code → ~5 lines using the library
2. **SwiftUI-First**: Provides ready-made `LaunchAtLogin.Toggle()` component
3. **Well-Maintained**: Community-maintained by sindresorhus (trusted macOS developer)
4. **App Store Compliant**: Built-in safeguards for Mac App Store requirements
5. **Perfect Fit**: Requires macOS 13+, TextWarden requires macOS 14.0+ (Sonoma)

## Implementation Status

### ✅ Completed

- [x] Added launch-at-login question to onboarding wizard
- [x] New onboarding step appears after accessibility permission grant
- [x] User can choose "Enable Launch at Login" or "Not Now"
- [x] Added TODO comments marking where LaunchAtLogin will be used
- [x] Default remains `false` (user must explicitly enable)

### 🔄 To Complete

The following steps require adding the package via Xcode:

## Step 1: Add LaunchAtLogin-Modern Package

1. Open `TextWarden.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter the package URL:
   ```
   https://github.com/sindresorhus/LaunchAtLogin-Modern
   ```
4. Select **"Up to Next Major Version"** with `1.0.0`
5. Click **Add Package**
6. Ensure the package is added to the **TextWarden** target

## Step 2: Update OnboardingView.swift

Replace the current implementation in `handleEnableLaunchAtLogin()`:

```swift
// BEFORE (current):
private func handleEnableLaunchAtLogin() {
    print("✅ Onboarding: Enabling launch at login...")
    // TODO: Replace with LaunchAtLogin.isEnabled = true once LaunchAtLogin-Modern is added
    LoginItemManager.shared.setLaunchAtLogin(true)
    dismiss()
}

// AFTER:
import LaunchAtLogin  // Add to top of file

private func handleEnableLaunchAtLogin() {
    print("✅ Onboarding: Enabling launch at login...")
    LaunchAtLogin.isEnabled = true
    dismiss()
}
```

## Step 3: Update PreferencesView.swift

Replace the manual toggle with LaunchAtLogin.Toggle():

```swift
// BEFORE (current - around line 795):
// TODO: Replace with LaunchAtLogin.Toggle() once LaunchAtLogin-Modern package is added
// LaunchAtLogin.Toggle()
Toggle("Launch TextWarden at login", isOn: $preferences.launchAtLogin)
    .help("Automatically start TextWarden when you log in")

// AFTER:
import LaunchAtLogin  // Add to top of file

LaunchAtLogin.Toggle()
```

The `LaunchAtLogin.Toggle()` component automatically provides:
- Correct label ("Launch at login")
- Proper binding to system state
- App Store compliance

## Step 4: Clean Up UserPreferences.swift

Remove the now-unused `launchAtLogin` property:

```swift
// REMOVE these lines (around lines 203-208, 495, 578, 912):
@Published var launchAtLogin: Bool {
    didSet {
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        LoginItemManager.shared.setLaunchAtLogin(launchAtLogin)
    }
}
// ... initialization code ...
self.launchAtLogin = false
// ... loading code ...
self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
// ... Keys enum ...
static let launchAtLogin = "launchAtLogin"
```

## Step 5: Remove or Deprecate LoginItemManager.swift

Option A: Delete the file entirely
```bash
git rm Sources/Models/LoginItemManager.swift
```

Option B: Mark as deprecated (if you want to keep it temporarily)
```swift
@available(*, deprecated, message: "Use LaunchAtLogin from LaunchAtLogin-Modern package instead")
class LoginItemManager {
    // ... existing code ...
}
```

## Step 6: Test

1. **Clean build** the project
2. **Delete the app** from Applications if previously installed
3. **Run the app** and go through onboarding:
   - Grant accessibility permission
   - See the new "Launch at Login" step
   - Test both "Enable" and "Not Now" options
4. **Verify in System Settings**:
   - Go to System Settings → General → Login Items
   - Check if TextWarden appears when enabled
5. **Test the Preferences toggle**:
   - Open Preferences → General
   - Toggle launch at login on/off
   - Verify it persists across app restarts

## Step 7: Commit

```bash
git add -A
git commit -m "refactor: migrate to LaunchAtLogin-Modern package

- Replace custom LoginItemManager with LaunchAtLogin-Modern
- Simplify code from ~77 lines to ~5 lines
- Add launch-at-login question to onboarding wizard
- Use LaunchAtLogin.Toggle() in preferences
- Remove UserPreferences.launchAtLogin property
- Default remains false (explicit user opt-in required)

Benefits:
- Simpler, more maintainable code
- Better SwiftUI integration
- Community-maintained package
- App Store compliant

Package: https://github.com/sindresorhus/LaunchAtLogin-Modern"
```

## Verification Checklist

- [ ] LaunchAtLogin-Modern package added via Xcode
- [ ] OnboardingView imports LaunchAtLogin
- [ ] PreferencesView imports LaunchAtLogin
- [ ] PreferencesView uses `LaunchAtLogin.Toggle()`
- [ ] UserPreferences.launchAtLogin property removed
- [ ] LoginItemManager removed or deprecated
- [ ] Build succeeds with no errors
- [ ] Onboarding shows launch-at-login step
- [ ] Launch at login can be enabled/disabled in preferences
- [ ] Setting persists across app restarts
- [ ] App appears in System Settings → Login Items when enabled
- [ ] Default is false (requires explicit user action)

## Rollback Plan

If issues arise, the current `LoginItemManager` implementation can be restored from this commit. The onboarding changes are additive and can remain even if reverting the LaunchAtLogin package.

## References

- [LaunchAtLogin-Modern GitHub](https://github.com/sindresorhus/LaunchAtLogin-Modern)
- [Mac App Store Guidelines on Launch at Login](https://developer.apple.com/app-store/review/guidelines/)
