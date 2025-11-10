//
//  PreferencesView.swift
//  Gnau
//
//  Settings/Preferences window
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var preferences = UserPreferences.shared

    var body: some View {
        TabView {
            GeneralPreferencesView(preferences: preferences)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ApplicationSettingsView(preferences: preferences)
                .tabItem {
                    Label("Applications", systemImage: "app.badge")
                }

            FilteringPreferencesView(preferences: preferences)
                .tabItem {
                    Label("Categories", systemImage: "line.3.horizontal.decrease.circle")
                }

            CustomVocabularyView()
                .tabItem {
                    Label("Dictionary", systemImage: "text.book.closed")
                }

            AppearancePreferencesView(preferences: preferences)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            KeyboardShortcutsView(preferences: preferences)
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Application Settings (T066-T075)

struct ApplicationSettingsView: View {
    @ObservedObject var preferences: UserPreferences
    @State private var searchText = ""
    @State private var discoveredApps: [ApplicationInfo] = []

    var body: some View {
        VStack(spacing: 0) {
            // Search field (T074)
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

            // Application list (T067-T069)
            List {
                Section {
                    ForEach(filteredApps, id: \.bundleIdentifier) { app in
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
                                Text(app.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Toggle for enable/disable (T069, T073)
                            Toggle("", isOn: Binding(
                                get: {
                                    !preferences.disabledApplications.contains(app.bundleIdentifier)
                                },
                                set: { enabled in
                                    if enabled {
                                        preferences.disabledApplications.remove(app.bundleIdentifier)
                                    } else {
                                        preferences.disabledApplications.insert(app.bundleIdentifier)
                                    }
                                }
                            ))
                            .help("Enable or disable grammar checking for \(app.name)")
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
            }
            .listStyle(.inset)

            // Info text
            Text("Applications are automatically discovered when you type in them. Toggle to enable or disable grammar checking per application.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .onAppear {
            loadDiscoveredApplications()
        }
        .onChange(of: preferences.disabledApplications) {
            // Reload to reflect changes (T072, T073)
            loadDiscoveredApplications()
        }
    }

    /// Get filtered applications based on search text (T074)
    private var filteredApps: [ApplicationInfo] {
        if searchText.isEmpty {
            return discoveredApps
        }
        return discoveredApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Load discovered applications (T071)
    private func loadDiscoveredApplications() {
        var apps: [ApplicationInfo] = []

        // Add common applications
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
            if let app = getApplicationInfo(for: bundleID) {
                apps.append(app)
            }
        }

        // Add any apps from disabled list that weren't in common list
        for bundleID in preferences.disabledApplications {
            if !apps.contains(where: { $0.bundleIdentifier == bundleID }) {
                if let app = getApplicationInfo(for: bundleID) {
                    apps.append(app)
                }
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

        // Get app name
        let appName = FileManager.default.displayName(atPath: appURL.path)

        // Get app icon
        let icon = workspace.icon(forFile: appURL.path)

        return ApplicationInfo(
            name: appName,
            bundleIdentifier: bundleID,
            icon: icon
        )
    }
}

/// Application info for display in preferences
private struct ApplicationInfo {
    let name: String
    let bundleIdentifier: String
    let icon: NSImage?
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @ObservedObject var preferences: UserPreferences

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Grammar checking:", selection: $preferences.pauseDuration) {
                        ForEach(PauseDuration.allCases, id: \.self) { duration in
                            Text(duration.rawValue).tag(duration)
                        }
                    }
                    .help("Pause grammar checking temporarily or indefinitely")

                    if preferences.pauseDuration == .oneHour, let until = preferences.pausedUntil {
                        Text("Will resume at \(until.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Launch Gnau at login", isOn: $preferences.launchAtLogin)
                    .help("Automatically start Gnau when you log in")
            } header: {
                Text("General")
                    .font(.headline)
            }

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
                Text("Performance")
                    .font(.headline)
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

            Section {
                Toggle("Automatically check for updates", isOn: $preferences.autoCheckForUpdates)
                    .help("Check for app updates automatically")
            } header: {
                Text("Updates")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Reset All Settings") {
                        preferences.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                    .help("Reset all preferences to their default values")

                    Button("Clear Custom Dictionary") {
                        preferences.customDictionary.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .help("Remove all words from your custom dictionary")

                    Button("Clear Ignored Rules") {
                        preferences.ignoredRules.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .help("Re-enable all previously ignored grammar rules")
                }
            } header: {
                Text("Reset Options")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
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
                    .help("Check for misspelled words")

                Toggle("Typos", isOn: categoryBinding("Typo"))
                    .help("Detect typing mistakes (e.g., 'seem' → 'seen')")

                Toggle("Grammar", isOn: categoryBinding("Grammar"))
                    .help("Check grammatical correctness")

                Toggle("Agreement", isOn: categoryBinding("Agreement"))
                    .help("Check subject-verb agreement")

                Toggle("Punctuation", isOn: categoryBinding("Punctuation"))
                    .help("Check punctuation usage")

                Toggle("Capitalization", isOn: categoryBinding("Capitalization"))
                    .help("Check proper capitalization")
            } header: {
                Text("Core Checks")
                    .font(.headline)
            }

            // Writing Style
            Section {
                Toggle("Style", isOn: categoryBinding("Style"))
                    .help("Suggest style improvements")

                Toggle("Readability", isOn: categoryBinding("Readability"))
                    .help("Improve text readability")

                Toggle("Enhancement", isOn: categoryBinding("Enhancement"))
                    .help("Suggest clarity improvements")

                Toggle("Redundancy", isOn: categoryBinding("Redundancy"))
                    .help("Detect redundant phrases")

                Toggle("Repetition", isOn: categoryBinding("Repetition"))
                    .help("Detect repeated words")
            } header: {
                Text("Style & Clarity")
                    .font(.headline)
            }

            // Word Usage
            Section {
                Toggle("Word Choice", isOn: categoryBinding("WordChoice"))
                    .help("Suggest better word choices")

                Toggle("Usage", isOn: categoryBinding("Usage"))
                    .help("Check conventional word usage")

                Toggle("Eggcorns", isOn: categoryBinding("Eggcorn"))
                    .help("Detect word substitutions (e.g., 'egg corn' for 'acorn')")

                Toggle("Malapropisms", isOn: categoryBinding("Malapropism"))
                    .help("Detect similar-sounding wrong words")
            } header: {
                Text("Word Usage")
                    .font(.headline)
            }

            // Advanced
            Section {
                Toggle("Formatting", isOn: categoryBinding("Formatting"))
                    .help("Check text formatting")

                Toggle("Boundary Errors", isOn: categoryBinding("BoundaryError"))
                    .help("Check word boundaries (e.g., 'each and everyone')")

                Toggle("Regionalism", isOn: categoryBinding("Regionalism"))
                    .help("Detect regional variations")

                Toggle("Nonstandard", isOn: categoryBinding("Nonstandard"))
                    .help("Detect non-standard usage")

                Toggle("Miscellaneous", isOn: categoryBinding("Miscellaneous"))
                    .help("Other grammar checks")
            } header: {
                Text("Advanced")
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
    ///           "UnclearReferent" -> "Unclear Referent"
    private func formatRuleName(_ ruleId: String) -> String {
        // Insert spaces before uppercase letters (except the first one)
        var result = ""
        for (index, char) in ruleId.enumerated() {
            if index > 0 && char.isUppercase {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}

// MARK: - Custom Vocabulary View (T102)

struct CustomVocabularyView: View {
    @ObservedObject private var vocabulary = CustomVocabulary.shared
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
            // Add word section - modern macOS style
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
        try? vocabulary.removeWord(word)
        errorMessage = nil
    }

    private func clearAll() {
        try? vocabulary.clearAll()
        errorMessage = nil
    }
}

// MARK: - About View

struct AboutView: View {
    @State private var appVersion: String = "1.0"
    @State private var buildNumber: String = "1"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App Icon and Title
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text("Gnau")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Real-time Grammar Checking for macOS")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Divider()
                    .padding(.horizontal, 40)

                // Version Information
                VStack(spacing: 12) {
                    InfoRow(label: "Version", value: "\(appVersion) (\(buildNumber))")
                    InfoRow(label: "Grammar Engine", value: "Harper 0.61")
                    InfoRow(label: "Supported Dialects", value: "American, British, Canadian, Australian")
                    InfoRow(label: "Minimum macOS", value: "14.0 (Sonoma)")
                    InfoRow(label: "License", value: "Apache 2.0")
                }
                .padding(.horizontal, 40)

                Divider()
                    .padding(.horizontal, 40)

                // Features
                VStack(alignment: .leading, spacing: 12) {
                    Text("Features")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    FeatureRow(icon: "text.badge.checkmark", title: "Real-time Grammar Checking", description: "Instant feedback as you type")
                    FeatureRow(icon: "globe", title: "Multiple English Dialects", description: "Support for 4 English variants")
                    FeatureRow(icon: "slider.horizontal.3", title: "20+ Grammar Categories", description: "Fine-grained control over check types")
                    FeatureRow(icon: "app.badge", title: "Per-Application Control", description: "Enable/disable for specific apps")
                    FeatureRow(icon: "book.closed", title: "Custom Dictionary", description: "Add your own words and terms")
                    FeatureRow(icon: "pause.circle", title: "Smart Pause", description: "Pause for 1 hour or indefinitely")
                }
                .padding(.horizontal, 40)

                Divider()
                    .padding(.horizontal, 40)

                // Links
                VStack(spacing: 8) {
                    Link(destination: URL(string: "https://github.com/philipschmid/gnau")!) {
                        HStack {
                            Image(systemName: "link.circle.fill")
                            Text("View on GitHub")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://github.com/philipschmid/gnau/blob/main/LICENSE")!) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("View License")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://github.com/philipschmid/gnau/issues")!) {
                        HStack {
                            Image(systemName: "exclamationmark.bubble.fill")
                            Text("Report an Issue")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                VStack(spacing: 4) {
                    Text("Built with Swift, Rust, and Harper")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("© 2025 Philip Schmid. All rights reserved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .onAppear {
            loadVersionInfo()
        }
    }

    private func loadVersionInfo() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            appVersion = version
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            buildNumber = build
        }
    }
}

// Helper Views for About Page
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Appearance Preferences

struct AppearancePreferencesView: View {
    @ObservedObject var preferences: UserPreferences

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Opacity:")
                        Spacer()
                        Text(String(format: "%.0f%%", preferences.suggestionOpacity * 100))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $preferences.suggestionOpacity, in: 0.7...1.0, step: 0.05)

                    Text("Adjust the transparency of suggestion popovers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Popover")
                    .font(.headline)
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
                Picker("Theme:", selection: $preferences.suggestionTheme) {
                    ForEach(UserPreferences.suggestionThemes, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .help("Color scheme for suggestion popovers")

                Text("System: Automatically match macOS appearance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Color Scheme")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Keyboard Shortcuts Preferences

struct KeyboardShortcutsView: View {
    @ObservedObject var preferences: UserPreferences

    var body: some View {
        Form {
            Section {
                Toggle("Enable keyboard shortcuts", isOn: $preferences.keyboardShortcutsEnabled)
                    .help("Enable or disable all keyboard shortcuts")
            } header: {
                Text("General")
                    .font(.headline)
            }

            Section {
                HStack {
                    Text("Toggle grammar checking:")
                    Spacer()
                    Text(preferences.toggleShortcut)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Accept suggestion:")
                    Spacer()
                    Text(preferences.acceptSuggestionShortcut)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Dismiss suggestion:")
                    Spacer()
                    Text(preferences.dismissSuggestionShortcut)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text("Note: Keyboard shortcuts are currently display-only. Full customization will be available in a future update.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } header: {
                Text("Shortcuts")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    PreferencesView()
}
