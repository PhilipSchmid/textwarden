//
//  AppBehaviorConsistencyTests.swift
//  TextWarden
//
//  Consistency tests to ensure all app behaviors are correctly configured.
//  These tests catch common mistakes when adding new app behaviors.
//

@testable import TextWarden
import XCTest

final class AppBehaviorConsistencyTests: XCTestCase {
    // MARK: - All Behaviors Collection

    /// Get all registered behaviors for testing
    private var allBehaviors: [AppBehavior] {
        AppBehaviorRegistry.shared.registeredBundleIDs.compactMap {
            AppBehaviorRegistry.shared.registeredBehavior(for: $0)
        }
    }

    // MARK: - Basic Validity Tests

    func testAllBehaviorsHaveNonEmptyBundleID() {
        for behavior in allBehaviors {
            XCTAssertFalse(
                behavior.bundleIdentifier.isEmpty,
                "\(behavior.displayName) has empty bundle identifier"
            )
        }
    }

    func testAllBehaviorsHaveNonEmptyDisplayName() {
        for behavior in allBehaviors {
            XCTAssertFalse(
                behavior.displayName.isEmpty,
                "Behavior for \(behavior.bundleIdentifier) has empty display name"
            )
        }
    }

    func testNoDuplicateBundleIDs() {
        let bundleIDs = AppBehaviorRegistry.shared.registeredBundleIDs
        let uniqueBundleIDs = Set(bundleIDs)

        XCTAssertEqual(
            bundleIDs.count,
            uniqueBundleIDs.count,
            "Found duplicate bundle IDs in registry"
        )
    }

    func testRegistryHasExpectedApps() {
        // Core apps that should always be registered
        let expectedApps = [
            "com.tinyspeck.slackmacgap",
            "notion.id",
            "com.apple.mail",
            "com.microsoft.Word",
            "com.microsoft.Powerpoint",
            "com.microsoft.Outlook",
            "com.microsoft.teams2",
            "com.apple.iWork.Pages",
            "com.anthropic.claudefordesktop",
            "com.openai.chat",
            "ai.perplexity.mac",
        ]

        for bundleID in expectedApps {
            XCTAssertTrue(
                AppBehaviorRegistry.shared.hasRegisteredBehavior(for: bundleID),
                "Expected app \(bundleID) is not registered"
            )
        }
    }

    // MARK: - Quirk Consistency Tests

    func testBrowserStyleAppsHaveCorrectQuirk() {
        // Apps that use browser-style replacement should have the quirk
        let browserStyleApps = [
            "com.tinyspeck.slackmacgap",
            "notion.id",
            "com.microsoft.teams2",
            "com.anthropic.claudefordesktop",
            "com.openai.chat",
            "ai.perplexity.mac",
            "com.microsoft.Word",
            "com.microsoft.Powerpoint",
            "com.microsoft.Outlook",
        ]

        for bundleID in browserStyleApps {
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            XCTAssertTrue(
                behavior.knownQuirks.contains(.requiresBrowserStyleReplacement),
                "\(bundleID) should have requiresBrowserStyleReplacement quirk"
            )
        }
    }

    func testWebBasedAppsHaveCorrectQuirk() {
        // Web-based apps should have the webBasedRendering quirk
        let webBasedApps = [
            "com.tinyspeck.slackmacgap",
            "notion.id",
            "com.microsoft.teams2",
            "com.anthropic.claudefordesktop",
            "com.openai.chat",
            "ai.perplexity.mac",
        ]

        for bundleID in webBasedApps {
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            XCTAssertTrue(
                behavior.knownQuirks.contains(.webBasedRendering),
                "\(bundleID) should have webBasedRendering quirk"
            )
        }
    }

    func testNativeAppsDoNotHaveWebBasedQuirk() {
        // Native macOS apps should NOT have webBasedRendering quirk
        let nativeApps = [
            "com.apple.mail",
            "com.microsoft.Word",
            "com.microsoft.Powerpoint",
            "com.microsoft.Outlook",
            "com.apple.iWork.Pages",
            "com.apple.Notes",
            "com.apple.TextEdit",
        ]

        for bundleID in nativeApps {
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            XCTAssertFalse(
                behavior.knownQuirks.contains(.webBasedRendering),
                "\(bundleID) is native and should NOT have webBasedRendering quirk"
            )
        }
    }

    func testFocusPasteAppsHaveCorrectQuirk() {
        // Apps using focus+select+paste replacement
        let focusPasteApps = [
            "com.microsoft.Word",
            "com.microsoft.Powerpoint",
            "com.microsoft.Outlook",
            "com.apple.iWork.Pages",
        ]

        for bundleID in focusPasteApps {
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            XCTAssertTrue(
                behavior.knownQuirks.contains(.requiresFocusPasteReplacement),
                "\(bundleID) should have requiresFocusPasteReplacement quirk"
            )
        }
    }

    // MARK: - UTF-16 Index Consistency Tests

