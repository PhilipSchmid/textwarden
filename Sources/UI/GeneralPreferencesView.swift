//
//  GeneralPreferencesView.swift
//  TextWarden
//
//  General preferences including appearance, permissions, and keyboard shortcuts.
//

import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts
import AppKit

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @ObservedObject var preferences: UserPreferences
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var showingPermissionDialog = false

    var body: some View {
        Form {
            // MARK: Application Settings Group
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Grammar checking:", selection: $preferences.pauseDuration) {
                        ForEach(PauseDuration.allCases, id: \.self) { duration in
                            Text(duration.rawValue).tag(duration)
                        }
                    }
                    .help("Pause grammar checking temporarily or indefinitely")
                    .onChange(of: preferences.pauseDuration) { _, newValue in
                        // Update menu bar icon when pause duration changes
                        let iconState: MenuBarController.IconState = newValue == .active ? .active : .inactive
                        MenuBarController.shared?.setIconState(iconState)
                    }

                    if preferences.pauseDuration == .oneHour, let until = preferences.pausedUntil {
                        Text("Will resume at \(until.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                LaunchAtLogin.Toggle()
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Application Settings")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Configure core application behavior and system permissions")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("General")
                        .font(.headline)
                        .padding(.top, 8)
                }
            }

            // Accessibility Permission Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: permissionManager.isPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(permissionManager.isPermissionGranted ? .green : .red)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility Permission")
                                .font(.headline)
                            Text(permissionManager.isPermissionGranted ? "Granted" : "Not Granted")
                                .font(.subheadline)
                                .foregroundColor(permissionManager.isPermissionGranted ? .green : .red)
                        }

                        Spacer()
                    }

                    Text(permissionManager.isPermissionGranted ?
                         "TextWarden has the necessary permissions to monitor your text and provide grammar checking." :
                         "TextWarden needs Accessibility permissions to monitor your text.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !permissionManager.isPermissionGranted {
                        HStack(spacing: 12) {
                            Button {
                                permissionManager.requestPermission()
                                showingPermissionDialog = true
                            } label: {
                                HStack {
                                    Image(systemName: "lock.open")
                                    Text("Request Permission")
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                permissionManager.openSystemSettings()
                            } label: {
                                HStack {
                                    Image(systemName: "gearshape")
                                    Text("Open System Settings")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } header: {
                Text("Permissions")
                    .font(.headline)
            }

            // MARK: Appearance Settings Group
            Section {
                Picker("Position:", selection: $preferences.suggestionPosition) {
                    ForEach(UserPreferences.suggestionPositions, id: \.self) { position in
                        Text(position).tag(position)
                    }
                }
                .help("Choose where suggestion popovers appear relative to text")

                Toggle("Show on hover", isOn: $preferences.enableHoverPopover)
                    .help("Automatically show suggestions when hovering over underlines or the error indicator")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Text size:")
                        Spacer()
                        Text(String(format: "%.0fpt", preferences.suggestionTextSize))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $preferences.suggestionTextSize, in: 10.0...20.0, step: 1.0)
                }

                Text("Position: Where the popover appears (Auto adjusts based on screen space). Show on hover: When disabled, click underlines or the indicator to show suggestions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Appearance Settings")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Customize the visual appearance of grammar suggestions and indicators")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Popover")
                        .font(.headline)
                        .padding(.top, 8)
                }
            }

            Section {
                Picker("Theme:", selection: $preferences.appTheme) {
                    ForEach(UserPreferences.themeOptions, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .help("Color scheme for the TextWarden application UI")

                Picker("Overlay Theme:", selection: $preferences.overlayTheme) {
                    ForEach(UserPreferences.themeOptions, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .help("Color scheme for popovers and error/style indicators")

                Text("Theme: Controls the TextWarden settings window appearance\nOverlay Theme: Controls popovers and indicators shown over other apps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Color Scheme")
                    .font(.headline)
            }

            Section {
                Toggle("Show error underlines", isOn: $preferences.showUnderlines)
                    .help("Show wavy underlines beneath spelling and grammar errors")

                if preferences.showUnderlines {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Thickness:")
                            Spacer()
                            Text(String(format: "%.1fpt", preferences.underlineThickness))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $preferences.underlineThickness, in: 1.0...5.0, step: 0.5)
                    }
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Hide when errors exceed:")
                            Spacer()
                            Text("\(preferences.maxErrorsForUnderlines)")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(preferences.maxErrorsForUnderlines) },
                                set: { preferences.maxErrorsForUnderlines = Int($0) }
                            ),
                            in: 1...20,
                            step: 1
                        )
                    }
                    .padding(.top, 4)
                }

                Text("Underlines are only shown in applications with proper accessibility API support (e.g., native macOS apps, Slack, Notion). Some apps like Microsoft Teams and web browsers don't provide accurate text positioning, so only the floating error indicator is used. When the error count exceeds the threshold above, underlines are hidden to reduce visual clutter.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Underlines")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Default position:", selection: $preferences.indicatorPosition) {
                        ForEach(UserPreferences.indicatorPositions, id: \.self) { position in
                            Text(position).tag(position)
                        }
                    }
                    .help("Choose the default position for new applications. Drag the indicator to customize per-app positions.")

                    Text("Default position for the floating indicator. You can drag it to any position along the window border, and positions are remembered per application.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle(isOn: $preferences.alwaysShowCapsule) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Always show indicator")
                        Text("Show even when there are no issues, displaying a green checkmark as confirmation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hover delay:")
                        Spacer()
                        Text("\(preferences.popoverHoverDelayMs) ms")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(preferences.popoverHoverDelayMs) },
                            set: { preferences.popoverHoverDelayMs = Int($0) }
                        ),
                        in: 0...1000,
                        step: 50
                    )
                    Text("Delay before showing the suggestion popover when hovering over the indicator. Set to 0 for instant display.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help("Time to wait before showing the suggestion popover when hovering over the indicator. 0 = instant.")
            } header: {
                Text("Indicator")
                    .font(.headline)
            }

            // MARK: Keyboard Shortcuts Group
            Section {
                Toggle("Enable keyboard shortcuts", isOn: $preferences.keyboardShortcutsEnabled)
                    .help("Enable or disable all keyboard shortcuts")

                Text("When disabled, keyboard shortcuts will not trigger any actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Keyboard Shortcuts")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Configure global and context-specific keyboard shortcuts")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("General")
                        .font(.headline)
                        .padding(.top, 8)
                }
            }

            Section {
                KeyboardShortcuts.Recorder("Toggle TextWarden:", name: .toggleTextWarden)
                KeyboardShortcuts.Recorder("Fix All Grammar Errors:", name: .fixAllObvious)

                Text("Works system-wide, even when TextWarden isn't the active app")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Global Shortcuts")
                    .font(.headline)
            }

            Section {
                KeyboardShortcuts.Recorder("Show Grammar Suggestions:", name: .showGrammarSuggestions)
                KeyboardShortcuts.Recorder("Show Style Suggestions:", name: .showStyleSuggestions)
                KeyboardShortcuts.Recorder("Show AI Compose:", name: .showAICompose)
                KeyboardShortcuts.Recorder("Run Style Check:", name: .runStyleCheck)

                Text("Quick access to grammar, style, and AI writing features")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Feature Shortcuts")
                    .font(.headline)
            }

            Section {
                KeyboardShortcuts.Recorder("Accept Suggestion:", name: .acceptSuggestion)
                KeyboardShortcuts.Recorder("Dismiss Popover:", name: .dismissSuggestion)
                KeyboardShortcuts.Recorder("Previous Suggestion:", name: .previousSuggestion)
                KeyboardShortcuts.Recorder("Next Suggestion:", name: .nextSuggestion)

                Text("These shortcuts work when the suggestion popover is visible")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Suggestion Popover")
                    .font(.headline)
            }

            Section {
                KeyboardShortcuts.Recorder("Apply 1st Suggestion:", name: .applySuggestion1)
                KeyboardShortcuts.Recorder("Apply 2nd Suggestion:", name: .applySuggestion2)
                KeyboardShortcuts.Recorder("Apply 3rd Suggestion:", name: .applySuggestion3)

                Text("Quickly apply suggestions by number from the popover")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Quick Apply")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Permission Requested", isPresented: $showingPermissionDialog) {
            Button("OK") {
                showingPermissionDialog = false
            }
        } message: {
            Text("Please check System Settings to grant Accessibility permission to TextWarden.")
        }
    }
}

