//
//  ReplacementTextMatcherTests.swift
//  TextWardenTests
//

@testable import TextWarden
import XCTest

final class ReplacementTextMatcherTests: XCTestCase {
    func testStyleSelectionRequiresOneLiteralMatchWithUTF16Offsets() {
        let source = "😊 Begin here. Please proceed."
        let target = "Please proceed."
        let range = ReplacementTextMatcher.uniqueLiteralRange(of: target, in: source)
        XCTAssertEqual(range.map { NSRange($0, in: source) }, NSRange(location: 15, length: 15))
        XCTAssertNil(ReplacementTextMatcher.uniqueLiteralRange(of: target, in: "\(target) \(target)"))
        XCTAssertNil(ReplacementTextMatcher.uniqueLiteralRange(of: "aa", in: "aaa"))
        XCTAssertNil(ReplacementTextMatcher.uniqueLiteralRange(of: "é", in: "e\u{301}"))
    }

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

    func testSegmentReconciliationAppliesReplacementToUnchangedAnalysisText() {
        XCTAssertEqual(
            ReplacementTextMatcher.reconcileSegment(
                currentText: "Testing wrong writting",
                analyzedText: "Testing wrong writting",
                replacing: 14 ..< 22,
                with: "writing"
            ),
            .updated("Testing wrong writing")
        )
    }

    func testSegmentReconciliationPreservesShorterTextAlreadyUpdatedByAX() {
        XCTAssertEqual(
            ReplacementTextMatcher.reconcileSegment(
                currentText: "Testing wrong writing",
                analyzedText: "Testing wrong writting",
                replacing: 14 ..< 22,
                with: "writing"
            ),
            .sourceChanged
        )
    }

    func testSegmentReconciliationDoesNotDuplicateLongerReplacement() {
        XCTAssertEqual(
            ReplacementTextMatcher.reconcileSegment(
                currentText: "This is better",
                analyzedText: "This is bad",
                replacing: 8 ..< 11,
                with: "better"
            ),
            .sourceChanged
        )
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

    func testErrorSourceStoreAdvancesOnlyUnchangedSpansAfterCorrection() {
        let nextError = spellingError(start: 4, end: 9)
        let overlappingError = spellingError(start: 2, end: 5)
        let remainingErrors = [nextError, overlappingError]
        let original = "HEy thois"
        let corrected = "Hey thois"
        var store = GrammarErrorSourceStore()
        store.replace(errors: remainingErrors, sourceText: original)

        store.advanceUnchangedErrors(
            remainingErrors, replacing: 0 ..< 3, in: original, with: "Hey", matching: "Hey their"
        )
        XCTAssertEqual(store.sourceText(for: nextError, among: remainingErrors), original)

        store.advanceUnchangedErrors(
            remainingErrors, replacing: 0 ..< 3, in: original, with: "Hey", matching: corrected
        )
        store.replace(errors: remainingErrors, sourceText: corrected)
        XCTAssertEqual(store.sourceText(for: nextError, among: remainingErrors), corrected)
        XCTAssertEqual(store.sourceText(for: overlappingError, among: remainingErrors), original)
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
