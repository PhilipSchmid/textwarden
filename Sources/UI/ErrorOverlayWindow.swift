//
//  ErrorOverlayWindow.swift
//  Gnau
//
//  Transparent overlay window for drawing error underlines
//

import AppKit
import ApplicationServices

/// Manages a transparent overlay panel that draws error underlines
/// CRITICAL: Uses NSPanel to prevent activating the app
class ErrorOverlayWindow: NSPanel {
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

    /// Global event monitor for mouse movement
    private var mouseMonitor: Any?

    /// Callback when user hovers over an error (includes window frame for smart positioning)
    var onErrorHover: ((GrammarErrorModel, CGPoint, CGRect?) -> Void)?

    /// Callback when hover ends
    var onHoverEnd: (() -> Void)?

    init() {
        // Create transparent, non-activating panel
        // CRITICAL: Use .nonactivatingPanel to prevent Gnau from stealing focus
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        // Configure panel properties to prevent ANY focus stealing
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        // CRITICAL: Use .popUpMenu level - these windows NEVER activate the app
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // CRITICAL: Prevent this panel from affecting app activation
        self.hidesOnDeactivate = false
        self.worksWhenModal = false
        // CRITICAL: This makes the panel resist becoming the key window
        self.becomesKeyOnlyIfNeeded = true
        // CRITICAL: Set ignoresMouseEvents = TRUE to allow ALL clicks/events to pass through to Chrome
        // We'll use a global event monitor for hover detection instead of window's mouse tracking
        self.ignoresMouseEvents = true

        // Create underline view with click pass-through
        let view = UnderlineView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.allowsClickPassThrough = true  // Custom property to enable click pass-through
        self.contentView = view
        self.underlineView = view

        // Setup global mouse monitor for hover detection
        setupGlobalMouseMonitor()
    }

    /// Prevent window from becoming key (stealing focus)
    override var canBecomeKey: Bool {
        return false
    }

    /// Prevent window from becoming main (stealing focus)
    override var canBecomeMain: Bool {
        return false
    }

    /// Setup global mouse monitor for hover detection
    /// Uses NSEvent.addGlobalMonitorForEvents instead of NSTrackingArea
    /// because ignoresMouseEvents = true prevents tracking areas from working
    private func setupGlobalMouseMonitor() {
        // Monitor mouse moved events globally
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self else { return }

            // Only process if window is visible
            guard self.isCurrentlyVisible else { return }

            // Get mouse location in screen coordinates
            let mouseLocation = NSEvent.mouseLocation

            // Check if mouse is within our window bounds
            guard self.frame.contains(mouseLocation) else {
                // Mouse left the window - clear hover state
                if self.hoveredUnderline != nil {
                    self.hoveredUnderline = nil
                    self.underlineView?.hoveredUnderline = nil
                    self.underlineView?.needsDisplay = true
                    self.onHoverEnd?()
                }
                return
            }

            // Convert to window-local coordinates
            let windowOrigin = self.frame.origin
            let localPoint = CGPoint(
                x: mouseLocation.x - windowOrigin.x,
                y: mouseLocation.y - windowOrigin.y
            )

            let msg1 = "🖱️ ErrorOverlay: Global mouse at screen: \(mouseLocation), window-local: \(localPoint)"
            NSLog(msg1)
            self.logToDebugFile(msg1)

            // Check if hovering over any underline
            guard let underlineView = self.underlineView else { return }

            if let newHoveredUnderline = underlineView.underlines.first(where: { $0.bounds.contains(localPoint) }) {
                let msg2 = "📍 ErrorOverlay: Hovering over error at bounds: \(newHoveredUnderline.bounds)"
                NSLog(msg2)
                self.logToDebugFile(msg2)

                // Update hovered underline if changed
                if self.hoveredUnderline?.error.start != newHoveredUnderline.error.start ||
                   self.hoveredUnderline?.error.end != newHoveredUnderline.error.end {
                    self.hoveredUnderline = newHoveredUnderline
                    underlineView.hoveredUnderline = newHoveredUnderline
                    underlineView.needsDisplay = true
                }

                // Convert to screen coordinates for popup positioning
                let errorCenter = CGPoint(
                    x: newHoveredUnderline.bounds.midX,
                    y: newHoveredUnderline.bounds.midY
                )

                let screenLocation = CGPoint(
                    x: windowOrigin.x + errorCenter.x,
                    y: windowOrigin.y + errorCenter.y
                )

                let msg3 = "📍 ErrorOverlay: Popup position (screen): \(screenLocation)"
                NSLog(msg3)
                self.logToDebugFile(msg3)

                // Get the application window frame for smart positioning
                let appWindowFrame = self.getApplicationWindowFrame()

                self.onErrorHover?(newHoveredUnderline.error, screenLocation, appWindowFrame)
            } else {
                // Clear hovered state
                if self.hoveredUnderline != nil {
                    self.hoveredUnderline = nil
                    underlineView.hoveredUnderline = nil
                    underlineView.needsDisplay = true
                    self.onHoverEnd?()
                }
            }
        }

