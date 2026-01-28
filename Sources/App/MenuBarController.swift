//
//  MenuBarController.swift
//  TextWarden
//
//  Manages the NSStatusItem and menu bar icon for TextWarden
//

import Cocoa
import SwiftUI

@MainActor
class MenuBarController: NSObject, NSMenuDelegate {
    static var shared: MenuBarController?

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var previousIconState: IconState = .active

    /// The app to show in the menu - captured when button is clicked (BEFORE menu opens)
    private var menuTargetApp: NSRunningApplication?

    /// Window controller for milestone celebration cards
    private var milestoneCardController: MilestoneCardWindowController?

    /// Window controller for menu bar tooltip (shown once after onboarding)
    private var menuBarTooltipController: MenuBarTooltipWindowController?

    override init() {
        super.init()
        MenuBarController.shared = self

        // Initialize ApplicationTracker early to start tracking active app
        _ = ApplicationTracker.shared

        setupMenuBar()

        // NOTE: onApplicationChange callback is set by AnalysisCoordinator, which calls updateMenu()
        // This prevents the callback from being overwritten and ensures both monitoring and menu updates happen
    }

    deinit {
        // Intentionally empty - reserved for future cleanup if needed
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            Logger.error("Failed to create status item button", category: Logger.ui)
            return
        }

        // Set initial icon state based on whether grammar checking is enabled
        let initialState: IconState = UserPreferences.shared.isEnabled ? .active : .inactive
        let icon = initialState == .active ? TextWardenIcon.create() : TextWardenIcon.createDisabled()
        button.image = icon
        button.toolTip = initialState == .active ? "TextWarden Grammar Checker" : "TextWarden (Paused)"

