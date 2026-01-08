//
//  UnderlineStateManagerTests.swift
//  TextWardenTests
//
//  Unit tests for UnderlineStateManager to verify state consistency
//  and invariant enforcement.
//

@testable import TextWarden
import XCTest

final class UnderlineStateManagerTests: XCTestCase {
    var manager: UnderlineStateManager!
    var stateChanges: [UnderlineState]!

    override func setUp() {
        super.setUp()
        manager = UnderlineStateManager()
        stateChanges = []
        manager.onStateChanged = { [weak self] state in
            self?.stateChanges.append(state)
        }
    }

    override func tearDown() {
        manager = nil
        stateChanges = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsEmpty() {
        XCTAssertTrue(manager.currentState.grammarUnderlines.isEmpty)
        XCTAssertTrue(manager.currentState.styleUnderlines.isEmpty)
        XCTAssertTrue(manager.currentState.readabilityUnderlines.isEmpty)
        XCTAssertNil(manager.currentState.hoveredGrammarIndex)
        XCTAssertNil(manager.currentState.hoveredStyleIndex)
        XCTAssertNil(manager.currentState.hoveredReadabilityIndex)
        XCTAssertNil(manager.currentState.lockedHighlightIndex)
        XCTAssertFalse(manager.currentState.hasContent)
    }

    // MARK: - Atomic Update Tests

    func testUpdateAllSetsAllUnderlines() {
        let grammarUnderlines = createMockGrammarUnderlines(count: 2)
        let styleUnderlines = createMockStyleUnderlines(count: 1)
        let readabilityUnderlines = createMockReadabilityUnderlines(count: 3)

        manager.updateAll(
            grammarUnderlines: grammarUnderlines,
            styleUnderlines: styleUnderlines,
            readabilityUnderlines: readabilityUnderlines
        )

        XCTAssertEqual(manager.currentState.grammarUnderlines.count, 2)
        XCTAssertEqual(manager.currentState.styleUnderlines.count, 1)
        XCTAssertEqual(manager.currentState.readabilityUnderlines.count, 3)
        XCTAssertTrue(manager.currentState.hasContent)
        XCTAssertEqual(stateChanges.count, 1)
    }

    func testClearRemovesAllState() {
        // Setup initial state
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: createMockStyleUnderlines(count: 1),
            readabilityUnderlines: createMockReadabilityUnderlines(count: 1)
        )
        manager.setHoveredGrammarIndex(0)
        manager.setLockedHighlightIndex(1)

        // Clear
        manager.clear()

        XCTAssertTrue(manager.currentState.grammarUnderlines.isEmpty)
        XCTAssertTrue(manager.currentState.styleUnderlines.isEmpty)
        XCTAssertTrue(manager.currentState.readabilityUnderlines.isEmpty)
        XCTAssertNil(manager.currentState.hoveredGrammarIndex)
        XCTAssertNil(manager.currentState.lockedHighlightIndex)
        XCTAssertFalse(manager.currentState.hasContent)
    }

    // MARK: - Partial Clear Tests

    func testClearGrammarUnderlines_PreservesReadability() {
        // Setup both grammar and readability underlines
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: createMockStyleUnderlines(count: 1),
            readabilityUnderlines: createMockReadabilityUnderlines(count: 3)
        )
        manager.setHoveredReadabilityIndex(1)

        // Clear only grammar
        manager.clearGrammarUnderlines()

        // Grammar and style should be cleared
        XCTAssertTrue(manager.currentState.grammarUnderlines.isEmpty)
        XCTAssertTrue(manager.currentState.styleUnderlines.isEmpty)
        XCTAssertNil(manager.currentState.hoveredGrammarIndex)
        XCTAssertNil(manager.currentState.lockedHighlightIndex)

