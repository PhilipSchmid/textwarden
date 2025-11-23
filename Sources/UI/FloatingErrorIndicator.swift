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
        // Create a small circular window
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

        // Create and add indicator view
        let indicatorView = IndicatorView(frame: initialFrame)
        indicatorView.onClicked = { [weak self] in
            self?.showErrors()
        }
        indicatorView.onHover = { [weak self] isHovering in
            if isHovering {
                self?.showErrors()
            } else {
                // Hide popover when mouse leaves indicator
                SuggestionPopover.shared.scheduleHide()
            }
        }
        indicatorView.onDragStart = { [weak self] in
            guard let self = self else { return }

            let msg = "🟢 onDragStart triggered!"
            NSLog(msg)
            logToDebugFile(msg)

            // Hide popover during drag
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

            // Show border guide around the target window
            if let element = self.monitoredElement,
               let windowFrame = self.getVisibleWindowFrame(for: element) {
                let msg2 = "🟢 Showing border guide with frame: \(windowFrame)"
                NSLog(msg2)
                logToDebugFile(msg2)

                // Use brown color (TextWarden logo color) for border guide
                let brownColor = NSColor(red: 139/255.0, green: 69/255.0, blue: 19/255.0, alpha: 1.0)
                self.borderGuide.showBorder(around: windowFrame, color: brownColor)
            } else {
                let msg3 = "🔴 Cannot show border guide - element=\(String(describing: self.monitoredElement))"
                NSLog(msg3)
                logToDebugFile(msg3)
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

            // Hide border guide
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
                    let msg = "🔴 FloatingErrorIndicator: Position changed to '\(newPosition)' - repositioning"
                    NSLog(msg)
                    logToDebugFile(msg)
                    self.positionIndicator(for: element)
                }
            }
            .store(in: &cancellables)
    }

    /// Update indicator with errors
    func update(errors: [GrammarErrorModel], element: AXUIElement, context: ApplicationContext?) {
        NSLog("🔴 FloatingErrorIndicator: update() called with \(errors.count) errors")
        self.errors = errors
        self.monitoredElement = element
        self.context = context

        guard !errors.isEmpty else {
            NSLog("🔴 FloatingErrorIndicator: No errors, hiding")
            hide()
            return
        }

        // Update indicator view
        indicatorView?.errorCount = errors.count
        indicatorView?.errorColor = colorForErrors(errors)
        indicatorView?.needsDisplay = true

        // Position in bottom-right of text field
        positionIndicator(for: element)

        // Show window without stealing focus
        NSLog("🔴 FloatingErrorIndicator: Window level: \(self.level.rawValue), isVisible: \(isVisible)")
        if !isVisible {
            NSLog("🔴 FloatingErrorIndicator: Calling order(.above)")
            order(.above, relativeTo: 0)  // Show window without stealing focus
            NSLog("🔴 FloatingErrorIndicator: After order(.above), isVisible: \(isVisible)")
        } else {
            NSLog("🔴 FloatingErrorIndicator: Window already visible")
        }
    }

    /// Hide indicator
    func hide() {
        orderOut(nil)
        borderGuide.hide()
        errors = []
        monitoredElement = nil
    }

    /// Handle drag end with free positioning
    private func handleDragEnd(at finalPosition: CGPoint) {
        guard let element = monitoredElement,
              let windowFrame = getVisibleWindowFrame(for: element),
              let bundleId = context?.bundleIdentifier else {
            NSLog("🔴 FloatingErrorIndicator: handleDragEnd - no window frame or bundle ID available")
            return
        }

        let indicatorSize: CGFloat = 40

        // Convert absolute position to percentage
        let percentagePos = IndicatorPositionStore.PercentagePosition.from(
            absolutePosition: finalPosition,
            in: windowFrame,
            indicatorSize: indicatorSize
        )

        // Save position for this application
        IndicatorPositionStore.shared.savePosition(percentagePos, for: bundleId)

        NSLog("🔴 FloatingErrorIndicator: Saved position for \(bundleId) at x=\(percentagePos.xPercent), y=\(percentagePos.yPercent)")
    }

    /// Position indicator based on per-app stored position or user preference
    private func positionIndicator(for element: AXUIElement) {
        // Try to get the actual visible window frame
        guard let visibleFrame = getVisibleWindowFrame(for: element) else {
            NSLog("🔴 FloatingErrorIndicator: Failed to get visible window frame, using screen corner")
            positionInScreenCorner()
            return
        }

        NSLog("🔴 FloatingErrorIndicator: Using visible window frame: \(visibleFrame)")

        let indicatorSize: CGFloat = 40

        // Check for per-app stored position first
        var percentagePos: IndicatorPositionStore.PercentagePosition?
        if let bundleId = context?.bundleIdentifier {
            percentagePos = IndicatorPositionStore.shared.getPosition(for: bundleId)
            if percentagePos != nil {
                NSLog("📍 FloatingErrorIndicator: Using stored position for \(bundleId)")
            }
        }

        // If no stored position, use default from preferences
        if percentagePos == nil {
            percentagePos = IndicatorPositionStore.shared.getDefaultPosition()
            NSLog("📍 FloatingErrorIndicator: Using default position from preferences")
        }

        // Convert percentage to absolute position
        let position = percentagePos!.toAbsolute(in: visibleFrame, indicatorSize: indicatorSize)
        let finalFrame = NSRect(x: position.x, y: position.y, width: indicatorSize, height: indicatorSize)

        NSLog("🔴 FloatingErrorIndicator: Positioning at \(finalFrame)")
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
        NSLog("🔴 FloatingErrorIndicator: Fallback positioning at screen corner: \(finalFrame)")

        setFrame(finalFrame, display: true)
    }

    /// Get the actual visible window frame using CGWindowListCopyWindowInfo
    /// This avoids the scrollback buffer issue with Terminal apps
    private func getVisibleWindowFrame(for element: AXUIElement) -> CGRect? {
        // Get the window's PID
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) != .success {
            NSLog("🔴 FloatingErrorIndicator: Failed to get PID from element")
            return nil
        }

        // Get all windows for this process
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            NSLog("🔴 FloatingErrorIndicator: Failed to get window list")
            return nil
        }

        // Find the frontmost window for this PID
        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == pid,
               let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {

                // Extract bounds
                let x = boundsDict["X"] ?? 0
                let y = boundsDict["Y"] ?? 0
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0

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
                    NSLog("🔴 FloatingErrorIndicator: No screen found")
                    return nil
                }

                // Convert from CGWindow coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
                // Use simple formula: cocoaY = totalScreenHeight - cgY - height
                let cocoaY = totalScreenHeight - y - height

                let frame = NSRect(x: x, y: cocoaY, width: width, height: height)
                let msg = "🔴 FloatingErrorIndicator: Window on screen '\(screen.localizedName)' at \(screen.frame) - CGWindow: (\(x), \(y)), Cocoa: \(frame)"
                NSLog(msg)
                logToDebugFile(msg)

                // DEBUG: Show debug boxes based on user preferences
                DispatchQueue.main.async {
                    DebugBorderWindow.clearAll()

                    // Show CGWindow coordinates (blue box) if enabled
                    if UserPreferences.shared.showDebugBorderCGWindowCoords {
                        let cgDisplayRect = NSRect(x: x, y: totalScreenHeight - y - height, width: width, height: height)
                        _ = DebugBorderWindow(frame: cgDisplayRect, color: .systemBlue, label: "CGWindow coords")
                    }

                    // Show Cocoa coordinates (green box) if enabled
                    if UserPreferences.shared.showDebugBorderCocoaCoords {
                        _ = DebugBorderWindow(frame: frame, color: .systemGreen, label: "Cocoa coords")
                    }
                }

                return frame
            }
        }

        NSLog("🔴 FloatingErrorIndicator: No matching window found in window list")
        return nil
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

        // Get the window's position and size
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
        NSLog("🔴 FloatingErrorIndicator: showErrors called with \(errors.count) errors")
        guard let firstError = errors.first else {
            NSLog("🔴 FloatingErrorIndicator: No errors to show")
            return
        }

        // Position popover inward from indicator based on position
        let indicatorFrame = frame
        let position = calculatePopoverPosition(for: indicatorFrame)

        NSLog("🔴 FloatingErrorIndicator: Showing popover at \(position)")
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

        // Add hover tracking
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

        // Add subtle shadow for depth (adapts to dark mode)
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
        let msg = "🔴 IndicatorView: mouseDown called at \(event.locationInWindow)"
        NSLog(msg)
        logToDebugFile(msg)

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

        // Get final position and snap it
        if let window = window {
            onDragEnd?(window.frame.origin)
        }

        // Redraw to show count instead of dots
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        NSLog("🔴 IndicatorView: mouseEntered")
        isHovered = true

        // Use open hand cursor to indicate draggability
        if !isDragging {
            NSCursor.openHand.push()
        }

        // Show popover after a short delay
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.onHover?(true)
        }

        // Redraw to update dot opacity
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        NSLog("🔴 IndicatorView: mouseExited")
        isHovered = false

        if !isDragging {
            NSCursor.pop()
        }

        // Cancel hover timer if mouse exits before delay
        hoverTimer?.invalidate()
        hoverTimer = nil

        // Hide popover
        onHover?(false)

        // Redraw to update dot opacity
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove old tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        // Add new tracking area with current bounds
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}
