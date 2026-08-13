//
//  ReplacementTextMatcherTests.swift
//  TextWardenTests
//

@testable import TextWarden
import XCTest

final class ReplacementTextMatcherTests: XCTestCase {
    func testSentenceStartCapitalizationMatchesTheOriginalRange() {
        let text = "THis is a test."
        let error = capitalizationError(start: 0, end: 4)

        XCTAssertEqual(
            ReplacementTextMatcher.resolveRange(in: text, analyzedText: text, for: error),
            .matched(0 ..< 4)
        )
    }

    func testMidSentenceCapitalizationMatchesAtNonzeroPosition() {
        let text = "THis is yet another test which shows that this is incorrectly replaced. Because tHis is wrong."
        let error = capitalizationError(start: 80, end: 84)

        XCTAssertEqual(
            ReplacementTextMatcher.resolveRange(in: text, analyzedText: text, for: error),
            .matched(80 ..< 84)
        )
    }

    func testExactSpellingTokenMatches() {
        let text = "testt"
        let error = spellingError(start: 0, end: 5)

        XCTAssertEqual(
            ReplacementTextMatcher.resolveRange(in: text, analyzedText: text, for: error),
            .matched(0 ..< 5)
        )
    }

    func testChangedCaseIsRejected() {
        let error = capitalizationError(start: 0, end: 4)

        XCTAssertEqual(
            ReplacementTextMatcher.resolveRange(in: "THis", analyzedText: "tHis", for: error),
            .notFound
        )
    }

    func testUniqueShiftedMatchIsResolved() {
        let error = capitalizationError(start: 0, end: 4)

        XCTAssertEqual(
            ReplacementTextMatcher.resolveRange(
                in: "xtHis",
                analyzedText: "tHis",
                for: error,
                searchRadius: 1
            ),
            .matched(1 ..< 5)
        )
    }

    func testRepeatedShiftedMatchesAreRejected() {
        let error = capitalizationError(start: 4, end: 8)

        XCTAssertEqual(
            ReplacementTextMatcher.resolveRange(
                in: "tHisxtHis",
                analyzedText: "xxxxtHis",
                for: error
            ),
            .ambiguous([0 ..< 4, 5 ..< 9])
        )
    }

    func testHumanReadableMessageIsNotUsedForValidation() {
        let error = capitalizationError(start: 0, end: 4, message: "Capitalize this word")

        XCTAssertEqual(
            ReplacementTextMatcher.resolveRange(in: "THis", analyzedText: "THis", for: error),
            .matched(0 ..< 4)
        )
    }

    func testInvalidAnalyzedRangeIsUnavailable() {
        let error = capitalizationError(start: 0, end: 8)

        XCTAssertEqual(
            ReplacementTextMatcher.resolveRange(in: "and also", analyzedText: "and", for: error),
            .unavailable
        )
    }

    func testUnicodePrefixKeepsScalarAndUTF16RangesDistinct() {
        let prefix = "👨‍👩‍👧 "
        let text = prefix + "THis"
        let start = prefix.unicodeScalars.count
        let error = capitalizationError(start: start, end: start + 4)

        let resolution = ReplacementTextMatcher.resolveRange(
            in: text,
            analyzedText: text,
            for: error
        )

        XCTAssertEqual(resolution, .matched(start ..< start + 4))
        guard let utf16Range = TextIndexConverter.scalarRangeToUTF16CFRange(
            start: start,
            end: start + 4,
            in: text
        ) else {
            return XCTFail("Expected a valid UTF-16 range")
        }
        XCTAssertEqual(utf16Range.location, (prefix as NSString).length)
        XCTAssertEqual(utf16Range.length, 4)
    }

    func testErrorSourceStoreRejectsAnErrorFromAnOlderResultSet() {
        let oldError = capitalizationError(start: 0, end: 4)
        let newError = capitalizationError(start: 0, end: 4)
        var store = GrammarErrorSourceStore()

        store.replace(errors: [oldError], sourceText: "THis")
        store.replace(errors: [newError], sourceText: "tHis")

        XCTAssertNil(store.sourceText(for: oldError, among: [newError]))
        XCTAssertEqual(store.sourceText(for: newError, among: [newError]), "tHis")
    }

    func testErrorSourceStoreRejectsAnErrorAfterCanonicalErrorsAreCleared() {
        let error = capitalizationError(start: 0, end: 4)
        var store = GrammarErrorSourceStore()
        store.replace(errors: [error], sourceText: "THis")

        XCTAssertNil(store.sourceText(for: error, among: []))
    }

    func testErrorSourceStoreDoesNotRetieAnExistingErrorToNewerText() {
        let error = capitalizationError(start: 0, end: 4)
        var store = GrammarErrorSourceStore()

        store.replace(errors: [error], sourceText: "THis")
        store.replace(errors: [error], sourceText: "tHis")

        XCTAssertEqual(store.sourceText(for: error, among: [error]), "THis")
    }

    private func capitalizationError(
        start: Int,
        end: Int,
        message: String = "The canonical dictionary spelling is `this`."
    ) -> GrammarErrorModel {
        GrammarErrorModel(
            start: start,
            end: end,
            message: message,
            severity: .warning,
            category: "Capitalization",
            lintId: "Capitalization::canonical_spelling",
            suggestions: ["this"]
        )
    }

    private func spellingError(start: Int, end: Int) -> GrammarErrorModel {
        GrammarErrorModel(
            start: start,
            end: end,
            message: "Check this spelling.",
            severity: .warning,
            category: "Spelling",
            lintId: "Spelling::did_you_mean_to_spell",
            suggestions: []
        )
    }
}
