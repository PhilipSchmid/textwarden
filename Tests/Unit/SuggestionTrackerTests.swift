//
//  SuggestionTrackerTests.swift
//  TextWarden
//
//  Tests for the SuggestionTracker unified loop prevention system.
//

@testable import TextWarden
import XCTest

final class SuggestionTrackerTests: XCTestCase {
    var tracker: SuggestionTracker!

    override func setUp() {
        super.setUp()
        tracker = SuggestionTracker()
    }

    override func tearDown() {
        tracker = nil
        super.tearDown()
    }

    // MARK: - Confidence Threshold Tests

    func testShouldShowStyleSuggestion_HighConfidence_ReturnsTrue() {
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "utilize",
            confidence: 0.85,
            impact: .medium,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertTrue(result, "High confidence suggestions should be shown")
    }

    func testShouldShowStyleSuggestion_LowConfidence_ReturnsFalse() {
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "utilize",
            confidence: 0.5,
            impact: .medium,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertFalse(result, "Low confidence suggestions should be filtered")
    }

    func testShouldShowStyleSuggestion_BoundaryConfidence_ReturnsTrue() {
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "utilize",
            confidence: 0.7,
            impact: .medium,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertTrue(result, "Confidence at threshold should be shown")
    }

    // MARK: - Impact Filtering Tests

