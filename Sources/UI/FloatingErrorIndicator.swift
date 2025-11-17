//
//  FloatingErrorIndicator.swift
//  Gnau
//
//  Floating error indicator ((redacted)-style)
//  Shows a small circular badge in the bottom-right corner of text fields
//

import Cocoa
import AppKit
import Combine

/// Floating error indicator window (like (redacted)'s badge)
class FloatingErrorIndicator: NSWindow {
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

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Create a small circular window
        let initialFrame = NSRect(x: 0, y: 0, width: 40, height: 40)

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless],
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
        self.indicatorView = indicatorView
        self.contentView = indicatorView

        // Listen to indicator position changes for immediate repositioning
        setupPositionObserver()
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

        // Show window
        NSLog("🔴 FloatingErrorIndicator: Window level: \(self.level.rawValue), isVisible: \(isVisible)")
        if !isVisible {
            NSLog("🔴 FloatingErrorIndicator: Calling orderFront")
            orderFront(nil)
            makeKeyAndOrderFront(nil)  // Force to front
            NSLog("🔴 FloatingErrorIndicator: After orderFront, isVisible: \(isVisible)")
        } else {
            NSLog("🔴 FloatingErrorIndicator: Window already visible")
        }
    }

    /// Hide indicator
    func hide() {
        orderOut(nil)
        errors = []
        monitoredElement = nil
    }

    /// Position indicator based on user preference
    private func positionIndicator(for element: AXUIElement) {
        // For terminals, the AX window frame often includes scrollback buffer
        // which can be huge (thousands of pixels). Use screen bounds instead
        // to ensure reliable positioning, similar to (redacted).

        // Try to get the actual visible window frame using NSWindow if possible
        if let visibleFrame = getVisibleWindowFrame(for: element) {
            NSLog("🔴 FloatingErrorIndicator: Using visible window frame: \(visibleFrame)")

            let padding: CGFloat = 10
            let indicatorSize: CGFloat = 40
            let position = UserPreferences.shared.indicatorPosition

            let (x, y) = calculatePosition(
                for: position,
                in: visibleFrame,
                indicatorSize: indicatorSize,
                padding: padding
            )

            let finalFrame = NSRect(x: x, y: y, width: indicatorSize, height: indicatorSize)
            NSLog("🔴 FloatingErrorIndicator: Positioning at \(finalFrame)")

            setFrame(finalFrame, display: true)
        } else {
            NSLog("🔴 FloatingErrorIndicator: Failed to get visible window frame, using screen corner")
            positionInScreenCorner()
        }
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

                // CGWindowListCopyWindowInfo returns screen coordinates with y=0 at TOP
                // Convert to Cocoa coordinates where y=0 is at BOTTOM
                if let screen = NSScreen.main {
                    let screenHeight = screen.frame.height
                    let cocoaY = screenHeight - y - height

                    let frame = NSRect(x: x, y: cocoaY, width: width, height: height)
                    NSLog("🔴 FloatingErrorIndicator: Found visible window - CGWindow bounds: (\(x), \(y), \(width), \(height)), Cocoa coords: \(frame)")
                    return frame
                }
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

    private var hoverTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // Add click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(clickGesture)

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

        // Draw circular background
        let circlePath = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        errorColor.setFill()
        circlePath.fill()

        // Draw white border
        NSColor.white.setStroke()
        circlePath.lineWidth = 2
        circlePath.stroke()

        // Draw error count
        let countString = "\(errorCount)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (countString as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2 + 1,  // Slight offset for visual balance
            width: textSize.width,
            height: textSize.height
        )
        (countString as NSString).draw(in: textRect, withAttributes: attributes)
    }

    @objc private func handleClick() {
        NSLog("🔴 IndicatorView: handleClick called")
        onClicked?()
    }

    override func mouseDown(with event: NSEvent) {
        NSLog("🔴 IndicatorView: mouseDown called")
        onClicked?()
    }

    override func mouseEntered(with event: NSEvent) {
        NSLog("🔴 IndicatorView: mouseEntered")
        NSCursor.pointingHand.push()

        // Show popover after a short delay
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.onHover?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSLog("🔴 IndicatorView: mouseExited")
        NSCursor.pop()

        // Cancel hover timer if mouse exits before delay
        hoverTimer?.invalidate()
        hoverTimer = nil

        // Hide popover
        onHover?(false)
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
