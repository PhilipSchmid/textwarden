//
//  PreferencesView.swift
//  Gnau
//
//  Settings/Preferences window
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView(preferences: preferences)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.fill")
                }
                .tag(1)

            ApplicationSettingsView(preferences: preferences)
                .tabItem {
                    Label("Applications", systemImage: "app.badge")
                }
                .tag(2)

            FilteringPreferencesView(preferences: preferences)
                .tabItem {
                    Label("Categories", systemImage: "line.3.horizontal.decrease.circle")
                }
                .tag(3)

            CustomVocabularyView()
                .tabItem {
                    Label("Dictionary", systemImage: "text.book.closed")
                }
                .tag(4)

            AppearancePreferencesView(preferences: preferences)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(5)

            KeyboardShortcutsView(preferences: preferences)
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(6)

            SystemStatusView()
                .tabItem {
                    Label("System", systemImage: "checkmark.shield")
                }
                .tag(7)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(8)
        }
        .frame(width: 800, height: 650)
        .onAppear {
            // Check if a specific tab was requested (e.g., About from menu)
            let requestedTab = UserDefaults.standard.integer(forKey: "PreferencesSelectedTab")
            if requestedTab > 0 {
                selectedTab = requestedTab
                // Reset to default after reading
                UserDefaults.standard.set(0, forKey: "PreferencesSelectedTab")
            }
        }
    }
}

// MARK: - Statistics View

