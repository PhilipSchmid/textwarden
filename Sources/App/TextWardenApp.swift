//
//  TextWardenApp.swift
//  TextWarden
//
//  Created by phisch on 09.11.2025.
//
//  Main entry point for TextWarden menu bar application.
//

import SwiftUI
import os.log
import KeyboardShortcuts

@main
struct TextWardenApp: App {
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
        let logPath = "/tmp/textwarden-debug.log"
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
        logToFile("🚀 TextWarden: Application launched")
        NSLog("🚀 TextWarden: Application launched")

        // Log build information for debugging
        logToFile("📦 TextWarden Build Info:")
        logToFile("   Version: \(BuildInfo.fullVersion)")
        logToFile("   Build Timestamp: \(BuildInfo.buildTimestamp)")
        logToFile("   Build Age: \(BuildInfo.buildAge)")
        NSLog("📦 TextWarden Build Info: \(BuildInfo.fullVersion) | Built: \(BuildInfo.buildTimestamp) (\(BuildInfo.buildAge))")

        // Record app session for statistics
        UserStatistics.shared.recordSession()

        NSApp.setActivationPolicy(.accessory)

        logToFile("📍 TextWarden: Set as menu bar app (no dock icon)")
        NSLog("📍 TextWarden: Set as menu bar app (no dock icon)")

