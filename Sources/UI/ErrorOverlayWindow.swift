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

    // MARK: - Properties

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

    /// Last known element frame for detecting resize/movement
    private var lastElementFrame: CGRect?

    /// Timer for periodic frame validation (detects resize/scroll during visibility)
    private var frameValidationTimer: Timer?

    /// Timestamp when frame last changed (for stabilization detection)
    private var frameLastChangedAt: Date?

    /// Whether we're waiting for frame to stabilize after hiding
    private var waitingForFrameStabilization = false

    /// Callback when frame stabilizes after resize (to re-show underlines)
    var onFrameStabilized: (() -> Void)?

    /// Current bundle ID for app-specific behavior
    private var currentBundleID: String?

    /// Global event monitor for mouse movement
    private var mouseMonitor: Any?

    /// Callback when user hovers over an error (includes window frame for smart positioning)
    var onErrorHover: ((GrammarErrorModel, CGPoint, CGRect?) -> Void)?

    /// Callback when hover ends
    var onHoverEnd: (() -> Void)?

    // MARK: - Initialization

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
        // CRITICAL: Ignore mouse events so clicks pass through to the app below
        // The overlay should be purely visual - only the FloatingErrorIndicator handles interaction
        self.ignoresMouseEvents = true
        self.isMovableByWindowBackground = false

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

    // MARK: - Mouse Monitoring

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
            // CRITICAL: UnderlineView uses flipped coordinates (isFlipped = true)
            // So Y=0 is at TOP of view, increases downward
            // But mouseLocation is in Cocoa coordinates (Y=0 at bottom, increases upward)
            // We must flip the Y coordinate to match the view's coordinate system
            let windowOrigin = self.frame.origin
            let windowHeight = self.frame.height
            let cocoaLocalY = mouseLocation.y - windowOrigin.y
            let flippedLocalY = windowHeight - cocoaLocalY  // Flip Y for flipped view
            let localPoint = CGPoint(
                x: mouseLocation.x - windowOrigin.x,
                y: flippedLocalY
            )

            Logger.trace("ErrorOverlay: Global mouse at screen: \(mouseLocation), window-local (flipped): \(localPoint)", category: Logger.ui)

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

                // Convert underline bounds to screen coordinates for popup positioning
                // The underline bounds are in flipped local coordinates (Y from top)
                // Screen coordinates are in Cocoa (Y from bottom)
                let underlineBounds = newHoveredUnderline.drawingBounds

                // Position the anchor at the CENTER-BOTTOM of the underlined word
                // The popover will position itself relative to this anchor
                let localX = underlineBounds.midX
                // Use maxY (bottom of underline in flipped coords) without extra offset
                // The SuggestionPopover will handle spacing
                let localY = underlineBounds.maxY

                // Convert from flipped local to Cocoa screen coordinates
                // Flipped local Y → Cocoa local Y: cocoaLocalY = windowHeight - flippedLocalY
                // Then add window origin to get screen coords
                let screenLocation = CGPoint(
                    x: windowOrigin.x + localX,
                    y: windowOrigin.y + (windowHeight - localY)
                )

                Logger.debug("ErrorOverlay: Popup anchor - underline bounds: \(underlineBounds), screen: \(screenLocation)", category: Logger.ui)

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

    // MARK: - Overlay Updates

    /// Update overlay with new errors and monitored element
    /// Returns the number of underlines that were successfully created
    /// - Parameters:
    ///   - errors: Grammar errors to show underlines for
    ///   - element: The AX element containing the text
    ///   - context: Application context
    ///   - sourceText: The text that was analyzed (used to detect if text has changed)
    @discardableResult
    func update(errors: [GrammarErrorModel], element: AXUIElement, context: ApplicationContext?, sourceText: String? = nil) -> Int {
        Logger.debug("ErrorOverlay: update() called with \(errors.count) errors", category: Logger.ui)
        self.errors = errors
        self.monitoredElement = element

        // Check if visual underlines are enabled for this app
        let bundleID = context?.bundleIdentifier ?? "unknown"
        self.currentBundleID = bundleID

        // CRITICAL: Check watchdog BEFORE making any AX calls
        // If this app is blacklisted or watchdog is busy, skip ALL AX calls in this function
        // This prevents freezing on apps with slow/hanging AX implementations (like Microsoft Office)
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("ErrorOverlay: Skipping update - watchdog protection active for \(bundleID)", category: Logger.ui)
            hide()
            return 0
        }
        let appConfig = AppRegistry.shared.configuration(for: bundleID)
        let parser = ContentParserFactory.shared.parser(for: bundleID)

        // For apps with typing pause: Hide underlines while typing to avoid misplacement
        // The floating error indicator will still show the error count
        // TypingDetector tracks typing state for all apps via TypingDetector.shared.notifyTextChange()
        if appConfig.features.requiresTypingPause && TypingDetector.shared.isCurrentlyTyping {
            Logger.debug("ErrorOverlay: Hiding underlines during typing (\(appConfig.displayName))", category: Logger.ui)
            hide()
            // Return 0 underlines but errors will still be counted by the indicator
            return 0
        }

        // Check global underlines toggle first
        if !UserPreferences.shared.showUnderlines {
            Logger.info("ErrorOverlay: Underlines globally disabled in preferences - skipping", category: Logger.ui)
            hide()
            return 0
        }

        // Check error count threshold - hide underlines when there are too many errors
        let maxErrors = UserPreferences.shared.maxErrorsForUnderlines
        if errors.count > maxErrors {
            Logger.info("ErrorOverlay: Error count (\(errors.count)) exceeds threshold (\(maxErrors)) - hiding underlines", category: Logger.ui)
            hide()
            return 0
        }

        // Check user's per-app underlines preference (user can override the default)
        if !UserPreferences.shared.areUnderlinesEnabled(for: bundleID) {
            Logger.info("ErrorOverlay: Underlines disabled by user for '\(bundleID)' - skipping", category: Logger.ui)
            hide()
            return 0
        }

        // Check per-app underlines setting from AppRegistry (technical limitations)
        let underlinesDisabled = !appConfig.features.visualUnderlinesEnabled
        Logger.info("ErrorOverlay: Using parser '\(parser.parserName)' for bundleID '\(bundleID)', underlinesDisabled=\(underlinesDisabled)", category: Logger.ui)

        if underlinesDisabled {
            Logger.info("ErrorOverlay: Visual underlines disabled for '\(appConfig.displayName)' - skipping", category: Logger.ui)
            hide()
            return 0
        }

        // Use text field element's AX bounds (not window bounds!)
        // The element passed is the actual text field, so we want ITS bounds
        var elementFrame: CGRect

        // Strategy 1: Try AX API to get text field bounds
        // CRITICAL: Track with watchdog so timeout triggers immediate blacklisting
        AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXPosition/AXSize")
        let frameResult = getElementFrameInCocoaCoords(element)
        AXWatchdog.shared.endCall()

        // Abort immediately if watchdog detected slow call
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.warning("ErrorOverlay: Aborting - watchdog triggered during frame query", category: Logger.ui)
            hide()
            return 0
        }

        if let frame = frameResult {
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

        // Detect element frame changes (resize, scroll, movement)
        // Hide underlines immediately when frame changes to avoid stale underlines
        if let lastFrame = lastElementFrame {
            let positionChanged = abs(elementFrame.origin.x - lastFrame.origin.x) > 5 ||
                                  abs(elementFrame.origin.y - lastFrame.origin.y) > 5
            let sizeChanged = abs(elementFrame.width - lastFrame.width) > 5 ||
                              abs(elementFrame.height - lastFrame.height) > 5

            if positionChanged || sizeChanged {
                Logger.trace("ErrorOverlay: Element frame changed - hiding stale underlines (was: \(lastFrame), now: \(elementFrame))", category: Logger.ui)
                hide()
                lastElementFrame = elementFrame
                // Continue processing to show new underlines at correct positions
            }
        }
        lastElementFrame = elementFrame

        Logger.debug("ErrorOverlay: Element frame (may include scroll content): \(elementFrame)", category: Logger.ui)

        // CRITICAL: Keep track of both original and constrained frames
        // originalElementFrame: The full AX bounds of the text area (used for coordinate calculations)
        // elementFrame: Constrained to visible window (used for overlay window positioning)
        //
        // AXBoundsForRange returns absolute screen coordinates relative to the ORIGINAL element,
        // not the visible/constrained portion. We must use originalElementFrame when converting
        // AX bounds to local coordinates.
        let originalElementFrame = elementFrame

        // Constrain element frame to visible window frame for overlay positioning
        // Element frame may include full scrollable content, but we only want the visible portion
        if let windowFrame = getApplicationWindowFrame() {
            Logger.debug("ErrorOverlay: Visible window frame: \(windowFrame)", category: Logger.ui)
            let visibleFrame = elementFrame.intersection(windowFrame)
            if !visibleFrame.isEmpty {
                Logger.debug("ErrorOverlay: Constraining to visible frame: \(visibleFrame)", category: Logger.ui)
                elementFrame = visibleFrame
            }
        }

        Logger.debug("ErrorOverlay: Final element frame: \(elementFrame)", category: Logger.ui)
        Logger.debug("ErrorOverlay: Original element frame (for coord calc): \(originalElementFrame)", category: Logger.ui)

        // Extend the overlay window slightly below the element frame to allow underlines
        // on the last line to be visible. Underlines are drawn at bounds.maxY + offset,
        // so we need extra space at the bottom. This also helps when app chrome
        // (like ChatGPT's input bar) overlaps the bottom of the text area.
        let underlineExtension: CGFloat = 10.0
        var extendedFrame = elementFrame
        extendedFrame.origin.y -= underlineExtension  // In Cocoa coords, decrease Y to extend down
        extendedFrame.size.height += underlineExtension

        // Position overlay window with extended bounds
        setFrame(extendedFrame, display: true)
        Logger.debug("ErrorOverlay: Window positioned at \(elementFrame)", category: Logger.ui)

        // Extract full text once for all positioning calculations
        // Use timeout wrapper to prevent freeze on slow AX APIs
        // CRITICAL: Track with watchdog so timeout triggers immediate blacklisting
        AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXValue")
        var fullText: String?
        let textCompleted = executeWithTimeout(seconds: 1.5) {
            var textValue: CFTypeRef?
            let textError = AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &textValue
            )
            if textError == .success, let text = textValue as? String {
                fullText = text
            }
        }
        AXWatchdog.shared.endCall()

        // Abort immediately if watchdog detected slow call
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.warning("ErrorOverlay: Aborting - watchdog triggered during text extraction", category: Logger.ui)
            hide()
            return 0
        }

        guard textCompleted, let extractedText = fullText else {
            if !textCompleted {
                Logger.warning("ErrorOverlay: AXValue extraction timed out", category: Logger.ui)
            } else {
                Logger.debug("ErrorOverlay: Could not extract text from element for positioning", category: Logger.ui)
            }
            hide()
            return 0
        }
        let fullTextValue = extractedText


        // Get visible character range to filter out off-screen errors
        // Note: Some apps (like Mail's WebKit) return Int.max for visibleRange which is invalid
        // Note: Mac Catalyst apps (like Messages) return {0, 0} which means "unsupported"
        // CRITICAL: Track with watchdog so timeout triggers immediate blacklisting
        AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXVisibleCharacterRange")
        var visibleRange = AccessibilityBridge.getVisibleCharacterRange(element)
        AXWatchdog.shared.endCall()

        // Abort immediately if watchdog detected slow call (prevents cascading timeouts)
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.warning("ErrorOverlay: Aborting - watchdog triggered during visible range query", category: Logger.ui)
            hide()
            return 0
        }
        if let vr = visibleRange {
            // Sanity check: if location is absurdly large (> 1 billion chars), it's invalid
            // This happens with Mail's WebKit which returns Int64.max
            if vr.location > 1_000_000_000 || vr.length > 1_000_000_000 {
                Logger.debug("ErrorOverlay: Visible character range is invalid (\(vr.location)-\(vr.location + vr.length)), ignoring", category: Logger.ui)
                visibleRange = nil
            } else if vr.length == 0 {
                // Zero-length visible range means the app doesn't properly support this API
                // This happens with Mac Catalyst apps like Messages which return {0, 0}
                Logger.debug("ErrorOverlay: Visible character range has zero length (\(vr.location)-\(vr.location + vr.length)), ignoring", category: Logger.ui)
                visibleRange = nil
            } else {
                Logger.debug("ErrorOverlay: Visible character range: \(vr.location)-\(vr.location + vr.length)", category: Logger.ui)
            }
        }

        // Calculate underline positions for each error using new positioning system
        var skippedCount = 0
        var skippedDueToVisibility = 0

        // Detect internal text padding using TextMarker API (most accurate)
        // TextMarker returns actual visual bounds while LineIndex uses element frame
        var internalPaddingX: CGFloat = 0

        if fullTextValue.count > 0 {
            // Use TextMarker API to get the ACTUAL first character position
            // This is more accurate than AXBoundsForRange which often returns element frame X
            let startMarker = AccessibilityBridge.requestOpaqueMarker(at: 0, from: element)
            let endMarker = AccessibilityBridge.requestOpaqueMarker(at: 1, from: element)

            if startMarker == nil {
                Logger.trace("ErrorOverlay: TextMarker padding detection - startMarker is nil", category: Logger.ui)
            }
            if endMarker == nil {
                Logger.trace("ErrorOverlay: TextMarker padding detection - endMarker is nil", category: Logger.ui)
            }

            if let start = startMarker, let end = endMarker {
                if let bounds = AccessibilityBridge.calculateBounds(from: start, to: end, in: element) {
                    // bounds is in Quartz coords, elementFrame is in Cocoa coords
                    // Both X coordinates are the same in Quartz vs Cocoa (only Y differs)
                    let firstCharX = bounds.origin.x
                    let elementX = originalElementFrame.origin.x
                    internalPaddingX = firstCharX - elementX
                    Logger.trace("ErrorOverlay: TextMarker first char bounds: \(bounds), elementX=\(elementX), padding=\(internalPaddingX)", category: Logger.ui)
                } else {
                    Logger.trace("ErrorOverlay: TextMarker padding detection - calculateBounds returned nil", category: Logger.ui)
                }
            }
        }

        // Clear debug marker (will be set if enabled for parsers with custom bounds)
        underlineView?.firstCharDebugMarker = nil

        let underlines = errors.compactMap { error -> ErrorUnderline? in
            let errorRange = NSRange(location: error.start, length: error.end - error.start)

            // Filter out errors that are completely outside the visible character range
            if let visibleRange = visibleRange {
                let errorEnd = error.start + (error.end - error.start)
                let visibleEnd = visibleRange.location + visibleRange.length

                // Skip if error ends before visible range starts OR error starts after visible range ends
                if errorEnd < visibleRange.location || error.start > visibleEnd {
                    Logger.debug("ErrorOverlay: Skipping error at \(error.start)-\(error.end) - outside visible range \(visibleRange.location)-\(visibleEnd)", category: Logger.ui)
                    skippedDueToVisibility += 1
                    return nil
                }
            }

            // Use new multi-strategy positioning system
            Logger.debug("BEFORE calling parser.resolvePosition() - parser type: \(type(of: parser)), parserName: \(parser.parserName), actualBundleID: \(bundleID)", category: Logger.ui)
            let geometryResult = parser.resolvePosition(
                for: errorRange,
                in: element,
                text: fullTextValue,
                actualBundleID: bundleID
            )

            Logger.debug("ErrorOverlay: PositionResolver returned bounds: \(geometryResult.bounds), strategy: \(geometryResult.strategy), confidence: \(geometryResult.confidence), isMultiLine: \(geometryResult.isMultiLine)", category: Logger.ui)

            // Handle unavailable results (graceful degradation)
            // Unavailable results mean we should NOT show an underline rather than show it wrong
            if geometryResult.isUnavailable {
                Logger.debug("ErrorOverlay: Position unavailable for error at \(error.start)-\(error.end) (graceful degradation: \(geometryResult.metadata["reason"] ?? "unknown"))", category: Logger.ui)
                skippedCount += 1
                return nil
            }

            // Check if result is usable
            guard geometryResult.isUsable else {
                Logger.debug("ErrorOverlay: Position result not usable (confidence: \(geometryResult.confidence))", category: Logger.ui)
                return nil
            }

            // getElementFrameInCocoaCoords() returns Cocoa coordinates (bottom-left origin)
            // NSPanel.setFrame() uses Cocoa coordinates for positioning
            Logger.debug("ErrorOverlay: Element frame (Cocoa): \(elementFrame)", category: Logger.ui)

            // Convert all line bounds to local coordinates
            let allScreenBounds = geometryResult.allLineBounds
            var allLocalBounds: [CGRect] = []

            // Set first character debug marker if enabled (uses parser's custom bounds)
            if UserPreferences.shared.showDebugCharacterMarkers,
               let firstCharBounds = parser.getBoundsForRange(range: NSRange(location: 0, length: 1), in: element) {
                let firstCharCocoa = CoordinateMapper.toCocoaCoordinates(firstCharBounds)
                let firstCharLocal = convertToLocal(firstCharCocoa, from: elementFrame)
                underlineView?.firstCharDebugMarker = firstCharLocal
            }

            for (lineIndex, screenBounds) in allScreenBounds.enumerated() {
                // CRITICAL: Filter out underlines whose screen bounds fall outside the visible element frame
                // This handles scrolled text where underlines would appear outside the window
                // Check in screen coordinates BEFORE converting to local
                if !elementFrame.intersects(screenBounds) {
                    Logger.debug("ErrorOverlay: Skipping line \(lineIndex) outside element frame - screen: \(screenBounds), element: \(elementFrame)", category: Logger.ui)
                    continue
                }

                // CRITICAL: Use the CONSTRAINED element frame (where window is actually positioned)
                // for local coordinate calculations. The window is at elementFrame, so:
                //   local = screen - elementFrame
                // Then underline appears at: elementFrame + local = screen ✓
                //
                // Note: Parsers with custom bounds (getBoundsForRange) already provide
                // properly converted screen coordinates, so no additional offset needed.
                let frameForConversion: CGRect = elementFrame
                var localBounds = convertToLocal(screenBounds, from: frameForConversion)

                // Apply internal text padding offset if detected
                // This shifts underlines right to match the actual text position
                if internalPaddingX > 0 {
                    localBounds.origin.x += internalPaddingX
                }

                Logger.debug("ErrorOverlay: Line \(lineIndex) - screen: \(screenBounds), local: \(localBounds)", category: Logger.ui)

                // Validate local bounds - reject invalid coordinates
                // Invalid bounds cause hover detection to fail
                let maxValidHeight: CGFloat = UIConstants.maximumTextLineHeight
                if localBounds.origin.y < -10 || localBounds.height > maxValidHeight {
                    Logger.warning("ErrorOverlay: Skipping invalid line bounds (y=\(localBounds.origin.y), h=\(localBounds.height))", category: Logger.ui)
                    continue
                }

                // Additional check: ensure local bounds are within the window's drawable area
                let windowHeight = elementFrame.height
                if localBounds.origin.y > windowHeight || localBounds.maxY < 0 {
                    Logger.debug("ErrorOverlay: Skipping line outside visible area (y=\(localBounds.origin.y), windowHeight=\(windowHeight))", category: Logger.ui)
                    continue
                }

                allLocalBounds.append(localBounds)
            }

            // If no valid bounds remain, skip this error
            guard !allLocalBounds.isEmpty else {
                Logger.warning("ErrorOverlay: All line bounds invalid for error at \(error.start)-\(error.end)", category: Logger.ui)
                skippedCount += 1
                return nil
            }

            // Calculate overall expanded bounds for hit detection (covers all lines)
            let thickness = CGFloat(UserPreferences.shared.underlineThickness)
            let offsetAmount = max(2.0, thickness / 2.0)

            let overallLocalBounds = calculateOverallBounds(from: allLocalBounds)
            let expandedBounds = CGRect(
                x: overallLocalBounds.minX,
                y: overallLocalBounds.minY - offsetAmount - thickness - 2.0,
                width: overallLocalBounds.width,
                height: overallLocalBounds.height + offsetAmount + thickness + 2.0
            )

            Logger.debug("ErrorOverlay: Multi-line error with \(allLocalBounds.count) lines, expanded bounds: \(expandedBounds)", category: Logger.ui)

            // Use the last line's bounds as the primary drawing bounds (for popup anchor)
            // allLocalBounds is guaranteed non-empty here due to guard at line 428
            guard let primaryDrawingBounds = allLocalBounds.last else {
                Logger.error("ErrorOverlay: Unexpected empty allLocalBounds after guard", category: Logger.ui)
                return nil
            }

            return ErrorUnderline(
                bounds: expandedBounds,
                drawingBounds: primaryDrawingBounds,
                allDrawingBounds: allLocalBounds,
                color: underlineColor(for: error.category),
                error: error
            )
        }

        // Restore cursor position after all Chromium measurements are complete
        // This must be called AFTER all positioning calculations are done
        ChromiumStrategy.restoreCursorPosition()

        Logger.info("ErrorOverlay: Created \(underlines.count) underlines from \(errors.count) errors (skipped \(skippedCount) positioning, \(skippedDueToVisibility) not visible)", category: Logger.ui)

        // Extra debug for Notion
        if bundleID.contains("notion") {
            Logger.info("NOTION UNDERLINES: \(underlines.count) underlines created", category: Logger.ui)
            for (i, ul) in underlines.enumerated() {
                Logger.info("  Underline \(i): bounds=\(ul.bounds), drawingBounds=\(ul.drawingBounds), allDrawingBounds.count=\(ul.allDrawingBounds.count)", category: Logger.ui)
                for (j, lineBounds) in ul.allDrawingBounds.enumerated() {
                    Logger.info("    Line \(j): \(lineBounds)", category: Logger.ui)
                }
            }
        }

        underlineView?.underlines = underlines
        underlineView?.needsDisplay = true

        if !underlines.isEmpty {
            // Only order window if not already visible to avoid window ordering spam
            if !isCurrentlyVisible {
                Logger.info("ErrorOverlay: Showing overlay window (first time) with \(underlines.count) underlines", category: Logger.ui)
                // Use order(.above) instead of orderFrontRegardless() to avoid activating the app
                order(.above, relativeTo: 0)
                isCurrentlyVisible = true
                // Start periodic frame validation only for apps that need it (e.g., Outlook Copilot)
                // This is expensive, so we don't enable it by default
                if appConfig.features.requiresFrameValidation {
                    startFrameValidationTimer()
                }
            } else {
                Logger.debug("ErrorOverlay: Updating overlay (already visible, not reordering)", category: Logger.ui)
            }
        } else {
            Logger.info("ErrorOverlay: No underlines created - hiding overlay", category: Logger.ui)
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

        // Only stop timer if not waiting for frame stabilization
        // (we need the timer to keep running to detect when resize is done)
        if !waitingForFrameStabilization {
            stopFrameValidationTimer()
        }
    }

    /// Start periodic frame validation to detect resize/scroll
    private func startFrameValidationTimer() {
        stopFrameValidationTimer()

        frameValidationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.validateElementFrame()
        }
    }

    /// Stop frame validation timer
    private func stopFrameValidationTimer() {
        frameValidationTimer?.invalidate()
        frameValidationTimer = nil
    }

    /// Check if element frame has changed and hide underlines if so
    private func validateElementFrame() {
        guard let element = monitoredElement,
              let lastFrame = lastElementFrame else {
            // No element or frame - stop waiting
            if waitingForFrameStabilization {
                waitingForFrameStabilization = false
                stopFrameValidationTimer()
            }
            return
        }

        // Get current frame (this is a lightweight AX call)
        guard let currentFrame = getElementFrameInCocoaCoords(element) else {
            // Element no longer accessible - hide underlines and stop waiting
            Logger.debug("ErrorOverlay: Frame validation - element not accessible, hiding", category: Logger.ui)
            hide()
            waitingForFrameStabilization = false
            stopFrameValidationTimer()
            return
        }

        // Check for significant changes
        let positionChanged = abs(currentFrame.origin.x - lastFrame.origin.x) > 3 ||
                              abs(currentFrame.origin.y - lastFrame.origin.y) > 3
        let sizeChanged = abs(currentFrame.width - lastFrame.width) > 3 ||
                          abs(currentFrame.height - lastFrame.height) > 3

        if positionChanged || sizeChanged {
            // Frame changed - update tracking and reset stabilization timer
            frameLastChangedAt = Date()
            lastElementFrame = currentFrame

            // IMPORTANT: Set flag BEFORE hide() so timer keeps running
            waitingForFrameStabilization = true

            if isCurrentlyVisible {
                Logger.trace("ErrorOverlay: Frame validation detected change - hiding stale underlines", category: Logger.ui)
                hide()
            }

        } else if waitingForFrameStabilization {
            // Frame is stable - check if it's been stable long enough
            if let lastChanged = frameLastChangedAt,
               Date().timeIntervalSince(lastChanged) > 0.4 {
                Logger.trace("ErrorOverlay: Frame stabilized after resize - triggering re-display", category: Logger.ui)
                waitingForFrameStabilization = false
                // Don't stop timer - keep monitoring for future changes
                onFrameStabilized?()
            }
        }
        // Note: Timer keeps running while underlines are visible to detect future changes
        // It's stopped only in hide() when not waiting for stabilization
    }

    /// Clean up resources
    deinit {
        stopFrameValidationTimer()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // MARK: - Window Frame Helpers

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

                    // CGWindow coordinates are in Quartz (top-left origin relative to primary screen's top-left)
                    // Convert to Cocoa (bottom-left origin relative to primary screen's bottom-left)
                    //
                    // IMPORTANT: For multi-monitor setups, we need to use the primary screen's height
                    // for the coordinate conversion, NOT the screen where the window is located.
                    // Quartz origin is at top-left of primary screen, Cocoa origin is at bottom-left of primary screen.
                    // The conversion formula is: cocoaY = primaryScreenHeight - quartzY - windowHeight
                    //
                    // Find primary screen (the one with origin 0,0)
                    let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
                    if let primaryScreen = primaryScreen {
                        // The global coordinate system height is the primary screen's height in this context
                        // Actually, Quartz uses a global coordinate system where Y=0 is at the top of the primary screen
                        // and extends downward. For multi-monitor setups, the conversion needs the primary screen height.
                        let primaryScreenHeight = primaryScreen.frame.height
                        let cocoaY = primaryScreenHeight - y - height
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

        // Try Method 2: Walk up AX hierarchy using centralized helper
        Logger.debug("ErrorOverlay: CGWindow API failed, trying AX hierarchy", category: Logger.ui)

        if let quartzFrame = AccessibilityBridge.getWindowFrame(element) {
            Logger.debug("ErrorOverlay: Found window via AX hierarchy, frame (Quartz): \(quartzFrame)", category: Logger.ui)

            // Convert from Quartz (top-left origin) to Cocoa (bottom-left origin)
            if let screen = NSScreen.main {
                let screenHeight = screen.frame.height
                let cocoaY = screenHeight - quartzFrame.origin.y - quartzFrame.height

                var frame = CGRect(x: quartzFrame.origin.x, y: cocoaY, width: quartzFrame.width, height: quartzFrame.height)

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
        }

        Logger.debug("ErrorOverlay: All methods failed, returning nil", category: Logger.ui)
        return nil
    }

    /// Get frame of AX element in Cocoa coordinates (bottom-left origin)
    /// Uses shared AccessibilityBridge.getElementFrame() for basic retrieval,
    /// then converts from Quartz to Cocoa coordinates for NSPanel positioning
    private func getElementFrameInCocoaCoords(_ element: AXUIElement) -> CGRect? {
        guard var frame = AccessibilityBridge.getElementFrame(element) else {
            return nil
        }

        Logger.debug("DEBUG getElementFrame: RAW AX data (Quartz) - \(frame)", category: Logger.ui)

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? "unknown"
        Logger.debug("DEBUG getElementFrame: Element role: \(role)", category: Logger.ui)

        // CRITICAL: AX API returns coordinates in Quartz (top-left origin)
        // NSPanel.setFrame() uses Cocoa coordinates (bottom-left origin)
        // Must flip Y coordinate using PRIMARY screen height (the one with Cocoa origin at 0,0)
        let originalQuartzY = frame.origin.y
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        if let screenHeight = primaryScreen?.frame.height ?? NSScreen.main?.frame.height {
            frame.origin.y = screenHeight - frame.origin.y - frame.height
            Logger.debug("DEBUG getElementFrame: Converted to Cocoa coords - Y from \(originalQuartzY) to \(frame.origin.y) (screen height: \(screenHeight))", category: Logger.ui)
        }

        return frame
    }

    // MARK: - Bounds Calculation

    /// Get bounds for specific error range
    private func getErrorBounds(for error: GrammarErrorModel, in element: AXUIElement) -> CGRect? {
        let location = error.start
        let length = error.end - error.start

        var range = CFRange(location: location, length: max(1, length))
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard boundsError == .success,
              let axValue = boundsValue,
              let rect = safeAXValueGetRect(axValue) else {
            return nil
        }

        var adjustedRect = rect

        // CRITICAL: AX API returns coordinates in top-left origin system (Quartz)
        // NSWindow uses bottom-left origin (AppKit)
        // Must flip Y coordinate using screen height
        if let screenHeight = NSScreen.main?.frame.height {
            adjustedRect.origin.y = screenHeight - adjustedRect.origin.y - adjustedRect.height
        }

        return adjustedRect
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
        // Use safe index operations with limitedBy to prevent crashes on out-of-bounds access
        guard let lineStartIndex = fullText.index(fullText.startIndex, offsetBy: lineStart, limitedBy: fullText.endIndex),
              let errorStartIndex = fullText.index(fullText.startIndex, offsetBy: safeStart, limitedBy: fullText.endIndex),
              let errorEndIndex = fullText.index(fullText.startIndex, offsetBy: safeEnd, limitedBy: fullText.endIndex),
              lineStartIndex <= errorStartIndex,
              errorStartIndex <= errorEndIndex else {
            Logger.debug("ErrorOverlay: String index bounds check failed, using simple fallback", category: Logger.ui)
            return simpleFallbackBounds(for: error, elementFrame: elementFrame, context: context)
        }
        let textBeforeError = String(fullText[lineStartIndex..<errorStartIndex])
        let errorText = String(fullText[errorStartIndex..<errorEndIndex])

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

            // Use Y position from parser if it looks valid (non-zero and within reasonable bounds)
            // Parser returns position in Quartz coordinates (Y from screen bottom)
            let estimatedY: CGFloat
            let estimatedHeight: CGFloat = 24.0  // Standard underline height

            // Check if parser provided a meaningful Y position
            // Valid positions should be within or near the element's vertical extent
            let parserY = adjustedBounds.position.y
            if parserY > 0 && parserY < (elementFrame.origin.y + elementFrame.height + 500) {
                // Use parser's calculated Y position
                estimatedY = parserY
                Logger.debug("ErrorOverlay: Using parser Y position: \(parserY)", category: Logger.ui)
            } else {
                // Fall back to middle of element for unreliable Y positions
                estimatedY = elementFrame.origin.y + (elementFrame.height * 0.25)
                Logger.debug("ErrorOverlay: Falling back to element middle Y: \(estimatedY) (parser gave \(parserY))", category: Logger.ui)
            }

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
        Logger.debug("ContentParser returned nil for \(bundleID) - disabling visual underline", category: Logger.ui)
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

    /// Calculate the overall bounding box that encompasses all bounds
    private func calculateOverallBounds(from bounds: [CGRect]) -> CGRect {
        guard let first = bounds.first else { return .zero }

        var minX = first.minX
        var minY = first.minY
        var maxX = first.maxX
        var maxY = first.maxY

        for rect in bounds.dropFirst() {
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Coordinate Conversion

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

    // MARK: - Color Mapping

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
    let bounds: CGRect // Overall bounds for hit detection (expanded to include underline area)
    let drawingBounds: CGRect // Primary bounds for drawing position (used for popup anchor)
    let allDrawingBounds: [CGRect] // All line bounds for multi-line underlines
    let color: NSColor
    let error: GrammarErrorModel

    /// Check if this is a multi-line underline
    var isMultiLine: Bool {
        allDrawingBounds.count > 1
    }

    /// Single-line convenience initializer
    init(bounds: CGRect, drawingBounds: CGRect, color: NSColor, error: GrammarErrorModel) {
        self.bounds = bounds
        self.drawingBounds = drawingBounds
        self.allDrawingBounds = [drawingBounds]
        self.color = color
        self.error = error
    }

    /// Multi-line initializer
    init(bounds: CGRect, drawingBounds: CGRect, allDrawingBounds: [CGRect], color: NSColor, error: GrammarErrorModel) {
        self.bounds = bounds
        self.drawingBounds = drawingBounds
        self.allDrawingBounds = allDrawingBounds
        self.color = color
        self.error = error
    }
}

// MARK: - Style Underline Model

struct StyleUnderline {
    let bounds: CGRect // Bounds for hit detection
    let drawingBounds: CGRect // Original bounds for drawing position
    let suggestion: StyleSuggestionModel
}

extension StyleUnderline {
    static let color = NSColor.purple
}

// MARK: - Underline View

class UnderlineView: NSView {

    // MARK: - Properties

    var underlines: [ErrorUnderline] = []
    var styleUnderlines: [StyleUnderline] = []
    var hoveredUnderline: ErrorUnderline?
    var hoveredStyleUnderline: StyleUnderline?
    var allowsClickPassThrough: Bool = false
    var firstCharDebugMarker: CGRect?  // For coordinate debugging (first char position)

    // MARK: - View Configuration

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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // DEBUG: Log actual window position at draw time
        if UserPreferences.shared.showDebugBorderTextFieldBounds, let window = self.window {
            Logger.info("UnderlineView.draw: Window ACTUAL frame at draw time: \(window.frame)", category: Logger.ui)
        }

        // Clear background
        context.clear(bounds)

        // Draw highlight for hovered underline first (behind the underlines)
        // For multi-line underlines, highlight all lines
        if let hovered = hoveredUnderline {
            for lineBounds in hovered.allDrawingBounds {
                drawHighlight(in: context, bounds: lineBounds, color: hovered.color)
            }
        }

        // Draw highlight for hovered style underline
        if let hovered = hoveredStyleUnderline {
            drawHighlight(in: context, bounds: hovered.drawingBounds, color: StyleUnderline.color)
        }

        // Draw each grammar error underline (solid line)
        // For multi-line underlines, draw underlines for each line
        for (underlineIdx, underline) in underlines.enumerated() {
            Logger.debug("Draw: Underline \(underlineIdx) has \(underline.allDrawingBounds.count) line bounds", category: Logger.ui)
            for (lineIdx, lineBounds) in underline.allDrawingBounds.enumerated() {
                Logger.debug("Draw: Drawing line \(lineIdx) at bounds \(lineBounds)", category: Logger.ui)
                drawWavyUnderline(in: context, bounds: lineBounds, color: underline.color)

                // Draw orange marker at underline START position for coordinate debugging
                if UserPreferences.shared.showDebugCharacterMarkers {
                    context.setFillColor(NSColor.systemOrange.cgColor)
                    context.fill(CGRect(x: lineBounds.minX, y: lineBounds.minY, width: 6, height: 6))
                }
            }
        }

        // Draw each style suggestion underline (dotted purple line)
        for styleUnderline in styleUnderlines {
            drawDottedUnderline(in: context, bounds: styleUnderline.drawingBounds, color: StyleUnderline.color)
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

            // DEBUG: Draw markers to verify coordinate alignment
            // Green marker at (0,0) to show window origin
            context.setFillColor(NSColor.systemGreen.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))

            // Blue marker at (24, 15) for reference point
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(CGRect(x: 24, y: 15, width: 10, height: 10))

            // Draw coordinate labels
            let coordAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 10),
                .foregroundColor: NSColor.systemGreen
            ]
            let originLabel = "(0,0)" as NSString
            originLabel.draw(at: NSPoint(x: 12, y: 0), withAttributes: coordAttrs)

            let offsetAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 10),
                .foregroundColor: NSColor.systemBlue
            ]
            let offsetLabel = "(24,15)" as NSString
            offsetLabel.draw(at: NSPoint(x: 36, y: 15), withAttributes: offsetAttrs)

            // Draw cyan marker at first character position (only if character markers are enabled)
            if UserPreferences.shared.showDebugCharacterMarkers, let firstCharMarker = firstCharDebugMarker {
                context.setFillColor(NSColor.systemTeal.cgColor)
                context.fill(CGRect(x: firstCharMarker.origin.x, y: firstCharMarker.origin.y, width: 8, height: 8))

                let firstCharAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 9),
                    .foregroundColor: NSColor.systemTeal
                ]
                let firstCharLabel = "1st(\(Int(firstCharMarker.origin.x)),\(Int(firstCharMarker.origin.y)))" as NSString
                firstCharLabel.draw(at: NSPoint(x: firstCharMarker.origin.x + 10, y: firstCharMarker.origin.y), withAttributes: firstCharAttrs)
            }
        }
    }

    // MARK: - Underline Drawing Helpers

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

    /// Draw dotted underline for style suggestions (purple)
    private func drawDottedUnderline(in context: CGContext, bounds: CGRect, color: NSColor) {
        context.setStrokeColor(color.cgColor)

        let thickness = CGFloat(UserPreferences.shared.underlineThickness)
        context.setLineWidth(thickness)

        // Set dotted line pattern: 4pt dash, 3pt gap
        context.setLineDash(phase: 0, lengths: [4.0, 3.0])

        // Draw dotted line below the text
        let offset = max(2.0, thickness / 2.0)
        let y = bounds.maxY + offset

        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.minX, y: y))
        path.addLine(to: CGPoint(x: bounds.maxX, y: y))

        context.addPath(path)
        context.strokePath()

        // Reset line dash to solid for other drawing
        context.setLineDash(phase: 0, lengths: [])
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
