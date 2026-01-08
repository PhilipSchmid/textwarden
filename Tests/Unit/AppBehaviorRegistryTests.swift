//
//  AppBehaviorRegistryTests.swift
//  TextWarden
//
//  Unit tests for AppBehaviorRegistry and per-app behavior system.
//

@testable import TextWarden
import XCTest

final class AppBehaviorRegistryTests: XCTestCase {
    // MARK: - Registry Lookup Tests

    func testRegisteredAppReturnsSpecificBehavior() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(behavior.bundleIdentifier, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(behavior.displayName, "Slack")
    }

    func testUnknownAppReturnsDefaultBehavior() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.unknown.nonexistent.app")
        // DefaultBehavior should have the requested bundle ID
        XCTAssertEqual(behavior.bundleIdentifier, "com.unknown.nonexistent.app")
        // DefaultBehavior has conservative defaults
        XCTAssertFalse(behavior.usesUTF16TextIndices, "Default behavior should use grapheme indices")
    }

    func testRegisteredBehaviorReturnsNilForUnknownApp() {
        let behavior = AppBehaviorRegistry.shared.registeredBehavior(for: "com.unknown.app")
        XCTAssertNil(behavior, "registeredBehavior should return nil for unknown apps")
    }

    func testRegisteredBehaviorReturnsValueForKnownApp() {
        let behavior = AppBehaviorRegistry.shared.registeredBehavior(for: "com.tinyspeck.slackmacgap")
        XCTAssertNotNil(behavior, "registeredBehavior should return value for known apps")
    }

    func testHasRegisteredBehavior() {
        XCTAssertTrue(AppBehaviorRegistry.shared.hasRegisteredBehavior(for: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(AppBehaviorRegistry.shared.hasRegisteredBehavior(for: "com.unknown.app"))
    }

    // MARK: - Quirk Helper Tests

    func testHasQuirkForKnownApp() {
        XCTAssertTrue(
            AppBehaviorRegistry.shared.hasQuirk(.webBasedRendering, for: "com.tinyspeck.slackmacgap"),
            "Slack should have webBasedRendering quirk"
        )
    }

    func testHasQuirkReturnsFalseForMissingQuirk() {
        XCTAssertFalse(
            AppBehaviorRegistry.shared.hasQuirk(.usesMailReplaceRangeAPI, for: "com.tinyspeck.slackmacgap"),
            "Slack should not have usesMailReplaceRangeAPI quirk"
        )
    }

    func testHasQuirkForUnknownApp() {
        // Unknown apps get DefaultBehavior with empty quirks
        XCTAssertFalse(
            AppBehaviorRegistry.shared.hasQuirk(.webBasedRendering, for: "com.unknown.app"),
            "Unknown apps should have no quirks"
        )
    }

    // MARK: - Slack Behavior Tests

    func testSlackBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.tinyspeck.slackmacgap")

        XCTAssertTrue(behavior.knownQuirks.contains(.chromiumEmojiWidthBug))
        XCTAssertTrue(behavior.knownQuirks.contains(.webBasedRendering))
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresBrowserStyleReplacement))
        XCTAssertTrue(behavior.knownQuirks.contains(.hasSlackFormatPreservingReplacement))
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresCustomScrollHandling))
        XCTAssertTrue(behavior.knownQuirks.contains(.unreliableScrollEvents))
    }

    func testSlackUsesUTF16Indices() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.tinyspeck.slackmacgap")
        XCTAssertTrue(behavior.usesUTF16TextIndices, "Slack should use UTF-16 indices")
    }

    // MARK: - Notion Behavior Tests

    func testNotionBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "notion.id")

        XCTAssertTrue(behavior.knownQuirks.contains(.chromiumEmojiWidthBug))
        XCTAssertTrue(behavior.knownQuirks.contains(.webBasedRendering))
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresBrowserStyleReplacement))
    }

    func testNotionUsesUTF16Indices() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "notion.id")
        XCTAssertTrue(behavior.usesUTF16TextIndices, "Notion should use UTF-16 indices")
    }

    // MARK: - Apple Mail Behavior Tests

    func testMailBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.apple.mail")

        XCTAssertTrue(
            behavior.knownQuirks.contains(.usesMailReplaceRangeAPI),
            "Mail should use WebKit's AXReplaceRangeWithText API"
        )
    }

    func testMailUsesUTF16Indices() {
        // Mail uses WebKit for compose view, which uses UTF-16 indices
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.apple.mail")
        XCTAssertTrue(behavior.usesUTF16TextIndices, "Mail (WebKit) should use UTF-16 indices")
    }

    // MARK: - Microsoft Office Behavior Tests

    func testWordBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Word")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresBrowserStyleReplacement))
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresFocusPasteReplacement))
        XCTAssertFalse(behavior.knownQuirks.contains(.webBasedRendering), "Word is native, not web-based")
    }

    func testWordUsesGraphemeIndices() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Word")
        XCTAssertFalse(behavior.usesUTF16TextIndices, "Word should use grapheme indices")
    }

    func testPowerPointBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Powerpoint")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresBrowserStyleReplacement))
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresFocusPasteReplacement))
    }

    func testPowerPointUsesGraphemeIndices() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Powerpoint")
        XCTAssertFalse(behavior.usesUTF16TextIndices, "PowerPoint should use grapheme indices")
    }

    func testOutlookBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Outlook")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresBrowserStyleReplacement))
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresFocusPasteReplacement))
    }

    func testOutlookUsesGraphemeIndices() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Outlook")
        XCTAssertFalse(behavior.usesUTF16TextIndices, "Outlook should use grapheme indices")
    }

    // MARK: - Teams Behavior Tests

    func testTeamsBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.teams2")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresSelectionValidationBeforePaste))
        XCTAssertTrue(behavior.knownQuirks.contains(.webBasedRendering))
    }

    func testTeamsUsesUTF16Indices() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.teams2")
        XCTAssertTrue(behavior.usesUTF16TextIndices, "Teams should use UTF-16 indices")
    }

    // MARK: - Pages Behavior Tests

    func testPagesBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.apple.iWork.Pages")

        XCTAssertTrue(
            behavior.knownQuirks.contains(.requiresFocusPasteReplacement),
            "Pages should use focus+paste replacement"
        )
    }

    func testPagesUsesGraphemeIndices() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.apple.iWork.Pages")
        XCTAssertFalse(behavior.usesUTF16TextIndices, "Pages should use grapheme indices")
    }

    // MARK: - Perplexity Behavior Tests

    func testPerplexityBehaviorQuirks() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "ai.perplexity.mac")

        XCTAssertTrue(
            behavior.knownQuirks.contains(.requiresDirectTypingAtPosition0),
            "Perplexity should have position 0 typing quirk"
        )
    }

    // MARK: - Timing Profile Tests

    func testTimingProfileForSlack() {
        let timing = AppBehaviorRegistry.shared.timingProfile(for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(timing.analysisDebounce, 1.0, "Slack should have 1s debounce for Chromium")
    }

    func testTimingProfileForUnknownApp() {
        let timing = AppBehaviorRegistry.shared.timingProfile(for: "com.unknown.app")
        // DefaultBehavior should have reasonable defaults
        XCTAssertGreaterThan(timing.analysisDebounce, 0)
    }

    // MARK: - Scroll Behavior Tests

    func testScrollBehaviorForSlack() {
        let scroll = AppBehaviorRegistry.shared.scrollBehavior(for: "com.tinyspeck.slackmacgap")
        XCTAssertFalse(scroll.hideOnScrollStart, "Slack should not hide on scroll (unreliable events)")
        XCTAssertFalse(scroll.hasReliableScrollEvents)
    }

    func testScrollBehaviorForNotion() {
        let scroll = AppBehaviorRegistry.shared.scrollBehavior(for: "notion.id")
        XCTAssertTrue(scroll.hideOnScrollStart, "Notion should hide on scroll")
        XCTAssertTrue(scroll.hasReliableScrollEvents)
    }

    // MARK: - AppConfiguration Lookup Tests

    func testBehaviorForAppConfigurationReturnsRegisteredBehavior() {
        // Create an AppConfiguration with Slack's bundle ID
        let slackConfig = AppConfiguration(
            identifier: "slack",
            displayName: "Slack",
            bundleIDs: ["com.tinyspeck.slackmacgap"],
            category: .electron,
            parserType: .slack
        )

        let behavior = AppBehaviorRegistry.shared.behavior(for: slackConfig)

        // Should return the registered Slack behavior, not a default
        XCTAssertEqual(behavior.bundleIdentifier, "com.tinyspeck.slackmacgap")
        XCTAssertTrue(behavior.usesUTF16TextIndices, "Slack should use UTF-16 indices")
        XCTAssertTrue(behavior.knownQuirks.contains(.webBasedRendering))
    }

    func testBehaviorForAppConfigurationWithUnknownBundleID() {
        // Create an AppConfiguration with unknown bundle ID
        let unknownConfig = AppConfiguration(
            identifier: "unknown",
            displayName: "Unknown App",
            bundleIDs: ["com.unknown.app"],
            category: .native,
            parserType: .generic
        )

        let behavior = AppBehaviorRegistry.shared.behavior(for: unknownConfig)

        // Should return default behavior with conservative settings
        XCTAssertFalse(behavior.usesUTF16TextIndices, "Default should use grapheme indices")
        XCTAssertTrue(behavior.knownQuirks.isEmpty, "Default should have no quirks")
    }

    func testBehaviorForAppConfigurationUsesIdentifierNotBundleID() {
        // This test ensures that using appConfig.identifier (e.g., "slack")
        // instead of bundleIDs (e.g., "com.tinyspeck.slackmacgap") correctly
        // finds the registered behavior. This was a regression bug.
        let slackConfig = AppConfiguration(
            identifier: "slack", // This should NOT be used for lookup
            displayName: "Slack",
            bundleIDs: ["com.tinyspeck.slackmacgap"], // This SHOULD be used
            category: .electron,
            parserType: .slack
        )

        // The behavior(for: AppConfiguration) method should use bundleIDs, not identifier
        let behavior = AppBehaviorRegistry.shared.behavior(for: slackConfig)

        // Verify we got the registered Slack behavior (which uses UTF-16)
        // If it incorrectly used "slack" identifier, it would return default (grapheme)
        XCTAssertTrue(
            behavior.usesUTF16TextIndices,
            "Should use bundleIDs for lookup, not identifier. Got grapheme indices instead of UTF-16."
        )
    }

    func testBehaviorForAppConfigurationWithMultipleBundleIDs() {
        // Some apps might have multiple bundle IDs (old and new versions)
        let multiConfig = AppConfiguration(
            identifier: "multi-id-app",
            displayName: "Multi ID App",
            bundleIDs: ["com.unknown.first", "com.tinyspeck.slackmacgap", "com.unknown.third"],
            category: .electron,
            parserType: .generic
        )

        let behavior = AppBehaviorRegistry.shared.behavior(for: multiConfig)

        // Should find Slack's registered behavior via the second bundle ID
        XCTAssertTrue(
            behavior.usesUTF16TextIndices,
            "Should find registered behavior when any bundle ID matches"
        )
    }
}