        // IMPORTANT: Do NOT set statusItem.menu here, as it prevents button.action from firing
        // Instead, we handle the click manually and show the menu programmatically

        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp])

        createMenu()
    }

    /// Called when the status bar button is clicked
    /// Captures the frontmost app BEFORE the menu opens
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        // Performance profiling for menu bar display
        let (profilingState, profilingStartTime) = PerformanceProfiler.shared.beginInterval(.menuBarDisplay, context: "click")

        let totalStart = CFAbsoluteTimeGetCurrent()
        var stepStart = totalStart

        // Capture the frontmost app before our app potentially becomes active
        menuTargetApp = NSWorkspace.shared.frontmostApplication
        let frontmostAppTime = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000
        stepStart = CFAbsoluteTimeGetCurrent()

        // Check for pending milestones first (only if onboarding is complete)
        if UserPreferences.shared.hasCompletedOnboarding,
           let milestone = MilestoneManager.shared.checkForMilestones()
        {
            let milestoneCheckTime = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000
            Logger.info("MenuBar timing: frontmostApp=\(String(format: "%.1f", frontmostAppTime))ms, milestoneCheck=\(String(format: "%.1f", milestoneCheckTime))ms (showing milestone)", category: Logger.performance)
            // Mark as shown immediately so it won't show again on next click
            MilestoneManager.shared.markMilestoneShown(milestone)
            showMilestoneCard(milestone, from: sender)
            return
        }
        let milestoneCheckTime = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000
        stepStart = CFAbsoluteTimeGetCurrent()

        // Rebuild menu with the captured app
        createMenu()
        let createMenuTime = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000
        stepStart = CFAbsoluteTimeGetCurrent()

        guard let menu else { return }
        let buttonBounds = sender.bounds

        // Log timing BEFORE popUp (which blocks until menu dismissed)
        let prepTime = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        Logger.info("MenuBar timing: frontmostApp=\(String(format: "%.1f", frontmostAppTime))ms, milestoneCheck=\(String(format: "%.1f", milestoneCheckTime))ms, createMenu=\(String(format: "%.1f", createMenuTime))ms, totalPrep=\(String(format: "%.1f", prepTime))ms", category: Logger.performance)

        // End profiling BEFORE popUp - don't measure how long user has menu open
        PerformanceProfiler.shared.endInterval(.menuBarDisplay, state: profilingState, startTime: profilingStartTime)

        // This call blocks until user dismisses menu - don't include in timing
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttonBounds.height), in: sender)
    }

    /// Show a milestone celebration card near the menu bar button
    private func showMilestoneCard(_ milestone: Milestone, from button: NSStatusBarButton, isPreview: Bool = false) {
        guard let window = button.window else { return }

        // Get the button's frame in screen coordinates
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)

        // Create controller if needed
        if milestoneCardController == nil {
            milestoneCardController = MilestoneCardWindowController()
        }

        milestoneCardController?.showMilestoneCard(milestone, near: buttonFrameOnScreen, isPreview: isPreview)
        Logger.info("Showing milestone card: \(milestone.id) (preview: \(isPreview))", category: Logger.ui)
    }

    /// Show a preview milestone card for troubleshooting purposes
    /// This shows a sample milestone regardless of actual user statistics
    func showMilestonePreview() {
        guard let button = statusItem?.button else {
            Logger.warning("Cannot show milestone preview: no status item button", category: Logger.ui)
            return
        }

        let previewMilestone = MilestoneManager.shared.createPreviewMilestone()
        showMilestoneCard(previewMilestone, from: button, isPreview: true)
    }

    /// Show a specific milestone card (e.g., on app startup for overdue milestones)
    func showMilestone(_ milestone: Milestone) {
        guard let button = statusItem?.button else {
            Logger.warning("Cannot show milestone: no status item button", category: Logger.ui)
            return
        }

        showMilestoneCard(milestone, from: button, isPreview: false)
    }

    /// Show the menu bar tooltip after onboarding completes
    /// This tooltip is shown only once to help users find the menu bar icon
    func showMenuBarTooltip() {
        guard let button = statusItem?.button else {
            Logger.warning("Cannot show menu bar tooltip: no status item button", category: Logger.ui)
            return
        }

        guard let window = button.window else {
            Logger.warning("Cannot show menu bar tooltip: no window for button", category: Logger.ui)
            return
        }

        // Get the button's frame in screen coordinates
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)

        // Create controller if needed
        if menuBarTooltipController == nil {
            menuBarTooltipController = MenuBarTooltipWindowController()
        }

        menuBarTooltipController?.showTooltip(near: buttonFrameOnScreen)
    }

    private func createMenu() {
        menu = NSMenu()

        // Status header
        let headerItem = NSMenuItem(title: "TextWarden Grammar Checker", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu?.addItem(headerItem)
        menu?.addItem(NSMenuItem.separator())

        addGlobalPauseMenuItems()
        menu?.addItem(NSMenuItem.separator())

        addAppSpecificPauseMenuItems()

        addUtilityMenuItems()

        // Menu is shown manually in statusBarButtonClicked, not attached to statusItem
    }

    /// Add global pause menu items
    private func addGlobalPauseMenuItems() {
        // Grammar Checking Status
        let statusLabel = NSMenuItem(title: "Grammar Checking:", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu?.addItem(statusLabel)

        // Active option
        let activeItem = NSMenuItem(
            title: "  Active",
            action: #selector(setPauseActive),
            keyEquivalent: ""
        )
        activeItem.target = self
        activeItem.state = UserPreferences.shared.pauseDuration == .active ? .on : .off
        menu?.addItem(activeItem)

        // Pause for 1 Hour option
        let oneHourItem = NSMenuItem(
            title: "  Paused for 1 Hour",
            action: #selector(setPauseOneHour),
            keyEquivalent: ""
        )
        oneHourItem.target = self
        oneHourItem.state = UserPreferences.shared.pauseDuration == .oneHour ? .on : .off
        menu?.addItem(oneHourItem)

        // Pause for 24 Hours option
        let twentyFourHoursItem = NSMenuItem(
            title: "  Paused for 24 Hours",
            action: #selector(setPauseTwentyFourHours),
            keyEquivalent: ""
        )
        twentyFourHoursItem.target = self
        twentyFourHoursItem.state = UserPreferences.shared.pauseDuration == .twentyFourHours ? .on : .off
        menu?.addItem(twentyFourHoursItem)

        // Pause Indefinitely option
        let indefiniteItem = NSMenuItem(
            title: "  Paused Until Resumed",
            action: #selector(setPauseIndefinite),
            keyEquivalent: ""
        )
        indefiniteItem.target = self
        indefiniteItem.state = UserPreferences.shared.pauseDuration == .indefinite ? .on : .off
        menu?.addItem(indefiniteItem)

        if UserPreferences.shared.pauseDuration == .oneHour || UserPreferences.shared.pauseDuration == .twentyFourHours,
           let until = UserPreferences.shared.pausedUntil
        {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeString = formatter.string(from: until)
            let resumeItem = NSMenuItem(title: "    Will resume at \(timeString)", action: nil, keyEquivalent: "")
            resumeItem.isEnabled = false
            menu?.addItem(resumeItem)
        }
    }

    /// Add app-specific pause menu items if applicable
    private func addAppSpecificPauseMenuItems() {
        // Use the app captured when the button was clicked
        // This was captured BEFORE the menu opened, so it's the app the user was in
        guard let targetApp = menuTargetApp,
              let bundleID = targetApp.bundleIdentifier,
              bundleID != "io.textwarden.TextWarden"
        else {
            return
        }

        let appName = targetApp.localizedName ?? bundleID
        let context = ApplicationContext(
            bundleIdentifier: bundleID,
            processID: targetApp.processIdentifier,
            applicationName: appName
        )

        addAppSpecificPauseMenu(for: context)
        menu?.addItem(NSMenuItem.separator())
    }

    /// Add utility menu items (Sketch Pad, Preferences, Quit)
    private func addUtilityMenuItems() {
        // Sketch Pad
        let sketchPadItem = NSMenuItem(
            title: "Open Sketch Pad",
            action: #selector(openSketchPad),
            keyEquivalent: "n"
        )
        sketchPadItem.keyEquivalentModifierMask = [.option, .control]
        sketchPadItem.target = self
        menu?.addItem(sketchPadItem)

        menu?.addItem(NSMenuItem.separator())

        // Preferences
        let preferencesItem = NSMenuItem(
            title: "Preferences",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu?.addItem(preferencesItem)

        menu?.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit TextWarden",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)
    }

    @objc private func openSketchPad() {
        Logger.debug("Opening Sketch Pad from menu", category: Logger.ui)
        SketchPadWindowController.shared.showWindow()
    }

    @objc private func setPauseActive() {
        UserPreferences.shared.pauseDuration = .active
        setIconState(.active)
        updateMenu()
    }

    @objc private func setPauseOneHour() {
        UserPreferences.shared.pauseDuration = .oneHour
        setIconState(.inactive)
        updateMenu()
    }

    @objc private func setPauseTwentyFourHours() {
        UserPreferences.shared.pauseDuration = .twentyFourHours
        setIconState(.inactive)
        updateMenu()
    }

    @objc private func setPauseIndefinite() {
        UserPreferences.shared.pauseDuration = .indefinite
        setIconState(.inactive)
        updateMenu()
    }

    // MARK: - App-Specific Pause

    /// Add app-specific pause menu items for the given application
    private func addAppSpecificPauseMenu(for app: ApplicationContext) {
        let bundleID = app.bundleIdentifier
        let appName = app.applicationName

        // App label
        let appLabel = NSMenuItem(title: "\(appName):", action: nil, keyEquivalent: "")
        appLabel.isEnabled = false
        menu?.addItem(appLabel)

        let currentPause = UserPreferences.shared.getPauseDuration(for: bundleID)

        // Active option
        let activeItem = NSMenuItem(
            title: "  Active for \(appName)",
            action: #selector(setAppPauseActive),
            keyEquivalent: ""
        )
        activeItem.target = self
        activeItem.representedObject = bundleID
        activeItem.state = currentPause == .active ? .on : .off
        menu?.addItem(activeItem)

        // Pause for 1 Hour option
        let oneHourItem = NSMenuItem(
            title: "  Paused for 1 Hour for \(appName)",
            action: #selector(setAppPauseOneHour),
            keyEquivalent: ""
        )
        oneHourItem.target = self
        oneHourItem.representedObject = bundleID
        oneHourItem.state = currentPause == .oneHour ? .on : .off
        menu?.addItem(oneHourItem)

        // Pause for 24 Hours option
        let twentyFourHoursItem = NSMenuItem(
            title: "  Paused for 24 Hours for \(appName)",
            action: #selector(setAppPauseTwentyFourHours),
            keyEquivalent: ""
        )
        twentyFourHoursItem.target = self
        twentyFourHoursItem.representedObject = bundleID
        twentyFourHoursItem.state = currentPause == .twentyFourHours ? .on : .off
        menu?.addItem(twentyFourHoursItem)

        // Pause Indefinitely option
        let indefiniteItem = NSMenuItem(
            title: "  Paused Until Resumed for \(appName)",
            action: #selector(setAppPauseIndefinite),
            keyEquivalent: ""
        )
        indefiniteItem.target = self
        indefiniteItem.representedObject = bundleID
        indefiniteItem.state = currentPause == .indefinite ? .on : .off
        menu?.addItem(indefiniteItem)

        if currentPause == .oneHour || currentPause == .twentyFourHours,
           let until = UserPreferences.shared.getPausedUntil(for: bundleID)
        {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeString = formatter.string(from: until)
            let resumeItem = NSMenuItem(title: "    Will resume at \(timeString)", action: nil, keyEquivalent: "")
            resumeItem.isEnabled = false
            menu?.addItem(resumeItem)
        }
    }

    @objc private func setAppPauseActive(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.setPauseDuration(for: bundleID, duration: .active)
    }

    @objc private func setAppPauseOneHour(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.setPauseDuration(for: bundleID, duration: .oneHour)
    }

    @objc private func setAppPauseTwentyFourHours(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.setPauseDuration(for: bundleID, duration: .twentyFourHours)
    }

    @objc private func setAppPauseIndefinite(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.setPauseDuration(for: bundleID, duration: .indefinite)
    }

    /// Update menu to reflect current pause state
    func updateMenu() {
        createMenu()
    }

    @objc private func openPreferences() {
        Logger.debug("openPreferences() called - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

        PreferencesWindowController.shared.selectTab(0)

        Logger.debug("Switching to .regular mode", category: Logger.ui)

        // Switch to regular mode temporarily
        NSApp.setActivationPolicy(.regular)

        Logger.debug("setActivationPolicy(.regular) completed - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

        // Use NSApp.sendAction to open settings - let AppKit find the target
        NSApp.sendAction(#selector(AppDelegate.openSettingsWindow(selectedTab:)), to: nil, from: self)

        Logger.debug("Sent openSettingsWindow action for General tab", category: Logger.ui)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Update menu bar icon state (e.g., to show error/disabled state)
    func setIconState(_ state: IconState) {
        guard let button = statusItem?.button else { return }

        previousIconState = state

        // Use disabled icon with strikethrough when paused, normal icon otherwise
        let icon: NSImage = switch state {
        case .inactive:
            TextWardenIcon.createDisabled()
        case .active, .error, .restarting:
            TextWardenIcon.create()
        }
        button.image = icon

        switch state {
        case .active:
            button.toolTip = "TextWarden Grammar Checker"
        case .inactive:
            button.toolTip = "TextWarden (Paused)"
        case .error:
            button.toolTip = "TextWarden (Error)"
        case .restarting:
            button.toolTip = "TextWarden (Restarting...)"
        }
    }

    /// Show restart indicator briefly
    func showRestartIndicator() {
        Logger.info("Showing restart indicator", category: Logger.ui)
        setIconState(.restarting)
    }

    /// Hide restart indicator and restore previous state
    func hideRestartIndicator() {
        Logger.info("Hiding restart indicator", category: Logger.ui)
        setIconState(previousIconState)
    }

    enum IconState: String {
        case active
        case inactive
        case error
        case restarting
    }
}
