//
//  AnalysisCoordinator+WindowTracking.swift
//  TextWarden
//
//  Window tracking functionality extracted from AnalysisCoordinator.
//  Handles window movement detection, scroll detection, and text validation
//  for Mac Catalyst apps where AX notifications are unreliable.
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation

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

        // CRITICAL: Check watchdog BEFORE making any AX calls
        // This prevents freeze when Outlook Copilot or other overlays make AX API unresponsive
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? "unknown"
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("Text validation: Skipping - watchdog active for \(bundleID)", category: Logger.analysis)
            return
        }

        // Don't validate immediately after a replacement - wait for text to settle
        // Browser/Catalyst text replacement can take 0.5-0.7 seconds total, plus delayed AX notifications
        // Use 1.5s grace period to match handleTextChange for consistency
        if let replacementTime = lastReplacementTime,
           Date().timeIntervalSince(replacementTime) < 1.5
        {
            return
        }

        // Don't validate during a conversation switch in Mac Catalyst chat apps
        // handleConversationSwitchInChatApp() handles this, and we must let it complete
        // before resuming validation to avoid race conditions
        if let switchTime = lastConversationSwitchTime,
           Date().timeIntervalSince(switchTime) < 0.6
        {
            return
        }

        // Extract current text from the element synchronously
        guard let currentText = extractTextSynchronously(from: element) else {
            Logger.trace("Text validation: Could not extract text", category: Logger.analysis)
            return
        }

        // Check if text has changed from what we analyzed
        let analyzedText = lastAnalyzedText

        // Text matches - no action needed (skip logging for this common case)
        if currentText == analyzedText {
            return
        }

        // Only log when there's a mismatch that we need to handle
        Logger.trace("Text validation: current=\(currentText.count) chars, analyzed=\(analyzedText.count) chars (mismatch)", category: Logger.analysis)

        // Text is now empty (e.g., message was sent in chat app)
        if currentText.isEmpty, !analyzedText.isEmpty {
            // For web-based apps (Slack, Teams, etc.), focus can briefly land on elements
            // that return empty text (like AXWebArea) before settling on the actual compose field.
            // Don't clear errors immediately - let the focus settle first.
            let bundleID = textMonitor.currentContext?.bundleIdentifier ?? ""
            let emptyTextBehavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            if emptyTextBehavior.knownQuirks.contains(.webBasedRendering) {
                // Web-based apps: focus can briefly land on elements returning empty text
                // Skip clearing errors - let the focus settle first (no log, too frequent)
                return
            }

            Logger.debug("Text validation: Text is now empty - clearing errors (message likely sent)", category: Logger.analysis)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !isManualStyleCheckActive {
                    floatingIndicator.hide()
                }
                errorOverlay.hide()
                suggestionPopover.hide()
                DebugBorderWindow.clearAll()
                currentErrors.removeAll()
                lastAnalyzedText = ""
                positionResolver.clearCache()
            }
            return
        }

        // Text has changed significantly (different content, not just typing)
        // This handles switching to a different chat conversation
        // Note: We check for significant difference to avoid false positives from typing
        let textChanged = !currentText.hasPrefix(analyzedText) && !analyzedText.hasPrefix(currentText)
        if textChanged {
            // Web-based apps (Notion, Slack, etc.) have content parsers that can return slightly
            // different filtered text each time due to UI element filtering, code block detection, etc.
            // This causes false "text changed" detection. Skip text validation entirely for these apps
            // since position monitoring handles sidebar toggles and the element frame tracking handles
            // most layout changes.
            let bundleID = textMonitor.currentContext?.bundleIdentifier ?? ""
            let appBehavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            if appBehavior.knownQuirks.contains(.webBasedRendering) {
                // Web-based apps: parsers may return different filtered text each time
                // Skip validation - position monitoring handles layout changes (no log, too frequent)
                return
            }

            // Apps with unstable AX text retrieval (like Outlook) may return slightly different
            // text each time due to invisible characters, formatting, or AX API quirks.
            // This causes false "text changed" detection. Skip validation for these apps.
            if appBehavior.knownQuirks.contains(.hasUnstableTextRetrieval) {
                return
            }

            // Check if this app needs special handling for text validation
            // Some apps have unreliable AX notifications that cause text to appear changed
            let isCatalystApp = textMonitor.currentContext?.isMacCatalystApp ?? false
            let needsSpecialHandling = appBehavior.knownQuirks.contains(.requiresFullReanalysisAfterReplacement)
            let needsReanalysis = isCatalystApp || needsSpecialHandling

            Logger.debug("Text validation: Text content changed - \(needsReanalysis ? "triggering re-analysis" : "hiding indicator") (possibly switched conversation)", category: Logger.analysis)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // For apps with unreliable AX, don't hide indicators during focus bounces
                // Just trigger re-analysis to update errors
                if needsSpecialHandling {
                    currentErrors.removeAll()
                    lastAnalyzedText = ""
                    positionResolver.clearCache()

                    // Trigger fresh analysis
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.mediumDelay) { [weak self] in
                        guard let self,
                              let context = textMonitor.currentContext,
                              !currentText.isEmpty else { return }
                        handleTextChange(currentText, in: context)
                    }
                    return
                }

                // Always hide UI elements for other apps
                if !isManualStyleCheckActive {
                    floatingIndicator.hide()
                }
                errorOverlay.hide()
                suggestionPopover.hide()
                DebugBorderWindow.clearAll()

                // For Mac Catalyst apps, clear errors and trigger fresh analysis
                // For other apps, let the normal AXValueChanged notification handle re-analysis
                if isCatalystApp {
                    currentErrors.removeAll()
                    lastAnalyzedText = ""
                    positionResolver.clearCache()

                    // Trigger fresh analysis after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.longDelay) { [weak self] in
                        guard let self,
                              let context = textMonitor.currentContext,
                              !currentText.isEmpty else { return }
                        handleTextChange(currentText, in: context)
                    }
                }
            }
        }
    }

    /// Extract text from an AXUIElement synchronously
    /// Used by text validation timer to check if content has changed
    func extractTextSynchronously(from element: AXUIElement) -> String? {
        // CRITICAL: Check watchdog BEFORE making any AX calls
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? "unknown"
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("extractTextSynchronously: Skipping - watchdog active for \(bundleID)", category: Logger.analysis)
            return nil
        }

        // First, try app-specific extraction via ContentParser
        if let parserBundleID = textMonitor.currentContext?.bundleIdentifier {
            let parser = contentParserFactory.parser(for: parserBundleID)
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

        // CRITICAL: Check watchdog BEFORE making any AX calls
        // This prevents freeze when Outlook or other overlays make AX API unresponsive
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? "unknown"
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("Window monitoring: Skipping position check - watchdog active for \(bundleID)", category: Logger.analysis)
            return
        }

        guard let currentFrame = windowFrame(for: element) else {
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

        // Track element frame separately for apps where the element can move without window changes:
        // - Mac Catalyst apps: text input field shrinks when message sent
        // - Web-based apps: element shifts when sidebar is toggled (Slack, Claude, ChatGPT, Perplexity, etc.)
        if let context = textMonitor.currentContext {
            let bundleID = context.bundleIdentifier
            let behavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
            let isWebBasedApp = behavior.knownQuirks.contains(.webBasedRendering)
            if context.isMacCatalystApp || isWebBasedApp {
                checkElementFrameForApps(element: element, isCatalyst: context.isMacCatalystApp)
            }
        }

        // Check if position or size has changed
        if let lastFrame = lastWindowFrame {
            let positionThreshold: CGFloat = 5.0 // Movement threshold in pixels
            let sizeThreshold: CGFloat = 5.0 // Size change threshold in pixels

            let positionDistance = hypot(currentFrame.origin.x - lastFrame.origin.x, currentFrame.origin.y - lastFrame.origin.y)
            let widthChange = abs(currentFrame.width - lastFrame.width)
            let heightChange = abs(currentFrame.height - lastFrame.height)

            let positionChanged = positionDistance > positionThreshold
            let sizeChanged = widthChange > sizeThreshold || heightChange > sizeThreshold

            if positionChanged || sizeChanged {
                if sizeChanged {
                    Logger.debug("Window monitoring: Resize detected - width: \(widthChange)px, height: \(heightChange)px", category: Logger.analysis)
                    lastResizeTime = Date() // Track resize time for Electron settling
                }
                if positionChanged {
                    Logger.debug("Window monitoring: Movement detected - distance: \(positionDistance)px", category: Logger.analysis)
                }

                // For web-based apps, resize events are typically sidebar toggles or internal layout changes.
                // Don't hide overlays for these - let the element frame monitoring handle smooth updates.
                // Only hide overlays for position-only changes (actual window dragging).
                let isWebBasedApp = textMonitor.currentContext.flatMap { context in
                    AppBehaviorRegistry.shared.behavior(for: context.bundleIdentifier).knownQuirks.contains(.webBasedRendering)
                } ?? false

                if isWebBasedApp, sizeChanged {
                    // Web-based app resize (sidebar toggle) - clear cache and wait for stability.
                    // Don't call errorOverlay.hide() - it will clear stale underlines internally
                    // without hiding the window, avoiding a flash.
                    Logger.debug("Window monitoring: Web-based app resize - triggering stability handler (sidebar toggle)", category: Logger.analysis)
                    positionResolver.clearCache()
                    // Trigger sidebar toggle handling to wait for AX stability
                    handleElementPositionChangeInElectronApp()
                } else {
                    // Window is moving (drag) or non-Electron resize - hide overlays immediately
                    handleWindowMovementStarted()
                }
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

    /// Check element frame changes for Mac Catalyst and Electron apps
    /// - Mac Catalyst: Detects message sent (shrink), typing (grow), conversation switch (position)
    /// - Electron apps: Detects sidebar toggle (position change without window change)
    func checkElementFrameForApps(element: AXUIElement, isCatalyst: Bool) {
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
            let significantPositionChange = positionChange > 10.0 // Element moved significantly

            if significantHeightChange || significantPositionChange {
                if isCatalyst {
                    // Mac Catalyst-specific handling
                    if significantPositionChange {
                        // Element position changed significantly - conversation was likely switched
                        Logger.debug("Element monitoring: Element position changed by \(positionChange)px in Mac Catalyst app - triggering re-analysis (conversation switch)", category: Logger.analysis)
                        handleConversationSwitchInChatApp(element: element)
                    } else if significantHeightChange, heightChange < 0, !currentErrors.isEmpty || floatingIndicator.isVisible {
                        // Text field shrunk - message was likely sent
                        Logger.debug("Element monitoring: Text field shrunk by \(abs(heightChange))px in Mac Catalyst app - clearing errors", category: Logger.analysis)
                        handleMessageSentInChatApp()
                    } else if significantHeightChange, heightChange > 0, !currentErrors.isEmpty {
                        // Text field grew - user is typing more, text positions shifted
                        Logger.debug("Element monitoring: Text field grew by \(heightChange)px in Mac Catalyst app - invalidating positions", category: Logger.analysis)
                        positionResolver.clearCache()
                        errorOverlay.hide()
                    }
                } else {
                    // Electron app handling - sidebar toggle or UI layout change
                    if significantPositionChange {
                        // Skip if position change is very large (>500px) - this indicates focus changed
                        // to a different element, not an actual sidebar toggle (which is typically 200-400px)
                        if positionChange > 500 {
                            // Very large position change - likely a different element being monitored
                            // (e.g., focus changed from message list back to compose field)
                            // Just reset tracking, don't trigger sidebar toggle handling
                            Logger.debug("Element monitoring: Large position change (\(positionChange)px) in Electron app - resetting element tracking (likely different element)", category: Logger.analysis)
                            lastElementFrame = currentElementFrame
                            return
                        }

                        // Skip if already handling a sidebar toggle (stabilization in progress)
                        // This prevents double detection during animations and restarts of the
                        // stabilization process that cause flickering
                        if sidebarToggleStartTime != nil {
                            Logger.trace("Element monitoring: Skipping position change - sidebar toggle handling already in progress", category: Logger.analysis)
                            lastElementFrame = currentElementFrame
                            return
                        }

                        Logger.debug("Element monitoring: Element position changed by \(positionChange)px in Electron app (sidebar toggle?) - triggering stability handler", category: Logger.analysis)
                        // Don't call errorOverlay.hide() - ErrorOverlay will clear stale underlines
                        // internally without hiding the window, avoiding a flash.
                        handleElementPositionChangeInElectronApp()
                    }
                }
            }
        } else {
            Logger.debug("Element monitoring: Initial element frame: \(currentElementFrame)", category: Logger.analysis)
        }

        lastElementFrame = currentElementFrame
    }

    /// Handle element position change in Electron apps (e.g., sidebar toggle)
    /// Clears position cache and waits for AX API to settle before refreshing underlines.
    /// Note: Underlines should be hidden before calling this to avoid stale positions.
    /// The capsule indicator stays visible throughout.
    func handleElementPositionChangeInElectronApp() {
        // Clear position cache since element position changed
        positionResolver.clearCache()

        // Reset stability tracking for sidebar toggle
        lastCharacterBounds = nil
        contentStabilityCount = 0
        sidebarToggleStartTime = Date()

        // Tell ErrorOverlay not to hide on 0 underlines during sidebar toggle
        errorOverlay.isSidebarToggleInProgress = true

        // Wait for AX API to settle, then verify character bounds are stable
        // Electron apps can take 300-500ms for AX layer to update after UI changes
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.axBoundsStabilizationDelay) { [weak self] in
            self?.waitForCharacterBoundsStability()
        }
    }

    /// Wait for character bounds to stabilize after element position change
    /// This ensures the AX API has fully updated before we recalculate underline positions
    private func waitForCharacterBoundsStability() {
        guard let element = textMonitor.monitoredElement,
              let context = textMonitor.currentContext,
              !currentErrors.isEmpty else { return }

        // Maximum wait time of 1 second to prevent infinite loops
        if let startTime = sidebarToggleStartTime,
           Date().timeIntervalSince(startTime) > 1.0
        {
            Logger.debug("Element monitoring: Timeout waiting for stability - refreshing anyway", category: Logger.analysis)
            positionResolver.clearCache()
            _ = errorOverlay.update(errors: currentErrors, element: element, context: context)
            lastCharacterBounds = nil
            contentStabilityCount = 0

            // Keep sidebarToggleStartTime set for a grace period to prevent
            // late position changes or click-based refreshes from causing flicker
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.sidebarToggleGracePeriod) { [weak self] in
                self?.sidebarToggleStartTime = nil
                self?.errorOverlay.isSidebarToggleInProgress = false
                Logger.trace("Element monitoring: Sidebar toggle grace period ended (after timeout)", category: Logger.analysis)
            }
            return
        }

        // Get current character bounds
        let currentCharBounds = firstCharacterBounds(for: element)

        if let lastBounds = lastCharacterBounds, let currBounds = currentCharBounds {
            let positionDelta = hypot(currBounds.origin.x - lastBounds.origin.x,
                                      currBounds.origin.y - lastBounds.origin.y)

            if positionDelta < 3.0 {
                // Bounds are stable - increment counter
                contentStabilityCount += 1

                // Require 2 consecutive stable samples (faster recovery)
                if contentStabilityCount >= 2 {
                    Logger.debug("Element monitoring: AX API settled - refreshing underlines", category: Logger.analysis)
                    positionResolver.clearCache()
                    _ = errorOverlay.update(errors: currentErrors, element: element, context: context)
                    lastCharacterBounds = nil
                    contentStabilityCount = 0

                    // Keep sidebarToggleStartTime set for a grace period to prevent
                    // late position changes or click-based refreshes from causing flicker
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.sidebarToggleGracePeriod) { [weak self] in
                        self?.sidebarToggleStartTime = nil
                        self?.errorOverlay.isSidebarToggleInProgress = false
                        Logger.trace("Element monitoring: Sidebar toggle grace period ended", category: Logger.analysis)
                    }
                    return
                }
            } else {
                // Still changing - reset counter
                contentStabilityCount = 0
            }
        }

        lastCharacterBounds = currentCharBounds

        // Check again with faster polling
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.boundsStabilityPollInterval) { [weak self] in
            self?.waitForCharacterBoundsStability()
        }
    }

    /// Handle conversation switch in a Mac Catalyst chat app
    /// Hides overlays and triggers fresh analysis since the text content has likely changed
    func handleConversationSwitchInChatApp(element _: AXUIElement) {
        // Record the time to prevent validateCurrentText() from racing with us
        lastConversationSwitchTime = Date()

        // Capture the text BEFORE clearing state - we'll use this to detect if text actually changed
        // Some messenger apps (WhatsApp) may return stale text after conversation switches
        let textBeforeSwitch = lastAnalyzedText

        // Hide all overlays
        floatingIndicator.hide()
        errorOverlay.hide()
        suggestionPopover.hide()
        DebugBorderWindow.clearAll()

        // Clear position cache
        positionResolver.clearCache()

        // Clear current errors and text tracking - the text has changed
        currentErrors.removeAll()
        lastAnalyzedText = ""
        previousText = "" // Clear previousText so handleTextChange will process the text

        // Get app-specific delay from MessengerBehavior
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? ""
        let delay = MessengerBehavior.conversationSwitchDelay(for: bundleID)

        // Trigger fresh analysis after a delay (let the UI settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // Re-read the text and trigger analysis
            guard let monitoredElement = textMonitor.monitoredElement,
                  let context = textMonitor.currentContext,
                  let text = extractTextSynchronously(from: monitoredElement),
                  !text.isEmpty
            else {
                return
            }

            // Check for stale AX data using MessengerBehavior
            // Apps like WhatsApp may return unchanged text after conversation switch
            if MessengerBehavior.isTextLikelyStale(
                currentText: text,
                previousText: textBeforeSwitch,
                bundleID: context.bundleIdentifier
            ) {
                Logger.debug("Messenger: Text unchanged after conversation switch (\(text.count) chars) - skipping re-analysis (stale AX data)", category: Logger.analysis)
                return
            }

            handleTextChange(text, in: context)
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
           Date().timeIntervalSince(replacementTime) < 1.5
        {
            Logger.debug("Scroll monitoring: Ignoring scroll - just applied suggestion", category: Logger.analysis)
            return
        }

        // Get app-specific scroll behavior from AppBehaviorRegistry
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? ""
        let appBehavior = AppBehaviorRegistry.shared.behavior(for: bundleID)

        // Check if this app should hide overlays on scroll
        // Some apps (like Slack) have unreliable scroll events or scroll affects
        // message list, not compose field - skip hiding to avoid flickering
        if !appBehavior.scrollBehavior.hideOnScrollStart {
            Logger.trace("Scroll monitoring: Skipping scroll hide for \(appBehavior.displayName) (hideOnScrollStart=false)", category: Logger.analysis)
            return
        }

        if !overlaysHiddenDueToScroll {
            Logger.debug("Scroll monitoring: Scroll started - hiding underlines only", category: Logger.analysis)
            overlaysHiddenDueToScroll = true

            // Notify state machine of scroll event
            overlayStateMachine.handle(.scrollStarted)

            // Hide underlines only (not floating indicator)
            errorOverlay.hide()
            suggestionPopover.hide()

            // Clear the position cache so underlines are recalculated after scroll
            positionResolver.clearCache()
        }

        // Get restore delay from app behavior
        let restoreDelay = appBehavior.scrollBehavior.reshowDelay

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

        // Notify state machine of scroll end
        overlayStateMachine.handle(.scrollEnded)

        // Re-show underlines using cached errors (positions will be recalculated)
        if let element = textMonitor.monitoredElement,
           let context = textMonitor.currentContext,
           !currentErrors.isEmpty
        {
            let underlinesRestored = errorOverlay.update(errors: currentErrors, element: element, context: context)
            Logger.debug("Scroll monitoring: Restored \(underlinesRestored) underlines from \(currentErrors.count) cached errors", category: Logger.analysis)
        }
    }

    /// Window frame for the given element
    func windowFrame(for element: AXUIElement) -> CGRect? {
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
               let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat]
            {
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
    func windowPosition(for element: AXUIElement) -> CGPoint? {
        windowFrame(for: element)?.origin
    }

    /// Handle message sent in a Mac Catalyst chat app (text field shrunk)
    /// Clears all errors and hides indicators since the text is now empty
    func handleMessageSentInChatApp() {
        floatingIndicator.hide()
        errorOverlay.hide()
        suggestionPopover.hide()
        currentErrors.removeAll()
        lastAnalyzedText = ""
        positionResolver.clearCache()
        DebugBorderWindow.clearAll()
    }

    /// Handle window movement started
    func handleWindowMovementStarted() {
        guard !overlaysHiddenDueToMovement else { return }

        Logger.debug("Window monitoring: Movement started - hiding all overlays", category: Logger.analysis)
        overlaysHiddenDueToMovement = true
        positionSyncRetryCount = 0 // Reset retry counter for new movement cycle
        lastElementPosition = nil // Reset element position tracking

        // Notify state machine of window movement
        overlayStateMachine.handle(.windowMoveStarted)

        // Immediately hide all overlays
        errorOverlay.hide()
        floatingIndicator.hide()
        suggestionPopover.hide()

        // Clear debug border windows as well
        DebugBorderWindow.clearAll()

        // CRITICAL: Clear the position cache so underlines are recalculated at new window position
        // The cache stores screen coordinates which become stale when the window moves
        positionResolver.clearCache()

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
        positionResolver.clearCache()

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
            floatingIndicator.updateWithContext(errors: currentErrors, readabilityResult: currentReadabilityResult, context: context, sourceText: lastAnalyzedText)
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
        windowMovementDebounceTimer = nil // Clear timer reference so new timer can be created

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
        guard let cgWindowPosition = windowPosition(for: element) else {
            Logger.debug("Window monitoring: Cannot get CGWindow position - showing overlays anyway", category: Logger.analysis)
            overlaysHiddenDueToMovement = false
            positionSyncRetryCount = 0
            lastElementPosition = nil
            contentStabilityCount = 0
            lastCharacterBounds = nil
            positionResolver.clearCache()
            let sourceText = currentSegment?.content ?? ""
            applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
            updateDebugBorders()
            return
        }

        // Check 1: Verify window position sync between AX and CGWindow
        var needsRetry = false
        if let axWindowPos = axWindowPosition(for: element) {
            let windowDelta = hypot(cgWindowPosition.x - axWindowPos.x, cgWindowPosition.y - axWindowPos.y)
            let toleranceThreshold: CGFloat = 5.0 // Tighter tolerance for window position

            if windowDelta > toleranceThreshold {
                Logger.debug("Window monitoring: Window position mismatch - AX: \(axWindowPos), CG: \(cgWindowPosition), delta: \(windowDelta)px", category: Logger.analysis)
                needsRetry = true
            }
        }

        // Check 2: Verify element position is stable (not still updating)
        if let currentElementPos = axElementPosition(for: element) {
            if let lastPos = lastElementPosition {
                let elementDelta = hypot(currentElementPos.x - lastPos.x, currentElementPos.y - lastPos.y)
                let elementTolerance: CGFloat = 3.0 // Very tight tolerance for element stability

                if elementDelta > elementTolerance {
                    Logger.debug("Window monitoring: Element position still changing - last: \(lastPos), current: \(currentElementPos), delta: \(elementDelta)px", category: Logger.analysis)
                    needsRetry = true
                }
            }
            lastElementPosition = currentElementPos
        }

        // If either check failed and we have retries left, wait and retry
        if needsRetry, positionSyncRetryCount < maxPositionSyncRetries {
            positionSyncRetryCount += 1
            Logger.debug("Window monitoring: Position not stable - retry \(positionSyncRetryCount)/\(maxPositionSyncRetries) in 50ms", category: Logger.analysis)

            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.shortDelay) { [weak self] in
                guard let self else { return }
                if overlaysHiddenDueToMovement {
                    reshowOverlaysAfterMovement()
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
                guard let self else { return }
                if overlaysHiddenDueToMovement {
                    finalizeOverlayReshow()
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
        let appBehavior = AppBehaviorRegistry.shared.behavior(for: bundleID)
        let isWebBasedApp = appBehavior.knownQuirks.contains(.webBasedRendering)

        // For web-based apps after resize, verify ACTUAL CONTENT position stability
        // Notion centers content blocks AFTER the window resize completes
        // We must track character bounds, not just element position
        if lastResizeTime != nil, isWebBasedApp {
            guard let element = textMonitor.monitoredElement else {
                completeOverlayReshow()
                return
            }

            // Get character bounds for a character near the start of text
            // This detects content block repositioning that element position misses
            let currentCharBounds = firstCharacterBounds(for: element)

            if let lastBounds = lastCharacterBounds, let currBounds = currentCharBounds {
                // Check both position AND size changes (text reflow can affect both)
                let positionDelta = hypot(currBounds.origin.x - lastBounds.origin.x,
                                          currBounds.origin.y - lastBounds.origin.y)
                let widthDelta = abs(currBounds.width - lastBounds.width)

                if positionDelta < 3.0, widthDelta < 2.0 {
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
                guard let self, overlaysHiddenDueToMovement else { return }
                finalizeOverlayReshow()
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
                    guard let self, overlaysHiddenDueToMovement else { return }
                    completeOverlayReshow()
                }
                return
            }
        }

        completeOverlayReshow()
    }

    /// Bounds of the first character in the text element
    /// This tracks actual content position, not just the element container
    func firstCharacterBounds(for element: AXUIElement) -> CGRect? {
        // CRITICAL: Check watchdog BEFORE making any AX calls
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? "unknown"
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("firstCharacterBounds: Skipping - watchdog active for \(bundleID)", category: Logger.analysis)
            return nil
        }

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
              let bounds = safeAXValueGetRect(value)
        else {
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

        // Notify state machine that window movement is complete
        overlayStateMachine.handle(.windowMoveEnded)

        // CRITICAL: Clear position cache AGAIN before re-showing overlays
        // The cache was cleared when movement started, but async analysis operations
        // running during the debounce period might have repopulated it with stale positions
        // (calculated from the old window location). Clear it now to ensure fresh positions.
        positionResolver.clearCache()

        // Re-show overlays by triggering a re-filter of current errors
        // This will recalculate positions and show overlays at the new location
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)

        // Also update debug borders
        updateDebugBorders()
    }

    /// AX window position for the given element (walks up to find window)
    /// Returns position in Quartz coordinates (top-left origin) for comparison with CGWindow
    func axWindowPosition(for element: AXUIElement) -> CGPoint? {
        // CRITICAL: Check watchdog BEFORE making any AX calls
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? "unknown"
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("axWindowPosition: Skipping - watchdog active for \(bundleID)", category: Logger.analysis)
            return nil
        }

        // Walk up to find the window element
        var windowElement: AXUIElement?
        var currentElement: AXUIElement? = element

        for _ in 0 ..< 10 {
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

    /// AX element position directly (for stability checking)
    /// Returns position in Quartz coordinates (top-left origin)
    func axElementPosition(for element: AXUIElement) -> CGPoint? {
        // CRITICAL: Check watchdog BEFORE making any AX calls
        let bundleID = textMonitor.currentContext?.bundleIdentifier ?? "unknown"
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("axElementPosition: Skipping - watchdog active for \(bundleID)", category: Logger.analysis)
            return nil
        }

        return AccessibilityBridge.getElementPosition(element)
    }
}
