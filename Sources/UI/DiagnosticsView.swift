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
    @State private var showingExportAlert: Bool = false
    @State private var exportAlertMessage: String = ""

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
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Generating diagnostic report...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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

                    Text("⚠️ Privacy: User text content is NEVER included in exports")
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
                            .help("Reset all preferences to their default values")

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
        .alert("Diagnostic Export", isPresented: $showingExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportAlertMessage)
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
                self.isExporting = false
                return
            }

            // CRITICAL: Collect shortcuts on main thread BEFORE dispatching to background
            // KeyboardShortcuts.Shortcut.description requires main thread access
            let shortcuts = SettingsDump.collectShortcuts()

            // Generate and export ZIP package
            Task { @MainActor in
                let success = DiagnosticReport.exportAsZIP(
                    to: url,
                    preferences: self.preferences,
                    shortcuts: shortcuts
                )

                self.isExporting = false

                if success {
                    self.exportAlertMessage = "Diagnostic package exported successfully to:\n\(url.path)"
                    self.showingExportAlert = true

                    Logger.info("Diagnostic package exported to: \(url.path)", category: Logger.general)
                } else {
                    self.exportAlertMessage = "Failed to export diagnostic package. Please check the logs for details."
                    self.showingExportAlert = true

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
}
