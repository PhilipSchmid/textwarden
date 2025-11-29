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

            SpellCheckingView()
                .tabItem {
                    Label("Grammar", systemImage: "text.badge.checkmark")
                }
                .tag(SettingsTab.grammar.rawValue)

            StyleCheckingSettingsView()
                .tabItem {
                    Label("Style", systemImage: "sparkles")
                }
                .tag(SettingsTab.style.rawValue)

            ApplicationSettingsView(preferences: preferences)
                .tabItem {
                    Label("Applications", systemImage: "app.badge")
                }
                .tag(SettingsTab.applications.rawValue)

            WebsiteSettingsView(preferences: preferences)
                .tabItem {
                    Label("Websites", systemImage: "globe")
                }
                .tag(SettingsTab.websites.rawValue)

            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.fill")
                }
                .tag(SettingsTab.statistics.rawValue)

            DiagnosticsView(preferences: preferences)
                .tabItem {
                    Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                }
                .tag(SettingsTab.diagnostics.rawValue)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about.rawValue)
        }
        .frame(minWidth: 750, minHeight: 600)
    }
}

// MARK: - Statistics View

struct StatisticsView: View {
    @ObservedObject private var statistics = UserStatistics.shared
    @State private var showResetConfirmation = false
    @State private var selectedTimeRange: TimeRange = .week

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with Time Range Picker
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Grammar Journey")
                            .font(.system(size: 28, weight: .bold))
                        Text("Track your improvements and writing progress")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Time Range Picker
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Time Period")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedTimeRange) {
                            ForEach(TimeRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .help(selectedTimeRange == .session ?
                            "Shows statistics since the app was last restarted" :
                            "Shows statistics for the selected time period"
                        )
                    }
                }
                .padding(.bottom, 4)

                // Core Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    MetricCard(
                        title: "Issues Detected",
                        value: formatNumber(statistics.errorsFound(in: selectedTimeRange)),
                        subtitle: "",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                    .help("Total grammar, spelling, and style issues detected in the selected time period. This includes re-analyzed text, so the count may be higher than unique errors.")

                    MetricCard(
                        title: "Improvements Made",
                        value: "\(statistics.suggestionsApplied(in: selectedTimeRange))",
                        subtitle: "",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    .help("Number of suggestions you've accepted and applied in the selected time period.")

                    MetricCard(
                        title: "Words Analyzed",
                        value: formatNumber(statistics.wordsAnalyzed(in: selectedTimeRange)),
                        subtitle: "",
                        icon: "doc.text.fill",
                        color: .blue
                    )
                    .help("Total word count analyzed in the selected time period. The same text analyzed multiple times is counted each time.")

                    MetricCard(
                        title: "Avg Errors per 100 Words",
                        value: String(format: "%.1f", statistics.averageErrorsPer100Words(in: selectedTimeRange)),
                        subtitle: "",
                        icon: "chart.bar.fill",
                        color: .orange
                    )
                    .help("Average number of errors found per 100 words analyzed in the selected time period.\nCalculated as: (Total Errors ÷ Total Words) × 100")

                    MetricCard(
                        title: "Active Days",
                        value: "\(statistics.currentStreak(in: selectedTimeRange))",
                        subtitle: "",
                        icon: "calendar.badge.clock",
                        color: .pink
                    )
                    .help("Number of consecutive days you've used TextWarden. Keep your streak going!")

                    MetricCard(
                        title: "Most Used In",
                        value: statistics.topWritingApp(in: selectedTimeRange)?.name ?? "—",
                        subtitle: "",
                        icon: "app.fill",
                        color: .purple
                    )
                    .help("The application where TextWarden has caught the most errors in the selected time period.")
                }

                Divider()
                    .padding(.vertical, 8)

                // Engine Performance
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "speedometer")
                                .font(.title2)
                                .foregroundColor(.cyan)
                                .frame(width: 28)
                            Text("Grammar Engine Performance")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        if statistics.latencySamples(in: selectedTimeRange).isEmpty {
                            Text("No performance data yet")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                                .padding(.vertical, 8)
                        } else {
                            let meanLatency = statistics.meanLatencyMs(in: selectedTimeRange)
                            let medianLatency = statistics.medianLatencyMs(in: selectedTimeRange)
                            let p90Latency = statistics.p90LatencyMs(in: selectedTimeRange)
                            let p95Latency = statistics.p95LatencyMs(in: selectedTimeRange)
                            let p99Latency = statistics.p99LatencyMs(in: selectedTimeRange)
                            let maxLatency = max(meanLatency, medianLatency, p90Latency, p95Latency, p99Latency)

                            VStack(alignment: .leading, spacing: 10) {
                                LatencyRow(label: "Average", value: meanLatency, maxValue: maxLatency, color: .cyan)
                                    .help("Mean analysis time: sum of all latencies divided by sample count. Shows typical performance.")

                                LatencyRow(label: "Median", value: medianLatency, maxValue: maxLatency, color: .blue.opacity(0.8))
                                    .help("Middle value of analysis times. Less affected by outliers than average, representing the most common experience.")

                                LatencyRow(label: "P90", value: p90Latency, maxValue: maxLatency, color: .blue)
                                    .help("90% of analyses complete faster than this time. Indicates good performance for most analyses.")

                                LatencyRow(label: "P95", value: p95Latency, maxValue: maxLatency, color: .blue.opacity(1.2))
                                    .help("95% of analyses complete faster than this time. Shows performance consistency.")

                                LatencyRow(label: "P99", value: p99Latency, maxValue: maxLatency, color: Color(red: 0, green: 0.3, blue: 0.7))
                                    .help("99% of analyses complete faster than this time. Represents worst-case performance for edge cases.")
                            }
                            .padding(.vertical, 4)

                            Text("Total analyses: \(statistics.analysisSessions(in: selectedTimeRange))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                }

                Divider()
                    .padding(.vertical, 8)

                // Top Applications
                let appUsage = statistics.appUsageBreakdown(in: selectedTimeRange)
                let sortedApps = appUsage.sorted { $0.value > $1.value }.prefix(5)
                let totalAppErrors = sortedApps.reduce(0) { $0 + $1.1 }
                let maxAppCount = sortedApps.first?.1 ?? 1

                if !appUsage.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "app.badge.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28)
                                Text("Top Applications")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            .help("Applications where TextWarden analyzed text, ranked by number of errors found.")

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(sortedApps.enumerated()), id: \.element.key) { index, app in
                                    let purpleShades: [Color] = [
                                        Color(red: 0.7, green: 0.5, blue: 0.9),  // Light purple
                                        Color(red: 0.6, green: 0.4, blue: 0.8),  // Medium-light purple
                                        Color(red: 0.5, green: 0.3, blue: 0.7),  // Medium purple
                                        Color(red: 0.4, green: 0.2, blue: 0.6),  // Medium-dark purple
                                        Color(red: 0.3, green: 0.1, blue: 0.5)   // Dark purple
                                    ]
                                    AppRow(
                                        appName: statistics.friendlyAppName(from: app.key),
                                        count: app.value,
                                        maxCount: maxAppCount,
                                        total: totalAppErrors,
                                        color: purpleShades[min(index, purpleShades.count - 1)]
                                    )
                                }

                                Text("Total errors: \(totalAppErrors)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding()
                    }

                    Divider()
                        .padding(.vertical, 8)
                }

                // User Actions
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .frame(width: 28)
                            Text("User Actions")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .help("Breakdown of how you interact with TextWarden's suggestions.")

                        let appliedCount = statistics.suggestionsApplied(in: selectedTimeRange)
                        let dismissedCount = statistics.suggestionsDismissed(in: selectedTimeRange)
                        let dictionaryCount = statistics.wordsAddedToDictionary(in: selectedTimeRange)
                        let totalActions = appliedCount + dismissedCount + dictionaryCount

                        if totalActions > 0 {
                            VStack(alignment: .leading, spacing: 10) {
                                ActionRow(
                                    label: "Applied",
                                    value: appliedCount,
                                    total: totalActions,
                                    color: Color(red: 0.4, green: 0.8, blue: 0.4)
                                )
                                .help("Number of suggestions you've accepted and applied. Shows you find these helpful.")

                                ActionRow(
                                    label: "Dismissed",
                                    value: dismissedCount,
                                    total: totalActions,
                                    color: Color(red: 0.2, green: 0.7, blue: 0.3)
                                )
                                .help("Number of suggestions you've ignored or dismissed. These may not have been relevant.")

                                ActionRow(
                                    label: "To Dictionary",
                                    value: dictionaryCount,
                                    total: totalActions,
                                    color: Color(red: 0.1, green: 0.6, blue: 0.2)
                                )
                                .help("Words you've added to your personal dictionary to prevent future false positives.")
                            }
                            .padding(.vertical, 4)

                            Text("Total actions: \(totalActions)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        } else {
                            Text("No actions yet")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding()
                }

                Divider()
                    .padding(.vertical, 8)

                // Category Breakdown
                let categoryBreakdown = statistics.categoryBreakdown(in: selectedTimeRange)
                let sortedCategories = categoryBreakdown.sorted { $0.value > $1.value }
                let mostCommonCategory = statistics.mostCommonCategory(in: selectedTimeRange)
                let totalCategoryErrors = sortedCategories.reduce(0) { $0 + $1.1 }
                let maxCategoryCount = sortedCategories.first?.1 ?? 1

                if !categoryBreakdown.isEmpty {
                    GroupBox {
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
                                ForEach(Array(sortedCategories.enumerated()), id: \.element.0) { index, categoryPair in
                                    let orangeShades: [Color] = [
                                        Color(red: 1.0, green: 0.7, blue: 0.4),  // Light orange
                                        Color(red: 1.0, green: 0.6, blue: 0.3),  // Medium-light orange
                                        Color(red: 0.9, green: 0.5, blue: 0.2),  // Medium orange
                                        Color(red: 0.8, green: 0.45, blue: 0.15), // Medium-dark orange
                                        Color(red: 0.7, green: 0.4, blue: 0.1),  // Dark orange
                                        Color(red: 0.6, green: 0.35, blue: 0.05), // Darker orange
                                        Color(red: 0.5, green: 0.3, blue: 0.0)   // Darkest orange
                                    ]
                                    CategoryRow(
                                        category: categoryPair.0,
                                        count: categoryPair.1,
                                        maxCount: maxCategoryCount,
                                        total: totalCategoryErrors,
                                        isTopCategory: categoryPair.0 == mostCommonCategory,
                                        color: orangeShades[min(index, orangeShades.count - 1)]
                                    )
                                }

                                Text("Total errors: \(totalCategoryErrors)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding()
                    }

                    Divider()
                        .padding(.vertical, 8)
                }

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
        HStack(spacing: 10) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .cornerRadius(6)

            // Content
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

private struct CategoryRow: View {
    let category: String
    let count: Int
    let maxCount: Int
    let total: Int
    let isTopCategory: Bool
    let color: Color

    var percentage: Double {
        guard total > 0 else { return 0.0 }
        return (Double(count) / Double(total)) * 100.0
    }

    var body: some View {
        HStack {
            // Category name
            Text(formatCategoryName(category))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            // Visual bar indicator
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    // Bar (scaled relative to max count, like LatencyRow)
                    let barPercentage = maxCount > 0 ? (Double(count) / Double(maxCount)) : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.5))
                        .frame(width: geometry.size.width * 0.75 * barPercentage)
                        .frame(height: 6)

                    Spacer()

                    // Count and percentage
                    HStack(spacing: 4) {
                        Text("\(count)")
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(color)

                        Text("(\(Int(percentage))%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 20)
        }
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

private struct LatencyRow: View {
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            // Visual bar indicator
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    // Bar (scaled relative to max value)
                    let percentage = maxValue > 0 ? (value / maxValue) : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.5))
                        .frame(width: geometry.size.width * 0.75 * percentage)
                        .frame(height: 6)

                    Spacer()

                    // Value
                    Text(String(format: "%.0fms", value))
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(color)
                }
            }
            .frame(height: 20)
        }
    }
}

