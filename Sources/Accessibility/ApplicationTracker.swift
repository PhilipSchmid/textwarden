//
//  ApplicationTracker.swift
//  TextWarden
//
//  Tracks active application changes using NSWorkspace
//

import Foundation
import AppKit
import Combine

/// Tracks the currently active application and notifies observers
@MainActor
class ApplicationTracker: ObservableObject {
    static let shared = ApplicationTracker()

    /// Currently active application context
    @Published private(set) var activeApplication: ApplicationContext?

    /// Previous active application (for menu bar display)
    @Published private(set) var previousApplication: ApplicationContext?

    /// Callback for application changes
    var onApplicationChange: ((ApplicationContext) -> Void)?

    /// Workspace for monitoring application changes
    private let workspace = NSWorkspace.shared

    /// Polling timer for fast app switching detection
    /// Menu bar apps (NSUIElement) don't receive timely NSWorkspace notifications,
    /// so we poll every 250ms for instant detection.
    /// Using DispatchSourceTimer instead of Timer because it's GCD-based and doesn't rely on run loops
    private var pollingTimer: DispatchSourceTimer?

    private init() {
        setupNotifications()
        // Use synchronous update during init to ensure activeApplication is set
        // before AnalysisCoordinator initializes and checks for it
        updateActiveApplicationSync()
        // Start polling for instant app switch detection
        startPolling()
    }

    /// Setup workspace notifications for app termination
    /// Note: We no longer use didActivateApplicationNotification because it's delayed by 30+ seconds
    /// for LSUIElement apps. Instead, we use polling (startPolling) for instant app switch detection.
    private func setupNotifications() {
        // Only listen for app termination to clean up state
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    /// Start polling for frontmost application changes
    /// Poll every 250ms for instant detection using GCD-based DispatchSourceTimer
    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.checkForApplicationChange()
        }
        timer.resume()

        pollingTimer = timer

        Logger.debug("ApplicationTracker: Polling started (250ms interval)", category: Logger.accessibility)
    }

    /// Check if frontmost application has changed
    private func checkForApplicationChange() {
        guard let app = workspace.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier else {
            return
        }

        // Only trigger callback if app actually changed
        if activeApplication?.bundleIdentifier != bundleIdentifier {
            Logger.debug("ApplicationTracker: App switch detected: \(activeApplication?.bundleIdentifier ?? "nil") → \(bundleIdentifier)", category: Logger.accessibility)
            updateActiveApplicationSync()
        }
    }

    /// Handle application termination
    @objc private func handleApplicationTerminated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        // If the terminated app is the one we're tracking, clear it
        if app.processIdentifier == activeApplication?.processID {
            activeApplication = nil
        }
    }

    /// Updates the active application from the workspace synchronously.
    /// Queries NSWorkspace for the frontmost application and updates state immediately.
    /// Triggers the `onApplicationChange` callback if the application has changed.
    /// - Note: Must be called on the main thread to ensure thread safety with @Published properties
    func updateActiveApplicationSync() {
        guard let app = workspace.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier else {
            return
        }

        let applicationName = app.localizedName ?? bundleIdentifier
        let processID = app.processIdentifier

        let context = ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: applicationName
        )

        // Record this app as discovered
        let isNewApp = !UserPreferences.shared.discoveredApplications.contains(bundleIdentifier)
        UserPreferences.shared.discoveredApplications.insert(bundleIdentifier)

        // Pause unsupported apps by default on first discovery
        if isNewApp && !AppRegistry.shared.hasConfiguration(for: bundleIdentifier) {
            // Only set pause if user hasn't already configured this app
            if UserPreferences.shared.getPauseDuration(for: bundleIdentifier) == .active {
                UserPreferences.shared.setPauseDuration(for: bundleIdentifier, duration: .indefinite)
                Logger.info("Auto-paused unsupported app: \(bundleIdentifier)", category: Logger.general)
            }
        }

        // Track previous app before updating current
        if let current = self.activeApplication, current.bundleIdentifier != bundleIdentifier {
            self.previousApplication = current
        }

        self.activeApplication = context

        // Trigger callback for app change
        self.onApplicationChange?(context)
    }

    /// Gets the most relevant application to display in the menu bar.
    /// Prioritizes showing the current active app unless it's TextWarden itself, in which case it shows the previous app.
    /// This prevents the menu from showing "TextWarden" when the user opens the menu bar.
    /// - Returns: The application context to display, or `nil` if no suitable app is available
    func getMenuDisplayApp() -> ApplicationContext? {
        // If current app is not TextWarden, use it
        if let current = activeApplication, current.bundleIdentifier != "io.textwarden.TextWarden" {
            return current
        }

        // Otherwise, use previous app (the one before TextWarden became active)
        if let previous = previousApplication, previous.bundleIdentifier != "io.textwarden.TextWarden" {
            return previous
        }

        return nil
    }

    /// Get context for a specific application
    func context(for bundleIdentifier: String) -> ApplicationContext? {
        let runningApps = workspace.runningApplications

        guard let app = runningApps.first(where: { $0.bundleIdentifier == bundleIdentifier }),
              let bundle = app.bundleIdentifier else {
            return nil
        }

        let applicationName = app.localizedName ?? bundle
        let processID = app.processIdentifier

        return ApplicationContext(
            bundleIdentifier: bundle,
            processID: processID,
            applicationName: applicationName
        )
    }

    /// Check if application is running
    func isApplicationRunning(_ bundleIdentifier: String) -> Bool {
        workspace.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    deinit {
        pollingTimer?.cancel()
        workspace.notificationCenter.removeObserver(self)
    }
}

// MARK: - Well-known Applications

extension ApplicationTracker {
    /// Check if current app is a text editor
    var isTextEditor: Bool {
        guard let bundleID = activeApplication?.bundleIdentifier else { return false }

        let textEditors = [
            "com.apple.TextEdit",
            "com.apple.Pages",
            "com.microsoft.Word",
            "com.microsoft.VSCode",
            "com.sublimetext.4",
            "com.apple.dt.Xcode",
            "com.github.atom",
            "com.jetbrains.intellij",
            "md.obsidian",
            "notion.id"
        ]

        return textEditors.contains(bundleID)
    }

    /// Check if current app is a browser
    var isBrowser: Bool {
        guard let bundleID = activeApplication?.bundleIdentifier else { return false }

        let browsers = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser"
        ]

        return browsers.contains(bundleID)
    }
}