    func testShouldShowStyleSuggestion_HighImpact_Minimal_ReturnsTrue() {
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "complex sentence",
            confidence: 0.85,
            impact: .high,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .minimal
        )
        XCTAssertTrue(result, "High impact suggestions should show with minimal sensitivity")
    }

    func testShouldShowStyleSuggestion_MediumImpact_Minimal_ReturnsFalse() {
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "some words",
            confidence: 0.85,
            impact: .medium,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .minimal
        )
        XCTAssertFalse(result, "Medium impact suggestions should not show with minimal sensitivity")
    }

    func testShouldShowStyleSuggestion_LowImpact_Balanced_ReturnsFalse() {
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "word",
            confidence: 0.75,
            impact: .low,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertFalse(result, "Low impact suggestions should not show with balanced sensitivity")
    }

    func testShouldShowStyleSuggestion_LowImpact_Detailed_ReturnsTrue() {
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "word",
            confidence: 0.75,
            impact: .low,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .detailed
        )
        XCTAssertTrue(result, "Low impact suggestions should show with detailed sensitivity")
    }

    // MARK: - Manual Check Tests

    func testShouldShowStyleSuggestion_ManualCheck_IgnoresImpact() {
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "word",
            confidence: 0.75,
            impact: .low,
            source: "appleIntelligence",
            isManualCheck: true,
            sensitivity: .minimal
        )
        XCTAssertTrue(result, "Manual check should show all suggestions regardless of impact")
    }

    // MARK: - Dismissed Suggestion Tests

    func testDismissedSuggestion_NotShownAgain() {
        let text = "some text to change"

        // First check should pass
        let firstResult = tracker.shouldShowStyleSuggestion(
            originalText: text,
            confidence: 0.85,
            impact: .high,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertTrue(firstResult)

        // Dismiss the suggestion
        tracker.markSuggestionDismissed(originalText: text)

        // Second check should fail
        let secondResult = tracker.shouldShowStyleSuggestion(
            originalText: text,
            confidence: 0.85,
            impact: .high,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertFalse(secondResult, "Dismissed suggestions should not be shown again")
    }

    // MARK: - Accepted Suggestion Tests

    func testAcceptedSuggestion_NotShownAgain() {
        let originalText = "complex text"
        let newText = "simple text"

        // Accept the suggestion
        tracker.markSuggestionAccepted(
            originalText: originalText,
            newText: newText,
            isReadability: false
        )

        // Check should fail for original text
        let result = tracker.shouldShowStyleSuggestion(
            originalText: originalText,
            confidence: 0.85,
            impact: .high,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertFalse(result, "Accepted suggestions should not be shown again")
    }

    // MARK: - Readability Tracking Tests

    func testReadabilitySuggestion_SimplifiedTextTracked() {
        let originalText = "The implementation of the sophisticated algorithm necessitates comprehensive analysis."
        let simplifiedText = "The advanced algorithm needs full analysis."

        // Accept readability suggestion
        tracker.markSuggestionAccepted(
            originalText: originalText,
            newText: simplifiedText,
            isReadability: true
        )

        // Original should not be suggested again
        let originalResult = tracker.shouldShowReadabilitySuggestion(
            sentenceText: originalText,
            isSimplified: false
        )
        XCTAssertFalse(originalResult, "Original text should be tracked as dismissed")

        // Simplified text should not be re-flagged
        let simplifiedResult = tracker.shouldShowReadabilitySuggestion(
            sentenceText: simplifiedText,
            isSimplified: false
        )
        XCTAssertFalse(simplifiedResult, "Simplified text should not be re-flagged as complex")
    }

    // MARK: - Auto Analysis Suppression Tests

    func testAutoAnalysis_SuppressedAfterAccept() {
        // Initially should be allowed
        XCTAssertTrue(tracker.shouldRunAutoStyleAnalysis())

        // Accept a suggestion
        tracker.markSuggestionAccepted(
            originalText: "some text",
            newText: "better text",
            isReadability: false
        )

        // Should be suppressed
        XCTAssertFalse(tracker.shouldRunAutoStyleAnalysis(), "Auto analysis should be suppressed after accepting suggestion")
    }

    func testAutoAnalysis_ReenabledAfterUserEdit() {
        // Accept a suggestion (suppresses auto analysis)
        tracker.markSuggestionAccepted(
            originalText: "some text",
            newText: "better text",
            isReadability: false
        )
        XCTAssertFalse(tracker.shouldRunAutoStyleAnalysis())

        // User makes a genuine edit
        tracker.notifyTextChanged(isGenuineEdit: true)

        // Should be re-enabled
        XCTAssertTrue(tracker.shouldRunAutoStyleAnalysis(), "Auto analysis should be re-enabled after user edit")
    }

    // MARK: - Reset Tests

    func testReset_ClearsAllState() {
        // Add some state
        tracker.markSuggestionDismissed(originalText: "text1")
        tracker.markSuggestionAccepted(originalText: "text2", newText: "new2", isReadability: false)

        // Reset
        tracker.reset()

        // Previously dismissed should now be showable
        let result = tracker.shouldShowStyleSuggestion(
            originalText: "text1",
            confidence: 0.85,
            impact: .high,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertTrue(result, "Reset should clear dismissed state")

        // Auto analysis should be allowed
        XCTAssertTrue(tracker.shouldRunAutoStyleAnalysis(), "Reset should clear suppression")
    }

    func testResetDismissed_ClearsDismissedOnly() {
        // Dismiss and accept suggestions
        tracker.markSuggestionDismissed(originalText: "dismissed")
        tracker.markSuggestionAccepted(originalText: "accepted", newText: "new", isReadability: false)

        // Reset dismissed only
        tracker.resetDismissed()

        // Dismissed suggestion should now be showable
        let dismissedResult = tracker.shouldShowStyleSuggestion(
            originalText: "dismissed",
            confidence: 0.85,
            impact: .high,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertTrue(dismissedResult, "ResetDismissed should clear dismissed state")

        // Auto analysis should be allowed (suppression cleared)
        XCTAssertTrue(tracker.shouldRunAutoStyleAnalysis(), "ResetDismissed should clear suppression")
    }

    // MARK: - Cooldown Tests

    func testShownSuggestion_CooldownPreventsImmediate() {
        let text = "some text"

        // Mark as shown
        tracker.markSuggestionShown(originalText: text, source: "appleIntelligence")

        // Should be blocked due to cooldown
        let result = tracker.shouldShowStyleSuggestion(
            originalText: text,
            confidence: 0.85,
            impact: .high,
            source: "appleIntelligence",
            isManualCheck: false,
            sensitivity: .balanced
        )
        XCTAssertFalse(result, "Recently shown suggestions should be blocked by cooldown")
    }
}
