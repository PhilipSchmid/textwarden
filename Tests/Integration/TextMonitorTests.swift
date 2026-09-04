//
//  TextMonitorTests.swift
//  TextWarden Integration Tests
//

@testable import TextWarden
import XCTest

final class TextMonitorTests: XCTestCase {
    func testFocusSettlingDelay_IsOptimal() {
        let settlingDelay = TimingConstants.focusSettlingDelay

        XCTAssertGreaterThanOrEqual(settlingDelay, 0.05)
        XCTAssertLessThanOrEqual(settlingDelay, 0.15)
        XCTAssertEqual(settlingDelay, 0.08)
    }

    func testProtectedFocusedFieldNeverUsesAlternativeTraversal() {
        let disposition = FocusedElementPolicy.disposition(
            isProtected: true,
            isEditable: false,
            isValidContent: false
        )

        XCTAssertEqual(disposition, .stopForProtectedField)
    }

    func testInvalidNonProtectedFocusStillUsesCompatibilityTraversal() {
        let disposition = FocusedElementPolicy.disposition(
            isProtected: false,
            isEditable: false,
            isValidContent: false
        )

        XCTAssertEqual(disposition, .searchForAlternative)
    }

    func testOnlyProtectedAppsRefreshTransientNonEditableFocusEvents() {
        XCTAssertTrue(
            FocusedElementPolicy.shouldRefreshFromAuthoritativeFocus(
                disposition: .searchForAlternative,
                hasFocusBounceProtection: true
            )
        )
        XCTAssertFalse(
            FocusedElementPolicy.shouldRefreshFromAuthoritativeFocus(
                disposition: .stopForProtectedField,
                hasFocusBounceProtection: true
            )
        )
        XCTAssertFalse(
            FocusedElementPolicy.shouldRefreshFromAuthoritativeFocus(
                disposition: .searchForAlternative,
                hasFocusBounceProtection: false
            )
        )
    }

    func testFocusProtectedWebAppsWaitForEditableFocusInsteadOfScanning() {
        XCTAssertTrue(
            FocusedElementPolicy.shouldWaitForEditableWebFocus(
                disposition: .searchForAlternative,
                hasFocusBounceProtection: true,
                hasWebBasedRendering: true
            )
        )
        XCTAssertFalse(
            FocusedElementPolicy.shouldWaitForEditableWebFocus(
                disposition: .useFocusedElement,
                hasFocusBounceProtection: true,
                hasWebBasedRendering: true
            )
        )
        XCTAssertFalse(
            FocusedElementPolicy.shouldWaitForEditableWebFocus(
                disposition: .searchForAlternative,
                hasFocusBounceProtection: false,
                hasWebBasedRendering: true
            )
        )
    }

    func testContextChangeClearsOnlyWhenAXConfirmsMismatch() {
        XCTAssertTrue(FocusedElementPolicy.shouldClearForConfirmedContextChange(matches: false))
        XCTAssertFalse(FocusedElementPolicy.shouldClearForConfirmedContextChange(matches: true))
        XCTAssertFalse(FocusedElementPolicy.shouldClearForConfirmedContextChange(matches: nil))
    }

    func testNotionRejectsTransientRootWebArea() {
        XCTAssertFalse(NotionContentParser.isEditableContentRole("AXWebArea"))
        XCTAssertTrue(NotionContentParser.isEditableContentRole("AXTextArea"))
    }
}
