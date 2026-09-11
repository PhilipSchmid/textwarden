@testable import TextWarden
import XCTest

@MainActor
final class GrammarErrorFilterTests: XCTestCase {
    private final class Vocabulary: CustomVocabularyProviding {
        var words: Set<String> = []
        func containsAnyWord(in text: String) -> Bool {
            words.contains(text)
        }

        func addWord(_ word: String) throws {
            words.insert(word)
        }

        func allWords() -> [String] {
            Array(words)
        }
    }

    private func error(_ start: Int, _ end: Int, lint: String = "Spelling") -> GrammarErrorModel {
        GrammarErrorModel(start: start, end: end, message: lint, severity: .warning, category: "Spelling", lintId: lint)
    }

    func testLargeErrorBatchDoesNotRescanTheDocumentPerError() {
        let sentence = "This is a sentnce with a spelling mistke. "
        let text = String(repeating: sentence, count: 1300)
        let errors = (0 ..< 1300).flatMap { index in
            let offset = index * sentence.unicodeScalars.count
            return [error(offset + 10, offset + 17), error(offset + 34, offset + 40)]
        }
        let config = GrammarFilterConfig(enabledCategories: ["Spelling"], ignoredRules: [], ignoredErrorTexts: [], useMacOSDictionary: false)
        let start = ProcessInfo.processInfo.systemUptime
        let filtered = GrammarErrorFilter.filter(errors: errors, sourceText: text, config: config, customVocabulary: Vocabulary())
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertEqual(filtered.count, 2600)
        XCTAssertEqual(filtered.last?.end, errors.last?.end)
        // Generous regression ceiling, not a production latency budget.
        XCTAssertLessThan(elapsed, 2)
    }

    func testBatchFilteringPreservesUnicodeVocabularyIgnoredTextAndInvalidRanges() {
        let prefix = "👨‍👩‍👧é "
        let text = prefix + "known typo\n  item"
        let start = prefix.unicodeScalars.count
        let vocabulary = Vocabulary()
        vocabulary.words = ["known"]
        let config = GrammarFilterConfig(enabledCategories: ["Spelling"], ignoredRules: ["Dismissed"], ignoredErrorTexts: ["typo"], useMacOSDictionary: false)
        let errors = [
            error(start, start + 5),
            error(start + 6, start + 10),
            error(start + 11, start + 13, lint: "RepeatedWhitespace"),
            error(start + 13, start + 17, lint: "Dismissed"),
            error(1, 2), // Inside a ZWJ grapheme: preserve the existing fail-open behavior.
            error(-1, 2),
            error(3, 3),
            error(4, 2),
            error(0, Int.max),
        ]
        let filtered = GrammarErrorFilter.filter(errors: errors, sourceText: text, config: config, customVocabulary: vocabulary)
        XCTAssertEqual(filtered.map(\.start), [1, -1, 3, 4, 0])
    }
}
