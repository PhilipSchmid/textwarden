//
//  PopoverUtilities.swift
//  TextWarden
//
//  Shared utilities for popover positioning and window management.
//  Used by SuggestionPopover, ReadabilityPopover, and TextGenerationPopover.
//

import AppKit
import Foundation

// MARK: - Popover Positioning

/// Utility for calculating popover positions with automatic direction flipping
enum PopoverPositioner {
    /// Calculate the origin for a popover given an anchor point and direction.
    /// Automatically flips to opposite direction if the popover doesn't fit on screen.
    ///
    /// - Parameters:
    ///   - anchorPoint: The screen point to anchor the popover to
    ///   - panelSize: The size of the popover panel
    ///   - direction: The preferred direction to open (left, right, top, bottom)
    ///   - constraintFrame: The frame to constrain the popover within (usually screen.visibleFrame)
    ///   - padding: Padding from screen edges (default 20pt)
    /// - Returns: A tuple of (origin, usedDirection) for the final position
    static func positionFromAnchor(
        at anchorPoint: CGPoint,
        panelSize: NSSize,
        direction: PopoverOpenDirection,
        constraintFrame: CGRect,
        padding: CGFloat = 20
    ) -> (origin: CGPoint, usedDirection: PopoverOpenDirection) {
        // Calculate origin for a given direction
        func originFor(dir: PopoverOpenDirection) -> CGPoint {
            switch dir {
            case .left:
                CGPoint(x: anchorPoint.x - panelSize.width, y: anchorPoint.y - panelSize.height / 2)
            case .right:
                CGPoint(x: anchorPoint.x, y: anchorPoint.y - panelSize.height / 2)
            case .top:
                CGPoint(x: anchorPoint.x - panelSize.width / 2, y: anchorPoint.y)
            case .bottom:
                CGPoint(x: anchorPoint.x - panelSize.width / 2, y: anchorPoint.y - panelSize.height)
            }
        }

        // Check if origin fits within constraint frame
        func fitsScreen(origin: CGPoint) -> Bool {
            let minX = constraintFrame.minX + padding
            let maxX = constraintFrame.maxX - panelSize.width - padding
            let minY = constraintFrame.minY + padding
            let maxY = constraintFrame.maxY - panelSize.height - padding
            return origin.x >= minX && origin.x <= maxX && origin.y >= minY && origin.y <= maxY
        }

        // Get opposite direction for fallback
        func opposite(_ dir: PopoverOpenDirection) -> PopoverOpenDirection {
            switch dir {
            case .left: .right
            case .right: .left
            case .top: .bottom
            case .bottom: .top
            }
        }

        // Try requested direction first
        var origin = originFor(dir: direction)
        var usedDirection = direction

        // If doesn't fit, try opposite direction
        if !fitsScreen(origin: origin) {
            let oppositeDir = opposite(direction)
            let oppositeOrigin = originFor(dir: oppositeDir)
            if fitsScreen(origin: oppositeOrigin) {
                origin = oppositeOrigin
                usedDirection = oppositeDir
            } else {
                // Neither direction fits - clamp to constraint frame
                origin.x = max(constraintFrame.minX + padding, min(origin.x, constraintFrame.maxX - panelSize.width - padding))
                origin.y = max(constraintFrame.minY + padding, min(origin.y, constraintFrame.maxY - panelSize.height - padding))
            }
        }

        return (origin, usedDirection)
    }
}

// MARK: - Modal Dialog Detection

/// Utility for checking if modal dialogs are present
enum ModalDialogDetector {
    /// Check if the mouse is currently over a modal dialog window.
    /// This is more reliable than checking for modal windows globally,
    /// as it only blocks popovers when the user is actually interacting with a dialog.
    static func isModalDialogPresent() -> Bool {
        // Check for app-modal windows in TextWarden (covers our own dialogs)
        if NSApp.modalWindow != nil {
            return true
        }

        // Check if any of our windows has an attached sheet
        for window in NSApp.windows where window.attachedSheet != nil {
            return true
        }

        // Check if mouse is over a modal-level window from another app
        // This catches Print dialogs, Save sheets, etc. without false positives
        return isMouseOverModalWindow()
    }

