@testable import TextWarden
import XCTest

final class GrammarResultRebaserTests: XCTestCase {
    private func error(_ start: Int, _ end: Int, lintId: String = "LanguageTool::RULE") -> GrammarErrorModel {
        GrammarErrorModel(
            start: start,
            end: end,
            message: "Possible problem",
            severity: .warning,
            category: "Grammar",
            lintId: lintId,
            suggestions: []
        )
    }

    // MARK: - Unchanged Text

    func testIdenticalTextKeepsEverything() {
        let errors = [error(0, 3), error(10, 14)]
        let survivors = GrammarResultRebaser.surviving(
            errors,
            computedFor: "The cat sat down",
            stillValidIn: "The cat sat down"
        )
        XCTAssertEqual(survivors.count, 2)
    }

    // MARK: - Typing At The End

    /// The common case: text is appended after a finished word, so nothing the
    /// server already said becomes untrue.
    func testAppendingAfterAFinishedWordKeepsEverything() {
        let previous = "I will receive"
        let current = "I will receive the"
        let errors = [error(2, 6), error(7, 14)]

        let survivors = GrammarResultRebaser.surviving(errors, computedFor: previous, stillValidIn: current)
        XCTAssertEqual(survivors.count, 2)
    }

    /// The caveat that matters: the server judged a word the user had not
    /// finished typing, so its verdict on that fragment must go.
    func testFinishingAHalfTypedWordDiscardsOnlyThatWord() {
        let previous = "I will recei"
        let current = "I will receive"
        let fragment = error(7, 12, lintId: "LanguageTool::MORFOLOGIK_RULE")
        let earlier = error(2, 6)

        let survivors = GrammarResultRebaser.surviving(
            [earlier, fragment],
            computedFor: previous,
            stillValidIn: current
        )

        XCTAssertEqual(survivors.count, 1)
        XCTAssertEqual(survivors.first?.start, 2)
        XCTAssertEqual(survivors.first?.end, 6)
    }

    func testAppendingPunctuationKeepsTheWordBeforeIt() {
        let survivors = GrammarResultRebaser.surviving(
            [error(0, 5)],
            computedFor: "Hello",
            stillValidIn: "Hello!"
        )
        XCTAssertEqual(survivors.count, 1)
    }

    /// An apostrophe joins a word, so "don" and "don't" are not the same span.
    func testApostropheIsTreatedAsPartOfTheWord() {
        let survivors = GrammarResultRebaser.surviving(
            [error(4, 7)],
            computedFor: "You don",
            stillValidIn: "You don't"
        )
        XCTAssertTrue(survivors.isEmpty)
    }

    // MARK: - Editing Earlier

    func testEditInTheMiddleKeepsOnlyWhatPrecedesIt() {
        let previous = "The cat sat on the mat"
        let current = "The dog sat on the mat"
        let early = error(0, 3)
        let atTheEdit = error(4, 7)
        let after = error(8, 11)

        let survivors = GrammarResultRebaser.surviving(
            [early, atTheEdit, after],
            computedFor: previous,
            stillValidIn: current
        )

        XCTAssertEqual(survivors.map(\.start), [0])
    }

    func testDeletingInsideAWordDiscardsThatWord() {
        let survivors = GrammarResultRebaser.surviving(
            [error(0, 3), error(8, 13)],
            computedFor: "The dog barks",
            stillValidIn: "The dog bark"
        )
        XCTAssertEqual(survivors.map(\.start), [0])
    }

    func testChangingTheFirstWordKeepsNothing() {
        let survivors = GrammarResultRebaser.surviving(
            [error(0, 3), error(4, 7)],
            computedFor: "The cat",
            stillValidIn: "Any cat"
        )
        XCTAssertTrue(survivors.isEmpty)
    }

    func testEmptyInputIsHandled() {
        XCTAssertTrue(GrammarResultRebaser.surviving([], computedFor: "a", stillValidIn: "b").isEmpty)
        XCTAssertTrue(GrammarResultRebaser.surviving([error(0, 1)], computedFor: "a", stillValidIn: "").isEmpty)
    }

    // MARK: - Boundary Safety

    /// Offsets address characters, so a cut inside a grapheme cluster would
    /// produce a range the replacement path cannot apply.
    func testCutNeverFallsInsideAGraphemeCluster() {
        // A family emoji is one Character built from several scalars.
        let previous = "Hi 👨‍👩‍👧 there"
        let current = "Hi 👨‍👩‍👧 THERE"

        let boundary = GrammarResultRebaser.unchangedPrefixLength(of: previous, against: current)
        let graphemeBoundaries = TextIndexConverter.stringIndicesByScalarOffset(in: previous)
        XCTAssertNotNil(graphemeBoundaries[boundary], "Cut at \(boundary) splits a grapheme cluster")
    }

    func testCombiningMarksCountAsPartOfTheirWord() {
        // "café" written with a combining acute accent.
        let previous = "the cafe\u{0301}"
        let current = "the cafe\u{0301}s"

        let boundary = GrammarResultRebaser.unchangedPrefixLength(of: previous, against: current)
        let graphemeBoundaries = TextIndexConverter.stringIndicesByScalarOffset(in: previous)
        XCTAssertNotNil(graphemeBoundaries[boundary])
        // The word gained a letter, so nothing about that word survives.
        XCTAssertLessThanOrEqual(boundary, 4)
    }

    func testSurvivorsNeverExtendBeyondTheBoundary() {
        let previous = "Alpha beta gamma delta"
        let current = "Alpha beta gamma epsilon"
        let errors = [error(0, 5), error(6, 10), error(11, 16), error(17, 22)]

        let boundary = GrammarResultRebaser.unchangedPrefixLength(of: previous, against: current)
        let survivors = GrammarResultRebaser.surviving(errors, computedFor: previous, stillValidIn: current)

        for survivor in survivors {
            XCTAssertLessThanOrEqual(survivor.end, boundary)
        }
        XCTAssertEqual(survivors.count, 3)
    }
}