private struct AppRow: View {
    let appName: String
    let count: Int
    let maxCount: Int
    let total: Int
    let color: Color

    var percentage: Double {
        guard total > 0 else { return 0.0 }
        return (Double(count) / Double(total)) * 100.0
    }

    var body: some View {
        HStack {
            Text(appName)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)

            // Visual bar indicator
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    // Bar (scaled relative to max count)
                    let barPercentage = maxCount > 0 ? (Double(count) / Double(maxCount)) : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.5))
                        .frame(width: geometry.size.width * 0.75 * barPercentage)
                        .frame(height: 6)

                    Spacer()

                    // Count and percentage
                    HStack(spacing: 4) {
                        Text("\(count)")
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(color)

                        Text("(\(Int(percentage))%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 20)
        }
    }
}

private struct ActionRow: View {
    let label: String
    let value: Int
    let total: Int
    let color: Color

    var percentage: Double {
        guard total > 0 else { return 0.0 }
        return (Double(value) / Double(total)) * 100.0
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            // Visual bar indicator
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    // Bar (scaled to percentage)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.5))
                        .frame(width: min(geometry.size.width * 0.75 * (percentage / 100.0), geometry.size.width * 0.75))
                        .frame(height: 6)

                    Spacer()

                    // Count and percentage
                    HStack(spacing: 4) {
                        Text("\(value)")
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(color)

                        Text("(\(Int(percentage))%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 20)
        }
    }
}

// MARK: - Application Settings (T066-T075)

struct ApplicationSettingsView: View {
    @ObservedObject var preferences: UserPreferences
    @State private var searchText = ""
    @State private var discoveredApps: [ApplicationInfo] = []
    @State private var hiddenApps: [ApplicationInfo] = []
    @State private var isHiddenSectionExpanded = false

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

