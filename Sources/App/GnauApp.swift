//
//  GnauApp.swift
//  Gnau
//
//  Created by phisch on 09.11.2025.
//
//  Main entry point for Gnau menu bar application.
//

import SwiftUI

@main
struct GnauApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some Scene {
        // Settings window (can be opened from menu)
        Settings {
            PreferencesView()
        }

        // Onboarding window for first-time setup (T055, T056)
        Window("Welcome to Gnau", id: "onboarding") {
            OnboardingView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .handlesExternalEvents(matching: Set(arrayLiteral: "onboarding"))
    }
}

/// AppDelegate handles menu bar controller initialization
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var analysisCoordinator: AnalysisCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Gnau: Application launched")

        // Hide dock icon for menu bar-only app
        NSApp.setActivationPolicy(.accessory)
        print("📍 Gnau: Set as menu bar app (no dock icon)")

        // Initialize menu bar controller
        menuBarController = MenuBarController()
        print("📍 Gnau: Menu bar controller initialized")

        // Check permissions on launch (T055)
        let permissionManager = PermissionManager.shared
        let hasPermission = permissionManager.isPermissionGranted
        print("🔐 Gnau: Accessibility permission check: \(hasPermission ? "✅ Granted" : "❌ Not granted")")

        if hasPermission {
            // Permission already granted - start grammar checking immediately
            print("✅ Gnau: Starting grammar checking...")
            analysisCoordinator = AnalysisCoordinator.shared
            print("📍 Gnau: Analysis coordinator initialized")
        } else {
            // No permission - show onboarding to request it (T056)
            print("⚠️ Gnau: Accessibility permission not granted - showing onboarding")

            // Set up callback to start grammar checking when permission is granted
            permissionManager.onPermissionGranted = { [weak self] in
                guard let self = self else { return }
                print("✅ Gnau: Permission granted via onboarding - starting grammar checking...")
                self.analysisCoordinator = AnalysisCoordinator.shared
                print("📍 Gnau: Analysis coordinator initialized")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("📱 Gnau: Opening onboarding window")
                if let onboardingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
                    onboardingWindow.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    // Fallback: Open onboarding programmatically
                    self.openOnboardingWindow()
                }
            }
        }
    }

    private func openOnboardingWindow() {
        let onboardingView = OnboardingView()
        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Gnau"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 550, height: 550))
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    // Prevent app from quitting when all windows close (menu bar app)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
