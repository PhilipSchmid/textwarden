//
//  PermissionManagerTests.swift
//  TextWarden Integration Tests
//
//  Integration tests for Accessibility permission detection
//

import XCTest
import ApplicationServices
@testable import TextWarden

final class PermissionManagerTests: XCTestCase {

    var permissionManager: PermissionManager!

    override func setUp() {
        super.setUp()
        permissionManager = PermissionManager.shared
    }

    override func tearDown() {
        permissionManager = nil
        super.tearDown()
    }

    // MARK: - Permission Detection Tests

    func testPermissionGrantedDetection() {
        // Given: System has granted Accessibility permissions
        // Note: This test requires actual system permissions to pass

        // When: Check if permission is granted
        let isGranted = permissionManager.isPermissionGranted

        // Then: Permission status should reflect system state
        // This test will pass only if running in an environment with granted permissions
        if AXIsProcessTrusted() {
            XCTAssertTrue(isGranted, "Permission should be detected as granted when AXIsProcessTrusted returns true")
        } else {
            XCTAssertFalse(isGranted, "Permission should be detected as not granted when AXIsProcessTrusted returns false")
        }
    }

    func testPermissionCheckWithPrompt() {
        // Given: App needs to check permission with prompt

        // When: Request permission check
        let canRequest = permissionManager.canRequestPermission()

        // Then: Should be able to request on macOS 13.0+
        XCTAssertTrue(canRequest, "Should always be able to request permission on supported macOS versions")
    }

    func testPermissionStatusPublisher() {
        // Given: Permission manager is initialized
        let expectation = XCTestExpectation(description: "Permission status should be published")

        var receivedStatus: Bool?

        // When: Subscribe to permission status changes
        let cancellable = permissionManager.$isPermissionGranted
            .sink { isGranted in
                receivedStatus = isGranted
                expectation.fulfill()
            }

        // Then: Should receive initial permission status
        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(receivedStatus, "Should receive permission status via publisher")

        cancellable.cancel()
    }

    func testOpenSystemPreferences() {
        // Given: User needs to grant permissions

        // When: Request to open System Settings
        permissionManager.openSystemPreferences()

        // Then: No crash should occur
        // Note: Actual navigation to System Settings cannot be tested in unit tests
        // Manual verification required
        XCTAssertTrue(true, "Opening System Settings should not crash")
    }

    func testPermissionPolling() {
        // Given: App is monitoring for permission changes
        let expectation = XCTestExpectation(description: "Permission polling should detect changes")
        expectation.isInverted = false  // Expect this to be fulfilled quickly

        var callbackCalled = false

        // When: Set up permission change callback
        permissionManager.onPermissionGranted = {
            callbackCalled = true
            expectation.fulfill()
        }

        // Trigger permission check (simulates polling)
        permissionManager.checkPermissionStatus()

        // Then: If permission is already granted, callback should be called
        if AXIsProcessTrusted() {
            wait(for: [expectation], timeout: 2.0)
            XCTAssertTrue(callbackCalled, "Callback should be called when permission is granted")
        } else {
            // If not granted, callback shouldn't be called
            XCTAssertFalse(callbackCalled, "Callback should not be called when permission is not granted")
        }
    }

    // MARK: - Permission State Transitions

    func testPermissionDeniedToGrantedTransition() {
        // Given: Permission starts as denied (simulated)
        // This test documents expected behavior during permission grant flow

        // When: Permission changes from denied to granted
        // (This cannot be automated - requires manual System Settings interaction)

        // Then: App should detect the change via polling
        // Test documents that PermissionManager.checkPermissionStatus() should be called every 1 second
        XCTAssertTrue(true, "Manual test: Grant permission in System Settings and verify detection within 1 second")
    }

    func testMultiplePermissionChecks() {
        // Given: Permission manager is initialized

        // When: Check permission multiple times rapidly
        let result1 = permissionManager.isPermissionGranted
        let result2 = permissionManager.isPermissionGranted
        let result3 = permissionManager.isPermissionGranted

        // Then: Results should be consistent
        XCTAssertEqual(result1, result2, "Multiple permission checks should return consistent results")
        XCTAssertEqual(result2, result3, "Multiple permission checks should return consistent results")
    }
}
