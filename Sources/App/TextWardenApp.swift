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
        // Menu bar app - use Settings scene as placeholder (doesn't auto-create window)
        // Both settings and onboarding windows are created manually in AppDelegate for full control
        // MenuBarController handles the actual menu bar icon
        // Note: WindowGroup always creates a visible window, Settings does not
        Settings {
            EmptyView()
        }
    }
}

/// AppDelegate handles menu bar controller initialization
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var analysisCoordinator: AnalysisCoordinator?
    var settingsWindow: NSWindow?  // Keep strong reference to settings window
    var onboardingWindow: NSWindow?  // Keep strong reference to onboarding window

    /// Shared updater view model for Sparkle auto-updates
    /// Lazy to ensure initialization happens on main thread (UpdaterViewModel is @MainActor)
    @MainActor lazy var updaterViewModel = UpdaterViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.info("Application launched", category: Logger.lifecycle)

        // Log build information for debugging
        Logger.info("Build Info - Version: \(BuildInfo.fullVersion), Built: \(BuildInfo.buildTimestamp) (\(BuildInfo.buildAge))", category: Logger.lifecycle)

        // CRITICAL: Set global timeout for Accessibility API calls
        // The default is 6 seconds which causes severe freezing with apps that have slow AX implementations
        // (e.g., Microsoft Office overlays). Setting to 1.0s is the industry standard and
        // provides a reasonable upper bound while preventing severe freezes.
        // When timeout expires, AX calls return kAXErrorCannotComplete instead of blocking indefinitely.
        // Reference: https://github.com/lwouis/alt-tab-macos uses this same approach.
        // NOTE: For apps with slow AX (Outlook), we also use deferred text extraction
        // to reduce the frequency of AX calls during typing - see defersTextExtraction flag.
        let axTimeout: Float = 1.0
        let timeoutResult = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axTimeout)
        if timeoutResult == .success {
            Logger.info("Set global AX messaging timeout to \(axTimeout)s", category: Logger.accessibility)
        } else {
            Logger.warning("Failed to set AX messaging timeout: \(timeoutResult.rawValue)", category: Logger.accessibility)
        }

        // Initialize unified logging (Rust → Swift bridge)
        Logger.registerRustLogCallback()

        // Initialize Rust logging (with Swift callback now registered)
        let logLevel = Logger.minimumLogLevel
        initialize_logging(logLevel.rawValue)
        Logger.info("Rust logging initialized with level: \(logLevel.rawValue) (unified)", category: Logger.ffi)

        // Record app session for statistics
        UserStatistics.shared.recordSession()

        // Set app launch timestamp for "This Session" filtering
        UserStatistics.shared.appLaunchTimestamp = Date()

        // Perform periodic cleanup of old statistics data
        UserStatistics.shared.performPeriodicCleanup()

        // Start resource monitoring
        ResourceMonitor.shared.startMonitoring()
        Logger.info("Resource monitoring started", category: Logger.lifecycle)

        NSApp.setActivationPolicy(.accessory)

        Logger.info("Set as menu bar app (no dock icon)", category: Logger.lifecycle)

        // CRITICAL: LSUIElement apps don't receive activation events, so the main run loop
        // doesn't fully "spin" until something creates a Cocoa event. This causes timers,
        // GCD on main queue, and NSWorkspace notifications to be delayed by 30+ seconds.
        // Calling activate() manually kick-starts the event loop, but it must be delayed
        // until after the app infrastructure is fully initialized (research shows calling it
        // too early can cause it to fail silently).
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.shortDelay) {
            Logger.debug("Calling NSApp.activate() to kick-start event loop", category: Logger.lifecycle)
            NSApp.activate(ignoringOtherApps: false)
            Logger.debug("NSApp.activate() completed", category: Logger.lifecycle)
        }

        // Initialize menu bar controller
        menuBarController = MenuBarController()
        Logger.info("Menu bar controller initialized", category: Logger.lifecycle)

        // Setup main application menu (overrides default About action)
        setupMainMenu()
        Logger.info("Main application menu initialized", category: Logger.lifecycle)

        // Setup keyboard shortcuts
        setupKeyboardShortcuts()

        // CRITICAL: Disable popover-specific shortcuts at startup
        // These shortcuts (Tab, Option+Escape, etc.) must only be active when the popover is visible
        // Otherwise they intercept keypresses globally and break normal app behavior
        KeyboardShortcuts.Name.disablePopoverShortcuts()
        Logger.info("Keyboard shortcuts initialized (popover shortcuts disabled until needed)", category: Logger.lifecycle)

        // Check for updates silently in background
        updaterViewModel.checkForUpdatesInBackground()
        Logger.info("Background update check initiated", category: Logger.lifecycle)

        // Check permissions and onboarding status
        let permissionManager = PermissionManager.shared
        let hasPermission = permissionManager.isPermissionGranted
        let hasCompletedOnboarding = UserPreferences.shared.hasCompletedOnboarding
        Logger.info("Accessibility permission check: \(hasPermission ? "Granted" : "Not granted")", category: Logger.permissions)
        Logger.info("Onboarding completed: \(hasCompletedOnboarding)", category: Logger.lifecycle)

        // Show onboarding if not completed yet, regardless of permission status
        let shouldShowOnboarding = !hasCompletedOnboarding || !hasPermission

        if shouldShowOnboarding {
            // Show onboarding (either first launch or permission not granted)
            if !hasCompletedOnboarding {
                Logger.info("First launch or reset - showing onboarding", category: Logger.lifecycle)
            } else {
                Logger.warning("Accessibility permission not granted - showing onboarding", category: Logger.permissions)
            }

            // If permission already granted, start analysis coordinator immediately
            if hasPermission {
                analysisCoordinator = AnalysisCoordinator.shared
                Logger.info("Analysis coordinator initialized (permission already granted)", category: Logger.lifecycle)
            } else {
                permissionManager.onPermissionGranted = { [weak self] in
                    guard let self = self else { return }
                    Logger.info("Permission granted via onboarding - starting grammar checking", category: Logger.permissions)
                    self.analysisCoordinator = AnalysisCoordinator.shared
                    Logger.info("Analysis coordinator initialized", category: Logger.lifecycle)
                }
            }

            // Open onboarding window
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.longDelay) { [weak self] in
                self?.openOnboardingWindow()
            }
        } else {
            // Permission granted and onboarding completed - start grammar checking immediately
            Logger.info("Starting grammar checking - enabled: \(UserPreferences.shared.isEnabled)", category: Logger.lifecycle)

            // Log paused applications (excluding .active state)
            let pausedApps = UserPreferences.shared.appPauseDurations.filter { $0.value != .active }
            let pausedAppBundleIDs = pausedApps.keys.sorted()
            Logger.info("Paused applications (\(pausedApps.count)): \(pausedAppBundleIDs)", category: Logger.lifecycle)

            analysisCoordinator = AnalysisCoordinator.shared
            Logger.info("Analysis coordinator initialized", category: Logger.lifecycle)

            // Check if user wants to open settings window in foreground
            if UserPreferences.shared.openInForeground {
                Logger.info("Opening settings window in foreground (user preference)", category: Logger.ui)
                DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.hoverDelay) { [weak self] in
                    self?.openSettingsWindow()
                }
            }

            // Check for pending milestones on startup (e.g., after system restart)
            // Delay to ensure menu bar is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.startupMilestoneCheckDelay) { [weak self] in
                Task { @MainActor in
                    self?.checkForStartupMilestone()
                }
            }
        }
    }

    /// Check for and show any pending milestone on app startup
    @MainActor
    private func checkForStartupMilestone() {
        guard let milestone = MilestoneManager.shared.checkForMilestones() else {
            Logger.debug("No pending milestones on startup", category: Logger.ui)
            return
        }

        Logger.info("Found pending milestone on startup: \(milestone.id)", category: Logger.ui)
        menuBarController?.showMilestone(milestone)
    }

    @objc func openOnboardingWindow() {
        Logger.info("Creating onboarding window", category: Logger.ui)

        let onboardingView = OnboardingView()
        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to TextWarden"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false  // We manage the lifecycle manually
        window.setContentSize(NSSize(width: 640, height: 760))
        window.center()

        // Store strong reference to prevent premature deallocation
        self.onboardingWindow = window

        // Clean up reference after window closes (with delay for animations)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Delay cleanup to let window animations complete (macOS 26 fix)
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.windowCleanupDelay) {
                self?.onboardingWindow = nil
                Logger.debug("Onboarding window reference cleared", category: Logger.ui)
            }
        }

        // Temporarily switch to regular mode to show window
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Logger.info("Onboarding window displayed", category: Logger.ui)
    }

    /// Close the onboarding window and return to menu bar mode
    @objc func closeOnboardingWindow() {
        Logger.info("Closing onboarding window", category: Logger.ui)

        // Close the window (triggers willCloseNotification which cleans up the reference)
        onboardingWindow?.close()

        // Return to accessory mode after window closes
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.accessoryModeReturnDelay) {
            NSApp.setActivationPolicy(.accessory)
            Logger.info("Returned to menu bar only mode", category: Logger.lifecycle)
        }
    }

    // Prevent app from quitting when all windows close (menu bar app)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.info("Application will terminate - cleaning up", category: Logger.lifecycle)

        // Stop crash recovery heartbeat for clean shutdown detection
        CrashRecoveryManager.shared.stopHeartbeat()

        // Stop resource monitoring
        ResourceMonitor.shared.stopMonitoring()

        // Flush and persist log volume statistics
        UserStatistics.shared.flushLogSample()
        UserStatistics.shared.forceLogVolumePersist()

        // Clean up AnalysisCoordinator (timers, event monitors)
        analysisCoordinator?.cleanup()

        // Clean up TypingDetector (keyboard monitor, timers)
        TypingDetector.shared.cleanup()

        Logger.info("Cleanup complete", category: Logger.lifecycle)
    }

    /// Open or bring forward the settings window
    /// Creates window manually for reliable reopening behavior
    /// Tab selection is controlled by PreferencesWindowController.shared
    @objc func openSettingsWindow(selectedTab: Int = 0) {
        Logger.debug("openSettingsWindow called - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

        // If window exists, just show it (tab is already set by PreferencesWindowController)
        if let window = settingsWindow {
            Logger.debug("Reusing existing settings window", category: Logger.ui)

            Logger.debug("Switching to .regular mode to show settings", category: Logger.ui)

            // Temporarily switch to regular mode to show window
            NSApp.setActivationPolicy(.regular)

            Logger.debug("setActivationPolicy(.regular) completed - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

            // Force window to front
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)

            // Activate app
            NSApp.activate(ignoringOtherApps: true)

            Logger.info("Settings window shown", category: Logger.ui)
            return
        }

        Logger.debug("Creating new settings window", category: Logger.ui)

        let preferencesView = PreferencesView()
        let hostingController = NSHostingController(rootView: preferencesView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "TextWarden Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false  // CRITICAL: Keep window alive when closed
        window.setContentSize(NSSize(width: 850, height: 1000))
        window.minSize = NSSize(width: 750, height: 800)
        window.center()
        window.delegate = self
        window.level = .normal

        // Add toolbar for modern macOS 26 "Toolbar window" style (26pt corner radius)
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Store window
        settingsWindow = window

        Logger.debug("Window created, switching to regular mode", category: Logger.ui)

        // Temporarily switch to regular mode to show window
        NSApp.setActivationPolicy(.regular)

        Logger.debug("setActivationPolicy(.regular) completed - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        // Activate app
        NSApp.activate(ignoringOtherApps: true)

        Logger.info("Settings window displayed", category: Logger.ui)
    }
}

// MARK: - Window Delegate
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // When settings window closes, return to menu bar only mode
        if let window = notification.object as? NSWindow, window == settingsWindow {
            Logger.debug("windowWillClose - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

            NSApp.setActivationPolicy(.accessory)

            Logger.debug("setActivationPolicy(.accessory) completed - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)
        }
    }

    // MARK: - Menu Setup

    /// Setup custom main application menu to override default About action
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu (TextWarden)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        // About TextWarden - custom action
        let aboutItem = NSMenuItem(
            title: "About TextWarden",
            action: #selector(showAboutFromMenu),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        // Check for Updates
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        updateItem.target = self
        appMenu.addItem(updateItem)

        appMenu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsWindowFromMenu),
            keyEquivalent: ","
        )
        prefsItem.target = self
        appMenu.addItem(prefsItem)

        appMenu.addItem(NSMenuItem.separator())

        // Hide TextWarden
        let hideItem = NSMenuItem(
            title: "Hide TextWarden",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)

        // Hide Others
        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        // Show All
        let showAllItem = NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())

        // Quit TextWarden
        let quitItem = NSMenuItem(
            title: "Quit TextWarden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        // Help menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)

        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu

        let helpItem = NSMenuItem(
            title: "TextWarden Help",
            action: #selector(showHelpFromMenu),
            keyEquivalent: "?"
        )
        helpItem.target = self
        helpMenu.addItem(helpItem)

        NSApp.mainMenu = mainMenu
    }

    @MainActor @objc private func showAboutFromMenu() {
        PreferencesWindowController.shared.selectTab(.about)
        openSettingsWindow()
    }

    @MainActor @objc private func checkForUpdatesFromMenu() {
        updaterViewModel.checkForUpdates()
        showAboutFromMenu()
    }

    @MainActor @objc private func openSettingsWindowFromMenu() {
        PreferencesWindowController.shared.selectTab(.general)
        openSettingsWindow()
    }

    @objc private func showHelpFromMenu() {
        NSApp.showHelp(nil)
    }

    // MARK: - Keyboard Shortcuts

    /// Setup global keyboard shortcuts using KeyboardShortcuts package
    private func setupKeyboardShortcuts() {
        // Toggle TextWarden (Option+Control+T by default)
        KeyboardShortcuts.onKeyUp(for: .toggleTextWarden) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                Logger.debug("Keyboard shortcut: Toggle TextWarden", category: Logger.ui)

                // Toggle pause duration between active and indefinite
                if preferences.pauseDuration == .active {
                    // Disabling - hide all overlays immediately
                    preferences.pauseDuration = .indefinite
                    MenuBarController.shared?.setIconState(.inactive)

                    // Hide error underlines, indicator, and popover
                    FloatingErrorIndicator.shared.hide()
                    SuggestionPopover.shared.hide()
                    AnalysisCoordinator.shared.hideAllOverlays()

                    Logger.debug("Grammar checking disabled - hid all overlays", category: Logger.ui)
                } else {
                    // Enabling - trigger re-analysis to show errors
                    preferences.pauseDuration = .active
                    MenuBarController.shared?.setIconState(.active)

                    // Trigger re-analysis of current text to show errors immediately
                    AnalysisCoordinator.shared.triggerReanalysis()

                    Logger.debug("Grammar checking enabled - triggered re-analysis", category: Logger.ui)
                }
            }
        }

        // Run style check on current text (Option+Control+S by default)
        KeyboardShortcuts.onKeyUp(for: .runStyleCheck) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                Logger.debug("Keyboard shortcut: Run style check", category: Logger.ui)

                // Trigger manual style check via AnalysisCoordinator
                AnalysisCoordinator.shared.runManualStyleCheck()
            }
        }

        // Fix all obvious errors (Option+Control+A by default - "A" for Apply All)
        // Applies all single-suggestion fixes at once
        KeyboardShortcuts.onKeyUp(for: .fixAllObvious) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                Logger.debug("Keyboard shortcut: Fix all obvious errors", category: Logger.ui)

                let fixCount = await AnalysisCoordinator.shared.applyAllSingleSuggestionFixes()
                if fixCount > 0 {
                    Logger.info("Fixed \(fixCount) obvious error(s)", category: Logger.ui)
                }
            }
        }

        // Toggle suggestion popover (Option+Control+G by default)
        KeyboardShortcuts.onKeyUp(for: .showSuggestionPopover) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                // Toggle: hide if visible, show if hidden
                if SuggestionPopover.shared.isVisible {
                    Logger.debug("Keyboard shortcut: Hide suggestion popover (toggle)", category: Logger.ui)
                    SuggestionPopover.shared.hide()
                } else {
                    Logger.debug("Keyboard shortcut: Show suggestion popover (toggle)", category: Logger.ui)
                    // Show popover via FloatingErrorIndicator (uses its position and data)
                    FloatingErrorIndicator.shared.showPopoverFromKeyboard()
                }
            }
        }

        // Accept current suggestion (Tab by default)
        KeyboardShortcuts.onKeyUp(for: .acceptSuggestion) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }
                guard SuggestionPopover.shared.isVisible else { return }

                // Handle grammar errors
                if let error = SuggestionPopover.shared.currentError,
                   let firstSuggestion = error.suggestions.first {
                    Logger.debug("Keyboard shortcut: Accept grammar suggestion - \(firstSuggestion)", category: Logger.ui)
                    SuggestionPopover.shared.applySuggestion(firstSuggestion)
                    return
                }

                // Handle style suggestions
                if SuggestionPopover.shared.currentStyleSuggestion != nil {
                    SuggestionPopover.shared.acceptStyleSuggestion()
                    return
                }
            }
        }

        // Dismiss suggestion popover (Escape by default)
        KeyboardShortcuts.onKeyUp(for: .dismissSuggestion) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }
                guard SuggestionPopover.shared.isVisible else { return }

                Logger.debug("Keyboard shortcut: Dismiss suggestion", category: Logger.ui)

                SuggestionPopover.shared.hide()
            }
        }

        // Navigate to previous suggestion (Option + Left arrow by default)
        KeyboardShortcuts.onKeyUp(for: .previousSuggestion) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }
                guard SuggestionPopover.shared.isVisible else { return }

                Logger.debug("Keyboard shortcut: Previous suggestion", category: Logger.ui)

                // Use unified navigation to cycle through both grammar errors and style suggestions
                SuggestionPopover.shared.previousUnifiedItem()
            }
        }

        // Navigate to next suggestion (Option + Right arrow by default)
        KeyboardShortcuts.onKeyUp(for: .nextSuggestion) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }
                guard SuggestionPopover.shared.isVisible else { return }

                Logger.debug("Keyboard shortcut: Next suggestion", category: Logger.ui)

                // Use unified navigation to cycle through both grammar errors and style suggestions
                SuggestionPopover.shared.nextUnifiedItem()
            }
        }

        // Quick apply shortcuts (Option+1, Option+2, Option+3)
        KeyboardShortcuts.onKeyUp(for: .applySuggestion1) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }
                guard SuggestionPopover.shared.isVisible else { return }
                guard let error = SuggestionPopover.shared.currentError else { return }
                // Use .first for safe array access
                guard let suggestion = error.suggestions.first else { return }

                Logger.debug("Keyboard shortcut: Apply suggestion 1 - \(suggestion)", category: Logger.ui)

                SuggestionPopover.shared.applySuggestion(suggestion)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .applySuggestion2) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }
                guard SuggestionPopover.shared.isVisible else { return }
                guard let error = SuggestionPopover.shared.currentError else { return }
                // Bounds-checked access for index 1
                guard error.suggestions.indices.contains(1) else { return }
                let suggestion = error.suggestions[1]

                Logger.debug("Keyboard shortcut: Apply suggestion 2 - \(suggestion)", category: Logger.ui)

                SuggestionPopover.shared.applySuggestion(suggestion)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .applySuggestion3) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }
                guard SuggestionPopover.shared.isVisible else { return }
                guard let error = SuggestionPopover.shared.currentError else { return }
                // Bounds-checked access for index 2
                guard error.suggestions.indices.contains(2) else { return }
                let suggestion = error.suggestions[2]

                Logger.debug("Keyboard shortcut: Apply suggestion 3 - \(suggestion)", category: Logger.ui)

                SuggestionPopover.shared.applySuggestion(suggestion)
            }
        }
    }
}
