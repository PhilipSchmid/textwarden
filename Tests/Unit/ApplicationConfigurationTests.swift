//
//  ApplicationConfigurationTests.swift
//  TextWarden
//
//  Unit tests for ApplicationConfiguration
//

@testable import TextWarden
import XCTest

final class ApplicationConfigurationTests: XCTestCase {
    // MARK: - Keyboard Operation Delay Tests

    func testKeyboardDelayForSlack() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(delay, 0.15, "Slack should have 150ms delay for React rendering")
    }

    func testKeyboardDelayForDiscord() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.hnc.Discord")
        XCTAssertEqual(delay, 0.15, "Discord should have 150ms delay for React rendering")
    }

    func testKeyboardDelayForVSCode() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.microsoft.VSCode")
        XCTAssertEqual(delay, 0.05, "Unregistered apps should use the safe default delay")
    }

    func testKeyboardDelayForChrome() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.google.Chrome")
        XCTAssertEqual(delay, 0.10, "Chrome should have 100ms delay")
    }

    func testKeyboardDelayForSafari() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.apple.Safari")
        XCTAssertEqual(delay, 0.10, "Registered browsers should use the browser category delay")
    }

    func testKeyboardDelayForFirefox() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "org.mozilla.firefox")
        XCTAssertEqual(delay, 0.12, "Firefox should have 120ms delay")
    }

    func testGeckoBrowsersUseSupportedBrowserPaths() {
        for bundleID in ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen"] {
            let configuration = AppRegistry.shared.configuration(for: bundleID)
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            let context = ApplicationContext(bundleIdentifier: bundleID, processID: 0, applicationName: "Browser")

            XCTAssertEqual(AppRegistry.shared.policy(for: bundleID), .supported)
            XCTAssertEqual(configuration.category, .browser)
            XCTAssertEqual(configuration.parserType, .browser)
            XCTAssertEqual(configuration.features.textReplacementMethod, .browserStyle)
            XCTAssertTrue(behavior.usesUTF16TextIndices)
            XCTAssertTrue(behavior.knownQuirks.contains(.webBasedRendering))
            XCTAssertTrue(context.isBrowser)
            XCTAssertFalse(context.isChromiumBased)
            XCTAssertEqual(context.keyboardOperationDelay, 0.12)
        }
        XCTAssertEqual(BrowserContentParser(bundleIdentifier: "app.zen-browser.zen").parserName, "Zen")
    }

    func testUnverifiedBrowsersRequireSafeTrialConsent() {
        for bundleID in [
            "com.microsoft.edgemac", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Canary",
            "com.operasoftware.Opera", "com.operasoftware.OperaGX",
            "company.thebrowser.Browser", "company.thebrowser.Browser.beta",
            "com.brave.Browser.beta",
            "com.vivaldi.Vivaldi", "org.chromium.Chromium",
        ] {
            XCTAssertFalse(AppRegistry.shared.hasConfiguration(for: bundleID))
            XCTAssertEqual(AppRegistry.shared.policy(for: bundleID), .safeTrial)
            XCTAssertTrue(AppRegistry.shared.requiresSafeTrialConsent(for: bundleID))
            XCTAssertNil(AppBehaviorRegistry.shared.registeredBehavior(for: bundleID))
        }
    }

    func testKeyboardDelayForNativeApp() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.apple.TextEdit")
        XCTAssertEqual(delay, 0.05, "Native apps should have 50ms delay")
    }

    // MARK: - Font Size Tests

    func testEstimatedFontSizeForSlack() {
        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(fontSize, 15.0)
    }

    func testEstimatedFontSizeForDiscord() {
        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.hnc.Discord")
        XCTAssertEqual(fontSize, 13.0, "Unregistered apps should use the default font size")
    }

    func testEstimatedFontSizeForVSCode() {
        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.microsoft.VSCode")
        XCTAssertEqual(fontSize, 13.0, "Unregistered apps should use the default font size")
    }

    func testEstimatedFontSizeForElectronApp() {
        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.electron.app")
        XCTAssertEqual(fontSize, 13.0, "Unregistered apps should use the default font size")
    }

    func testEstimatedFontSizeForNativeApp() {
        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.apple.TextEdit")
        XCTAssertEqual(fontSize, 12.0, "TextEdit should use its registered font size")
    }

    // MARK: - Character Width Correction Tests

    func testCharacterWidthCorrectionForSlack() {
        let correction = ApplicationConfiguration.characterWidthCorrection(for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(correction, 0.0, "Slack should have 0 correction (use raw measurement)")
    }

    func testCharacterWidthCorrectionForDiscord() {
        let correction = ApplicationConfiguration.characterWidthCorrection(for: "com.hnc.Discord")
        XCTAssertEqual(correction, 0.0, "Discord should have 0 correction")
    }

    func testCharacterWidthCorrectionForOtherApps() {
        let correction = ApplicationConfiguration.characterWidthCorrection(for: "com.apple.TextEdit")
        XCTAssertEqual(correction, 0.0, "Other apps should have 0 correction by default")
    }

    // MARK: - Left Padding Tests

    func testEstimatedLeftPaddingForSlack() {
        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(padding, 12.0)
    }

    func testEstimatedLeftPaddingForDiscord() {
        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.hnc.Discord")
        XCTAssertEqual(padding, 8.0, "Unregistered apps should use the default padding")
    }

    func testEstimatedLeftPaddingForVSCode() {
        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.microsoft.VSCode")
        XCTAssertEqual(padding, 8.0, "Unregistered apps should use the default padding")
    }

    func testEstimatedLeftPaddingForElectronApp() {
        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.electron.app")
        XCTAssertEqual(padding, 8.0, "Unregistered apps should use the default padding")
    }

    func testEstimatedLeftPaddingForNativeApp() {
        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.apple.TextEdit")
        XCTAssertEqual(padding, 0.0, "TextEdit should use its registered padding")
    }

    // MARK: - Format Preservation Tests

    func testSupportsFormatPreservationForNativeApp() {
        let supports = ApplicationConfiguration.supportsFormatPreservation(for: "com.apple.TextEdit")
        XCTAssertTrue(supports, "Native apps should support format preservation")
    }

    func testSupportsFormatPreservationForElectronApp() {
        let supports = ApplicationConfiguration.supportsFormatPreservation(for: "com.microsoft.VSCode")
        XCTAssertFalse(supports, "Electron apps should not support format preservation")
    }

    func testSupportsFormatPreservationForChromiumApp() {
        let supports = ApplicationConfiguration.supportsFormatPreservation(for: "com.google.Chrome")
        XCTAssertFalse(supports, "Chromium apps should not support format preservation")
    }

    // MARK: - Edge Cases

    func testUnknownBundleIdentifier() {
        // Should fall back to safe defaults
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.unknown.app")
        XCTAssertEqual(delay, 0.05, "Unknown apps should use native app defaults")

        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.unknown.app")
        XCTAssertEqual(fontSize, 13.0, "Unknown apps should use native app font size")

        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.unknown.app")
        XCTAssertEqual(padding, 8.0, "Unknown apps should use native app padding")
    }

    func testBrowserBundleIdentifiers() {
        // Test various browser identifiers
        let browsers = [
            "com.google.Chrome",
            "com.brave.Browser",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "app.zen-browser.zen",
            "ai.perplexity.comet",
        ]

        for bundleID in browsers {
            XCTAssertEqual(AppRegistry.shared.policy(for: bundleID), .supported)
            XCTAssertNotNil(AppBehaviorRegistry.shared.registeredBehavior(for: bundleID))
            let delay = ApplicationConfiguration.keyboardOperationDelay(for: bundleID)
            XCTAssertGreaterThanOrEqual(delay, 0.05, "\(bundleID) should have reasonable delay")
            XCTAssertLessThanOrEqual(delay, 0.15, "\(bundleID) delay should not be excessive")
        }
    }

    func testFormatPreservationMatchesRegistryConfiguration() {
        let expectedSupport = [
            "com.microsoft.VSCode": false,
            "com.tinyspeck.slackmacgap": true,
            "com.hnc.Discord": false,
            "com.electron.app": false,
        ]

        for (bundleID, expected) in expectedSupport {
            let supports = ApplicationConfiguration.supportsFormatPreservation(for: bundleID)
            XCTAssertEqual(supports, expected, "\(bundleID) should match its AppRegistry configuration")
        }
    }
}
