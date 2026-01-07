//
//  DiagnosticsView.swift
//  TextWarden
//
//  Diagnostics view showing debugging information and system monitoring.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Diagnostics View

struct DiagnosticsView: View {
    @ObservedObject var preferences: UserPreferences
    @ObservedObject private var applicationTracker = ApplicationTracker.shared
    @State private var isExporting: Bool = false
    @State private var showingExportSuccess: Bool = false
    @State private var showingExportError: Bool = false
    @State private var exportedFilePath: String = ""
    @State private var exportedFileSize: String = ""
    @State private var lastMilestoneResetClick: Date?

    var body: some View {
        Form {
            // MARK: - Active Application Monitoring

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "eye.fill")
                            .font(.title2)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Currently Monitoring")
                                .font(.headline)
                            if let app = applicationTracker.activeApplication {
                                Text(app.applicationName)
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            } else {
                                Text("No application")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Live indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .opacity(applicationTracker.activeApplication != nil ? 1.0 : 0.3)
                            Text("Live")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let app = applicationTracker.activeApplication {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Application:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(app.applicationName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }

                            HStack {
                                Text("Bundle ID:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(app.bundleIdentifier)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .textSelection(.enabled)
                            }

                            HStack {
                                Text("Checking:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(app.shouldCheck() ? "Enabled" : "Disabled")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(app.shouldCheck() ? .green : .orange)
                            }
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Active Application Monitoring")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Real-time information about the currently active application")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Session Information

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Started:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(BuildInfo.launchTimestamp)
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Uptime:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(BuildInfo.uptime)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Session Information")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("How long TextWarden has been running")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Resource Monitoring Section

            ResourceMonitoringView()

            // MARK: - Logging Configuration

            LoggingConfigurationView(preferences: preferences)

            // MARK: - Export System Diagnostics

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export a complete diagnostic package including logs, crash reports, system information, and comprehensive performance metrics for troubleshooting")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    Button(action: exportDiagnosticsToFile) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Diagnostics")
                        }
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)

                    if isExporting {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Preparing diagnostic package...")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Sanitizing logs and collecting data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's included in the ZIP package:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Group {
                            Label("diagnostic_overview.json - System info, permissions, settings", systemImage: "doc.text")
                            Label("Performance metrics - Latency (mean, median, P90, P95, P99) by timeframe", systemImage: "chart.xyaxis.line")
                            Label("Usage statistics - Errors, suggestions, categories by timeframe", systemImage: "chart.bar")
                            Label("Complete log files (current + rotated logs)", systemImage: "doc.on.doc")
                            Label("crash_reports/ - Crash logs (if any)", systemImage: "exclamationmark.triangle")
                            Label("Application state (paused/active apps)", systemImage: "app.dashed")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Text("⚠️ Privacy: We take great care to exclude your text from exports, but please review before sharing")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Export System Diagnostics")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Generate comprehensive diagnostic reports for troubleshooting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Debug Overlays

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Enable visual debug overlays to help diagnose positioning issues. When enabled, colored boxes will appear around text fields to show how TextWarden calculates positions for grammar indicators")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    Toggle("Show Text Field Bounds", isOn: $preferences.showDebugBorderTextFieldBounds)
                        .help("Display a red box showing the exact boundaries of the text field being monitored for grammar checking")

                    Text("Red box showing the text field being monitored for grammar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                        .padding(.bottom, 8)

                    Toggle("Show CGWindow Coordinates", isOn: $preferences.showDebugBorderCGWindowCoords)
                        .help("Display a blue box showing the raw CGWindow coordinates from the system")

                    Text("Blue box showing CGWindow coordinates (raw from system)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                        .padding(.bottom, 8)

                    Toggle("Show Cocoa Coordinates", isOn: $preferences.showDebugBorderCocoaCoords)
                        .help("Display a green box showing the Cocoa coordinate system (converted from CGWindow)")

                    Text("Green box showing Cocoa coordinates (converted)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                        .padding(.bottom, 8)

                    Toggle("Show Character Position Markers", isOn: $preferences.showDebugCharacterMarkers)
                        .help("Display markers showing character positions for debugging text positioning")

                    Text("Orange = underline start (Cyan = first char when combined with Text Field Bounds)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("These overlays are useful for troubleshooting position-related issues in specific applications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Debug Overlays")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Visual debugging tools for positioning and coordinate issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Reset Options

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Reset various aspects of TextWarden to their default state. Use these options with caution as they cannot be undone")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    // Arrange buttons in a 2x2 grid for better alignment
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                preferences.resetToDefaults()
                                // Relaunch the app to start fresh with onboarding
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    Self.relaunchApp()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "arrow.counterclockwise.circle.fill")
                                        Text("Reset All Settings")
                                    }
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .help("Reset all preferences and restart onboarding")

                            Button {
                                preferences.customDictionary.removeAll()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "book.closed.fill")
                                        Text("Clear Custom Dictionary")
                                    }
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .help("Remove all words from your custom dictionary")
                        }

                        HStack(spacing: 12) {
                            Button {
                                preferences.ignoredRules.removeAll()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "checklist")
                                        Text("Clear Ignored Rules")
                                    }
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .help("Re-enable all previously ignored grammar rules")

                            Button {
                                preferences.ignoredErrorTexts.removeAll()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "text.badge.xmark")
                                        Text("Clear Ignored Error Texts")
                                    }
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .help("Clear all error texts ignored with 'Ignore Everywhere'")
                        }

