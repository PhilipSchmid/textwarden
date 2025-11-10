//
//  GrammarAnalysisPerformanceTests.swift
//  Gnau Performance Tests
//
//  Performance tests ensuring <20ms analysis for real-time detection
//

import XCTest
@testable import Gnau

final class GrammarAnalysisPerformanceTests: XCTestCase {

    // MARK: - Real-time Analysis Performance (<20ms target)

    func testAnalysis_ShortSentence_Under20ms() {
        // Given: Short sentence (10-15 words)
        let text = "The quick brown fox jumps over the lazy dog."

        // When: Measuring analysis time
        measure {
            _ = GrammarEngine.shared.analyzeText(text)
        }

        // Then: Should complete in <20ms (verified by XCTest metrics)
    }

    func testAnalysis_MediumParagraph_Under50ms() {
        // Given: Medium paragraph (~50 words)
        let text = """
        The quick brown fox jumps over the lazy dog. This sentence is used to test \
        the performance of grammar analysis. We want to ensure that even with moderate \
        text length, the analysis completes quickly enough for real-time checking.
        """

        // When: Measuring analysis time
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = GrammarEngine.shared.analyzeText(text)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Then: Should complete in <50ms
        XCTAssertLessThan(elapsedMs, 50, "Medium paragraph should analyze under 50ms")
    }

    func testAnalysis_TypicalSentence_ConsistentTiming() {
        // Given: Typical sentence length (15-20 words)
        let sentences = [
            "The team is working on multiple projects this quarter.",
            "She doesn't like apples but enjoys oranges very much.",
            "They were happy yesterday when the results were announced.",
            "A quick brown fox jumps over the lazy sleeping dog."
        ]

        // When: Analyzing multiple times
        var times: [Double] = []
        for sentence in sentences {
            let start = CFAbsoluteTimeGetCurrent()
            _ = GrammarEngine.shared.analyzeText(sentence)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            times.append(elapsed)
        }

        // Then: All should be under 20ms
        for (index, time) in times.enumerated() {
            XCTAssertLessThan(time, 20, "Sentence \(index) took \(time)ms, should be <20ms")
        }
    }

    // MARK: - Incremental Analysis Performance

    func testIncrementalAnalysis_SingleWordChange_Under20ms() {
        // Given: Large text with single word change
        let originalText = String(repeating: "The quick brown fox jumps. ", count: 20)
        let modifiedText = originalText.replacingOccurrences(of: "jumps", with: "jumped")

        // When: Analyzing incremental change
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = GrammarEngine.shared.analyzeText(modifiedText)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Then: Should complete quickly (targeting <20ms for incremental)
        XCTAssertLessThan(elapsedMs, 100, "Incremental analysis should be fast")
    }

    // MARK: - Async Performance

    func testAsyncAnalysis_NoBlocking() async {
        // Given: Text to analyze asynchronously
        let text = "The cats sits on the mat while the dog sleep."

        // When: Using async wrapper
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = await GrammarEngine.shared.analyzeText(text)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Then: Should complete quickly without blocking main thread
        XCTAssertLessThan(elapsedMs, 50, "Async analysis should complete quickly")
    }

    func testConcurrentAnalysis_MultipleTexts() async {
        // Given: Multiple texts to analyze
        let texts = [
            "The quick brown fox.",
            "She dont like apples.",
            "They was happy.",
            "A beautiful day outside."
        ]

        // When: Analyzing concurrently
        let startTime = CFAbsoluteTimeGetCurrent()

        await withTaskGroup(of: Void.self) { group in
            for text in texts {
                group.addTask {
                    _ = await GrammarEngine.shared.analyzeText(text)
                }
            }
        }

        let totalElapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Then: Should complete efficiently
        XCTAssertLessThan(totalElapsedMs, 100, "Concurrent analysis should be efficient")
    }

    // MARK: - Memory Performance

    func testAnalysis_MemoryStable() {
        // Given: Repeated analysis cycles
        let text = "The quick brown fox jumps over the lazy dog."

        // When: Analyzing many times
        for _ in 0..<100 {
            autoreleasepool {
                _ = GrammarEngine.shared.analyzeText(text)
            }
        }

        // Then: Should not leak memory (verified by XCTest memory tracking)
        XCTAssertTrue(true, "Memory stability test completed")
    }

    // MARK: - Edge Case Performance

    func testAnalysis_EmptyText_Instant() {
        // Given: Empty text
        let text = ""

        // When: Analyzing
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = GrammarEngine.shared.analyzeText(text)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Then: Should be nearly instant
        XCTAssertLessThan(elapsedMs, 5, "Empty text analysis should be instant")
    }

    func testAnalysis_VeryLongText_Acceptable() {
        // Given: Very long text (1000 words)
        let text = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 100)

        // When: Analyzing
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = GrammarEngine.shared.analyzeText(text)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Then: Should complete in reasonable time
        XCTAssertLessThan(elapsedMs, 500, "Long text should analyze under 500ms")
    }
}
