//
//  SafeTrialPromptControllerTests.swift
//  TextWardenTests
//

import AppKit
@testable import TextWarden
import XCTest

@MainActor
final class SafeTrialPromptControllerTests: XCTestCase {
    private let textWardenBundleID = "io.textwarden.TextWarden"
    private let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
    private let visibleFrame = NSRect(x: 0, y: 0, width: 1512, height: 956)

    func testTextWardenIsKnownButDisabledForExternalMonitoring() {
        let registry = AppRegistry.shared

        XCTAssertTrue(registry.hasConfiguration(for: textWardenBundleID))
        XCTAssertFalse(registry.configuration(for: textWardenBundleID).features.visualUnderlinesEnabled)
        XCTAssertFalse(UserPreferences.shared.isEnabled(for: textWardenBundleID))
    }

    func testKnownNonWritingSystemAppsNeverRequireSafeTrial() {
        let registry = AppRegistry.shared
        let bundleIDs = [
            "com.apple.finder",
            "com.apple.notificationcenterui",
            "com.apple.systempreferences",
            "com.apple.UserNotificationCenter",
        ]

        for bundleID in bundleIDs {
            XCTAssertTrue(registry.isKnownApplication(bundleID))
            XCTAssertTrue(registry.isIntentionallyDisabled(bundleID))
            XCTAssertFalse(UserPreferences.shared.isEnabled(for: bundleID))
        }
    }

    func testUnregisteredWritingCandidateRemainsUnknown() {
        let registry = AppRegistry.shared
        let bundleID = "com.example.new-editor"

        XCTAssertFalse(registry.isKnownApplication(bundleID))
        XCTAssertFalse(registry.isIntentionallyDisabled(bundleID))
    }

    func testVisibleStatusItemIsAUsablePopoverAnchor() {
        let statusItemFrame = NSRect(x: 1400, y: 956, width: 28, height: 26)

        XCTAssertTrue(isUsable(statusItemFrame))
    }

    func testOffscreenStatusItemUsedByMenuBarManagerIsRejected() {
        let hiddenStatusItemFrame = NSRect(x: -40, y: 956, width: 28, height: 26)

        XCTAssertFalse(isUsable(hiddenStatusItemFrame))
    }

    func testProxyBarPositionIsRejected() {
        let proxyBarFrame = NSRect(x: 1000, y: 875, width: 28, height: 26)

        XCTAssertFalse(isUsable(proxyBarFrame))
    }

    func testCollapsedStatusItemIsRejected() {
        let collapsedStatusItemFrame = NSRect(x: 1400, y: 956, width: 1, height: 26)

        XCTAssertFalse(isUsable(collapsedStatusItemFrame))
    }

    func testFallbackPanelStaysInsideTargetWindowNearTopRight() {
        let origin = SafeTrialPromptController.fallbackPanelOrigin(
            panelSize: NSSize(width: 352, height: 156),
            targetWindowFrame: NSRect(x: 100, y: 80, width: 1100, height: 800),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: 832, y: 708))
    }

    func testQuartzWindowFrameConvertsToAppKitCoordinates() {
        let quartzFrame = NSRect(x: 100, y: 50, width: 800, height: 600)

        XCTAssertEqual(
            SafeTrialPromptController.cocoaFrame(fromQuartzFrame: quartzFrame, primaryScreenMaxY: 982),
            NSRect(x: 100, y: 332, width: 800, height: 600)
        )
    }

    func testFallbackPanelCanAppearOverFullScreenApplications() {
        let behavior = SafeTrialPromptController.fallbackCollectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.stationary))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertGreaterThan(
            SafeTrialPromptController.fallbackWindowLevel.rawValue,
            NSWindow.Level.floating.rawValue
        )
    }

    private func isUsable(_ frame: NSRect) -> Bool {
        SafeTrialPromptController.isUsableAnchorFrame(
            frame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )
    }
}
