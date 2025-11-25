//
//  FloatingErrorIndicator.swift
//  TextWarden
//
//  Floating error indicator
//  Shows a small circular badge in the bottom-right corner of text fields
//

import Cocoa
import AppKit
import Combine

/// Floating error indicator window
class FloatingErrorIndicator: NSPanel {
    /// Shared singleton instance
    static let shared = FloatingErrorIndicator()

    /// Current errors being displayed
    private var errors: [GrammarErrorModel] = []

    /// Current monitored element
    private var monitoredElement: AXUIElement?

    /// Application context
    private var context: ApplicationContext?

    /// Custom view for drawing the indicator
    private var indicatorView: IndicatorView?

    /// Border guide window for drag feedback
    private let borderGuide = BorderGuideWindow()

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 40, height: 40)

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Window configuration
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))  // Highest possible level
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let indicatorView = IndicatorView(frame: initialFrame)
        indicatorView.onClicked = { [weak self] in
            self?.showErrors()
        }
        indicatorView.onHover = { [weak self] isHovering in
            if isHovering {
                self?.showErrors()
            } else {
                SuggestionPopover.shared.scheduleHide()
            }
        }
        indicatorView.onDragStart = { [weak self] in
            guard let self = self else { return }

            Logger.debug("onDragStart triggered!", category: Logger.ui)

            SuggestionPopover.shared.hide()

            // Enlarge indicator to show it's being dragged
            let currentFrame = self.frame
            let normalSize: CGFloat = 40
            let enlargedSize: CGFloat = 45
            let sizeDelta = enlargedSize - normalSize

            // Adjust origin to keep indicator centered while enlarging
            let newFrame = NSRect(
                x: currentFrame.origin.x - sizeDelta / 2,
                y: currentFrame.origin.y - sizeDelta / 2,
                width: enlargedSize,
                height: enlargedSize
            )
            self.setFrame(newFrame, display: true)

            // Ensure indicator stays visible and in front during drag
            self.alphaValue = 0.85  // Slightly transparent to see what's underneath
            self.orderFrontRegardless()
            self.level = .popUpMenu + 2  // Increase level during drag

            if let element = self.monitoredElement,
               let windowFrame = self.getVisibleWindowFrame(for: element) {
                Logger.debug("Showing border guide with frame: \(windowFrame)", category: Logger.ui)

                // Use brown color (TextWarden logo color) for border guide
                let brownColor = NSColor(red: 139/255.0, green: 69/255.0, blue: 19/255.0, alpha: 1.0)
                self.borderGuide.showBorder(around: windowFrame, color: brownColor)
            } else {
                Logger.debug("Cannot show border guide - element=\(String(describing: self.monitoredElement))", category: Logger.ui)
            }
        }
        indicatorView.onDragEnd = { [weak self] finalPosition in
            guard let self = self else { return }

            // Restore normal size
            let normalSize: CGFloat = 40
            let enlargedSize: CGFloat = 45
            let sizeDelta = enlargedSize - normalSize

            // Adjust origin to keep indicator centered while shrinking back
            let newFrame = NSRect(
                x: finalPosition.x + sizeDelta / 2,
                y: finalPosition.y + sizeDelta / 2,
                width: normalSize,
                height: normalSize
            )
            self.setFrame(newFrame, display: true)

            // Restore normal appearance
            self.alphaValue = 1.0
            self.level = .popUpMenu + 1  // Restore original level

            self.borderGuide.hide()

            // Handle snap positioning with corrected position
            self.handleDragEnd(at: newFrame.origin)
        }
        self.indicatorView = indicatorView
        self.contentView = indicatorView

        // Listen to indicator position changes for immediate repositioning
        setupPositionObserver()
    }

    // CRITICAL: Prevent this window from stealing focus from other applications
    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }

    /// Setup observer for indicator position preference changes
    private func setupPositionObserver() {
        UserPreferences.shared.$indicatorPosition
            .dropFirst()  // Skip initial value
            .receive(on: DispatchQueue.main)  // Ensure UI updates on main thread
            .sink { [weak self] newPosition in
                guard let self = self else { return }

                // If indicator is currently visible with errors, reposition immediately
                if self.isVisible, let element = self.monitoredElement, !self.errors.isEmpty {
                    Logger.debug("FloatingErrorIndicator: Position changed to '\(newPosition)' - repositioning", category: Logger.ui)
                    self.positionIndicator(for: element)
                }
            }
            .store(in: &cancellables)
    }

    /// Update indicator with errors
    func update(errors: [GrammarErrorModel], element: AXUIElement, context: ApplicationContext?) {
        Logger.debug("FloatingErrorIndicator: update() called with \(errors.count) errors", category: Logger.ui)
        self.errors = errors
        self.monitoredElement = element
        self.context = context

        guard !errors.isEmpty else {
            Logger.debug("FloatingErrorIndicator: No errors, hiding", category: Logger.ui)
            hide()
            return
        }

        indicatorView?.errorCount = errors.count
        indicatorView?.errorColor = colorForErrors(errors)
        indicatorView?.needsDisplay = true

        // Position in bottom-right of text field
        positionIndicator(for: element)

        Logger.debug("FloatingErrorIndicator: Window level: \(self.level.rawValue), isVisible: \(isVisible)", category: Logger.ui)
        if !isVisible {
            Logger.debug("FloatingErrorIndicator: Calling order(.above)", category: Logger.ui)
            order(.above, relativeTo: 0)  // Show window without stealing focus
            Logger.debug("FloatingErrorIndicator: After order(.above), isVisible: \(isVisible)", category: Logger.ui)
        } else {
            Logger.debug("FloatingErrorIndicator: Window already visible", category: Logger.ui)
        }
    }

    /// Update indicator with errors using only context (no element required)
    /// Used when restoring from window minimize where element may not be available
    func updateWithContext(errors: [GrammarErrorModel], context: ApplicationContext) {
        Logger.debug("FloatingErrorIndicator: updateWithContext() called with \(errors.count) errors", category: Logger.ui)
        self.errors = errors
        self.context = context
        // Don't set monitoredElement - we don't have one

        guard !errors.isEmpty else {
            Logger.debug("FloatingErrorIndicator: No errors, hiding", category: Logger.ui)
            hide()
            return
        }

        indicatorView?.errorCount = errors.count
        indicatorView?.errorColor = colorForErrors(errors)
        indicatorView?.needsDisplay = true

        // Position using PID from context (no element needed)
        positionIndicatorByPID(context.processID)

        Logger.debug("FloatingErrorIndicator: Window level: \(self.level.rawValue), isVisible: \(isVisible)", category: Logger.ui)
        if !isVisible {
            Logger.debug("FloatingErrorIndicator: Calling order(.above)", category: Logger.ui)
            order(.above, relativeTo: 0)  // Show window without stealing focus
            Logger.debug("FloatingErrorIndicator: After order(.above), isVisible: \(isVisible)", category: Logger.ui)
        } else {
            Logger.debug("FloatingErrorIndicator: Window already visible", category: Logger.ui)
        }
    }

    /// Position indicator using PID (when no element is available)
    private func positionIndicatorByPID(_ pid: pid_t) {
        guard let visibleFrame = getVisibleWindowFrameByPID(pid) else {
            Logger.debug("FloatingErrorIndicator: Failed to get visible window frame by PID, using screen corner", category: Logger.ui)
            positionInScreenCorner()
            return
        }

        Logger.debug("FloatingErrorIndicator: Using visible window frame (by PID): \(visibleFrame)", category: Logger.ui)

        let indicatorSize: CGFloat = 40

        // Check for per-app stored position first
        var percentagePos: IndicatorPositionStore.PercentagePosition?
        if let bundleId = context?.bundleIdentifier {
            percentagePos = IndicatorPositionStore.shared.getPosition(for: bundleId)
            if percentagePos != nil {
                Logger.debug("FloatingErrorIndicator: Using stored position for \(bundleId)", category: Logger.ui)
            }
        }

        // If no stored position, use default from preferences
        if percentagePos == nil {
            percentagePos = IndicatorPositionStore.shared.getDefaultPosition()
            Logger.debug("FloatingErrorIndicator: Using default position from preferences", category: Logger.ui)
        }

        // Convert percentage to absolute position
        let position = percentagePos!.toAbsolute(in: visibleFrame, indicatorSize: indicatorSize)
        let finalFrame = NSRect(x: position.x, y: position.y, width: indicatorSize, height: indicatorSize)

        Logger.debug("FloatingErrorIndicator: Positioning at \(finalFrame)", category: Logger.ui)
        setFrame(finalFrame, display: true)
    }

    /// Get visible window frame using PID directly (no element required)
    private func getVisibleWindowFrameByPID(_ pid: pid_t) -> CGRect? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            Logger.debug("FloatingErrorIndicator: Failed to get window list", category: Logger.ui)
            return nil
        }

        // Find the LARGEST window for this PID
        var bestWindow: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, area: CGFloat)?

        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == pid,
               let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {

                let x = boundsDict["X"] ?? 0
                let y = boundsDict["Y"] ?? 0
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0
                let area = width * height

                // Skip tiny windows (< 100x100, likely tooltips or popups)
                guard width >= 100 && height >= 100 else { continue }

                if bestWindow == nil || area > bestWindow!.area {
                    bestWindow = (x: x, y: y, width: width, height: height, area: area)
                }
            }
        }

        guard let best = bestWindow else {
            Logger.debug("FloatingErrorIndicator: No matching window found for PID \(pid)", category: Logger.ui)
            return nil
        }

        // Convert from CGWindow coordinates (y=0 at top) to Cocoa coordinates (y=0 at bottom)
        let totalScreenHeight = NSScreen.screens.reduce(0) { max($0, $1.frame.maxY) }
        let cocoaY = totalScreenHeight - best.y - best.height

        return CGRect(x: best.x, y: cocoaY, width: best.width, height: best.height)
    }

    /// Hide indicator
    func hide() {
        orderOut(nil)
        borderGuide.hide()
        errors = []
        monitoredElement = nil
    }

    /// Handle drag end with snap-back to valid border area
    private func handleDragEnd(at finalPosition: CGPoint) {
        guard let element = monitoredElement,
              let windowFrame = getVisibleWindowFrame(for: element),
              let bundleId = context?.bundleIdentifier else {
            Logger.debug("FloatingErrorIndicator: handleDragEnd - no window frame or bundle ID available", category: Logger.ui)
            return
        }

        let indicatorSize: CGFloat = 40

        // Snap position to valid border area
        let snappedPosition = snapToBorderArea(
            position: finalPosition,
            windowFrame: windowFrame,
            indicatorSize: indicatorSize
        )

        // Update the indicator position if it was snapped
        if snappedPosition != finalPosition {
            Logger.debug("FloatingErrorIndicator: Snapping from \(finalPosition) to \(snappedPosition)", category: Logger.ui)
            let snappedFrame = NSRect(x: snappedPosition.x, y: snappedPosition.y, width: indicatorSize, height: indicatorSize)
            setFrame(snappedFrame, display: true, animate: true)
        }

        // Convert absolute position to percentage
        let percentagePos = IndicatorPositionStore.PercentagePosition.from(
            absolutePosition: snappedPosition,
            in: windowFrame,
            indicatorSize: indicatorSize
        )

        // Save position for this application
        IndicatorPositionStore.shared.savePosition(percentagePos, for: bundleId)

        Logger.debug("FloatingErrorIndicator: Saved position for \(bundleId) at x=\(percentagePos.xPercent), y=\(percentagePos.yPercent)", category: Logger.ui)
    }

    /// Snap a position to the valid border area (1.5cm band around window edge)
    /// If the position is outside the window or in the center, snaps to closest valid position
    private func snapToBorderArea(position: CGPoint, windowFrame: CGRect, indicatorSize: CGFloat) -> CGPoint {
        let borderWidth = BorderGuideWindow.borderWidth

        // First, clamp position to be within the window bounds
        var snappedX = max(windowFrame.minX, min(position.x, windowFrame.maxX - indicatorSize))
        var snappedY = max(windowFrame.minY, min(position.y, windowFrame.maxY - indicatorSize))

        // Define the valid border area (within borderWidth of any edge)
        let innerRect = windowFrame.insetBy(dx: borderWidth, dy: borderWidth)

        // Check if the indicator center is in the "forbidden" center zone
        let indicatorCenterX = snappedX + indicatorSize / 2
        let indicatorCenterY = snappedY + indicatorSize / 2

        // If the indicator is fully within the inner (forbidden) zone, snap to closest edge
        if innerRect.contains(CGPoint(x: indicatorCenterX, y: indicatorCenterY)) {
            // Calculate distances to each edge of the valid border area
            let distToLeft = indicatorCenterX - windowFrame.minX
            let distToRight = windowFrame.maxX - indicatorCenterX
            let distToBottom = indicatorCenterY - windowFrame.minY
            let distToTop = windowFrame.maxY - indicatorCenterY

            let minDist = min(distToLeft, distToRight, distToBottom, distToTop)

            // Snap to the closest edge
            if minDist == distToLeft {
                snappedX = windowFrame.minX
            } else if minDist == distToRight {
                snappedX = windowFrame.maxX - indicatorSize
            } else if minDist == distToBottom {
                snappedY = windowFrame.minY
            } else {
                snappedY = windowFrame.maxY - indicatorSize
            }

            Logger.debug("FloatingErrorIndicator: Snapped to closest edge (minDist=\(minDist))", category: Logger.ui)
        }

        // Ensure the final position keeps the indicator within the border area
        // The indicator can be anywhere in the border band, not just on the edge
        // But it must have at least part of it within borderWidth of an edge

        return CGPoint(x: snappedX, y: snappedY)
    }

    /// Position indicator based on per-app stored position or user preference
    private func positionIndicator(for element: AXUIElement) {
        // Try to get the actual visible window frame
        guard let visibleFrame = getVisibleWindowFrame(for: element) else {
            Logger.debug("FloatingErrorIndicator: Failed to get visible window frame, using screen corner", category: Logger.ui)
            positionInScreenCorner()
            return
        }

        Logger.debug("FloatingErrorIndicator: Using visible window frame: \(visibleFrame)", category: Logger.ui)

        let indicatorSize: CGFloat = 40

        // Check for per-app stored position first
        var percentagePos: IndicatorPositionStore.PercentagePosition?
        if let bundleId = context?.bundleIdentifier {
            percentagePos = IndicatorPositionStore.shared.getPosition(for: bundleId)
            if percentagePos != nil {
                Logger.debug("FloatingErrorIndicator: Using stored position for \(bundleId)", category: Logger.ui)
            }
        }

        // If no stored position, use default from preferences
        if percentagePos == nil {
            percentagePos = IndicatorPositionStore.shared.getDefaultPosition()
            Logger.debug("FloatingErrorIndicator: Using default position from preferences", category: Logger.ui)
        }

        // Convert percentage to absolute position
        let position = percentagePos!.toAbsolute(in: visibleFrame, indicatorSize: indicatorSize)
        let finalFrame = NSRect(x: position.x, y: position.y, width: indicatorSize, height: indicatorSize)

        Logger.debug("FloatingErrorIndicator: Positioning at \(finalFrame)", category: Logger.ui)
        setFrame(finalFrame, display: true)
    }

    /// Calculate indicator position based on user preference
    private func calculatePosition(
        for position: String,
        in frame: CGRect,
        indicatorSize: CGFloat,
        padding: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        switch position {
        case "Top Left":
            return (frame.minX + padding, frame.maxY - indicatorSize - padding)
        case "Top Right":
            return (frame.maxX - indicatorSize - padding, frame.maxY - indicatorSize - padding)
        case "Center Left":
            return (frame.minX + padding, frame.midY - indicatorSize / 2)
        case "Center Right":
            return (frame.maxX - indicatorSize - padding, frame.midY - indicatorSize / 2)
        case "Bottom Left":
            return (frame.minX + padding, frame.minY + padding)
        case "Bottom Right":
            return (frame.maxX - indicatorSize - padding, frame.minY + padding)
        default:
            // Default to bottom right
            return (frame.maxX - indicatorSize - padding, frame.minY + padding)
        }
    }

    /// Fallback: position based on user preference using screen bounds
    private func positionInScreenCorner() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 10
        let indicatorSize: CGFloat = 40
        let position = UserPreferences.shared.indicatorPosition

        let (x, y) = calculatePosition(
            for: position,
            in: screenFrame,
            indicatorSize: indicatorSize,
            padding: padding
        )

        let finalFrame = NSRect(x: x, y: y, width: indicatorSize, height: indicatorSize)
        Logger.debug("FloatingErrorIndicator: Fallback positioning at screen corner: \(finalFrame)", category: Logger.ui)

        setFrame(finalFrame, display: true)
    }

    /// Get the actual visible window frame using CGWindowListCopyWindowInfo
    /// This avoids the scrollback buffer issue with Terminal apps
    private func getVisibleWindowFrame(for element: AXUIElement) -> CGRect? {
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) != .success {
            Logger.debug("FloatingErrorIndicator: Failed to get PID from element", category: Logger.ui)
            return nil
        }

        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            Logger.debug("FloatingErrorIndicator: Failed to get window list", category: Logger.ui)
            return nil
        }

        // Find the LARGEST window for this PID
        // This ensures we get the main application window, not floating panels/popups like Cmd+F search
        var bestWindow: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, area: CGFloat)?

        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == pid,
               let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {

                // Extract bounds
                let x = boundsDict["X"] ?? 0
                let y = boundsDict["Y"] ?? 0
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0
                let area = width * height

                // Skip tiny windows (< 100x100, likely tooltips or popups)
                guard width >= 100 && height >= 100 else { continue }

                // Keep track of the largest window
                if bestWindow == nil || area > bestWindow!.area {
                    bestWindow = (x: x, y: y, width: width, height: height, area: area)
                }
            }
        }

        guard let best = bestWindow else {
            Logger.debug("FloatingErrorIndicator: No matching window found in window list", category: Logger.ui)
            return nil
        }

        let x = best.x
        let y = best.y
        let width = best.width
        let height = best.height

        // CGWindowListCopyWindowInfo returns coordinates with y=0 at TOP
        // NSScreen uses Cocoa coordinates with y=0 at BOTTOM
        // CRITICAL: Must find which screen the window is on for proper conversion

        // First, find which screen contains this window
        // We'll check which screen's bounds (in CGWindow coordinates) intersect with the window
        let windowCGRect = CGRect(x: x, y: y, width: width, height: height)
        let totalScreenHeight = NSScreen.screens.reduce(0) { max($0, $1.frame.maxY) }

        var targetScreen: NSScreen?
        var maxIntersection: CGFloat = 0

        for screen in NSScreen.screens {
            // Convert this screen's Cocoa frame to CGWindow coordinates for comparison
            let cocoaFrame = screen.frame
            let cgY = totalScreenHeight - cocoaFrame.maxY
            let cgScreenRect = CGRect(
                x: cocoaFrame.origin.x,
                y: cgY,
                width: cocoaFrame.width,
                height: cocoaFrame.height
            )

            // Check intersection
            let intersection = windowCGRect.intersection(cgScreenRect)
            let area = intersection.width * intersection.height

            if area > maxIntersection {
                maxIntersection = area
                targetScreen = screen
            }
        }

        // Use the screen we found (or fall back to main)
        guard let screen = targetScreen ?? NSScreen.main else {
            Logger.debug("FloatingErrorIndicator: No screen found", category: Logger.ui)
            return nil
        }

        // Convert from CGWindow coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
        // Use simple formula: cocoaY = totalScreenHeight - cgY - height
        let cocoaY = totalScreenHeight - y - height

        let frame = NSRect(x: x, y: cocoaY, width: width, height: height)
        Logger.debug("FloatingErrorIndicator: Window on screen '\(screen.localizedName)' at \(screen.frame) - CGWindow: (\(x), \(y)), Cocoa: \(frame)", category: Logger.ui)

        // Note: Debug borders are now managed by AnalysisCoordinator.updateDebugBorders()
        // to show them always when enabled (not just when errors exist)

        return frame
    }

    /// Get the window frame for the given element (may include scrollback for terminals)
    private func getWindowFrame(for element: AXUIElement) -> CGRect? {
        // Try to get the window that contains this element
        var windowValue: CFTypeRef?

        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) != .success {
            // If this element doesn't have a window attribute, try to get its parent window
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success else {
                return nil
            }

            // Try up to 10 levels to find a window
            var current = parentValue as! AXUIElement
            for _ in 0..<10 {
                if AXUIElementCopyAttributeValue(current, kAXWindowAttribute as CFString, &windowValue) == .success {
                    break
                }

                var nextParent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &nextParent) == .success else {
                    return nil
                }
                current = nextParent as! AXUIElement
            }

            guard windowValue != nil else {
                return nil
            }
        }

        let window = windowValue as! AXUIElement

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return NSRect(origin: position, size: size)
    }

    /// Get color for errors based on severity
    private func colorForErrors(_ errors: [GrammarErrorModel]) -> NSColor {
        // Prioritize by severity: Spelling > Grammar > Style
        if errors.contains(where: { $0.category == "Spelling" || $0.category == "Typo" }) {
            return .systemRed
        } else if errors.contains(where: {
            $0.category == "Grammar" || $0.category == "Agreement" || $0.category == "Punctuation"
        }) {
            return .systemOrange
        } else {
            return .systemBlue
        }
    }

    /// Show errors popover
    private func showErrors() {
        Logger.debug("FloatingErrorIndicator: showErrors called with \(errors.count) errors", category: Logger.ui)
        guard let firstError = errors.first else {
            Logger.debug("FloatingErrorIndicator: No errors to show", category: Logger.ui)
            return
        }

        // Position popover inward from indicator based on position
        let indicatorFrame = frame
        let position = calculatePopoverPosition(for: indicatorFrame)

        Logger.debug("FloatingErrorIndicator: Showing popover at \(position)", category: Logger.ui)
        SuggestionPopover.shared.show(
            error: firstError,
            allErrors: errors,
            at: position
        )
    }

    /// Calculate popover position that points inward from the indicator
    private func calculatePopoverPosition(for indicatorFrame: CGRect) -> CGPoint {
        let indicatorPosition = UserPreferences.shared.indicatorPosition
        // Use larger spacing for left positions (to overcome popover's auto-positioning logic)
        // Use smaller spacing for right positions to match visual gap
        // Formula: left gap = leftSpacing - popoverWidth - padding
        //          right gap = rightSpacing + padding
        let leftSpacing: CGFloat = 400
        let rightSpacing: CGFloat = 30

        switch indicatorPosition {
        case "Top Left":
            // Indicator at top-left → popover to right and slightly below
            return CGPoint(x: indicatorFrame.maxX + leftSpacing, y: indicatorFrame.midY - 20)
        case "Top Right":
            // Indicator at top-right → popover to left and slightly below
            return CGPoint(x: indicatorFrame.minX - rightSpacing, y: indicatorFrame.midY - 20)
        case "Center Left":
            // Indicator at center-left → popover to the right
            return CGPoint(x: indicatorFrame.maxX + leftSpacing, y: indicatorFrame.midY)
        case "Center Right":
            // Indicator at center-right → popover to the left
            return CGPoint(x: indicatorFrame.minX - rightSpacing, y: indicatorFrame.midY)
        case "Bottom Left":
            // Indicator at bottom-left → popover to right and slightly above
            return CGPoint(x: indicatorFrame.maxX + leftSpacing, y: indicatorFrame.midY + 20)
        case "Bottom Right":
            // Indicator at bottom-right → popover to left and slightly above
            return CGPoint(x: indicatorFrame.minX - rightSpacing, y: indicatorFrame.midY + 20)
        default:
            // Default to above indicator (old behavior)
            return CGPoint(x: indicatorFrame.midX, y: indicatorFrame.maxY + 10)
        }
    }

    /// Get frame of AX element
    private func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return NSRect(origin: position, size: size)
    }
}

