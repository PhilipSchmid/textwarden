//
//  PositionRefreshCoordinator.swift
//  TextWarden
//
//  Handles app-specific position refresh triggers.
//  Some apps (like Slack) have AX trees that update asynchronously after user interactions,
//  requiring position recalculation after clicks or other events.
//
//  Also monitors formatting changes that affect text layout without changing content:
//  - Keyboard shortcuts (Cmd+B, Cmd+I, Cmd+U)
//  - Toolbar button clicks (Bold, Italic, Underline buttons)
//

import AppKit

/// Protocol for receiving position refresh notifications
protocol PositionRefreshDelegate: AnyObject {
    /// Called when positions should be recalculated for the current element
    func positionRefreshRequested()
}

/// Coordinates app-specific position refresh triggers
/// Monitors events that may require underline position recalculation
class PositionRefreshCoordinator {

    weak var delegate: PositionRefreshDelegate?

    /// Currently monitored bundle ID (nil if not monitoring)
    private var monitoredBundleID: String?

    /// Global mouse click monitor
    private var mouseClickMonitor: Any?

    /// Global keyboard monitor for formatting shortcuts
    private var keyboardMonitor: Any?

    /// Debounce work item for click-based refresh
    private var refreshWorkItem: DispatchWorkItem?

    /// Formatting shortcut key codes: B=11, I=34, U=32
    private static let formattingKeyCodes: Set<UInt16> = [11, 34, 32]

    // MARK: - Lifecycle

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    /// Start monitoring for position refresh triggers for the given app
    /// - Parameter bundleID: The bundle identifier of the app to monitor
    func startMonitoring(bundleID: String) {
        let needsClick = Self.needsClickBasedRefresh(bundleID: bundleID)
        let needsFormatting = Self.needsFormattingRefresh(bundleID: bundleID)

        // Only set up monitors for apps that need them
        guard needsClick || needsFormatting else {
            stopMonitoring()
            return
        }

        // Already monitoring this app
        if monitoredBundleID == bundleID {
            return
        }

        stopMonitoring()
        monitoredBundleID = bundleID

        if needsClick {
            setupMouseClickMonitor()
        }
        if needsFormatting {
            setupKeyboardMonitor()
        }

        Logger.debug("PositionRefreshCoordinator: Started monitoring for \(bundleID) (click: \(needsClick), formatting: \(needsFormatting))", category: Logger.ui)
    }

    /// Stop monitoring for position refresh triggers
    func stopMonitoring() {
        if let monitor = mouseClickMonitor {
            NSEvent.removeMonitor(monitor)
            mouseClickMonitor = nil
        }
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        monitoredBundleID = nil
    }

    // MARK: - App-Specific Configuration

    /// Check if an app needs click-based position refresh
    /// - Parameter bundleID: The bundle identifier to check
    /// - Returns: true if the app needs position refresh after clicks (async AX updates or formatting buttons)
    private static func needsClickBasedRefresh(bundleID: String) -> Bool {
        switch bundleID {
        case "com.tinyspeck.slackmacgap":
            // Slack's Electron-based editor updates AX tree asynchronously
            return true
        default:
            // Apps that support formatted text need click-based refresh for toolbar buttons
            // (Bold, Italic, Underline buttons that aren't detected via keyboard shortcuts)
            let config = AppRegistry.shared.configuration(for: bundleID)
            return config.features.supportsFormattedText
        }
    }

    /// Check if an app needs formatting shortcut refresh
    /// - Parameter bundleID: The bundle identifier to check
    /// - Returns: true if the app supports rich text formatting that can shift text layout
    private static func needsFormattingRefresh(bundleID: String) -> Bool {
        // Use AppFeatures to determine if the app supports formatted text
        let config = AppRegistry.shared.configuration(for: bundleID)
        return config.features.supportsFormattedText
    }

    /// Get the debounce delay for position refresh (milliseconds)
    /// - Parameter bundleID: The bundle identifier
    /// - Returns: Debounce delay in milliseconds
    private static func refreshDebounceMs(for bundleID: String) -> Int {
        switch bundleID {
        case "com.tinyspeck.slackmacgap":
            return GeometryConstants.slackRecheckDebounceMs
        default:
            // Formatting button clicks need a bit more delay for layout to stabilize
            return 250
        }
    }

    // MARK: - Event Monitoring

    /// Setup global mouse click monitor
    private func setupMouseClickMonitor() {
        mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseClick()
        }
    }

    /// Setup global keyboard monitor for formatting shortcuts
    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    /// Handle key down events - check for formatting shortcuts
    private func handleKeyDown(_ event: NSEvent) {
        // Capture event properties before dispatching (NSEvent is not thread-safe)
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags

        // Only interested in Cmd+key combinations
        guard modifierFlags.contains(.command) else { return }

        // Check if this is a formatting shortcut (Cmd+B, Cmd+I, Cmd+U)
        guard Self.formattingKeyCodes.contains(keyCode) else { return }

        // Dispatch to main thread for thread-safe access
        DispatchQueue.main.async { [weak self] in
            self?.handleFormattingShortcut()
        }
    }

    /// Handle formatting shortcut - trigger position refresh
    private func handleFormattingShortcut() {
        guard let bundleID = monitoredBundleID else { return }

        Logger.debug("PositionRefreshCoordinator: Formatting shortcut detected - scheduling position refresh", category: Logger.ui)

        // All checks for replacement mode happen on MainActor
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Skip refresh if in replacement mode
            if AnalysisCoordinator.shared.isInReplacementMode {
                return
            }

            // Cancel any pending refresh
            self.refreshWorkItem?.cancel()

            // Schedule refresh with short delay to let layout update
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard !AnalysisCoordinator.shared.isInReplacementMode else { return }
                    self?.delegate?.positionRefreshRequested()
                }
            }
            self.refreshWorkItem = workItem

            // Use slightly longer delay for formatting (layout needs to stabilize)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Self.refreshDebounceMs(for: bundleID) + 50),
                execute: workItem
            )
        }
    }

    /// Handle mouse click event
    private func handleMouseClick() {
        guard let bundleID = monitoredBundleID else { return }

        // Debounce to let the app's DOM/AX tree stabilize after click
        // All checks for replacement mode happen on MainActor
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Skip refresh if in replacement mode (during replacement or grace period after)
            // Clicking on a suggestion triggers this, but we don't want to refresh
            // until after the replacement completes and positions are adjusted
            if AnalysisCoordinator.shared.isInReplacementMode {
                return
            }

            // Cancel any pending refresh
            self.refreshWorkItem?.cancel()

            // Schedule new refresh
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    // Check again before executing (replacement may have started during delay)
                    guard !AnalysisCoordinator.shared.isInReplacementMode else { return }
                    self?.delegate?.positionRefreshRequested()
                }
            }
            self.refreshWorkItem = workItem

            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Self.refreshDebounceMs(for: bundleID)),
                execute: workItem
            )
        }
    }
}