        // Readability should be preserved
        XCTAssertEqual(manager.currentState.readabilityUnderlines.count, 3)
        XCTAssertEqual(manager.currentState.hoveredReadabilityIndex, 1)
        XCTAssertTrue(manager.currentState.hasContent)
    }

    func testClearReadabilityUnderlines_PreservesGrammar() {
        // Setup both grammar and readability underlines
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: createMockStyleUnderlines(count: 1),
            readabilityUnderlines: createMockReadabilityUnderlines(count: 3)
        )
        manager.setHoveredGrammarIndex(1)
        manager.setLockedHighlightIndex(0)

        // Clear only readability
        manager.clearReadabilityUnderlines()

        // Readability should be cleared
        XCTAssertTrue(manager.currentState.readabilityUnderlines.isEmpty)
        XCTAssertNil(manager.currentState.hoveredReadabilityIndex)

        // Grammar and style should be preserved
        XCTAssertEqual(manager.currentState.grammarUnderlines.count, 2)
        XCTAssertEqual(manager.currentState.styleUnderlines.count, 1)
        XCTAssertEqual(manager.currentState.hoveredGrammarIndex, 1)
        XCTAssertEqual(manager.currentState.lockedHighlightIndex, 0)
        XCTAssertTrue(manager.currentState.hasContent)
    }

    // MARK: - Partial Update Tests

    func testUpdateGrammarUnderlines_PreservesReadability() {
        // Setup initial state with readability underlines
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 1),
            styleUnderlines: [],
            readabilityUnderlines: createMockReadabilityUnderlines(count: 3)
        )
        manager.setHoveredReadabilityIndex(1)

        // Update grammar underlines
        manager.updateGrammarUnderlines(
            createMockGrammarUnderlines(count: 2),
            styleUnderlines: createMockStyleUnderlines(count: 1)
        )

        // Readability should be preserved
        XCTAssertEqual(manager.currentState.readabilityUnderlines.count, 3)
        XCTAssertEqual(manager.currentState.hoveredReadabilityIndex, 1)

        // Grammar and style should be updated
        XCTAssertEqual(manager.currentState.grammarUnderlines.count, 2)
        XCTAssertEqual(manager.currentState.styleUnderlines.count, 1)
    }

    func testUpdateReadabilityUnderlines_PreservesGrammar() {
        // Setup initial state with grammar underlines
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: createMockStyleUnderlines(count: 1),
            readabilityUnderlines: []
        )
        manager.setHoveredGrammarIndex(1)
        manager.setLockedHighlightIndex(0)

        // Update readability underlines
        manager.updateReadabilityUnderlines(createMockReadabilityUnderlines(count: 2))

        // Grammar and style should be preserved
        XCTAssertEqual(manager.currentState.grammarUnderlines.count, 2)
        XCTAssertEqual(manager.currentState.styleUnderlines.count, 1)
        XCTAssertEqual(manager.currentState.hoveredGrammarIndex, 1)
        XCTAssertEqual(manager.currentState.lockedHighlightIndex, 0)

        // Readability should be updated
        XCTAssertEqual(manager.currentState.readabilityUnderlines.count, 2)
    }

    func testUpdateGrammarUnderlines_PreservesValidHoverIndex() {
        // Setup initial state
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 3),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        manager.setHoveredGrammarIndex(1)

        // Update with same or more underlines - hover should be preserved
        manager.updateGrammarUnderlines(
            createMockGrammarUnderlines(count: 3),
            styleUnderlines: []
        )

        XCTAssertEqual(manager.currentState.hoveredGrammarIndex, 1)
    }

    func testUpdateGrammarUnderlines_ClearsInvalidHoverIndex() {
        // Setup initial state
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 3),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        manager.setHoveredGrammarIndex(2) // Last item

        // Update with fewer underlines - hover should be cleared
        manager.updateGrammarUnderlines(
            createMockGrammarUnderlines(count: 1),
            styleUnderlines: []
        )

        XCTAssertNil(manager.currentState.hoveredGrammarIndex)
    }

    // MARK: - Invariant Tests

    func testInvariant_EmptyGrammarMeansEmptyGrammarUnderlines() {
        // When we update with empty grammar array
        manager.updateAll(
            grammarUnderlines: [],
            styleUnderlines: [],
            readabilityUnderlines: createMockReadabilityUnderlines(count: 2)
        )

        // Grammar underlines should be empty (not stale!)
        XCTAssertTrue(manager.currentState.grammarUnderlines.isEmpty)
        // But readability should exist
        XCTAssertEqual(manager.currentState.readabilityUnderlines.count, 2)
    }

    func testInvariant_HoverIndexClearedWhenUnderlineRemoved() {
        // Setup with hover
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 3),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        manager.setHoveredGrammarIndex(2) // Hover on last item

        // Remove underlines (simulate error being fixed)
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 1), // Only 1 left
            styleUnderlines: [],
            readabilityUnderlines: []
        )

        // Hover index should be cleared (was 2, but only 0 is valid now)
        XCTAssertNil(manager.currentState.hoveredGrammarIndex)
    }

    func testInvariant_HoverIndexPreservedWhenValid() {
        // Setup with hover
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 3),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        manager.setHoveredGrammarIndex(1) // Hover on middle item

        // Update with same count
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 3),
            styleUnderlines: [],
            readabilityUnderlines: []
        )

        // Hover index should be preserved
        XCTAssertEqual(manager.currentState.hoveredGrammarIndex, 1)
    }

    func testInvariant_LockedHighlightClearedWhenUnderlineRemoved() {
        // Setup with locked highlight
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        manager.setLockedHighlightIndex(1)

        // Remove underlines
        manager.updateAll(
            grammarUnderlines: [],
            styleUnderlines: [],
            readabilityUnderlines: []
        )

        // Locked highlight should be cleared
        XCTAssertNil(manager.currentState.lockedHighlightIndex)
    }

    // MARK: - Hover State Tests

    func testSetHoveredGrammarIndex_ValidIndex() {
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 3),
            styleUnderlines: [],
            readabilityUnderlines: []
        )

        manager.setHoveredGrammarIndex(1)

        XCTAssertEqual(manager.currentState.hoveredGrammarIndex, 1)
        XCTAssertNotNil(manager.currentState.hoveredGrammarUnderline)
    }

    func testSetHoveredGrammarIndex_InvalidIndexIgnored() {
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: [],
            readabilityUnderlines: []
        )

        manager.setHoveredGrammarIndex(5) // Invalid index

        // Should be ignored, remain nil
        XCTAssertNil(manager.currentState.hoveredGrammarIndex)
    }

    func testSetHoveredGrammarIndex_Nil_ClearsHover() {
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        manager.setHoveredGrammarIndex(0)

        manager.setHoveredGrammarIndex(nil)

        XCTAssertNil(manager.currentState.hoveredGrammarIndex)
    }

    func testClearHoverState_ClearsAllHovers() {
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: createMockStyleUnderlines(count: 1),
            readabilityUnderlines: createMockReadabilityUnderlines(count: 1)
        )
        manager.setHoveredGrammarIndex(0)
        manager.setHoveredStyleIndex(0)
        manager.setHoveredReadabilityIndex(0)

        manager.clearHoverState()

        XCTAssertNil(manager.currentState.hoveredGrammarIndex)
        XCTAssertNil(manager.currentState.hoveredStyleIndex)
        XCTAssertNil(manager.currentState.hoveredReadabilityIndex)
    }

    // MARK: - Locked Highlight Tests

    func testSetLockedHighlightIndex() {
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 3),
            styleUnderlines: [],
            readabilityUnderlines: []
        )

        manager.setLockedHighlightIndex(2)

        XCTAssertEqual(manager.currentState.lockedHighlightIndex, 2)
        XCTAssertNotNil(manager.currentState.lockedHighlightUnderline)
    }

    func testClearLockedHighlight() {
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        manager.setLockedHighlightIndex(0)

        manager.clearLockedHighlight()

        XCTAssertNil(manager.currentState.lockedHighlightIndex)
    }

    // MARK: - State Change Notification Tests

    func testStateChangeNotification_OnlyFiredWhenChanged() {
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        let initialChangeCount = stateChanges.count

        // Same hover index (already nil)
        manager.setHoveredGrammarIndex(nil)

        // No additional notification
        XCTAssertEqual(stateChanges.count, initialChangeCount)
    }

    func testStateChangeNotification_FiredOnActualChange() {
        manager.updateAll(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: [],
            readabilityUnderlines: []
        )
        let initialChangeCount = stateChanges.count

        // New hover index
        manager.setHoveredGrammarIndex(0)

        // Should fire notification
        XCTAssertEqual(stateChanges.count, initialChangeCount + 1)
    }

    // MARK: - UnderlineState Validation Tests

    func testUnderlineStateValidation_ValidState() {
        let state = UnderlineState(
            grammarUnderlines: createMockGrammarUnderlines(count: 2),
            styleUnderlines: [],
            readabilityUnderlines: [],
            hoveredGrammarIndex: 1,
            hoveredStyleIndex: nil,
            hoveredReadabilityIndex: nil,
            lockedHighlightIndex: 0
        )

        XCTAssertTrue(state.validateInvariants())
    }

    func testUnderlineStateEmpty() {
        let state = UnderlineState.empty

        XCTAssertTrue(state.grammarUnderlines.isEmpty)
        XCTAssertTrue(state.styleUnderlines.isEmpty)
        XCTAssertTrue(state.readabilityUnderlines.isEmpty)
        XCTAssertFalse(state.hasContent)
        XCTAssertTrue(state.validateInvariants())
    }

    // MARK: - Helper Methods

    private func createMockGrammarUnderlines(count: Int) -> [ErrorUnderline] {
        var result: [ErrorUnderline] = []
        for index in 0 ..< count {
            let bounds = CGRect(x: CGFloat(index * 50), y: 0, width: 40, height: 20)
            let error = GrammarErrorModel(
                start: index * 10,
                end: index * 10 + 5,
                message: "Error \(index)",
                severity: .error,
                category: "Spelling",
                lintId: "test_\(index)",
                suggestions: ["fix"]
            )
            let underline = ErrorUnderline(
                bounds: bounds,
                drawingBounds: bounds,
                allDrawingBounds: [bounds],
                color: .red,
                error: error
            )
            result.append(underline)
        }
        return result
    }

    private func createMockStyleUnderlines(count: Int) -> [StyleUnderline] {
        var result: [StyleUnderline] = []
        for index in 0 ..< count {
            let bounds = CGRect(x: CGFloat(index * 50), y: 0, width: 40, height: 20)
            let suggestion = StyleSuggestionModel(
                originalStart: index * 10,
                originalEnd: index * 10 + 5,
                originalText: "test",
                suggestedText: "suggestion",
                explanation: "explanation"
            )
            let underline = StyleUnderline(
                bounds: bounds,
                drawingBounds: bounds,
                suggestion: suggestion
            )
            result.append(underline)
        }
        return result
    }

    private func createMockReadabilityUnderlines(count: Int) -> [ReadabilityUnderline] {
        var result: [ReadabilityUnderline] = []
        for index in 0 ..< count {
            let bounds = CGRect(x: CGFloat(index * 100), y: 0, width: 80, height: 20)
            let sentenceResult = SentenceReadabilityResult(
                sentence: "Complex sentence \(index)",
                range: NSRange(location: index * 20, length: 15),
                score: 50.0,
                wordCount: 10,
                isComplex: true,
                targetAudience: .general
            )
            // Use convenience initializer for single-line underlines
            let underline = ReadabilityUnderline(
                bounds: bounds,
                drawingBounds: bounds,
                sentenceResult: sentenceResult
            )
            result.append(underline)
        }
        return result
    }
}
