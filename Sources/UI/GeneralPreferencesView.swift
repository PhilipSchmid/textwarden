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

                Toggle("Always open in foreground", isOn: $preferences.openInForeground)
                    .help("Show settings window when TextWarden starts (default: background only)")
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transparency:")
                        Spacer()
                        Text(String(format: "%.0f%%", preferences.suggestionOpacity * 100))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $preferences.suggestionOpacity, in: 0.2...1.0, step: 0.05)

                    Text("Adjust the background transparency of suggestion popovers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Text size:")
                        Spacer()
                        Text(String(format: "%.0fpt", preferences.suggestionTextSize))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $preferences.suggestionTextSize, in: 10.0...20.0, step: 1.0)

                    Text("Font size for suggestion text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Typography")
                    .font(.headline)
            }

            Section {
                Picker("Position:", selection: $preferences.suggestionPosition) {
                    ForEach(UserPreferences.suggestionPositions, id: \.self) { position in
                        Text(position).tag(position)
                    }
                }
                .help("Choose where suggestions appear relative to text")

                Text("Auto: Choose position based on available space")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Layout")
                    .font(.headline)
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
                Picker("Default position:", selection: $preferences.indicatorPosition) {
                    ForEach(UserPreferences.indicatorPositions, id: \.self) { position in
                        Text(position).tag(position)
                    }
                }
                .help("Choose the default position for new applications. Drag the indicator to customize per-app positions.")

                Text("Default position for the floating error indicator badge. Positions are remembered per application after you drag the indicator.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Error Indicator")
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
                KeyboardShortcuts.Recorder("Toggle Grammar Checking:", name: .toggleGrammarChecking)
                KeyboardShortcuts.Recorder("Run Style Check:", name: .runStyleCheck)

                Text("Works system-wide, even when TextWarden isn't the active app")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Global Shortcuts")
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

            // MARK: Logging Configuration - moved from Diagnostics
            LoggingConfigurationView(preferences: preferences)
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

// MARK: - Logging Configuration View

struct LoggingConfigurationView: View {
    @ObservedObject var preferences: UserPreferences
    @State private var selectedLogLevel: LogLevel = Logger.minimumLogLevel
    @State private var fileLoggingEnabled: Bool = Logger.fileLoggingEnabled
    @State private var logFilePath: String = Logger.logFilePath

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configure log verbosity and output location for debugging")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                // Log Level Picker
                HStack {
                    Text("Log Level:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Log Level", selection: $selectedLogLevel) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedLogLevel) { _, newValue in
                        Logger.minimumLogLevel = newValue
                    }

                    Spacer()
                }

                Text("Controls verbosity: Debug shows all messages, Critical shows only severe issues")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()
                    .padding(.vertical, 4)

                // File Logging Toggle
                Toggle("Enable File Logging", isOn: $fileLoggingEnabled)
                    .onChange(of: fileLoggingEnabled) { _, newValue in
                        Logger.fileLoggingEnabled = newValue
                    }
                    .help("Write logs to a file for debugging purposes")

                if fileLoggingEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        // Log File Path Configuration
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Log File Location:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            // Path displayed in a styled text field
                            HStack {
                                Text(logFilePath)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .help("Current log file path. Click 'Choose' to change location.")
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )

                            Text("You can choose a custom location using the button below, or use the default location")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                Button("Choose Location...") {
                                    chooseLogFilePath()
                                }
                                .buttonStyle(.bordered)
                                .help("Select a custom location for log files")

                                if Logger.customLogFilePath != nil {
                                    Button("Reset to Default") {
                                        resetLogFilePathToDefault()
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Use default location: ~/Library/Logs/TextWarden/")
                                }

                                Button("Open in Finder") {
                                    NSWorkspace.shared.selectFile(logFilePath, inFileViewerRootedAtPath: "")
                                }
                                .buttonStyle(.bordered)
                                .help("Show log file in Finder")
                            }

                            Text("Default: ~/Library/Logs/TextWarden/textwarden.log")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("Logging Configuration")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Text("Configure debug logging and file output settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func chooseLogFilePath() {
        let savePanel = NSSavePanel()
        savePanel.title = "Choose Log File Location"
        savePanel.message = "Select where to save log files"
        savePanel.nameFieldStringValue = "textwarden.log"
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false

        // Set default directory to ~/Library/Logs/TextWarden
        let defaultLogDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TextWarden")
        savePanel.directoryURL = defaultLogDir

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            // Save the custom path
            Logger.customLogFilePath = url.path
            logFilePath = url.path

            Logger.info("Log file path changed to: \(url.path)", category: Logger.general)
        }
    }

    private func resetLogFilePathToDefault() {
        Logger.resetLogFilePathToDefault()
        logFilePath = Logger.logFilePath

        Logger.info("Log file path reset to default", category: Logger.general)
    }
}

/// Separate text field component to avoid crashes with Int binding
struct AnalysisDelayTextField: View {
    @ObservedObject var preferences: UserPreferences
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        TextField("", text: $text)
            .frame(width: 80)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .onAppear {
                text = String(preferences.analysisDelayMs)
            }
            .onChange(of: text) { oldValue, newValue in
                // Cancel previous save task
                saveTask?.cancel()

                // Save after a short delay (500ms) when user stops typing
                saveTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !Task.isCancelled {
                        await MainActor.run {
                            saveValue()
                        }
                    }
                }
            }
            .onChange(of: isFocused) { oldValue, newValue in
                // When field loses focus, save immediately
                if !newValue {
                    saveTask?.cancel()
                    saveValue()
                }
            }
            .onSubmit {
                saveTask?.cancel()
                saveValue()
            }
            .onExitCommand {
                saveTask?.cancel()
                saveValue()
            }
    }

    private func saveValue() {
        if let value = Int(text), value > 0 {
            preferences.analysisDelayMs = value
        } else {
            // Revert to current value if invalid
            text = String(preferences.analysisDelayMs)
        }
    }
}
