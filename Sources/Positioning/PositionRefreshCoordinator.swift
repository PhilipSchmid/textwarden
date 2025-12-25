//
//  PositionRefreshCoordinator.swift
//  TextWarden
//
//  Handles app-specific position refresh triggers.
//  Some apps (like Slack) have AX trees that update asynchronously after user interactions,
//  requiring position recalculation after clicks or other events.
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

    /// Debounce work item for click-based refresh
    private var refreshWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    /// Start monitoring for position refresh triggers for the given app
    /// - Parameter bundleID: The bundle identifier of the app to monitor
    func startMonitoring(bundleID: String) {
        // Only set up monitors for apps that need them
        guard Self.needsClickBasedRefresh(bundleID: bundleID) else {
            stopMonitoring()
            return
        }

        // Already monitoring this app
        if monitoredBundleID == bundleID {
            return
        }

        stopMonitoring()
        monitoredBundleID = bundleID
        setupMouseClickMonitor()

        Logger.debug("PositionRefreshCoordinator: Started monitoring for \(bundleID)", category: Logger.ui)
    }

    /// Stop monitoring for position refresh triggers
    func stopMonitoring() {
        if let monitor = mouseClickMonitor {
            NSEvent.removeMonitor(monitor)
            mouseClickMonitor = nil
        }
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        monitoredBundleID = nil
    }

    // MARK: - App-Specific Configuration

    /// Check if an app needs click-based position refresh
    /// - Parameter bundleID: The bundle identifier to check
    /// - Returns: true if the app's AX tree updates asynchronously after clicks
    private static func needsClickBasedRefresh(bundleID: String) -> Bool {
        switch bundleID {
        case "com.tinyspeck.slackmacgap":
            // Slack's Electron-based editor updates AX tree asynchronously
            return true
        default:
            return false
        }
    }

    /// Get the debounce delay for position refresh (milliseconds)
    /// - Parameter bundleID: The bundle identifier
    /// - Returns: Debounce delay in milliseconds
    private static func refreshDebounceMs(for bundleID: String) -> Int {
        switch bundleID {
        case "com.tinyspeck.slackmacgap":
            return GeometryConstants.slackRecheckDebounceMs
        default:
            return 200
        }
    }

    // MARK: - Event Monitoring

    /// Setup global mouse click monitor
    private func setupMouseClickMonitor() {
        mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseClick()
        }
    }

    /// Handle mouse click event
    private func handleMouseClick() {
        guard let bundleID = monitoredBundleID else { return }

        // Debounce to let the app's DOM/AX tree stabilize after click
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Cancel any pending refresh
            self.refreshWorkItem?.cancel()

            // Schedule new refresh
            let workItem = DispatchWorkItem { [weak self] in
                self?.delegate?.positionRefreshRequested()
            }
            self.refreshWorkItem = workItem

            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Self.refreshDebounceMs(for: bundleID)),
                execute: workItem
            )
        }
    }
}
