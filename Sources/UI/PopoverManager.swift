//
//  PopoverManager.swift
//  TextWarden
//
//  Centralized popover management.
//  Coordinates showing/hiding popovers based on app behavior.
//

import AppKit
import Foundation

// MARK: - Popover Manager

/// Centralized manager for all TextWarden popovers.
///
/// This class manages the lifecycle of popovers, ensuring only one is visible
/// at a time and applying app-specific behavior settings.
///
/// Usage:
/// ```swift
/// PopoverManager.shared.showSuggestion(for: error, at: position, behavior: behavior)
/// PopoverManager.shared.hideAll()
/// ```
final class PopoverManager {
    // MARK: - Singleton

    static let shared = PopoverManager()

    // MARK: - Properties

    /// Currently active popover type
    private(set) var activePopoverType: PopoverType?

    /// Auto-hide timer
    private var autoHideTimer: Timer?

    /// Click-outside monitor
    private let clickMonitor = ClickOutsideMonitor()

    // MARK: - Types

    /// Types of popovers managed by this class
    enum PopoverType {
        case suggestion
        case readability
        case textGeneration
        case style
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Hide all popovers
    func hideAll() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        clickMonitor.removeAll()
        activePopoverType = nil

        Logger.trace("PopoverManager: hideAll called", category: Logger.ui)
    }

    /// Check if any popover is currently visible
    var isPopoverVisible: Bool {
        activePopoverType != nil
    }

    // MARK: - Auto-Hide

    /// Schedule auto-hide after the specified timeout
    /// - Parameter timeout: Time interval in seconds (0 = no auto-hide)
    func scheduleAutoHide(after timeout: TimeInterval) {
        autoHideTimer?.invalidate()

        guard timeout > 0 else { return }

        autoHideTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Logger.trace("PopoverManager: auto-hide triggered", category: Logger.ui)
            self?.hideAll()
        }
    }

    /// Cancel scheduled auto-hide (e.g., when mouse enters popover)
    func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    // MARK: - Popover Type Tracking

    /// Mark a popover as shown
    func markPopoverShown(_ type: PopoverType) {
        activePopoverType = type
        Logger.trace("PopoverManager: marked \(type) as shown", category: Logger.ui)
    }

    /// Mark current popover as hidden
    func markPopoverHidden() {
        activePopoverType = nil
        Logger.trace("PopoverManager: marked popover as hidden", category: Logger.ui)
    }

    // MARK: - Behavior-Based Configuration

    /// Get auto-hide timeout for the current app
    /// - Parameter behavior: App behavior to get timeout from
    /// - Returns: Auto-hide timeout in seconds
    func autoHideTimeout(for behavior: AppBehavior) -> TimeInterval {
        behavior.popoverBehavior.autoHideTimeout
    }

    /// Get hover delay for the current app
    /// - Parameter behavior: App behavior to get delay from
    /// - Returns: Hover delay in seconds
    func hoverDelay(for behavior: AppBehavior) -> TimeInterval {
        behavior.popoverBehavior.hoverDelay
    }

    /// Check if click-outside should dismiss popover
    /// - Parameter behavior: App behavior to check
    /// - Returns: true if click-outside should dismiss
    func shouldDismissOnClickOutside(for behavior: AppBehavior) -> Bool {
        behavior.mouseBehavior.dismissOnClickOutside
    }

    /// Check if window deactivation should hide popover
    /// - Parameter behavior: App behavior to check
    /// - Returns: true if window deactivation should hide
    func shouldHideOnWindowDeactivate(for behavior: AppBehavior) -> Bool {
        behavior.popoverBehavior.hideOnWindowDeactivate
    }

    /// Get preferred popover direction for the current app
    /// - Parameter behavior: App behavior to get direction from
    /// - Returns: Preferred popover direction
    func preferredDirection(for behavior: AppBehavior) -> PopoverBehavior.PopoverDirection {
        behavior.popoverBehavior.preferredDirection
    }
}

// MARK: - Convenience Extensions

extension PopoverManager {
    /// Convert behavior direction to existing PopoverOpenDirection
    func toPopoverOpenDirection(_ direction: PopoverBehavior.PopoverDirection) -> PopoverOpenDirection {
        switch direction {
        case .above:
            .top
        case .below:
            .bottom
        case .left:
            .left
        case .right:
            .right
        }
    }
}