                            // Position Calibration for Electron apps
                            PositionCalibrationSection(
                                preferences: preferences,
                                app: app
                            )
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
                                        Text(app.bundleIdentifier)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .onTapGesture(count: 2) {
                                                copyToClipboard(app.bundleIdentifier)
                                            }
                                            .help("Double-click to copy bundle identifier")
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
            // Reload to reflect changes (T072, T073)
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

    /// Check if a bundle ID should be excluded from the discovered applications list
    /// Checks against the user's hidden applications list
    private func shouldExcludeFromApplicationList(_ bundleID: String) -> Bool {
        return preferences.hiddenApplications.contains(bundleID)
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

    private var filteredWords: [String] {
        let allWords = Array(vocabulary.words).sorted()
        if searchText.isEmpty {
            return allWords
        }
        return allWords.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            // Predefined Wordlists
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Internet Abbreviations", isOn: $preferences.enableInternetAbbreviations)
                            .help("Accept common abbreviations like BTW, FYI, LOL, ASAP, etc.")

                        Text("3,200+ abbreviations (BTW, FYI, LOL, ASAP, AFAICT, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Gen Z Slang", isOn: $preferences.enableGenZSlang)
                            .help("Accept modern slang words like ghosting, sus, slay, etc.")

                        Text("270+ modern terms (ghosting, sus, slay, vibe, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("IT & Tech Terminology", isOn: $preferences.enableITTerminology)
                            .help("Accept technical terms like kubernetes, docker, API, JSON, localhost, etc.")

                        Text("10,000+ technical terms (kubernetes, docker, nginx, API, JSON, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.book.closed.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Custom Dictionary & Wordlists")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Manage your personal dictionary and enable predefined wordlists")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Predefined Wordlists")
                        .font(.headline)
                        .padding(.top, 8)
                }
            }

