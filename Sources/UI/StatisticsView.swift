//
//  StatisticsView.swift
//  TextWarden
//
//  Statistics and usage analytics view for the preferences window.
//

import Charts
import SwiftUI

// MARK: - Statistics View

struct StatisticsView: View {
    @ObservedObject private var statistics = UserStatistics.shared
    @ObservedObject private var preferences = UserPreferences.shared
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
                            "Shows statistics for the selected time period")
                    }
                }
                .padding(.bottom, 4)

                // Core Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
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
                                        Color(red: 0.7, green: 0.5, blue: 0.9), // Light purple
                                        Color(red: 0.6, green: 0.4, blue: 0.8), // Medium-light purple
                                        Color(red: 0.5, green: 0.3, blue: 0.7), // Medium purple
                                        Color(red: 0.4, green: 0.2, blue: 0.6), // Medium-dark purple
                                        Color(red: 0.3, green: 0.1, blue: 0.5), // Dark purple
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
                                        Color(red: 1.0, green: 0.7, blue: 0.4), // Light orange
                                        Color(red: 1.0, green: 0.6, blue: 0.3), // Medium-light orange
                                        Color(red: 0.9, green: 0.5, blue: 0.2), // Medium orange
                                        Color(red: 0.8, green: 0.45, blue: 0.15), // Medium-dark orange
                                        Color(red: 0.7, green: 0.4, blue: 0.1), // Dark orange
                                        Color(red: 0.6, green: 0.35, blue: 0.05), // Darker orange
                                        Color(red: 0.5, green: 0.3, blue: 0.0), // Darkest orange
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

                // Style Checking Statistics
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header
                        HStack {
                            Image(systemName: "apple.intelligence")
                                .font(.title2)
                                .foregroundColor(.purple)
                                .frame(width: 28)
                            Text("Style Checking")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Spacer()

                            Text("Apple Intelligence")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // Metrics row
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("\(statistics.llmAnalysisRuns)")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.purple)
                                Text("Analyses")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()
                                .frame(height: 40)

                            VStack(alignment: .leading) {
                                Text("\(statistics.styleSuggestionsShown)")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.purple.opacity(0.8))
                                Text("Suggestions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()
                                .frame(height: 40)

                            VStack(alignment: .leading) {
                                Text("\(statistics.styleSuggestionsAccepted)")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                Text("Accepted")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()
                                .frame(height: 40)

                            VStack(alignment: .leading) {
                                Text("\(statistics.styleSuggestionsRejected)")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                Text("Rejected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()
                                .frame(height: 40)

                            VStack(alignment: .leading) {
                                // Ignored = Shown - Accepted - Rejected
                                let ignoredCount = max(0, statistics.styleSuggestionsShown - statistics.styleSuggestionsAccepted - statistics.styleSuggestionsRejected)
                                Text("\(ignoredCount)")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text("Ignored")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Divider()
                            .padding(.vertical, 4)

                        // Performance section with grouped bars by preset
                        Text("LLM Inference Performance")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        // Apple Intelligence model ID constant
                        let appleIntelligenceModelId = "apple-foundation-models"

                        if statistics.detailedStyleLatencySamples.isEmpty {
                            Text("No performance data yet")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                                .padding(.vertical, 8)
                        } else {
                            // Temperature preset legend
                            HStack(spacing: 16) {
                                ForEach(StyleTemperaturePreset.allCases) { preset in
                                    let count = statistics.sampleCount(forModel: appleIntelligenceModelId, preset: preset.rawValue)
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(temperaturePresetColor(preset))
                                            .frame(width: 10, height: 10)
                                        Text("\(preset.label) (\(count))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)

                            // Grouped bar chart for metrics
                            VStack(alignment: .leading, spacing: 12) {
                                AppleIntelligenceLatencyRow(
                                    label: "Average",
                                    modelId: appleIntelligenceModelId,
                                    statistics: statistics,
                                    metricExtractor: { stats, model, preset in
                                        stats.averageStyleLatency(forModel: model, preset: preset)
                                    }
                                )
                                .help("Mean inference time for each temperature preset.")

                                AppleIntelligenceLatencyRow(
                                    label: "Median",
                                    modelId: appleIntelligenceModelId,
                                    statistics: statistics,
                                    metricExtractor: { stats, model, preset in
                                        stats.medianStyleLatency(forModel: model, preset: preset)
                                    }
                                )
                                .help("Middle value of inference times. Less affected by outliers.")

                                AppleIntelligenceLatencyRow(
                                    label: "P90",
                                    modelId: appleIntelligenceModelId,
                                    statistics: statistics,
                                    metricExtractor: { stats, model, preset in
                                        stats.p90StyleLatency(forModel: model, preset: preset)
                                    }
                                )
                                .help("90% of inferences complete faster than this time.")

                                AppleIntelligenceLatencyRow(
                                    label: "P95",
                                    modelId: appleIntelligenceModelId,
                                    statistics: statistics,
                                    metricExtractor: { stats, model, preset in
                                        stats.p95StyleLatency(forModel: model, preset: preset)
                                    }
                                )
                                .help("95% of inferences complete faster than this time.")

                                AppleIntelligenceLatencyRow(
                                    label: "P99",
                                    modelId: appleIntelligenceModelId,
                                    statistics: statistics,
                                    metricExtractor: { stats, model, preset in
                                        stats.p99StyleLatency(forModel: model, preset: preset)
                                    }
                                )
                                .help("99% of inferences complete faster than this time. Shows worst-case.")
                            }
                            .padding(.vertical, 4)

                            if statistics.styleSuggestionsAccepted + statistics.styleSuggestionsRejected > 0 {
                                let acceptanceRate = statistics.styleAcceptanceRate
                                Text(String(format: "Acceptance rate: %.0f%%", acceptanceRate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding()
                }

                Divider()
                    .padding(.vertical, 8)

                // Rejection Reasons (standalone card)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .frame(width: 28)
                            Text("Rejection Reasons")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        let totalRejections = statistics.styleRejectionCategories.values.reduce(0, +)
                        let maxRejectionCount = SuggestionRejectionCategory.allCases.map { statistics.styleRejectionCategories[$0.rawValue] ?? 0 }.max() ?? 1

                        VStack(alignment: .leading, spacing: 8) {
                            // Show all rejection categories, sorted by count (descending)
                            ForEach(Array(SuggestionRejectionCategory.allCases.sorted { category1, category2 in
                                let count1 = statistics.styleRejectionCategories[category1.rawValue] ?? 0
                                let count2 = statistics.styleRejectionCategories[category2.rawValue] ?? 0
                                return count1 > count2
                            }.enumerated()), id: \.element) { index, category in
                                let count = statistics.styleRejectionCategories[category.rawValue] ?? 0

                                let orangeShades: [Color] = [
                                    Color(red: 1.0, green: 0.7, blue: 0.4),
                                    Color(red: 1.0, green: 0.6, blue: 0.3),
                                    Color(red: 0.9, green: 0.5, blue: 0.2),
                                    Color(red: 0.8, green: 0.45, blue: 0.15),
                                    Color(red: 0.7, green: 0.4, blue: 0.1),
                                    Color(red: 0.6, green: 0.35, blue: 0.05),
                                ]

                                CategoryRow(
                                    category: category.displayName,
                                    count: count,
                                    maxCount: max(maxRejectionCount, 1),
                                    total: max(totalRejections, 1),
                                    isTopCategory: index == 0 && count > 0,
                                    color: orangeShades[min(index, orangeShades.count - 1)]
                                )
                            }

                            Text("Total rejections: \(totalRejections)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
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
                        Button("Cancel", role: .cancel) {}
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
            String(format: "%.1fM", Double(number) / 1_000_000.0)
        } else if number >= 1000 {
            String(format: "%.1fK", Double(number) / 1000.0)
        } else {
            "\(number)"
        }
    }

    private func formatCategoryName(_ category: String) -> String {
        guard category != "None" else { return category }

        var result = ""
        for (index, char) in category.enumerated() {
            if index > 0, char.isUppercase {
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
                .accessibilityHidden(true) // Decorative icon

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
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
                        .accessibilityHidden(true) // Visual progress bar

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formatCategoryName(category)): \(count) errors, \(Int(percentage)) percent of total")
    }

    private func formatCategoryName(_ category: String) -> String {
        var result = ""
        for (index, char) in category.enumerated() {
            if index > 0, char.isUppercase {
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
                        .accessibilityHidden(true) // Visual progress bar

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) latency: \(String(format: "%.0f", value)) milliseconds")
    }
}

/// Helper function to convert StyleTemperaturePreset to SwiftUI Color
private func temperaturePresetColor(_ preset: StyleTemperaturePreset) -> Color {
    let rgb = preset.color
    return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
}

/// View that shows stacked bars for Apple Intelligence temperature presets (Consistent/Balanced/Creative)
private struct AppleIntelligenceLatencyRow: View {
    let label: String
    let modelId: String
    let statistics: UserStatistics
    let metricExtractor: (UserStatistics, String, String) -> Double

    var body: some View {
        let values = StyleTemperaturePreset.allCases.map { preset in
            metricExtractor(statistics, modelId, preset.rawValue)
        }
        let maxValue = values.max() ?? 1.0

        VStack(alignment: .leading, spacing: 4) {
            // Metric label
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .padding(.bottom, 2)

            // Stacked bars for each temperature preset
            ForEach(StyleTemperaturePreset.allCases) { preset in
                let value = metricExtractor(statistics, modelId, preset.rawValue)
                let hasData = statistics.hasData(forModel: modelId, preset: preset.rawValue)
                let percentage = maxValue > 0 ? (value / maxValue) : 0

                HStack(spacing: 8) {
                    // Preset indicator
                    Circle()
                        .fill(temperaturePresetColor(preset))
                        .frame(width: 8, height: 8)

                    // Bar
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            if hasData {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(temperaturePresetColor(preset).opacity(0.6))
                                    .frame(width: max(2, geometry.size.width * 0.7 * percentage), height: 6)
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: geometry.size.width * 0.3, height: 6)
                            }
                            Spacer()
                        }
                    }
                    .frame(height: 6)

                    // Value
                    if hasData {
                        Text(String(format: "%.0fms", value))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(temperaturePresetColor(preset))
                            .frame(width: 60, alignment: .trailing)
                    } else {
                        Text("-")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                .frame(height: 14)
            }
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
                        .accessibilityHidden(true) // Visual progress bar

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appName): \(count) errors, \(Int(percentage)) percent of total")
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
