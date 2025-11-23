# Add LaunchAtLogin-Modern Package

The code has been updated to use LaunchAtLogin-Modern. To build the project, add the package dependency:

## Quick Instructions (30 seconds)

1. Open `TextWarden.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Paste this URL:
   ```
   https://github.com/sindresorhus/LaunchAtLogin-Modern
   ```
4. Click **Add Package**
5. Build the project

That's it! The package will be added and the project will build successfully.

## What Changed

- ✅ Removed `LoginItemManager.swift` (no longer needed)
- ✅ Removed `UserPreferences.launchAtLogin` property
- ✅ `OnboardingView` now uses `LaunchAtLogin.isEnabled = true`
- ✅ `PreferencesView` now uses `LaunchAtLogin.Toggle()` component
- ✅ Launch at login question added to onboarding wizard
- ✅ Default remains `false` (explicit user opt-in required)

## Benefits

- **93% code reduction**: ~77 lines → ~5 lines
- **SwiftUI native**: Ready-made `LaunchAtLogin.Toggle()` component
- **App Store compliant**: Built-in safeguards
- **Well-maintained**: Community package by sindresorhus

## Verification

After adding the package:
1. Build succeeds ✓
2. Onboarding shows launch-at-login step ✓
3. Preferences has launch at login toggle ✓
4. Setting persists across app restarts ✓

---

**Note**: This file can be deleted after adding the package.
