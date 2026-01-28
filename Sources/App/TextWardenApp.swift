//
//  TextWardenApp.swift
//  TextWarden
//
//  Created by phisch on 09.11.2025.
//
//  Main entry point for TextWarden menu bar application.
//

import KeyboardShortcuts
import os.log
import SwiftUI

@main
struct TextWardenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some Scene {
        // Menu bar app - hidden placeholder scene (no visible window)
        WindowGroup(id: "hidden-placeholder") {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .defaultSize(width: 0, height: 0)
        .windowResizability(.contentSize)
        .commands {
            // App menu customizations
            CommandGroup(replacing: .appInfo) {
                Button("About TextWarden") {
                    PreferencesWindowController.shared.selectTab(.about)
                    NSApp.sendAction(#selector(AppDelegate.openSettingsWindow(selectedTab:)), to: nil, from: nil)
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdaterViewModel.shared.checkForUpdates()
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    PreferencesWindowController.shared.selectTab(.general)
                    NSApp.sendAction(#selector(AppDelegate.openSettingsWindow(selectedTab:)), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // Replace default New Window with New Sketch
            CommandGroup(replacing: .newItem) {
                Button("New Sketch") {
                    // Show Sketch Pad window if not visible
                    SketchPadWindowController.shared.showWindow()
                    // Create new sketch
                    SketchPadViewModel.shared.newDocument()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // Add Save command
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    Task {
                        await SketchPadViewModel.shared.saveCurrentDocument()
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            // Standard Edit menu commands (Undo, Redo, Cut, Copy, Paste, Select All)
            TextEditingCommands()

            // Format menu for Sketch Pad text formatting
            CommandMenu("Format") {
                Button("Bold") {
                    SketchPadViewModel.shared.toggleBold()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    SketchPadViewModel.shared.toggleItalic()
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Underline") {
                    SketchPadViewModel.shared.toggleUnderline()
                }
                .keyboardShortcut("u", modifiers: .command)

                Button("Strikethrough") {
                    SketchPadViewModel.shared.toggleStrikethrough()
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])

                Divider()

                Button("Heading 1") {
                    SketchPadViewModel.shared.toggleHeading(level: 1)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Heading 2") {
                    SketchPadViewModel.shared.toggleHeading(level: 2)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Heading 3") {
                    SketchPadViewModel.shared.toggleHeading(level: 3)
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("Clear Formatting") {
                    SketchPadViewModel.shared.clearFormatting()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
        }
    }
}

/// AppDelegate handles menu bar controller initialization
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var analysisCoordinator: AnalysisCoordinator?
    var settingsWindow: NSWindow? // Keep strong reference to settings window
    var onboardingWindow: NSWindow? // Keep strong reference to onboarding window
    var sketchPadWindow: NSWindow? // Keep strong reference to sketch pad window (managed by SketchPadWindowController)

    /// Shared updater view model for Sparkle auto-updates
    /// Uses singleton to ensure only ONE SPUStandardUpdaterController exists
    @MainActor var updaterViewModel: UpdaterViewModel { UpdaterViewModel.shared }

    func applicationDidFinishLaunching(_: Notification) {
        Logger.info("Application launched", category: Logger.lifecycle)

        // Enable key repeat instead of showing accent picker when holding keys
        // This is the expected behavior for text editors - users can still access
        // accents via Option+key combinations
        UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled")

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

        // Note: Menus are configured via SwiftUI Commands in TextWardenApp.body.commands
        Logger.info("SwiftUI Commands will handle menu setup", category: Logger.lifecycle)

        // Setup keyboard shortcuts
        setupKeyboardShortcuts()

        // CRITICAL: Disable popover-specific shortcuts at startup
        // These shortcuts (Tab, Option+Escape, etc.) must only be active when the popover is visible
        // Otherwise they intercept keypresses globally and break normal app behavior
        KeyboardShortcuts.Name.disablePopoverShortcuts()
        Logger.info("Keyboard shortcuts initialized (popover shortcuts disabled until needed)", category: Logger.lifecycle)

        // Sparkle handles automatic update checks based on user preference (automaticallyChecksForUpdates)
        // Do NOT manually call checkForUpdatesInBackground() - this interferes with Sparkle's scheduler
        // See: https://sparkle-project.org/documentation/programmatic-setup/
        Logger.info("Sparkle auto-update: \(updaterViewModel.automaticallyChecksForUpdates ? "enabled" : "disabled")", category: Logger.lifecycle)

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
                Logger.debug("Setting up onPermissionGranted callback on PermissionManager.shared", category: Logger.permissions)
                permissionManager.onPermissionGranted = { [weak self] in
                    guard let self else {
                        Logger.error("onPermissionGranted callback: self (AppDelegate) is nil! Cannot initialize AnalysisCoordinator.", category: Logger.permissions)
                        return
                    }
                    Logger.info("onPermissionGranted callback EXECUTED - initializing AnalysisCoordinator", category: Logger.permissions)
                    analysisCoordinator = AnalysisCoordinator.shared
                    Logger.info("Analysis coordinator initialized successfully", category: Logger.lifecycle)
                }
                Logger.debug("onPermissionGranted callback is now set (callback != nil: \(permissionManager.onPermissionGranted != nil))", category: Logger.permissions)
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
        window.isReleasedWhenClosed = false // We manage the lifecycle manually
        window.setContentSize(NSSize(width: 640, height: 760))
        window.center()

        // Store strong reference to prevent premature deallocation
        onboardingWindow = window

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
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_: Notification) {
        Logger.info("Application will terminate - cleaning up", category: Logger.lifecycle)

        // Save Sketch Pad document synchronously before termination
        SketchPadViewModel.shared.saveImmediately()

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
    @objc func openSettingsWindow(selectedTab _: Int = 0) {
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
        window.isReleasedWhenClosed = false // CRITICAL: Keep window alive when closed
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
        // When settings window closes, check if we should return to menu bar only mode
        if let window = notification.object as? NSWindow, window == settingsWindow {
            Logger.debug("Settings windowWillClose - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

            // Only return to accessory mode if Sketch Pad is not visible
            let sketchPadVisible = SketchPadWindowController.shared.isVisible
            if !sketchPadVisible {
                NSApp.setActivationPolicy(.accessory)
                Logger.debug("setActivationPolicy(.accessory) completed - no other windows visible", category: Logger.ui)
            } else {
                Logger.debug("Sketch Pad still visible, staying in regular mode", category: Logger.ui)
            }
        }
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

                // Check if Sketch Pad is the key window
                if SketchPadWindowController.shared.isKeyWindow {
                    // Trigger style analysis in Sketch Pad
                    SketchPadViewModel.shared.triggerStyleAnalysis()
                } else {
                    // Trigger manual style check via AnalysisCoordinator for other apps
                    AnalysisCoordinator.shared.runManualStyleCheck()
                }
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

        // Show grammar suggestions popover (Option+Control+G by default)
        KeyboardShortcuts.onKeyUp(for: .showGrammarSuggestions) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                // Toggle: hide if visible, show if hidden
                if SuggestionPopover.shared.isVisible {
                    Logger.debug("Keyboard shortcut: Hide grammar popover (toggle)", category: Logger.ui)
                    SuggestionPopover.shared.hide()
                } else {
                    Logger.debug("Keyboard shortcut: Show grammar suggestions", category: Logger.ui)
                    FloatingErrorIndicator.shared.showGrammarPopoverFromKeyboard()
                }
            }
        }

        // Show style suggestions popover (Option+Control+Y by default)
        KeyboardShortcuts.onKeyUp(for: .showStyleSuggestions) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                // Toggle: hide if visible, show if hidden
                if SuggestionPopover.shared.isVisible {
                    Logger.debug("Keyboard shortcut: Hide style popover (toggle)", category: Logger.ui)
                    SuggestionPopover.shared.hide()
                } else {
                    Logger.debug("Keyboard shortcut: Show style suggestions", category: Logger.ui)
                    FloatingErrorIndicator.shared.showStylePopoverFromKeyboard()
                }
            }
        }

        // Show AI Compose popover (Option+Control+W by default)
        KeyboardShortcuts.onKeyUp(for: .showAICompose) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                // Toggle: hide if visible, show if hidden
                if TextGenerationPopover.shared.isVisible {
                    Logger.debug("Keyboard shortcut: Hide AI Compose (toggle)", category: Logger.ui)
                    TextGenerationPopover.shared.hide()
                } else {
                    Logger.debug("Keyboard shortcut: Show AI Compose", category: Logger.ui)
                    FloatingErrorIndicator.shared.showAIComposeFromKeyboard()
                }
            }
        }

        // Show Readability popover (Option+Control+R by default)
        KeyboardShortcuts.onKeyUp(for: .showReadability) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                // Toggle: hide if visible, show if hidden
                if ReadabilityPopover.shared.isVisible {
                    Logger.debug("Keyboard shortcut: Hide Readability (toggle)", category: Logger.ui)
                    ReadabilityPopover.shared.hide()
                } else {
                    Logger.debug("Keyboard shortcut: Show Readability", category: Logger.ui)
                    FloatingErrorIndicator.shared.showReadabilityFromKeyboard()
                }
            }
        }

        // Toggle Sketch Pad window (Option+Control+N by default)
        KeyboardShortcuts.onKeyUp(for: .toggleSketchPad) {
            Task { @MainActor in
                let preferences = UserPreferences.shared
                guard preferences.keyboardShortcutsEnabled else { return }

                Logger.debug("Keyboard shortcut: Toggle Sketch Pad", category: Logger.ui)
                SketchPadWindowController.shared.toggleWindow()
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
                   let firstSuggestion = error.suggestions.first
                {
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