        let msg = "✅ ErrorOverlay: Global mouse monitor set up"
        NSLog(msg)
        logToDebugFile(msg)
    }

    /// Update overlay with new errors and monitored element
    /// Returns the number of underlines that were successfully created
    @discardableResult
    func update(errors: [GrammarErrorModel], element: AXUIElement, context: ApplicationContext?) -> Int {
        let msg1 = "🎨 ErrorOverlay: update() called with \(errors.count) errors"
        NSLog(msg1)
        logToDebugFile(msg1)
        self.errors = errors
        self.monitoredElement = element

        // Check if the parser wants to disable visual underlines
        let bundleID = context?.bundleIdentifier ?? "unknown"
        let parser = ContentParserFactory.shared.parser(for: bundleID)
        let msg = "🔍 ErrorOverlay: Using parser '\(parser.parserName)' for bundleID '\(bundleID)', disablesVisualUnderlines=\(parser.disablesVisualUnderlines)"
        NSLog(msg)
        logToDebugFile(msg)
        print(msg)  // Force print to console

        if parser.disablesVisualUnderlines {
            let msg2 = "⏭️ ErrorOverlay: Parser '\(parser.parserName)' disables visual underlines - skipping and showing floating indicator"
            NSLog(msg2)
            logToDebugFile(msg2)
            print(msg2)  // Force print to console
            hide()
            return 0
        }

        // Get element bounds
        // For Electron apps (like Slack), AX APIs return invalid bounds
        // Fall back to mouse cursor position as a workaround
        let elementFrame: CGRect
        if let frame = getElementFrame(element) {
            elementFrame = frame
            let msg = "📐 ErrorOverlay: Got element frame from AX API: \(elementFrame)"
            NSLog(msg)
            logToDebugFile(msg)
        } else {
            // Fallback: Use mouse cursor position (for Electron apps)
            let mouseLocation = NSEvent.mouseLocation
            // Create a reasonable-sized window area around the cursor
            elementFrame = CGRect(x: mouseLocation.x - 200, y: mouseLocation.y - 100, width: 800, height: 200)
            let msg2 = "⚠️ ErrorOverlay: Could not get element frame from AX API"
            NSLog(msg2)
            logToDebugFile(msg2)
            let msg3 = "📍 ErrorOverlay: Using mouse cursor fallback: \(elementFrame)"
            NSLog(msg3)
            logToDebugFile(msg3)
        }

        let msg2 = "📐 ErrorOverlay: Final element frame: \(elementFrame)"
        NSLog(msg2)
        logToDebugFile(msg2)

        // Position overlay window to match element
        setFrame(elementFrame, display: true)
        let msg3 = "✅ ErrorOverlay: Window positioned at \(elementFrame)"
        NSLog(msg3)
        logToDebugFile(msg3)

        // Calculate underline positions for each error
        let underlines = errors.compactMap { error -> ErrorUnderline? in
            let bounds: CGRect

            // Try to get bounds from AX API
            if let axBounds = getErrorBounds(for: error, in: element) {
                let msg = "🔍 ErrorOverlay: AX API returned bounds: \(axBounds)"
                NSLog(msg)
                logToDebugFile(msg)

                // Validate the bounds before using them
                // Pass bundle identifier so validator can apply app-specific rules
                if BoundsValidator.isPlausible(
                    axBounds,
                    context: "Error at \(error.start)-\(error.end)",
                    bundleIdentifier: context?.bundleIdentifier
                ) {
                    bounds = axBounds
                    let msg2 = "✅ ErrorOverlay: Using validated AX API bounds: \(bounds)"
                    NSLog(msg2)
                    logToDebugFile(msg2)
                } else {
                    // Bounds failed validation - try to estimate instead
                    let msg2 = "⚠️ ErrorOverlay: AX bounds failed validation, using fallback estimation"
                    NSLog(msg2)
                    logToDebugFile(msg2)
                    guard let estimatedBounds = estimateErrorBounds(for: error, in: element, elementFrame: elementFrame, context: context) else {
                        let msg3 = "⏭️ ErrorOverlay: Parser disabled visual underline for this error"
                        NSLog(msg3)
                        logToDebugFile(msg3)
                        return nil
                    }
                    bounds = estimatedBounds
                    let msg3 = "📍 ErrorOverlay: Estimated error bounds: \(bounds)"
                    NSLog(msg3)
                    logToDebugFile(msg3)
                }
            } else {
                // AX API didn't return bounds at all
                let msg = "❌ ErrorOverlay: AX API failed to get bounds for error at \(error.start)-\(error.end), using fallback"
                NSLog(msg)
                logToDebugFile(msg)
                guard let estimatedBounds = estimateErrorBounds(for: error, in: element, elementFrame: elementFrame, context: context) else {
                    let msg2 = "⏭️ ErrorOverlay: Parser disabled visual underline for this error"
                    NSLog(msg2)
                    logToDebugFile(msg2)
                    return nil
                }
                bounds = estimatedBounds
                let msg2 = "📍 ErrorOverlay: Estimated error bounds: \(bounds)"
                NSLog(msg2)
                logToDebugFile(msg2)
            }

            let msg4 = "📍 ErrorOverlay: Final error bounds (screen): \(bounds)"
            NSLog(msg4)
            logToDebugFile(msg4)

            // Convert to overlay-local coordinates
            let localBounds = convertToLocal(bounds, from: elementFrame)
            let msg5 = "📍 ErrorOverlay: Error bounds (local): \(localBounds)"
            NSLog(msg5)
            logToDebugFile(msg5)

            // Expand bounds downward to include the underline area
            // The underline is drawn below the text, so we need to extend the hit area
            let thickness = CGFloat(UserPreferences.shared.underlineThickness)
            let offset = max(2.0, thickness / 2.0)
            let expandedBounds = CGRect(
                x: localBounds.minX,
                y: localBounds.minY - offset - thickness - 2.0, // Extend down to include underline + extra padding
                width: localBounds.width,
                height: localBounds.height + offset + thickness + 2.0 // Increase height to cover underline area
            )
            let msg6 = "📍 ErrorOverlay: Expanded bounds for hit detection: \(expandedBounds)"
            NSLog(msg6)
            logToDebugFile(msg6)

            return ErrorUnderline(
                bounds: expandedBounds,
                drawingBounds: localBounds,
                color: underlineColor(for: error.category),
                error: error
            )
        }

        let msg7 = "🎨 ErrorOverlay: Created \(underlines.count) underlines"
        NSLog(msg7)
        logToDebugFile(msg7)

        underlineView?.underlines = underlines
        underlineView?.needsDisplay = true

        if !underlines.isEmpty {
            // Only order window if not already visible to avoid window ordering spam
            if !isCurrentlyVisible {
                let msg = "✅ ErrorOverlay: Showing overlay window (first time)"
                NSLog(msg)
                logToDebugFile(msg)
                // Use order(.above) instead of orderFrontRegardless() to avoid activating the app
                order(.above, relativeTo: 0)
                isCurrentlyVisible = true
            } else {
                let msg = "✅ ErrorOverlay: Updating overlay (already visible, not reordering)"
                NSLog(msg)
                logToDebugFile(msg)
            }
        } else {
            let msg = "⚠️ ErrorOverlay: No underlines - hiding"
            NSLog(msg)
            logToDebugFile(msg)
            hide()
        }

        return underlines.count
    }

    /// Hide overlay
    func hide() {
        if isCurrentlyVisible {
            orderOut(nil)
            isCurrentlyVisible = false
        }
        underlineView?.underlines = []

        // Clear hover state
        hoveredUnderline = nil
        underlineView?.hoveredUnderline = nil
    }

    /// Clean up resources
    deinit {
        // Remove global mouse monitor
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Log to debug file (same as GnauApp)
    private func logToDebugFile(_ message: String) {
        let logPath = "/tmp/gnau-debug.log"
        let timestamp = Date()
        let logMessage = "[\(timestamp)] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    /// Get the application window frame for smart popover positioning
    /// Returns the visible window frame if available
    private func getApplicationWindowFrame() -> CGRect? {
        guard let element = monitoredElement else { return nil }

        // Try to get the window frame using CGWindowListCopyWindowInfo (most reliable)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }

        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find the frontmost window for this PID
        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == pid,
               let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {

                let x = boundsDict["X"] ?? 0
                let y = boundsDict["Y"] ?? 0
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0

                // Convert from Quartz (top-left origin) to Cocoa (bottom-left origin)
                if let screen = NSScreen.main {
                    let screenHeight = screen.frame.height
                    let cocoaY = screenHeight - y - height

                    let frame = NSRect(x: x, y: cocoaY, width: width, height: height)
                    let msg = "🪟 ErrorOverlay: Got application window frame: \(frame)"
                    NSLog(msg)
                    logToDebugFile(msg)
                    return frame
                }
            }
        }

        return nil
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

        var frame = CGRect(origin: position, size: size)

        // CRITICAL: AX API returns coordinates in top-left origin system (Quartz)
        // NSWindow uses bottom-left origin (AppKit)
        // Must flip Y coordinate using screen height
        if let screenHeight = NSScreen.main?.frame.height {
            frame.origin.y = screenHeight - frame.origin.y - frame.height
        }

        return frame
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

        guard success else { return nil }

        // CRITICAL: AX API returns coordinates in top-left origin system (Quartz)
        // NSWindow uses bottom-left origin (AppKit)
        // Must flip Y coordinate using screen height
        if let screenHeight = NSScreen.main?.frame.height {
            rect.origin.y = screenHeight - rect.origin.y - rect.height
        }

        return rect
    }

    /// Estimate error bounds when AX API fails (Electron apps fallback)
    /// Uses ContentParser architecture for app-specific bounds calculation
    /// Returns nil if the parser explicitly disables visual underlines
    private func estimateErrorBounds(for error: GrammarErrorModel, in element: AXUIElement, elementFrame: CGRect, context: ApplicationContext?) -> CGRect? {
        // Get the full text content
        var textValue: CFTypeRef?
        let textError = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        )

        guard textError == .success, let fullText = textValue as? String else {
            let msg = "⚠️ ErrorOverlay: Could not get text for measurement, using simple fallback"
            NSLog(msg)
            logToDebugFile(msg)
            return simpleFallbackBounds(for: error, elementFrame: elementFrame, context: context)
        }

        // Extract the text before and at the error position
        let safeStart = min(error.start, fullText.count)
        let safeEnd = min(error.end, fullText.count)

        // CRITICAL FIX: Find the start of the current line
        // In multiline text fields (like Slack), we need to measure text only from the
        // start of the current line, not from the beginning of the entire text field
        let textUpToError = String(fullText.prefix(safeStart))
        let lineStart: Int
        if let lastNewlineIndex = textUpToError.lastIndex(of: "\n") {
            lineStart = fullText.distance(from: fullText.startIndex, to: lastNewlineIndex) + 1
        } else {
            lineStart = 0
        }

        // Extract only the text on the current line before the error
        let textBeforeError = String(fullText[fullText.index(fullText.startIndex, offsetBy: lineStart)..<fullText.index(fullText.startIndex, offsetBy: safeStart)])
        let errorText = String(fullText[fullText.index(fullText.startIndex, offsetBy: safeStart)..<fullText.index(fullText.startIndex, offsetBy: safeEnd)])

        let lineMsg = "📏 ErrorOverlay: Multiline handling - lineStart: \(lineStart), textOnLine: '\(textBeforeError)', error: '\(errorText)'"
        NSLog(lineMsg)
        logToDebugFile(lineMsg)

        // USE CONTENT PARSER ARCHITECTURE
        // Get app-specific parser from factory
        let bundleID = context?.bundleIdentifier ?? "unknown"
        let parser = ContentParserFactory.shared.parser(for: bundleID)

        // Create error range
        let errorRange = NSRange(location: safeStart, length: safeEnd - safeStart)

        // Ask parser to adjust bounds with app-specific logic
        if let adjustedBounds = parser.adjustBounds(
            element: element,
            errorRange: errorRange,
            textBeforeError: textBeforeError,
            errorText: errorText,
            fullText: fullText
        ) {
            // Convert position to CGRect format expected by overlay
            let estimatedX = adjustedBounds.position.x
            let estimatedWidth = adjustedBounds.errorWidth

            // Constrain to element bounds
            let maxX = elementFrame.maxX - 10.0
            let clampedWidth: CGFloat
            if estimatedX + estimatedWidth > maxX {
                clampedWidth = max(20.0, maxX - estimatedX)
            } else {
                clampedWidth = estimatedWidth
            }

            // Position vertically in the middle of the text area
            let estimatedY = elementFrame.origin.y + (elementFrame.height * 0.25)
            let estimatedHeight = elementFrame.height * 0.5

            let estimatedBounds = CGRect(
                x: estimatedX,
                y: estimatedY,
                width: clampedWidth,
                height: estimatedHeight
            )

            let msg = "📐 ErrorOverlay: ContentParser (\(parser.parserName)) bounds - confidence: \(adjustedBounds.confidence), context: \(adjustedBounds.uiContext ?? "none")"
            NSLog(msg)
            logToDebugFile(msg)
            let msg2 = "📐 ErrorOverlay: \(adjustedBounds.debugInfo)"
            NSLog(msg2)
            logToDebugFile(msg2)
            let msg3 = "📐 ErrorOverlay: Final bounds at \(error.start)-\(error.end): \(estimatedBounds)"
            NSLog(msg3)
            logToDebugFile(msg3)

            return estimatedBounds
        }

        // Parser explicitly returned nil - this means the parser wants to disable visual underlines
        // (e.g., for terminals where positioning is unreliable)
        Logger.debug("ContentParser returned nil for \(bundleID) - disabling visual underline")
        return nil
    }

    /// Simple fallback when we can't measure text
    private func simpleFallbackBounds(for error: GrammarErrorModel, elementFrame: CGRect, context: ApplicationContext?) -> CGRect {
        let averageCharWidth: CGFloat = 9.0
        let leftPadding = context?.estimatedLeftPadding ?? 16.0
        let errorLength = error.end - error.start

        let estimatedX = elementFrame.origin.x + leftPadding + (CGFloat(error.start) * averageCharWidth)
        let estimatedWidth = max(20.0, CGFloat(errorLength) * averageCharWidth)

        let maxX = elementFrame.maxX - 10.0
        let clampedWidth = (estimatedX + estimatedWidth > maxX) ? max(20.0, maxX - estimatedX) : estimatedWidth

        let estimatedY = elementFrame.origin.y + (elementFrame.height * 0.25)
        let estimatedHeight = elementFrame.height * 0.5

        return CGRect(x: estimatedX, y: estimatedY, width: clampedWidth, height: estimatedHeight)
    }

    /// Convert screen coordinates to overlay-local coordinates
    private func convertToLocal(_ screenBounds: CGRect, from elementFrame: CGRect) -> CGRect {
        // Both screen and window use bottom-left origin, so simple subtraction
        let localX = screenBounds.origin.x - elementFrame.origin.x
        let localY = screenBounds.origin.y - elementFrame.origin.y

        let msg1 = "📐 ConvertToLocal: Screen bounds: \(screenBounds), Element frame: \(elementFrame), Local X: \(localX), Local Y: \(localY)"
        NSLog(msg1)
        logToDebugFile(msg1)

        return CGRect(
            x: localX,
            y: localY,
            width: screenBounds.width,
            height: screenBounds.height
        )
    }

    /// Get underline color for category (high-level categorization)
    private func underlineColor(for category: String) -> NSColor {
        // Group categories into high-level color categories
        switch category {
        // Spelling and typos: Red (critical, obvious errors)
        case "Spelling", "Typo":
            return NSColor.systemRed

        // Grammar and structure: Orange (grammatical correctness)
        case "Grammar", "Agreement", "BoundaryError", "Capitalization", "Nonstandard", "Punctuation":
            return NSColor.systemOrange

        // Style and enhancement: Blue (style improvements)
        case "Style", "Enhancement", "WordChoice", "Readability", "Redundancy", "Formatting":
            return NSColor.systemBlue

        // Usage and word choice issues: Purple
        case "Usage", "Eggcorn", "Malapropism", "Regionalism", "Repetition":
            return NSColor.systemPurple

        // Miscellaneous: Gray (fallback)
        default:
            return NSColor.systemGray
        }
    }

}

