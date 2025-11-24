//
//  UserStatisticsTests.swift
//  TextWarden
//
//  Unit tests for UserStatistics model
//

import XCTest
@testable import TextWarden

final class UserStatisticsTests: XCTestCase {
    var statistics: UserStatistics!

    override func setUp() {
        super.setUp()
        // Use a separate UserDefaults suite for testing to avoid affecting real data
        statistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)
        statistics.resetAllStatistics()
    }

    override func tearDown() {
        statistics.resetAllStatistics()
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialStatisticsAreZero() {
        XCTAssertEqual(statistics.errorsFound, 0)
        XCTAssertEqual(statistics.suggestionsApplied, 0)
        XCTAssertEqual(statistics.suggestionsDismissed, 0)
        XCTAssertEqual(statistics.wordsAnalyzed, 0)
        XCTAssertEqual(statistics.analysisSessions, 0)
        XCTAssertEqual(statistics.sessionCount, 0)
        XCTAssertEqual(statistics.activeDays.count, 0)
    }

    // MARK: - Recording Tests

    func testRecordAnalysisSession() {
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 5)

        XCTAssertEqual(statistics.analysisSessions, 1)
        XCTAssertEqual(statistics.wordsAnalyzed, 100)
        XCTAssertEqual(statistics.errorsFound, 5)
    }

    func testRecordMultipleAnalysisSessions() {
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 5)
        statistics.recordAnalysisSession(wordsProcessed: 200, errorsFound: 10)

        XCTAssertEqual(statistics.analysisSessions, 2)
        XCTAssertEqual(statistics.wordsAnalyzed, 300)
        XCTAssertEqual(statistics.errorsFound, 15)
    }

    func testRecordSuggestionApplied() {
        statistics.recordSuggestionApplied(category: "Spelling")

        XCTAssertEqual(statistics.suggestionsApplied, 1)
        XCTAssertEqual(statistics.categoryBreakdown["Spelling"], 1)
    }

    func testRecordSuggestionDismissed() {
        statistics.recordSuggestionDismissed()

        XCTAssertEqual(statistics.suggestionsDismissed, 1)
    }

    func testRecordCategoryBreakdown() {
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionApplied(category: "Grammar")
        statistics.recordSuggestionApplied(category: "Spelling")

        XCTAssertEqual(statistics.categoryBreakdown["Spelling"], 2)
        XCTAssertEqual(statistics.categoryBreakdown["Grammar"], 1)
    }

    func testRecordSession() {
        let initialCount = statistics.sessionCount
        statistics.recordSession()

        XCTAssertEqual(statistics.sessionCount, initialCount + 1)
    }

    func testRecordActiveDays() {
        let today = Calendar.current.startOfDay(for: Date())

        statistics.recordAnalysisSession(wordsProcessed: 10, errorsFound: 1)

        XCTAssertTrue(statistics.activeDays.contains(today))
        XCTAssertEqual(statistics.activeDays.count, 1)
    }

    func testRecordActiveDaysDoesNotDuplicate() {
        statistics.recordAnalysisSession(wordsProcessed: 10, errorsFound: 1)
        statistics.recordAnalysisSession(wordsProcessed: 20, errorsFound: 2)

        // Should still be 1 day since both sessions are on the same day
        XCTAssertEqual(statistics.activeDays.count, 1)
    }

    // MARK: - Computed Properties Tests

    func testImprovementRate() {
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionApplied(category: "Grammar")
        statistics.recordSuggestionDismissed()
        statistics.recordSuggestionDismissed()

        // 2 applied out of 4 total = 50%
        XCTAssertEqual(statistics.improvementRate, 50.0, accuracy: 0.01)
    }

    func testImprovementRateWithNoSuggestions() {
        XCTAssertEqual(statistics.improvementRate, 0.0)
    }

    func testImprovementRateWithAllApplied() {
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionApplied(category: "Grammar")

        XCTAssertEqual(statistics.improvementRate, 100.0)
    }

    func testAverageErrorsPerSession() {
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 10)
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 20)

        XCTAssertEqual(statistics.averageErrorsPerSession, 15.0)
    }

    func testAverageErrorsPerSessionWithNoSessions() {
        XCTAssertEqual(statistics.averageErrorsPerSession, 0.0)
    }

    func testMostCommonCategory() {
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionApplied(category: "Grammar")
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionApplied(category: "Spelling")

        XCTAssertEqual(statistics.mostCommonCategory, "Spelling")
    }

    func testMostCommonCategoryWithNoCategories() {
        XCTAssertEqual(statistics.mostCommonCategory, "None")
    }

    func testTimeSavedInSeconds() {
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionApplied(category: "Grammar")

        // 2 applied * 2 seconds = 4 seconds
        XCTAssertEqual(statistics.timeSavedInSeconds, 4)
    }

    func testTimeSavedFormatted() {
        // 65 seconds = 1m 5s
        for _ in 0..<32 {
            statistics.recordSuggestionApplied(category: "Spelling")
        }
        statistics.recordSuggestionApplied(category: "Grammar")

        XCTAssertEqual(statistics.timeSavedFormatted, "1m 6s")
    }

    func testTimeSavedFormattedWithHours() {
        // 3661 seconds = 1h 1m 1s
        for _ in 0..<1830 {
            statistics.recordSuggestionApplied(category: "Spelling")
        }
        statistics.recordSuggestionApplied(category: "Grammar")

        XCTAssertTrue(statistics.timeSavedFormatted.contains("h"))
    }

    // MARK: - Persistence Tests

    func testStatisticsPersistence() {
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 5)
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSession()

        // Create a new instance with the same UserDefaults suite
        let newStatistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)

        XCTAssertEqual(newStatistics.analysisSessions, 1)
        XCTAssertEqual(newStatistics.wordsAnalyzed, 100)
        XCTAssertEqual(newStatistics.errorsFound, 5)
        XCTAssertEqual(newStatistics.suggestionsApplied, 1)
        XCTAssertEqual(newStatistics.sessionCount, 1)
    }

    func testCategoryBreakdownPersistence() {
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionApplied(category: "Grammar")

        let newStatistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)

        XCTAssertEqual(newStatistics.categoryBreakdown["Spelling"], 1)
        XCTAssertEqual(newStatistics.categoryBreakdown["Grammar"], 1)
    }

    func testActiveDaysPersistence() {
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 5)

        let newStatistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)

        XCTAssertEqual(newStatistics.activeDays.count, 1)
    }

    // MARK: - Reset Tests

    func testResetAllStatistics() {
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 5)
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionDismissed()
        statistics.recordSession()

        statistics.resetAllStatistics()

        XCTAssertEqual(statistics.errorsFound, 0)
        XCTAssertEqual(statistics.suggestionsApplied, 0)
        XCTAssertEqual(statistics.suggestionsDismissed, 0)
        XCTAssertEqual(statistics.wordsAnalyzed, 0)
        XCTAssertEqual(statistics.analysisSessions, 0)
        XCTAssertEqual(statistics.sessionCount, 0)
        XCTAssertEqual(statistics.activeDays.count, 0)
        XCTAssertEqual(statistics.categoryBreakdown.count, 0)
    }

    // MARK: - Edge Cases

    func testNegativeValuesAreNotRecorded() {
        statistics.recordAnalysisSession(wordsProcessed: -10, errorsFound: -5)

        XCTAssertEqual(statistics.wordsAnalyzed, 0)
        XCTAssertEqual(statistics.errorsFound, 0)
    }

    func testLargeNumbers() {
        statistics.recordAnalysisSession(wordsProcessed: 1_000_000, errorsFound: 10_000)

        XCTAssertEqual(statistics.wordsAnalyzed, 1_000_000)
        XCTAssertEqual(statistics.errorsFound, 10_000)
    }

    // MARK: - Detailed Analysis Session Tests

    func testRecordDetailedAnalysisSession() {
        let categoryBreakdown = ["Spelling": 2, "Grammar": 3]

        statistics.recordDetailedAnalysisSession(
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.apple.Safari",
            categoryBreakdown: categoryBreakdown,
            latencyMs: 50.5
        )

        // Check cumulative totals
        XCTAssertEqual(statistics.analysisSessions, 1)
        XCTAssertEqual(statistics.wordsAnalyzed, 100)
        XCTAssertEqual(statistics.errorsFound, 5)

        // Check detailed sessions array
        XCTAssertEqual(statistics.detailedSessions.count, 1)

        let session = statistics.detailedSessions[0]
        XCTAssertEqual(session.wordsProcessed, 100)
        XCTAssertEqual(session.errorsFound, 5)
        XCTAssertEqual(session.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(session.categoryBreakdown, categoryBreakdown)
        XCTAssertEqual(session.latencyMs, 50.5)

        // Check active days
        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertTrue(statistics.activeDays.contains(today))
    }

    func testRecordDetailedAnalysisSessionWithNegativeValues() {
        statistics.recordDetailedAnalysisSession(
            wordsProcessed: -10,
            errorsFound: -5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: -10
        )

        // Should not record negative values
        XCTAssertEqual(statistics.analysisSessions, 0)
        XCTAssertEqual(statistics.detailedSessions.count, 0)
    }

    func testRecordMultipleDetailedAnalysisSessions() {
        statistics.recordDetailedAnalysisSession(
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.apple.Safari",
            categoryBreakdown: ["Spelling": 5],
            latencyMs: 50.0
        )

        statistics.recordDetailedAnalysisSession(
            wordsProcessed: 200,
            errorsFound: 10,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            categoryBreakdown: ["Grammar": 10],
            latencyMs: 75.0
        )

        XCTAssertEqual(statistics.detailedSessions.count, 2)
        XCTAssertEqual(statistics.analysisSessions, 2)
        XCTAssertEqual(statistics.wordsAnalyzed, 300)
        XCTAssertEqual(statistics.errorsFound, 15)
    }

    // MARK: - Timestamped Suggestion Action Tests

    func testRecordSuggestionAppliedWithTimestamp() {
        statistics.recordSuggestionApplied(category: "Spelling")

        XCTAssertEqual(statistics.suggestionActions.count, 1)

        let action = statistics.suggestionActions[0]
        XCTAssertEqual(action.action, .applied)
        XCTAssertEqual(action.category, "Spelling")

        // Check cumulative total
        XCTAssertEqual(statistics.suggestionsApplied, 1)
    }

    func testRecordSuggestionDismissedWithTimestamp() {
        statistics.recordSuggestionDismissed()

        XCTAssertEqual(statistics.suggestionActions.count, 1)

        let action = statistics.suggestionActions[0]
        XCTAssertEqual(action.action, .dismissed)
        XCTAssertNil(action.category)

        // Check cumulative total
        XCTAssertEqual(statistics.suggestionsDismissed, 1)
    }

    func testRecordWordAddedToDictionary() {
        statistics.recordWordAddedToDictionary()

        XCTAssertEqual(statistics.suggestionActions.count, 1)

        let action = statistics.suggestionActions[0]
        XCTAssertEqual(action.action, .addedToDictionary)
        XCTAssertNil(action.category)

        // Check cumulative total
        XCTAssertEqual(statistics.wordsAddedToDictionary, 1)
    }

    // MARK: - Time-Filtered Statistics Tests

    func testFilteredSessionsForCurrentSession() {
        // Set app launch timestamp to 1 hour ago
        let oneHourAgo = Date().addingTimeInterval(-3600)
        statistics.appLaunchTimestamp = oneHourAgo

        // Add session from 30 minutes ago (should be included)
        let thirtyMinutesAgo = Date().addingTimeInterval(-1800)
        let recentSession = DetailedAnalysisSession(
            timestamp: thirtyMinutesAgo,
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: ["Spelling": 5],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(recentSession)

        // Add session from 2 hours ago (should be excluded)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        let oldSession = DetailedAnalysisSession(
            timestamp: twoHoursAgo,
            wordsProcessed: 200,
            errorsFound: 10,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: ["Grammar": 10],
            latencyMs: 100.0
        )
        statistics.detailedSessions.append(oldSession)

        // Filter for current session
        let filtered = statistics.filteredSessions(for: .session)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].wordsProcessed, 100)
    }

    func testFilteredActionsForTimeRange() {
        // Add action from now
        let nowAction = SuggestionAction(
            timestamp: Date(),
            action: .applied,
            category: "Spelling"
        )
        statistics.suggestionActions.append(nowAction)

        // Add action from 8 days ago (should be excluded from 7-day filter)
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        let oldAction = SuggestionAction(
            timestamp: eightDaysAgo,
            action: .dismissed,
            category: nil
        )
        statistics.suggestionActions.append(oldAction)

        // Filter for last 7 days
        let filtered = statistics.filteredActions(for: .week)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].action, .applied)
    }

    func testErrorsFoundInTimeRange() {
        // Add session from today
        let todaySession = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: ["Spelling": 5],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(todaySession)

        // Add session from 8 days ago
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        let oldSession = DetailedAnalysisSession(
            timestamp: eightDaysAgo,
            wordsProcessed: 100,
            errorsFound: 10,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: ["Grammar": 10],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(oldSession)

        // Check errors in last 7 days (should only include today's session)
        let errorsInWeek = statistics.errorsFound(in: .week)
        XCTAssertEqual(errorsInWeek, 5)

        // Check errors in last 30 days (should include both)
        let errorsInMonth = statistics.errorsFound(in: .month)
        XCTAssertEqual(errorsInMonth, 15)
    }

    func testWordsAnalyzedInTimeRange() {
        let todaySession = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(todaySession)

        let words = statistics.wordsAnalyzed(in: .day)
        XCTAssertEqual(words, 100)
    }

    func testAnalysisSessionsInTimeRange() {
        // Add 2 sessions from today
        for _ in 0..<2 {
            let session = DetailedAnalysisSession(
                timestamp: Date(),
                wordsProcessed: 100,
                errorsFound: 5,
                bundleIdentifier: "com.test.app",
                categoryBreakdown: [:],
                latencyMs: 50.0
            )
            statistics.detailedSessions.append(session)
        }

        let count = statistics.analysisSessions(in: .day)
        XCTAssertEqual(count, 2)
    }

    func testSuggestionsAppliedInTimeRange() {
        let nowAction = SuggestionAction(
            timestamp: Date(),
            action: .applied,
            category: "Spelling"
        )
        statistics.suggestionActions.append(nowAction)

        let count = statistics.suggestionsApplied(in: .day)
        XCTAssertEqual(count, 1)
    }

    func testSuggestionsDismissedInTimeRange() {
        let nowAction = SuggestionAction(
            timestamp: Date(),
            action: .dismissed,
            category: nil
        )
        statistics.suggestionActions.append(nowAction)

        let count = statistics.suggestionsDismissed(in: .day)
        XCTAssertEqual(count, 1)
    }

    func testImprovementRateInTimeRange() {
        // Add 3 applied and 1 dismissed
        for _ in 0..<3 {
            let action = SuggestionAction(
                timestamp: Date(),
                action: .applied,
                category: "Spelling"
            )
            statistics.suggestionActions.append(action)
        }

        let dismissedAction = SuggestionAction(
            timestamp: Date(),
            action: .dismissed,
            category: nil
        )
        statistics.suggestionActions.append(dismissedAction)

        let rate = statistics.improvementRate(in: .day)
        XCTAssertEqual(rate, 75.0, accuracy: 0.01)  // 3/4 = 75%
    }

    func testCategoryBreakdownInTimeRange() {
        let session = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 10,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: ["Spelling": 5, "Grammar": 5],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(session)

        let breakdown = statistics.categoryBreakdown(in: .day)
        XCTAssertEqual(breakdown["Spelling"], 5)
        XCTAssertEqual(breakdown["Grammar"], 5)
    }

    func testAppUsageBreakdownInTimeRange() {
        let session1 = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.apple.Safari",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(session1)

        let session2 = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 10,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(session2)

        let breakdown = statistics.appUsageBreakdown(in: .day)
        XCTAssertEqual(breakdown["com.apple.Safari"], 5)
        XCTAssertEqual(breakdown["com.tinyspeck.slackmacgap"], 10)
    }

    // MARK: - Latency Tests

    func testRecordLatency() {
        statistics.recordLatency(milliseconds: 50.0)
        statistics.recordLatency(milliseconds: 100.0)
        statistics.recordLatency(milliseconds: 150.0)

        XCTAssertEqual(statistics.latencySamples.count, 3)
        XCTAssertEqual(statistics.latencySamples[0], 50.0)
        XCTAssertEqual(statistics.latencySamples[1], 100.0)
        XCTAssertEqual(statistics.latencySamples[2], 150.0)
    }

    func testRecordLatencyWithNegativeValue() {
        statistics.recordLatency(milliseconds: -10.0)

        XCTAssertEqual(statistics.latencySamples.count, 0)
    }

    func testLatencySamplesCappedAt100() {
        // Record 150 samples
        for i in 0..<150 {
            statistics.recordLatency(milliseconds: Double(i))
        }

        // Should only keep last 100
        XCTAssertEqual(statistics.latencySamples.count, 100)

        // First sample should be 50 (50-149)
        XCTAssertEqual(statistics.latencySamples.first, 50.0)
        XCTAssertEqual(statistics.latencySamples.last, 149.0)
    }

    func testMeanLatency() {
        statistics.recordLatency(milliseconds: 50.0)
        statistics.recordLatency(milliseconds: 100.0)
        statistics.recordLatency(milliseconds: 150.0)

        XCTAssertEqual(statistics.meanLatencyMs, 100.0)
    }

    func testMeanLatencyWithNoSamples() {
        XCTAssertEqual(statistics.meanLatencyMs, 0.0)
    }

    func testMedianLatency() {
        statistics.recordLatency(milliseconds: 10.0)
        statistics.recordLatency(milliseconds: 50.0)
        statistics.recordLatency(milliseconds: 100.0)

        // Median of [10, 50, 100] should be 50
        XCTAssertEqual(statistics.medianLatencyMs, 50.0)
    }

    func testP90Latency() {
        // Add 10 samples: 10, 20, 30, ..., 100
        for i in 1...10 {
            statistics.recordLatency(milliseconds: Double(i * 10))
        }

        // P90 should be around 90th sample (index 9) = 100
        let p90 = statistics.p90LatencyMs
        XCTAssertGreaterThanOrEqual(p90, 90.0)
        XCTAssertLessThanOrEqual(p90, 100.0)
    }

    func testP95Latency() {
        // Add 20 samples
        for i in 1...20 {
            statistics.recordLatency(milliseconds: Double(i * 10))
        }

        // P95 should be around 95th percentile
        let p95 = statistics.p95LatencyMs
        XCTAssertGreaterThanOrEqual(p95, 180.0)
        XCTAssertLessThanOrEqual(p95, 200.0)
    }

    func testP99Latency() {
        // Add 100 samples
        for i in 1...100 {
            statistics.recordLatency(milliseconds: Double(i))
        }

        // P99 should be around 99th sample
        let p99 = statistics.p99LatencyMs
        XCTAssertGreaterThanOrEqual(p99, 98.0)
        XCTAssertLessThanOrEqual(p99, 100.0)
    }

    func testLatencySamplesInTimeRange() {
        let session = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(session)

        let samples = statistics.latencySamples(in: .day)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0], 50.0)
    }

    func testMeanLatencyInTimeRange() {
        let session1 = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(session1)

        let session2 = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: 100.0
        )
        statistics.detailedSessions.append(session2)

        let mean = statistics.meanLatencyMs(in: .day)
        XCTAssertEqual(mean, 75.0)
    }

    // MARK: - App Usage Tests

    func testRecordAppUsage() {
        statistics.recordAppUsage(bundleIdentifier: "com.apple.Safari", errorCount: 5)
        statistics.recordAppUsage(bundleIdentifier: "com.tinyspeck.slackmacgap", errorCount: 10)
        statistics.recordAppUsage(bundleIdentifier: "com.apple.Safari", errorCount: 3)

        XCTAssertEqual(statistics.appUsageBreakdown["com.apple.Safari"], 8)
        XCTAssertEqual(statistics.appUsageBreakdown["com.tinyspeck.slackmacgap"], 10)
    }

    func testRecordAppUsageWithZeroErrors() {
        statistics.recordAppUsage(bundleIdentifier: "com.test.app", errorCount: 0)

        XCTAssertNil(statistics.appUsageBreakdown["com.test.app"])
    }

    func testTopWritingApp() {
        statistics.recordAppUsage(bundleIdentifier: "com.apple.Safari", errorCount: 5)
        statistics.recordAppUsage(bundleIdentifier: "com.tinyspeck.slackmacgap", errorCount: 15)
        statistics.recordAppUsage(bundleIdentifier: "com.google.Chrome", errorCount: 10)

        guard let top = statistics.topWritingApp else {
            XCTFail("Should have a top writing app")
            return
        }

        XCTAssertEqual(top.name, "Slack")  // Friendly name mapping
        XCTAssertEqual(top.errorCount, 15)
    }

    func testTopWritingAppWithNoData() {
        XCTAssertNil(statistics.topWritingApp)
    }

    func testTopWritingAppInTimeRange() {
        let session1 = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.apple.Safari",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(session1)

        let session2 = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 15,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(session2)

        guard let top = statistics.topWritingApp(in: .day) else {
            XCTFail("Should have a top writing app")
            return
        }

        XCTAssertEqual(top.name, "Slack")
        XCTAssertEqual(top.errorCount, 15)
    }

    // MARK: - Error Density Tests

    func testErrorDensity() {
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 5)
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 5)

        // Average: 5 errors per 100 words = 5.0 errors per 100 words
        XCTAssertEqual(statistics.errorDensity, 5.0, accuracy: 0.01)
    }

    func testErrorDensityWithNoData() {
        XCTAssertEqual(statistics.errorDensity, 0.0)
    }

    func testAverageErrorsPer100Words() {
        statistics.recordAnalysisSession(wordsProcessed: 100, errorsFound: 5)
        statistics.recordAnalysisSession(wordsProcessed: 200, errorsFound: 10)

        // Total: 15 errors in 300 words = 5.0 per 100 words
        XCTAssertEqual(statistics.averageErrorsPer100Words, 5.0, accuracy: 0.01)
    }

    func testAverageErrorsPer100WordsInTimeRange() {
        let session = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(session)

        let avg = statistics.averageErrorsPer100Words(in: .day)
        XCTAssertEqual(avg, 5.0, accuracy: 0.01)
    }

    // MARK: - Current Streak Tests

    func testCurrentStreakWithConsecutiveDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Add today
        statistics.activeDays.insert(today)

        // Add yesterday
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            statistics.activeDays.insert(yesterday)
        }

        // Add 2 days ago
        if let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) {
            statistics.activeDays.insert(twoDaysAgo)
        }

        XCTAssertEqual(statistics.currentStreak, 3)
    }

    func testCurrentStreakWithGap() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Add today
        statistics.activeDays.insert(today)

        // Skip yesterday, add 2 days ago
        if let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) {
            statistics.activeDays.insert(twoDaysAgo)
        }

        // Streak should be broken (only today counts)
        XCTAssertEqual(statistics.currentStreak, 1)
    }

    func testCurrentStreakWithNoActivity() {
        XCTAssertEqual(statistics.currentStreak, 0)
    }


    // MARK: - Data Cleanup Tests

    func testCleanupOldDetailedSessions() {
        // Add a session from 100 days ago
        let hundredDaysAgo = Date().addingTimeInterval(-100 * 24 * 3600)
        let oldSession = DetailedAnalysisSession(
            timestamp: hundredDaysAgo,
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(oldSession)

        // Add a recent session
        let recentSession = DetailedAnalysisSession(
            timestamp: Date(),
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: 50.0
        )
        statistics.detailedSessions.append(recentSession)

        // Trigger cleanup by recording a new session
        statistics.recordDetailedAnalysisSession(
            wordsProcessed: 50,
            errorsFound: 2,
            bundleIdentifier: "com.test.app",
            categoryBreakdown: [:],
            latencyMs: 30.0
        )

        // Old session should be removed, keeping only the 2 recent ones
        XCTAssertEqual(statistics.detailedSessions.count, 2)
    }

    func testCleanupOldSuggestionActions() {
        // Add an action from 100 days ago
        let hundredDaysAgo = Date().addingTimeInterval(-100 * 24 * 3600)
        let oldAction = SuggestionAction(
            timestamp: hundredDaysAgo,
            action: .applied,
            category: "Spelling"
        )
        statistics.suggestionActions.append(oldAction)

        // Add a recent action
        let recentAction = SuggestionAction(
            timestamp: Date(),
            action: .applied,
            category: "Grammar"
        )
        statistics.suggestionActions.append(recentAction)

        // Trigger cleanup
        statistics.recordSuggestionApplied(category: "Style")

        // Old action should be removed
        XCTAssertEqual(statistics.suggestionActions.count, 2)
    }

    // MARK: - Persistence Tests for New Features

    func testDetailedSessionsPersistence() {
        statistics.recordDetailedAnalysisSession(
            wordsProcessed: 100,
            errorsFound: 5,
            bundleIdentifier: "com.apple.Safari",
            categoryBreakdown: ["Spelling": 5],
            latencyMs: 50.0
        )

        let newStatistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)

        XCTAssertEqual(newStatistics.detailedSessions.count, 1)
        XCTAssertEqual(newStatistics.detailedSessions[0].wordsProcessed, 100)
        XCTAssertEqual(newStatistics.detailedSessions[0].errorsFound, 5)
    }

    func testSuggestionActionsPersistence() {
        statistics.recordSuggestionApplied(category: "Spelling")
        statistics.recordSuggestionDismissed()

        let newStatistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)

        XCTAssertEqual(newStatistics.suggestionActions.count, 2)
    }

    func testAppLaunchTimestampPersistence() {
        let timestamp = Date()
        statistics.appLaunchTimestamp = timestamp

        let newStatistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)

        // Compare timestamps with 1 second tolerance
        XCTAssertEqual(
            newStatistics.appLaunchTimestamp.timeIntervalSince1970,
            timestamp.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testLatencySamplesPersistence() {
        statistics.recordLatency(milliseconds: 50.0)
        statistics.recordLatency(milliseconds: 100.0)

        let newStatistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)

        XCTAssertEqual(newStatistics.latencySamples.count, 2)
        XCTAssertEqual(newStatistics.latencySamples[0], 50.0)
        XCTAssertEqual(newStatistics.latencySamples[1], 100.0)
    }

    func testAppUsageBreakdownPersistence() {
        statistics.recordAppUsage(bundleIdentifier: "com.apple.Safari", errorCount: 5)

        let newStatistics = UserStatistics(defaults: UserDefaults(suiteName: "test.textwarden.statistics")!)

        XCTAssertEqual(newStatistics.appUsageBreakdown["com.apple.Safari"], 5)
    }
}