/// Custom view for drawing the circular indicator
private class IndicatorView: NSView {
    var errorCount: Int = 0
    var errorColor: NSColor = .systemRed
    var onClicked: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?

    private var hoverTimer: Timer?
    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 4
        shadow.set()

        // Draw background circle with system-adaptive color
        let backgroundPath = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        NSColor.controlBackgroundColor.setFill()
        backgroundPath.fill()

        // Clear shadow for border
        NSShadow().set()

        // Draw colored ring (thicker, more prominent)
        let ringPath = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        errorColor.setStroke()
        ringPath.lineWidth = 3.5
        ringPath.stroke()

        // Draw error count with adaptive text color
        let countString = "\(errorCount)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = (countString as NSString).size(withAttributes: attributes)

        // Position text centered
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2 + 2,
            width: textSize.width,
            height: textSize.height
        )
        (countString as NSString).draw(in: textRect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        Logger.debug("IndicatorView: mouseDown called at \(event.locationInWindow)", category: Logger.ui)

        isDragging = true
        dragStartPoint = event.locationInWindow

        // Change cursor to closed hand
        NSCursor.closedHand.push()

        // Notify drag start
        onDragStart?()

        // Redraw to show dots instead of count
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = window else { return }

        // Calculate delta from start point
        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - dragStartPoint.x
        let deltaY = currentPoint.y - dragStartPoint.y

        // Move window
        var newOrigin = window.frame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY

        window.setFrameOrigin(newOrigin)

        // Ensure window stays visible and in front during drag
        window.orderFrontRegardless()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else {
            // If not dragging, treat as a click
            onClicked?()
            return
        }

        isDragging = false
        NSCursor.pop()

        if let window = window {
            onDragEnd?(window.frame.origin)
        }

        // Redraw to show count instead of dots
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        Logger.debug("IndicatorView: mouseEntered", category: Logger.ui)
        isHovered = true

        // Use open hand cursor to indicate draggability
        if !isDragging {
            NSCursor.openHand.push()
        }

        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.onHover?(true)
        }

        // Redraw to update dot opacity
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        Logger.debug("IndicatorView: mouseExited", category: Logger.ui)
        isHovered = false

        if !isDragging {
            NSCursor.pop()
        }

        // Cancel hover timer if mouse exits before delay
        hoverTimer?.invalidate()
        hoverTimer = nil

        onHover?(false)

        // Redraw to update dot opacity
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}
