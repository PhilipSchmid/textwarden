//
//  UserPreferencesTests.swift
//  Gnau Tests
//
//  Unit tests for per-app settings (T064)
//

import XCTest
@testable import Gnau

final class UserPreferencesTests: XCTestCase {
    var preferences: UserPreferences!

    override func setUp() {
        super.setUp()
        // Create a fresh instance for each test
        preferences = UserPreferences.shared
        preferences.resetToDefaults()
    }

    override func tearDown() {
        preferences.resetToDefaults()
        super.tearDown()
    }

    // MARK: - Per-App Settings Tests

    func testEnableDisableApp() {
        let bundleID = "com.apple.TextEdit"

        // Initially enabled (default)
        XCTAssertTrue(preferences.isEnabled(for: bundleID))

        // Disable app
        preferences.disabledApplications.insert(bundleID)
        XCTAssertFalse(preferences.isEnabled(for: bundleID))

        // Re-enable app
        preferences.disabledApplications.remove(bundleID)
        XCTAssertTrue(preferences.isEnabled(for: bundleID))
    }

    func testMultipleAppsIndependent() {
        let textEdit = "com.apple.TextEdit"
        let vscode = "com.microsoft.VSCode"

        // Disable TextEdit
        preferences.disabledApplications.insert(textEdit)

        // TextEdit disabled, VSCode enabled
        XCTAssertFalse(preferences.isEnabled(for: textEdit))
        XCTAssertTrue(preferences.isEnabled(for: vscode))

        // Disable VSCode
        preferences.disabledApplications.insert(vscode)

        // Both disabled
        XCTAssertFalse(preferences.isEnabled(for: textEdit))
        XCTAssertFalse(preferences.isEnabled(for: vscode))
    }

    func testGlobalDisableOverridesPerApp() {
        let bundleID = "com.apple.TextEdit"

        // App is enabled by default
        XCTAssertTrue(preferences.isEnabled(for: bundleID))

        // Disable globally
        preferences.isEnabled = false

        // App should be disabled even though not in disabledApplications
        XCTAssertFalse(preferences.isEnabled(for: bundleID))

        // Re-enable globally
        preferences.isEnabled = true
        XCTAssertTrue(preferences.isEnabled(for: bundleID))
    }

    func testPerAppSettingsPersistence() {
        let bundleID = "com.apple.Pages"

        // Disable app
        preferences.disabledApplications.insert(bundleID)

        // Verify it's in the set
        XCTAssertTrue(preferences.disabledApplications.contains(bundleID))
        XCTAssertFalse(preferences.isEnabled(for: bundleID))
    }

    // MARK: - Custom Dictionary Tests

    func testCustomDictionaryLimit() {
        // Add 1000 words (limit)
        for i in 0..<1000 {
            preferences.addToCustomDictionary("word\(i)")
        }

        XCTAssertEqual(preferences.customDictionary.count, 1000)

        // Try to add 1001st word - should fail silently
        preferences.addToCustomDictionary("word1000")
        XCTAssertEqual(preferences.customDictionary.count, 1000)
        XCTAssertFalse(preferences.customDictionary.contains("word1000"))
    }

    func testCustomDictionaryCaseInsensitive() {
        preferences.addToCustomDictionary("SwiftUI")

        // Should be stored as lowercase
        XCTAssertTrue(preferences.customDictionary.contains("swiftui"))
        XCTAssertFalse(preferences.customDictionary.contains("SwiftUI"))
    }

    // MARK: - Ignored Rules Tests

    func testIgnoreRulePermanently() {
        let ruleID = "passive-voice"

        // Initially not ignored
        XCTAssertFalse(preferences.ignoredRules.contains(ruleID))

        // Ignore rule
        preferences.ignoreRule(ruleID)
        XCTAssertTrue(preferences.ignoredRules.contains(ruleID))

        // Re-enable rule
        preferences.enableRule(ruleID)
        XCTAssertFalse(preferences.ignoredRules.contains(ruleID))
    }

    // MARK: - Severity Filtering Tests

    func testSeverityFiltering() {
        // All severities enabled by default
        XCTAssertEqual(preferences.enabledSeverities, [0, 1, 2])

        // Disable warnings (1)
        preferences.enabledSeverities.remove(1)
        XCTAssertEqual(preferences.enabledSeverities, [0, 2])

        // Re-enable warnings
        preferences.enabledSeverities.insert(1)
        XCTAssertEqual(preferences.enabledSeverities, [0, 1, 2])
    }

    // MARK: - Reset Tests

    func testResetToDefaults() {
        // Modify preferences
        preferences.isEnabled = false
        preferences.disabledApplications.insert("com.test.App")
        preferences.addToCustomDictionary("testword")
        preferences.ignoreRule("test-rule")
        preferences.enabledSeverities = [0]

        // Reset
        preferences.resetToDefaults()

        // Verify defaults restored
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertTrue(preferences.disabledApplications.isEmpty)
        XCTAssertTrue(preferences.customDictionary.isEmpty)
        XCTAssertTrue(preferences.ignoredRules.isEmpty)
        XCTAssertEqual(preferences.enabledSeverities, [0, 1, 2])
    }
}
