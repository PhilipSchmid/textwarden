//
//  GnauApp.swift
//  Gnau
//
//  Created by phisch on 09.11.2025.
//
//  Main entry point for Gnau menu bar application.
//

import SwiftUI
import os.log

@main
struct GnauApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some Scene {
        // Menu bar app - minimal dummy scene required by SwiftUI
        // Both settings and onboarding windows are created manually in AppDelegate for full control
        // MenuBarController handles the actual menu bar icon
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
    }
}

/// AppDelegate handles menu bar controller initialization
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var analysisCoordinator: AnalysisCoordinator?
    var settingsWindow: NSWindow?  // Keep strong reference to settings window

    func logToFile(_ message: String) {
        let logPath = "/tmp/gnau-debug.log"
        let timestamp = Date()
        let logMessage = "[\(timestamp)] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logToFile("🚀 Gnau: Application launched")
        NSLog("🚀 Gnau: Application launched")

        // Record app session for statistics
        UserStatistics.shared.recordSession()

        // Hide dock icon for menu bar-only app (like VoiceInk)
        NSApp.setActivationPolicy(.accessory)

        logToFile("📍 Gnau: Set as menu bar app (no dock icon)")
        NSLog("📍 Gnau: Set as menu bar app (no dock icon)")

        // CRITICAL: LSUIElement apps don't receive activation events, so the main run loop
        // doesn't fully "spin" until something creates a Cocoa event. This causes timers,
        // GCD on main queue, and NSWorkspace notifications to be delayed by 30+ seconds.
        // Calling activate() manually kick-starts the event loop, but it must be delayed
        // until after the app infrastructure is fully initialized (research shows calling it
        // too early can cause it to fail silently).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let msg = "⚡ Gnau: Calling NSApp.activate() to kick-start event loop"
            self.logToFile(msg)
            NSLog(msg)
            NSApp.activate(ignoringOtherApps: false)
            let msg2 = "✅ Gnau: NSApp.activate() completed"
            self.logToFile(msg2)
            NSLog(msg2)
        }

        // Initialize menu bar controller
        menuBarController = MenuBarController()
        logToFile("📍 Gnau: Menu bar controller initialized")
        NSLog("📍 Gnau: Menu bar controller initialized")

        // Check permissions on launch (T055)
        let permissionManager = PermissionManager.shared
        let hasPermission = permissionManager.isPermissionGranted
        logToFile("🔐 Gnau: Accessibility permission check: \(hasPermission ? "✅ Granted" : "❌ Not granted")")
        NSLog("🔐 Gnau: Accessibility permission check: \(hasPermission ? "✅ Granted" : "❌ Not granted")")

        if hasPermission {
            // Permission already granted - start grammar checking immediately
            logToFile("✅ Gnau: Starting grammar checking...")
            logToFile("📊 Gnau: Grammar checking enabled: \(UserPreferences.shared.isEnabled)")

            // Log paused applications (excluding .active state)
            let pausedApps = UserPreferences.shared.appPauseDurations.filter { $0.value != .active }
            let pausedAppBundleIDs = pausedApps.keys.sorted()
            logToFile("📊 Gnau: Paused applications (\(pausedApps.count)): \(pausedAppBundleIDs)")

            NSLog("✅ Gnau: Starting grammar checking...")
            NSLog("📊 Gnau: Grammar checking enabled: \(UserPreferences.shared.isEnabled)")
            NSLog("📊 Gnau: Paused applications (\(pausedApps.count)): \(pausedAppBundleIDs)")

            analysisCoordinator = AnalysisCoordinator.shared
            logToFile("📍 Gnau: Analysis coordinator initialized")
            NSLog("📍 Gnau: Analysis coordinator initialized")

            // Check if user wants to open settings window in foreground
            if UserPreferences.shared.openInForeground {
                logToFile("📍 Gnau: Opening settings window in foreground (user preference)")
                NSLog("📍 Gnau: Opening settings window in foreground (user preference)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.openSettingsWindow()
                }
            }
        } else {
            // No permission - show onboarding to request it (T056)
            logToFile("⚠️ Gnau: Accessibility permission not granted - showing onboarding")
            NSLog("⚠️ Gnau: Accessibility permission not granted - showing onboarding")

            // Set up callback to start grammar checking when permission is granted
            permissionManager.onPermissionGranted = { [weak self] in
                guard let self = self else { return }
                self.logToFile("✅ Gnau: Permission granted via onboarding - starting grammar checking...")
                NSLog("✅ Gnau: Permission granted via onboarding - starting grammar checking...")
                self.analysisCoordinator = AnalysisCoordinator.shared
                self.logToFile("📍 Gnau: Analysis coordinator initialized")
                NSLog("📍 Gnau: Analysis coordinator initialized")

                // Return to accessory mode after onboarding completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.setActivationPolicy(.accessory)
                    self.logToFile("📍 Gnau: Returned to menu bar only mode")
                    NSLog("📍 Gnau: Returned to menu bar only mode")
                }
            }

            // Open onboarding window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.openOnboardingWindow()
            }
        }
    }

    private func openOnboardingWindow() {
        logToFile("📱 Gnau: Creating onboarding window")
        NSLog("📱 Gnau: Creating onboarding window")

        let onboardingView = OnboardingView()
        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Gnau"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = true  // Can be released when closed
        window.setContentSize(NSSize(width: 550, height: 550))
        window.center()

        // Temporarily switch to regular mode to show window
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        logToFile("✅ Gnau: Onboarding window displayed")
        NSLog("✅ Gnau: Onboarding window displayed")
    }

    // Prevent app from quitting when all windows close (menu bar app)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Open or bring forward the settings window
    /// Creates window manually for reliable reopening behavior
    /// Tab selection is controlled by PreferencesWindowController.shared
    @objc func openSettingsWindow(selectedTab: Int = 0) {
        logToFile("🪟 Gnau: openSettingsWindow called - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
        NSLog("🪟 Gnau: openSettingsWindow called - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

        // If window exists, just show it (tab is already set by PreferencesWindowController)
        if let window = settingsWindow {
            logToFile("🪟 Gnau: Reusing existing settings window")
            NSLog("🪟 Gnau: Reusing existing settings window")

            logToFile("🪟 Gnau: Switching to .regular mode to show settings")
            NSLog("🪟 Gnau: Switching to .regular mode to show settings")

            // Temporarily switch to regular mode to show window
            NSApp.setActivationPolicy(.regular)

            logToFile("🪟 Gnau: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
            NSLog("🪟 Gnau: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

            // Force window to front
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)

            // Activate app
            NSApp.activate(ignoringOtherApps: true)

            logToFile("✅ Gnau: Settings window shown")
            NSLog("✅ Gnau: Settings window shown")
            return
        }

        // Create window first time
        logToFile("🪟 Gnau: Creating new settings window")
        NSLog("🪟 Gnau: Creating new settings window")

        let preferencesView = PreferencesView()
        let hostingController = NSHostingController(rootView: preferencesView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Gnau Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false  // CRITICAL: Keep window alive when closed
        window.setContentSize(NSSize(width: 850, height: 700))
        window.minSize = NSSize(width: 750, height: 600)
        window.center()
        window.delegate = self
        window.level = .normal
        window.toolbar = NSToolbar()
        window.toolbar?.displayMode = .iconOnly

        // Store window
        settingsWindow = window

        logToFile("🪟 Gnau: Window created, switching to regular mode")
        NSLog("🪟 Gnau: Window created, switching to regular mode")

        // Temporarily switch to regular mode to show window
        NSApp.setActivationPolicy(.regular)

        logToFile("🪟 Gnau: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
        NSLog("🪟 Gnau: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

        // Show window aggressively
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        // Activate app
        NSApp.activate(ignoringOtherApps: true)

        logToFile("✅ Gnau: Settings window displayed")
        NSLog("✅ Gnau: Settings window displayed")
    }
}

// MARK: - Window Delegate
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // When settings window closes, return to menu bar only mode
        if let window = notification.object as? NSWindow, window == settingsWindow {
            logToFile("🪟 Gnau: windowWillClose - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
            NSLog("🪟 Gnau: windowWillClose - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

            NSApp.setActivationPolicy(.accessory)

            logToFile("🪟 Gnau: windowWillClose - AFTER setActivationPolicy(.accessory) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
            NSLog("🪟 Gnau: windowWillClose - AFTER setActivationPolicy(.accessory) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
        }
    }
}
