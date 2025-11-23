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
}
