//
//  UserStatistics.swift
//  TextWarden
//
//  User statistics tracking with UserDefaults persistence
//

import Combine
import Foundation

// MARK: - Time Range

/// Time range for filtering statistics
enum TimeRange: String, CaseIterable, Codable {
    case session = "Since App Start"
    case day = "1 Day"
    case week = "7 Days"
    case month = "30 Days"
    case ninetyDays = "90 Days"

    var dateThreshold: Date? {
        let now = Date()
        switch self {
        case .session:
            // Special case: handled by app launch timestamp
            return nil
        case .day:
            return Calendar.current.date(byAdding: .day, value: -1, to: now)
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month:
            return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .ninetyDays:
            return Calendar.current.date(byAdding: .day, value: -90, to: now)
        }
    }
}

// MARK: - Timestamped Data Structures

/// Detailed analysis session with timestamp
struct DetailedAnalysisSession: Codable {
    let timestamp: Date
    let wordsProcessed: Int
    let errorsFound: Int
    let bundleIdentifier: String?
    let categoryBreakdown: [String: Int]
    let latencyMs: Double
}

/// User action on a suggestion
enum ActionType: String, Codable {
    case applied
    case dismissed
    case addedToDictionary
}

/// Timestamped suggestion action
struct SuggestionAction: Codable {
    let timestamp: Date
    let action: ActionType
    let category: String?
}

/// Style latency sample with model and preset context
struct StyleLatencySample: Codable {
    let timestamp: Date
    let modelId: String
    let preset: String // "fast", "balanced", "quality"
    let latencyMs: Double
}

/// Log volume sample tracking log counts by severity over a time window
struct LogVolumeSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    var trace: Int
    var debug: Int
    var info: Int
    var warning: Int
    var error: Int
    var critical: Int

    init(timestamp: Date = Date()) {
        id = UUID()
        self.timestamp = timestamp
        trace = 0
        debug = 0
        info = 0
        warning = 0
        error = 0
        critical = 0
    }

    /// Total log count across all severities
    var total: Int {
        trace + debug + info + warning + error + critical
    }

    /// Count of logs at warning level or higher
    var warningsAndAbove: Int {
        warning + error + critical
    }
}

/// Observable user statistics for tracking usage and improvements
@MainActor
class UserStatistics: ObservableObject {
    static let shared = UserStatistics()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Helper to encode and persist a value with logging on failure
    private func persist(_ value: some Encodable, forKey key: String) {
        do {
            let encoded = try encoder.encode(value)
            defaults.set(encoded, forKey: key)
        } catch {
            Logger.warning("Failed to persist \(key): \(error.localizedDescription)", category: Logger.general)
        }
    }

    // MARK: - Core Statistics

    /// Total grammar errors detected
    @Published var errorsFound: Int {
        didSet {
            defaults.set(errorsFound, forKey: Keys.errorsFound)
        }
    }

    /// Number of suggestions that were applied
    @Published var suggestionsApplied: Int {
        didSet {
            defaults.set(suggestionsApplied, forKey: Keys.suggestionsApplied)
        }
    }

    /// Number of suggestions that were dismissed
    @Published var suggestionsDismissed: Int {
        didSet {
            defaults.set(suggestionsDismissed, forKey: Keys.suggestionsDismissed)
        }
    }

    /// Number of words added to custom dictionary
    @Published var wordsAddedToDictionary: Int {
        didSet {
            defaults.set(wordsAddedToDictionary, forKey: Keys.wordsAddedToDictionary)
        }
    }

    /// Total words analyzed across all sessions
    @Published var wordsAnalyzed: Int {
        didSet {
            defaults.set(wordsAnalyzed, forKey: Keys.wordsAnalyzed)
        }
    }

    /// Number of analysis sessions run
    @Published var analysisSessions: Int {
        didSet {
            defaults.set(analysisSessions, forKey: Keys.analysisSessions)
        }
    }

    /// Number of app sessions (launches)
    @Published var sessionCount: Int {
        didSet {
            defaults.set(sessionCount, forKey: Keys.sessionCount)
        }
    }

    /// Set of dates when the app was actively used
    @Published var activeDays: Set<Date> {
        didSet {
            persist(activeDays, forKey: Keys.activeDays)
        }
    }

    /// Breakdown of errors by category
    @Published var categoryBreakdown: [String: Int] {
        didSet {
            persist(categoryBreakdown, forKey: Keys.categoryBreakdown)
        }
    }

    /// Application usage tracking: bundleID -> error count
    @Published var appUsageBreakdown: [String: Int] {
        didSet {
            persist(appUsageBreakdown, forKey: Keys.appUsageBreakdown)
        }
    }

    /// Grammar engine latency samples (last 100 analyses)
    @Published var latencySamples: [Double] {
        didSet {
            persist(latencySamples, forKey: Keys.latencySamples)
        }
    }

    // MARK: - Timestamped Data (for time-based filtering)

    /// Detailed analysis sessions with timestamps (last 90 days)
    @Published var detailedSessions: [DetailedAnalysisSession] {
        didSet {
            persist(detailedSessions, forKey: Keys.detailedSessions)
        }
    }

    /// Timestamped suggestion actions (last 90 days)
    @Published var suggestionActions: [SuggestionAction] {
        didSet {
            persist(suggestionActions, forKey: Keys.suggestionActions)
        }
    }

    /// Timestamp when app was last launched (for "This Session" filter)
    @Published var appLaunchTimestamp: Date {
        didSet {
            defaults.set(appLaunchTimestamp.timeIntervalSince1970, forKey: Keys.appLaunchTimestamp)
        }
    }

    /// Historical app launch timestamps (last 90 days)
    @Published var appLaunchHistory: [Date] {
        didSet {
            persist(appLaunchHistory, forKey: Keys.appLaunchHistory)
        }
    }

    // MARK: - Resource Monitoring Data

    /// Resource monitoring samples (persisted to UserDefaults, 30-day retention)
    @Published private(set) var resourceSamples: [ResourceMetricSample] = [] {
        didSet {
            persistResourceSamples()
        }
    }

    // Retention configuration
    private let maxResourceAge: TimeInterval = TimingConstants.statisticsMaxAge
    private let maxInMemorySamples = 720 // 1 hour at 5s interval
    private var persistBatchCounter = 0

    // MARK: - Log Volume Tracking

    /// Log volume samples aggregated per minute (persisted, 30-day retention)
    @Published private(set) var logVolumeSamples: [LogVolumeSample] = [] {
        didSet {
            persistLogVolumeSamples()
        }
    }

    /// Current minute's log accumulator (not persisted, aggregates logs within the minute)
    private var currentLogSample: LogVolumeSample?
    private var logPersistBatchCounter = 0
    private let logSampleInterval: TimeInterval = 60 // Aggregate logs per minute

