//
//  MenuBarController.swift
//  Gnau
//
//  Manages the NSStatusItem and menu bar icon for Gnau
//

import Cocoa
import SwiftUI

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

        // Update menu when active application changes
        ApplicationTracker.shared.onApplicationChange = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMenu()
            }
        }
    }

    deinit {
        // Intentionally empty - reserved for future cleanup if needed
    }

    private func setupMenuBar() {
        // Create status item with variable length
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            print("Failed to create status item button")
            return
        }

        // Set menu bar icon - using custom Gnau icon
        let icon = GnauIcon.create()
        button.image = icon
        button.toolTip = "Gnau Grammar Checker"

        // IMPORTANT: Do NOT set statusItem.menu here, as it prevents button.action from firing
        // Instead, we handle the click manually and show the menu programmatically

        // Set button action and configure to send action on left mouse up
        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp])

        // Create menu (but don't attach it to statusItem)
        createMenu()
    }

    /// Called when the status bar button is clicked
    /// Captures the frontmost app BEFORE the menu opens
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        // Capture the frontmost app before our app potentially becomes active
        menuTargetApp = NSWorkspace.shared.frontmostApplication

        // Rebuild menu with the captured app
        createMenu()

        // Show the menu at the button's location
        guard let menu = menu else { return }
        let buttonBounds = sender.bounds
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttonBounds.height), in: sender)
    }



    private func createMenu() {
        menu = NSMenu()

        // Status header
        let headerItem = NSMenuItem(title: "Gnau Grammar Checker", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu?.addItem(headerItem)
        menu?.addItem(NSMenuItem.separator())

        // Add menu sections
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

        // Show resume time if paused temporarily
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
              bundleID != "app.gnau.Gnau" else {
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
        // Show errors if any exist (useful for terminals and apps without visual underlines)
        let errorCount = AnalysisCoordinator.shared.getCurrentErrors().count
        if errorCount > 0 {
            let errorItem = NSMenuItem(
                title: "Show \(errorCount) Grammar \(errorCount == 1 ? "Issue" : "Issues")...",
                action: #selector(showCurrentErrors),
                keyEquivalent: ""
            )
            errorItem.target = self
            menu?.addItem(errorItem)
            menu?.addItem(NSMenuItem.separator())
        }

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
            title: "About Gnau",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu?.addItem(aboutItem)

        menu?.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Gnau",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)
    }

    @objc private func setPauseActive() {
        UserPreferences.shared.pauseDuration = .active
        updateMenu()
    }

    @objc private func setPauseOneHour() {
        UserPreferences.shared.pauseDuration = .oneHour
        updateMenu()
    }

    @objc private func setPauseTwentyFourHours() {
        UserPreferences.shared.pauseDuration = .twentyFourHours
        updateMenu()
    }

    @objc private func setPauseIndefinite() {
        UserPreferences.shared.pauseDuration = .indefinite
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

        // Get current pause state for this app
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

        // Show resume time if paused temporarily
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
        NSLog("🔵 MenuBarController: openPreferences() called - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

        // Set tab to General (0)
        PreferencesWindowController.shared.selectTab(0)

        NSLog("🔵 MenuBarController: Switching to .regular mode")

        // Switch to regular mode temporarily
        NSApp.setActivationPolicy(.regular)

        NSLog("🔵 MenuBarController: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

        // Use NSApp.sendAction to open settings - let AppKit find the target
        NSApp.sendAction(#selector(AppDelegate.openSettingsWindow(selectedTab:)), to: nil, from: self)

        NSLog("🔵 MenuBarController: Sent openSettingsWindow action for General tab")
    }

    @objc private func showAbout() {
        NSLog("🔵 MenuBarController: showAbout() called - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

        // Set tab to About (8)
        PreferencesWindowController.shared.selectTab(8)

        NSLog("🔵 MenuBarController: Switching to .regular mode")

        // Switch to regular mode temporarily
        NSApp.setActivationPolicy(.regular)

        NSLog("🔵 MenuBarController: AFTER setActivationPolicy(.regular) - ActivationPolicy: \(NSApp.activationPolicy().rawValue)")

        // Use NSApp.sendAction to open settings with About tab (index 8)
        NSApp.sendAction(#selector(AppDelegate.openSettingsWindow(selectedTab:)), to: nil, from: self)

        NSLog("🔵 MenuBarController: Sent openSettingsWindow action for About tab (8)")
    }

    @objc private func showCurrentErrors() {
        // Get current errors from AnalysisCoordinator
        let errors = AnalysisCoordinator.shared.getCurrentErrors()
        guard let firstError = errors.first else { return }

        // Show popover with the first error (user can navigate to others)
        // Position near menu bar icon since we don't have text field position
        if let button = statusItem?.button {
            let buttonFrame = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
            let position = NSPoint(x: buttonFrame.midX, y: buttonFrame.minY)

            SuggestionPopover.shared.show(
                error: firstError,
                allErrors: errors,
                at: position
            )
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Update menu bar icon state (e.g., to show error/disabled state)
    func setIconState(_ state: IconState) {
        guard let button = statusItem?.button else { return }

        previousIconState = state

        let symbolName: String
        switch state {
        case .active:
            symbolName = "text.badge.checkmark"
        case .inactive:
            symbolName = "text.badge.xmark"
        case .error:
            symbolName = "exclamationmark.triangle"
        case .restarting:
            symbolName = "arrow.triangle.2.circlepath"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Gnau - \(state)") {
            image.isTemplate = true
            button.image = image
        }
    }

    /// Show restart indicator briefly (T112)
    func showRestartIndicator() {
        Logger.info("Showing restart indicator", category: Logger.ui)
        setIconState(.restarting)
    }

    /// Hide restart indicator and restore previous state (T112)
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
