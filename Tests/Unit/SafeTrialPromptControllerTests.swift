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
            "com.apple.ActivityMonitor",
            "com.apple.AppStore",
            "com.apple.finder",
            "com.apple.notificationcenterui",
            "com.apple.printcenter",
            "com.apple.systempreferences",
            "com.apple.UserNotificationCenter",
            "com.knollsoft.Rectangle",
            "com.apple.Passwords",
            "com.apple.Passwords.MenuBarExtra",
            "com.apple.keychainaccess",
            "com.apple.helpviewer",
            "com.apple.tips",
            "com.apple.DiskUtility",
            "com.apple.Console",
            "com.apple.tcc.AuthorizationPromptService",
        ]

        for bundleID in bundleIDs {
            XCTAssertEqual(registry.policy(for: bundleID), .ignored)
            XCTAssertTrue(registry.isIntentionallyDisabled(bundleID))
            XCTAssertFalse(registry.requiresSafeTrialConsent(for: bundleID))
            XCTAssertFalse(UserPreferences.shared.isEnabled(for: bundleID))
        }
    }

    func testEveryBuiltInExclusionWinsOverSavedConsentAndActiveOverrides() throws {
        let suite = "ApplicationExclusionsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UserPreferences(defaults: defaults)
        preferences.pauseDuration = .active

        for (bundleID, policy) in ApplicationPolicy.defaults where policy == .ignored {
            preferences.allowSafeTrial(for: bundleID)
            preferences.setPauseDuration(for: bundleID, duration: .active)
            XCTAssertFalse(preferences.isEnabled(for: bundleID), bundleID)
            XCTAssertFalse(AppRegistry.shared.requiresSafeTrialConsent(for: bundleID), bundleID)

            let decision = RuntimeHealthPolicy.evaluate(RuntimeHealthConditions(
                applicationSupported: !AppRegistry.shared.isIntentionallyDisabled(bundleID),
                permissionGranted: false,
                globalPaused: false,
                applicationPaused: false,
                applicationDisabled: false,
                consentGranted: true,
                availableCapabilities: .full,
                availableAction: .reportCompatibility
            ))
            XCTAssertFalse(decision.allowsMonitoring, bundleID)
            XCTAssertEqual(decision.reason, .unsupportedApplication, bundleID)
            XCTAssertNil(decision.action, bundleID)
        }
        preferences.resetToDefaults()
        XCTAssertFalse(preferences.isEnabled(for: "com.apple.helpviewer"))
    }

    func testExclusionsMatchWholeIdentifiersAndPreserveWritingApps() {
        let registry = AppRegistry.shared
        for bundleID in [
            "com.apple.Preview", "com.apple.iBooksX", "com.apple.Photos",
            "com.apple.Stickies", "com.apple.freeform", "com.apple.journal",
            "com.apple.shortcuts", "com.apple.ScriptEditor2", "com.apple.Automator",
            "com.apple.appleseed.FeedbackAssistant", "com.apple.ProblemReporter",
            "com.apple.accessibility.LiveSpeech", "com.apple.LinkedNotesUIService",
            "com.apple.helpviewer.editor", "com.apple.PasswordsHelper", "com.example.Passwords",
        ] {
            XCTAssertFalse(registry.isIntentionallyDisabled(bundleID), bundleID)
        }
        for bundleID in ["com.apple.TextEdit", "com.apple.mail", "com.apple.Notes", "com.apple.Safari"] {
            XCTAssertEqual(registry.policy(for: bundleID), .supported, bundleID)
        }
    }

    func testTerminalsArePausedByDefaultButStillRequireConsentWhenResumed() {
        let registry = AppRegistry.shared
        let bundleIDs = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "co.zeit.hyper",
            "dev.warp.Warp-Stable",
            "org.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "com.mitchellh.ghostty",
        ]

        XCTAssertEqual(registry.defaultPausedBundleIDs, Set(bundleIDs))
        for bundleID in bundleIDs {
            XCTAssertEqual(registry.policy(for: bundleID), .pausedByDefault)
            XCTAssertFalse(registry.isIntentionallyDisabled(bundleID))
            XCTAssertTrue(registry.requiresSafeTrialConsent(for: bundleID))
        }
    }

    func testUnregisteredWritingCandidateRemainsUnknown() {
        let registry = AppRegistry.shared
        let bundleID = "com.example.new-editor"

        XCTAssertEqual(registry.policy(for: bundleID), .safeTrial)
        XCTAssertFalse(registry.isIntentionallyDisabled(bundleID))
        XCTAssertTrue(registry.requiresSafeTrialConsent(for: bundleID))
    }

    func testConfiguredWritingAppIsSupported() {
        let registry = AppRegistry.shared

        XCTAssertEqual(registry.policy(for: "com.apple.TextEdit"), .supported)
        XCTAssertFalse(registry.requiresSafeTrialConsent(for: "com.apple.TextEdit"))
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
