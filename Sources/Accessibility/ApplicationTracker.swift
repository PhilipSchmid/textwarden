//
//  ApplicationTracker.swift
//  Gnau
//
//  Tracks active application changes using NSWorkspace
//

import Foundation
import AppKit
import Combine

/// Tracks the currently active application and notifies observers
class ApplicationTracker: ObservableObject {
    static let shared = ApplicationTracker()

    /// Currently active application context
    @Published private(set) var activeApplication: ApplicationContext?

    /// Callback for application changes
    var onApplicationChange: ((ApplicationContext) -> Void)?

    /// Workspace for monitoring application changes
    private let workspace = NSWorkspace.shared

    private init() {
        setupNotifications()
        updateActiveApplication()
    }

    /// Setup workspace notifications
    private func setupNotifications() {
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    /// Handle application activation
    @objc private func handleApplicationActivated(_ notification: Notification) {
        updateActiveApplication()
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

    /// Update active application from workspace
    func updateActiveApplication() {
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
        UserPreferences.shared.discoveredApplications.insert(bundleIdentifier)

        DispatchQueue.main.async {
            self.activeApplication = context
            self.onApplicationChange?(context)
        }
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
