//
//  ErrorOverlayWindow.swift
//  TextWarden
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
        // CRITICAL: Use .nonactivatingPanel to prevent TextWarden from stealing focus
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        // Configure panel properties to prevent ANY focus stealing
        self.isOpaque = false
        // DEBUG: Clear background - border and label shown in UnderlineView
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
        // DEBUG: Temporarily enable mouse events to allow window dragging for debugging
        // TODO: Re-enable ignoresMouseEvents after debugging window sizing issues
        self.ignoresMouseEvents = false
        self.isMovableByWindowBackground = true

        let view = UnderlineView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.allowsClickPassThrough = true  // Custom property to enable click pass-through
        self.contentView = view
        self.underlineView = view

        // Setup global mouse monitor for hover detection
        setupGlobalMouseMonitor()
    }

    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }

    private func setupGlobalMouseMonitor() {
        // Monitor mouse moved events globally
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self else { return }

            // Only process if window is visible
            guard self.isCurrentlyVisible else { return }

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

            Logger.debug("ErrorOverlay: Global mouse at screen: \(mouseLocation), window-local: \(localPoint)", category: Logger.ui)

            // Check if hovering over any underline
            guard let underlineView = self.underlineView else { return }

            if let newHoveredUnderline = underlineView.underlines.first(where: { $0.bounds.contains(localPoint) }) {
                Logger.debug("ErrorOverlay: Hovering over error at bounds: \(newHoveredUnderline.bounds)", category: Logger.ui)

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

                Logger.debug("ErrorOverlay: Popup position (screen): \(screenLocation)", category: Logger.ui)

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

        Logger.debug("ErrorOverlay: Global mouse monitor set up", category: Logger.ui)
    }

    /// Update overlay with new errors and monitored element
    /// Returns the number of underlines that were successfully created
    @discardableResult
    func update(errors: [GrammarErrorModel], element: AXUIElement, context: ApplicationContext?) -> Int {
        Logger.debug("ErrorOverlay: update() called with \(errors.count) errors", category: Logger.ui)
        self.errors = errors
        self.monitoredElement = element

        // Check if the parser wants to disable visual underlines
        let bundleID = context?.bundleIdentifier ?? "unknown"
        let parser = ContentParserFactory.shared.parser(for: bundleID)
        let msg = "ErrorOverlay: Using parser '\(parser.parserName)' for bundleID '\(bundleID)', disablesVisualUnderlines=\(parser.disablesVisualUnderlines)"
        Logger.debug(msg, category: Logger.ui)
        print(msg)  // Force print to console

        if parser.disablesVisualUnderlines {
            let msg2 = "ErrorOverlay: Parser '\(parser.parserName)' disables visual underlines - skipping and showing floating indicator"
            Logger.debug(msg2, category: Logger.ui)
            print(msg2)  // Force print to console
            hide()
            return 0
        }

        // Use text field element's AX bounds (not window bounds!)
        // The element passed is the actual text field, so we want ITS bounds
        let elementFrame: CGRect

        // Strategy 1: Try AX API to get text field bounds
        if let frame = getElementFrame(element) {
            elementFrame = frame
            Logger.debug("ErrorOverlay: Got text field bounds from AX API: \(elementFrame)", category: Logger.ui)
        }
        // Strategy 2: Last resort - mouse cursor position
        else {
            let mouseLocation = NSEvent.mouseLocation
            elementFrame = CGRect(x: mouseLocation.x - 200, y: mouseLocation.y - 100, width: 800, height: 200)
            Logger.debug("ErrorOverlay: AX API failed for text field bounds", category: Logger.ui)
            Logger.debug("ErrorOverlay: Using mouse cursor fallback: \(elementFrame)", category: Logger.ui)
        }

        Logger.debug("ErrorOverlay: Final element frame: \(elementFrame)", category: Logger.ui)

        Logger.debug("DEBUG: Element frame details - X: \(elementFrame.origin.x), Y: \(elementFrame.origin.y), Width: \(elementFrame.width), Height: \(elementFrame.height)", category: Logger.ui)

        // Position overlay window to match element
        setFrame(elementFrame, display: true)
        Logger.debug("ErrorOverlay: Window positioned at \(elementFrame)", category: Logger.ui)

        Logger.debug("DEBUG: Actual window frame after setFrame - \(self.frame)", category: Logger.ui)

        // Extract full text once for all positioning calculations
        var textValue: CFTypeRef?
        let textError = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        )

        guard textError == .success, let fullText = textValue as? String else {
            Logger.debug("ErrorOverlay: Could not extract text from element for positioning", category: Logger.ui)
            hide()
            return 0
        }

        // Calculate underline positions for each error using new positioning system
        let underlines = errors.compactMap { error -> ErrorUnderline? in
            let errorRange = NSRange(location: error.start, length: error.end - error.start)

            // Use new multi-strategy positioning system
            Logger.debug("BEFORE calling parser.resolvePosition() - parser type: \(type(of: parser)), parserName: \(parser.parserName)", category: Logger.ui)
            let geometryResult = parser.resolvePosition(
                for: errorRange,
                in: element,
                text: fullText
            )

            Logger.debug("ErrorOverlay: PositionResolver returned bounds: \(geometryResult.bounds), strategy: \(geometryResult.strategy), confidence: \(geometryResult.confidence)", category: Logger.ui)

            // Check if result is usable
            guard geometryResult.isUsable else {
                Logger.debug("ErrorOverlay: Position result not usable (confidence: \(geometryResult.confidence))", category: Logger.ui)
                return nil
            }

            let bounds = geometryResult.bounds

            Logger.debug("ErrorOverlay: Final error bounds (screen): \(bounds)", category: Logger.ui)

            // getElementFrame() returns Quartz coordinates (top-left origin)
            // NSPanel.setFrame() works directly with Quartz in multi-monitor setups
            Logger.debug("ErrorOverlay: Element frame (Quartz): \(elementFrame)", category: Logger.ui)

            // Convert to overlay-local coordinates
            let localBounds = convertToLocal(bounds, from: elementFrame)
            Logger.debug("ErrorOverlay: Error bounds (local): \(localBounds)", category: Logger.ui)

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
            Logger.debug("ErrorOverlay: Expanded bounds for hit detection: \(expandedBounds)", category: Logger.ui)

            return ErrorUnderline(
                bounds: expandedBounds,
                drawingBounds: localBounds,
                color: underlineColor(for: error.category),
                error: error
            )
        }

        Logger.debug("ErrorOverlay: Created \(underlines.count) underlines", category: Logger.ui)

        underlineView?.underlines = underlines
        underlineView?.needsDisplay = true

        if !underlines.isEmpty {
            // Only order window if not already visible to avoid window ordering spam
            if !isCurrentlyVisible {
                Logger.debug("ErrorOverlay: Showing overlay window (first time)", category: Logger.ui)
                // Use order(.above) instead of orderFrontRegardless() to avoid activating the app
                order(.above, relativeTo: 0)
                isCurrentlyVisible = true
            } else {
                Logger.debug("ErrorOverlay: Updating overlay (already visible, not reordering)", category: Logger.ui)
            }
        } else {
            Logger.debug("ErrorOverlay: No underlines - hiding", category: Logger.ui)
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
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Log to debug file (same as TextWardenApp)
    private func logToDebugFile(_ message: String) {
        let logPath = "/tmp/textwarden-debug.log"
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
        Logger.debug("ErrorOverlay: getApplicationWindowFrame() called", category: Logger.ui)

        guard let element = monitoredElement else {
            Logger.debug("ErrorOverlay: getApplicationWindowFrame() - no monitoredElement", category: Logger.ui)
            return nil
        }

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        guard pidResult == .success, pid > 0 else {
            Logger.debug("ErrorOverlay: Could not get PID from element (result: \(pidResult.rawValue))", category: Logger.ui)
            return nil
        }

        Logger.debug("ErrorOverlay: Got PID \(pid) from element", category: Logger.ui)

        // Try Method 1: CGWindow API (most reliable for regular apps)
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]

        if let windowList = windowList {
            Logger.debug("ErrorOverlay: Got \(windowList.count) windows from CGWindowListCopyWindowInfo", category: Logger.ui)

            // Find windows belonging to the monitored app's PID
            let appWindows = windowList.filter { dict in
                guard let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32 else { return false }
                return ownerPID == pid
            }

            Logger.debug("ErrorOverlay: Found \(appWindows.count) windows for PID \(pid)", category: Logger.ui)

            // Find the frontmost window (layer 0)
            if let frontWindow = appWindows.first(where: { dict in
                (dict[kCGWindowLayer as String] as? Int) == 0
            }) {
                if let boundsDict = frontWindow[kCGWindowBounds as String] as? [String: CGFloat],
                   let x = boundsDict["X"],
                   let y = boundsDict["Y"],
                   let width = boundsDict["Width"],
                   let height = boundsDict["Height"] {

                    // CGWindow coordinates are in Quartz (top-left origin)
                    // Convert to Cocoa (bottom-left origin)
                    if let screen = NSScreen.main {
                        let screenHeight = screen.frame.height
                        let cocoaY = screenHeight - y - height
                        var frame = NSRect(x: x, y: cocoaY, width: width, height: height)

                        // Account for window chrome (title bar, borders)
                        // Title bar is ~24px, add small margins on other sides
                        let chromeTop: CGFloat = 24    // Title bar
                        let chromeLeft: CGFloat = 2    // Left border
                        let chromeRight: CGFloat = 2   // Right border
                        let chromeBottom: CGFloat = 2  // Bottom border

                        frame = frame.insetBy(dx: 0, dy: 0)
                        frame.origin.x += chromeLeft
                        frame.origin.y += chromeBottom
                        frame.size.width -= (chromeLeft + chromeRight)
                        frame.size.height -= (chromeTop + chromeBottom)

                        Logger.debug("ErrorOverlay: Got window frame from CGWindow API (with chrome margins): \(frame)", category: Logger.ui)
                        return frame
                    }
                }
            }
        }

        // Try Method 2: Walk up AX hierarchy
        Logger.debug("ErrorOverlay: CGWindow API failed, trying AX hierarchy", category: Logger.ui)

        var windowElement: AXUIElement?
        var currentElement: AXUIElement? = element

        // Walk up the accessibility hierarchy to find the window
        for level in 0..<10 { // Max 10 levels up
            guard let current = currentElement else {
                Logger.debug("ErrorOverlay: AX walk stopped at level \(level) - no current element", category: Logger.ui)
                break
            }

            var roleValue: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)

            guard roleResult == .success, let role = roleValue as? String else {
                Logger.debug("ErrorOverlay: AX walk stopped at level \(level) - could not get role (result: \(roleResult.rawValue))", category: Logger.ui)
                break
            }

            Logger.debug("ErrorOverlay: AX walk level \(level) - role: \(role)", category: Logger.ui)

            if role == "AXWindow" || role == kAXWindowRole as String {
                windowElement = current
                Logger.debug("ErrorOverlay: Found AXWindow at level \(level)", category: Logger.ui)
                break
            }

            var parentValue: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard parentResult == .success, let parent = parentValue else {
                Logger.debug("ErrorOverlay: AX walk stopped at level \(level) - could not get parent (result: \(parentResult.rawValue))", category: Logger.ui)
                break
            }
            currentElement = (parent as! AXUIElement)
        }

        // If we found a window element, get its frame
        if let window = windowElement {
            Logger.debug("ErrorOverlay: Extracting frame from AXWindow element", category: Logger.ui)

            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?

            let positionResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
            let sizeResult = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

            if positionResult == .success, sizeResult == .success,
               let position = positionValue, let size = sizeValue {

                var origin = CGPoint.zero
                var windowSize = CGSize.zero

                AXValueGetValue(position as! AXValue, .cgPoint, &origin)
                AXValueGetValue(size as! AXValue, .cgSize, &windowSize)

                // Convert from Quartz (top-left origin) to Cocoa (bottom-left origin)
                if let screen = NSScreen.main {
                    let screenHeight = screen.frame.height
                    let cocoaY = screenHeight - origin.y - windowSize.height

                    var frame = NSRect(x: origin.x, y: cocoaY, width: windowSize.width, height: windowSize.height)

                    // Account for window chrome (title bar, borders)
                    let chromeTop: CGFloat = 24    // Title bar
                    let chromeLeft: CGFloat = 2    // Left border
                    let chromeRight: CGFloat = 2   // Right border
                    let chromeBottom: CGFloat = 2  // Bottom border

                    frame.origin.x += chromeLeft
                    frame.origin.y += chromeBottom
                    frame.size.width -= (chromeLeft + chromeRight)
                    frame.size.height -= (chromeTop + chromeBottom)

                    Logger.debug("ErrorOverlay: Got window frame from AX hierarchy (with chrome margins): \(frame)", category: Logger.ui)
                    return frame
                }
            } else {
                Logger.debug("ErrorOverlay: Could not extract position/size from AXWindow (pos result: \(positionResult.rawValue), size result: \(sizeResult.rawValue))", category: Logger.ui)
            }
        }

        Logger.debug("ErrorOverlay: All methods failed, returning nil", category: Logger.ui)
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

        Logger.debug("DEBUG getElementFrame: RAW AX data - Position: \(position), Size: \(size)", category: Logger.ui)

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? "unknown"
        Logger.debug("DEBUG getElementFrame: Element role: \(role)", category: Logger.ui)

        var frame = CGRect(origin: position, size: size)

        // CRITICAL: AX API returns coordinates in Quartz (top-left origin)
        // NSPanel.setFrame() uses Cocoa coordinates (bottom-left origin)
        // Must flip Y coordinate using screen height
        if let screenHeight = NSScreen.main?.frame.height {
            frame.origin.y = screenHeight - frame.origin.y - frame.height
            Logger.debug("DEBUG getElementFrame: Converted to Cocoa coords - Y from \(position.y) to \(frame.origin.y) (screen height: \(screenHeight))", category: Logger.ui)
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
        var textValue: CFTypeRef?
        let textError = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        )

        guard textError == .success, let fullText = textValue as? String else {
            Logger.debug("ErrorOverlay: Could not get text for measurement, using simple fallback", category: Logger.ui)
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

        Logger.debug("ErrorOverlay: Multiline handling - lineStart: \(lineStart), textOnLine: '\(textBeforeError)', error: '\(errorText)'", category: Logger.ui)

        // USE CONTENT PARSER ARCHITECTURE
        let bundleID = context?.bundleIdentifier ?? "unknown"
        let parser = ContentParserFactory.shared.parser(for: bundleID)

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

            Logger.debug("ErrorOverlay: ContentParser (\(parser.parserName)) bounds - confidence: \(adjustedBounds.confidence), context: \(adjustedBounds.uiContext ?? "none")", category: Logger.ui)
            Logger.debug("ErrorOverlay: \(adjustedBounds.debugInfo)", category: Logger.ui)
            Logger.debug("ErrorOverlay: Final bounds at \(error.start)-\(error.end): \(estimatedBounds)", category: Logger.ui)

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
        // Screen coordinates are in Cocoa (bottom-left origin)
        // UnderlineView uses flipped coordinates (top-left origin)
        // Must convert from bottom-left to top-left reference

        let localX = screenBounds.origin.x - elementFrame.origin.x

        // Convert Y from Cocoa (bottom-origin) to flipped view (top-origin)
        // In Cocoa: Y=0 is bottom, increases upward
        // In flipped view: Y=0 is top, increases downward
        let cocoaLocalY = screenBounds.origin.y - elementFrame.origin.y
        let flippedLocalY = elementFrame.height - cocoaLocalY - screenBounds.height

        Logger.debug("ConvertToLocal: Screen bounds: \(screenBounds), Element frame: \(elementFrame)", category: Logger.ui)
        Logger.debug("  Cocoa local Y: \(cocoaLocalY), Flipped local Y: \(flippedLocalY)", category: Logger.ui)

        return CGRect(
            x: localX,
            y: flippedLocalY,
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

    // CRITICAL: Use flipped coordinates (top-left origin) to match window positioning
    // When isFlipped = true: (0,0) is top-left, Y increases downward
    override var isFlipped: Bool {
        return true
    }

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

        // Draw debug border and label if enabled (like DebugBorderWindow)
        if UserPreferences.shared.showDebugBorderTextFieldBounds {
            let borderColor = NSColor.systemRed
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(5.0)
            context.stroke(bounds.insetBy(dx: 2.5, dy: 2.5))

            // Draw label in top left (in flipped coords, this is correct)
            let label = "Text Field Bounds"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: borderColor
            ]
            let labelStr = label as NSString
            labelStr.draw(at: NSPoint(x: 10, y: 10), withAttributes: attrs)
        }
    }

    /// Draw straight underline
    private func drawWavyUnderline(in context: CGContext, bounds: CGRect, color: NSColor) {
        context.setStrokeColor(color.cgColor)

        let thickness = CGFloat(UserPreferences.shared.underlineThickness)
        context.setLineWidth(thickness)

        // Draw straight line below the text
        // View uses flipped coordinates (top-left origin): minY is top, maxY is bottom
        // Position the line below the text, offset by thickness to avoid covering text
        let offset = max(2.0, thickness / 2.0) // Minimum 2pt offset, or half thickness
        let y = bounds.maxY + offset  // In flipped coords, maxY is the bottom edge

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
