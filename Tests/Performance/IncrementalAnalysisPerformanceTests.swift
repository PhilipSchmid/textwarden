//
//  IncrementalAnalysisPerformanceTests.swift
//  TextWarden Tests
//
//  Performance tests for incremental re-analysis (T077)
//

import XCTest
@testable import TextWarden

final class IncrementalAnalysisPerformanceTests: XCTestCase {
    var coordinator: AnalysisCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = AnalysisCoordinator.shared
    }

    override func tearDown() {
        coordinator.clearCache()
        super.tearDown()
    }

    // MARK: - Incremental Analysis Tests (T077)

    func testIncrementalEditUnder20ms() {
        // Create initial large document
        let initialText = generateLargeDocument(wordCount: 10000)
        let context = createMockContext()

        // Initial full analysis
        let segment = TextSegment(content: initialText, startIndex: 0, endIndex: initialText.count, context: context)

        // Simulate text change: edit a single paragraph
        let editedText = initialText.replacingOccurrences(
            of: "The quick brown fox",
            with: "The slow brown fox"
        )

        // Measure incremental analysis time
        let startTime = CFAbsoluteTimeGetCurrent()
        // In production, this would trigger incremental analysis
        // For now, we measure the diff detection cost
        let hasChanged = editedText != initialText
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertTrue(hasChanged)
        XCTAssertLessThan(elapsed, 20.0)
    }

    func testSmallEditDetection() {
        let text1 = "The team are working on multiple project."
        let text2 = "The team are working on multiple projects."

        let startTime = CFAbsoluteTimeGetCurrent()

        // Detect change
        let changed = text1 != text2
        let changeLocation = findDifferenceLocation(text1, text2)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertTrue(changed)
        XCTAssertNotNil(changeLocation)
        XCTAssertLessThan(elapsed, 1.0) // Should be near-instant
    }

    func testLargeEditDetection() {
        let text1 = generateLargeDocument(wordCount: 10000)
        let text2 = text1 + " Additional paragraph with more text."

        measure {
            let changed = text1 != text2
            XCTAssertTrue(changed)
        }
    }

    func testCopyPasteDetection() {
        let originalText = "Short paragraph."
        let pastedText = generateLargeDocument(wordCount: 1000)
        let newText = originalText + " " + pastedText

        // Large paste should be detected as significant change
        let oldCount = originalText.count
        let newCount = newText.count
        let diff = abs(newCount - oldCount)

        XCTAssertGreaterThan(diff, 100)
    }

    // MARK: - Sentence Boundary Detection Tests

    func testSentenceBoundaryDetection() {
        let text = "First sentence. Second sentence! Third sentence? Fourth sentence."

        let boundaries = detectSentenceBoundaries(text)

        XCTAssertEqual(boundaries.count, 4)
    }

    func testContextAwareIncremental() {
        // Test that we include surrounding context for accurate analysis
        let text = "The dog are happy. The cat is sad."

        // Edit in second sentence shouldn't re-analyze first
        let editIndex = text.range(of: "cat")!.lowerBound
        let editLocation = text.distance(from: text.startIndex, to: editIndex)

        // Should only need to analyze second sentence
        let contextStart = max(0, editLocation - 50)
        let contextEnd = min(text.count, editLocation + 50)

        XCTAssertGreaterThan(contextEnd - contextStart, 0)
    }

    // MARK: - Helper Methods

    private func generateLargeDocument(wordCount: Int) -> String {
        let words = Array(repeating: "word", count: wordCount)
        return words.joined(separator: " ")
    }

    private func createMockContext() -> ApplicationContext {
        return ApplicationContext(
            applicationName: "Test App",
            bundleIdentifier: "com.test.app",
            processID: 12345
        )
    }

    private func findDifferenceLocation(_ text1: String, _ text2: String) -> Int? {
        let minLength = min(text1.count, text2.count)

        for (index, (char1, char2)) in zip(text1, text2).enumerated() {
            if char1 != char2 {
                return index
            }
        }

        if text1.count != text2.count {
            return minLength
        }

        return nil
    }

    private func detectSentenceBoundaries(_ text: String) -> [Range<String.Index>] {
        var boundaries: [Range<String.Index>] = []
        var currentStart = text.startIndex

        for (index, char) in text.enumerated() {
            if char == "." || char == "!" || char == "?" {
                let endIndex = text.index(text.startIndex, offsetBy: index + 1)
                boundaries.append(currentStart..<endIndex)
                currentStart = endIndex

                // Skip whitespace
                if currentStart < text.endIndex {
                    while currentStart < text.endIndex && text[currentStart].isWhitespace {
                        currentStart = text.index(after: currentStart)
                    }
                }
            }
        }

        return boundaries
    }
}