    func testElectronAppsUseUTF16Indices() {
        // Electron/Chromium apps should use UTF-16 indices
        let electronApps = [
            "com.tinyspeck.slackmacgap",
            "notion.id",
            "com.microsoft.teams2",
            "com.anthropic.claudefordesktop",
            "com.openai.chat",
            "ai.perplexity.mac",
        ]

        for bundleID in electronApps {
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            XCTAssertTrue(
                behavior.usesUTF16TextIndices,
                "\(bundleID) is Electron-based and should use UTF-16 indices"
            )
        }
    }

    func testNativeAppsUseGraphemeIndices() {
        // Native macOS apps (non-WebKit/Catalyst) should use grapheme indices
        let nativeApps = [
            "com.microsoft.Word",
            "com.microsoft.Powerpoint",
            "com.microsoft.Outlook",
            "com.apple.iWork.Pages",
            "com.apple.Notes",
            "com.apple.TextEdit",
        ]

        for bundleID in nativeApps {
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            XCTAssertFalse(
                behavior.usesUTF16TextIndices,
                "\(bundleID) is native and should use grapheme indices (not UTF-16)"
            )
        }
    }

    func testWebKitCatalystAppsUseUTF16Indices() {
        // WebKit-based and Mac Catalyst apps use UTF-16 indices
        let webKitCatalystApps = [
            "com.apple.mail", // WebKit compose view
            "com.apple.MobileSMS", // Mac Catalyst
        ]

        for bundleID in webKitCatalystApps {
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            XCTAssertTrue(
                behavior.usesUTF16TextIndices,
                "\(bundleID) is WebKit/Catalyst and should use UTF-16 indices"
            )
        }
    }

    // MARK: - Timing Profile Consistency Tests

    func testChromiumAppsHaveLongerDebounce() {
        // Chromium apps need longer debounce due to async rendering
        let chromiumApps = [
            "com.tinyspeck.slackmacgap",
            "notion.id",
            "com.microsoft.teams2",
        ]

        for bundleID in chromiumApps {
            let timing = AppBehaviorRegistry.shared.timingProfile(for: bundleID)
            XCTAssertGreaterThanOrEqual(
                timing.analysisDebounce,
                0.8,
                "\(bundleID) is Chromium-based and should have debounce >= 0.8s"
            )
        }
    }

    func testNativeAppsHaveShorterDebounce() {
        // Native apps can have shorter debounce
        let nativeApps = [
            "com.apple.mail",
            "com.apple.Notes",
            "com.apple.TextEdit",
        ]

        for bundleID in nativeApps {
            let timing = AppBehaviorRegistry.shared.timingProfile(for: bundleID)
            XCTAssertLessThanOrEqual(
                timing.analysisDebounce,
                0.5,
                "\(bundleID) is native and should have debounce <= 0.5s"
            )
        }
    }

    // MARK: - Scroll Behavior Consistency Tests

    func testAppsWithUnreliableScrollEventsHaveQuirk() {
        for behavior in allBehaviors {
            if !behavior.scrollBehavior.hasReliableScrollEvents {
                XCTAssertTrue(
                    behavior.knownQuirks.contains(.unreliableScrollEvents),
                    "\(behavior.bundleIdentifier) has unreliable scroll events but missing quirk"
                )
            }
        }
    }

    func testAppsWithUnreliableScrollEventsDisableHideOnScroll() {
        for behavior in allBehaviors {
            if behavior.knownQuirks.contains(.unreliableScrollEvents) {
                XCTAssertFalse(
                    behavior.scrollBehavior.hideOnScrollStart,
                    "\(behavior.bundleIdentifier) has unreliable scroll events but hideOnScrollStart is true"
                )
            }
        }
    }

    // MARK: - Default Behavior Tests

    func testDefaultBehaviorHasConservativeSettings() {
        let defaultBehavior = AppBehaviorRegistry.shared.behavior(for: "com.totally.unknown.app.12345")

        // Default should be conservative
        XCTAssertFalse(defaultBehavior.usesUTF16TextIndices, "Default should use safe grapheme indices")
        XCTAssertTrue(defaultBehavior.knownQuirks.isEmpty, "Default should have no quirks")
        // Conservative: assume scroll events might be unreliable for unknown apps
        XCTAssertFalse(defaultBehavior.scrollBehavior.hasReliableScrollEvents, "Default should conservatively assume unreliable scroll")
    }

    // MARK: - Cross-App Isolation Tests

    func testChangingOneBehaviorDoesNotAffectOthers() {
        // Get two different behaviors
        let slackBehavior = AppBehaviorRegistry.shared.behavior(for: "com.tinyspeck.slackmacgap")
        let notionBehavior = AppBehaviorRegistry.shared.behavior(for: "notion.id")

        // They should be distinct instances with different values where expected
        XCTAssertNotEqual(slackBehavior.bundleIdentifier, notionBehavior.bundleIdentifier)
        XCTAssertNotEqual(slackBehavior.displayName, notionBehavior.displayName)

        // Slack has format-preserving replacement, Notion doesn't
        XCTAssertTrue(slackBehavior.knownQuirks.contains(.hasSlackFormatPreservingReplacement))
        XCTAssertFalse(notionBehavior.knownQuirks.contains(.hasSlackFormatPreservingReplacement))
    }
}
