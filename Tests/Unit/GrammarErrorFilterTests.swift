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

    func testHarperSplitFollowsCategoriesAndIgnoredRules() throws {
        let text = "👩🏽‍💻 I found thebest example."
        let start = "👩🏽‍💻 I found ".unicodeScalars.count
        let errors = GrammarEngine.shared.analyzeText(text).errors
        let split = try XCTUnwrap(errors.first { $0.category == "Typo" && $0.start == start })
        let cases: [(enabled: Set<String>, ignored: Set<String>, expected: String)] = [
            (["Spelling", "Typo"], [], "Typo"),
            (["Typo"], [], "Typo"),
            (["Spelling"], [], "Spelling"),
            (["Spelling", "Typo"], [split.lintId], "Spelling"),
        ]
        for test in cases {
            let config = GrammarFilterConfig(enabledCategories: test.enabled, ignoredRules: test.ignored, ignoredErrorTexts: [], useMacOSDictionary: false)
            let result = GrammarErrorFilter.filter(errors: errors, sourceText: text, config: config, customVocabulary: Vocabulary())
            let sameSpan = result.filter { $0.start == start && $0.end == start + "thebest".count }
            XCTAssertEqual(sameSpan.map(\.category), [test.expected])
            if test.expected == "Typo" {
                let correction = try XCTUnwrap(sameSpan.first?.suggestions.first)
                let range = TextIndexConverter.scalarToUTF16Range(NSRange(location: start, length: "thebest".count), in: text)
                XCTAssertEqual((text as NSString).replacingCharacters(in: range, with: correction), "👩🏽‍💻 I found the best example.")
            }
        }

        let vocabulary = Vocabulary()
        vocabulary.words = ["thebest"]
        let config = GrammarFilterConfig(enabledCategories: ["Spelling", "Typo"], ignoredRules: [], ignoredErrorTexts: [], useMacOSDictionary: false)
        let filtered = GrammarErrorFilter.filter(errors: errors, sourceText: text, config: config, customVocabulary: vocabulary)
        XCTAssertFalse(filtered.contains { $0.start == start })
    }

    func testWordOrderIsEnabledForExistingGrammarUsersOnce() throws {
        XCTAssertTrue(UserPreferences.allCategories.contains("WordOrder"))
        XCTAssertFalse(UserPreferences.allCategories.contains("Readability"))
        for grammarEnabled in [true, false] {
            let suite = "WordOrderPreferencesTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let previous: Set<String> = grammarEnabled ? ["Spelling", "Grammar"] : ["Spelling"]
            try defaults.set(JSONEncoder().encode(previous), forKey: "enabledCategories")

            let migrated = UserPreferences(defaults: defaults)
            XCTAssertEqual(migrated.enabledCategories, grammarEnabled ? previous.union(["WordOrder"]) : previous)
            migrated.enabledCategories.remove("WordOrder")
            XCTAssertEqual(UserPreferences(defaults: defaults).enabledCategories, previous)
        }
    }

    func testWordOrderAndPunctuationSpacingUseTheirOwnCategorySettings() throws {
        for (text, category, replacement, expected) in [
            ("No longer they work there.", "WordOrder", "They no longer", "They no longer work there."),
            ("We are done.Next comes the review.", "Formatting", ". ", "We are done. Next comes the review."),
            ("Yes,please come in.", "Punctuation", ", ", "Yes, please come in."),
        ] {
            let errors = GrammarEngine.shared.analyzeText(text).errors
            let disabled = GrammarFilterConfig(enabledCategories: ["Spelling"], ignoredRules: [], ignoredErrorTexts: [], useMacOSDictionary: false)
            let enabled = GrammarFilterConfig(enabledCategories: [category], ignoredRules: [], ignoredErrorTexts: [], useMacOSDictionary: false)
            XCTAssertTrue(GrammarErrorFilter.filter(errors: errors, sourceText: text, config: disabled, customVocabulary: Vocabulary()).isEmpty)
            let accepted = GrammarErrorFilter.filter(errors: errors, sourceText: text, config: enabled, customVocabulary: Vocabulary())
            let error = try XCTUnwrap(accepted.first { $0.category == category })
            XCTAssertEqual(error.suggestions.first, replacement)
            let range = TextIndexConverter.scalarToUTF16Range(NSRange(location: error.start, length: error.end - error.start), in: text)
            XCTAssertEqual((text as NSString).replacingCharacters(in: range, with: replacement), expected)
        }
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