            // Language Detection
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
                            .padding(.top, 8)

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
            } header: {
                Text("Language Detection")
                    .font(.headline)
            }

            // Custom Dictionary
            Section {
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
                }

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

                if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text("Custom Dictionary")
                    .font(.headline)
            }

            // Word List
            if !vocabulary.words.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

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
                    .padding(.vertical, 4)
                }

                Section {
                    if filteredWords.isEmpty {
                        Text("No words found")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
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
                        }
                    }
                } header: {
                    HStack {
                        Text("Your Words")
                            .font(.headline)
                        Spacer()
                        if !vocabulary.words.isEmpty {
                            Button(role: .destructive) {
                                clearAll()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
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

            // Generate and export ZIP package asynchronously
            DispatchQueue.global(qos: .userInitiated).async {
                let success = DiagnosticReport.exportAsZIP(
                    to: url,
                    preferences: self.preferences,
                    shortcuts: shortcuts
                )

                DispatchQueue.main.async {
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
    }


    private func formatDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - Resource Monitoring View

struct ResourceMonitoringView: View {
    @ObservedObject private var statistics = UserStatistics.shared
    @State private var selectedTimeRange: ResourceTimeRange = .oneHour
    @State private var selectedCPUDate: Date?
    @State private var selectedMemoryDate: Date?

    enum ResourceTimeRange: String, CaseIterable {
        case fifteenMin = "15m"
        case oneHour = "1h"
        case oneDay = "1d"
        case sevenDays = "7d"
        case thirtyDays = "30d"

        var minutes: Int {
            switch self {
            case .fifteenMin: return 15
            case .oneHour: return 60
            case .oneDay: return 24 * 60
            case .sevenDays: return 7 * 24 * 60
            case .thirtyDays: return 30 * 24 * 60
            }
        }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                // Header with time range selector
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("System Resource Usage")
                            .font(.headline)
                        Spacer()
                        Picker("", selection: $selectedTimeRange) {
                            ForEach(ResourceTimeRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Text("Monitor CPU and memory usage of the TextWarden process")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("CPU load shows active threads. A load of 1.0 means one CPU core is fully utilized. On a \(ProcessInfo.processInfo.activeProcessorCount)-core system, full utilization would be \(ProcessInfo.processInfo.activeProcessorCount).0.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Metrics display
                let samples = filteredSamples()
                if !samples.isEmpty {
                    // CPU Metrics
                    cpuMetricsView(samples: samples)

                    Divider()
                        .padding(.vertical, 8)

                    // Memory Metrics
                    memoryMetricsView(samples: samples)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No data available for selected time range")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Resource monitoring started when the app launched.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
        } header: {
            Text("Resource Monitoring")
                .font(.headline)
        }
    }

    // MARK: - CPU Metrics View

    @ViewBuilder
    private func cpuMetricsView(samples: [ResourceMetricSample]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.orange)
                Text("CPU Load Over Time")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // CPU Load Line Chart
            let peakLoad = samples.map(\.processLoad).max() ?? 0.0
            let maxLoad = peakLoad * 1.2  // Add 20% headroom

            // Add horizontal padding by extending the time domain
            let rawTimeRange = (samples.first?.timestamp ?? Date())...(samples.last?.timestamp ?? Date())
            let duration = rawTimeRange.upperBound.timeIntervalSince(rawTimeRange.lowerBound)
            let padding = duration * 0.045  // 4.5% padding on each side (~45pt equivalent)
            let timeRange = rawTimeRange.lowerBound.addingTimeInterval(-padding)...rawTimeRange.upperBound.addingTimeInterval(padding)

            // Filter app launches to only those within the raw time range (before padding)
            let visibleLaunches = statistics.appLaunchHistory.filter {
                $0 >= rawTimeRange.lowerBound && $0 <= rawTimeRange.upperBound
            }

            Chart {
                // CPU load line
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Load", sample.processLoad)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                }

                // Peak load line (dotted)
                RuleMark(y: .value("Peak", peakLoad))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Peak: \(String(format: "%.2f", peakLoad))")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.background.opacity(0.8))
                            .cornerRadius(4)
                    }

                // App launch markers (dots)
                ForEach(visibleLaunches, id: \.self) { launchTime in
                    PointMark(
                        x: .value("Launch", launchTime),
                        y: .value("Load", 0)
                    )
                    .foregroundStyle(.gray)
                    .symbolSize(60)
                }

                // Tooltip on hover
                if let selectedCPUDate {
                    // Find the nearest sample to the selected date
                    let nearestSample = samples.min(by: { abs($0.timestamp.timeIntervalSince(selectedCPUDate)) < abs($1.timestamp.timeIntervalSince(selectedCPUDate)) })
                    if let selectedSample = nearestSample {
                        RuleMark(x: .value("Selected", selectedSample.timestamp))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .top, alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedSample.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Load: \(String(format: "%.2f", selectedSample.processLoad))")
                                        .font(.callout)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                    if let sys1m = selectedSample.systemLoad1m {
                                        Text("System: \(String(format: "%.2f", sys1m))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(.background)
                                .cornerRadius(8)
                                .shadow(radius: 3)
                            }
                    }
                }
            }
            .chartXSelection(value: $selectedCPUDate)
            .chartXScale(domain: timeRange)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let load = value.as(Double.self) {
                            Text(String(format: "%.1f", load))
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYScale(domain: 0...maxLoad)
            .frame(height: 200)

            // Summary statistics
            let loadValues = samples.map(\.processLoad)
            let avgLoad = loadValues.reduce(0, +) / Double(loadValues.count)
            let medianLoad = median(loadValues)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", loadValues.min() ?? 0))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Max")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", loadValues.max() ?? 0))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", avgLoad))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Median")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", medianLoad))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }

                Spacer()

                Text("\(samples.count) samples")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Legend for app restart markers
            if !visibleLaunches.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.gray)
                        .frame(width: 8, height: 8)
                    Text("Gray dots indicate app restarts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Memory Metrics View

    @ViewBuilder
    private func memoryMetricsView(samples: [ResourceMetricSample]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "memorychip")
                    .foregroundColor(.blue)
                Text("Memory Usage Over Time")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Memory Line Chart
            let maxMemoryMB = Double(samples.map(\.memoryBytes).max() ?? 0) / 1_048_576
            let minMemoryMB = Double(samples.map(\.memoryBytes).min() ?? 0) / 1_048_576

            // Add horizontal padding by extending the time domain
            let rawTimeRange = (samples.first?.timestamp ?? Date())...(samples.last?.timestamp ?? Date())
            let duration = rawTimeRange.upperBound.timeIntervalSince(rawTimeRange.lowerBound)
            let padding = duration * 0.045  // 4.5% padding on each side (~45pt equivalent)
            let timeRange = rawTimeRange.lowerBound.addingTimeInterval(-padding)...rawTimeRange.upperBound.addingTimeInterval(padding)

            // Filter app launches to only those within the raw time range (before padding)
            let visibleLaunches = statistics.appLaunchHistory.filter {
                $0 >= rawTimeRange.lowerBound && $0 <= rawTimeRange.upperBound
            }

            Chart {
                // Memory line
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Memory", Double(sample.memoryBytes) / 1_048_576) // Convert to MB
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
                }

                // Peak memory line (dotted)
                RuleMark(y: .value("Peak", maxMemoryMB))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Peak: \(Int(maxMemoryMB)) MB")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.background.opacity(0.8))
                            .cornerRadius(4)
                    }

                // App launch markers (dots)
                ForEach(visibleLaunches, id: \.self) { launchTime in
                    PointMark(
                        x: .value("Launch", launchTime),
                        y: .value("Memory", minMemoryMB)
                    )
                    .foregroundStyle(.gray)
                    .symbolSize(60)
                }

                // Tooltip on hover
                if let selectedMemoryDate {
                    // Find the nearest sample to the selected date
                    let nearestSample = samples.min(by: { abs($0.timestamp.timeIntervalSince(selectedMemoryDate)) < abs($1.timestamp.timeIntervalSince(selectedMemoryDate)) })
                    if let selectedSample = nearestSample {
                        RuleMark(x: .value("Selected", selectedSample.timestamp))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .top, alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedSample.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(selectedSample.memoryBytes), countStyle: .memory))
                                        .font(.callout)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                                .padding(8)
                                .background(.background)
                                .cornerRadius(8)
                                .shadow(radius: 3)
                            }
                    }
                }
            }
            .chartXSelection(value: $selectedMemoryDate)
            .chartXScale(domain: timeRange)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let mb = value.as(Double.self) {
                            Text("\(Int(mb)) MB")
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYScale(domain: (minMemoryMB * 0.9)...(maxMemoryMB * 1.1))
            .frame(height: 200)

            // Summary statistics
            let memoryValues = samples.map(\.memoryBytes)
            let avgBytes = memoryValues.reduce(0, +) / UInt64(memoryValues.count)
            let medianBytes = medianUInt64(memoryValues)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(memoryValues.min() ?? 0), countStyle: .memory))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Max")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(memoryValues.max() ?? 0), countStyle: .memory))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(avgBytes), countStyle: .memory))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Median")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(medianBytes), countStyle: .memory))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }

                Spacer()

                Text("\(samples.count) samples")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Legend for app restart markers
            if !visibleLaunches.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.gray)
                        .frame(width: 8, height: 8)
                    Text("Gray dots indicate app restarts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func filteredSamples() -> [ResourceMetricSample] {
        let cutoffDate = Calendar.current.date(byAdding: .minute, value: -selectedTimeRange.minutes, to: Date()) ?? Date.distantPast

        let allSamples = statistics.resourceSamples
            .filter { $0.component == .swiftApp }
            .filter { $0.timestamp >= cutoffDate }
            .sorted { $0.timestamp < $1.timestamp }

        // Downsample for longer time ranges to keep charts smooth
        // Target ~180 points for optimal visual appearance
        let targetPoints = 180
        guard allSamples.count > targetPoints else { return allSamples }

        // For 15m, keep all samples (usually ~180 at 5s intervals)
        // For longer ranges, downsample by averaging windows
        let step = max(1, allSamples.count / targetPoints)
        var downsampled: [ResourceMetricSample] = []

        for i in stride(from: 0, to: allSamples.count, by: step) {
            let windowEnd = min(i + step, allSamples.count)
            let window = Array(allSamples[i..<windowEnd])

            guard !window.isEmpty else { continue }

            // Use the middle sample's timestamp for accurate positioning
            let midIndex = window.count / 2
            let timestamp = window[midIndex].timestamp

            // Average the values in the window
            let avgLoad = window.map(\.processLoad).reduce(0, +) / Double(window.count)
            let avgMemory = UInt64(window.map { Double($0.memoryBytes) }.reduce(0, +) / Double(window.count))

            // Take system load from middle sample (or nil if any is nil)
            let sys1m = window[midIndex].systemLoad1m
            let sys5m = window[midIndex].systemLoad5m
            let sys15m = window[midIndex].systemLoad15m

            downsampled.append(ResourceMetricSample(
                timestamp: timestamp,
                component: .swiftApp,
                processLoad: avgLoad,
                memoryBytes: avgMemory,
                systemLoad1m: sys1m,
                systemLoad5m: sys5m,
                systemLoad15m: sys15m
            ))
        }

        return downsampled
    }

    /// Calculate median of Double values
    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let sorted = values.sorted()
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            return sorted[sorted.count / 2]
        }
    }

    /// Calculate median of UInt64 values
    private func medianUInt64(_ values: [UInt64]) -> UInt64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            return sorted[sorted.count / 2]
        }
    }

    // MARK: - Helper Views

    private func loadBadge(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f%%", value))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(loadColor(value))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private func loadColor(_ value: Double) -> Color {
        switch value {
        case 0..<25: return .green
        case 25..<50: return .yellow
        case 50..<75: return .orange
        default: return .red
        }
    }

    private func percentileRow(_ label: String, value: Double, max: Double, color: Color, isPercent: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 40, alignment: .leading)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                    Rectangle()
                        .fill(color)
                        .frame(width: max > 0 ? geometry.size.width * CGFloat(value / max) : 0)
                }
            }
            .frame(height: 6)
            .cornerRadius(3)

            if isPercent {
                Text(String(format: "%.1f%%", value))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                    .monospacedDigit()
            } else {
                Text(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory))
                    .font(.caption)
                    .frame(width: 70, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App Icon and Title
                Image("TextWardenLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)

                Text("TextWarden")
                    .font(.system(size: 42, weight: .bold))

                Text("Real-time Grammar Checking for macOS")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Divider()
                    .padding(.horizontal, 40)

                // Version Information
                VStack(spacing: 14) {
                    InfoRow(label: "Version", value: BuildInfo.fullVersion)
                    InfoRow(label: "Build Timestamp", value: BuildInfo.buildTimestamp)
                    InfoRow(label: "Build Age", value: BuildInfo.buildAge)
                    InfoRow(label: "Grammar Engine", value: "Harper \(BuildInfo.harperVersion)")
                    InfoRow(label: "Supported Dialects", value: "American, British, Canadian, Australian")
                    InfoRow(label: "License", value: "Apache 2.0")
                }
                .padding(.horizontal, 40)

                Divider()
                    .padding(.horizontal, 40)

                // Links
                VStack(spacing: 16) {
                    Link(destination: URL(string: "https://github.com/philipschmid/textwarden")!) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("View on GitHub")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Source code and development")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://github.com/philipschmid/textwarden/blob/main/LICENSE")!) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "doc.text")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("View License")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Apache 2.0 open source license")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://github.com/philipschmid/textwarden/issues")!) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "exclamationmark.bubble")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Report an Issue")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Bug reports and feature requests")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)

                Spacer()

                Text("© 2025 Philip Schmid. All rights reserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
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

// MARK: - Position Calibration Section

fileprivate struct PositionCalibrationSection: View {
    @ObservedObject var preferences: UserPreferences
    let app: ApplicationInfo
    @State private var isExpanded = false

    var body: some View {
        let calibration = preferences.getCalibration(for: app.bundleIdentifier)
        let hasCustomCalibration = calibration != .default
        let isElectronApp = app.bundleIdentifier.contains("electron") ||
                           app.bundleIdentifier.contains("slack") ||
                           app.bundleIdentifier.contains("discord") ||
                           app.bundleIdentifier.contains("msteams") ||
                           app.bundleIdentifier.contains("vscode")

        VStack(alignment: .leading, spacing: 0) {
            // Clickable header
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "ruler.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Position Calibration")
                        .font(.caption)
                        .fontWeight(.medium)
                    if hasCustomCalibration {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)
            .padding(.top, 8)

            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                        // Status indicator
                        HStack {
                            Image(systemName: calibration == .default ? "checkmark.circle" :
                                  calibration == .slackPreset ? "star.circle" : "pencil.circle")
                                .foregroundColor(calibration == .default ? .green :
                                               calibration == .slackPreset ? .blue : .orange)
                            Text(calibration == .default ? "Using default positioning" :
                                 calibration == .slackPreset ? "Using Slack preset" :
                                 "Using custom positioning")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)

                        // Position Adjustment (Horizontal Offset)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text("Position Adjustment")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Button {
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Shifts underlines left or right to align with text. Use this if underlines appear offset from the actual error.")

                                Spacer()

                                Text("\(Int(calibration.horizontalOffset)) px")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            HStack(spacing: 8) {
                                Text("← Left")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 52, alignment: .leading)

                                Slider(
                                    value: Binding(
                                        get: { calibration.horizontalOffset },
                                        set: { newValue in
                                            var updated = calibration
                                            updated.horizontalOffset = newValue
                                            preferences.setCalibration(for: app.bundleIdentifier, calibration: updated)
                                        }
                                    ),
                                    in: -50...50,
                                    step: 1
                                )

                                Text("Right →")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }

                        // Width Adjustment (Width Multiplier)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text("Width Adjustment")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Button {
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Adjusts the width of underlines. Use this if underlines are too wide or too narrow for the error text.")

                                Spacer()

                                Text(String(format: "%.0f%%", calibration.widthMultiplier * 100))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            HStack(spacing: 8) {
                                Text("Narrower")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 52, alignment: .leading)

                                Slider(
                                    value: Binding(
                                        get: { calibration.widthMultiplier },
                                        set: { newValue in
                                            var updated = calibration
                                            updated.widthMultiplier = newValue
                                            preferences.setCalibration(for: app.bundleIdentifier, calibration: updated)
                                        }
                                    ),
                                    in: 0.5...1.5,
                                    step: 0.01
                                )

                                Text("Wider")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }

                        // Preset Buttons
                        HStack(spacing: 8) {
                            if isElectronApp {
                                Button {
                                    preferences.setCalibration(for: app.bundleIdentifier, calibration: .slackPreset)
                                } label: {
                                    Label("Electron Preset", systemImage: "wand.and.stars")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help("Apply recommended settings for Electron apps (0.94x width)")
                            }

                            Button {
                                preferences.setCalibration(for: app.bundleIdentifier, calibration: .default)
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Reset to default positioning")
                        }
                        .padding(.top, 4)

                        // Info text
                        Text("💡 Adjust these values while viewing errors in \(app.name) for real-time preview.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.leading, 28)
                    .padding(.vertical, 8)
            }
        }
    }
}

#Preview {
    PreferencesView()
}
