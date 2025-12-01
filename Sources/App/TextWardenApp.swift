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
import Combine

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
    private var styleCheckingCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.info("Application launched", category: Logger.lifecycle)

        // Log build information for debugging
        Logger.info("Build Info - Version: \(BuildInfo.fullVersion), Built: \(BuildInfo.buildTimestamp) (\(BuildInfo.buildAge))", category: Logger.lifecycle)

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Logger.debug("Calling NSApp.activate() to kick-start event loop", category: Logger.lifecycle)
            NSApp.activate(ignoringOtherApps: false)
            Logger.debug("NSApp.activate() completed", category: Logger.lifecycle)
        }

        // Initialize menu bar controller
        menuBarController = MenuBarController()
        Logger.info("Menu bar controller initialized", category: Logger.lifecycle)

        // Setup keyboard shortcuts
        setupKeyboardShortcuts()
        Logger.info("Keyboard shortcuts initialized", category: Logger.lifecycle)

        // Check permissions on launch (T055)
        let permissionManager = PermissionManager.shared
        let hasPermission = permissionManager.isPermissionGranted
        Logger.info("Accessibility permission check: \(hasPermission ? "Granted" : "Not granted")", category: Logger.permissions)

        if hasPermission {
            // Permission already granted - start grammar checking immediately
            Logger.info("Starting grammar checking - enabled: \(UserPreferences.shared.isEnabled)", category: Logger.lifecycle)

            // Log paused applications (excluding .active state)
            let pausedApps = UserPreferences.shared.appPauseDurations.filter { $0.value != .active }
            let pausedAppBundleIDs = pausedApps.keys.sorted()
            Logger.info("Paused applications (\(pausedApps.count)): \(pausedAppBundleIDs)", category: Logger.lifecycle)

            analysisCoordinator = AnalysisCoordinator.shared
            Logger.info("Analysis coordinator initialized", category: Logger.lifecycle)

            // Setup style checking model management
            setupStyleCheckingModelManagement()

            // Check if user wants to open settings window in foreground
            if UserPreferences.shared.openInForeground {
                Logger.info("Opening settings window in foreground (user preference)", category: Logger.ui)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.openSettingsWindow()
                }
            }
        } else {
            // No permission - show onboarding to request it (T056)
            Logger.warning("Accessibility permission not granted - showing onboarding", category: Logger.permissions)

            permissionManager.onPermissionGranted = { [weak self] in
                guard let self = self else { return }
                Logger.info("Permission granted via onboarding - starting grammar checking", category: Logger.permissions)
                self.analysisCoordinator = AnalysisCoordinator.shared
                Logger.info("Analysis coordinator initialized", category: Logger.lifecycle)

                // Setup style checking model management
                self.setupStyleCheckingModelManagement()

                // Return to accessory mode after onboarding completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.setActivationPolicy(.accessory)
                    Logger.info("Returned to menu bar only mode", category: Logger.lifecycle)
                }
            }

            // Open onboarding window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.openOnboardingWindow()
            }
        }
    }

    private func openOnboardingWindow() {
        Logger.info("Creating onboarding window", category: Logger.ui)

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

        Logger.info("Onboarding window displayed", category: Logger.ui)
    }

    // Prevent app from quitting when all windows close (menu bar app)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Setup style checking model management:
    /// - Initialize LLM engine (on background thread)
    /// - Auto-load model on launch if enabled
    /// - Reactively load/unload model when style checking is toggled
    private func setupStyleCheckingModelManagement() {
        let preferences = UserPreferences.shared
        let modelManager = ModelManager.shared

        // Setup the preference observer first (this is lightweight, can be on main thread)
        setupStyleCheckingObserver(preferences: preferences, modelManager: modelManager)

        // Run heavy initialization on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            self.initializeLLMEngineAndLoadModel(preferences: preferences, modelManager: modelManager)
        }

        Logger.info("Style checking model management setup initiated (async)", category: Logger.llm)
    }

    /// Initialize LLM engine and auto-load model (runs on background thread)
    private func initializeLLMEngineAndLoadModel(preferences: UserPreferences, modelManager: ModelManager) {
        // Initialize LLM engine with app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let textWardenDir = appSupport.appendingPathComponent("TextWarden", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: textWardenDir, withIntermediateDirectories: true)

        Logger.info("Initializing LLM engine on background thread...", category: Logger.llm)
        let initSuccess = LLMEngine.shared.initialize(appSupportDir: textWardenDir)
        if !initSuccess {
            Logger.error("LLM engine initialization failed - style checking will not work", category: Logger.llm)
            return
        }
        Logger.info("LLM engine initialized successfully", category: Logger.llm)

        // Log current state
        Logger.debug("Style checking preferences - enabled: \(preferences.enableStyleChecking), selectedModel: \(preferences.selectedModelId)", category: Logger.llm)

        // Refresh models on background thread
        DispatchQueue.main.sync {
            modelManager.refreshModels()
        }

        Logger.debug("Available models: \(modelManager.models.count), downloaded: \(modelManager.downloadedModels.count)", category: Logger.llm)

        // Auto-load model on launch if style checking is enabled
        guard preferences.enableStyleChecking else {
            Logger.debug("Style checking is disabled - skipping model auto-load", category: Logger.llm)
            return
        }

        let selectedModelId = preferences.selectedModelId
        Logger.debug("Style checking enabled, checking if model '\(selectedModelId)' is available...", category: Logger.llm)

        guard let model = modelManager.models.first(where: { $0.id == selectedModelId }) else {
            Logger.warning("Selected model '\(selectedModelId)' not found in available models", category: Logger.llm)
            return
        }

        Logger.debug("Found model: \(model.name), isDownloaded: \(model.isDownloaded)", category: Logger.llm)

        guard model.isDownloaded else {
            Logger.warning("Selected model '\(model.name)' is not downloaded - cannot auto-load", category: Logger.llm)
            return
        }

        Logger.info("Auto-loading AI model: \(model.name) (style checking enabled)", category: Logger.llm)

        // Load model - this is the heavy operation, keep it on background thread
        Task.detached(priority: .userInitiated) {
            await modelManager.loadModel(selectedModelId)
        }
    }

    /// Setup observer for style checking toggle (lightweight, runs on main thread)
    private func setupStyleCheckingObserver(preferences: UserPreferences, modelManager: ModelManager) {
        styleCheckingCancellable = preferences.$enableStyleChecking
            .dropFirst() // Skip initial value (we handle that in initializeLLMEngineAndLoadModel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard self != nil else { return }
                let selectedModelId = preferences.selectedModelId

                if enabled {
                    // Style checking enabled - load the selected model if downloaded
                    if let model = modelManager.models.first(where: { $0.id == selectedModelId }), model.isDownloaded {
                        Logger.info("Style checking enabled - loading model: \(model.name)", category: Logger.llm)
                        // Use Task.detached to avoid blocking main thread
                        Task.detached(priority: .userInitiated) {
                            await modelManager.loadModel(selectedModelId)
                        }
                    } else {
                        Logger.warning("Style checking enabled but selected model not downloaded", category: Logger.llm)
                    }
                } else {
                    // Style checking disabled - unload the model from memory
                    if modelManager.loadedModelId != nil {
                        Logger.info("Style checking disabled - unloading model from memory", category: Logger.llm)
                        // Unload on background thread
                        DispatchQueue.global(qos: .userInitiated).async {
                            modelManager.unloadModel()
                        }
                    }
                }
            }
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
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false  // CRITICAL: Keep window alive when closed
        window.setContentSize(NSSize(width: 850, height: 1000))
        window.minSize = NSSize(width: 750, height: 800)
        window.center()
        window.delegate = self
        window.level = .normal
        window.toolbar = NSToolbar()
        window.toolbar?.displayMode = .iconOnly

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

    // MARK: - Keyboard Shortcuts

    /// Setup global keyboard shortcuts using KeyboardShortcuts package
    private func setupKeyboardShortcuts() {
        let preferences = UserPreferences.shared

        // Toggle grammar checking (Cmd+Shift+G by default)
        KeyboardShortcuts.onKeyUp(for: .toggleGrammarChecking) {
            guard preferences.keyboardShortcutsEnabled else { return }

            Logger.debug("Keyboard shortcut: Toggle grammar checking", category: Logger.ui)

            // Toggle pause duration between active and indefinite
            if preferences.pauseDuration == .active {
                preferences.pauseDuration = .indefinite
                MenuBarController.shared?.setIconState(.inactive)
            } else {
                preferences.pauseDuration = .active
                MenuBarController.shared?.setIconState(.active)
            }
        }

        // Run style check on current text (Cmd+Shift+S by default)
        KeyboardShortcuts.onKeyUp(for: .runStyleCheck) {
            guard preferences.keyboardShortcutsEnabled else { return }

            Logger.debug("Keyboard shortcut: Run style check", category: Logger.ui)

            // Trigger manual style check via AnalysisCoordinator
            AnalysisCoordinator.shared.runManualStyleCheck()
        }

        // Accept current suggestion (Tab by default)
        KeyboardShortcuts.onKeyUp(for: .acceptSuggestion) {
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.isVisible else { return }
            guard let error = SuggestionPopover.shared.currentError else { return }
            guard let firstSuggestion = error.suggestions.first else { return }

            Logger.debug("Keyboard shortcut: Accept suggestion - \(firstSuggestion)", category: Logger.ui)

            SuggestionPopover.shared.applySuggestion(firstSuggestion)
        }

        // Dismiss suggestion popover (Escape by default)
        KeyboardShortcuts.onKeyUp(for: .dismissSuggestion) {
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.isVisible else { return }

            Logger.debug("Keyboard shortcut: Dismiss suggestion", category: Logger.ui)

            SuggestionPopover.shared.hide()
        }

        // Navigate to previous suggestion (Option + Left arrow by default)
        KeyboardShortcuts.onKeyUp(for: .previousSuggestion) {
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.isVisible else { return }

            Logger.debug("Keyboard shortcut: Previous suggestion", category: Logger.ui)

            SuggestionPopover.shared.previousError()
        }

        // Navigate to next suggestion (Option + Right arrow by default)
        KeyboardShortcuts.onKeyUp(for: .nextSuggestion) {
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.isVisible else { return }

            Logger.debug("Keyboard shortcut: Next suggestion", category: Logger.ui)

            SuggestionPopover.shared.nextError()
        }

        // Quick apply shortcuts (Option+1, Option+2, Option+3)
        KeyboardShortcuts.onKeyUp(for: .applySuggestion1) {
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.isVisible else { return }
            guard let error = SuggestionPopover.shared.currentError else { return }
            guard error.suggestions.count >= 1 else { return }

            let suggestion = error.suggestions[0]
            Logger.debug("Keyboard shortcut: Apply suggestion 1 - \(suggestion)", category: Logger.ui)

            SuggestionPopover.shared.applySuggestion(suggestion)
        }

        KeyboardShortcuts.onKeyUp(for: .applySuggestion2) {
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.isVisible else { return }
            guard let error = SuggestionPopover.shared.currentError else { return }
            guard error.suggestions.count >= 2 else { return }

            let suggestion = error.suggestions[1]
            Logger.debug("Keyboard shortcut: Apply suggestion 2 - \(suggestion)", category: Logger.ui)

            SuggestionPopover.shared.applySuggestion(suggestion)
        }

        KeyboardShortcuts.onKeyUp(for: .applySuggestion3) {
            guard preferences.keyboardShortcutsEnabled else { return }
            guard SuggestionPopover.shared.isVisible else { return }
            guard let error = SuggestionPopover.shared.currentError else { return }
            guard error.suggestions.count >= 3 else { return }

            let suggestion = error.suggestions[2]
            Logger.debug("Keyboard shortcut: Apply suggestion 3 - \(suggestion)", category: Logger.ui)

            SuggestionPopover.shared.applySuggestion(suggestion)
        }
    }
}
