//
//  ApplicationTrackerTests.swift
//  TextWarden Tests
//
//  Integration tests for per-app filtering (T065)
//

import XCTest
@testable import TextWarden

final class ApplicationTrackerTests: XCTestCase {
    var tracker: ApplicationTracker!
    var preferences: UserPreferences!

    override func setUp() {
        super.setUp()
        tracker = ApplicationTracker.shared
        preferences = UserPreferences.shared
        preferences.resetToDefaults()
    }

    override func tearDown() {
        preferences.resetToDefaults()
        super.tearDown()
    }

    // MARK: - Application Filtering Tests

    func testActiveApplicationTracking() {
        // NOTE: This test requires an active application to be running
        // In real test environment, we would use mocking

        // Get current active application
        if let activeApp = tracker.activeApplication {
            XCTAssertFalse(activeApp.bundleIdentifier.isEmpty)
            XCTAssertFalse(activeApp.applicationName.isEmpty)
            XCTAssertGreaterThan(activeApp.processID, 0)
        }
    }

    func testDisabledApplicationNotMonitored() {
        let testBundleID = "com.apple.TextEdit"

        // Disable TextEdit
        preferences.disabledApplications.insert(testBundleID)

        // Verify it's disabled in preferences
        XCTAssertFalse(preferences.isEnabled(for: testBundleID))

        // Create mock application context
        let context = ApplicationContext(
            applicationName: "TextEdit",
            bundleIdentifier: testBundleID,
            processID: 12345
        )

        // Verify shouldCheck returns false
        XCTAssertFalse(context.shouldCheck())
    }

    func testEnabledApplicationIsMonitored() {
        let testBundleID = "com.apple.TextEdit"

        // Ensure TextEdit is enabled
        preferences.disabledApplications.remove(testBundleID)

        // Create mock application context
        let context = ApplicationContext(
            applicationName: "TextEdit",
            bundleIdentifier: testBundleID,
            processID: 12345
        )

        // Verify shouldCheck returns true
        XCTAssertTrue(context.shouldCheck())
    }

    func testToggleAppWhileRunning() {
        let testBundleID = "com.apple.TextEdit"

        // Initial state: enabled
        XCTAssertTrue(preferences.isEnabled(for: testBundleID))

        // Disable
        preferences.disabledApplications.insert(testBundleID)
        XCTAssertFalse(preferences.isEnabled(for: testBundleID))

        // Re-enable
        preferences.disabledApplications.remove(testBundleID)
        XCTAssertTrue(preferences.isEnabled(for: testBundleID))
    }

    func testApplicationContextEquality() {
        let context1 = ApplicationContext(
            applicationName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            processID: 12345
        )

        let context2 = ApplicationContext(
            applicationName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            processID: 67890  // Different PID
        )

        // Should be equal based on bundle ID
        XCTAssertEqual(context1, context2)
    }

    func testApplicationContextUniqueness() {
        let context1 = ApplicationContext(
            applicationName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            processID: 12345
        )

        let context2 = ApplicationContext(
            applicationName: "VSCode",
            bundleIdentifier: "com.microsoft.VSCode",
            processID: 12345  // Same PID
        )

        // Should NOT be equal (different bundle IDs)
        XCTAssertNotEqual(context1, context2)
    }

    // MARK: - Application Discovery Tests

    func testAutoDiscoverApplication() {
        // When an application is detected for the first time,
        // it should default to enabled
        let newBundleID = "com.test.NewApp"

        // Not in disabled list = enabled
        XCTAssertTrue(preferences.isEnabled(for: newBundleID))
    }

    // MARK: - Global Disable Tests

    func testGlobalDisableAffectsAllApps() {
        preferences.isEnabled = false

        // All apps should be disabled
        XCTAssertFalse(preferences.isEnabled(for: "com.apple.TextEdit"))
        XCTAssertFalse(preferences.isEnabled(for: "com.microsoft.VSCode"))
        XCTAssertFalse(preferences.isEnabled(for: "com.any.App"))
    }

    func testGlobalEnableRespectsPerAppSettings() {
        let disabledApp = "com.apple.TextEdit"
        let enabledApp = "com.microsoft.VSCode"

        // Global enabled, TextEdit disabled
        preferences.isEnabled = true
        preferences.disabledApplications.insert(disabledApp)

        XCTAssertFalse(preferences.isEnabled(for: disabledApp))
        XCTAssertTrue(preferences.isEnabled(for: enabledApp))
    }
}
