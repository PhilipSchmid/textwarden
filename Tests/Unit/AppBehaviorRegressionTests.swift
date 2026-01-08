//
//  AppBehaviorRegressionTests.swift
//  TextWarden
//
//  Regression prevention tests for the AppBehavior system.
//
//  These tests are designed to catch common mistakes when:
//  - Adding new application behaviors
//  - Modifying existing behavior configurations
//  - Refactoring the behavior system
//
//  If a test fails, it's likely that a change broke something important.
//  Don't just update the test - understand WHY it failed first.
//

@testable import TextWarden
import XCTest

final class AppBehaviorRegressionTests: XCTestCase {
    // MARK: - All Behaviors Collection

    private var allBehaviors: [AppBehavior] {
        AppBehaviorRegistry.shared.registeredBundleIDs.compactMap {
            AppBehaviorRegistry.shared.registeredBehavior(for: $0)
        }
    }

    // MARK: - Quirk Dependency Tests

    /// If an app has chromiumEmojiWidthBug, it should also have webBasedRendering
    /// (Chromium apps are web-based by definition)
    func testChromiumEmojiQuirkImpliesWebBasedRendering() {
        for behavior in allBehaviors {
            if behavior.knownQuirks.contains(.chromiumEmojiWidthBug) {
                XCTAssertTrue(
                    behavior.knownQuirks.contains(.webBasedRendering),
                    "\(behavior.bundleIdentifier) has chromiumEmojiWidthBug but missing webBasedRendering"
                )
            }
        }
    }

    /// If an app has Slack format-preserving replacement, it must have browser-style replacement
    func testSlackFormatPreservingImpliesBrowserStyle() {
        for behavior in allBehaviors {
            if behavior.knownQuirks.contains(.hasSlackFormatPreservingReplacement) {
                XCTAssertTrue(
                    behavior.knownQuirks.contains(.requiresBrowserStyleReplacement),
                    "\(behavior.bundleIdentifier) has Slack format-preserving but missing browserStyleReplacement"
                )
            }
        }
    }

    /// If an app has focus-paste replacement, it should also have browser-style
    /// (focus-paste is a specialized form of browser-style)
    func testFocusPasteImpliesBrowserStyle() {
        for behavior in allBehaviors {
            if behavior.knownQuirks.contains(.requiresFocusPasteReplacement) {
                XCTAssertTrue(
                    behavior.knownQuirks.contains(.requiresBrowserStyleReplacement),
                    "\(behavior.bundleIdentifier) has focusPasteReplacement but missing browserStyleReplacement"
                )
            }
        }
    }

    /// If an app requires full reanalysis after replacement, it should have browser-style
    func testFullReanalysisImpliesBrowserStyle() {
        for behavior in allBehaviors {
            if behavior.knownQuirks.contains(.requiresFullReanalysisAfterReplacement) {
                XCTAssertTrue(
                    behavior.knownQuirks.contains(.requiresBrowserStyleReplacement),
                    "\(behavior.bundleIdentifier) requires reanalysis but missing browserStyleReplacement"
                )
            }
        }
    }

    // MARK: - Quirk Mutual Exclusivity Tests

    /// Mail API and Slack format-preserving are mutually exclusive
    func testMailAPIAndSlackFormatExclusive() {
        for behavior in allBehaviors {
            let hasMailAPI = behavior.knownQuirks.contains(.usesMailReplaceRangeAPI)
            let hasSlackFormat = behavior.knownQuirks.contains(.hasSlackFormatPreservingReplacement)

            XCTAssertFalse(
                hasMailAPI && hasSlackFormat,
                "\(behavior.bundleIdentifier) has both Mail API and Slack format quirks (mutually exclusive)"
            )
        }
    }

    /// Focus-paste and Mail API are mutually exclusive
    func testFocusPasteAndMailAPIExclusive() {
        for behavior in allBehaviors {
            let hasFocusPaste = behavior.knownQuirks.contains(.requiresFocusPasteReplacement)
            let hasMailAPI = behavior.knownQuirks.contains(.usesMailReplaceRangeAPI)

            XCTAssertFalse(
                hasFocusPaste && hasMailAPI,
                "\(behavior.bundleIdentifier) has both focusPaste and Mail API quirks (mutually exclusive)"
            )
        }
    }

