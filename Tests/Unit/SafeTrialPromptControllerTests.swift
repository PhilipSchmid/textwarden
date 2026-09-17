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

    func testKnownExcludedAppsNeverRequireSafeTrial() {
        let registry = AppRegistry.shared
        let bundleIDs = [
            "com.apple.ActivityMonitor",
            "com.openai.sky.CUAService",
            "com.microsoft.errorreporting",
            "com.apple.Music",
            "com.readdle.PDFExpert-Mac",
            "com.apple.Photos",
            "com.apple.Preview",
            "com.apple.ProblemReporter",
            "com.apple.appleseed.FeedbackAssistant",
            "com.apple.AppStore",
            "com.apple.podcasts",
            "com.adobe.lightroomCC",
            "com.TechSmith.Snagit",
            "com.valvesoftware.steam",
            "com.valvesoftware.steam.helper",
            "com.docker.docker",
            "com.electron.dockerdesktop",
            "app.omlx",
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
            "com.1password.1password",
            "2BUA8C4S2C.com.1password.browser-helper",
            "com.1password.1password-launcher",
            "com.1password.OP-Updater",
            "com.1password.1password.helper",
            "com.1password.1password.helper.GPU",
            "com.1password.1password.helper.Renderer",
            "com.1password.1password.helper.Plugin",
            "org.sparkle-project.Sparkle.Autoupdate",
            "pro.betterdisplay.BetterDisplay",
            "com.steipete.codexbar",
            "com.adobe.acc.AdobeCreativeCloud",
            "com.adobe.acc.anc.AdobeCreativeCloud",
            "com.adobe.Creative-Cloud-Desktop-App",
            "Qisda.DDPM",
            "com.apple.IconComposer",
            "com.intego.commonservices.integomenu",
            "com.intego.virusbarrier.alert",
            "com.intego.virusbarrier.application",
            "com.intego.NetUpdate",
            "com.logi.optionsplus",
            "com.logi.cp-dev-mgr",
            "com.fabriceleyne.menubarstats",
            "com.fabriceleyne.menubarstatshelper",
            "com.microsoft.autoupdate2",
            "com.microsoft.autoupdate.fba",
            "com.microsoft.OneDrive",
            "wang.jianing.app.OpenInTerminal",
            "wang.jianing.app.OpenInTerminalHelper",
            "com.techsmith.snagit.capturehelper",
            "com.TechSmith.SupportSnagit",
            "io.tailscale.ipn.macos",
            "com.tresorit.mac",
            "com.stonerl.Thaw",
            "com.apple.universalcontrol",
            "com.apple.accessibility.universalAccessAuthWarn",
            "com.electron.wispr-flow.accessibility-mac-app",
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
            "com.apple.iBooksX",
            "com.apple.Stickies", "com.apple.freeform", "com.apple.journal",
            "com.apple.shortcuts", "com.apple.ScriptEditor2", "com.apple.Automator",
            "com.apple.accessibility.LiveSpeech", "com.apple.LinkedNotesUIService",
            "ai.unsloth.studio", "com.adobe.Photoshop", "com.microsoft.Word",
            "com.openai.codex", "com.readdle.PDFExpert-Mac.editor",
            "com.techsmith.snagit.capturehelper.editor", "com.1password.unlisted-editor",
            "com.apple.helpviewer.editor", "com.apple.PasswordsHelper", "com.example.Passwords",
        ] {
            XCTAssertFalse(registry.isIntentionallyDisabled(bundleID), bundleID)
        }
        for bundleID in ["com.apple.TextEdit", "com.apple.mail", "com.apple.Notes", "com.apple.Safari"] {
            XCTAssertEqual(registry.policy(for: bundleID), .supported, bundleID)
        }
    }

    func testDefaultPausesStillAllowOptInAndRequireConsent() throws {
        let registry = AppRegistry.shared
        let bundleIDs = [
            "app.crynta.terax",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "co.zeit.hyper",
            "dev.warp.Warp-Stable",
            "org.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "com.mitchellh.ghostty",
            "com.raycast.macos",
            "com.electron.wispr-flow",
        ]

        let suite = "DefaultPauseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UserPreferences(defaults: defaults)
        XCTAssertEqual(registry.defaultPausedBundleIDs, Set(bundleIDs))
        for bundleID in bundleIDs {
            XCTAssertEqual(registry.policy(for: bundleID), .pausedByDefault)
            XCTAssertFalse(registry.isIntentionallyDisabled(bundleID))
            XCTAssertTrue(registry.requiresSafeTrialConsent(for: bundleID))
            XCTAssertFalse(preferences.isEnabled(for: bundleID), bundleID)
            preferences.setPauseDuration(for: bundleID, duration: .active)
            preferences.allowSafeTrial(for: bundleID)
            XCTAssertTrue(preferences.isEnabled(for: bundleID), bundleID)
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
