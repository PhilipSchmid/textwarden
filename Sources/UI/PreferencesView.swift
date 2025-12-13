//
//  PreferencesView.swift
//  TextWarden
//
//  Settings/Preferences window
//

import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts
import UniformTypeIdentifiers
import Charts
import AppKit

// MARK: - Native macOS Text Field (left-aligned)

/// A native macOS text field wrapper for SwiftUI with left-aligned text
struct LeftAlignedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.alignment = .left
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
        }
    }
}

// MARK: - Native macOS Search Field

/// A native macOS search field wrapper for SwiftUI
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search..."

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .exterior
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            if let searchField = obj.object as? NSSearchField {
                text = searchField.stringValue
            }
        }
    }
}

struct PreferencesView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var windowController = PreferencesWindowController.shared

    var body: some View {
        TabView(selection: $windowController.selectedTab) {
            GeneralPreferencesView(preferences: preferences)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general.rawValue)
                .accessibilityLabel("General settings tab")

            SpellCheckingView()
                .tabItem {
                    Label("Grammar", systemImage: "text.badge.checkmark")
                }
                .tag(SettingsTab.grammar.rawValue)
                .accessibilityLabel("Grammar checking settings tab")

            StyleCheckingSettingsView()
                .tabItem {
                    Label("Style", systemImage: "sparkles")
                }
                .tag(SettingsTab.style.rawValue)
                .accessibilityLabel("Style checking settings tab")

            ApplicationSettingsView(preferences: preferences)
                .tabItem {
                    Label("Applications", systemImage: "app.badge")
                }
                .tag(SettingsTab.applications.rawValue)
                .accessibilityLabel("Application settings tab")

            WebsiteSettingsView(preferences: preferences)
                .tabItem {
                    Label("Websites", systemImage: "globe")
                }
                .tag(SettingsTab.websites.rawValue)
                .accessibilityLabel("Website settings tab")

            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.fill")
                }
                .tag(SettingsTab.statistics.rawValue)
                .accessibilityLabel("Usage statistics tab")

            DiagnosticsView(preferences: preferences)
                .tabItem {
                    Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                }
                .tag(SettingsTab.diagnostics.rawValue)
                .accessibilityLabel("Diagnostics and troubleshooting tab")

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about.rawValue)
                .accessibilityLabel("About TextWarden tab")
        }
        .frame(minWidth: 750, minHeight: 600)
        // Theme is managed via NSApp.appearance in PreferencesWindowController
        // This provides seamless theme switching without view recreation or scroll position reset
    }
}

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

        // 1. Add common applications (always show these)
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
            "com.literatureandlatte.scrivener3",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable"
        ]
        bundleIDs.formUnion(commonBundleIDs)

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
fileprivate struct ApplicationInfo {
    let name: String
    let bundleIdentifier: String
    let icon: NSImage?
}

// MARK: - Website Settings

struct WebsiteSettingsView: View {
    @ObservedObject var preferences: UserPreferences
    @State private var searchText = ""
    @State private var newWebsite = ""
    @State private var showingAddSheet = false