    // MARK: - UTF-16 Consistency Tests

    /// Apps with webBasedRendering should use UTF-16 indices
    func testWebBasedAppsUseUTF16() {
        for behavior in allBehaviors {
            if behavior.knownQuirks.contains(.webBasedRendering) {
                XCTAssertTrue(
                    behavior.usesUTF16TextIndices,
                    "\(behavior.bundleIdentifier) has webBasedRendering but usesUTF16TextIndices=false"
                )
            }
        }
    }

    /// Apps with chromiumEmojiWidthBug should use UTF-16 indices
    func testChromiumAppsUseUTF16() {
        for behavior in allBehaviors {
            if behavior.knownQuirks.contains(.chromiumEmojiWidthBug) {
                XCTAssertTrue(
                    behavior.usesUTF16TextIndices,
                    "\(behavior.bundleIdentifier) has chromiumEmojiWidthBug but usesUTF16TextIndices=false"
                )
            }
        }
    }

    /// Apps WITHOUT webBasedRendering should use grapheme indices UNLESS they have a valid reason
    /// Valid reasons: Mac Catalyst, WebKit compose view, or documented UTF-16 AX API usage
    func testNativeAppsWithoutWebKitUseGrapheme() {
        // Apps that are known to be native but use WebKit internally
        let webKitNativeApps: Set<String> = [
            "com.apple.mail", // Uses WebKit for compose
        ]

        // Mac Catalyst apps (use UTF-16 but aren't "web-based" in the Electron sense)
        let catalystApps: Set<String> = [
            "com.apple.MobileSMS", // Messages
            "net.whatsapp.WhatsApp", // WhatsApp
        ]

        // Native apps that use UTF-16 for AX APIs (documented in behavior file)
        let nativeWithUTF16AX: Set<String> = [
            "ru.keepcoder.Telegram", // Uses UTF-16 for AXNumberOfCharacters
        ]

        for behavior in allBehaviors {
            // Skip web-based apps
            if behavior.knownQuirks.contains(.webBasedRendering) { continue }
            // Skip known WebKit native apps
            if webKitNativeApps.contains(behavior.bundleIdentifier) { continue }
            // Skip Catalyst apps
            if catalystApps.contains(behavior.bundleIdentifier) { continue }
            // Skip native apps with documented UTF-16 AX usage
            if nativeWithUTF16AX.contains(behavior.bundleIdentifier) { continue }

            XCTAssertFalse(
                behavior.usesUTF16TextIndices,
                "\(behavior.bundleIdentifier) is not web-based but usesUTF16TextIndices=true. " +
                    "If this is correct, add to exception list with documentation."
            )
        }
    }

    // MARK: - Timing Profile Validation Tests

    /// All timing values must be positive
    func testAllTimingValuesArePositive() {
        for behavior in allBehaviors {
            let timing = behavior.timingProfile

            XCTAssertGreaterThan(
                timing.analysisDebounce, 0,
                "\(behavior.bundleIdentifier) has non-positive analysisDebounce"
            )
            XCTAssertGreaterThan(
                timing.boundsStabilizationDelay, 0,
                "\(behavior.bundleIdentifier) has non-positive boundsStabilizationDelay"
            )
            XCTAssertGreaterThan(
                timing.windowChangeGracePeriod, 0,
                "\(behavior.bundleIdentifier) has non-positive windowChangeGracePeriod"
            )
            XCTAssertGreaterThan(
                timing.boundsValidationInterval, 0,
                "\(behavior.bundleIdentifier) has non-positive boundsValidationInterval"
            )
        }
    }

    /// Debounce should be within reasonable range (0.1s to 3s)
    func testDebounceInReasonableRange() {
        for behavior in allBehaviors {
            let debounce = behavior.timingProfile.analysisDebounce

            XCTAssertGreaterThanOrEqual(
                debounce, 0.1,
                "\(behavior.bundleIdentifier) has debounce < 0.1s (too fast, will cause flickering)"
            )
            XCTAssertLessThanOrEqual(
                debounce, 3.0,
                "\(behavior.bundleIdentifier) has debounce > 3s (too slow, bad UX)"
            )
        }
    }

