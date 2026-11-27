@testable import TextWarden
import XCTest

final class GrammarResultMergerTests: XCTestCase {
    private func harper(_ start: Int, _ end: Int, lint: String = "Spelling::misspelled") -> GrammarErrorModel {
        GrammarErrorModel(
            start: start,
            end: end,
            message: "Harper",
            severity: .error,
            category: "Spelling",
            lintId: lint
        )
    }

    private func external(_ start: Int, _ end: Int, lint: String = "LanguageTool::RULE") -> GrammarErrorModel {
        GrammarErrorModel(
            start: start,
            end: end,
            message: "LanguageTool",
            severity: .warning,
            category: "Grammar",
            lintId: lint
        )
    }

    // MARK: - Overlap Policy

    /// Both engines flag common misspellings. Keeping both would draw two
    /// underlines on one word and count twice toward the underline ceiling.
    func testExactOverlapKeepsHarperOnly() {
        let merged = GrammarResultMerger.merge(primary: [harper(0, 4)], secondary: [external(0, 4)])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.message, "Harper")
    }

    func testPartialOverlapKeepsHarperOnly() {
        let merged = GrammarResultMerger.merge(primary: [harper(5, 10)], secondary: [external(8, 14)])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.message, "Harper")
    }

    func testExternalSpanContainingHarperSpanIsDropped() {
        let merged = GrammarResultMerger.merge(primary: [harper(6, 9)], secondary: [external(0, 20)])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.message, "Harper")
    }

    /// The point of the external source: spans Harper said nothing about.
    func testNonOverlappingExternalResultsSurvive() {
        let merged = GrammarResultMerger.merge(primary: [harper(0, 4)], secondary: [external(10, 15)])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.message), ["Harper", "LanguageTool"])
    }

    /// Ranges are half-open, so a span starting exactly where another ends is
    /// adjacent rather than overlapping.
    func testAdjacentSpansAreNotTreatedAsOverlapping() {
        let merged = GrammarResultMerger.merge(primary: [harper(0, 5)], secondary: [external(5, 9)])

        XCTAssertEqual(merged.count, 2)
    }

    func testOnlyOverlappingExternalResultsAreDropped() {
        let merged = GrammarResultMerger.merge(
            primary: [harper(0, 4), harper(20, 24)],
            secondary: [external(0, 4), external(10, 14), external(22, 30)]
        )

        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.map(\.start), [0, 10, 20])
    }

    // MARK: - Ordering and Duplicates

    func testResultsAreOrderedByPosition() {
        let merged = GrammarResultMerger.merge(
            primary: [harper(30, 34), harper(0, 4)],
            secondary: [external(20, 24), external(10, 14)]
        )

        XCTAssertEqual(merged.map(\.start), [0, 10, 20, 30])
    }

    func testIdenticalExternalResultsAreCollapsed() {
        let merged = GrammarResultMerger.merge(
            primary: [],
            secondary: [external(10, 14), external(10, 14)]
        )

        XCTAssertEqual(merged.count, 1)
    }

    /// LanguageTool routinely reports several rules across one span, such as a
    /// whitespace rule and a punctuation rule on the same comma. Drawing both
    /// would duplicate an underline, which is what the merge exists to avoid.
    func testOverlappingExternalResultsCollapse() {
        let merged = GrammarResultMerger.merge(
            primary: [],
            secondary: [
                external(4, 8, lint: "LanguageTool::COMMA_PARENTHESIS_WHITESPACE"),
                external(5, 7, lint: "LanguageTool::WHITESPACE_RULE"),
            ]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.start, 4, "The earliest result wins")
    }

    /// The same word misspelled twice is two errors, not one.
    func testSameRuleAtDifferentPositionsIsKept() {
        let merged = GrammarResultMerger.merge(
            primary: [],
            secondary: [external(10, 14), external(30, 34)]
        )

        XCTAssertEqual(merged.count, 2)
    }

    // MARK: - Underline Ceiling

    /// Above `maxErrorsForUnderlines` the overlay hides every underline, so a
    /// late external addition must not be what pushes the list over.
    func testExternalResultsAreTrimmedToTheCeiling() {
        let primary = (0 ..< 8).map { harper($0 * 10, $0 * 10 + 4) }
        let secondary = (0 ..< 5).map { external(200 + $0 * 10, 204 + $0 * 10) }

        let merged = GrammarResultMerger.merge(primary: primary, secondary: secondary, limit: 10)

        XCTAssertEqual(merged.count, 10)
        XCTAssertEqual(merged.filter { $0.message == "Harper" }.count, 8, "Harper results are never trimmed")
        XCTAssertEqual(merged.filter { $0.message == "LanguageTool" }.count, 2)
    }

    func testTrimmingKeepsTheEarliestExternalResults() {
        let merged = GrammarResultMerger.merge(
            primary: [harper(0, 4)],
            secondary: [external(300, 304), external(100, 104), external(200, 204)],
            limit: 3
        )

        XCTAssertEqual(merged.map(\.start), [0, 100, 200])
    }

    /// Once the primary set is over the ceiling the underlines are hidden
    /// regardless, so trimming would lose suggestions for no benefit.
    func testNothingIsTrimmedWhenPrimaryAlreadyExceedsTheCeiling() {
        let primary = (0 ..< 12).map { harper($0 * 10, $0 * 10 + 4) }
        let secondary = (0 ..< 5).map { external(200 + $0 * 10, 204 + $0 * 10) }

        let merged = GrammarResultMerger.merge(primary: primary, secondary: secondary, limit: 10)

        XCTAssertEqual(merged.count, 17)
    }

    func testNoLimitKeepsEverything() {
        let primary = (0 ..< 8).map { harper($0 * 10, $0 * 10 + 4) }
        let secondary = (0 ..< 5).map { external(200 + $0 * 10, 204 + $0 * 10) }

        XCTAssertEqual(GrammarResultMerger.merge(primary: primary, secondary: secondary).count, 13)
    }

    func testCeilingAppliesWithNoPrimaryResults() {
        let secondary = (0 ..< 9).map { external($0 * 10, $0 * 10 + 4) }

        let merged = GrammarResultMerger.merge(primary: [], secondary: secondary, limit: 4)

        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(merged.map(\.start), [0, 10, 20, 30])
    }

    /// An external result that is going to lose to Harper must not take a
    /// neighbour with it. Harper covers 0..<4 and says nothing about 6..<9, so
    /// 6..<9 is exactly the kind of span the external source exists to add.
    func testExternalResultLosingToHarperDoesNotDisplaceAValidNeighbour() {
        let merged = GrammarResultMerger.merge(
            primary: [harper(0, 4)],
            secondary: [external(3, 8), external(6, 9)],
            limit: nil
        )

        XCTAssertEqual(merged.map(\.start), [0, 6])
        XCTAssertEqual(
            merged.filter { $0.message == "LanguageTool" }.map(\.start),
            [6],
            "6..<9 overlaps no Harper result and must survive"
        )
    }

    /// The overlay hides underlines *above* the ceiling, not at it, so a
    /// primary set sitting exactly on the ceiling has no room for one more.
    func testNothingIsAddedWhenPrimarySitsExactlyOnTheCeiling() {
        let primary = (0 ..< 10).map { harper($0 * 10, $0 * 10 + 4) }

        let merged = GrammarResultMerger.merge(primary: primary, secondary: [external(500, 504)], limit: 10)

        XCTAssertEqual(merged.count, 10, "One more result would hide every underline")
        XCTAssertTrue(merged.allSatisfy { $0.message == "Harper" })
    }

    /// Collapsing a source's own overlaps has to stay correct when an early
    /// span is long enough to swallow several later ones.
    func testDeduplicationHandlesALongLeadingSpan() {
        let merged = GrammarResultMerger.merge(
            primary: [],
            secondary: [external(0, 100), external(10, 20), external(50, 60), external(150, 160)],
            limit: nil
        )

        XCTAssertEqual(merged.map(\.start), [0, 150])
    }

    // MARK: - Degenerate Inputs

    func testEmptySecondaryReturnsPrimaryInOrder() {
        let merged = GrammarResultMerger.merge(primary: [harper(9, 12), harper(0, 4)], secondary: [])

        XCTAssertEqual(merged.map(\.start), [0, 9])
    }

    func testEmptyPrimaryReturnsSecondaryInOrder() {
        let merged = GrammarResultMerger.merge(primary: [], secondary: [external(9, 12), external(0, 4)])

        XCTAssertEqual(merged.map(\.start), [0, 9])
    }

    func testBothEmptyReturnsEmpty() {
        XCTAssertTrue(GrammarResultMerger.merge(primary: [], secondary: []).isEmpty)
    }

    /// A server that returns a result for every word must not be able to push
    /// Harper's results out of the list.
    func testPrimaryResultsAreNeverDropped() {
        let primary = (0 ..< 50).map { harper($0 * 10, $0 * 10 + 4) }
        let secondary = (0 ..< 200).map { external($0 * 2, $0 * 2 + 5) }

        let merged = GrammarResultMerger.merge(primary: primary, secondary: secondary)

        for error in primary {
            XCTAssertTrue(
                merged.contains { $0.start == error.start && $0.end == error.end && $0.message == "Harper" },
                "Harper result at \(error.start) was dropped"
            )
        }
    }
}
