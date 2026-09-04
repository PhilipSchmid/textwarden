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
}
