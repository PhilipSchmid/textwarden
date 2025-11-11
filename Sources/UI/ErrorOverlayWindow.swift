//
//  ErrorOverlayWindow.swift
//  Gnau
//
//  Transparent overlay window for drawing error underlines
//

import AppKit
import ApplicationServices

/// Manages a transparent overlay window that draws error underlines
class ErrorOverlayWindow: NSWindow {
    /// Current errors to display
    private var errors: [GrammarErrorModel] = []

    /// The monitored text element
    private var monitoredElement: AXUIElement?

    /// Underline view
    private var underlineView: UnderlineView?

    /// Currently hovered error underline
    private var hoveredUnderline: ErrorUnderline?

    /// Track if window is currently visible
    private var isCurrentlyVisible = false

    /// Callback when user hovers over an error
    var onErrorHover: ((GrammarErrorModel, CGPoint) -> Void)?

    /// Callback when hover ends
    var onHoverEnd: (() -> Void)?

    init() {
        // Create transparent, borderless window
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Configure window properties
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false // Need to detect hover

        // Create underline view
        let view = UnderlineView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        self.contentView = view
        self.underlineView = view

        // Setup mouse tracking
        setupMouseTracking()
    }

    /// Setup mouse tracking for hover detection
    private func setupMouseTracking() {
        guard let contentView = contentView else { return }

        let trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(trackingArea)
    }

    /// Update overlay with new errors and monitored element
    func update(errors: [GrammarErrorModel], element: AXUIElement) {
        print("🎨 ErrorOverlay: update() called with \(errors.count) errors")
        self.errors = errors
        self.monitoredElement = element

        // Get element bounds
        guard let elementFrame = getElementFrame(element) else {
            print("⚠️ ErrorOverlay: Could not get element frame - hiding")
            hide()
            return
        }

        print("📐 ErrorOverlay: Element frame: \(elementFrame)")

        // Position overlay window to match element
        setFrame(elementFrame, display: true)
        print("✅ ErrorOverlay: Window positioned at \(elementFrame)")

        // Calculate underline positions for each error
        let underlines = errors.compactMap { error -> ErrorUnderline? in
            guard let bounds = getErrorBounds(for: error, in: element) else {
                print("⚠️ ErrorOverlay: Could not get bounds for error at \(error.start)-\(error.end)")
                return nil
            }

            print("📍 ErrorOverlay: Error bounds (screen): \(bounds)")

            // Convert to overlay-local coordinates
            let localBounds = convertToLocal(bounds, from: elementFrame)
            print("📍 ErrorOverlay: Error bounds (local): \(localBounds)")

            return ErrorUnderline(
                bounds: localBounds,
                color: underlineColor(for: error.severity),
                error: error
            )
        }

        print("🎨 ErrorOverlay: Created \(underlines.count) underlines")

        underlineView?.underlines = underlines
        underlineView?.needsDisplay = true

        if !underlines.isEmpty {
            // Only order window if not already visible to avoid window ordering spam
            if !isCurrentlyVisible {
                print("✅ ErrorOverlay: Showing overlay window (first time)")
                orderFrontRegardless()
                isCurrentlyVisible = true
            } else {
                print("✅ ErrorOverlay: Updating overlay (already visible, not reordering)")
            }
        } else {
            print("⚠️ ErrorOverlay: No underlines - hiding")
            hide()
        }
    }

    /// Hide overlay
    func hide() {
        if isCurrentlyVisible {
            orderOut(nil)
            isCurrentlyVisible = false
        }
        underlineView?.underlines = []
    }

