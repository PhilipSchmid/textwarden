//
//  MenuBarController.swift
//  Gnau
//
//  Manages the NSStatusItem and menu bar icon for Gnau
//

import Cocoa
import SwiftUI

class MenuBarController: NSObject {
    static var shared: MenuBarController?

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var previousIconState: IconState = .active

    override init() {
        super.init()
        MenuBarController.shared = self
        setupMenuBar()
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

        // Create menu
        createMenu()
    }

    private func createMenu() {
        menu = NSMenu()

        // Status header
        let headerItem = NSMenuItem(title: "Gnau Grammar Checker", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu?.addItem(headerItem)

        menu?.addItem(NSMenuItem.separator())

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

        // Pause Indefinitely option
        let indefiniteItem = NSMenuItem(
            title: "  Paused Until Resumed",
            action: #selector(setPauseIndefinite),
            keyEquivalent: ""
        )
        indefiniteItem.target = self
        indefiniteItem.state = UserPreferences.shared.pauseDuration == .indefinite ? .on : .off
        menu?.addItem(indefiniteItem)

        // Show resume time if paused for 1 hour
        if UserPreferences.shared.pauseDuration == .oneHour,
           let until = UserPreferences.shared.pausedUntil {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeString = formatter.string(from: until)
            let resumeItem = NSMenuItem(title: "    Will resume at \(timeString)", action: nil, keyEquivalent: "")
            resumeItem.isEnabled = false
            menu?.addItem(resumeItem)
        }

        menu?.addItem(NSMenuItem.separator())

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

        self.statusItem?.menu = menu
    }

    @objc private func setPauseActive() {
        UserPreferences.shared.pauseDuration = .active
        updateMenu()
    }

    @objc private func setPauseOneHour() {
        UserPreferences.shared.pauseDuration = .oneHour
        updateMenu()
    }

    @objc private func setPauseIndefinite() {
        UserPreferences.shared.pauseDuration = .indefinite
        updateMenu()
    }

    /// Update menu to reflect current pause state
    func updateMenu() {
        createMenu()
    }

    @objc private func openPreferences() {
        // Activate app to ensure Settings window appears
        // This is intentional when user explicitly clicks "Preferences..."
        NSApp.activate(ignoringOtherApps: true)

        // Open Settings window
        // The Settings scene is defined in GnauApp.swift and SwiftUI handles window management
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector("showPreferencesWindow:"), to: nil, from: nil)
        }
    }

    @objc private func showAbout() {
        // Open preferences window with About tab instead of separate about panel
        // Set the selected tab to About first
        UserDefaults.standard.set(8, forKey: "PreferencesSelectedTab") // 8 = About tab index

        // Then open preferences
        openPreferences()
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