struct StatisticsView: View {
    @ObservedObject private var statistics = UserStatistics.shared
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    Text("Your Grammar Journey")
                        .font(.system(size: 32, weight: .bold))
                    Text("Track your improvements and writing progress")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                // Core Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    MetricCard(
                        title: "Grammar Issues",
                        value: "\(statistics.errorsFound)",
                        subtitle: "Detected",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )

                    MetricCard(
                        title: "Improvements",
                        value: "\(statistics.suggestionsApplied)",
                        subtitle: "Made",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )

                    MetricCard(
                        title: "Words Checked",
                        value: formatNumber(statistics.wordsAnalyzed),
                        subtitle: "Analyzed",
                        icon: "doc.text.fill",
                        color: .blue
                    )

                    MetricCard(
                        title: "Documents",
                        value: "\(statistics.analysisSessions)",
                        subtitle: "Analyzed",
                        icon: "folder.fill",
                        color: .purple
                    )

                    MetricCard(
                        title: "Active Days",
                        value: "\(statistics.activeDays.count)",
                        subtitle: "Writing",
                        icon: "calendar.badge.clock",
                        color: .pink
                    )

                    MetricCard(
                        title: "Time Saved",
                        value: statistics.timeSavedFormatted,
                        subtitle: "Estimated",
                        icon: "clock.fill",
                        color: .cyan
                    )
                }

                Divider()
                    .padding(.vertical, 8)

                // Improvement Rate
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "percent")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                            .frame(width: 28)
                        Text("Improvement Rate")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    HStack(spacing: 16) {
                        // Progress bar
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(Int(statistics.improvementRate))%")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Text("\(statistics.suggestionsApplied) of \(statistics.suggestionsApplied + statistics.suggestionsDismissed) suggestions applied")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(height: 16)

                                    // Progress
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor)
                                        .frame(
                                            width: geometry.size.width * CGFloat(statistics.improvementRate / 100.0),
                                            height: 16
                                        )
                                }
                            }
                            .frame(height: 16)
                        }
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(12)
                }

                Divider()
                    .padding(.vertical, 8)

                // Category Breakdown
                if !statistics.categoryBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chart.pie.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .frame(width: 28)
                            Text("Error Categories")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(sortedCategories, id: \.0) { category, count in
                                CategoryRow(
                                    category: category,
                                    count: count,
                                    total: statistics.suggestionsApplied,
                                    isTopCategory: category == statistics.mostCommonCategory
                                )
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }

                    Divider()
                        .padding(.vertical, 8)
                }

                // Additional Stats
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                            .frame(width: 28)
                        Text("Insights")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    VStack(spacing: 12) {
                        InsightRow(
                            icon: "lightbulb.fill",
                            title: "Average Errors per Document",
                            value: String(format: "%.1f", statistics.averageErrorsPerSession),
                            color: .yellow
                        )

                        InsightRow(
                            icon: "star.fill",
                            title: "Most Common Issue",
                            value: formatCategoryName(statistics.mostCommonCategory),
                            color: .orange
                        )

                        InsightRow(
                            icon: "book.fill",
                            title: "Personal Dictionary",
                            value: "\(statistics.customDictionarySize) words",
                            color: .indigo
                        )

                        InsightRow(
                            icon: "app.badge",
                            title: "Total Sessions",
                            value: "\(statistics.sessionCount) launches",
                            color: .teal
                        )
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }

                Divider()
                    .padding(.vertical, 8)

                // Reset Button
                HStack {
                    Spacer()
                    Button(action: {
                        showResetConfirmation = true
                    }) {
                        Label("Reset All Statistics", systemImage: "arrow.counterclockwise")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .alert("Reset Statistics?", isPresented: $showResetConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) {
                            statistics.resetAllStatistics()
                        }
                    } message: {
                        Text("This will permanently delete all your statistics. This action cannot be undone.")
                    }
                    Spacer()
                }
            }
            .padding(24)
        }
    }

    private var sortedCategories: [(String, Int)] {
        statistics.categoryBreakdown.sorted { $0.value > $1.value }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000.0)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000.0)
        } else {
            return "\(number)"
        }
    }

    private func formatCategoryName(_ category: String) -> String {
        guard category != "None" else { return category }

        var result = ""
        for (index, char) in category.enumerated() {
            if index > 0 && char.isUppercase {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}

// MARK: - Statistics Supporting Views

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

private struct CategoryRow: View {
    let category: String
    let count: Int
    let total: Int
    let isTopCategory: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Category name
            HStack(spacing: 6) {
                if isTopCategory {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
                Text(formatCategoryName(category))
                    .font(.body)
                    .fontWeight(isTopCategory ? .semibold : .regular)
            }

            Spacer()

            // Count and percentage
            HStack(spacing: 12) {
                Text("\(count)")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 30, alignment: .trailing)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(isTopCategory ? Color.accentColor : Color.accentColor.opacity(0.6))
                            .frame(
                                width: geometry.size.width * CGFloat(Double(count) / Double(total)),
                                height: 8
                            )
                    }
                }
                .frame(width: 100, height: 8)

                Text("\(Int(Double(count) / Double(total) * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 35, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
    }

    private func formatCategoryName(_ category: String) -> String {
        var result = ""
        for (index, char) in category.enumerated() {
            if index > 0 && char.isUppercase {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}

private struct InsightRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)

            Text(title)
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.body)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 4)
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
                                    Text(app.bundleIdentifier)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .onTapGesture(count: 2) {
                                            copyToClipboard(app.bundleIdentifier)
                                        }
                                        .help("Double-click to copy bundle identifier")
                                }

                                Spacer()

                                // Pause duration picker (T069, T073)
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

                            // Show resume time for timed pause
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
        }
        .onChange(of: preferences.disabledApplications) {
            // Reload to reflect changes (T072, T073)
            loadDiscoveredApplications()
        }
        .onChange(of: preferences.appPauseDurations) {
            // Reload to reflect pause duration changes
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

    /// Check if a bundle ID is a system background service that should be filtered out
    private func isSystemBackgroundService(_ bundleID: String) -> Bool {
        // List of system services that users typically don't interact with
        let systemServices = [
            "app.gnau.Gnau",  // Don't check grammar in Gnau's own UI
            "com.apple.loginwindow",
            "com.apple.UserNotificationCenter",
            "com.apple.notificationcenterui",
            "com.apple.accessibility.universalAccessAuthWarn",
            "com.apple.controlcenter",
            "com.apple.systemuiserver",
            "com.apple.QuickLookUIService",
            "com.apple.appkit.xpc.openAndSavePanelService",
            "com.apple.CloudKit.ShareBear",
            "com.apple.bird",
            "com.apple.CommCenter",
            "com.apple.cloudphotosd",
            "com.apple.iCloudHelper",
            "com.apple.InputMethodKit.TextReplacementService",
            "com.apple.Console",
            "com.apple.dock",
            "com.apple.systempreferences"
        ]

        // Check for exact matches (case-insensitive)
        let lowercaseBundleID = bundleID.lowercased()
        for service in systemServices {
            if lowercaseBundleID == service.lowercased() {
                return true
            }
        }

        return false
    }

    /// Load discovered applications (T071)
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

        // 2. Add all discovered applications (apps that have been used), excluding system services
        for bundleID in preferences.discoveredApplications {
            if !isSystemBackgroundService(bundleID) {
                bundleIDs.insert(bundleID)
            }
        }

        // 3. Add currently running applications with GUI, excluding system services
        let workspace = NSWorkspace.shared
        for app in workspace.runningApplications {
            // Only include apps with a bundle ID and that are not background-only or system services
            if let bundleID = app.bundleIdentifier,
               app.activationPolicy == .regular,
               !isSystemBackgroundService(bundleID) {
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

                    Button("Clear Ignored Error Texts") {
                        preferences.ignoredErrorTexts.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .help("Clear all error texts ignored with 'Ignore Everywhere'")
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
    ///           "Formatting::horizontal_ellipsis_must_have_3_dots" -> "Horizontal Ellipsis Must Have 3 Dots"
    private func formatRuleName(_ ruleId: String) -> String {
        // Handle new format with category prefix (e.g., "Formatting::rule_name")
        let components = ruleId.split(separator: ":", maxSplits: 1)
        var nameToFormat = components.count > 1 ? String(components[1]) : ruleId
        // Remove any leading colons (from the "::" separator)
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

// MARK: - Custom Vocabulary View (T102)

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

// MARK: - System Status View

struct SystemStatusView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var applicationTracker = ApplicationTracker.shared
    @State private var showingPermissionDialog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundColor(permissionManager.isPermissionGranted ? .green : .orange)
                        Spacer()
                    }
                    Text("System Status")
                        .font(.system(size: 32, weight: .bold))
                    Text("Monitor accessibility permissions and app status")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                // Permission Status Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: permissionManager.isPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
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
                         "Gnau has the necessary permissions to monitor your text and provide grammar checking." :
                         "Gnau needs Accessibility permissions to monitor your text. Click the button below to grant permission.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    HStack(spacing: 12) {
                        if !permissionManager.isPermissionGranted {
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
                        }

                        Button {
                            permissionManager.openSystemSettings()
                        } label: {
                            HStack {
                                Image(systemName: "gearshape")
                                Text("Open System Settings")
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                // Monitoring Status Card
                if permissionManager.isPermissionGranted {
                    VStack(alignment: .leading, spacing: 16) {
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
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }

                // Permission Info
                VStack(alignment: .leading, spacing: 12) {
                    Text("About Accessibility Permissions")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        SystemInfoRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Text Monitoring",
                            description: "Gnau needs to read text you type to check for grammar errors."
                        )

                        SystemInfoRow(
                            icon: "pencil.and.outline",
                            title: "Text Replacement",
                            description: "Gnau can replace text with suggested corrections when you click them."
                        )

                        SystemInfoRow(
                            icon: "lock.shield",
                            title: "Privacy",
                            description: "All text analysis happens locally on your Mac. Nothing is sent to external servers."
                        )
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Permission Requested", isPresented: $showingPermissionDialog) {
            Button("OK") {
                showingPermissionDialog = false
            }
        } message: {
            Text("Please check System Settings to grant Accessibility permission to Gnau. The app will automatically detect when permission is granted.")
        }
    }
}

private struct SystemInfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
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

// MARK: - About View

struct AboutView: View {
    @State private var appVersion: String = "1.0"
    @State private var buildNumber: String = "1"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App Icon and Title
                Image("GnauLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)

                Text("Gnau")
                    .font(.system(size: 42, weight: .bold))

                Text("Real-time Grammar Checking for macOS")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Divider()
                    .padding(.horizontal, 40)

                // Version Information
                VStack(spacing: 14) {
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
                VStack(alignment: .leading, spacing: 14) {
                    Text("Features")
                        .font(.title3)
                        .fontWeight(.semibold)
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
                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://github.com/philipschmid/gnau")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.forward.square.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .frame(width: 32)
                            Text("View on GitHub")
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://github.com/philipschmid/gnau/blob/main/LICENSE")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.plaintext.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .frame(width: 32)
                            Text("View License")
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://github.com/philipschmid/gnau/issues")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "ladybug.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .frame(width: 32)
                            Text("Report an Issue")
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)

                Spacer()

                VStack(spacing: 6) {
                    Text("Built with Swift, Rust, and Harper")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("© 2025 Philip Schmid. All rights reserved.")
                        .font(.subheadline)
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
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.subheadline)
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

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thickness:")
                        Spacer()
                        Text(String(format: "%.1fpt", preferences.underlineThickness))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $preferences.underlineThickness, in: 1.0...5.0, step: 0.5)

                    Text("Adjust the thickness of error underlines")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Underlines")
                    .font(.headline)
            }

            Section {
                Picker("Position:", selection: $preferences.indicatorPosition) {
                    ForEach(UserPreferences.indicatorPositions, id: \.self) { position in
                        Text(position).tag(position)
                    }
                }
                .help("Choose where the error counter appears in Terminal and other apps")

                Text("Position of the floating error indicator badge")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Error Indicator")
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
