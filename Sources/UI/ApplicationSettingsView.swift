//
//  ApplicationSettingsView.swift
//  TextWarden
//
//  Per-application settings for grammar checking.
//

import AppKit
import SwiftUI

// MARK: - Application Settings

struct ApplicationSettingsView: View {
    @ObservedObject var preferences: UserPreferences
    @State private var searchText = ""
    @State private var supportedApps: [ApplicationInfo] = []
    @State private var otherApps: [ApplicationInfo] = []
    @State private var isOtherSectionExpanded = false

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
                // MARK: - Supported Applications Section

                Section {
                    ForEach(filteredSupportedApps, id: \.bundleIdentifier) { app in
                        ApplicationRow(
                            app: app,
                            preferences: preferences
                        )
                    }
                } header: {
                    HStack {
                        Text("Supported Applications")
                            .font(.headline)
                        Spacer()
                        Text("\(supportedApps.count) apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("TextWarden has been tested and optimized for these applications.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .headerProminence(.increased)

                // MARK: - Other Applications Section

                if !otherApps.isEmpty || !searchText.isEmpty {
                    Section {
                        DisclosureGroup(
                            isExpanded: $isOtherSectionExpanded,
                            content: {
                                // Request support hint at the top
                                if !otherApps.isEmpty {
                                    HStack(spacing: 12) {
                                        Image(systemName: "sparkles")
                                            .font(.title2)
                                            .foregroundColor(.accentColor)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Want better support for an app?")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text("Let us know which apps you'd like TextWarden to fully support.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Link(destination: URL(string: "https://github.com/philipschmid/textwarden/discussions/new?category=ideas&title=App%20Support%20Request")!) {
                                            Text("Request")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                    .padding(.bottom, 4)
                                }
                                ForEach(filteredOtherApps, id: \.bundleIdentifier) { app in
                                    ApplicationRow(
                                        app: app,
                                        preferences: preferences
                                    )
                                }
                            },
                            label: {
                                HStack {
                                    Text("Other Applications")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(otherApps.count) apps")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        )

                        if !isOtherSectionExpanded {
                            Text("Apps without dedicated support require your approval and start in safe mode.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .headerProminence(.increased)
                }
            }
            .listStyle(.inset)

            // Info text
            Text("Supported apps use their verified capabilities. Other apps start with copy-only fixes after you approve them.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .onAppear {
            loadApplications()
        }
        .onChange(of: preferences.appPauseDurations) {
            loadApplications()
        }
        .onChange(of: preferences.discoveredApplications) {
            loadApplications()
        }
    }

    // MARK: - Filtered Apps

    /// Get filtered supported applications based on search text
    private var filteredSupportedApps: [ApplicationInfo] {
        if searchText.isEmpty {
            return supportedApps
        }
        return supportedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
                app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Get filtered other applications based on search text
    private var filteredOtherApps: [ApplicationInfo] {
        if searchText.isEmpty {
            return otherApps
        }
        return otherApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
                app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Load Applications

    /// Load all applications and split into supported/other
    private func loadApplications() {
        var allBundleIDs = Set<String>()

        // 1. Add all registered/supported apps from AppRegistry
        for config in AppRegistry.shared.allConfigurations {
            for bundleID in config.bundleIDs {
                allBundleIDs.insert(bundleID)
            }
        }

        // 2. Add discovered applications (apps that have been used)
        for bundleID in preferences.discoveredApplications {
            allBundleIDs.insert(bundleID)
        }

        // 3. Add currently running applications with GUI
        let workspace = NSWorkspace.shared
        for app in workspace.runningApplications {
            if let bundleID = app.bundleIdentifier,
               app.activationPolicy == .regular
            {
                allBundleIDs.insert(bundleID)
            }
        }

        // 4. Add apps from pause durations (in case they have custom settings)
        for bundleID in preferences.appPauseDurations.keys {
            allBundleIDs.insert(bundleID)
        }

        // 5. Include installed apps with a registry-owned paused-by-default policy.
        allBundleIDs.formUnion(AppRegistry.shared.defaultPausedBundleIDs)

        // Convert to ApplicationInfo and split by support status
        var supported: [ApplicationInfo] = []
        var other: [ApplicationInfo] = []

        for bundleID in allBundleIDs {
            if let app = getApplicationInfo(for: bundleID) {
                switch app.policy {
                case .supported:
                    supported.append(app)
                case .safeTrial, .pausedByDefault:
                    other.append(app)
                case .ignored:
                    break
                }
            }
        }

        // Sort alphabetically
        supportedApps = supported.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        otherApps = other.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Get application info from bundle ID
    private func getApplicationInfo(for bundleID: String) -> ApplicationInfo? {
        let workspace = NSWorkspace.shared
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            // App not installed - skip it
            return nil
        }

        let appName = FileManager.default.displayName(atPath: appURL.path)
        let icon = workspace.icon(forFile: appURL.path)

        return ApplicationInfo(
            name: appName,
            bundleIdentifier: bundleID,
            icon: icon,
            policy: AppRegistry.shared.policy(for: bundleID)
        )
    }
}

// MARK: - Application Row

private struct ApplicationRow: View {
    let app: ApplicationInfo
    @ObservedObject var preferences: UserPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

                    if let statusDescription {
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if needsSafeTrialConsent {
                    Button("Try Safely") {
                        preferences.allowSafeTrial(for: app.bundleIdentifier)
                        preferences.setPauseDuration(for: app.bundleIdentifier, duration: .active)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Allow indicator and copy-only fixes in \(app.name)")
                } else {
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

                    if app.policy == .supported {
                        Button {
                            let currentlyEnabled = preferences.areUnderlinesEnabled(for: app.bundleIdentifier)
                            preferences.setUnderlinesEnabled(!currentlyEnabled, for: app.bundleIdentifier)
                        } label: {
                            Image(systemName: "underline")
                                .foregroundColor(preferences.areUnderlinesEnabled(for: app.bundleIdentifier) ? .accentColor : .secondary)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(preferences.areUnderlinesEnabled(for: app.bundleIdentifier) ? "Disable underlines for \(app.name)" : "Enable underlines for \(app.name)")
                    }
                }
            }

            // Resume time if paused
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

    private var needsSafeTrialConsent: Bool {
        app.policy.requiresSafeTrialConsent
            && !preferences.safeTrialApplications.contains(app.bundleIdentifier)
    }

    private var statusDescription: String? {
        if preferences.safeTrialApplications.contains(app.bundleIdentifier) {
            return "Safe trial · indicator and copy-only fixes"
        }
        if needsSafeTrialConsent,
           app.policy == .pausedByDefault,
           preferences.getPauseDuration(for: app.bundleIdentifier) != .active
        {
            return "Paused by default"
        }
        if needsSafeTrialConsent {
            return "Approval required before checking text"
        }
        return nil
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Application Info

private struct ApplicationInfo {
    let name: String
    let bundleIdentifier: String
    let icon: NSImage?
    let policy: ApplicationPolicy
}