    /// Chromium/Electron apps need at least 0.8s debounce due to async rendering
    func testChromiumAppsHaveAdequateDebounce() {
        for behavior in allBehaviors {
            if behavior.knownQuirks.contains(.chromiumEmojiWidthBug) ||
                behavior.knownQuirks.contains(.webBasedRendering)
            {
                XCTAssertGreaterThanOrEqual(
                    behavior.timingProfile.analysisDebounce, 0.5,
                    "\(behavior.bundleIdentifier) is web-based but debounce < 0.5s (needs longer for async rendering)"
                )
            }
        }
    }

    // MARK: - Scroll Behavior Consistency Tests

    /// If hideOnScrollStart is false, should have fallback or unreliable quirk
    func testScrollHideDisabledHasReason() {
        for behavior in allBehaviors {
            if !behavior.scrollBehavior.hideOnScrollStart {
                let hasUnreliableQuirk = behavior.knownQuirks.contains(.unreliableScrollEvents)
                let hasFallback = behavior.scrollBehavior.fallbackDetection != .none
                let hasCustomHandling = behavior.knownQuirks.contains(.requiresCustomScrollHandling)

                XCTAssertTrue(
                    hasUnreliableQuirk || hasFallback || hasCustomHandling,
                    "\(behavior.bundleIdentifier) has hideOnScrollStart=false but no unreliableScrollEvents quirk, fallback, or custom handling"
                )
            }
        }
    }

    /// If hasReliableScrollEvents is false, should have unreliableScrollEvents quirk
    func testUnreliableScrollEventsQuirkConsistency() {
        for behavior in allBehaviors {
            if !behavior.scrollBehavior.hasReliableScrollEvents {
                // Either has the quirk OR is using DefaultBehavior (conservative)
                let hasQuirk = behavior.knownQuirks.contains(.unreliableScrollEvents)
                let isDefault = behavior.knownQuirks.isEmpty // DefaultBehavior has no quirks

                XCTAssertTrue(
                    hasQuirk || isDefault,
                    "\(behavior.bundleIdentifier) has unreliable scroll events but missing quirk"
                )
            }
        }
    }

    // MARK: - Bundle ID Format Validation Tests

    /// Bundle IDs should follow reverse-domain format
    func testBundleIDsAreValidFormat() {
        for behavior in allBehaviors {
            let bundleID = behavior.bundleIdentifier

            // No whitespace
            XCTAssertFalse(
                bundleID.contains(" "),
                "\(bundleID) contains whitespace"
            )

            // Not empty
            XCTAssertFalse(
                bundleID.isEmpty,
                "Found behavior with empty bundle ID"
            )

            // Should contain at least one dot (reverse-domain format)
            XCTAssertTrue(
                bundleID.contains("."),
                "\(bundleID) doesn't follow reverse-domain format (no dots)"
            )

            // Should not start or end with dot
            XCTAssertFalse(
                bundleID.hasPrefix(".") || bundleID.hasSuffix("."),
                "\(bundleID) starts or ends with dot"
            )
        }
    }

    // MARK: - Behavior Value Range Tests

    /// Show delay should be reasonable (0 to 1 second)
    func testShowDelayInRange() {
        for behavior in allBehaviors {
            let delay = behavior.underlineVisibility.showDelay

            XCTAssertGreaterThanOrEqual(
                delay, 0,
                "\(behavior.bundleIdentifier) has negative showDelay"
            )
            XCTAssertLessThanOrEqual(
                delay, 1.0,
                "\(behavior.bundleIdentifier) has showDelay > 1s (bad UX)"
            )
        }
    }

    /// Hover delay should be reasonable (0.1 to 1 second)
    func testHoverDelayInRange() {
        for behavior in allBehaviors {
            let delay = behavior.popoverBehavior.hoverDelay

            XCTAssertGreaterThanOrEqual(
                delay, 0.1,
                "\(behavior.bundleIdentifier) has hoverDelay < 0.1s (too sensitive)"
            )
            XCTAssertLessThanOrEqual(
                delay, 1.0,
                "\(behavior.bundleIdentifier) has hoverDelay > 1s (bad UX)"
            )
        }
    }