    /// Get frame of AX element
    private func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let positionResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )

        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard positionResult == .success,
              sizeResult == .success,
              let positionValue = positionValue,
              let sizeValue = sizeValue else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    /// Get bounds for specific error range
    private func getErrorBounds(for error: GrammarErrorModel, in element: AXUIElement) -> CGRect? {
        let location = error.start
        let length = error.end - error.start

        var range = CFRange(location: location, length: max(1, length))
        let rangeValue = AXValueCreate(.cfRange, &range)!

        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard boundsError == .success,
              let axValue = boundsValue,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        let success = AXValueGetValue(axValue as! AXValue, .cgRect, &rect)

        return success ? rect : nil
    }

    /// Convert screen coordinates to overlay-local coordinates
    private func convertToLocal(_ screenBounds: CGRect, from elementFrame: CGRect) -> CGRect {
        // Both screen and window use bottom-left origin, so simple subtraction
        let localX = screenBounds.origin.x - elementFrame.origin.x
        let localY = screenBounds.origin.y - elementFrame.origin.y

        print("📐 ConvertToLocal:")
        print("   Screen bounds: \(screenBounds)")
        print("   Element frame: \(elementFrame)")
        print("   Local X: \(localX), Local Y: \(localY)")

        return CGRect(
            x: localX,
            y: localY,
            width: screenBounds.width,
            height: screenBounds.height
        )
    }

    /// Get underline color for severity
    private func underlineColor(for severity: GrammarErrorSeverity) -> NSColor {
        switch severity {
        case .error:
            return NSColor.systemRed      // Red for critical errors
        case .warning:
            return NSColor.systemOrange   // Orange for warnings
        case .info:
            return NSColor.systemBlue     // Blue for suggestions
        }
    }

    /// Handle mouse movement for hover detection
    override func mouseMoved(with event: NSEvent) {
        guard let underlineView = underlineView else { return }

        let location = event.locationInWindow
        print("🖱️ ErrorOverlay: Mouse at window coords: \(location)")

        // Check if hovering over any underline
        if let newHoveredUnderline = underlineView.underlines.first(where: { $0.bounds.contains(location) }) {
            print("📍 ErrorOverlay: Hovering over error at bounds: \(newHoveredUnderline.bounds)")

            // Update hovered underline if changed
            if hoveredUnderline?.error.start != newHoveredUnderline.error.start ||
               hoveredUnderline?.error.end != newHoveredUnderline.error.end {
                hoveredUnderline = newHoveredUnderline
                underlineView.hoveredUnderline = newHoveredUnderline
                underlineView.needsDisplay = true
            }

            // Convert to screen coordinates for popup positioning
            // Get the error's bounds center point for better popup positioning
            let errorCenter = CGPoint(
                x: newHoveredUnderline.bounds.midX,
                y: newHoveredUnderline.bounds.midY
            )

            print("📍 ErrorOverlay: Error center (window coords): \(errorCenter)")

            // Convert window coordinates to screen coordinates
            let windowOrigin = self.frame.origin
            let screenLocation = CGPoint(
                x: windowOrigin.x + errorCenter.x,
                y: windowOrigin.y + errorCenter.y
            )

            print("📍 ErrorOverlay: Window origin (screen): \(windowOrigin)")
            print("📍 ErrorOverlay: Popup position (screen): \(screenLocation)")

            onErrorHover?(newHoveredUnderline.error, screenLocation)
        } else {
            // Clear hovered state
            if hoveredUnderline != nil {
                hoveredUnderline = nil
                underlineView.hoveredUnderline = nil
                underlineView.needsDisplay = true
            }
            onHoverEnd?()
        }
    }

    /// Handle mouse exit
    override func mouseExited(with event: NSEvent) {
        // Clear hovered state
        if hoveredUnderline != nil {
            hoveredUnderline = nil
            underlineView?.hoveredUnderline = nil
            underlineView?.needsDisplay = true
        }
        onHoverEnd?()
    }
}

// MARK: - Error Underline Model

struct ErrorUnderline {
    let bounds: CGRect
    let color: NSColor
    let error: GrammarErrorModel
}

// MARK: - Underline View

class UnderlineView: NSView {
    var underlines: [ErrorUnderline] = []
    var hoveredUnderline: ErrorUnderline?

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Clear background
        context.clear(bounds)

        // Draw highlight for hovered underline first (behind the underlines)
        if let hovered = hoveredUnderline {
            drawHighlight(in: context, bounds: hovered.bounds, color: hovered.color)
        }

        // Draw each underline
        for underline in underlines {
            drawWavyUnderline(in: context, bounds: underline.bounds, color: underline.color)
        }
    }

    /// Draw straight underline
    private func drawWavyUnderline(in context: CGContext, bounds: CGRect, color: NSColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.0)

        // Draw straight line at bottom of bounds
        let y = bounds.maxY - 2 // Position at bottom of text

        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.minX, y: y))
        path.addLine(to: CGPoint(x: bounds.maxX, y: y))

        context.addPath(path)
        context.strokePath()
    }

    /// Draw highlight background for hovered error
    private func drawHighlight(in context: CGContext, bounds: CGRect, color: NSColor) {
        // Draw a semi-transparent background highlight
        context.setFillColor(color.withAlphaComponent(0.15).cgColor)
        context.fill(bounds)
    }
}
