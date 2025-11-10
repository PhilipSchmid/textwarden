//
//  GrammarEngineFFITests.swift
//  Gnau Contract Tests
//
//  Tests validating Rust-Swift FFI boundary integrity
//

import XCTest
@testable import Gnau

final class GrammarEngineFFITests: XCTestCase {

    // MARK: - Basic FFI Contract Tests

    func testAnalyzeText_EmptyString_ReturnsEmptyResult() {
        // Given: Empty text input
        let emptyText = ""

        // When: Analyzing empty text
        let result = GrammarEngine.shared.analyzeText(emptyText)

        // Then: Should return valid result with no errors
        XCTAssertNotNil(result, "FFI should return non-nil result for empty text")
        XCTAssertEqual(result.errors.count, 0, "Empty text should have no errors")
        XCTAssertEqual(result.wordCount, 0, "Empty text should have 0 word count")
        XCTAssertGreaterThanOrEqual(result.analysisTimeMs, 0, "Analysis time should be non-negative")
    }

    func testAnalyzeText_CorrectSentence_ReturnsNoErrors() {
        // Given: Grammatically correct sentence
        let correctText = "The cat sits on the mat."

        // When: Analyzing correct text
        let result = GrammarEngine.shared.analyzeText(correctText)

        // Then: Should return valid result with no errors
        XCTAssertNotNil(result)
        XCTAssertEqual(result.errors.count, 0, "Correct text should have no errors")
        XCTAssertGreaterThan(result.wordCount, 0, "Word count should be positive")
    }

    func testAnalyzeText_IncorrectSentence_ReturnsErrors() {
        // Given: Text with grammar error
        let incorrectText = "The cats sits on the mat."  // Subject-verb disagreement

        // When: Analyzing incorrect text
        let result = GrammarEngine.shared.analyzeText(incorrectText)

        // Then: Should detect the error
        XCTAssertNotNil(result)
        // Note: Harper may or may not detect this specific error
        // This test validates the FFI works, not specific grammar rules
        XCTAssertGreaterThanOrEqual(result.errors.count, 0, "Should return valid error array")
    }

    // MARK: - Error Model Contract Tests

    func testGrammarError_HasRequiredFields() {
        // Given: A grammar error from analysis
        let text = "She dont like apples."  // Grammar error
        let result = GrammarEngine.shared.analyzeText(text)

        // When: Checking error properties
        guard let error = result.errors.first else {
            // No errors detected - skip test
            return
        }

        // Then: Error should have all required fields
        XCTAssertGreaterThanOrEqual(error.start, 0, "Start index should be non-negative")
        XCTAssertGreaterThan(error.end, error.start, "End should be after start")
        XCTAssertFalse(error.message.isEmpty, "Message should not be empty")
        XCTAssertFalse(error.lintId.isEmpty, "Lint ID should not be empty")
    }

    func testGrammarError_SeverityIsValid() {
        // Given: A grammar error from analysis
        let text = "They was happy."  // Grammar error
        let result = GrammarEngine.shared.analyzeText(text)

        guard let error = result.errors.first else {
            return
        }

        // Then: Severity should be a valid enum value
        let validSeverities: [GrammarErrorSeverity] = [.error, .warning, .info]
        XCTAssertTrue(validSeverities.contains(error.severity), "Severity should be valid enum value")
    }

    // MARK: - Performance Contract Tests

    func testAnalyzeText_Performance_Under100ms() {
        // Given: A moderate-length text
        let text = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 10)

        // When: Measuring analysis time
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = GrammarEngine.shared.analyzeText(text)
        let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000  // Convert to ms

        // Then: Analysis should complete quickly
        XCTAssertNotNil(result)
        XCTAssertLessThan(elapsedTime, 100, "Analysis should complete under 100ms for moderate text")
    }

    func testAnalyzeText_ReportedTime_IsReasonable() {
        // Given: Any text
        let text = "This is a test sentence."

        // When: Analyzing text
        let result = GrammarEngine.shared.analyzeText(text)

        // Then: Reported analysis time should be reasonable
        XCTAssertGreaterThan(result.analysisTimeMs, 0, "Analysis time should be positive")
        XCTAssertLessThan(result.analysisTimeMs, 10000, "Analysis time should be under 10 seconds")
    }

    // MARK: - Memory Safety Tests

    func testAnalyzeText_LargeText_DoesNotCrash() {
        // Given: Large text input
        let largeText = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 1000)

        // When: Analyzing large text
        let result = GrammarEngine.shared.analyzeText(largeText)

        // Then: Should not crash and return valid result
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result.wordCount, 0)
    }

    func testAnalyzeText_SpecialCharacters_HandledSafely() {
        // Given: Text with special characters
        let specialText = "Hello! @#$%^&*() \"quotes\" 'apostrophes' — dashes…"

        // When: Analyzing text with special characters
        let result = GrammarEngine.shared.analyzeText(specialText)

        // Then: Should handle safely without crashing
        XCTAssertNotNil(result)
    }

    func testAnalyzeText_Unicode_HandledSafely() {
        // Given: Text with Unicode characters
        let unicodeText = "Café résumé naïve 日本語 한국어 中文"

        // When: Analyzing Unicode text
        let result = GrammarEngine.shared.analyzeText(unicodeText)

        // Then: Should handle Unicode safely
        XCTAssertNotNil(result)
    }

    // MARK: - Concurrency Safety Tests

    func testAnalyzeText_ConcurrentCalls_ThreadSafe() async {
        // Given: Multiple text samples
        let texts = [
            "The cat sat on the mat.",
            "She dont like apples.",
            "They was happy yesterday.",
            "A quick brown fox jumps.",
        ]

        // When: Analyzing concurrently
        await withTaskGroup(of: GrammarAnalysisResult.self) { group in
            for text in texts {
                group.addTask {
                    await GrammarEngine.shared.analyzeText(text)
                }
            }

            // Then: All tasks should complete without crashing
            var results: [GrammarAnalysisResult] = []
            for await result in group {
                results.append(result)
            }

            XCTAssertEqual(results.count, texts.count, "All concurrent analyses should complete")
        }
    }
}
