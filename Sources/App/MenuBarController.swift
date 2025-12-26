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
        // Capture the frontmost app before our app potentially becomes active
        menuTargetApp = NSWorkspace.shared.frontmostApplication

        // Rebuild menu with the captured app
        createMenu()

        guard let menu = menu else { return }
        let buttonBounds = sender.bounds
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttonBounds.height), in: sender)
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

        if (UserPreferences.shared.pauseDuration == .oneHour || UserPreferences.shared.pauseDuration == .twentyFourHours),
           let until = UserPreferences.shared.pausedUntil {
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
              bundleID != "io.textwarden.TextWarden" else {
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

    /// Add utility menu items (Preferences, About, Quit)
    private func addUtilityMenuItems() {
        // Preferences
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu?.addItem(preferencesItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About TextWarden",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu?.addItem(aboutItem)

        // Check for Updates
        let updateItem = NSMenuItem(
            title: "Check for Updates",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu?.addItem(updateItem)

        // Help
        let helpItem = NSMenuItem(
            title: "TextWarden Help",
            action: #selector(showHelp),
            keyEquivalent: "?"
        )
        helpItem.target = self
        menu?.addItem(helpItem)

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

        if (currentPause == .oneHour || currentPause == .twentyFourHours),
           let until = UserPreferences.shared.getPausedUntil(for: bundleID) {
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

    @objc private func showAbout() {
        Logger.debug("showAbout() called - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

        // Use type-safe enum to ensure correct tab is selected even if tabs are reordered
        PreferencesWindowController.shared.selectTab(.about)

        Logger.debug("Switching to .regular mode", category: Logger.ui)

        // Switch to regular mode temporarily
        NSApp.setActivationPolicy(.regular)

        Logger.debug("setActivationPolicy(.regular) completed - ActivationPolicy: \(NSApp.activationPolicy().rawValue)", category: Logger.ui)

        // Use NSApp.sendAction to open settings with About tab
        NSApp.sendAction(#selector(AppDelegate.openSettingsWindow(selectedTab:)), to: nil, from: self)

        Logger.debug("Sent openSettingsWindow action for About tab", category: Logger.ui)
    }

    @objc private func showHelp() {
        Logger.debug("showHelp() called", category: Logger.ui)
        NSApp.showHelp(nil)
    }

    @objc private func checkForUpdates() {
        Logger.debug("checkForUpdates() called", category: Logger.ui)

        // Get the AppDelegate to access the updater
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        // Trigger update check and show About tab
        Task { @MainActor in
            appDelegate.updaterViewModel.checkForUpdates()
        }

        // Also show the About page
        showAbout()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Update menu bar icon state (e.g., to show error/disabled state)
    func setIconState(_ state: IconState) {
        guard let button = statusItem?.button else { return }

        previousIconState = state

        // Use disabled icon with strikethrough when paused, normal icon otherwise
        let icon: NSImage
        switch state {
        case .inactive:
            icon = TextWardenIcon.createDisabled()
        case .active, .error, .restarting:
            icon = TextWardenIcon.create()
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