    // MARK: - Milestone Card Statistics

    /// Number of times user clicked "Buy me a coffee" on milestone card
    @Published var milestoneSupportClicks: Int {
        didSet {
            defaults.set(milestoneSupportClicks, forKey: Keys.milestoneSupportClicks)
        }
    }

    /// Number of times user clicked "Maybe Later" on milestone card
    @Published var milestoneDismissClicks: Int {
        didSet {
            defaults.set(milestoneDismissClicks, forKey: Keys.milestoneDismissClicks)
        }
    }

    /// Number of times user clicked "Don't show milestone celebrations"
    @Published var milestoneDisableClicks: Int {
        didSet {
            defaults.set(milestoneDisableClicks, forKey: Keys.milestoneDisableClicks)
        }
    }

    // MARK: - LLM Style Checking Statistics

    /// Total style suggestions shown
    @Published var styleSuggestionsShown: Int {
        didSet {
            defaults.set(styleSuggestionsShown, forKey: Keys.styleSuggestionsShown)
        }
    }

    /// Number of style suggestions accepted
    @Published var styleSuggestionsAccepted: Int {
        didSet {
            defaults.set(styleSuggestionsAccepted, forKey: Keys.styleSuggestionsAccepted)
        }
    }

    /// Number of style suggestions rejected
    @Published var styleSuggestionsRejected: Int {
        didSet {
            defaults.set(styleSuggestionsRejected, forKey: Keys.styleSuggestionsRejected)
        }
    }

    /// Number of style suggestions ignored (dismissed without action)
    @Published var styleSuggestionsIgnored: Int {
        didSet {
            defaults.set(styleSuggestionsIgnored, forKey: Keys.styleSuggestionsIgnored)
        }
    }

    /// Breakdown of rejections by category
    @Published var styleRejectionCategories: [String: Int] {
        didSet {
            persist(styleRejectionCategories, forKey: Keys.styleRejectionCategories)
        }
    }

    /// LLM analysis latency samples (last 100 analyses) - legacy, for backward compatibility
    @Published var styleLatencySamples: [Double] {
        didSet {
            persist(styleLatencySamples, forKey: Keys.styleLatencySamples)
        }
    }

    /// Detailed style latency samples with model and preset context (last 500 samples)
    @Published var detailedStyleLatencySamples: [StyleLatencySample] {
        didSet {
            persist(detailedStyleLatencySamples, forKey: Keys.detailedStyleLatencySamples)
        }
    }

    // MARK: - Computed Properties

    /// Percentage of suggestions that were applied (0-100)
    var improvementRate: Double {
        let total = suggestionsApplied + suggestionsDismissed
        guard total > 0 else { return 0.0 }
        return (Double(suggestionsApplied) / Double(total)) * 100.0
    }

    /// Average number of errors found per analysis session
    var averageErrorsPerSession: Double {
        guard analysisSessions > 0 else { return 0.0 }
        return Double(errorsFound) / Double(analysisSessions)
    }

    /// Average errors per 100 words
    var averageErrorsPer100Words: Double {
        guard wordsAnalyzed > 0 else { return 0.0 }
        return (Double(errorsFound) / Double(wordsAnalyzed)) * 100.0
    }

    /// Most frequently occurring error category
    var mostCommonCategory: String {
        guard !categoryBreakdown.isEmpty else { return "None" }
        return categoryBreakdown.max(by: { $0.value < $1.value })?.key ?? "None"
    }

    /// Estimated time saved in seconds (2 seconds per applied suggestion)
    var timeSavedInSeconds: Int {
        suggestionsApplied * 2
    }

    /// Formatted time saved string (e.g., "5m 30s" or "1h 15m")
    var timeSavedFormatted: String {
        let seconds = timeSavedInSeconds
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// Number of custom dictionary words (from UserPreferences)
    var customDictionarySize: Int {
        UserPreferences.shared.customDictionary.count
    }

    /// Current consecutive active days streak
    var currentStreak: Int {
        let sortedDays = activeDays.sorted(by: >)
        guard let mostRecent = sortedDays.first else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Check if most recent is today or yesterday (allow 1-day gap)
        let daysBetween = calendar.dateComponents([.day], from: mostRecent, to: today).day ?? 0
        guard daysBetween <= 1 else { return 0 }

        var streak = 0
        var checkDate = today

        for day in sortedDays {
            if calendar.isDate(day, inSameDayAs: checkDate) {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                    break
                }
                checkDate = previousDay
            } else if day < checkDate {
                break
            }
        }
        return streak
    }

    /// Error density (errors per 100 words) - calculated per session to avoid cumulative inflation
    var errorDensity: Double {
        guard analysisSessions > 0, wordsAnalyzed > 0 else { return 0.0 }
        let avgErrorsPerSession = Double(errorsFound) / Double(analysisSessions)
        let avgWordsPerSession = Double(wordsAnalyzed) / Double(analysisSessions)
        guard avgWordsPerSession > 0 else { return 0.0 }
        return (avgErrorsPerSession / avgWordsPerSession) * 100.0
    }

    /// Mean (average) grammar engine latency in milliseconds
    var meanLatencyMs: Double {
        guard !latencySamples.isEmpty else { return 0.0 }
        return latencySamples.reduce(0.0, +) / Double(latencySamples.count)
    }

    /// Median (P50) latency in milliseconds - middle value, less affected by outliers
    var medianLatencyMs: Double {
        percentile(of: latencySamples, percentile: 0.50)
    }

    /// P90 (90th percentile) latency in milliseconds
    /// 90% of analyses complete faster than this time
    var p90LatencyMs: Double {
        percentile(of: latencySamples, percentile: 0.90)
    }

    /// P95 (95th percentile) latency in milliseconds
    /// 95% of analyses complete faster than this time
    var p95LatencyMs: Double {
        percentile(of: latencySamples, percentile: 0.95)
    }

    /// P99 (99th percentile) latency in milliseconds
    /// 99% of analyses complete faster than this time
    var p99LatencyMs: Double {
        percentile(of: latencySamples, percentile: 0.99)
    }

    /// Top application where TextWarden is most active
    var topWritingApp: (name: String, errorCount: Int)? {
        guard !appUsageBreakdown.isEmpty else { return nil }

        let topEntry = appUsageBreakdown.max(by: { $0.value < $1.value })
        guard let entry = topEntry else { return nil }

        // Convert bundle ID to friendly name
        let appName = friendlyAppName(from: entry.key)
        return (appName, entry.value)
    }

    // MARK: - Time-Filtered Statistics

    /// Get filtered sessions based on time range
    func filteredSessions(for timeRange: TimeRange) -> [DetailedAnalysisSession] {
        if timeRange == .session {
            return detailedSessions.filter { $0.timestamp >= appLaunchTimestamp }
        }
        guard let threshold = timeRange.dateThreshold else {
            return detailedSessions
        }
        return detailedSessions.filter { $0.timestamp >= threshold }
    }

