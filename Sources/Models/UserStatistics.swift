//
//  UserStatistics.swift
//  TextWarden
//
//  User statistics tracking with UserDefaults persistence
//

import Foundation
import Combine

/// Observable user statistics for tracking usage and improvements
class UserStatistics: ObservableObject {
    static let shared = UserStatistics()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
            if let encoded = try? encoder.encode(activeDays) {
                defaults.set(encoded, forKey: Keys.activeDays)
            }
        }
    }

    /// Breakdown of errors by category
    @Published var categoryBreakdown: [String: Int] {
        didSet {
            if let encoded = try? encoder.encode(categoryBreakdown) {
                defaults.set(encoded, forKey: Keys.categoryBreakdown)
            }
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

    /// Most frequently occurring error category
    var mostCommonCategory: String {
        guard !categoryBreakdown.isEmpty else { return "None" }
        return categoryBreakdown.max(by: { $0.value < $1.value })?.key ?? "None"
    }

    /// Estimated time saved in seconds (2 seconds per applied suggestion)
    var timeSavedInSeconds: Int {
        return suggestionsApplied * 2
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
        return UserPreferences.shared.customDictionary.count
    }

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Initialize with default values first
        self.errorsFound = 0
        self.suggestionsApplied = 0
        self.suggestionsDismissed = 0
        self.wordsAnalyzed = 0
        self.analysisSessions = 0
        self.sessionCount = 0
        self.activeDays = []
        self.categoryBreakdown = [:]

        // Then load saved values
        self.errorsFound = defaults.integer(forKey: Keys.errorsFound)
        self.suggestionsApplied = defaults.integer(forKey: Keys.suggestionsApplied)
        self.suggestionsDismissed = defaults.integer(forKey: Keys.suggestionsDismissed)
        self.wordsAnalyzed = defaults.integer(forKey: Keys.wordsAnalyzed)
        self.analysisSessions = defaults.integer(forKey: Keys.analysisSessions)
        self.sessionCount = defaults.integer(forKey: Keys.sessionCount)

        if let data = defaults.data(forKey: Keys.activeDays),
           let set = try? decoder.decode(Set<Date>.self, from: data) {
            self.activeDays = set
        }

        if let data = defaults.data(forKey: Keys.categoryBreakdown),
           let dict = try? decoder.decode([String: Int].self, from: data) {
            self.categoryBreakdown = dict
        }
    }

    // MARK: - Recording Methods

    /// Record a new analysis session
    func recordAnalysisSession(wordsProcessed: Int, errorsFound: Int) {
        // Prevent negative values
        guard wordsProcessed >= 0, errorsFound >= 0 else { return }

        self.analysisSessions += 1
        self.wordsAnalyzed += wordsProcessed
        self.errorsFound += errorsFound

        // Record active day (start of day to avoid duplicates)
        let today = Calendar.current.startOfDay(for: Date())
        self.activeDays.insert(today)
    }

    /// Record a suggestion being applied
    func recordSuggestionApplied(category: String) {
        self.suggestionsApplied += 1

        let currentCount = categoryBreakdown[category] ?? 0
        categoryBreakdown[category] = currentCount + 1
    }

    /// Record a suggestion being dismissed
    func recordSuggestionDismissed() {
        self.suggestionsDismissed += 1
    }

    /// Record a new app session (launch)
    func recordSession() {
        self.sessionCount += 1
    }

    // MARK: - Reset

    /// Reset all statistics to zero
    func resetAllStatistics() {
        errorsFound = 0
        suggestionsApplied = 0
        suggestionsDismissed = 0
        wordsAnalyzed = 0
        analysisSessions = 0
        sessionCount = 0
        activeDays = []
        categoryBreakdown = [:]
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let errorsFound = "statistics.errorsFound"
        static let suggestionsApplied = "statistics.suggestionsApplied"
        static let suggestionsDismissed = "statistics.suggestionsDismissed"
        static let wordsAnalyzed = "statistics.wordsAnalyzed"
        static let analysisSessions = "statistics.analysisSessions"
        static let sessionCount = "statistics.sessionCount"
        static let activeDays = "statistics.activeDays"
        static let categoryBreakdown = "statistics.categoryBreakdown"
    }
}
