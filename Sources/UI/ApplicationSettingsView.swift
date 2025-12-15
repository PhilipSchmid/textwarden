//
//  ApplicationSettingsView.swift
//  TextWarden
//
//  Per-application settings for grammar checking.
//

import SwiftUI
import AppKit

// MARK: - Application Settings

struct ApplicationSettingsView: View {
    @ObservedObject var preferences: UserPreferences
    @State private var searchText = ""
    @State private var discoveredApps: [ApplicationInfo] = []
    @State private var hiddenApps: [ApplicationInfo] = []
    @State private var isHiddenSectionExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search applications...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding()

            // Application list
            List {
                Section {
                    ForEach(filteredApps, id: \.bundleIdentifier) { app in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // App icon (if available)
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                } else {
                                    Image(systemName: "app")
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.body)
                                    HStack(spacing: 4) {
                                        Text(app.bundleIdentifier)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Button {
                                            copyToClipboard(app.bundleIdentifier)
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy bundle identifier")
                                    }
                                }

                                Spacer()

                                // Pause duration picker
                                Picker("", selection: Binding(
                                    get: {
                                        preferences.getPauseDuration(for: app.bundleIdentifier)
                                    },
                                    set: { duration in
                                        preferences.setPauseDuration(for: app.bundleIdentifier, duration: duration)
                                    }
                                )) {
                                    Text("Active").tag(PauseDuration.active)
                                    Text("Paused for 1 Hour").tag(PauseDuration.oneHour)
                                    Text("Paused for 24 Hours").tag(PauseDuration.twentyFourHours)
                                    Text("Paused Until Resumed").tag(PauseDuration.indefinite)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 200)
                                .help("Set pause duration for \(app.name)")

                                // Underline toggle button
                                Button {
                                    let currentlyEnabled = preferences.areUnderlinesEnabled(for: app.bundleIdentifier)
                                    preferences.setUnderlinesEnabled(!currentlyEnabled, for: app.bundleIdentifier)
                                } label: {
                                    Image(systemName: preferences.areUnderlinesEnabled(for: app.bundleIdentifier) ? "underline" : "underline")
                                        .foregroundColor(preferences.areUnderlinesEnabled(for: app.bundleIdentifier) ? .accentColor : .secondary)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(preferences.areUnderlinesEnabled(for: app.bundleIdentifier) ? "Disable underlines for \(app.name)" : "Enable underlines for \(app.name)")

                                // Hide button
                                Button {
                                    hideApplication(app.bundleIdentifier)
                                } label: {
                                    Image(systemName: "eye.slash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Hide this app from the list")
                            }

                            if let until = preferences.getPausedUntil(for: app.bundleIdentifier) {
                                let pauseState = preferences.getPauseDuration(for: app.bundleIdentifier)
                                if pauseState == .oneHour || pauseState == .twentyFourHours {
                                    HStack {
                                        Spacer()
                                        Text("Will resume at \(formatTime(until))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.trailing, 4)
                                    }
                                }
                            }

                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    HStack {
                        Text("Discovered Applications")
                            .font(.headline)
                        Spacer()
                        Text("\(discoveredApps.count) apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .headerProminence(.increased)

                // Hidden Applications Section
                Section {
                    DisclosureGroup(
                        isExpanded: $isHiddenSectionExpanded,
                        content: {
                            ForEach(hiddenApps, id: \.bundleIdentifier) { app in
                                HStack {
                                    // App icon
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                    } else {
                                        Image(systemName: "app")
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, height: 24)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name)
                                            .font(.body)
                                        HStack(spacing: 4) {
                                            Text(app.bundleIdentifier)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Button {
                                                copyToClipboard(app.bundleIdentifier)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Copy bundle identifier")
                                        }
                                    }

                                    Spacer()

                                    // Show button
                                    Button {
                                        showApplication(app.bundleIdentifier)
                                    } label: {
                                        Label("Show", systemImage: "eye")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Show this app in Discovered Applications")
                                }
                                .padding(.vertical, 4)
                            }
                        },
                        label: {
                            HStack {
                                Text("Hidden Applications")
                                    .font(.headline)
                                Spacer()
                                Text("\(hiddenApps.count) apps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                }
                .headerProminence(.increased)
            }
            .listStyle(.inset)

            // Info text
            Text("Applications are automatically discovered when you activate them. This list includes common apps, running apps, and apps you've used. Set pause duration to control grammar checking per application: Active (enabled), Paused for 1 Hour (temporarily disabled), or Paused Until Resumed (disabled until you re-enable it).")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .onAppear {
            loadDiscoveredApplications()
            loadHiddenApplications()
        }
        .onChange(of: preferences.disabledApplications) {
            // Reload to reflect changes
            loadDiscoveredApplications()
        }
        .onChange(of: preferences.appPauseDurations) {
            // Reload to reflect pause duration changes
            loadDiscoveredApplications()
        }
        .onChange(of: preferences.hiddenApplications) {
            // Reload when hidden apps change
            loadHiddenApplications()
        }
    }

    /// Get filtered applications based on search text
    private var filteredApps: [ApplicationInfo] {
        if searchText.isEmpty {
            return discoveredApps
        }
        return discoveredApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Check if a bundle ID should be excluded from the discovered applications list
    /// Checks against the user's hidden applications list
    private func shouldExcludeFromApplicationList(_ bundleID: String) -> Bool {
        return preferences.hiddenApplications.contains(bundleID)
    }

    /// Load discovered applications
    private func loadDiscoveredApplications() {
        var bundleIDs = Set<String>()

        // 1. Add common applications (excluding hidden ones)
        let commonBundleIDs = [
            "com.apple.TextEdit",
            "com.microsoft.VSCode",
            "com.microsoft.Word",
            "com.apple.Pages",
            "com.apple.Notes",
            "com.apple.Safari",
            "com.google.Chrome",
            "com.brave.Browser",
            "org.mozilla.firefox",
            "com.apple.mail",
            "com.tinyspeck.slackmacgap",
            "notion.id",
            "md.obsidian",
            "com.literatureandlatte.scrivener3"
        ]
        for bundleID in commonBundleIDs {
            if !shouldExcludeFromApplicationList(bundleID) {
                bundleIDs.insert(bundleID)
            }
        }

        // 2. Add all discovered applications (apps that have been used), excluding system apps
        for bundleID in preferences.discoveredApplications {
            if !shouldExcludeFromApplicationList(bundleID) {
                bundleIDs.insert(bundleID)
            }
        }

        // 3. Add currently running applications with GUI, excluding system apps
        let workspace = NSWorkspace.shared
        for app in workspace.runningApplications {
            // Only include apps with a bundle ID and that are not background-only or excluded apps
            if let bundleID = app.bundleIdentifier,
               app.activationPolicy == .regular,
               !shouldExcludeFromApplicationList(bundleID) {
                bundleIDs.insert(bundleID)
            }
        }

        // 4. Add apps from disabled list (in case they're not running but disabled)
        bundleIDs.formUnion(preferences.disabledApplications)

        // Convert bundle IDs to ApplicationInfo
        var apps: [ApplicationInfo] = []
        for bundleID in bundleIDs {
            if let app = getApplicationInfo(for: bundleID) {
                apps.append(app)
            }
        }

        // Sort alphabetically
        discoveredApps = apps.sorted { $0.name < $1.name }
    }

    /// Get application info from bundle ID
    private func getApplicationInfo(for bundleID: String) -> ApplicationInfo? {
        // Try to find app path
        let workspace = NSWorkspace.shared
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            // App not installed, but show in list if disabled
            if preferences.disabledApplications.contains(bundleID) {
                return ApplicationInfo(
                    name: bundleID.components(separatedBy: ".").last ?? bundleID,
                    bundleIdentifier: bundleID,
                    icon: nil
                )
            }
            return nil
        }

        let appName = FileManager.default.displayName(atPath: appURL.path)

        let icon = workspace.icon(forFile: appURL.path)

        return ApplicationInfo(
            name: appName,
            bundleIdentifier: bundleID,
            icon: icon
        )
    }

    /// Load hidden applications
    private func loadHiddenApplications() {
        var apps: [ApplicationInfo] = []

        for bundleID in preferences.hiddenApplications {
            if let appInfo = getApplicationInfo(for: bundleID) {
                apps.append(appInfo)
            }
        }

        // Sort alphabetically
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        hiddenApps = apps
    }

    /// Move app from discovered to hidden
    private func hideApplication(_ bundleID: String) {
        preferences.hiddenApplications.insert(bundleID)
        preferences.discoveredApplications.remove(bundleID)
        loadDiscoveredApplications()
        loadHiddenApplications()
    }

    /// Move app from hidden to discovered
    private func showApplication(_ bundleID: String) {
        preferences.hiddenApplications.remove(bundleID)
        preferences.discoveredApplications.insert(bundleID)
        loadDiscoveredApplications()
        loadHiddenApplications()
    }

    /// Format time for display
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Copy text to clipboard
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Application info for display in preferences
private struct ApplicationInfo {
    let name: String
    let bundleIdentifier: String
    let icon: NSImage?
}