    /// Get filtered suggestion actions based on time range
    func filteredActions(for timeRange: TimeRange) -> [SuggestionAction] {
        if timeRange == .session {
            return suggestionActions.filter { $0.timestamp >= appLaunchTimestamp }
        }
        guard let threshold = timeRange.dateThreshold else {
            return suggestionActions
        }
        return suggestionActions.filter { $0.timestamp >= threshold }
    }

    /// Get errors found in time range
    func errorsFound(in timeRange: TimeRange) -> Int {
        filteredSessions(for: timeRange).reduce(0) { $0 + $1.errorsFound }
    }

    /// Get words analyzed in time range
    func wordsAnalyzed(in timeRange: TimeRange) -> Int {
        filteredSessions(for: timeRange).reduce(0) { $0 + $1.wordsProcessed }
    }

    /// Get analysis sessions count in time range
    func analysisSessions(in timeRange: TimeRange) -> Int {
        filteredSessions(for: timeRange).count
    }

    /// Get suggestions applied in time range
    func suggestionsApplied(in timeRange: TimeRange) -> Int {
        filteredActions(for: timeRange).count(where: { $0.action == .applied })
    }

    /// Get suggestions dismissed in time range
    func suggestionsDismissed(in timeRange: TimeRange) -> Int {
        filteredActions(for: timeRange).count(where: { $0.action == .dismissed })
    }

    /// Get words added to dictionary in time range
    func wordsAddedToDictionary(in timeRange: TimeRange) -> Int {
        filteredActions(for: timeRange).count(where: { $0.action == .addedToDictionary })
    }

    /// Get improvement rate in time range
    func improvementRate(in timeRange: TimeRange) -> Double {
        let applied = suggestionsApplied(in: timeRange)
        let dismissed = suggestionsDismissed(in: timeRange)
        let total = applied + dismissed
        guard total > 0 else { return 0.0 }
        return (Double(applied) / Double(total)) * 100.0
    }

    /// Get average errors per session in time range
    func averageErrorsPerSession(in timeRange: TimeRange) -> Double {
        let sessions = analysisSessions(in: timeRange)
        guard sessions > 0 else { return 0.0 }
        return Double(errorsFound(in: timeRange)) / Double(sessions)
    }

    /// Get average errors per 100 words in time range
    func averageErrorsPer100Words(in timeRange: TimeRange) -> Double {
        let words = wordsAnalyzed(in: timeRange)
        guard words > 0 else { return 0.0 }
        return (Double(errorsFound(in: timeRange)) / Double(words)) * 100.0
    }

    /// Get category breakdown for time range
    func categoryBreakdown(in timeRange: TimeRange) -> [String: Int] {
        var breakdown: [String: Int] = [:]
        for session in filteredSessions(for: timeRange) {
            for (category, count) in session.categoryBreakdown {
                breakdown[category, default: 0] += count
            }
        }
        return breakdown
    }

    /// Get app usage breakdown for time range
    func appUsageBreakdown(in timeRange: TimeRange) -> [String: Int] {
        var breakdown: [String: Int] = [:]
        for session in filteredSessions(for: timeRange) {
            if let bundleID = session.bundleIdentifier, session.errorsFound > 0 {
                breakdown[bundleID, default: 0] += session.errorsFound
            }
        }
        return breakdown
    }

    /// Get latency samples for time range
    func latencySamples(in timeRange: TimeRange) -> [Double] {
        filteredSessions(for: timeRange).map(\.latencyMs)
    }

    /// Get mean latency for time range
    func meanLatencyMs(in timeRange: TimeRange) -> Double {
        let samples = latencySamples(in: timeRange)
        guard !samples.isEmpty else { return 0.0 }
        return samples.reduce(0.0, +) / Double(samples.count)
    }

    /// Get median latency for time range
    func medianLatencyMs(in timeRange: TimeRange) -> Double {
        percentile(of: latencySamples(in: timeRange), percentile: 0.50)
    }

    /// Get P90 latency for time range
    func p90LatencyMs(in timeRange: TimeRange) -> Double {
        percentile(of: latencySamples(in: timeRange), percentile: 0.90)
    }

    /// Get P95 latency for time range
    func p95LatencyMs(in timeRange: TimeRange) -> Double {
        percentile(of: latencySamples(in: timeRange), percentile: 0.95)
    }

    /// Get P99 latency for time range
    func p99LatencyMs(in timeRange: TimeRange) -> Double {
        percentile(of: latencySamples(in: timeRange), percentile: 0.99)
    }

    /// Get most common category for time range
    func mostCommonCategory(in timeRange: TimeRange) -> String {
        let breakdown = categoryBreakdown(in: timeRange)
        guard !breakdown.isEmpty else { return "None" }
        return breakdown.max(by: { $0.value < $1.value })?.key ?? "None"
    }

    /// Get top writing app for time range
    func topWritingApp(in timeRange: TimeRange) -> (name: String, errorCount: Int)? {
        let breakdown = appUsageBreakdown(in: timeRange)
        guard !breakdown.isEmpty else { return nil }

        let topEntry = breakdown.max(by: { $0.value < $1.value })
        guard let entry = topEntry else { return nil }

        let appName = friendlyAppName(from: entry.key)
        return (appName, entry.value)
    }

    /// Get current streak (still uses activeDays, not time-filtered)
    func currentStreak(in _: TimeRange) -> Int {
        // Streak calculation doesn't really make sense with time filtering
        // Always return the full streak
        currentStreak
    }

    /// Get resource usage metrics for a time range
    func resourceUsageMetrics(in timeRange: TimeRange) -> ResourceUsageMetrics? {
        let filtered = filteredResourceSamples(for: timeRange)
        guard !filtered.isEmpty else { return nil }

        let loadValues = filtered.map(\.processLoad)
        let memoryValues = filtered.map(\.memoryBytes)

        let loadMin = loadValues.min() ?? 0
        let loadMax = loadValues.max() ?? 0
        let loadAverage = loadValues.reduce(0.0, +) / Double(loadValues.count)
        let loadMedian = median(of: loadValues)

        let memoryMin = memoryValues.min() ?? 0
        let memoryMax = memoryValues.max() ?? 0
        let memoryAverage = UInt64(memoryValues.map { Double($0) }.reduce(0.0, +) / Double(memoryValues.count))
        let memoryMedian = median(of: memoryValues)

        // Calculate system load averages if available
        let systemLoad1m = filtered.compactMap(\.systemLoad1m)
        let systemLoad5m = filtered.compactMap(\.systemLoad5m)
        let systemLoad15m = filtered.compactMap(\.systemLoad15m)

        return ResourceUsageMetrics(
            cpuLoadMin: loadMin,
            cpuLoadMax: loadMax,
            cpuLoadAverage: loadAverage,
            cpuLoadMedian: loadMedian,
            systemLoad1mAverage: systemLoad1m.isEmpty ? nil : systemLoad1m.reduce(0, +) / Double(systemLoad1m.count),
            systemLoad5mAverage: systemLoad5m.isEmpty ? nil : systemLoad5m.reduce(0, +) / Double(systemLoad5m.count),
            systemLoad15mAverage: systemLoad15m.isEmpty ? nil : systemLoad15m.reduce(0, +) / Double(systemLoad15m.count),
            memoryMin: memoryMin,
            memoryMax: memoryMax,
            memoryAverage: memoryAverage,
            memoryMedian: memoryMedian,
            sampleCount: filtered.count
        )
    }