// MARK: - Error Underline Model

struct ErrorUnderline {
    let bounds: CGRect // Bounds for hit detection (expanded to include underline area)
    let drawingBounds: CGRect // Original bounds for drawing position
    let color: NSColor
    let error: GrammarErrorModel
}

// MARK: - Underline View

class UnderlineView: NSView {
    var underlines: [ErrorUnderline] = []
    var hoveredUnderline: ErrorUnderline?
    var allowsClickPassThrough: Bool = false

    // CRITICAL: Override hitTest to return nil, which passes clicks through to the app below
    // This allows Chrome (or other apps) to receive clicks while we still track mouse movement
    override func hitTest(_ point: NSPoint) -> NSView? {
        if allowsClickPassThrough {
            return nil  // Pass all clicks through to the app below
        }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Clear background
        context.clear(bounds)

        // Draw highlight for hovered underline first (behind the underlines)
        if let hovered = hoveredUnderline {
            drawHighlight(in: context, bounds: hovered.drawingBounds, color: hovered.color)
        }

        // Draw each underline
        for underline in underlines {
            drawWavyUnderline(in: context, bounds: underline.drawingBounds, color: underline.color)
        }
    }

    /// Draw straight underline
    private func drawWavyUnderline(in context: CGContext, bounds: CGRect, color: NSColor) {
        context.setStrokeColor(color.cgColor)

        // Get user's preferred thickness from preferences
        let thickness = CGFloat(UserPreferences.shared.underlineThickness)
        context.setLineWidth(thickness)

        // Draw straight line below the text
        // In bottom-left origin system: minY is bottom, maxY is top
        // Position the line below the text, offset by thickness to avoid covering text
        let offset = max(2.0, thickness / 2.0) // Minimum 2pt offset, or half thickness
        let y = bounds.minY - offset

        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.minX, y: y))
        path.addLine(to: CGPoint(x: bounds.maxX, y: y))

        context.addPath(path)
        context.strokePath()
    }

    /// Draw highlight background for hovered error
    private func drawHighlight(in context: CGContext, bounds: CGRect, color: NSColor) {
        // Draw a more intense background highlight with better dark/light mode contrast
        // Use higher opacity for better visibility
        let highlightOpacity: CGFloat

        // Check if we're in dark mode for better contrast
        if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]),
           appearance == .darkAqua {
            // Dark mode: use lighter/brighter highlight with higher opacity
            highlightOpacity = 0.35
        } else {
            // Light mode: use more saturated highlight with good opacity
            highlightOpacity = 0.30
        }

        context.setFillColor(color.withAlphaComponent(highlightOpacity).cgColor)
        context.fill(bounds)
    }
}
