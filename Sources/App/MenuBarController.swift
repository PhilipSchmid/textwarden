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
        let icon = initialState == .active ? TextWardenIcon.create() : TextWardenIcon.createPaused()
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
        if SafeTrialPromptController.shared.handleStatusItemClick(sender) {
            return
        }
        SafeTrialPromptController.shared.dismiss()

        // Performance profiling for menu bar display
        let (profilingState, profilingStartTime) = PerformanceProfiler.shared.beginInterval(.menuBarDisplay, context: "click")

        let totalStart = CFAbsoluteTimeGetCurrent()
        var stepStart = totalStart

        // Capture the frontmost app before our app potentially becomes active
        menuTargetApp = NSWorkspace.shared.frontmostApplication
        let frontmostAppTime = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000
        stepStart = CFAbsoluteTimeGetCurrent()

        // Rebuild menu with the captured app
        createMenu()
        let createMenuTime = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000
        stepStart = CFAbsoluteTimeGetCurrent()

        guard let menu else { return }
        let buttonBounds = sender.bounds

        // Log timing BEFORE popUp (which blocks until menu dismissed)
        let prepTime = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        Logger.info("MenuBar timing: frontmostApp=\(String(format: "%.1f", frontmostAppTime))ms, createMenu=\(String(format: "%.1f", createMenuTime))ms, totalPrep=\(String(format: "%.1f", prepTime))ms", category: Logger.performance)

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

    /// Present the unknown-application choice using the system popover attached to TextWarden.
    func showSafeTrialPrompt(for context: ApplicationContext) {
        guard let button = statusItem?.button else {
            Logger.warning("Cannot show safe-trial prompt: no status item button", category: Logger.ui)
            return
        }

        setIconState(.inactive)
        button.toolTip = "TextWarden is paused in \(context.applicationName) — click to choose"
        SafeTrialPromptController.shared.present(for: context, relativeTo: button)
    }

    private func createMenu() {
        menu = NSMenu()

        // Status header
        let headerItem = NSMenuItem(title: "TextWarden Grammar Checker", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu?.addItem(headerItem)
        menu?.addItem(NSMenuItem.separator())

        addRuntimeHealthMenuItems()

        addGlobalPauseMenuItems()
        menu?.addItem(NSMenuItem.separator())

        addAppSpecificPauseMenuItems()

        addUtilityMenuItems()

        // Menu is shown manually in statusBarButtonClicked, not attached to statusItem
    }

    /// Add a short, actionable answer to “is TextWarden working here?”
    private func addRuntimeHealthMenuItems() {
        let snapshot = RuntimeHealthStore.shared.snapshot
        let appName = snapshot.applicationName ?? menuTargetApp?.localizedName
        let prefix = appName.map { "\($0): " } ?? ""
        let statusItem = NSMenuItem(title: "\(prefix)\(snapshot.menuTitle)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu?.addItem(statusItem)

        if let lastSuccess = snapshot.lastSuccessfulCheck {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let text = formatter.localizedString(for: lastSuccess, relativeTo: Date())
            let successItem = NSMenuItem(title: "Last check \(text)", action: nil, keyEquivalent: "")
            successItem.isEnabled = false
            menu?.addItem(successItem)
        }

        if let action = snapshot.action {
            addRecoveryMenuItem(for: action, snapshot: snapshot)
        }
        menu?.addItem(NSMenuItem.separator())
    }

    private func addRecoveryMenuItem(for action: RecoveryAction, snapshot: RuntimeHealthSnapshot) {
        let item: NSMenuItem
        switch action {
        case .grantPermission:
            item = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        case .resume:
            let title: String = switch snapshot.resumeScope {
            case .application:
                snapshot.applicationName.map { "Resume in \($0)" } ?? "Resume Here"
            case .global, nil:
                "Resume TextWarden"
            }
            item = NSMenuItem(title: title, action: #selector(resumePause(_:)), keyEquivalent: "")
            item.representedObject = snapshot.resumeScope
        case .trySafely:
            let appName = snapshot.applicationName.map { " in \($0)" } ?? ""
            item = NSMenuItem(title: "Try TextWarden Safely\(appName)", action: #selector(trySafeTrial(_:)), keyEquivalent: "")
            item.representedObject = snapshot.bundleIdentifier
        case .retry:
            item = NSMenuItem(title: "Retry Now", action: #selector(retryCurrentCheck), keyEquivalent: "")
        case .resetIndicatorPosition:
            item = NSMenuItem(title: "Reset Indicator Position", action: #selector(openPreferences), keyEquivalent: "")
        case .enable, .openSettings, .reportCompatibility, .copyDiagnostics, .keepPaused:
            item = NSMenuItem(title: "Open Settings…", action: #selector(openPreferences), keyEquivalent: "")
        }
        item.target = self
        menu?.addItem(item)

        if action == .trySafely, let bundleID = snapshot.bundleIdentifier {
            let appName = snapshot.applicationName ?? "This App"
            let pauseItem = NSMenuItem(title: "Keep \(appName) Paused", action: #selector(keepSafeTrialPaused(_:)), keyEquivalent: "")
            pauseItem.target = self
            pauseItem.representedObject = bundleID
            menu?.addItem(pauseItem)
        }
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
              !AppRegistry.shared.isIntentionallyDisabled(bundleID)
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
        UserPreferences.shared.resume(.global)
    }

    @objc private func setPauseOneHour() {
        UserPreferences.shared.setPauseDuration(.oneHour, for: .global)
    }

    @objc private func setPauseTwentyFourHours() {
        UserPreferences.shared.setPauseDuration(.twentyFourHours, for: .global)
    }

    @objc private func setPauseIndefinite() {
        UserPreferences.shared.setPauseDuration(.indefinite, for: .global)
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
            title: "  Active",
            action: #selector(setAppPauseActive),
            keyEquivalent: ""
        )
        activeItem.target = self
        activeItem.representedObject = bundleID
        activeItem.state = currentPause == .active ? .on : .off
        menu?.addItem(activeItem)

        // Pause for 1 Hour option
        let oneHourItem = NSMenuItem(
            title: "  Paused for 1 Hour",
            action: #selector(setAppPauseOneHour),
            keyEquivalent: ""
        )
        oneHourItem.target = self
        oneHourItem.representedObject = bundleID
        oneHourItem.state = currentPause == .oneHour ? .on : .off
        menu?.addItem(oneHourItem)

        // Pause for 24 Hours option
        let twentyFourHoursItem = NSMenuItem(
            title: "  Paused for 24 Hours",
            action: #selector(setAppPauseTwentyFourHours),
            keyEquivalent: ""
        )
        twentyFourHoursItem.target = self
        twentyFourHoursItem.representedObject = bundleID
        twentyFourHoursItem.state = currentPause == .twentyFourHours ? .on : .off
        menu?.addItem(twentyFourHoursItem)

        // Pause Indefinitely option
        let indefiniteItem = NSMenuItem(
            title: "  Paused Until Resumed",
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
        UserPreferences.shared.resume(.application(bundleID))
    }

    @objc private func setAppPauseOneHour(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.setPauseDuration(.oneHour, for: .application(bundleID))
    }

    @objc private func setAppPauseTwentyFourHours(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.setPauseDuration(.twentyFourHours, for: .application(bundleID))
    }

    @objc private func setAppPauseIndefinite(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.setPauseDuration(.indefinite, for: .application(bundleID))
    }

    @objc private func resumePause(_ sender: NSMenuItem) {
        guard let scope = sender.representedObject as? PauseScope else {
            Logger.warning("Resume action has no pause scope", category: Logger.ui)
            return
        }
        UserPreferences.shared.resume(scope)
    }

    @objc private func trySafeTrial(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        AnalysisCoordinator.shared.startSafeTrial(for: bundleID)
    }

    @objc private func keepSafeTrialPaused(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.declineSafeTrial(for: bundleID)
        UserPreferences.shared.setPauseDuration(.indefinite, for: .application(bundleID))
        RuntimeHealthStore.shared.update(
            state: .inactive,
            reason: .appPause,
            context: ApplicationTracker.shared.activeApplication,
            action: .resume
        )
        updateMenu()
    }

    @objc private func retryCurrentCheck() {
        AnalysisCoordinator.shared.retryCurrentCheck()
        updateMenu()
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.shared.openSystemSettings()
    }

    /// Update menu to reflect current pause state
    func updateMenu() {
        refreshIconForActiveApplication()
        createMenu()
    }

    /// Keep the status icon tied to the current app instead of whichever app last changed it.
    private func refreshIconForActiveApplication() {
        guard let context = ApplicationTracker.shared.activeApplication else {
            setIconState(UserPreferences.shared.isEnabled ? .active : .inactive)
            return
        }

        let preferences = UserPreferences.shared
        let isAwaitingConsent = AppRegistry.shared.requiresSafeTrialConsent(for: context.bundleIdentifier)
            && !preferences.safeTrialApplications.contains(context.bundleIdentifier)
        let snapshot = RuntimeHealthStore.shared.snapshot
        let matchingInactiveReason = snapshot.bundleIdentifier == context.bundleIdentifier
            && snapshot.state == .inactive ? snapshot.reason : nil

        setIconState(Self.iconState(
            isEnabledForActiveApplication: context.shouldCheck(),
            isAwaitingConsent: isAwaitingConsent,
            matchingInactiveReason: matchingInactiveReason
        ))
    }

    static func iconState(
        isEnabledForActiveApplication: Bool,
        isAwaitingConsent: Bool,
        matchingInactiveReason: InactiveReason?
    ) -> IconState {
        guard isEnabledForActiveApplication, !isAwaitingConsent else {
            return .inactive
        }

        switch matchingInactiveReason {
        case .permission, .siteDisabled, .consentRequired:
            return .inactive
        case .globalPause, .appPause, .secureField, .unsupportedField, .unsupportedApplication,
             .noEditableField, nil:
            return .active
        }
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

        // Keep the feather recognizable and add a compact pause badge when inactive.
        let icon: NSImage = switch state {
        case .inactive:
            TextWardenIcon.createPaused()
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