    /// Calculate median of UInt64 values
    private func median(of values: [UInt64]) -> UInt64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            return sorted[sorted.count / 2]
        }
    }

    /// Calculate median of Double values
    private func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let sorted = values.sorted()
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            return sorted[sorted.count / 2]
        }
    }

    /// Get overall resource usage metrics (all samples, not time-filtered)
    func overallResourceUsageMetrics() -> ResourceUsageMetrics? {
        // Filter to only swiftApp component (process-level metrics)
        let filtered = resourceSamples.filter { $0.component == .swiftApp }
        guard !filtered.isEmpty else { return nil }

        let loadValues = filtered.map(\.processLoad)
        let memoryValues = filtered.map(\.memoryBytes)

        let loadMin = loadValues.min() ?? 0
        let loadMax = loadValues.max() ?? 0
        let loadAverage = loadValues.reduce(0.0, +) / Double(loadValues.count)
        let loadMedian = median(of: loadValues)

        let memoryMin = memoryValues.min() ?? 0
        let memoryMax = memoryValues.max() ?? 0
        let memoryAverage = UInt64(memoryValues.map { Double($0) }.reduce(0.0, +) / Double(memoryValues.count))
        let memoryMedian = median(of: memoryValues)

        // Calculate system load averages if available
        let systemLoad1m = filtered.compactMap(\.systemLoad1m)
        let systemLoad5m = filtered.compactMap(\.systemLoad5m)
        let systemLoad15m = filtered.compactMap(\.systemLoad15m)

        return ResourceUsageMetrics(
            cpuLoadMin: loadMin,
            cpuLoadMax: loadMax,
            cpuLoadAverage: loadAverage,
            cpuLoadMedian: loadMedian,
            systemLoad1mAverage: systemLoad1m.isEmpty ? nil : systemLoad1m.reduce(0, +) / Double(systemLoad1m.count),
            systemLoad5mAverage: systemLoad5m.isEmpty ? nil : systemLoad5m.reduce(0, +) / Double(systemLoad5m.count),
            systemLoad15mAverage: systemLoad15m.isEmpty ? nil : systemLoad15m.reduce(0, +) / Double(systemLoad15m.count),
            memoryMin: memoryMin,
            memoryMax: memoryMax,
            memoryAverage: memoryAverage,
            memoryMedian: memoryMedian,
            sampleCount: filtered.count
        )
    }

    /// Filter resource samples by time range (process-level metrics only)
    private func filteredResourceSamples(for timeRange: TimeRange) -> [ResourceMetricSample] {
        let threshold: Date = if timeRange == .session {
            appLaunchTimestamp
        } else if let date = timeRange.dateThreshold {
            date
        } else {
            Date.distantPast
        }

        // Only return swiftApp component (process-level metrics)
        return resourceSamples.filter {
            $0.component == .swiftApp && $0.timestamp >= threshold
        }
    }

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Initialize with default values first
        errorsFound = 0
        suggestionsApplied = 0
        suggestionsDismissed = 0
        wordsAddedToDictionary = 0
        wordsAnalyzed = 0
        analysisSessions = 0
        sessionCount = 0
        activeDays = []
        categoryBreakdown = [:]
        appUsageBreakdown = [:]
        latencySamples = []
        detailedSessions = []
        suggestionActions = []
        appLaunchTimestamp = Date()
        appLaunchHistory = []

        // Milestone Card defaults
        milestoneSupportClicks = 0
        milestoneDismissClicks = 0
        milestoneDisableClicks = 0

        // LLM Style Checking defaults
        styleSuggestionsShown = 0
        styleSuggestionsAccepted = 0
        styleSuggestionsRejected = 0
        styleSuggestionsIgnored = 0
        styleRejectionCategories = [:]
        styleLatencySamples = []
        detailedStyleLatencySamples = []

        // Then load saved values
        errorsFound = defaults.integer(forKey: Keys.errorsFound)
        suggestionsApplied = defaults.integer(forKey: Keys.suggestionsApplied)
        suggestionsDismissed = defaults.integer(forKey: Keys.suggestionsDismissed)
        wordsAddedToDictionary = defaults.integer(forKey: Keys.wordsAddedToDictionary)
        wordsAnalyzed = defaults.integer(forKey: Keys.wordsAnalyzed)
        analysisSessions = defaults.integer(forKey: Keys.analysisSessions)
        sessionCount = defaults.integer(forKey: Keys.sessionCount)

        if let data = defaults.data(forKey: Keys.activeDays),
           let set = try? decoder.decode(Set<Date>.self, from: data)
        {
            activeDays = set
        }

        if let data = defaults.data(forKey: Keys.categoryBreakdown),
           let dict = try? decoder.decode([String: Int].self, from: data)
        {
            categoryBreakdown = dict
        }

        if let data = defaults.data(forKey: Keys.appUsageBreakdown),
           let dict = try? decoder.decode([String: Int].self, from: data)
        {
            appUsageBreakdown = dict
        }

        if let data = defaults.data(forKey: Keys.latencySamples),
           let array = try? decoder.decode([Double].self, from: data)
        {
            latencySamples = array
        }

        // Load timestamped data
        if let data = defaults.data(forKey: Keys.detailedSessions),
           let sessions = try? decoder.decode([DetailedAnalysisSession].self, from: data)
        {
            detailedSessions = sessions
        }

        if let data = defaults.data(forKey: Keys.suggestionActions),
           let actions = try? decoder.decode([SuggestionAction].self, from: data)
        {
            suggestionActions = actions
        }

        let launchTime = defaults.double(forKey: Keys.appLaunchTimestamp)
        if launchTime > 0 {
            appLaunchTimestamp = Date(timeIntervalSince1970: launchTime)
        }

        if let data = defaults.data(forKey: Keys.appLaunchHistory),
           let history = try? decoder.decode([Date].self, from: data)
        {
            appLaunchHistory = history
        }

        // Load Milestone Card statistics
        milestoneSupportClicks = defaults.integer(forKey: Keys.milestoneSupportClicks)
        milestoneDismissClicks = defaults.integer(forKey: Keys.milestoneDismissClicks)
        milestoneDisableClicks = defaults.integer(forKey: Keys.milestoneDisableClicks)

        // Load LLM style checking statistics
        styleSuggestionsShown = defaults.integer(forKey: Keys.styleSuggestionsShown)
        styleSuggestionsAccepted = defaults.integer(forKey: Keys.styleSuggestionsAccepted)
        styleSuggestionsRejected = defaults.integer(forKey: Keys.styleSuggestionsRejected)
        styleSuggestionsIgnored = defaults.integer(forKey: Keys.styleSuggestionsIgnored)

        if let data = defaults.data(forKey: Keys.styleRejectionCategories),
           let dict = try? decoder.decode([String: Int].self, from: data)
        {
            styleRejectionCategories = dict
        }

        if let data = defaults.data(forKey: Keys.styleLatencySamples),
           let array = try? decoder.decode([Double].self, from: data)
        {
            styleLatencySamples = array
        }

        if let data = defaults.data(forKey: Keys.detailedStyleLatencySamples),
           let samples = try? decoder.decode([StyleLatencySample].self, from: data)
        {
            detailedStyleLatencySamples = samples
        }

        // Load resource monitoring data
        loadResourceSamples()
        cleanupOldResourceSamples()

        // Load log volume samples
        loadLogVolumeSamples()
        cleanupOldLogVolumeSamples()
    }

    // MARK: - Recording Methods

    /// Record a new analysis session with full details for time-based filtering
    func recordDetailedAnalysisSession(
        wordsProcessed: Int,
        errorsFound: Int,
        bundleIdentifier: String?,
        categoryBreakdown: [String: Int],
        latencyMs: Double
    ) {
        // Prevent negative values
        guard wordsProcessed >= 0, errorsFound >= 0, latencyMs >= 0 else { return }

        // Create detailed session
        let session = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: wordsProcessed,
            errorsFound: errorsFound,
            bundleIdentifier: bundleIdentifier,
            categoryBreakdown: categoryBreakdown,
            latencyMs: latencyMs
        )

        // Add to detailed sessions array
        detailedSessions.append(session)

        // Update cumulative totals (for backward compatibility)
        analysisSessions += 1
        wordsAnalyzed += wordsProcessed
        self.errorsFound += errorsFound

        // Record active day (start of day to avoid duplicates)
        let today = Calendar.current.startOfDay(for: Date())
        activeDays.insert(today)

        // Cleanup old data (older than 90 days)
        cleanupOldData()
    }

    /// Record a new analysis session (legacy method for backward compatibility)
    func recordAnalysisSession(wordsProcessed: Int, errorsFound: Int) {
        // Prevent negative values
        guard wordsProcessed >= 0, errorsFound >= 0 else { return }

        analysisSessions += 1
        wordsAnalyzed += wordsProcessed
        self.errorsFound += errorsFound

        // Record active day (start of day to avoid duplicates)
        let today = Calendar.current.startOfDay(for: Date())
        activeDays.insert(today)
    }

    /// Record a suggestion being applied
    func recordSuggestionApplied(category: String) {
        // Store timestamped action
        let action = SuggestionAction(
            timestamp: Date(),
            action: .applied,
            category: category
        )
        suggestionActions.append(action)

        // Update cumulative totals (for backward compatibility)
        suggestionsApplied += 1

        let currentCount = categoryBreakdown[category] ?? 0
        categoryBreakdown[category] = currentCount + 1

        // Cleanup old data
        cleanupOldData()
    }

    /// Record a suggestion being dismissed
    func recordSuggestionDismissed() {
        // Store timestamped action
        let action = SuggestionAction(
            timestamp: Date(),
            action: .dismissed,
            category: nil
        )
        suggestionActions.append(action)

        // Update cumulative totals (for backward compatibility)
        suggestionsDismissed += 1

        // Cleanup old data
        cleanupOldData()
    }

    /// Record a word being added to dictionary
    func recordWordAddedToDictionary() {
        // Store timestamped action
        let action = SuggestionAction(
            timestamp: Date(),
            action: .addedToDictionary,
            category: nil
        )
        suggestionActions.append(action)

        // Update cumulative totals (for backward compatibility)
        wordsAddedToDictionary += 1

        // Cleanup old data
        cleanupOldData()
    }

    /// Record a new app session (launch)
    func recordSession() {
        sessionCount += 1

        // Add current timestamp to launch history
        let now = Date()
        appLaunchHistory.append(now)

        // Keep only last 90 days of launch history
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        appLaunchHistory = appLaunchHistory.filter { $0 >= ninetyDaysAgo }
    }

    /// Record application usage for current analysis
    func recordAppUsage(bundleIdentifier: String, errorCount: Int) {
        guard errorCount > 0 else { return }
        let currentCount = appUsageBreakdown[bundleIdentifier] ?? 0
        appUsageBreakdown[bundleIdentifier] = currentCount + errorCount
    }

    /// Record grammar engine latency sample
    func recordLatency(milliseconds: Double) {
        guard milliseconds >= 0 else { return }

        latencySamples.append(milliseconds)

        // Keep only last 100 samples for rolling statistics
        if latencySamples.count > 100 {
            latencySamples.removeFirst()
        }
    }

    // MARK: - Resource Monitoring Methods

    /// Record a resource usage sample
    func recordResourceSample(_ sample: ResourceMetricSample) {
        resourceSamples.append(sample)

        // Maintain in-memory limit (keep memory bounded)
        // Note: Full dataset is in UserDefaults, this is just in-memory cache
        if resourceSamples.count > maxInMemorySamples {
            let overflow = resourceSamples.count - maxInMemorySamples
            resourceSamples.removeFirst(overflow)
        }
    }

    /// Get resource statistics for a component in a time range
    func resourceStats(
        for component: ResourceComponent,
        in timeRange: TimeRange
    ) -> ComponentResourceStats? {
        let filtered = filteredResourceSamples(for: component, in: timeRange)
        guard !filtered.isEmpty else { return nil }

        let cpuValues = filtered.map(\.cpuPercent).sorted()
        let memValues = filtered.map(\.memoryBytes).sorted()

        let loadAvgs = cpuLoadAverages(for: component)

        return ComponentResourceStats(
            component: component,
            cpuMean: cpuValues.mean(),
            cpuMedian: cpuValues.median(),
            cpuP90: cpuValues.percentile(90),
            cpuP95: cpuValues.percentile(95),
            cpuP99: cpuValues.percentile(99),
            cpuMax: cpuValues.max() ?? 0,
            memoryMean: UInt64(memValues.map { Double($0) }.mean()),
            memoryMedian: memValues.median(),
            memoryP90: memValues.percentile(90),
            memoryP95: memValues.percentile(95),
            memoryP99: memValues.percentile(99),
            memoryMax: memValues.max() ?? 0,
            memoryPeak: filtered.compactMap(\.memoryPeakBytes).max() ?? 0,
            cpuLoad1m: loadAvgs.load1m,
            cpuLoad5m: loadAvgs.load5m,
            cpuLoad15m: loadAvgs.load15m,
            sampleCount: filtered.count
        )
    }

    /// Calculate CPU load averages (1m, 5m, 15m) for a component
    func cpuLoadAverages(
        for component: ResourceComponent
    ) -> (load1m: Double, load5m: Double, load15m: Double) {
        let now = Date()

        let samples1m = resourceSamples
            .filter { $0.component == component && now.timeIntervalSince($0.timestamp) <= 60 }
        let samples5m = resourceSamples
            .filter { $0.component == component && now.timeIntervalSince($0.timestamp) <= 300 }
        let samples15m = resourceSamples
            .filter { $0.component == component && now.timeIntervalSince($0.timestamp) <= 900 }

        return (
            load1m: samples1m.map(\.cpuPercent).mean(),
            load5m: samples5m.map(\.cpuPercent).mean(),
            load15m: samples15m.map(\.cpuPercent).mean()
        )
    }

    /// Filter resource samples by component and time range
    private func filteredResourceSamples(
        for component: ResourceComponent,
        in timeRange: TimeRange
    ) -> [ResourceMetricSample] {
        let threshold: Date = if timeRange == .session {
            appLaunchTimestamp
        } else if let date = timeRange.dateThreshold {
            date
        } else {
            Date.distantPast
        }

        return resourceSamples.filter {
            $0.component == component && $0.timestamp >= threshold
        }
    }

    /// Persist resource samples to UserDefaults (batched to reduce overhead)
    private func persistResourceSamples() {
        persistBatchCounter += 1

        // Only save every 10 samples to reduce disk I/O
        guard persistBatchCounter >= 10 else { return }
        persistBatchCounter = 0

        // Capture @Published property on main thread to create snapshot
        let samplesToEncode = resourceSamples

        DispatchQueue.global(qos: .utility).async {
            do {
                // Create local encoder to avoid sharing across threads
                let encoder = JSONEncoder()
                let encoded = try encoder.encode(samplesToEncode)
                // UserDefaults.standard is thread-safe
                UserDefaults.standard.set(encoded, forKey: Keys.resourceSamples)
            } catch {
                Logger.warning("Failed to persist resource samples: \(error.localizedDescription)", category: Logger.performance)
            }
        }
    }

    /// Load resource samples from UserDefaults
    private func loadResourceSamples() {
        guard let data = defaults.data(forKey: Keys.resourceSamples),
              let decoded = try? decoder.decode([ResourceMetricSample].self, from: data)
        else {
            return
        }
        resourceSamples = decoded
    }

    /// Clean up resource samples older than 30 days
    private func cleanupOldResourceSamples() {
        let cutoffDate = Date(timeIntervalSinceNow: -maxResourceAge)
        let before = resourceSamples.count
        resourceSamples.removeAll { $0.timestamp < cutoffDate }

        if before != resourceSamples.count {
            let removed = before - resourceSamples.count
            Logger.debug("ResourceMonitor: Cleaned up \(removed) samples older than 30 days", category: Logger.performance)
        }
    }

    /// Perform periodic cleanup (call on app launch)
    func performPeriodicCleanup() {
        cleanupOldData() // Existing 90-day cleanup
        cleanupOldResourceSamples() // New 30-day cleanup for resource samples
        cleanupOldLogVolumeSamples() // 30-day cleanup for log volume samples
    }

    // MARK: - Log Volume Methods

    /// Record a log event at the given level
    /// Call this from Logger for each log message
    func recordLog(level: LogLevel) {
        let now = Date()

        // Check if we need to finalize the current sample and start a new one
        if let current = currentLogSample {
            let elapsed = now.timeIntervalSince(current.timestamp)
            if elapsed >= logSampleInterval {
                // Finalize current sample
                logVolumeSamples.append(current)
                currentLogSample = nil
            }
        }

        // Create new sample if needed
        if currentLogSample == nil {
            currentLogSample = LogVolumeSample(timestamp: now)
        }

        // Increment the appropriate counter
        switch level {
        case .trace:
            currentLogSample?.trace += 1
        case .debug:
            currentLogSample?.debug += 1
        case .info:
            currentLogSample?.info += 1
        case .warning:
            currentLogSample?.warning += 1
        case .error:
            currentLogSample?.error += 1
        case .critical:
            currentLogSample?.critical += 1
        }
    }

    /// Flush current log sample (call periodically or on app termination)
    func flushLogSample() {
        guard let current = currentLogSample, current.total > 0 else { return }
        logVolumeSamples.append(current)
        currentLogSample = nil
    }

    /// Load log volume samples from UserDefaults
    private func loadLogVolumeSamples() {
        guard let data = defaults.data(forKey: Keys.logVolumeSamples),
              let decoded = try? decoder.decode([LogVolumeSample].self, from: data)
        else {
            return
        }
        logVolumeSamples = decoded
    }

    /// Persist log volume samples to UserDefaults (batched, background queue)
    private func persistLogVolumeSamples() {
        logPersistBatchCounter += 1
        // Persist every 10 samples to avoid too frequent writes
        guard logPersistBatchCounter >= 10 else { return }
        logPersistBatchCounter = 0

        // Capture @Published property on main thread to create snapshot
        let samplesToEncode = logVolumeSamples

        DispatchQueue.global(qos: .utility).async {
            do {
                let encoder = JSONEncoder()
                let encoded = try encoder.encode(samplesToEncode)
                UserDefaults.standard.set(encoded, forKey: Keys.logVolumeSamples)
            } catch {
                Logger.warning("Failed to persist log volume samples: \(error.localizedDescription)", category: Logger.performance)
            }
        }
    }

    /// Force persist log volume samples (for app termination)
    func forceLogVolumePersist() {
        // Synchronous persist for app termination
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(logVolumeSamples)
            UserDefaults.standard.set(encoded, forKey: Keys.logVolumeSamples)
        } catch {
            Logger.warning("Failed to force persist log volume samples: \(error.localizedDescription)", category: Logger.performance)
        }
    }

    /// Clean up log volume samples older than 30 days
    private func cleanupOldLogVolumeSamples() {
        let cutoffDate = Date(timeIntervalSinceNow: -maxResourceAge)
        let before = logVolumeSamples.count
        logVolumeSamples.removeAll { $0.timestamp < cutoffDate }

        if before != logVolumeSamples.count {
            let removed = before - logVolumeSamples.count
            Logger.debug("LogVolume: Cleaned up \(removed) samples older than 30 days", category: Logger.performance)
        }
    }

    /// Get log volume samples filtered by ResourceTimeRange (for ResourceMonitoringView)
    func logVolumeSamples(inMinutes minutes: Int) -> [LogVolumeSample] {
        let cutoffDate = Calendar.current.date(byAdding: .minute, value: -minutes, to: Date()) ?? Date.distantPast
        return logVolumeSamples.filter { $0.timestamp >= cutoffDate }
    }

    /// Total log count across all severities for the time range
    func totalLogCount(inMinutes minutes: Int) -> Int {
        logVolumeSamples(inMinutes: minutes).reduce(0) { $0 + $1.total }
    }

    /// Log count by severity for the time range
    func logCountBySeverity(inMinutes minutes: Int) -> (trace: Int, debug: Int, info: Int, warning: Int, error: Int, critical: Int) {
        let samples = logVolumeSamples(inMinutes: minutes)
        return (
            trace: samples.reduce(0) { $0 + $1.trace },
            debug: samples.reduce(0) { $0 + $1.debug },
            info: samples.reduce(0) { $0 + $1.info },
            warning: samples.reduce(0) { $0 + $1.warning },
            error: samples.reduce(0) { $0 + $1.error },
            critical: samples.reduce(0) { $0 + $1.critical }
        )
    }

    // MARK: - Helper Methods

    /// Clean up data older than 90 days
    private func cleanupOldData() {
        guard let threshold = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else {
            return
        }

        // Remove old analysis sessions
        detailedSessions.removeAll { $0.timestamp < threshold }

        // Remove old suggestion actions
        suggestionActions.removeAll { $0.timestamp < threshold }

        // Note: latencySamples is already capped at 100, no need to clean up by date
    }

    /// Calculate percentile from sorted samples
    private func percentile(of samples: [Double], percentile: Double) -> Double {
        guard !samples.isEmpty else { return 0.0 }
        guard percentile >= 0.0, percentile <= 1.0 else { return 0.0 }

        let sorted = samples.sorted()
        let index = Int(Double(sorted.count - 1) * percentile)
        return sorted[index]
    }

    /// Convert bundle ID to friendly app name
    func friendlyAppName(from bundleID: String) -> String {
        // Map common bundle IDs to friendly names
        let knownApps: [String: String] = [
            // Apple Apps
            "com.apple.MobileSMS": "Messages",
            "com.apple.mail": "Mail",
            "com.apple.Safari": "Safari",
            "com.apple.Notes": "Notes",
            "com.apple.reminders": "Reminders",
            "com.apple.iCal": "Calendar",
            "com.apple.TextEdit": "TextEdit",
            "com.apple.Terminal": "Terminal",
            "com.apple.dt.Xcode": "Xcode",
            "com.apple.iWork.Pages": "Pages",
            "com.apple.iWork.Numbers": "Numbers",
            "com.apple.iWork.Keynote": "Keynote",
            "com.apple.finder": "Finder",

            // Microsoft Apps
            "com.microsoft.Word": "Word",
            "com.microsoft.Excel": "Excel",
            "com.microsoft.Powerpoint": "PowerPoint",
            "com.microsoft.Outlook": "Outlook",
            "com.microsoft.onenote.mac": "OneNote",
            "com.microsoft.teams2": "Teams",
            "com.microsoft.VSCode": "VS Code",
            "com.microsoft.edgemac": "Edge",

            // Google Apps
            "com.google.Chrome": "Chrome",
            "com.google.Chrome.canary": "Chrome Canary",

            // Other Popular Apps
            "com.tinyspeck.slackmacgap": "Slack",
            "com.notion.id": "Notion",
            "notion.id": "Notion",
            "com.linear": "Linear",
            "com.figma.Desktop": "Figma",
            "net.whatsapp.WhatsApp": "WhatsApp",
            "com.hnc.Discord": "Discord",
            "ru.keepcoder.Telegram": "Telegram",
            "com.facebook.Messenger": "Messenger",
            "us.zoom.xos": "Zoom",
            "com.webex.meetingmanager": "Webex",
            "com.agilebits.onepassword7": "1Password",
            "com.todoist.mac.Todoist": "Todoist",
            "com.readdle.smartemail-Mac": "Spark",
            "com.postbox-inc.postbox": "Postbox",
            "org.mozilla.firefox": "Firefox",
            "company.thebrowser.Browser": "Arc",
            "com.operasoftware.Opera": "Opera",
            "com.brave.Browser": "Brave",
            "com.sublimetext.4": "Sublime Text",
            "com.jetbrains.intellij": "IntelliJ",
            "com.jetbrains.pycharm": "PyCharm",
            "com.jetbrains.WebStorm": "WebStorm",
            "com.github.atom": "Atom",
            "com.obsproject.obs-studio": "OBS",
            "com.spotify.client": "Spotify",
        ]

        // Try exact match first
        if let name = knownApps[bundleID] {
            return name
        }

        // Fallback: extract last component and capitalize
        let lastComponent = bundleID.components(separatedBy: ".").last ?? bundleID
        return lastComponent.capitalized
    }

    /// Convert model ID to user-friendly display name
    func modelDisplayName(from modelId: String) -> String {
        if modelId == "apple-foundation-models" {
            return "Apple Intelligence"
        }
        return modelId
    }

    // MARK: - LLM Style Checking Recording

    /// Record style suggestions shown in an analysis session with model and preset context
    func recordStyleSuggestions(count: Int, latencyMs: Double, modelId: String, preset: String) {
        guard count >= 0, latencyMs >= 0 else { return }

        styleSuggestionsShown += count

        // Add to legacy array (keep last 100)
        styleLatencySamples.append(latencyMs)
        if styleLatencySamples.count > 100 {
            styleLatencySamples.removeFirst()
        }

        // Add to detailed samples with model/preset context (keep last 500)
        let sample = StyleLatencySample(
            timestamp: Date(),
            modelId: modelId,
            preset: preset.lowercased(),
            latencyMs: latencyMs
        )
        detailedStyleLatencySamples.append(sample)
        if detailedStyleLatencySamples.count > 500 {
            detailedStyleLatencySamples.removeFirst()
        }
    }

    // MARK: - Style Latency Query Methods

    /// Constant model ID for Apple Intelligence (no longer using downloadable models)
    private static let appleIntelligenceModelId = "apple-intelligence"

    /// Get unique model IDs that have latency data
    var modelsWithLatencyData: [String] {
        var modelIds = Set(detailedStyleLatencySamples.map(\.modelId))
        // Always include Apple Intelligence so it appears in the dropdown
        modelIds.insert(Self.appleIntelligenceModelId)
        return Array(modelIds).sorted()
    }

    /// Get latency samples filtered by model
    func styleLatencySamples(forModel modelId: String) -> [StyleLatencySample] {
        detailedStyleLatencySamples.filter { $0.modelId == modelId }
    }

    /// Get latency samples filtered by model and preset
    func styleLatencySamples(forModel modelId: String, preset: String) -> [Double] {
        detailedStyleLatencySamples
            .filter { $0.modelId == modelId && $0.preset == preset.lowercased() }
            .map(\.latencyMs)
    }

    /// Get average latency for a model and preset combination
    func averageStyleLatency(forModel modelId: String, preset: String) -> Double {
        let samples = styleLatencySamples(forModel: modelId, preset: preset)
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    /// Get median latency for a model and preset combination
    func medianStyleLatency(forModel modelId: String, preset: String) -> Double {
        let samples = styleLatencySamples(forModel: modelId, preset: preset)
        return percentile(of: samples, percentile: 0.50)
    }

    /// Get P90 latency for a model and preset combination
    func p90StyleLatency(forModel modelId: String, preset: String) -> Double {
        let samples = styleLatencySamples(forModel: modelId, preset: preset)
        return percentile(of: samples, percentile: 0.90)
    }

    /// Get P95 latency for a model and preset combination
    func p95StyleLatency(forModel modelId: String, preset: String) -> Double {
        let samples = styleLatencySamples(forModel: modelId, preset: preset)
        return percentile(of: samples, percentile: 0.95)
    }

    /// Get P99 latency for a model and preset combination
    func p99StyleLatency(forModel modelId: String, preset: String) -> Double {
        let samples = styleLatencySamples(forModel: modelId, preset: preset)
        return percentile(of: samples, percentile: 0.99)
    }

    /// Get sample count for a model and preset combination
    func sampleCount(forModel modelId: String, preset: String) -> Int {
        styleLatencySamples(forModel: modelId, preset: preset).count
    }

    /// Check if a model has any data for a specific preset
    func hasData(forModel modelId: String, preset: String) -> Bool {
        !styleLatencySamples(forModel: modelId, preset: preset).isEmpty
    }

    /// Record a style suggestion acceptance
    func recordStyleAcceptance() {
        styleSuggestionsAccepted += 1
    }

    /// Record a style suggestion rejection with category
    func recordStyleRejection(category: String) {
        styleSuggestionsRejected += 1
        styleRejectionCategories[category, default: 0] += 1
    }

    /// Record a style suggestion being ignored (dismissed without accept/reject)
    func recordStyleIgnored() {
        styleSuggestionsIgnored += 1
    }

    /// Style suggestion acceptance rate (0-100)
    var styleAcceptanceRate: Double {
        let total = styleSuggestionsAccepted + styleSuggestionsRejected
        guard total > 0 else { return 0.0 }
        return (Double(styleSuggestionsAccepted) / Double(total)) * 100.0
    }

    /// Average LLM analysis latency in milliseconds
    var averageStyleLatency: Double {
        guard !styleLatencySamples.isEmpty else { return 0 }
        return styleLatencySamples.reduce(0, +) / Double(styleLatencySamples.count)
    }

    /// Median LLM latency in milliseconds
    var medianStyleLatencyMs: Double {
        percentile(of: styleLatencySamples, percentile: 0.50)
    }

    /// P90 LLM latency in milliseconds
    var p90StyleLatencyMs: Double {
        percentile(of: styleLatencySamples, percentile: 0.90)
    }

    /// P95 LLM latency in milliseconds
    var p95StyleLatencyMs: Double {
        percentile(of: styleLatencySamples, percentile: 0.95)
    }

    /// P99 LLM latency in milliseconds
    var p99StyleLatencyMs: Double {
        percentile(of: styleLatencySamples, percentile: 0.99)
    }

    /// Number of LLM analysis runs (total evaluations)
    var llmAnalysisRuns: Int {
        styleLatencySamples.count
    }

    // MARK: - Reset

    /// Reset all statistics to zero
    func resetAllStatistics() {
        errorsFound = 0
        suggestionsApplied = 0
        suggestionsDismissed = 0
        wordsAddedToDictionary = 0
        wordsAnalyzed = 0
        analysisSessions = 0
        sessionCount = 0
        activeDays = []
        categoryBreakdown = [:]
        appUsageBreakdown = [:]
        latencySamples = []
        detailedSessions = []
        suggestionActions = []
        appLaunchTimestamp = Date()

        // Reset milestone card statistics
        milestoneSupportClicks = 0
        milestoneDismissClicks = 0
        milestoneDisableClicks = 0

        // Reset style statistics
        styleSuggestionsShown = 0
        styleSuggestionsAccepted = 0
        styleSuggestionsRejected = 0
        styleSuggestionsIgnored = 0
        styleRejectionCategories = [:]
        styleLatencySamples = []
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let errorsFound = "statistics.errorsFound"
        static let suggestionsApplied = "statistics.suggestionsApplied"
        static let suggestionsDismissed = "statistics.suggestionsDismissed"
        static let wordsAddedToDictionary = "statistics.wordsAddedToDictionary"
        static let wordsAnalyzed = "statistics.wordsAnalyzed"
        static let analysisSessions = "statistics.analysisSessions"
        static let sessionCount = "statistics.sessionCount"
        static let activeDays = "statistics.activeDays"
        static let categoryBreakdown = "statistics.categoryBreakdown"
        static let appUsageBreakdown = "statistics.appUsageBreakdown"
        static let latencySamples = "statistics.latencySamples"
        static let detailedSessions = "statistics.detailedSessions"
        static let suggestionActions = "statistics.suggestionActions"
        static let appLaunchTimestamp = "statistics.appLaunchTimestamp"
        static let appLaunchHistory = "statistics.appLaunchHistory"
        static let resourceSamples = "statistics.resourceSamples"
        static let logVolumeSamples = "statistics.logVolumeSamples"

        // Milestone Card
        static let milestoneSupportClicks = "statistics.milestoneSupportClicks"
        static let milestoneDismissClicks = "statistics.milestoneDismissClicks"
        static let milestoneDisableClicks = "statistics.milestoneDisableClicks"

        // LLM Style Checking
        static let styleSuggestionsShown = "statistics.styleSuggestionsShown"
        static let styleSuggestionsAccepted = "statistics.styleSuggestionsAccepted"
        static let styleSuggestionsRejected = "statistics.styleSuggestionsRejected"
        static let styleSuggestionsIgnored = "statistics.styleSuggestionsIgnored"
        static let styleRejectionCategories = "statistics.styleRejectionCategories"
        static let styleLatencySamples = "statistics.styleLatencySamples"
        static let detailedStyleLatencySamples = "statistics.detailedStyleLatencySamples"
    }
}