        // CRITICAL: LSUIElement apps don't receive activation events, so the main run loop
        // doesn't fully "spin" until something creates a Cocoa event. This causes timers,
        // GCD on main queue, and NSWorkspace notifications to be delayed by 30+ seconds.
        // Calling activate() manually kick-starts the event loop, but it must be delayed
        // until after the app infrastructure is fully initialized (research shows calling it
        // too early can cause it to fail silently).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let msg = "⚡ TextWarden: Calling NSApp.activate() to kick-start event loop"
            self.logToFile(msg)
            NSLog(msg)
            NSApp.activate(ignoringOtherApps: false)
            let msg2 = "✅ TextWarden: NSApp.activate() completed"
            self.logToFile(msg2)
            NSLog(msg2)
        }

        // Initialize menu bar controller
        menuBarController = MenuBarController()
        logToFile("📍 TextWarden: Menu bar controller initialized")
        NSLog("📍 TextWarden: Menu bar controller initialized")

        // Setup keyboard shortcuts
        setupKeyboardShortcuts()
        logToFile("⌨️ TextWarden: Keyboard shortcuts initialized")
        NSLog("⌨️ TextWarden: Keyboard shortcuts initialized")

        // Check permissions on launch (T055)
        let permissionManager = PermissionManager.shared
        let hasPermission = permissionManager.isPermissionGranted
        logToFile("🔐 TextWarden: Accessibility permission check: \(hasPermission ? "✅ Granted" : "❌ Not granted")")
        NSLog("🔐 TextWarden: Accessibility permission check: \(hasPermission ? "✅ Granted" : "❌ Not granted")")

        if hasPermission {
            // Permission already granted - start grammar checking immediately
            logToFile("✅ TextWarden: Starting grammar checking...")
            logToFile("📊 TextWarden: Grammar checking enabled: \(UserPreferences.shared.isEnabled)")

            // Log paused applications (excluding .active state)
            let pausedApps = UserPreferences.shared.appPauseDurations.filter { $0.value != .active }
            let pausedAppBundleIDs = pausedApps.keys.sorted()
            logToFile("📊 TextWarden: Paused applications (\(pausedApps.count)): \(pausedAppBundleIDs)")

            NSLog("✅ TextWarden: Starting grammar checking...")
            NSLog("📊 TextWarden: Grammar checking enabled: \(UserPreferences.shared.isEnabled)")
            NSLog("📊 TextWarden: Paused applications (\(pausedApps.count)): \(pausedAppBundleIDs)")

            analysisCoordinator = AnalysisCoordinator.shared
            logToFile("📍 TextWarden: Analysis coordinator initialized")
            NSLog("📍 TextWarden: Analysis coordinator initialized")

            // Check if user wants to open settings window in foreground
            if UserPreferences.shared.openInForeground {
                logToFile("📍 TextWarden: Opening settings window in foreground (user preference)")
                NSLog("📍 TextWarden: Opening settings window in foreground (user preference)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.openSettingsWindow()
                }
            }
        } else {
            // No permission - show onboarding to request it (T056)
            logToFile("⚠️ TextWarden: Accessibility permission not granted - showing onboarding")
            NSLog("⚠️ TextWarden: Accessibility permission not granted - showing onboarding")

            permissionManager.onPermissionGranted = { [weak self] in
                guard let self = self else { return }
                self.logToFile("✅ TextWarden: Permission granted via onboarding - starting grammar checking...")
                NSLog("✅ TextWarden: Permission granted via onboarding - starting grammar checking...")
                self.analysisCoordinator = AnalysisCoordinator.shared
                self.logToFile("📍 TextWarden: Analysis coordinator initialized")
                NSLog("📍 TextWarden: Analysis coordinator initialized")

                // Return to accessory mode after onboarding completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.setActivationPolicy(.accessory)
                    self.logToFile("📍 TextWarden: Returned to menu bar only mode")
                    NSLog("📍 TextWarden: Returned to menu bar only mode")
                }
            }

            // Open onboarding window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.openOnboardingWindow()
            }
        }
    }

    private func openOnboardingWindow() {
        logToFile("📱 TextWarden: Creating onboarding window")
        NSLog("📱 TextWarden: Creating onboarding window")

        let onboardingView = OnboardingView()
        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to TextWarden"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = true  // Can be released when closed
        window.setContentSize(NSSize(width: 550, height: 550))
        window.center()

        // Temporarily switch to regular mode to show window
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        logToFile("✅ TextWarden: Onboarding window displayed")
        NSLog("✅ TextWarden: Onboarding window displayed")
    }

    // Prevent app from quitting when all windows close (menu bar app)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Open or bring forward the settings window
    /// Creates window manually for reliable reopening behavior
    /// Tab selection is controlled by PreferencesWindowController.shared
    @objc func openSettingsWindow(selectedTab: Int = 0) {
        logToFile("🪟 TextWarden: openSettingsWindow called - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
        NSLog("🪟 TextWarden: openSettingsWindow called - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

        // If window exists, just show it (tab is already set by PreferencesWindowController)
        if let window = settingsWindow {
            logToFile("🪟 TextWarden: Reusing existing settings window")
            NSLog("🪟 TextWarden: Reusing existing settings window")

            logToFile("🪟 TextWarden: Switching to .regular mode to show settings")
            NSLog("🪟 TextWarden: Switching to .regular mode to show settings")

            // Temporarily switch to regular mode to show window
            NSApp.setActivationPolicy(.regular)

            logToFile("🪟 TextWarden: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
            NSLog("🪟 TextWarden: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

            // Force window to front
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)

            // Activate app
            NSApp.activate(ignoringOtherApps: true)

            logToFile("✅ TextWarden: Settings window shown")
            NSLog("✅ TextWarden: Settings window shown")
            return
        }

        logToFile("🪟 TextWarden: Creating new settings window")
        NSLog("🪟 TextWarden: Creating new settings window")

        let preferencesView = PreferencesView()
        let hostingController = NSHostingController(rootView: preferencesView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "TextWarden Settings"
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

        logToFile("🪟 TextWarden: Window created, switching to regular mode")
        NSLog("🪟 TextWarden: Window created, switching to regular mode")

        // Temporarily switch to regular mode to show window
        NSApp.setActivationPolicy(.regular)

        logToFile("🪟 TextWarden: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
        NSLog("🪟 TextWarden: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        // Activate app
        NSApp.activate(ignoringOtherApps: true)

        logToFile("✅ TextWarden: Settings window displayed")
        NSLog("✅ TextWarden: Settings window displayed")
    }
}

// MARK: - Window Delegate
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // When settings window closes, return to menu bar only mode
        if let window = notification.object as? NSWindow, window == settingsWindow {
            logToFile("🪟 TextWarden: windowWillClose - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
            NSLog("🪟 TextWarden: windowWillClose - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

            NSApp.setActivationPolicy(.accessory)

            logToFile("🪟 TextWarden: windowWillClose - AFTER setActivationPolicy(.accessory) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
            NSLog("🪟 TextWarden: windowWillClose - AFTER setActivationPolicy(.accessory) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")
        }
    }

    // MARK: - Keyboard Shortcuts

    /// Setup global keyboard shortcuts using KeyboardShortcuts package
    private func setupKeyboardShortcuts() {
        let preferences = UserPreferences.shared

        // Toggle grammar checking (Cmd+Shift+G by default)
        KeyboardShortcuts.onKeyUp(for: .toggleGrammarChecking) { [weak self] in
            guard preferences.keyboardShortcutsEnabled else { return }

            let msg = "⌨️ Keyboard shortcut: Toggle grammar checking"
            self?.logToFile(msg)
            NSLog(msg)

            // Toggle pause duration between active and indefinite
            if preferences.pauseDuration == .active {
                preferences.pauseDuration = .indefinite
            } else {
                preferences.pauseDuration = .active
            }
        }

        // Accept current suggestion (Tab by default)
        KeyboardShortcuts.onKeyUp(for: .acceptSuggestion) { [weak self] in
            guard preferences.keyboardShortcutsEnabled else { return }
            guard let error = SuggestionPopover.shared.currentError else { return }
            guard let firstSuggestion = error.suggestions.first else { return }

            let msg = "⌨️ Keyboard shortcut: Accept suggestion - \(firstSuggestion)"
            self?.logToFile(msg)
            NSLog(msg)

            SuggestionPopover.shared.applySuggestion(firstSuggestion)
        }

        // Dismiss suggestion popover (Escape by default)
        KeyboardShortcuts.onKeyUp(for: .dismissSuggestion) { [weak self] in
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.currentError != nil else { return }

            let msg = "⌨️ Keyboard shortcut: Dismiss suggestion"
            self?.logToFile(msg)
            NSLog(msg)

            SuggestionPopover.shared.hide()
        }

        // Navigate to previous suggestion (Up arrow by default)
        KeyboardShortcuts.onKeyUp(for: .previousSuggestion) { [weak self] in
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.currentError != nil else { return }

            let msg = "⌨️ Keyboard shortcut: Previous suggestion"
            self?.logToFile(msg)
            NSLog(msg)

            SuggestionPopover.shared.previousError()
        }

        // Navigate to next suggestion (Down arrow by default)
        KeyboardShortcuts.onKeyUp(for: .nextSuggestion) { [weak self] in
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.currentError != nil else { return }

            let msg = "⌨️ Keyboard shortcut: Next suggestion"
            self?.logToFile(msg)
            NSLog(msg)

            SuggestionPopover.shared.nextError()
        }

        // Quick apply shortcuts (Cmd+1, Cmd+2, Cmd+3)
        KeyboardShortcuts.onKeyUp(for: .applySuggestion1) { [weak self] in
            guard preferences.keyboardShortcutsEnabled else { return }
            guard let error = SuggestionPopover.shared.currentError else { return }
            guard error.suggestions.count >= 1 else { return }

            let suggestion = error.suggestions[0]
            let msg = "⌨️ Keyboard shortcut: Apply suggestion 1 - \(suggestion)"
            self?.logToFile(msg)
            NSLog(msg)

            SuggestionPopover.shared.applySuggestion(suggestion)
        }

        KeyboardShortcuts.onKeyUp(for: .applySuggestion2) { [weak self] in
            guard preferences.keyboardShortcutsEnabled else { return }
            guard let error = SuggestionPopover.shared.currentError else { return }
            guard error.suggestions.count >= 2 else { return }

            let suggestion = error.suggestions[1]
            let msg = "⌨️ Keyboard shortcut: Apply suggestion 2 - \(suggestion)"
            self?.logToFile(msg)
            NSLog(msg)

            SuggestionPopover.shared.applySuggestion(suggestion)
        }

        KeyboardShortcuts.onKeyUp(for: .applySuggestion3) { [weak self] in
            guard preferences.keyboardShortcutsEnabled else { return }
            guard let error = SuggestionPopover.shared.currentError else { return }
            guard error.suggestions.count >= 3 else { return }

            let suggestion = error.suggestions[2]
            let msg = "⌨️ Keyboard shortcut: Apply suggestion 3 - \(suggestion)"
            self?.logToFile(msg)
            NSLog(msg)

            SuggestionPopover.shared.applySuggestion(suggestion)
        }
    }
}
