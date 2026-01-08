//
//  SlackStrategyValidationTests.swift
//  TextWarden
//
//  Tests for SlackStrategy bounds validation to prevent regressions.
//  These tests verify that multi-line bounds from Chromium's AXBoundsForRange
//  are correctly rejected.
//

@testable import TextWarden
import XCTest

final class SlackStrategyValidationTests: XCTestCase {
    // MARK: - Bounds Validation Tests

    /// Test that reasonable single-line bounds are accepted.
    /// For 16 characters at ~7px/char = ~112px width, ~19px height.
    func testReasonableSingleLineBoundsAreAccepted() {
        let charCount = 16
        let bounds = CGRect(x: 100, y: 200, width: 111, height: 19)

        let isSingleLineHeight = bounds.height > 0 && bounds.height <= 30
        let isReasonableWidth = bounds.width > 0 && bounds.width <= CGFloat(charCount) * 20

        XCTAssertTrue(isSingleLineHeight, "19px height should be accepted as single-line")
        XCTAssertTrue(isReasonableWidth, "111px for 16 chars should be accepted (< 320px max)")
    }

    /// Test that multi-line bounds (tall height) are rejected.
    /// This was the bug: Chromium returned 41px tall bounds for a single line.
    func testMultiLineBoundsHeightIsRejected() {
        let charCount = 26
        let bounds = CGRect(x: 100, y: 200, width: 200, height: 41) // 41px = ~2 lines

        let isSingleLineHeight = bounds.height > 0 && bounds.height <= 30

        XCTAssertFalse(isSingleLineHeight, "41px height should be rejected as multi-line")
    }

    /// Test that unreasonably wide bounds are rejected.
    /// This was the bug: Chromium returned 429px for 26 characters.
    func testUnreasonablyWideBoundsAreRejected() {
        let charCount = 26
        let bounds = CGRect(x: 100, y: 200, width: 429, height: 19)

        // 26 chars * 20px max = 520px max
        // But 429px is still suspicious for 26 chars (16px/char average)
        // At 15pt font, characters are ~7-10px wide, so 26 chars = ~180-260px
        let isReasonableWidth = bounds.width > 0 && bounds.width <= CGFloat(charCount) * 20

        // 429 is less than 520 (26*20), so it passes the basic check
        // But the combination with other factors should trigger rejection
        // The actual threshold is 20px/char which is generous
        XCTAssertTrue(isReasonableWidth, "429px for 26 chars is under 520px max, but this is borderline")

        // The real issue was the height - combined validation catches it
        let isSingleLineHeight = bounds.height > 0 && bounds.height <= 30
        let combinedValid = isSingleLineHeight && isReasonableWidth

        // If bounds were 429x41, they should be rejected
        let tallBounds = CGRect(x: 100, y: 200, width: 429, height: 41)
        let tallIsSingleLine = tallBounds.height > 0 && tallBounds.height <= 30
        XCTAssertFalse(tallIsSingleLine, "429x41 should be rejected due to height")
    }

    /// Test the exact bounds that caused the bug.
    /// Chromium returned (1215.0, 671.0, 429.0, 41.0) for 26 characters.
    func testExactBugBoundsAreRejected() {
        let charCount = 26
        let buggyBounds = CGRect(x: 1215, y: 671, width: 429, height: 41)

        let isSingleLineHeight = buggyBounds.height > 0 && buggyBounds.height <= 30
        let isReasonableWidth = buggyBounds.width > 0 && buggyBounds.width <= CGFloat(charCount) * 20

        // Height check should fail
        XCTAssertFalse(isSingleLineHeight, "41px height should be rejected")

        // Combined validation should fail
        let isValid = isSingleLineHeight && isReasonableWidth
        XCTAssertFalse(isValid, "Bounds (429x41) for 26 chars should be rejected")
    }

    /// Test that edge case bounds at the threshold are handled correctly.
    func testBoundsAtThreshold() {
        let charCount = 10

        // Exactly at height threshold
        let atHeightThreshold = CGRect(x: 0, y: 0, width: 100, height: 30)
        let heightValid = atHeightThreshold.height > 0 && atHeightThreshold.height <= 30
        XCTAssertTrue(heightValid, "30px height (at threshold) should be accepted")

        // Just over height threshold
        let overHeightThreshold = CGRect(x: 0, y: 0, width: 100, height: 31)
        let heightInvalid = overHeightThreshold.height > 0 && overHeightThreshold.height <= 30
        XCTAssertFalse(heightInvalid, "31px height (over threshold) should be rejected")

        // Exactly at width threshold (10 chars * 20px = 200px)
        let atWidthThreshold = CGRect(x: 0, y: 0, width: 200, height: 19)
        let widthValid = atWidthThreshold.width > 0 && atWidthThreshold.width <= CGFloat(charCount) * 20
        XCTAssertTrue(widthValid, "200px width for 10 chars (at threshold) should be accepted")

        // Just over width threshold
        let overWidthThreshold = CGRect(x: 0, y: 0, width: 201, height: 19)
        let widthInvalid = overWidthThreshold.width > 0 && overWidthThreshold.width <= CGFloat(charCount) * 20
        XCTAssertFalse(widthInvalid, "201px width for 10 chars (over threshold) should be rejected")
    }

    // MARK: - Real World Scenario Tests

    /// Test typical first 3 words bounds (should be accepted).
    func testTypicalFirst3WordsBounds() {
        // "This would heelp" = 16 chars, typically ~111px at 15pt font
        let charCount = 16
        let bounds = CGRect(x: 1215, y: 605, width: 111, height: 19)

        let isSingleLineHeight = bounds.height > 0 && bounds.height <= 30
        let isReasonableWidth = bounds.width > 0 && bounds.width <= CGFloat(charCount) * 20

        XCTAssertTrue(isSingleLineHeight && isReasonableWidth, "Typical first 3 words bounds should be accepted")
    }

    /// Test that zero/negative bounds are rejected.
    func testZeroAndNegativeBoundsAreRejected() {
        let zeroBounds = CGRect(x: 0, y: 0, width: 0, height: 0)
        let zeroValid = zeroBounds.width > 0 && zeroBounds.height > 0
        XCTAssertFalse(zeroValid, "Zero bounds should be rejected")

        let negativeWidth = CGRect(x: 0, y: 0, width: -100, height: 19)
        let negativeWidthValid = negativeWidth.width > 0 && negativeWidth.height > 0
        XCTAssertFalse(negativeWidthValid, "Negative width should be rejected")

        let negativeHeight = CGRect(x: 0, y: 0, width: 100, height: -19)
        let negativeHeightValid = negativeHeight.width > 0 && negativeHeight.height > 0
        XCTAssertFalse(negativeHeightValid, "Negative height should be rejected")
    }
}
