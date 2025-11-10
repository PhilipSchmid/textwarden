//
//  ErrorOverlayWindow.swift
//  Gnau
//
//  Transparent overlay window for drawing error underlines
//  Inspired by (redacted) and (redacted)'s visual feedback
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
            print("✅ ErrorOverlay: Showing overlay window")
            orderFrontRegardless()
        } else {
            print("⚠️ ErrorOverlay: No underlines - hiding")
            hide()
        }
    }

    /// Hide overlay
    func hide() {
        orderOut(nil)
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
        return CGRect(
            x: screenBounds.origin.x - elementFrame.origin.x,
            y: screenBounds.origin.y - elementFrame.origin.y,
            width: screenBounds.width,
            height: screenBounds.height
        )
    }

    /// Get underline color for severity ((redacted) style)
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

        // Check if hovering over any underline
        if let hoveredUnderline = underlineView.underlines.first(where: { $0.bounds.contains(location) }) {
            // Convert to screen coordinates for popup positioning
            let screenLocation = convertPoint(toScreen: location)
            onErrorHover?(hoveredUnderline.error, screenLocation)
        } else {
            onHoverEnd?()
        }
    }

    /// Handle mouse exit
    override func mouseExited(with event: NSEvent) {
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

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Clear background
        context.clear(bounds)

        // Draw each underline
        for underline in underlines {
            drawWavyUnderline(in: context, bounds: underline.bounds, color: underline.color)
        }
    }

    /// Draw wavy underline ((redacted)/(redacted) style)
    private func drawWavyUnderline(in context: CGContext, bounds: CGRect, color: NSColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.0)

        // Draw wavy line at bottom of bounds
        let y = bounds.minY + 2 // Slight offset from bottom
        let waveHeight: CGFloat = 2.0
        let waveLength: CGFloat = 4.0

        let path = CGMutablePath()
        var x = bounds.minX
        path.move(to: CGPoint(x: x, y: y))

        while x < bounds.maxX {
            x += waveLength / 2
            path.addLine(to: CGPoint(x: min(x, bounds.maxX), y: y + waveHeight))
            x += waveLength / 2
            path.addLine(to: CGPoint(x: min(x, bounds.maxX), y: y))
        }

        context.addPath(path)
        context.strokePath()
    }
}
