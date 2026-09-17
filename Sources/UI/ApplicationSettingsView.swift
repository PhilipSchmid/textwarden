//
//  ApplicationSettingsView.swift
//  TextWarden
//
//  Per-application settings for grammar checking.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Application Settings

struct ApplicationSettingsView: View {
    @ObservedObject var preferences: UserPreferences
    @State private var searchText = ""
    @State private var supportedApps: [ApplicationInfo] = []
    @State private var otherApps: [ApplicationInfo] = []
    @State private var excludedApps: [ApplicationInfo] = []
    @State private var isOtherSectionExpanded = false
    @State private var isExcludedSectionExpanded = false
    @State private var applicationError: String?

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

            HStack {
                Text("To exclude an app, choose Paused Until Resumed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Pause Another App…", action: chooseApplicationToPause)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Application list
            List {
                // MARK: - Supported Applications Section

                if !filteredSupportedApps.isEmpty {
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
                            Text(filteredSupportedApps.count == 1 ? "1 app" : "\(filteredSupportedApps.count) apps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } footer: {
                        Text("TextWarden has been tested and optimized for these applications.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .headerProminence(.increased)
                }

                // MARK: - Other Applications Section

                if !filteredOtherApps.isEmpty {
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
                                    Text(filteredOtherApps.count == 1 ? "1 app" : "\(filteredOtherApps.count) apps")
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

                if !filteredExcludedApps.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $isExcludedSectionExpanded) {
                            ForEach(filteredExcludedApps, id: \.bundleIdentifier) { app in
                                ApplicationRow(app: app, preferences: preferences)
                            }
                        } label: {
                            Text("Excluded by TextWarden")
                                .font(.headline)
                        }
                    } footer: {
                        Text("System utilities and sensitive apps are never checked. These exclusions cannot be resumed.")
                            .font(.caption)
                    }
                }

                if filteredSupportedApps.isEmpty, filteredOtherApps.isEmpty, filteredExcludedApps.isEmpty {
                    Text("No matching applications. Use Pause Another App… to select one.")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)

            // Info text
            Text("Use an app’s More menu to suggest a default exclusion. This opens a GitHub report for you to review.")
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
        .onChange(of: searchText) {
            if !searchText.isEmpty {
                isOtherSectionExpanded = true
                isExcludedSectionExpanded = true
            }
        }
        .alert("Couldn’t Pause Application", isPresented: Binding(
            get: { applicationError != nil },
            set: { if !$0 { applicationError = nil } }
        )) {
            Button("OK") { applicationError = nil }
        } message: {
            Text(applicationError ?? "")
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

    private var filteredExcludedApps: [ApplicationInfo] {
        excludedApps.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func chooseApplicationToPause() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Pause Application"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else {
                applicationError = "The selected app has no bundle identifier. Choose a macOS application."
                return
            }
            preferences.discoveredApplications.insert(bundleID)
            if !AppRegistry.shared.isIntentionallyDisabled(bundleID) {
                preferences.setPauseDuration(for: bundleID, duration: .indefinite)
            }
            searchText = bundleID
            loadApplications()
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

        // Include installed built-in exclusions, even before their first activation.
        allBundleIDs.formUnion(ApplicationPolicy.defaults.keys)

        // Convert to ApplicationInfo and split by support status
        var supported: [ApplicationInfo] = []
        var other: [ApplicationInfo] = []
        var excluded: [ApplicationInfo] = []

        for bundleID in allBundleIDs {
            if let app = getApplicationInfo(for: bundleID) {
                switch app.policy {
                case .supported:
                    supported.append(app)
                case .safeTrial, .pausedByDefault:
                    other.append(app)
                case .ignored:
                    excluded.append(app)
                }
            }
        }

        // Sort alphabetically
        supportedApps = supported.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        otherApps = other.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        excludedApps = excluded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

                if app.policy == .ignored {
                    Label("Always Excluded", systemImage: "shield.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if needsSafeTrialConsent {
                    if preferences.getPauseDuration(for: app.bundleIdentifier) == .indefinite {
                        Text("Paused Until Resumed")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
                }

                if app.policy != .ignored {
                    Menu {
                        if app.policy == .supported {
                            Toggle("Show Underlines", isOn: Binding(
                                get: { preferences.areUnderlinesEnabled(for: app.bundleIdentifier) },
                                set: { preferences.setUnderlinesEnabled($0, for: app.bundleIdentifier) }
                            ))
                            Divider()
                        }
                        if needsSafeTrialConsent {
                            Button("Pause Until Resumed") {
                                preferences.setPauseDuration(for: app.bundleIdentifier, duration: .indefinite)
                            }
                            Divider()
                        }
                        if let url = app.exclusionReportURL {
                            Link("Suggest Default Exclusion…", destination: url)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24, height: 24)
                    .fixedSize()
                    .help("More options for \(app.name)")
                    .accessibilityLabel("More options for \(app.name)")
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
        if app.policy.requiresSafeTrialConsent, preferences.safeTrialApplications.contains(app.bundleIdentifier) {
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

    var exclusionReportURL: URL? {
        var components = URLComponents(string: "https://github.com/PhilipSchmid/textwarden/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "application_exclusion.yml"),
            URLQueryItem(name: "title", value: "Default exclusion: \(name)"),
            URLQueryItem(name: "app", value: name),
            URLQueryItem(name: "bundle-id", value: bundleIdentifier),
        ]
        return components?.url
    }
}
