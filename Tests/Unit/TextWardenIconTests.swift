//
//  TextWardenIconTests.swift
//  TextWardenTests
//

import AppKit
@testable import TextWarden
import XCTest

@MainActor
final class TextWardenIconTests: XCTestCase {
    func testPausedIconRemainsAStandardTemplateImage() throws {
        let activeIcon = TextWardenIcon.create()
        let pausedIcon = TextWardenIcon.createPaused()

        XCTAssertEqual(pausedIcon.size, activeIcon.size)
        XCTAssertTrue(pausedIcon.isTemplate)
        XCTAssertNotEqual(
            try XCTUnwrap(pausedIcon.tiffRepresentation),
            try XCTUnwrap(activeIcon.tiffRepresentation)
        )
    }

    func testIconStateFollowsTheActiveApplication() {
        XCTAssertEqual(
            MenuBarController.iconState(
                isEnabledForActiveApplication: true,
                isAwaitingConsent: false,
                matchingInactiveReason: nil
            ),
            .active
        )
        XCTAssertEqual(
            MenuBarController.iconState(
                isEnabledForActiveApplication: false,
                isAwaitingConsent: false,
                matchingInactiveReason: nil
            ),
            .inactive
        )
    }

    func testNonEditableFieldDoesNotLookPaused() {
        XCTAssertEqual(
            MenuBarController.iconState(
                isEnabledForActiveApplication: true,
                isAwaitingConsent: false,
                matchingInactiveReason: .noEditableField
            ),
            .active
        )
    }

    func testConsentAndPreferenceStateLookPaused() {
        XCTAssertEqual(
            MenuBarController.iconState(
                isEnabledForActiveApplication: true,
                isAwaitingConsent: true,
                matchingInactiveReason: nil
            ),
            .inactive
        )
        XCTAssertEqual(
            MenuBarController.iconState(
                isEnabledForActiveApplication: false,
                isAwaitingConsent: false,
                matchingInactiveReason: .appPause
            ),
            .inactive
        )
    }

    func testStaleRuntimePauseCannotOverrideCurrentPreferenceState() {
        XCTAssertEqual(
            MenuBarController.iconState(
                isEnabledForActiveApplication: true,
                isAwaitingConsent: false,
                matchingInactiveReason: .appPause
            ),
            .active
        )
    }
}