    /// Check if the current mouse position is inside a modal-level window
    private static func isMouseOverModalWindow() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        let floatingLevel = Int(CGWindowLevelForKey(.floatingWindow))

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for windowInfo in windowList {
            guard let windowLevel = windowInfo[kCGWindowLayer as String] as? Int,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"]
            else { continue }

            // Only check windows above floating level (where our overlay sits)
            guard windowLevel > floatingLevel else { continue }

            let ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? ""

            // Skip our own TextWarden windows
            if ownerName == "TextWarden" { continue }

            // Skip system UI (menu bar, status items, etc.)
            if ownerName == "Window Server" || ownerName == "SystemUIServer" { continue }

            // Skip BetterDisplay - it has a persistent transparent overlay across virtual displays
            // that is always present, unlike other apps that only show high-level windows during user interaction
            if ownerName == "BetterDisplay" { continue }

            // Convert CGWindow bounds (top-left origin) to Cocoa coords (bottom-left origin)
            // Use PRIMARY screen height (frame.origin == .zero), not NSScreen.screens.first
            let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
            let screenHeight = primaryScreen?.frame.height ?? NSScreen.screens.first?.frame.height ?? 1080
            let windowFrame = CGRect(
                x: x,
                y: screenHeight - y - height,
                width: width,
                height: height
            )

            // Check if mouse is inside this window
            if windowFrame.contains(mouseLocation) {
                Logger.debug("ModalDialogDetector: Detected modal-level window '\(ownerName)' (level \(windowLevel)) at \(windowFrame) containing mouse at \(mouseLocation)", category: Logger.ui)
                return true
            }
        }

        return false
    }
}

// MARK: - Click Outside Monitor

/// Manages click-outside detection for popovers
final class ClickOutsideMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Set up a global monitor for clicks outside the panel
    /// - Parameters:
    ///   - panel: The panel to monitor clicks outside of
    ///   - onClickOutside: Callback when a click outside is detected
    func setupGlobalMonitor(for panel: NSPanel, onClickOutside: @escaping () -> Void) {
        removeAll()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak panel] event in
            guard let panel else { return }

            let clickLocation = event.locationInWindow
            let panelFrame = panel.frame

            if !panelFrame.contains(clickLocation) {
                onClickOutside()
            }
        }
    }

    /// Set up a local monitor for clicks outside the panel
    /// - Parameters:
    ///   - panel: The panel to monitor clicks outside of
    ///   - onClickOutside: Callback when a click outside is detected
    func setupLocalMonitor(for panel: NSPanel, onClickOutside: @escaping () -> Void) {
        removeAll()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak panel] event in
            guard let panel else { return event }

            // Check if click is in the panel window
            if event.window == panel {
                return event
            }

            // Convert to screen coordinates for proper comparison
            if let windowFrame = event.window?.frame {
                let screenLocation = CGPoint(
                    x: windowFrame.origin.x + event.locationInWindow.x,
                    y: windowFrame.origin.y + event.locationInWindow.y
                )

                if !panel.frame.contains(screenLocation) {
                    onClickOutside()
                }
            } else {
                // No window means click is somewhere else
                onClickOutside()
            }

            return event
        }
    }

    /// Remove all monitors
    func removeAll() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        removeAll()
    }
}

// MARK: - Popover Tracking Protocol

/// Protocol for views that track mouse enter/exit for popovers
protocol PopoverTracking: AnyObject {
    /// Called when mouse enters the popover
    func cancelHide()

    /// Called when mouse exits the popover
    func scheduleHide()
}

// MARK: - Base Tracking View

/// Base class for popover tracking views with mouse enter/exit detection
class BasePopoverTrackingView: NSView {
    /// The popover conforming to PopoverTracking
    weak var trackingDelegate: PopoverTracking?

    /// Callback when mouse enters
    var onMouseEntered: (() -> Void)?

    /// Callback when mouse exits
    var onMouseExited: (() -> Void)?

    /// Track last size to avoid unnecessary tracking area updates during rebuild cycles
    private var lastTrackingSize: NSSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
        setupTracking()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
    }

    private func setupTracking() {
        // Initial setup - will be properly configured in updateTrackingAreas()
        updateTrackingAreas()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        // Only update tracking areas if size actually changed significantly
        // This prevents unnecessary recreation during rebuild cycles
        if abs(newSize.width - lastTrackingSize.width) > 1 || abs(newSize.height - lastTrackingSize.height) > 1 {
            lastTrackingSize = newSize
            updateTrackingAreas()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }

        // Only add tracking area if we have valid bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    // CRITICAL: Accept first mouse click without requiring panel activation
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with _: NSEvent) {
        trackingDelegate?.cancelHide()
        onMouseEntered?()
    }

    override func mouseExited(with _: NSEvent) {
        onMouseExited?()
        trackingDelegate?.scheduleHide()
    }
}
