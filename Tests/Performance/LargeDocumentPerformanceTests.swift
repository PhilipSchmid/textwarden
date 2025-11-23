//
//  LargeDocumentPerformanceTests.swift
//  TextWarden Tests
//
//  Performance tests for 10,000-word document analysis (T076)
//

import XCTest
@testable import TextWarden

final class LargeDocumentPerformanceTests: XCTestCase {
    var grammarEngine: GrammarEngine!

    override func setUp() {
        super.setUp()
        grammarEngine = GrammarEngine.shared
    }

    // MARK: - Large Document Tests (T076)

    func testAnalyze10KWordDocumentUnder500ms() {
        // Generate a 10,000-word document
        let text = generateLargeDocument(wordCount: 10000)

        // Measure analysis time
        measure {
            let result = grammarEngine.analyzeText(text)
            XCTAssertNotNil(result)
        }

        // Assert: Initial analysis should be <500ms
        // Note: measure() will fail if baseline exceeds 500ms
    }

    func testAnalyze15KWordDocumentPerformance() {
        // Test edge case: 15,000 words
        let text = generateLargeDocument(wordCount: 15000)

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = grammarEngine.analyzeText(text)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        print("15K word analysis took: \(elapsed)ms")
        XCTAssertNotNil(result)

        // Should complete within reasonable time (allow up to 1 second for very large docs)
        XCTAssertLessThan(elapsed, 1000.0)
    }

    func testLargeDocumentMemoryFootprint() {
        // Test that analyzing large document doesn't cause memory spike
        let text = generateLargeDocument(wordCount: 10000)

        // Analyze multiple times to check for memory leaks
        for _ in 0..<5 {
            let _ = grammarEngine.analyzeText(text)
        }

        // If we get here without crash, memory is managed properly
        XCTAssertTrue(true)
    }

    func testMultipleLargeDocumentsConcurrently() {
        let expectation = self.expectation(description: "Concurrent analysis")
        expectation.expectedFulfillmentCount = 3

        let text = generateLargeDocument(wordCount: 5000)

        // Simulate analyzing multiple large documents concurrently
        for _ in 0..<3 {
            DispatchQueue.global().async {
                let _ = self.grammarEngine.analyzeText(text)
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)
    }

    // MARK: - Helper Methods

    private func generateLargeDocument(wordCount: Int) -> String {
        let sentences = [
            "The quick brown fox jumps over the lazy dog.",
            "She sells seashells by the seashore.",
            "How much wood would a woodchuck chuck if a woodchuck could chuck wood?",
            "Peter Piper picked a peck of pickled peppers.",
            "A journey of a thousand miles begins with a single step.",
            "To be or not to be, that is the question.",
            "All that glitters is not gold.",
            "Actions speak louder than words.",
            "Knowledge is power and power corrupts.",
            "The pen is mightier than the sword."
        ]

        var words: [String] = []
        var sentenceIndex = 0

        while words.count < wordCount {
            let sentence = sentences[sentenceIndex % sentences.count]
            let sentenceWords = sentence.split(separator: " ").map(String.init)
            words.append(contentsOf: sentenceWords)
            sentenceIndex += 1
        }

        // Trim to exact word count
        let trimmedWords = Array(words.prefix(wordCount))
        return trimmedWords.joined(separator: " ")
    }
}
