import AppKit
@testable import TextWarden
import XCTest

final class StartupSetupTests: XCTestCase {
    func testFirstInstallAlwaysUsesFullOnboarding() {
        for hasPermission in [false, true] {
            XCTAssertEqual(StartupSetup.required(hasCompletedOnboarding: false, hasPermission: hasPermission), .onboarding)
        }
    }

    func testExistingUsersOnlyRecoverMissingAccess() {
        XCTAssertEqual(StartupSetup.required(hasCompletedOnboarding: true, hasPermission: false), .restoreAccessibility)
        XCTAssertNil(StartupSetup.required(hasCompletedOnboarding: true, hasPermission: true))
    }

    @MainActor
    func testGrantClosesRecoveryButKeepsFirstRunOpen() {
        let delegate = AppDelegate()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        delegate.onboardingWindow = window
        defer { window.close() }

        window.orderFront(nil)
        delegate.handlePermissionGranted(for: .onboarding)
        XCTAssertTrue(window.isVisible, "First-time users must still finish their setup")
        XCTAssertNotNil(delegate.analysisCoordinator)

        delegate.handlePermissionGranted(for: .restoreAccessibility)
        XCTAssertFalse(window.isVisible, "Existing users should return directly to the app")
        XCTAssertNotNil(delegate.analysisCoordinator)
    }

    @MainActor
    func testWindowCloseClearsSetupAndReturnsToMenuBar() async throws {
        let preferences = UserPreferences.shared
        let completed = preferences.hasCompletedOnboarding
        let activationPolicy = NSApp.activationPolicy()
        let delegate = AppDelegate()
        defer {
            preferences.hasCompletedOnboarding = completed
            NSApp.setActivationPolicy(activationPolicy)
            delegate.onboardingWindow?.close()
        }

        preferences.hasCompletedOnboarding = false
        delegate.openOnboardingWindow()
        let window = try XCTUnwrap(delegate.onboardingWindow)
        XCTAssertTrue(window.isVisible)
        window.close()
        try await Task.sleep(for: .seconds(TimingConstants.windowCleanupDelay + 0.1))

        XCTAssertNil(delegate.onboardingWindow)
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertFalse(preferences.hasCompletedOnboarding, "Dismissing setup must not mark it complete")
    }
}
