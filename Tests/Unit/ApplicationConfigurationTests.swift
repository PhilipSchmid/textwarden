//
//  ApplicationConfigurationTests.swift
//  TextWarden
//
//  Unit tests for ApplicationConfiguration
//

import XCTest
@testable import TextWarden

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
        XCTAssertEqual(delay, 0.08, "VS Code should have 80ms delay")
    }

    func testKeyboardDelayForChrome() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.google.Chrome")
        XCTAssertEqual(delay, 0.10, "Chrome should have 100ms delay")
    }

    func testKeyboardDelayForSafari() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "com.apple.Safari")
        XCTAssertEqual(delay, 0.08, "Safari should have 80ms delay")
    }

    func testKeyboardDelayForFirefox() {
        let delay = ApplicationConfiguration.keyboardOperationDelay(for: "org.mozilla.firefox")
        XCTAssertEqual(delay, 0.12, "Firefox should have 120ms delay")
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
        XCTAssertEqual(fontSize, 15.0)
    }

    func testEstimatedFontSizeForVSCode() {
        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.microsoft.VSCode")
        XCTAssertEqual(fontSize, 14.0)
    }

    func testEstimatedFontSizeForElectronApp() {
        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.electron.app")
        XCTAssertEqual(fontSize, 15.0, "Generic Electron apps should use 15pt")
    }

    func testEstimatedFontSizeForNativeApp() {
        let fontSize = ApplicationConfiguration.estimatedFontSize(for: "com.apple.TextEdit")
        XCTAssertEqual(fontSize, 13.0, "Native apps should use 13pt")
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
        XCTAssertEqual(padding, 12.0)
    }

    func testEstimatedLeftPaddingForVSCode() {
        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.microsoft.VSCode")
        XCTAssertEqual(padding, 10.0)
    }

    func testEstimatedLeftPaddingForElectronApp() {
        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.electron.app")
        XCTAssertEqual(padding, 12.0, "Generic Electron apps should have 12px padding")
    }

    func testEstimatedLeftPaddingForNativeApp() {
        let padding = ApplicationConfiguration.estimatedLeftPadding(for: "com.apple.TextEdit")
        XCTAssertEqual(padding, 8.0, "Native apps should have 8px padding")
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
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.operasoftware.Opera",
            "com.brave.Browser"
        ]

        for bundleId in browsers {
            let delay = ApplicationConfiguration.keyboardOperationDelay(for: bundleId)
            XCTAssertGreaterThanOrEqual(delay, 0.05, "\(bundleId) should have reasonable delay")
            XCTAssertLessThanOrEqual(delay, 0.15, "\(bundleId) delay should not be excessive")
        }
    }

    func testConfigurationConsistency() {
        // Ensure all Electron apps get consistent treatment
        let electronApps = [
            "com.microsoft.VSCode",
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "com.electron.app"
        ]

        for bundleId in electronApps {
            let supports = ApplicationConfiguration.supportsFormatPreservation(for: bundleId)
            XCTAssertFalse(supports, "\(bundleId) should not support format preservation (Electron app)")
        }
    }
}