    /// Auto-hide timeout should be non-negative
    func testAutoHideTimeoutNonNegative() {
        for behavior in allBehaviors {
            XCTAssertGreaterThanOrEqual(
                behavior.popoverBehavior.autoHideTimeout, 0,
                "\(behavior.bundleIdentifier) has negative autoHideTimeout"
            )
        }
    }

    /// Mouse movement threshold should be positive
    func testMouseThresholdPositive() {
        for behavior in allBehaviors {
            XCTAssertGreaterThan(
                behavior.mouseBehavior.movementThreshold, 0,
                "\(behavior.bundleIdentifier) has non-positive movementThreshold"
            )
        }
    }

    // MARK: - Critical App Configuration Snapshot Tests

    /// Slack MUST have these exact quirks - changing them will break text replacement
    func testSlackCriticalConfiguration() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.tinyspeck.slackmacgap")

        // Required quirks
        XCTAssertTrue(behavior.knownQuirks.contains(.hasSlackFormatPreservingReplacement),
                      "Slack MUST have format-preserving replacement")
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresBrowserStyleReplacement),
                      "Slack MUST have browser-style replacement")
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresCustomScrollHandling),
                      "Slack MUST have custom scroll handling")
        XCTAssertTrue(behavior.knownQuirks.contains(.unreliableScrollEvents),
                      "Slack MUST have unreliable scroll events quirk")

        // Must use UTF-16
        XCTAssertTrue(behavior.usesUTF16TextIndices,
                      "Slack MUST use UTF-16 indices")

        // Scroll hide must be disabled
        XCTAssertFalse(behavior.scrollBehavior.hideOnScrollStart,
                       "Slack MUST NOT hide on scroll start")
    }

    /// Microsoft Word MUST have these exact quirks
    func testWordCriticalConfiguration() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Word")

        // Required quirks
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresFocusPasteReplacement),
                      "Word MUST have focus-paste replacement")
        XCTAssertTrue(behavior.knownQuirks.contains(.requiresBrowserStyleReplacement),
                      "Word MUST have browser-style replacement")

        // Must NOT use UTF-16 (native app with grapheme indices)
        XCTAssertFalse(behavior.usesUTF16TextIndices,
                       "Word MUST NOT use UTF-16 indices (uses grapheme)")

        // Must NOT have web-based rendering
        XCTAssertFalse(behavior.knownQuirks.contains(.webBasedRendering),
                       "Word MUST NOT have webBasedRendering (it's native)")
    }

    /// Microsoft PowerPoint MUST have these exact quirks
    func testPowerPointCriticalConfiguration() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Powerpoint")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresFocusPasteReplacement),
                      "PowerPoint MUST have focus-paste replacement")
        XCTAssertFalse(behavior.usesUTF16TextIndices,
                       "PowerPoint MUST NOT use UTF-16 indices")
    }

    /// Microsoft Outlook MUST have these exact quirks
    func testOutlookCriticalConfiguration() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.Outlook")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresFocusPasteReplacement),
                      "Outlook MUST have focus-paste replacement")
        XCTAssertFalse(behavior.usesUTF16TextIndices,
                       "Outlook MUST NOT use UTF-16 indices")
    }

    /// Teams MUST have selection validation
    func testTeamsCriticalConfiguration() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.microsoft.teams2")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresSelectionValidationBeforePaste),
                      "Teams MUST have selection validation")
        XCTAssertTrue(behavior.usesUTF16TextIndices,
                      "Teams MUST use UTF-16 indices")
    }

    /// Apple Mail MUST use Mail Replace API
    func testMailCriticalConfiguration() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.apple.mail")

        XCTAssertTrue(behavior.knownQuirks.contains(.usesMailReplaceRangeAPI),
                      "Mail MUST use Mail Replace Range API")
    }

    /// Pages MUST have focus-paste replacement
    func testPagesCriticalConfiguration() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "com.apple.iWork.Pages")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresFocusPasteReplacement),
                      "Pages MUST have focus-paste replacement")
        XCTAssertFalse(behavior.usesUTF16TextIndices,
                       "Pages MUST NOT use UTF-16 indices")
    }

    /// Perplexity MUST have position 0 typing quirk
    func testPerplexityCriticalConfiguration() {
        let behavior = AppBehaviorRegistry.shared.behavior(for: "ai.perplexity.mac")

        XCTAssertTrue(behavior.knownQuirks.contains(.requiresDirectTypingAtPosition0),
                      "Perplexity MUST have position 0 typing quirk")
    }

    // MARK: - Popover Configuration Tests

    /// If detectNativePopovers is true, nativePopoverDetection should be configured
    func testNativePopoverDetectionConfigured() {
        for behavior in allBehaviors {
            if behavior.popoverBehavior.detectNativePopovers {
                // Should have valid detection config
                let detection = behavior.popoverBehavior.nativePopoverDetection
                XCTAssertNotNil(
                    detection,
                    "\(behavior.bundleIdentifier) has detectNativePopovers=true but nil nativePopoverDetection"
                )

                // At least one pattern should be set
                if let det = detection {
                    let hasPattern = det.windowTitlePattern != nil || det.windowRolePattern != nil
                    XCTAssertTrue(
                        hasPattern,
                        "\(behavior.bundleIdentifier) has nativePopoverDetection but no patterns"
                    )
                }
            }
        }
    }

    // MARK: - Display Names Tests

    /// Display names should be unique EXCEPT for variants of the same app
    /// (e.g., Chrome and Chrome Canary can both be "Google Chrome")
    func testDisplayNamesAreUniqueExceptVariants() {
        // Known variant pairs that share display names
        let knownVariantPairs: Set<Set<String>> = [
            ["com.google.Chrome", "com.google.Chrome.canary"],
            ["com.apple.Safari", "com.apple.SafariTechnologyPreview"],
            ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"],
            ["com.microsoft.edgemac", "com.microsoft.edgemac.Dev"],
            ["com.operasoftware.Opera", "com.operasoftware.OperaGX"],
            ["com.brave.Browser", "com.brave.Browser.beta"],
        ]

        var displayNames: [String: [String]] = [:] // displayName -> [bundleIDs]

        for behavior in allBehaviors {
            displayNames[behavior.displayName, default: []].append(behavior.bundleIdentifier)
        }

        for (displayName, bundleIDs) in displayNames {
            if bundleIDs.count > 1 {
                // Check if all bundle IDs sharing this name are known variants
                let bundleIDSet = Set(bundleIDs)
                let isKnownVariantGroup = knownVariantPairs.contains { variantPair in
                    bundleIDSet.isSubset(of: variantPair)
                }

                XCTAssertTrue(
                    isKnownVariantGroup,
                    "Unexpected duplicate display name '\(displayName)' used by: \(bundleIDs.joined(separator: ", ")). " +
                        "If these are variants, add to knownVariantPairs."
                )
            }
        }
    }

    /// All display names should be non-empty and reasonable length
    func testDisplayNamesAreReasonable() {
        for behavior in allBehaviors {
            XCTAssertFalse(
                behavior.displayName.isEmpty,
                "\(behavior.bundleIdentifier) has empty display name"
            )
            XCTAssertLessThanOrEqual(
                behavior.displayName.count, 50,
                "\(behavior.bundleIdentifier) has overly long display name"
            )
        }
    }

    // MARK: - Registry Completeness Tests

    /// Ensure minimum number of apps are registered (catch mass deletion bugs)
    func testMinimumAppsRegistered() {
        let count = AppBehaviorRegistry.shared.registeredCount

        // We should have at least 20 apps registered
        XCTAssertGreaterThanOrEqual(
            count, 20,
            "Expected at least 20 registered apps, got \(count). Did someone accidentally delete behaviors?"
        )
    }

    /// Critical apps must always be registered
    func testCriticalAppsAlwaysRegistered() {
        let criticalApps = [
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
            "com.apple.Notes",
            "com.apple.TextEdit",
            "com.apple.MobileSMS",
        ]

        for bundleID in criticalApps {
            XCTAssertTrue(
                AppBehaviorRegistry.shared.hasRegisteredBehavior(for: bundleID),
                "Critical app \(bundleID) is not registered!"
            )
        }
    }
}