    /// Filtered websites based on search text
    private var filteredWebsites: [String] {
        let sorted = Array(preferences.disabledWebsites).sorted()
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field and add button row
            HStack {
                // Search field (matching Applications style)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search websites...", text: $searchText)
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

                // Current website button (if in browser)
                if let currentDomain = AnalysisCoordinator.shared.getCurrentBrowserDomain() {
                    if !preferences.isWebsiteDisabled(currentDomain) {
                        Button {
                            preferences.disableWebsite(currentDomain)
                        } label: {
                            Label("Disable \(currentDomain)", systemImage: "minus.circle")
                        }
                        .buttonStyle(.bordered)
                        .help("Disable grammar checking on the current website")
                    }
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Add a website to disable")
            }
            .padding()

            // Website list
            List {
                Section {
                    if filteredWebsites.isEmpty && !preferences.disabledWebsites.isEmpty {
                        // Search returned no results
                        HStack {
                            Spacer()
                            Text("No matching websites")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else if preferences.disabledWebsites.isEmpty {
                        // No websites added yet
                        VStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No disabled websites")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Add websites to disable grammar checking on specific sites")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(filteredWebsites, id: \.self) { website in
                            HStack {
                                // Website icon
                                Image(systemName: website.hasPrefix("*.") ? "globe.badge.chevron.backward" : "globe")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(website)
                                        .font(.body)
                                    if website.hasPrefix("*.") {
                                        Text("Includes all subdomains")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                // Status indicator
                                Text("Disabled")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(4)

                                // Remove button
                                Button {
                                    preferences.enableWebsite(website)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Enable grammar checking on this website")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack {
                        Text("Disabled Websites")
                            .font(.headline)
                        Spacer()
                        Text("\(preferences.disabledWebsites.count) \(preferences.disabledWebsites.count == 1 ? "website" : "websites")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .headerProminence(.increased)
            }
            .listStyle(.inset)

            // Info text (matching Applications style)
            Text("Disable grammar checking on specific websites. Enter exact domains like \"github.com\" or use wildcards like \"*.google.com\" to include all subdomains. When browsing, use the button above to quickly disable the current site.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWebsiteSheet(
                newWebsite: $newWebsite,
                isPresented: $showingAddSheet,
                onAdd: { website in
                    preferences.disableWebsite(website)
                    newWebsite = ""
                }
            )
        }
    }
}

/// Sheet for adding a new website to the disabled list
fileprivate struct AddWebsiteSheet: View {
    @Binding var newWebsite: String
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                Text("Add Website")
                    .font(.headline)
                Text("Disable grammar checking on a specific website")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Input field
            VStack(alignment: .leading, spacing: 6) {
                Text("Domain")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., github.com or *.google.com", text: $newWebsite)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                Text("Use * as wildcard for subdomains (e.g., *.example.com)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    newWebsite = ""
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Website") {
                    let trimmed = newWebsite.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onAdd(trimmed)
                    }
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

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
private struct AnalysisDelayTextField: View {
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

// MARK: - Spell Checking (combines Categories and Dictionary)

struct SpellCheckingView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var vocabulary = CustomVocabulary.shared
    @State private var newWord = ""
    @State private var searchText = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // MARK: Grammar Categories Group
            FilteringPreferencesContent(preferences: preferences)

            // MARK: Harper Settings Group
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        Text("Analysis delay:")

                        Spacer()

                        AnalysisDelayTextField(preferences: preferences)

                        Text("ms")
                            .foregroundColor(.secondary)
                    }

                    Text("Delay before analyzing text after you stop typing")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if preferences.analysisDelayMs < 10 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Value too low - recommended minimum is 10ms")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    } else if preferences.analysisDelayMs > 500 {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("High values may feel less responsive")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    } else {
                        Text("Recommended: 10-100ms for responsiveness, 200-500ms to reduce CPU usage")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.2.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Harper Settings")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Configure the Harper grammar engine performance and language options")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Performance")
                        .font(.headline)
                        .padding(.top, 8)
                }
            }

            Section {
                Picker("English dialect:", selection: $preferences.selectedDialect) {
                    ForEach(UserPreferences.availableDialects, id: \.self) { dialect in
                        Text(dialect).tag(dialect)
                    }
                }
                .help("Select the English dialect for grammar checking")

                Text("Choose your preferred English variant for spelling and grammar rules")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Language")
                    .font(.headline)
            }

            // MARK: Custom Dictionary Group
            CustomVocabularyContent(
                vocabulary: vocabulary,
                preferences: preferences,
                newWord: $newWord,
                searchText: $searchText,
                errorMessage: $errorMessage
            )
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Filtering Preferences Content (extracted from FilteringPreferencesView)

private struct FilteringPreferencesContent: View {
    @ObservedObject var preferences: UserPreferences

    /// Helper to create toggle binding for a category
    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledCategories.contains(category) },
            set: { enabled in
                var categories = preferences.enabledCategories
                if enabled {
                    categories.insert(category)
                } else {
                    categories.remove(category)
                }
                preferences.enabledCategories = categories
            }
        )
    }

    var body: some View {
        Group {
            // Quick Actions
            Section {
                HStack {
                    Button("Enable All") {
                        preferences.enabledCategories = UserPreferences.allCategories
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Disable All") {
                        preferences.enabledCategories = []
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Grammar Categories")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Enable or disable specific types of grammar and style checks")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Quick Actions")
                        .font(.headline)
                        .padding(.top, 8)
                }
            }

            // Core Grammar Checks
            Section {
                Toggle("Spelling", isOn: categoryBinding("Spelling"))
                    .help("When your brain doesn't know the right spelling")

                Toggle("Typos", isOn: categoryBinding("Typo"))
                    .help("When your brain knows the right spelling but your fingers made a mistake")

                Toggle("Grammar", isOn: categoryBinding("Grammar"))
                    .help("Detect grammatical errors and incorrect sentence structure")

                Toggle("Agreement", isOn: categoryBinding("Agreement"))
                    .help("Check subject-verb and pronoun agreement (e.g., 'he go' → 'he goes')")

                Toggle("Punctuation", isOn: categoryBinding("Punctuation"))
                    .help("Check punctuation usage, including hyphenation in compound adjectives")

                Toggle("Capitalization", isOn: categoryBinding("Capitalization"))
                    .help("Check proper capitalization of words and sentences")
            } header: {
                Text("Core Checks")
                    .font(.headline)
            }

            // Writing Style
            Section {
                Toggle("Style", isOn: categoryBinding("Style"))
                    .help("Check cases where multiple options are correct but one is preferred")

                Toggle("Readability", isOn: categoryBinding("Readability"))
                    .help("Improve text flow and make writing easier to understand")

                Toggle("Enhancement", isOn: categoryBinding("Enhancement"))
                    .help("Suggest improvements that enhance clarity or impact without fixing errors")

                Toggle("Redundancy", isOn: categoryBinding("Redundancy"))
                    .help("Detect cases where words duplicate meaning that's already expressed")

                Toggle("Repetition", isOn: categoryBinding("Repetition"))
                    .help("Detect repeated words or phrases in nearby sentences")
            } header: {
                Text("Style & Clarity")
                    .font(.headline)
            }

            // Word Usage
            Section {
                Toggle("Word Choice", isOn: categoryBinding("WordChoice"))
                    .help("Suggest choosing between different words or phrases in a given context")

                Toggle("Usage", isOn: categoryBinding("Usage"))
                    .help("Check conventional word usage and standard collocations")

                Toggle("Eggcorns", isOn: categoryBinding("Eggcorn"))
                    .help("Detect cases where a word or phrase is misused for a similar-sounding word or phrase (e.g., 'for all intensive purposes' → 'for all intents and purposes')")

                Toggle("Malapropisms", isOn: categoryBinding("Malapropism"))
                    .help("Detect cases where a word is mistakenly used for a similar-sounding word with a different meaning (e.g., 'escape goat' → 'scapegoat')")
            } header: {
                Text("Word Usage")
                    .font(.headline)
            }

            // Advanced
            Section {
                Toggle("Formatting", isOn: categoryBinding("Formatting"))
                    .help("Check text formatting issues such as spacing and special characters")

                Toggle("Boundary Errors", isOn: categoryBinding("BoundaryError"))
                    .help("Detect errors where words are joined or split at the wrong boundaries (e.g., 'each and everyone' → 'each and every one')")

                Toggle("Regionalism", isOn: categoryBinding("Regionalism"))
                    .help("Detect variations that are standard in some regions or dialects but not others")

                Toggle("Nonstandard", isOn: categoryBinding("Nonstandard"))
                    .help("Detect non-standard language usage that may be informal or colloquial")

                Toggle("Miscellaneous", isOn: categoryBinding("Miscellaneous"))
                    .help("Check for any other grammar issues that don't fit neatly into other categories")
            } header: {
                Text("Advanced")
                    .font(.headline)
            }

            // TextWarden Enhancements
            Section {
                Toggle("Sentence-Start Capitalization", isOn: $preferences.enableSentenceStartCapitalization)
                    .help("Automatically capitalize suggestions at the beginning of sentences")
            } header: {
                Text("TextWarden Enhancements")
                    .font(.headline)
            }

            Section {
                if preferences.ignoredRules.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("No ignored rules")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(Array(preferences.ignoredRules).sorted(), id: \.self) { ruleId in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatRuleName(ruleId))
                                    .font(.subheadline)
                                Text(ruleId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Re-enable") {
                                preferences.enableRule(ruleId)
                            }
                            .buttonStyle(.borderless)
                            .help("Allow this rule to show grammar suggestions again")
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Clear All") {
                            preferences.ignoredRules = []
                        }
                        .buttonStyle(.bordered)
                        .help("Re-enable all ignored grammar rules")
                    }
                }
            } header: {
                HStack {
                    Text("Ignored Rules")
                        .font(.headline)
                    Spacer()
                    if !preferences.ignoredRules.isEmpty {
                        Text("\(preferences.ignoredRules.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func formatRuleName(_ ruleId: String) -> String {
        let components = ruleId.split(separator: ":", maxSplits: 1)
        var nameToFormat = components.count > 1 ? String(components[1]) : ruleId
        nameToFormat = nameToFormat.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        let words = nameToFormat.split(separator: "_")
        if !words.isEmpty {
            return words.map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }.joined(separator: " ")
        }

        var result = ""
        for (index, char) in nameToFormat.enumerated() {
            if index > 0 && char.isUppercase {
                result += " "
            }
            result.append(char)
        }
        return result.isEmpty ? ruleId : result
    }
}

// MARK: - Custom Vocabulary Content (extracted from CustomVocabularyView)

private struct CustomVocabularyContent: View {
    @ObservedObject var vocabulary: CustomVocabulary
    @ObservedObject var preferences: UserPreferences
    @Binding var newWord: String
    @Binding var searchText: String
    @Binding var errorMessage: String?
    @State private var ignoredSearchText: String = ""
    @State private var showClearDictionaryAlert: Bool = false
    @State private var showClearIgnoredAlert: Bool = false

    private var filteredWords: [String] {
        let allWords = Array(vocabulary.words).sorted()
        if searchText.isEmpty {
            return allWords
        }
        return allWords.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredIgnoredTexts: [String] {
        let allTexts = Array(preferences.ignoredErrorTexts).sorted()
        if ignoredSearchText.isEmpty {
            return allTexts
        }
        return allTexts.filter { $0.localizedCaseInsensitiveContains(ignoredSearchText) }
    }

    @ViewBuilder
    var body: some View {
        Group {
            // MARK: - Predefined Wordlists Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Internet Abbreviations", isOn: $preferences.enableInternetAbbreviations)
                        .help("Accept common abbreviations like BTW, FYI, LOL, ASAP, etc.")

                    Text("3,200+ abbreviations (BTW, FYI, LOL, ASAP, AFAICT, etc.) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Gen Z Slang", isOn: $preferences.enableGenZSlang)
                        .help("Accept modern slang words like ghosting, sus, slay, etc.")

                    Text("270+ modern terms (ghosting, sus, slay, vibe, etc.) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("IT & Tech Terminology", isOn: $preferences.enableITTerminology)
                        .help("Accept technical terms like kubernetes, docker, API, JSON, localhost, etc.")

                    Text("10,000+ technical terms (kubernetes, docker, nginx, API, JSON, etc.) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Brand & Company Names", isOn: $preferences.enableBrandNames)
                        .help("Accept brand names like Apple, Microsoft, Google, Amazon, etc.")

                    Text("2,400+ brand/company names (Fortune 500, Forbes 2000, global brands) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Person Names (First Names)", isOn: $preferences.enablePersonNames)
                        .help("Accept common first names like James, Maria, Chen, Fatima, etc.")

                    Text("100,000+ international first names (US SSA + worldwide sources) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Surnames (Last Names)", isOn: $preferences.enableLastNames)
                        .help("Accept common surnames like Smith, Garcia, Johnson, etc.")

                    Text("150,000+ surnames from US Census data • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
            } header: {
                Text("Predefined Wordlists")
                    .font(.headline)
            }

            // MARK: - Language Detection Section
            Section {
                Toggle("Detect non-English words", isOn: $preferences.enableLanguageDetection)
                    .help("Automatically detect and ignore errors in non-English words")

                Text("Skip grammar checking for words detected in selected languages")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if preferences.enableLanguageDetection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Languages to ignore:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        LazyVGrid(columns: [
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading)
                        ], alignment: .leading, spacing: 6) {
                            ForEach(UserPreferences.availableLanguages.filter { $0 != "English" }.sorted(), id: \.self) { language in
                                Toggle(language, isOn: Binding(
                                    get: { preferences.excludedLanguages.contains(language) },
                                    set: { isSelected in
                                        if isSelected {
                                            preferences.excludedLanguages.insert(language)
                                        } else {
                                            preferences.excludedLanguages.remove(language)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                            }
                        }
                        .padding(.leading, 20)

                        if !preferences.excludedLanguages.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption2)
                                Text("Words detected as \(preferences.excludedLanguages.sorted().joined(separator: ", ")) will not be marked as errors")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            } header: {
                Text("Language Detection")
                    .font(.headline)
            }

            // MARK: - Custom Dictionary Section
            Section {
                // Add word input row
                HStack(spacing: 8) {
                    Text("Add new word:")
                        .foregroundColor(.secondary)

                    LeftAlignedTextField(
                        text: $newWord,
                        placeholder: "",
                        onSubmit: { addWord() }
                    )
                    .frame(minHeight: 22, maxHeight: 22)

                    Button("Add") {
                        addWord()
                    }
                    .buttonStyle(.bordered)
                    .disabled(newWord.isEmpty)
                    .help("Add word to dictionary")

                    // Error message inline
                    if let errorMessage = errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Search field (only show when there are words)
                if !vocabulary.words.isEmpty {
                    SearchField(text: $searchText, placeholder: "Search \(vocabulary.words.count) words...")
                        .frame(height: 22)
                }

                // Word list
                if vocabulary.words.isEmpty {
                    Text("No words added yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else if filteredWords.isEmpty && !searchText.isEmpty {
                    Text("No matching words")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else {
                    ForEach(filteredWords, id: \.self) { word in
                        HStack {
                            Text(word)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                removeWord(word)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from dictionary")
                        }
                    }
                }
            } header: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Dictionary")
                            .font(.headline)
                        Text("Words added here won't be flagged as spelling errors")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !vocabulary.words.isEmpty {
                        Button {
                            showClearDictionaryAlert = true
                        } label: {
                            Label("Clear list", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .alert("Clear Custom Dictionary?", isPresented: $showClearDictionaryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAll()
                }
            } message: {
                Text("This will remove all \(vocabulary.words.count) words from your custom dictionary. This action cannot be undone.")
            }

            // MARK: - Ignored Words Section
            Section {
                // Search field (only show when there are ignored words)
                if !preferences.ignoredErrorTexts.isEmpty {
                    SearchField(text: $ignoredSearchText, placeholder: "Search \(preferences.ignoredErrorTexts.count) words...")
                        .frame(height: 22)
                }

                // Word list
                if preferences.ignoredErrorTexts.isEmpty {
                    Text("No ignored words")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else if filteredIgnoredTexts.isEmpty && !ignoredSearchText.isEmpty {
                    Text("No matching words")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else {
                    ForEach(filteredIgnoredTexts, id: \.self) { ignoredText in
                        HStack {
                            Text(ignoredText)
                                .lineLimit(1)
                            Spacer()

                            // Move to dictionary button
                            Button {
                                moveToCustomDictionary(ignoredText)
                            } label: {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Add to Custom Dictionary")

                            // Remove button
                            Button {
                                preferences.ignoredErrorTexts.remove(ignoredText)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Stop ignoring (will be checked again)")
                        }
                    }
                }
            } header: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ignored Words")
                            .font(.headline)
                        Text("Errors you've dismissed. Click + to add to dictionary instead.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !preferences.ignoredErrorTexts.isEmpty {
                        Button {
                            showClearIgnoredAlert = true
                        } label: {
                            Label("Clear list", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .alert("Clear Ignored Words?", isPresented: $showClearIgnoredAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    preferences.ignoredErrorTexts.removeAll()
                }
            } message: {
                Text("This will remove all \(preferences.ignoredErrorTexts.count) ignored words. These errors will be flagged again. This action cannot be undone.")
            }
        }
    }

    private func addWord() {
        guard !newWord.isEmpty else { return }

        do {
            try vocabulary.addWord(newWord)
            newWord = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeWord(_ word: String) {
        do {
            try vocabulary.removeWord(word)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAll() {
        do {
            try vocabulary.clearAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Move an ignored word to the Custom Dictionary
    /// This adds it as a valid word and removes it from ignored list
    private func moveToCustomDictionary(_ text: String) {
        do {
            try vocabulary.addWord(text)
            preferences.ignoredErrorTexts.remove(text)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Category Preferences

struct FilteringPreferencesView: View {
    @ObservedObject var preferences: UserPreferences

    /// Helper to create toggle binding for a category
    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledCategories.contains(category) },
            set: { enabled in
                var categories = preferences.enabledCategories
                if enabled {
                    categories.insert(category)
                } else {
                    categories.remove(category)
                }
                preferences.enabledCategories = categories
            }
        )
    }

    var body: some View {
        Form {
            // Quick Actions
            Section {
                HStack {
                    Button("Enable All") {
                        preferences.enabledCategories = UserPreferences.allCategories
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Disable All") {
                        preferences.enabledCategories = []
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Quick Actions")
                    .font(.headline)
            }

            // Core Grammar Checks
            Section {
                Toggle("Spelling", isOn: categoryBinding("Spelling"))
                    .help("When your brain doesn't know the right spelling")

                Toggle("Typos", isOn: categoryBinding("Typo"))
                    .help("When your brain knows the right spelling but your fingers made a mistake")

                Toggle("Grammar", isOn: categoryBinding("Grammar"))
                    .help("Detect grammatical errors and incorrect sentence structure")

                Toggle("Agreement", isOn: categoryBinding("Agreement"))
                    .help("Check subject-verb and pronoun agreement (e.g., 'he go' → 'he goes')")

                Toggle("Punctuation", isOn: categoryBinding("Punctuation"))
                    .help("Check punctuation usage, including hyphenation in compound adjectives")

                Toggle("Capitalization", isOn: categoryBinding("Capitalization"))
                    .help("Check proper capitalization of words and sentences")
            } header: {
                Text("Core Checks")
                    .font(.headline)
            }

            // Writing Style
            Section {
                Toggle("Style", isOn: categoryBinding("Style"))
                    .help("Check cases where multiple options are correct but one is preferred")

                Toggle("Readability", isOn: categoryBinding("Readability"))
                    .help("Improve text flow and make writing easier to understand")

                Toggle("Enhancement", isOn: categoryBinding("Enhancement"))
                    .help("Suggest improvements that enhance clarity or impact without fixing errors")

                Toggle("Redundancy", isOn: categoryBinding("Redundancy"))
                    .help("Detect cases where words duplicate meaning that's already expressed")

                Toggle("Repetition", isOn: categoryBinding("Repetition"))
                    .help("Detect repeated words or phrases in nearby sentences")
            } header: {
                Text("Style & Clarity")
                    .font(.headline)
            }

            // Word Usage
            Section {
                Toggle("Word Choice", isOn: categoryBinding("WordChoice"))
                    .help("Suggest choosing between different words or phrases in a given context")

                Toggle("Usage", isOn: categoryBinding("Usage"))
                    .help("Check conventional word usage and standard collocations")

                Toggle("Eggcorns", isOn: categoryBinding("Eggcorn"))
                    .help("Detect cases where a word or phrase is misused for a similar-sounding word or phrase (e.g., 'for all intensive purposes' → 'for all intents and purposes')")

                Toggle("Malapropisms", isOn: categoryBinding("Malapropism"))
                    .help("Detect cases where a word is mistakenly used for a similar-sounding word with a different meaning (e.g., 'escape goat' → 'scapegoat')")
            } header: {
                Text("Word Usage")
                    .font(.headline)
            }

            // Advanced
            Section {
                Toggle("Formatting", isOn: categoryBinding("Formatting"))
                    .help("Check text formatting issues such as spacing and special characters")

                Toggle("Boundary Errors", isOn: categoryBinding("BoundaryError"))
                    .help("Detect errors where words are joined or split at the wrong boundaries (e.g., 'each and everyone' → 'each and every one')")

                Toggle("Regionalism", isOn: categoryBinding("Regionalism"))
                    .help("Detect variations that are standard in some regions or dialects but not others")

                Toggle("Nonstandard", isOn: categoryBinding("Nonstandard"))
                    .help("Detect non-standard language usage that may be informal or colloquial")

                Toggle("Miscellaneous", isOn: categoryBinding("Miscellaneous"))
                    .help("Check for any other grammar issues that don't fit neatly into other categories")
            } header: {
                Text("Advanced")
                    .font(.headline)
            }

            // TextWarden Enhancements
            Section {
                Toggle("Sentence-Start Capitalization", isOn: $preferences.enableSentenceStartCapitalization)
                    .help("Automatically capitalize suggestions at the beginning of sentences")
            } header: {
                Text("TextWarden Enhancements")
                    .font(.headline)
            }

            Section {
                if preferences.ignoredRules.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("No ignored rules")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(Array(preferences.ignoredRules).sorted(), id: \.self) { ruleId in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatRuleName(ruleId))
                                    .font(.subheadline)
                                Text(ruleId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Re-enable") {
                                preferences.enableRule(ruleId)
                            }
                            .buttonStyle(.borderless)
                            .help("Allow this rule to show grammar suggestions again")
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Clear All") {
                            preferences.ignoredRules = []
                        }
                        .buttonStyle(.bordered)
                        .help("Re-enable all ignored grammar rules")
                    }
                }
            } header: {
                HStack {
                    Text("Ignored Rules")
                        .font(.headline)
                    Spacer()
                    if !preferences.ignoredRules.isEmpty {
                        Text("\(preferences.ignoredRules.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Format rule ID from PascalCase/camelCase to readable text
    /// Examples: "SubjectVerbDisagreement" -> "Subject Verb Disagreement"
    ///           "Formatting::horizontal_ellipsis_must_have_3_dots" -> "Horizontal Ellipsis Must Have 3 Dots"
    private func formatRuleName(_ ruleId: String) -> String {
        // Handle new format with category prefix (e.g., "Formatting::rule_name")
        let components = ruleId.split(separator: ":", maxSplits: 1)
        var nameToFormat = components.count > 1 ? String(components[1]) : ruleId
        nameToFormat = nameToFormat.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        // Replace underscores with spaces and capitalize each word
        let words = nameToFormat.split(separator: "_")
        if !words.isEmpty {
            return words.map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }.joined(separator: " ")
        }

        // Fallback: Insert spaces before uppercase letters (for PascalCase/camelCase)
        var result = ""
        for (index, char) in nameToFormat.enumerated() {
            if index > 0 && char.isUppercase {
                result += " "
            }
            result.append(char)
        }
        return result.isEmpty ? ruleId : result
    }
}

// MARK: - Custom Vocabulary View

struct CustomVocabularyView: View {
    @ObservedObject private var vocabulary = CustomVocabulary.shared
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var newWord = ""
    @State private var searchText = ""
    @State private var errorMessage: String?

    /// Filtered words based on search text
    private var filteredWords: [String] {
        let allWords = Array(vocabulary.words).sorted()
        if searchText.isEmpty {
            return allWords
        }
        return allWords.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Predefined Wordlists section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Predefined Wordlists")
                            .font(.headline)
                    }

                    Text("Enable recognition of specialized vocabulary and informal language")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                    Divider()

                    // Internet Abbreviations
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Internet Abbreviations", isOn: $preferences.enableInternetAbbreviations)
                            .help("Accept common abbreviations like BTW, FYI, LOL, ASAP, etc.")

                        Text("3,200+ abbreviations (BTW, FYI, LOL, ASAP, AFAICT, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    Divider()

                    // Gen Z Slang
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Gen Z Slang", isOn: $preferences.enableGenZSlang)
                            .help("Accept modern slang words like ghosting, sus, slay, etc.")

                        Text("270+ modern terms (ghosting, sus, slay, vibe, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    Divider()

                    // IT Terminology
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("IT & Tech Terminology", isOn: $preferences.enableITTerminology)
                            .help("Accept technical terms like kubernetes, docker, API, JSON, localhost, etc.")

                        Text("10,000+ technical terms (kubernetes, docker, nginx, API, JSON, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    // Brand Names
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Brand & Company Names", isOn: $preferences.enableBrandNames)
                            .help("Accept brand names like Apple, Microsoft, Google, Amazon, etc.")

                        Text("2,400+ brand/company names (Fortune 500, Forbes 2000, global brands) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    // Person Names
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Person Names (First Names)", isOn: $preferences.enablePersonNames)
                            .help("Accept common first names like James, Maria, Chen, Fatima, etc.")

                        Text("100,000+ international first names (US SSA + worldwide sources) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    // Surnames
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Surnames (Last Names)", isOn: $preferences.enableLastNames)
                            .help("Accept common surnames like Smith, Garcia, Johnson, etc.")

                        Text("150,000+ surnames from US Census data • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding()

            Divider()

            // Language Detection section
            HStack {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Language Detection")
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Detect non-English words", isOn: $preferences.enableLanguageDetection)
                    .help("Automatically detect and ignore errors in non-English words")

                Text("Skip grammar checking for words detected in selected languages")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if preferences.enableLanguageDetection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Languages to ignore:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)

                        // Language selection grid with fixed columns
                        LazyVGrid(columns: [
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading)
                        ], alignment: .leading, spacing: 6) {
                            ForEach(UserPreferences.availableLanguages.filter { $0 != "English" }.sorted(), id: \.self) { language in
                                Toggle(language, isOn: Binding(
                                    get: { preferences.excludedLanguages.contains(language) },
                                    set: { isSelected in
                                        if isSelected {
                                            preferences.excludedLanguages.insert(language)
                                        } else {
                                            preferences.excludedLanguages.remove(language)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                            }
                        }
                        .padding(.leading, 20)

                        if !preferences.excludedLanguages.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption2)
                                Text("Words detected as \(preferences.excludedLanguages.sorted().joined(separator: ", ")) will not be marked as errors")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal)

            Divider()

            // Custom Dictionary header
            HStack {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Custom Dictionary")
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupBox {
                HStack(spacing: 12) {
                    TextField("Add word...", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWord()
                        }

                    Button("Add") {
                        addWord()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newWord.isEmpty)
                    .controlSize(.large)
                }
            }
            .padding()

            // Info section
            HStack {
                Label("\(vocabulary.words.count) of 1,000 words", systemImage: "list.number")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if vocabulary.words.count >= 1000 {
                    Label("Limit reached", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Error message
            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Search field - inline, modern style (only show if there are words)
            if !vocabulary.words.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.body)

                    TextField("Search words", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            // Word list
            if vocabulary.words.isEmpty {
                ContentUnavailableView {
                    Label("No Custom Words", systemImage: "text.book.closed")
                } description: {
                    Text("Add words to ignore during grammar checking")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredWords.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredWords, id: \.self) { word in
                        HStack(spacing: 12) {
                            Text(word)
                                .font(.body)

                            Spacer()

                            Button {
                                removeWord(word)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove \"\(word)\" from dictionary")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            // Clear all button - only show if there are words
            if !vocabulary.words.isEmpty {
                Divider()

                HStack {
                    Spacer()

                    Button(role: .destructive) {
                        clearAll()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
        }
    }

    private func addWord() {
        guard !newWord.isEmpty else { return }

        do {
            try vocabulary.addWord(newWord)
            newWord = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeWord(_ word: String) {
        do {
            try vocabulary.removeWord(word)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAll() {
        do {
            try vocabulary.clearAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

