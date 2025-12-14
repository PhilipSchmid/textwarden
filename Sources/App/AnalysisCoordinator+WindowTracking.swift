//
//  AnalysisCoordinator+WindowTracking.swift
//  TextWarden
//
//  Window tracking functionality extracted from AnalysisCoordinator.
//  Handles window movement detection, scroll detection, and text validation
//  for Mac Catalyst apps where AX notifications are unreliable.
//

import Foundation
import AppKit
@preconcurrency import ApplicationServices

extension AnalysisCoordinator {

    // MARK: - Window Movement Detection

    /// Start monitoring window position to detect movement
    func startWindowPositionMonitoring() {
        Logger.debug("Window monitoring: Starting position monitoring", category: Logger.analysis)
        // Poll window position frequently to catch window movement quickly
        windowPositionTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.shortDelay, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkWindowPosition()
            }
        }
        if let timer = windowPositionTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Logger.debug("Window monitoring: Timer scheduled on main RunLoop", category: Logger.analysis)

        // Also start text validation timer for Mac Catalyst apps
        startTextValidationTimer()
    }

    /// Stop monitoring window position
    func stopWindowPositionMonitoring() {
        windowPositionTimer?.invalidate()
        windowPositionTimer = nil
        windowMovementDebounceTimer?.invalidate()
        windowMovementDebounceTimer = nil
        scrollDebounceTimer?.invalidate()
        scrollDebounceTimer = nil
        textValidationTimer?.invalidate()
        textValidationTimer = nil
        lastWindowFrame = nil
        lastResizeTime = nil
        contentStabilityCount = 0
        lastCharacterBounds = nil
        overlaysHiddenDueToMovement = false
        overlaysHiddenDueToWindowOffScreen = false
        overlaysHiddenDueToScroll = false
    }

    // MARK: - Text Validation for Mac Catalyst Apps

    /// Start periodic text validation for apps where kAXValueChangedNotification is unreliable
    /// This is primarily needed for Mac Catalyst apps (Messages, WhatsApp) where text changes
    /// aren't always reported via accessibility notifications.
    func startTextValidationTimer() {
        guard textValidationTimer == nil else { return }

        // Run frequently enough to catch sent messages, but not too expensive
        textValidationTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.textValidationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.validateCurrentText()
            }
        }
        if let timer = textValidationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        Logger.debug("Text validation: Timer started", category: Logger.analysis)
    }

    /// Validate that the currently displayed errors match the current text
    /// If text has changed significantly, hide indicators and clear errors
    func validateCurrentText() {
        // Only validate if we have active errors or indicators showing
        guard !currentErrors.isEmpty || floatingIndicator.isVisible else { return }

        // Need the monitored element to extract text
        guard let element = textMonitor.monitoredElement else {
            Logger.trace("Text validation: No monitored element", category: Logger.analysis)
            return
        }

        // Don't validate immediately after a replacement - wait for text to settle
        // Browser/Catalyst text replacement can take 0.5-0.7 seconds total, plus delayed AX notifications
        // Use 1.5s grace period to match handleTextChange for consistency
        if let replacementTime = lastReplacementTime,
           Date().timeIntervalSince(replacementTime) < 1.5 {
            return
        }

        // Don't validate during a conversation switch in Mac Catalyst chat apps
        // handleConversationSwitchInChatApp() handles this, and we must let it complete
        // before resuming validation to avoid race conditions
        if let switchTime = lastConversationSwitchTime,
           Date().timeIntervalSince(switchTime) < 0.6 {
            return
        }

        // Extract current text from the element synchronously
        guard let currentText = extractTextSynchronously(from: element) else {
            Logger.trace("Text validation: Could not extract text", category: Logger.analysis)
            return
        }

        // Check if text has changed from what we analyzed
        let analyzedText = lastAnalyzedText

        Logger.trace("Text validation: current='\(currentText.prefix(50))...' (\(currentText.count) chars), analyzed='\(analyzedText.prefix(50))...' (\(analyzedText.count) chars)", category: Logger.analysis)

        // Text matches - no action needed
        if currentText == analyzedText {
            return
        }

        // Text is now empty (e.g., message was sent in chat app)
        if currentText.isEmpty && !analyzedText.isEmpty {
            Logger.debug("Text validation: Text is now empty - clearing errors (message likely sent)", category: Logger.analysis)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !self.isManualStyleCheckActive {
                    self.floatingIndicator.hide()
                }
                self.errorOverlay.hide()
                self.suggestionPopover.hide()
                DebugBorderWindow.clearAll()
                self.currentErrors.removeAll()
                self.lastAnalyzedText = ""
                PositionResolver.shared.clearCache()
            }
            return
        }

        // Text has changed significantly (different content, not just typing)
        // This handles switching to a different chat conversation
        // Note: We check for significant difference to avoid false positives from typing
        let textChanged = !currentText.hasPrefix(analyzedText) && !analyzedText.hasPrefix(currentText)
        if textChanged {
            // Check if this app needs special handling for text validation
            // Mac Catalyst apps and Microsoft Office have unreliable AX notifications
            let isCatalystApp = textMonitor.currentContext?.isMacCatalystApp ?? false
            let isMicrosoftOffice = textMonitor.currentContext?.bundleIdentifier == "com.microsoft.Word" ||
                                    textMonitor.currentContext?.bundleIdentifier == "com.microsoft.Powerpoint"
            let needsReanalysis = isCatalystApp || isMicrosoftOffice

            Logger.debug("Text validation: Text content changed - \(needsReanalysis ? "triggering re-analysis" : "hiding indicator") (possibly switched conversation)", category: Logger.analysis)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // For Microsoft Office, don't hide indicators during focus bounces
                // Just trigger re-analysis to update errors
                if isMicrosoftOffice {
                    self.currentErrors.removeAll()
                    self.lastAnalyzedText = ""
                    PositionResolver.shared.clearCache()

                    // Trigger fresh analysis
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.mediumDelay) { [weak self] in
                        guard let self = self,
                              let context = self.textMonitor.currentContext,
                              !currentText.isEmpty else { return }
                        self.handleTextChange(currentText, in: context)
                    }
                    return
                }

                // Always hide UI elements for other apps
                if !self.isManualStyleCheckActive {
                    self.floatingIndicator.hide()
                }
                self.errorOverlay.hide()
                self.suggestionPopover.hide()
                DebugBorderWindow.clearAll()

                // For Mac Catalyst apps, clear errors and trigger fresh analysis
                // For other apps, let the normal AXValueChanged notification handle re-analysis
                if isCatalystApp {
                    self.currentErrors.removeAll()
                    self.lastAnalyzedText = ""
                    PositionResolver.shared.clearCache()

                    // Trigger fresh analysis after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.longDelay) { [weak self] in
                        guard let self = self,
                              let context = self.textMonitor.currentContext,
                              !currentText.isEmpty else { return }
                        self.handleTextChange(currentText, in: context)
                    }
                }
            }
        }
    }

    /// Extract text from an AXUIElement synchronously
    /// Used by text validation timer to check if content has changed
    func extractTextSynchronously(from element: AXUIElement) -> String? {
        // First, try app-specific extraction via ContentParser
        if let bundleID = textMonitor.currentContext?.bundleIdentifier {
            let parser = ContentParserFactory.shared.parser(for: bundleID)
            if let parserText = parser.extractText(from: element) {
                return parserText
            }
        }

        // Fall back to standard AXValue extraction
        var value: CFTypeRef?
        let valueError = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        if valueError == .success, let textValue = value as? String {
            return textValue
        }

        return nil
    }

    /// Check if window has moved, resized, or content has scrolled
    func checkWindowPosition() {
        guard let element = textMonitor.monitoredElement else {
            lastWindowFrame = nil
            lastElementFrame = nil
            DebugBorderWindow.clearAll()
            return
        }

        guard let currentFrame = getWindowFrame(for: element) else {
            // Window is not on screen (minimized, hidden, or closed)
            Logger.debug("Window monitoring: Window not on screen - hiding all overlays", category: Logger.analysis)
            handleWindowOffScreen()
            return
        }

        // Window is back on screen - restore overlays if they were hidden
        if overlaysHiddenDueToWindowOffScreen {
            Logger.debug("Window monitoring: Window back on screen - restoring overlays", category: Logger.analysis)
            handleWindowBackOnScreen()
        }

        // Note: Scroll detection is now handled by global scrollWheelMonitor

        // For Mac Catalyst apps: track the element frame (text input field) separately
        // The window frame stays constant when sending messages, but the text field shrinks
        if let context = textMonitor.currentContext {
            if context.isMacCatalystApp {
                checkElementFrameForCatalyst(element: element)
            }
        }

        // Check if position or size has changed
        if let lastFrame = lastWindowFrame {
            let positionThreshold: CGFloat = 5.0  // Movement threshold in pixels
            let sizeThreshold: CGFloat = 5.0  // Size change threshold in pixels

            let positionDistance = hypot(currentFrame.origin.x - lastFrame.origin.x, currentFrame.origin.y - lastFrame.origin.y)
            let widthChange = abs(currentFrame.width - lastFrame.width)
            let heightChange = abs(currentFrame.height - lastFrame.height)

            let positionChanged = positionDistance > positionThreshold
            let sizeChanged = widthChange > sizeThreshold || heightChange > sizeThreshold

            if positionChanged || sizeChanged {
                if sizeChanged {
                    Logger.debug("Window monitoring: Resize detected - width: \(widthChange)px, height: \(heightChange)px", category: Logger.analysis)
                    lastResizeTime = Date()  // Track resize time for Electron settling
                }
                if positionChanged {
                    Logger.debug("Window monitoring: Movement detected - distance: \(positionDistance)px", category: Logger.analysis)
                }
                // Window is moving or resizing - hide overlays immediately
                handleWindowMovementStarted()
            } else {
                // Window stopped moving/resizing - show overlays after debounce
                handleWindowMovementStopped()

                // Update debug borders continuously when window is not moving
                // This handles frontmost status changes (e.g., another window comes to front)
                if !overlaysHiddenDueToMovement {
                    updateDebugBorders()
                }
            }
        } else {
            Logger.debug("Window monitoring: Initial frame set: \(currentFrame)", category: Logger.analysis)
            // Initial position - update debug borders
            updateDebugBorders()
        }

        lastWindowFrame = currentFrame
    }

    /// Check element frame changes for Mac Catalyst apps
    /// Detects when the text input field shrinks (message sent) or grows (more text typed)
    /// Also detects when the element position changes significantly (conversation switched)
    func checkElementFrameForCatalyst(element: AXUIElement) {
        guard let currentElementFrame = AccessibilityBridge.getElementFrame(element) else {
            return
        }

        if let lastFrame = lastElementFrame {
            let heightChange = currentElementFrame.height - lastFrame.height
            let positionChange = hypot(
                currentElementFrame.origin.x - lastFrame.origin.x,
                currentElementFrame.origin.y - lastFrame.origin.y
            )
            let significantHeightChange = abs(heightChange) > 5.0
            let significantPositionChange = positionChange > 10.0  // Element moved significantly

            if significantHeightChange || significantPositionChange {
                if significantPositionChange {
                    // Element position changed significantly - conversation was likely switched
                    // Always trigger re-analysis (text content has changed)
                    // This should happen regardless of current error state
                    Logger.debug("Element monitoring: Element position changed by \(positionChange)px in Mac Catalyst app - triggering re-analysis (conversation switch)", category: Logger.analysis)
                    handleConversationSwitchInChatApp(element: element)
                } else if significantHeightChange && heightChange < 0 && (!currentErrors.isEmpty || floatingIndicator.isVisible) {
                    // Text field shrunk - message was likely sent
                    Logger.debug("Element monitoring: Text field shrunk by \(abs(heightChange))px in Mac Catalyst app - clearing errors", category: Logger.analysis)
                    handleMessageSentInChatApp()
                } else if significantHeightChange && heightChange > 0 && !currentErrors.isEmpty {
                    // Text field grew - user is typing more, text positions shifted
                    Logger.debug("Element monitoring: Text field grew by \(heightChange)px in Mac Catalyst app - invalidating positions", category: Logger.analysis)
                    PositionResolver.shared.clearCache()
                    errorOverlay.hide()
                }
            }
        } else {
            Logger.debug("Element monitoring: Initial element frame: \(currentElementFrame)", category: Logger.analysis)
        }

        lastElementFrame = currentElementFrame
    }

    /// Handle conversation switch in a Mac Catalyst chat app
    /// Hides overlays and triggers fresh analysis since the text content has likely changed
    func handleConversationSwitchInChatApp(element: AXUIElement) {
        // Record the time to prevent validateCurrentText() from racing with us
        lastConversationSwitchTime = Date()

        // Capture the text BEFORE clearing state - we'll use this to detect if text actually changed
        // WhatsApp's accessibility API is notorious for returning stale text after conversation switches
        let textBeforeSwitch = lastAnalyzedText

        // Hide all overlays
        floatingIndicator.hide()
        errorOverlay.hide()
        suggestionPopover.hide()
        DebugBorderWindow.clearAll()

        // Clear position cache
        PositionResolver.shared.clearCache()

        // Clear current errors and text tracking - the text has changed
        currentErrors.removeAll()
        lastAnalyzedText = ""
        previousText = ""  // Clear previousText so handleTextChange will process the text

        // Use longer delay for WhatsApp - its accessibility API is slower to update after conversation switch
        // The API may return stale text from the previous conversation if we read too quickly
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? ""
        let delay: TimeInterval = bundleID == "net.whatsapp.WhatsApp" ? 0.5 : 0.2

        // Trigger fresh analysis after a delay (let the UI settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            // Re-read the text and trigger analysis
            guard let monitoredElement = self.textMonitor.monitoredElement,
                  let context = self.textMonitor.currentContext,
                  let text = self.extractTextSynchronously(from: monitoredElement),
                  !text.isEmpty else {
                return
            }

            // For WhatsApp: if the text hasn't changed, the accessibility API is still returning stale data
            // Don't trigger re-analysis with the same text - it would just show the same errors
            // The user will trigger fresh analysis when they actually interact with the new conversation
            if context.bundleIdentifier == "net.whatsapp.WhatsApp" && text == textBeforeSwitch {
                Logger.debug("WhatsApp: Text unchanged after conversation switch (\(text.count) chars) - skipping re-analysis (stale AX data)", category: Logger.analysis)
                return
            }

            self.handleTextChange(text, in: context)
        }
    }

    /// Handle scroll started - hide underlines only (keep indicator visible)
    func handleScrollStarted() {
        // Cancel any pending restore first
        scrollDebounceTimer?.invalidate()
        scrollDebounceTimer = nil

        // Don't hide popover if we just applied a replacement - the async browser/Catalyst
        // replacement may trigger scroll events that would interfere with showing the next error
        // Use 1.5s grace period to match handleTextChange (replacement + delayed AX notifications)
        if let replacementTime = lastReplacementTime,
           Date().timeIntervalSince(replacementTime) < 1.5 {
            Logger.debug("Scroll monitoring: Ignoring scroll - just applied suggestion", category: Logger.analysis)
            return
        }

        if !overlaysHiddenDueToScroll {
            Logger.debug("Scroll monitoring: Scroll started - hiding underlines only", category: Logger.analysis)
            overlaysHiddenDueToScroll = true

            // Hide underlines only (not floating indicator)
            errorOverlay.hide()
            suggestionPopover.hide()

            // Clear the position cache so underlines are recalculated after scroll
            PositionResolver.shared.clearCache()
        }

        // Determine restore delay based on app type
        // Electron/Chromium apps need much longer delay for AX layer to update positions
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? ""
        let isElectronApp = ElectronDetector.usesWebTechnologies(bundleID)
        let restoreDelay: TimeInterval = isElectronApp ? 0.7 : 0.3

        // Start/restart debounce timer for restore (will fire when scrolling stops)
        scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: restoreDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreUnderlinesAfterScroll()
            }
        }
    }

    /// Restore underlines after scroll has stopped
    func restoreUnderlinesAfterScroll() {
        guard overlaysHiddenDueToScroll else { return }

        Logger.debug("Scroll monitoring: Scroll stopped - restoring underlines", category: Logger.analysis)
        overlaysHiddenDueToScroll = false

        // Re-show underlines using cached errors (positions will be recalculated)
        if let element = textMonitor.monitoredElement,
           let context = textMonitor.currentContext,
           !currentErrors.isEmpty {
            let underlinesRestored = errorOverlay.update(errors: currentErrors, element: element, context: context)
            Logger.debug("Scroll monitoring: Restored \(underlinesRestored) underlines from \(currentErrors.count) cached errors", category: Logger.analysis)
        }
    }

    /// Get window position for the given element
    func getWindowFrame(for element: AXUIElement) -> CGRect? {
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
                return CGRect(x: x, y: y, width: width, height: height)
            }
        }

        return nil
    }

    /// Legacy method for compatibility - returns just the position
    func getWindowPosition(for element: AXUIElement) -> CGPoint? {
        return getWindowFrame(for: element)?.origin
    }

    /// Handle message sent in a Mac Catalyst chat app (text field shrunk)
    /// Clears all errors and hides indicators since the text is now empty
    func handleMessageSentInChatApp() {
        floatingIndicator.hide()
        errorOverlay.hide()
        suggestionPopover.hide()
        currentErrors.removeAll()
        lastAnalyzedText = ""
        PositionResolver.shared.clearCache()
        DebugBorderWindow.clearAll()
    }

    /// Handle window movement started
    func handleWindowMovementStarted() {
        guard !overlaysHiddenDueToMovement else { return }

        Logger.debug("Window monitoring: Movement started - hiding all overlays", category: Logger.analysis)
        overlaysHiddenDueToMovement = true
        positionSyncRetryCount = 0  // Reset retry counter for new movement cycle
        lastElementPosition = nil   // Reset element position tracking

        // Immediately hide all overlays
        errorOverlay.hide()
        floatingIndicator.hide()
        suggestionPopover.hide()

        // Clear debug border windows as well
        DebugBorderWindow.clearAll()

        // CRITICAL: Clear the position cache so underlines are recalculated at new window position
        // The cache stores screen coordinates which become stale when the window moves
        PositionResolver.shared.clearCache()

        // Cancel any pending re-show
        windowMovementDebounceTimer?.invalidate()
        windowMovementDebounceTimer = nil
    }

    /// Handle window movement stopped
    func handleWindowMovementStopped() {
        guard overlaysHiddenDueToMovement else { return }

        // Don't create a new timer if one is already scheduled
        // This prevents the timer from being constantly reset while the window is stationary
        guard windowMovementDebounceTimer == nil else { return }

        Logger.debug("Window monitoring: Movement stopped - scheduling re-show after 150ms", category: Logger.analysis)

        // Wait after movement stops before re-showing overlays
        // This provides a snappy UX while avoiding flickering during multi-step drags
        windowMovementDebounceTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.textSettleTime, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reshowOverlaysAfterMovement()
            }
        }
    }

    /// Handle window going off-screen (minimized, hidden, or closed)
    func handleWindowOffScreen() {
        guard !overlaysHiddenDueToWindowOffScreen else { return }

        Logger.debug("Window monitoring: Window off-screen - hiding all overlays", category: Logger.analysis)
        overlaysHiddenDueToWindowOffScreen = true
        lastWindowFrame = nil

        // Hide all overlays
        errorOverlay.hide()
        floatingIndicator.hide()
        suggestionPopover.hide()
        DebugBorderWindow.clearAll()

        // Cancel any pending movement timers
        windowMovementDebounceTimer?.invalidate()
        windowMovementDebounceTimer = nil
    }

    /// Handle window coming back on-screen (restored from minimize)
    func handleWindowBackOnScreen() {
        guard overlaysHiddenDueToWindowOffScreen else { return }

        Logger.debug("Window monitoring: Window back on-screen - restoring overlays", category: Logger.analysis)
        overlaysHiddenDueToWindowOffScreen = false

        // Clear position cache since window position may have changed
        PositionResolver.shared.clearCache()

        // Update debug borders immediately
        updateDebugBorders()

        // Force a text re-extraction to ensure element is fresh and overlays are restored
        // This is especially important for browsers where the element may become stale
        // after minimize/restore
        if let element = textMonitor.monitoredElement {
            Logger.debug("Window monitoring: Forcing text re-extraction after restore", category: Logger.analysis)
            // Clear previousText to force re-analysis even if text hasn't changed
            previousText = ""
            textMonitor.extractText(from: element)
        } else if !currentErrors.isEmpty, let context = monitoredContext {
            // No element but we have cached errors - show floating indicator immediately
            // We can't show underlines without an element (need it for positioning),
            // but we CAN show the floating indicator using just the PID from context
            // The user will see the error count badge; underlines will appear when they click
            Logger.debug("Window monitoring: No element but have \(currentErrors.count) cached errors - showing floating indicator", category: Logger.analysis)
            floatingIndicator.updateWithContext(errors: currentErrors, context: context, sourceText: lastAnalyzedText)
            // DON'T call startMonitoring - it will likely fail to find an editable element
            // in browsers (focus may be on nothing or a UI element after restore), which
            // triggers handleTextChange with nil element, hiding our floating indicator
            // The normal focus change notification will re-acquire the element when user clicks
        } else if let context = monitoredContext {
            // No monitored element and no cached errors - try to restart monitoring
            // This is important for browsers where the element may have become nil
            // (e.g., if user was in a browser UI element before minimize)
            Logger.debug("Window monitoring: No element and no cached errors - restarting monitoring for \(context.applicationName)", category: Logger.analysis)
            previousText = ""
            startMonitoring(context: context)
        }
    }

    /// Re-show overlays after window movement has stopped
    func reshowOverlaysAfterMovement() {
        Logger.debug("Window monitoring: Re-showing overlays at new position", category: Logger.analysis)
        windowMovementDebounceTimer = nil  // Clear timer reference so new timer can be created

        // CRITICAL: Verify that AX API position is in sync with CGWindow position
        // CGWindowList updates immediately, but AX API may lag behind
        // If positions don't match, wait and retry to avoid showing overlays at stale position
        guard let element = textMonitor.monitoredElement else {
            overlaysHiddenDueToMovement = false
            positionSyncRetryCount = 0
            lastElementPosition = nil
            contentStabilityCount = 0
            lastCharacterBounds = nil
            return
        }

        // Get CGWindow position (source of truth - updates immediately)
        guard let cgWindowPosition = getWindowPosition(for: element) else {
            Logger.debug("Window monitoring: Cannot get CGWindow position - showing overlays anyway", category: Logger.analysis)
            overlaysHiddenDueToMovement = false
            positionSyncRetryCount = 0
            lastElementPosition = nil
            contentStabilityCount = 0
            lastCharacterBounds = nil
            PositionResolver.shared.clearCache()
            let sourceText = currentSegment?.content ?? ""
            applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
            updateDebugBorders()
            return
        }

        // Check 1: Verify window position sync between AX and CGWindow
        var needsRetry = false
        if let axWindowPosition = getAXWindowPosition(for: element) {
            let windowDelta = hypot(cgWindowPosition.x - axWindowPosition.x, cgWindowPosition.y - axWindowPosition.y)
            let toleranceThreshold: CGFloat = 5.0  // Tighter tolerance for window position

            if windowDelta > toleranceThreshold {
                Logger.debug("Window monitoring: Window position mismatch - AX: \(axWindowPosition), CG: \(cgWindowPosition), delta: \(windowDelta)px", category: Logger.analysis)
                needsRetry = true
            }
        }

        // Check 2: Verify element position is stable (not still updating)
        if let currentElementPos = getAXElementPosition(for: element) {
            if let lastPos = lastElementPosition {
                let elementDelta = hypot(currentElementPos.x - lastPos.x, currentElementPos.y - lastPos.y)
                let elementTolerance: CGFloat = 3.0  // Very tight tolerance for element stability

                if elementDelta > elementTolerance {
                    Logger.debug("Window monitoring: Element position still changing - last: \(lastPos), current: \(currentElementPos), delta: \(elementDelta)px", category: Logger.analysis)
                    needsRetry = true
                }
            }
            lastElementPosition = currentElementPos
        }

        // If either check failed and we have retries left, wait and retry
        if needsRetry && positionSyncRetryCount < maxPositionSyncRetries {
            positionSyncRetryCount += 1
            Logger.debug("Window monitoring: Position not stable - retry \(positionSyncRetryCount)/\(maxPositionSyncRetries) in 50ms", category: Logger.analysis)

            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.shortDelay) { [weak self] in
                guard let self = self else { return }
                if self.overlaysHiddenDueToMovement {
                    self.reshowOverlaysAfterMovement()
                }
            }
            return
        }

        if needsRetry {
            Logger.debug("Window monitoring: Position sync timed out after \(positionSyncRetryCount) retries - showing overlays anyway", category: Logger.analysis)
        } else if positionSyncRetryCount > 0 {
            // Positions just became stable - add a settling delay for Electron apps
            // which can have extra latency in propagating position changes
            Logger.debug("Window monitoring: Position stable - adding 100ms settling delay", category: Logger.analysis)
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.mediumDelay) { [weak self] in
                guard let self = self else { return }
                if self.overlaysHiddenDueToMovement {
                    self.finalizeOverlayReshow()
                }
            }
            return
        } else {
            Logger.debug("Window monitoring: Position stable immediately (no retries needed)", category: Logger.analysis)
        }

        finalizeOverlayReshow()
    }

    /// Final step of reshowing overlays after all position checks pass
    func finalizeOverlayReshow() {
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? ""
        let isElectronApp = ElectronDetector.usesWebTechnologies(bundleID)

        // For Electron apps after resize, verify ACTUAL CONTENT position stability
        // Notion centers content blocks AFTER the window resize completes
        // We must track character bounds, not just element position
        if lastResizeTime != nil, isElectronApp {
            guard let element = textMonitor.monitoredElement else {
                completeOverlayReshow()
                return
            }

            // Get character bounds for a character near the start of text
            // This detects content block repositioning that element position misses
            let currentCharBounds = getFirstCharacterBounds(for: element)

            if let lastBounds = lastCharacterBounds, let currBounds = currentCharBounds {
                // Check both position AND size changes (text reflow can affect both)
                let positionDelta = hypot(currBounds.origin.x - lastBounds.origin.x,
                                          currBounds.origin.y - lastBounds.origin.y)
                let widthDelta = abs(currBounds.width - lastBounds.width)

                if positionDelta < 3.0 && widthDelta < 2.0 {
                    // Content is stable - increment counter
                    contentStabilityCount += 1
                    Logger.debug("Window monitoring: Character bounds stable (count: \(contentStabilityCount)/4, pos delta: \(positionDelta)px)", category: Logger.analysis)

                    // Require 4 consecutive stable samples (4 * 100ms = 400ms of stability)
                    // This is more conservative to catch late content repositioning
                    if contentStabilityCount >= 4 {
                        Logger.debug("Window monitoring: Content fully settled after resize", category: Logger.analysis)
                        completeOverlayReshow()
                        return
                    }
                } else {
                    // Content still changing - reset counter
                    contentStabilityCount = 0
                    Logger.debug("Window monitoring: Content still moving after resize (pos delta: \(positionDelta)px, width delta: \(widthDelta)px)", category: Logger.analysis)
                }
            }

            lastCharacterBounds = currentCharBounds

            // Schedule another stability check with 100ms interval
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.mediumDelay) { [weak self] in
                guard let self = self, self.overlaysHiddenDueToMovement else { return }
                self.finalizeOverlayReshow()
            }
            return
        }

        // For non-resize or non-Electron, just apply minimum settle time
        if let resizeTime = lastResizeTime {
            let timeSinceResize = Date().timeIntervalSince(resizeTime)
            let requiredSettleTime: TimeInterval = TimingConstants.textSettleTime

            if timeSinceResize < requiredSettleTime {
                let remainingTime = requiredSettleTime - timeSinceResize
                DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                    guard let self = self, self.overlaysHiddenDueToMovement else { return }
                    self.completeOverlayReshow()
                }
                return
            }
        }

        completeOverlayReshow()
    }

    /// Get bounds of the first character in the text element
    /// This tracks actual content position, not just the element container
    func getFirstCharacterBounds(for element: AXUIElement) -> CGRect? {
        // Try to get bounds for character at index 0
        var boundsValue: CFTypeRef?
        var mutableRange = CFRangeMake(0, 1)
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }

        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &boundsValue
        )

        guard error == .success,
              let value = boundsValue,
              let bounds = safeAXValueGetRect(value) else {
            return nil
        }

        return bounds
    }

    /// Actually show the overlays after all stability checks pass
    func completeOverlayReshow() {
        overlaysHiddenDueToMovement = false
        positionSyncRetryCount = 0
        lastElementPosition = nil
        lastResizeTime = nil
        contentStabilityCount = 0
        lastCharacterBounds = nil

        // CRITICAL: Clear position cache AGAIN before re-showing overlays
        // The cache was cleared when movement started, but async analysis operations
        // running during the debounce period might have repopulated it with stale positions
        // (calculated from the old window location). Clear it now to ensure fresh positions.
        PositionResolver.shared.clearCache()

        // Re-show overlays by triggering a re-filter of current errors
        // This will recalculate positions and show overlays at the new location
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)

        // Also update debug borders
        updateDebugBorders()
    }

    /// Get AX window position for the given element (walks up to find window)
    /// Returns position in Quartz coordinates (top-left origin) for comparison with CGWindow
    func getAXWindowPosition(for element: AXUIElement) -> CGPoint? {
        // Walk up to find the window element
        var windowElement: AXUIElement?
        var currentElement: AXUIElement? = element

        for _ in 0..<10 {
            guard let current = currentElement else { break }

            var roleValue: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)

            guard roleResult == .success, let role = roleValue as? String else { break }

            if role == "AXWindow" || role == kAXWindowRole as String {
                windowElement = current
                break
            }

            var parentValue: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard parentResult == .success,
                  let parent = parentValue,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            // Safe: type verified by CFGetTypeID check above
            currentElement = unsafeBitCast(parent, to: AXUIElement.self)
        }

        guard let window = windowElement else { return nil }

        // Return in Quartz coordinates (AX API already returns Quartz coords)
        return AccessibilityBridge.getElementPosition(window)
    }

    /// Get AX element position directly (for stability checking)
    /// Returns position in Quartz coordinates (top-left origin)
    func getAXElementPosition(for element: AXUIElement) -> CGPoint? {
        return AccessibilityBridge.getElementPosition(element)
    }

}