                        HStack(spacing: 12) {
                            Button {
                                // Easter egg: double-click shows milestone preview instead of resetting
                                let now = Date()
                                if let lastClick = lastMilestoneResetClick,
                                   now.timeIntervalSince(lastClick) < 0.4
                                {
                                    // Double-click detected - show preview
                                    MenuBarController.shared?.showMilestonePreview()
                                    lastMilestoneResetClick = nil
                                } else {
                                    // Single click - reset milestones
                                    lastMilestoneResetClick = now
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        if lastMilestoneResetClick != nil {
                                            preferences.milestonesDisabled = false
                                            preferences.shownMilestones.removeAll()
                                            lastMilestoneResetClick = nil
                                        }
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "gift")
                                        Text("Reset Milestones")
                                    }
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .help("Re-enable milestone celebration prompts")

                            // Empty spacer to maintain grid alignment
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Reset Options")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Restore settings and data to their default values")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showingExportSuccess) {
            ExportSuccessSheet(
                filePath: exportedFilePath,
                fileSize: exportedFileSize,
                isPresented: $showingExportSuccess
            )
        }
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Failed to export diagnostic package. Please check the logs for details.")
        }
    }

    // MARK: - Export Methods

    private func exportDiagnosticsToFile() {
        isExporting = true

        // Show save panel first
        let savePanel = NSSavePanel()
        savePanel.title = "Export Diagnostics"
        savePanel.message = "Choose a location to save the diagnostic package"
        savePanel.nameFieldStringValue = "TextWarden-Diagnostics-\(formatDateForFilename()).zip"
        savePanel.allowedContentTypes = [.zip]
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                isExporting = false
                return
            }

            // CRITICAL: Collect shortcuts on main thread BEFORE dispatching to background
            // KeyboardShortcuts.Shortcut.description requires main thread access
            let shortcuts = SettingsDump.collectShortcuts()

            // Generate and export ZIP package (heavy I/O runs in background)
            Task { @MainActor in
                let success = await DiagnosticReport.exportAsZIP(
                    to: url,
                    preferences: preferences,
                    shortcuts: shortcuts
                )

                isExporting = false

                if success {
                    exportedFilePath = url.path

                    // Get file size
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let fileSize = attrs[.size] as? Int64
                    {
                        let formatter = ByteCountFormatter()
                        formatter.allowedUnits = [.useMB, .useKB]
                        formatter.countStyle = .file
                        exportedFileSize = formatter.string(fromByteCount: fileSize)
                    } else {
                        exportedFileSize = "Unknown"
                    }

                    showingExportSuccess = true
                    Logger.info("Diagnostic package exported to: \(url.path)", category: Logger.general)
                } else {
                    showingExportError = true
                    Logger.error("Failed to export diagnostic package", category: Logger.general)
                }
            }
        }
    }

    private func formatDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - App Relaunch

    /// Relaunch the app to apply reset settings and show onboarding
    private static func relaunchApp() {
        guard let appURL = Bundle.main.bundleURL as URL? else {
            Logger.error("Failed to get app bundle URL for relaunch", category: Logger.general)
            return
        }

        Logger.info("Relaunching TextWarden after settings reset", category: Logger.general)

        // Launch a new instance of the app
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                Logger.error("Failed to relaunch app: \(error.localizedDescription)", category: Logger.general)
            } else {
                // Terminate current instance after new one starts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            }
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

                    Spacer()

                    Picker("Log Level", selection: $selectedLogLevel) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: selectedLogLevel) { _, newValue in
                        Logger.minimumLogLevel = newValue
                    }
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

// MARK: - Export Success Sheet

struct ExportSuccessSheet: View {
    let filePath: String
    let fileSize: String
    @Binding var isPresented: Bool
    @State private var showCopiedFeedback: Bool = false

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var directoryPath: String {
        (filePath as NSString).deletingLastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with success icon
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Export Successful")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // File info card
            VStack(alignment: .leading, spacing: 12) {
                // File name with icon
                HStack(spacing: 10) {
                    Image(systemName: "doc.zipper")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileName)
                            .font(.body)
                            .fontWeight(.medium)

                        Text(fileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Divider()

                // Path display
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(directoryPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(filePath, forType: .string)
                    showCopiedFeedback = true

                    // Hide feedback after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopiedFeedback = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        Text(showCopiedFeedback ? "Copied!" : "Copy Path")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(showCopiedFeedback ? .green : nil)

                Button {
                    NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Show in Finder")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Done button
            Button {
                isPresented = false
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .frame(width: 420)
        .background(.regularMaterial)
    }
}
