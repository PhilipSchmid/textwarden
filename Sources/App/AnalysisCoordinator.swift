//
//  AnalysisCoordinator.swift
//  TextWarden
//
//  Orchestrates text monitoring, grammar analysis, and UI presentation
//

import Foundation
import AppKit
import ApplicationServices
import Combine

/// Debug file logging
func logToDebugFile(_ message: String) {
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

/// Coordinates grammar analysis workflow: monitoring → analysis → UI
class AnalysisCoordinator: ObservableObject {
    static let shared = AnalysisCoordinator()

    /// Text monitor for accessibility
    private let textMonitor = TextMonitor()

    /// Application tracker
    private let applicationTracker = ApplicationTracker.shared

    /// Permission manager
    private let permissionManager = PermissionManager.shared

    /// Suggestion popover
    private let suggestionPopover = SuggestionPopover.shared

    /// Error overlay window for visual underlines (lazy initialization)
    private lazy var errorOverlay: ErrorOverlayWindow = {
        let window = ErrorOverlayWindow()
        print("📱 AnalysisCoordinator: Error overlay window created")
        return window
    }()

    /// Floating error indicator for apps without visual underlines
    private let floatingIndicator = FloatingErrorIndicator.shared

    /// Error cache mapping text segments to detected errors
    private var errorCache: [String: [GrammarErrorModel]] = [:]

    /// Cache metadata for LRU eviction (T085)
    private var cacheMetadata: [String: CacheMetadata] = [:]

    /// Previous text for incremental analysis
    private var previousText: String = ""

    /// Currently displayed errors
    @Published private(set) var currentErrors: [GrammarErrorModel] = []

    /// Current text segment being analyzed
    @Published private(set) var currentSegment: TextSegment?

    /// Currently monitored application context
    private var monitoredContext: ApplicationContext?

    /// Analysis queue for background processing
    private let analysisQueue = DispatchQueue(label: "com.textwarden.analysis", qos: .userInitiated)

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Maximum number of cached documents (T085)
    private let maxCachedDocuments = 10

    /// Cache expiration time in seconds (T084)
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes

    /// Window position tracking
    private var lastWindowPosition: CGPoint?
    private var windowPositionTimer: Timer?
    private var windowMovementDebounceTimer: Timer?
    private var overlaysHiddenDueToMovement = false
    private var overlaysHiddenDueToWindowOffScreen = false
    private var positionSyncRetryCount = 0
    private let maxPositionSyncRetries = 20  // Max 20 retries * 50ms = 1000ms max wait
    private var lastElementPosition: CGPoint?  // Track element position for stability check

    /// Hover switching timer - delays popover switching when hovering from one error to another
    private var hoverSwitchTimer: Timer?
    /// Pending error waiting for delayed hover switch
    private var pendingHoverError: (error: GrammarErrorModel, position: CGPoint, windowFrame: CGRect?)?

    private init() {
        setupMonitoring()
        setupPopoverCallbacks()
        setupOverlayCallbacks()
        setupCalibrationListener()
        // Window position monitoring will be started when we begin monitoring an app
    }

    /// Setup popover callbacks
    private func setupPopoverCallbacks() {
        // Handle apply suggestion (T044, T044a)
        suggestionPopover.onApplySuggestion = { [weak self] error, suggestion in
            guard let self = self else { return }
            self.applyTextReplacement(for: error, with: suggestion)
        }

        // Handle dismiss error (T045, T048)
        suggestionPopover.onDismissError = { [weak self] error in
            guard let self = self else { return }
            self.dismissError(error)
        }

        // Handle ignore rule (T046, T050)
        suggestionPopover.onIgnoreRule = { [weak self] ruleId in
            guard let self = self else { return }
            self.ignoreRulePermanently(ruleId)
        }

        // Handle add to dictionary
        suggestionPopover.onAddToDictionary = { [weak self] error in
            guard let self = self else { return }
            self.addToDictionary(error)
        }

        // Handle mouse entered popover - cancel any pending delayed switches
        suggestionPopover.onMouseEntered = { [weak self] in
            guard let self = self else { return }
            if self.hoverSwitchTimer != nil {
                Logger.debug("AnalysisCoordinator: Mouse entered popover - cancelling delayed switch", category: Logger.analysis)
                self.hoverSwitchTimer?.invalidate()
                self.hoverSwitchTimer = nil
                self.pendingHoverError = nil
            }
        }
    }

    /// Setup listener for calibration changes to refresh underlines
    private func setupCalibrationListener() {
        UserPreferences.shared.$positioningCalibrations
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Refresh underlines when calibration changes
                self.refreshUnderlines()
            }
            .store(in: &cancellables)
    }

    /// Setup overlay callbacks for hover-based popup
    private func setupOverlayCallbacks() {
        errorOverlay.onErrorHover = { [weak self] error, position, windowFrame in
            guard let self = self else { return }

            Logger.debug("AnalysisCoordinator: onErrorHover - error at \(error.start)-\(error.end)", category: Logger.analysis)

            // Cancel any pending hide when mouse enters ANY error
            self.suggestionPopover.cancelHide()

            // Check if popover is currently showing
            let isPopoverShowing = self.suggestionPopover.currentError != nil

            if !isPopoverShowing {
                // No popover showing - show immediately (first hover)
                Logger.debug("AnalysisCoordinator: First hover - showing popover immediately", category: Logger.analysis)
                self.hoverSwitchTimer?.invalidate()
                self.hoverSwitchTimer = nil
                self.pendingHoverError = nil
                self.suggestionPopover.show(
                    error: error,
                    allErrors: self.currentErrors,
                    at: position,
                    constrainToWindow: windowFrame
                )
            } else if self.isSameError(error, as: self.suggestionPopover.currentError) {
                // Same error - just keep showing (cancel any pending switches)
                Logger.debug("AnalysisCoordinator: Same error - keeping popover visible", category: Logger.analysis)
                self.hoverSwitchTimer?.invalidate()
                self.hoverSwitchTimer = nil
                self.pendingHoverError = nil
            } else {
                // Different error - delay the switch to give user time to reach the popover
                Logger.debug("AnalysisCoordinator: Different error - scheduling delayed switch (300ms)", category: Logger.analysis)

                // Cancel any existing timer
                self.hoverSwitchTimer?.invalidate()

                // Store pending hover info
                self.pendingHoverError = (error: error, position: position, windowFrame: windowFrame)

                // Schedule delayed switch (300ms)
                self.hoverSwitchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    guard let self = self,
                          let pending = self.pendingHoverError else { return }

                    Logger.debug("AnalysisCoordinator: Delayed switch timer fired - showing new popover", category: Logger.analysis)

                    self.suggestionPopover.show(
                        error: pending.error,
                        allErrors: self.currentErrors,
                        at: pending.position,
                        constrainToWindow: pending.windowFrame
                    )

                    // Clear timer and pending state
                    self.hoverSwitchTimer = nil
                    self.pendingHoverError = nil
                }
            }
        }

        // Cancel delayed switch when hover ends on underline
        // This prevents the switch if user quickly moves mouse away
        errorOverlay.onHoverEnd = { [weak self] in
            guard let self = self else { return }

            Logger.debug("AnalysisCoordinator: Hover ended on underline", category: Logger.analysis)

            // Cancel any pending delayed switch
            if self.hoverSwitchTimer != nil {
                Logger.debug("AnalysisCoordinator: Cancelling delayed switch (mouse left underline)", category: Logger.analysis)
                self.hoverSwitchTimer?.invalidate()
                self.hoverSwitchTimer = nil
                self.pendingHoverError = nil
            }

            // Don't schedule hide here - let the popover's own mouse tracking handle it
            // This allows users to freely move from underline to popover without hiding
        }
    }

    /// Check if two errors are the same (by position)
    private func isSameError(_ error1: GrammarErrorModel?, as error2: GrammarErrorModel?) -> Bool {
        guard let e1 = error1, let e2 = error2 else { return false }
        return e1.start == e2.start && e1.end == e2.end
    }

    /// Setup text monitoring and application tracking (T037)
    private func setupMonitoring() {
        // Monitor application changes
        applicationTracker.onApplicationChange = { [weak self] context in
            MenuBarController.shared?.updateMenu()

            guard let self = self else { return }

            Logger.debug("AnalysisCoordinator: App switched to \(context.applicationName) (\(context.bundleIdentifier))", category: Logger.analysis)

            // Check if this is the same app we're already monitoring
            let isSameApp = self.monitoredContext?.bundleIdentifier == context.bundleIdentifier

            // CRITICAL: Stop monitoring the previous app to prevent delayed AX notifications
            // from showing overlays for the old app after switching
            if !isSameApp {
                Logger.trace("AnalysisCoordinator: Stopping monitoring for previous app", category: Logger.analysis)
                self.textMonitor.stopMonitoring()
            }

            self.errorOverlay.hide()
            self.suggestionPopover.hide()
            self.floatingIndicator.hide()

            // Cancel any pending delayed switches
            self.hoverSwitchTimer?.invalidate()
            self.hoverSwitchTimer = nil
            self.pendingHoverError = nil

            // Start monitoring new application if enabled
            if context.shouldCheck() {
                if isSameApp {
                    Logger.debug("AnalysisCoordinator: Returning to same app - forcing immediate re-analysis", category: Logger.analysis)
                    // CRITICAL: Set context even for same app (might have been cleared when switching away)
                    self.monitoredContext = context
                    // Same app - force immediate re-analysis by clearing previousText
                    self.previousText = ""

                    if let element = self.textMonitor.monitoredElement {
                        self.textMonitor.extractText(from: element)
                    }
                } else {
                    Logger.debug("AnalysisCoordinator: New application - starting monitoring", category: Logger.analysis)
                    self.monitoredContext = context  // Set BEFORE startMonitoring
                    self.startMonitoring(context: context)

                    // Trigger immediate extraction, then retry a few times to catch delayed element readiness
                    if let element = self.textMonitor.monitoredElement {
                        Logger.debug("AnalysisCoordinator: Immediate text extraction", category: Logger.analysis)
                        self.textMonitor.extractText(from: element)
                    }

                    // Retry after short delays to catch cases where element wasn't ready immediately
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let element = self.textMonitor.monitoredElement {
                            Logger.debug("AnalysisCoordinator: Retry 1 - extracting text", category: Logger.analysis)
                            self.textMonitor.extractText(from: element)
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let element = self.textMonitor.monitoredElement {
                            Logger.debug("AnalysisCoordinator: Retry 2 - extracting text", category: Logger.analysis)
                            self.textMonitor.extractText(from: element)
                        }
                    }
                }
            } else {
                Logger.trace("AnalysisCoordinator: Application not in check list - stopping monitoring", category: Logger.analysis)
                self.stopMonitoring()
                self.monitoredContext = nil
            }
        }

        // Monitor text changes (T038)
        textMonitor.onTextChange = { [weak self] text, context in
            guard let self = self else { return }
            self.handleTextChange(text, in: context)
        }

        // Monitor permission changes
        permissionManager.$isPermissionGranted
            .sink { [weak self] isGranted in
                print("🔐 AnalysisCoordinator: Permission status changed to \(isGranted)")
                if isGranted {
                    self?.resumeMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        // CRITICAL FIX: Check if there's already an active application
        if let currentApp = applicationTracker.activeApplication {
            Logger.debug("AnalysisCoordinator: Found existing active application: \(currentApp.applicationName) (\(currentApp.bundleIdentifier))", category: Logger.analysis)
            Logger.debug("AnalysisCoordinator: Should check? \(currentApp.shouldCheck())", category: Logger.analysis)
            Logger.debug("AnalysisCoordinator: Context isEnabled: \(currentApp.isEnabled)", category: Logger.analysis)
            Logger.debug("AnalysisCoordinator: Global isEnabled: \(UserPreferences.shared.isEnabled)", category: Logger.analysis)
            Logger.debug("AnalysisCoordinator: Is in disabled apps? \(UserPreferences.shared.disabledApplications.contains(currentApp.bundleIdentifier))", category: Logger.analysis)
            if currentApp.shouldCheck() {
                Logger.debug("AnalysisCoordinator: Starting monitoring for existing app", category: Logger.analysis)
                self.monitoredContext = currentApp  // Set BEFORE startMonitoring
                startMonitoring(context: currentApp)
            } else {
                Logger.debug("AnalysisCoordinator: Existing app not in check list", category: Logger.analysis)
            }
        } else {
            Logger.debug("AnalysisCoordinator: No active application detected yet", category: Logger.analysis)
        }
    }

    /// Start monitoring a specific application
    private func startMonitoring(context: ApplicationContext) {
        Logger.debug("AnalysisCoordinator: startMonitoring called for \(context.applicationName)", category: Logger.analysis)
        guard permissionManager.isPermissionGranted else {
            Logger.debug("AnalysisCoordinator: Accessibility permissions not granted", category: Logger.analysis)
            return
        }

        Logger.debug("AnalysisCoordinator: Permission granted, calling textMonitor.startMonitoring", category: Logger.analysis)
        textMonitor.startMonitoring(
            processID: context.processID,
            bundleIdentifier: context.bundleIdentifier,
            appName: context.applicationName
        )
        Logger.debug("AnalysisCoordinator: textMonitor.startMonitoring completed", category: Logger.analysis)

        // Start window position monitoring now that we have an element to monitor
        startWindowPositionMonitoring()
    }

    /// Stop monitoring
    private func stopMonitoring() {
        textMonitor.stopMonitoring()
        currentErrors = []
        currentSegment = nil
        previousText = ""  // Clear previous text so analysis runs when we return
        errorOverlay.hide()
        floatingIndicator.hide()
        suggestionPopover.hide()
        DebugBorderWindow.clearAll()  // Clear debug borders when stopping
        MenuBarController.shared?.setIconState(.active)
        stopWindowPositionMonitoring()
    }

    /// Resume monitoring after permission grant
    private func resumeMonitoring() {
        if let context = applicationTracker.activeApplication,
           context.shouldCheck() {
            self.monitoredContext = context  // Set BEFORE startMonitoring
            startMonitoring(context: context)
        }
    }

    // MARK: - Window Movement Detection

    /// Start monitoring window position to detect movement
    private func startWindowPositionMonitoring() {
        Logger.debug("Window monitoring: Starting position monitoring", category: Logger.analysis)
        // Poll window position every 50ms (20 times per second)
        // This is frequent enough to catch window movement quickly
        windowPositionTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkWindowPosition()
        }
        RunLoop.main.add(windowPositionTimer!, forMode: .common)
        Logger.debug("Window monitoring: Timer scheduled on main RunLoop", category: Logger.analysis)
    }

    /// Stop monitoring window position
    private func stopWindowPositionMonitoring() {
        windowPositionTimer?.invalidate()
        windowPositionTimer = nil
        windowMovementDebounceTimer?.invalidate()
        windowMovementDebounceTimer = nil
        lastWindowPosition = nil
        overlaysHiddenDueToMovement = false
        overlaysHiddenDueToWindowOffScreen = false
    }

    /// Check if window has moved
    private func checkWindowPosition() {
        guard let element = textMonitor.monitoredElement else {
            lastWindowPosition = nil
            DebugBorderWindow.clearAll()
            return
        }

        guard let currentPosition = getWindowPosition(for: element) else {
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

        // Check if position has changed
        if let lastPosition = lastWindowPosition {
            let threshold: CGFloat = 5.0  // Movement threshold in pixels
            let distance = hypot(currentPosition.x - lastPosition.x, currentPosition.y - lastPosition.y)

            if distance > threshold {
                Logger.debug("Window monitoring: Movement detected - distance: \(distance)px, from: \(lastPosition) to: \(currentPosition)", category: Logger.analysis)
                // Window is moving - hide overlays immediately
                handleWindowMovementStarted()
            } else {
                // Window stopped moving - show overlays after debounce
                handleWindowMovementStopped()

                // Update debug borders continuously when window is not moving
                // This handles frontmost status changes (e.g., another window comes to front)
                if !overlaysHiddenDueToMovement {
                    updateDebugBorders()
                }
            }
        } else {
            Logger.debug("Window monitoring: Initial position set: \(currentPosition)", category: Logger.analysis)
            // Initial position - update debug borders
            updateDebugBorders()
        }

        lastWindowPosition = currentPosition
    }

    /// Get window position for the given element
    private func getWindowPosition(for element: AXUIElement) -> CGPoint? {
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
                return CGPoint(x: x, y: y)
            }
        }

        return nil
    }

    /// Handle window movement started
    private func handleWindowMovementStarted() {
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
    private func handleWindowMovementStopped() {
        guard overlaysHiddenDueToMovement else { return }

        // Don't create a new timer if one is already scheduled
        // This prevents the timer from being constantly reset while the window is stationary
        guard windowMovementDebounceTimer == nil else { return }

        Logger.debug("Window monitoring: Movement stopped - scheduling re-show after 150ms", category: Logger.analysis)

        // Wait 150ms after movement stops before re-showing overlays
        // This provides a snappy UX while avoiding flickering during multi-step drags
        windowMovementDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.reshowOverlaysAfterMovement()
        }
    }

    /// Handle window going off-screen (minimized, hidden, or closed)
    private func handleWindowOffScreen() {
        guard !overlaysHiddenDueToWindowOffScreen else { return }

        Logger.debug("Window monitoring: Window off-screen - hiding all overlays", category: Logger.analysis)
        overlaysHiddenDueToWindowOffScreen = true
        lastWindowPosition = nil

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
    private func handleWindowBackOnScreen() {
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
            floatingIndicator.updateWithContext(errors: currentErrors, context: context)
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
    private func reshowOverlaysAfterMovement() {
        Logger.debug("Window monitoring: Re-showing overlays at new position", category: Logger.analysis)
        windowMovementDebounceTimer = nil  // Clear timer reference so new timer can be created

        // CRITICAL: Verify that AX API position is in sync with CGWindow position
        // CGWindowList updates immediately, but AX API may lag behind
        // If positions don't match, wait and retry to avoid showing overlays at stale position
        guard let element = textMonitor.monitoredElement else {
            overlaysHiddenDueToMovement = false
            positionSyncRetryCount = 0
            lastElementPosition = nil
            return
        }

        // Get CGWindow position (source of truth - updates immediately)
        guard let cgWindowPosition = getWindowPosition(for: element) else {
            Logger.debug("Window monitoring: Cannot get CGWindow position - showing overlays anyway", category: Logger.analysis)
            overlaysHiddenDueToMovement = false
            positionSyncRetryCount = 0
            lastElementPosition = nil
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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
    private func finalizeOverlayReshow() {
        overlaysHiddenDueToMovement = false
        positionSyncRetryCount = 0
        lastElementPosition = nil

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
    private func getAXWindowPosition(for element: AXUIElement) -> CGPoint? {
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
            guard parentResult == .success, let parent = parentValue else { break }
            currentElement = (parent as! AXUIElement)
        }

        guard let window = windowElement else { return nil }

        // Get position from AX window
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              let positionValue = positionValue else {
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            return nil
        }

        // Return in Quartz coordinates (AX API already returns Quartz coords)
        return position
    }

    /// Get AX element position directly (for stability checking)
    /// Returns position in Quartz coordinates (top-left origin)
    private func getAXElementPosition(for element: AXUIElement) -> CGPoint? {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              let positionValue = positionValue else {
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            return nil
        }

        return position
    }

    // MARK: - Debug Border Management

    /// Update debug borders based on current window position and visibility
    /// Called periodically to keep debug borders in sync with monitored window
    private func updateDebugBorders() {
        guard let element = textMonitor.monitoredElement else {
            DebugBorderWindow.clearAll()
            return
        }

        // Check if any debug borders are enabled
        let showCGWindow = UserPreferences.shared.showDebugBorderCGWindowCoords
        let showCocoa = UserPreferences.shared.showDebugBorderCocoaCoords
        let showTextBounds = UserPreferences.shared.showDebugBorderTextFieldBounds

        guard showCGWindow || showCocoa || showTextBounds else {
            DebugBorderWindow.clearAll()
            return
        }

        // Get window info and check if it's frontmost
        guard let windowInfo = getWindowInfoForElement(element) else {
            DebugBorderWindow.clearAll()
            return
        }

        // Check if the window is in front (not occluded by other app windows)
        guard windowInfo.isFrontmost else {
            DebugBorderWindow.clearAll()
            return
        }

        // Clear existing and redraw at new position
        DebugBorderWindow.clearAll()

        if showCGWindow {
            _ = DebugBorderWindow(frame: windowInfo.cocoaFrame, color: .systemBlue, label: "CGWindow coords")
        }

        if showCocoa {
            _ = DebugBorderWindow(frame: windowInfo.cocoaFrame, color: .systemGreen, label: "Cocoa coords")
        }

        // Note: Text Field Bounds (red) is drawn by ErrorOverlayWindow's UnderlineView
        // It will be shown/hidden based on the showDebugBorderTextFieldBounds preference
    }

    /// Window info structure for debug border display
    private struct WindowInfo {
        let cgFrame: CGRect      // CGWindow coordinates (top-left origin)
        let cocoaFrame: CGRect   // Cocoa coordinates (bottom-left origin)
        let isFrontmost: Bool    // Whether this window is the frontmost for its app
    }

    /// Get window info for the monitored element, including frontmost status
    private func getWindowInfoForElement(_ element: AXUIElement) -> WindowInfo? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }

        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find the frontmost normal window overall (to check if our app is in front)
        var frontmostNormalWindowPID: Int32?
        for windowInfo in windowList {
            if let layer = windowInfo[kCGWindowLayer as String] as? Int,
               layer == 0,  // Normal window layer
               let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32 {
                frontmostNormalWindowPID = windowPID
                break  // First match is frontmost
            }
        }

        // Find the LARGEST window for our monitored app
        // This ensures we get the main application window, not floating panels/popups like Cmd+F search
        var bestWindow: (cgFrame: CGRect, cocoaFrame: CGRect, area: CGFloat)?

        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == pid,
               let layer = windowInfo[kCGWindowLayer as String] as? Int,
               layer == 0,  // Normal window layer
               let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {

                let x = boundsDict["X"] ?? 0
                let y = boundsDict["Y"] ?? 0
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0
                let area = width * height

                // Skip tiny windows (< 100x100, likely tooltips or popups)
                guard width >= 100 && height >= 100 else { continue }

                let cgFrame = CGRect(x: x, y: y, width: width, height: height)

                // Convert to Cocoa coordinates
                let totalScreenHeight = NSScreen.screens.reduce(0) { max($0, $1.frame.maxY) }
                let cocoaY = totalScreenHeight - y - height
                let cocoaFrame = CGRect(x: x, y: cocoaY, width: width, height: height)

                // Keep track of the largest window
                if bestWindow == nil || area > bestWindow!.area {
                    bestWindow = (cgFrame: cgFrame, cocoaFrame: cocoaFrame, area: area)
                }
            }
        }

        if let best = bestWindow {
            let isFrontmost = (frontmostNormalWindowPID == pid)
            return WindowInfo(cgFrame: best.cgFrame, cocoaFrame: best.cocoaFrame, isFrontmost: isFrontmost)
        }

        return nil
    }

    /// Refresh underlines when calibration settings change
    /// This re-renders existing underlines with updated positioning
    func refreshUnderlines() {
        guard !currentErrors.isEmpty else { return }

        Logger.debug("AnalysisCoordinator: Refreshing underlines after calibration change", category: Logger.analysis)

        // Re-apply filters to trigger underline refresh with new calibration
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
    }

    /// Handle text change and trigger analysis (T038)
    private func handleTextChange(_ text: String, in context: ApplicationContext) {
        Logger.debug("AnalysisCoordinator: Text changed in \(context.applicationName) (\(text.count) chars)", category: Logger.analysis)

        // If no element is being monitored (e.g., browser UI element was detected),
        // immediately hide overlays without waiting for async analysis
        // This ensures overlays disappear immediately when user clicks on browser
        // search fields, URL bars, find-in-page, etc.
        if textMonitor.monitoredElement == nil {
            Logger.debug("AnalysisCoordinator: No monitored element - hiding overlays immediately", category: Logger.analysis)
            errorOverlay.hide()
            floatingIndicator.hide()
            suggestionPopover.hide()
            DebugBorderWindow.clearAll()
            // DON'T clear currentErrors and currentSegment - keep them cached so we can
            // immediately restore overlays when user focuses back on the original text field
            // Clear previousText so that when user focuses back on a real text field,
            // analysis will run even if the text content is the same
            previousText = ""
            return
        }

        // We have a valid monitored element - immediately show debug borders
        // This ensures borders appear right away when focus returns from browser UI elements
        // (like Cmd+F search) to real content, without waiting for async analysis
        updateDebugBorders()

        // CRITICAL: If text has changed, hide old underlines IMMEDIATELY
        // This prevents stale underlines from lingering at wrong positions during re-analysis
        // We hide the overlay but keep currentErrors cached so they can be restored if text hasn't actually changed
        if text != previousText {
            Logger.debug("AnalysisCoordinator: Text changed - hiding overlay immediately for re-analysis", category: Logger.analysis)
            errorOverlay.hide()
        }

        // If we have cached errors for this exact text, show them immediately
        // This provides instant feedback when returning from browser UI elements (like Cmd+F)
        // A fresh analysis will still run to catch any changes
        if let cachedSegment = currentSegment,
           cachedSegment.content == text,
           !currentErrors.isEmpty,
           let element = textMonitor.monitoredElement {
            Logger.debug("AnalysisCoordinator: Restoring cached errors immediately (\(currentErrors.count) errors)", category: Logger.analysis)
            showErrorUnderlines(currentErrors, element: element)
        }

        let segment = TextSegment(
            content: text,
            startIndex: 0,
            endIndex: text.count,
            context: context
        )

        currentSegment = segment

        // Perform analysis
        let isEnabled = UserPreferences.shared.isEnabled
        Logger.debug("AnalysisCoordinator: Grammar checking enabled: \(isEnabled)", category: Logger.analysis)

        if isEnabled {
            Logger.debug("AnalysisCoordinator: Calling analyzeText()", category: Logger.analysis)
            analyzeText(segment)
        } else {
            Logger.debug("AnalysisCoordinator: Analysis disabled in preferences", category: Logger.analysis)
        }
    }

    /// Analyze text with incremental support (T039)
    private func analyzeText(_ segment: TextSegment) {
        let text = segment.content

        // Check if text has changed significantly
        let hasChanged = text != previousText

        guard hasChanged else { return }

        // For now, analyze full text
        // TODO: Implement true incremental diffing for large documents
        let shouldAnalyzeFull = text.count < 1000 || textHasChangedSignificantly(text)

        if shouldAnalyzeFull {
            analyzeFullText(segment)
        } else {
            // Incremental analysis for large docs
            analyzeChangedPortion(segment)
        }

        previousText = text
    }

    /// Analyze full text
    private func analyzeFullText(_ segment: TextSegment) {
        Logger.debug("AnalysisCoordinator: analyzeFullText called", category: Logger.analysis)

        // CRITICAL: Capture the monitored element BEFORE async operation
        let capturedElement = textMonitor.monitoredElement
        let segmentContent = segment.content

        analysisQueue.async { [weak self] in
            guard let self = self else { return }

            Logger.debug("AnalysisCoordinator: Calling Harper grammar engine...", category: Logger.analysis)

            let dialect = UserPreferences.shared.selectedDialect
            let enableInternetAbbrev = UserPreferences.shared.enableInternetAbbreviations
            let enableGenZSlang = UserPreferences.shared.enableGenZSlang
            let enableITTerminology = UserPreferences.shared.enableITTerminology
            let enableLanguageDetection = UserPreferences.shared.enableLanguageDetection
            let excludedLanguages = Array(UserPreferences.shared.excludedLanguages.map { UserPreferences.languageCode(for: $0) })
            let enableSentenceStartCapitalization = UserPreferences.shared.enableSentenceStartCapitalization
            let result = GrammarEngine.shared.analyzeText(
                segmentContent,
                dialect: dialect,
                enableInternetAbbrev: enableInternetAbbrev,
                enableGenZSlang: enableGenZSlang,
                enableITTerminology: enableITTerminology,
                enableLanguageDetection: enableLanguageDetection,
                excludedLanguages: excludedLanguages,
                enableSentenceStartCapitalization: enableSentenceStartCapitalization
            )

            Logger.debug("AnalysisCoordinator: Harper returned \(result.errors.count) error(s)", category: Logger.analysis)

            DispatchQueue.main.async {
                Logger.debug("AnalysisCoordinator: Updating error cache and applying filters...", category: Logger.analysis)

                self.updateErrorCache(for: segment, with: result.errors)
                self.applyFilters(to: result.errors, sourceText: segmentContent, element: capturedElement)

                // Record statistics with full details
                let wordCount = segmentContent.split(separator: " ").count

                // Compute category breakdown
                var categoryBreakdown: [String: Int] = [:]
                for error in result.errors {
                    categoryBreakdown[error.category, default: 0] += 1
                }

                UserStatistics.shared.recordDetailedAnalysisSession(
                    wordsProcessed: wordCount,
                    errorsFound: result.errors.count,
                    bundleIdentifier: self.monitoredContext?.bundleIdentifier,
                    categoryBreakdown: categoryBreakdown,
                    latencyMs: Double(result.analysisTimeMs)
                )

                Logger.debug("AnalysisCoordinator: Analysis complete", category: Logger.analysis)
            }
        }
    }

    /// Analyze only changed portion (T039)
    private func analyzeChangedPortion(_ segment: TextSegment) {
        // CRITICAL: Capture the monitored element BEFORE async operation
        let capturedElement = textMonitor.monitoredElement
        let segmentContent = segment.content

        // Simplified: For large docs, still analyze full text but async
        // Full incremental diff would require text diffing algorithm
        analysisQueue.async { [weak self] in
            guard let self = self else { return }

            let dialect = UserPreferences.shared.selectedDialect
            let enableInternetAbbrev = UserPreferences.shared.enableInternetAbbreviations
            let enableGenZSlang = UserPreferences.shared.enableGenZSlang
            let enableITTerminology = UserPreferences.shared.enableITTerminology
            let enableLanguageDetection = UserPreferences.shared.enableLanguageDetection
            let excludedLanguages = Array(UserPreferences.shared.excludedLanguages.map { UserPreferences.languageCode(for: $0) })
            let enableSentenceStartCapitalization = UserPreferences.shared.enableSentenceStartCapitalization
            let result = GrammarEngine.shared.analyzeText(
                segmentContent,
                dialect: dialect,
                enableInternetAbbrev: enableInternetAbbrev,
                enableGenZSlang: enableGenZSlang,
                enableITTerminology: enableITTerminology,
                enableLanguageDetection: enableLanguageDetection,
                excludedLanguages: excludedLanguages,
                enableSentenceStartCapitalization: enableSentenceStartCapitalization
            )

            DispatchQueue.main.async {
                self.updateErrorCache(for: segment, with: result.errors)
                self.applyFilters(to: result.errors, sourceText: segmentContent, element: capturedElement)

                // Record statistics with full details
                let wordCount = segmentContent.split(separator: " ").count

                // Compute category breakdown
                var categoryBreakdown: [String: Int] = [:]
                for error in result.errors {
                    categoryBreakdown[error.category, default: 0] += 1
                }

                UserStatistics.shared.recordDetailedAnalysisSession(
                    wordsProcessed: wordCount,
                    errorsFound: result.errors.count,
                    bundleIdentifier: self.monitoredContext?.bundleIdentifier,
                    categoryBreakdown: categoryBreakdown,
                    latencyMs: Double(result.analysisTimeMs)
                )
            }
        }
    }

    /// Check if text has changed significantly
    private func textHasChangedSignificantly(_ newText: String) -> Bool {
        let oldCount = previousText.count
        let newCount = newText.count

        // Consider significant if >10% change or >100 chars
        let diff = abs(newCount - oldCount)
        return diff > 100 || diff > oldCount / 10
    }

    // Note: updateErrorCache is now implemented in the Performance Optimizations extension

    /// Deduplicate consecutive identical errors
    /// This prevents flooding the UI with 157 "Horizontal ellipsis" errors
    private func deduplicateErrors(_ errors: [GrammarErrorModel]) -> [GrammarErrorModel] {
        guard !errors.isEmpty else { return errors }

        var deduplicated: [GrammarErrorModel] = []
        var currentGroup: [GrammarErrorModel] = [errors[0]]

        for i in 1..<errors.count {
            let current = errors[i]
            let previous = errors[i-1]

            // Check if this error is identical to the previous one
            if current.message == previous.message &&
               current.category == previous.category &&
               current.lintId == previous.lintId {
                // Same error - add to current group
                currentGroup.append(current)
            } else {
                // Different error - save one representative from the group
                if let representative = currentGroup.first {
                    deduplicated.append(representative)
                }
                // Start new group
                currentGroup = [current]
            }
        }

        // Don't forget the last group
        if let representative = currentGroup.first {
            deduplicated.append(representative)
        }

        return deduplicated
    }

    /// Apply filters based on user preferences (T049, T050, T103)
    private func applyFilters(to errors: [GrammarErrorModel], sourceText: String, element: AXUIElement?) {
        Logger.debug("AnalysisCoordinator: applyFilters called with \(errors.count) errors", category: Logger.analysis)

        var filteredErrors = errors

        // Log error categories
        for error in errors {
            Logger.debug("  Error category: '\(error.category)', message: '\(error.message)'", category: Logger.analysis)
        }

        // Filter by category (e.g., Spelling, Grammar, Style)
        let enabledCategories = UserPreferences.shared.enabledCategories
        Logger.debug("AnalysisCoordinator: Enabled categories: \(enabledCategories)", category: Logger.analysis)

        filteredErrors = filteredErrors.filter { error in
            let contains = enabledCategories.contains(error.category)
            if !contains {
                Logger.debug("  Filtering out error with category: '\(error.category)'", category: Logger.analysis)
            }
            return contains
        }

        Logger.debug("  After category filter: \(filteredErrors.count) errors", category: Logger.analysis)

        // Deduplicate consecutive identical errors (Issue #2)
        // This prevents 157 "Horizontal ellipsis" errors from flooding the UI
        filteredErrors = deduplicateErrors(filteredErrors)

        Logger.debug("  After deduplication: \(filteredErrors.count) errors", category: Logger.analysis)

        // Filter by dismissed rules (T050)
        let dismissedRules = UserPreferences.shared.ignoredRules
        filteredErrors = filteredErrors.filter { error in
            !dismissedRules.contains(error.lintId)
        }

        // Filter by custom vocabulary (T103)
        // Skip errors that contain words from the user's custom dictionary
        let vocabulary = CustomVocabulary.shared
        filteredErrors = filteredErrors.filter { error in
            // Extract error text from source using start/end indices
            guard error.start < sourceText.count, error.end <= sourceText.count, error.start < error.end else {
                return true // Keep error if indices are invalid
            }

            let startIndex = sourceText.index(sourceText.startIndex, offsetBy: error.start)
            let endIndex = sourceText.index(sourceText.startIndex, offsetBy: error.end)
            let errorText = String(sourceText[startIndex..<endIndex])

            return !vocabulary.containsAnyWord(in: errorText)
        }

        // Filter by globally ignored error texts
        // Skip errors that match texts the user has chosen to ignore globally
        let ignoredTexts = UserPreferences.shared.ignoredErrorTexts
        filteredErrors = filteredErrors.filter { error in
            // Extract error text from source using start/end indices
            guard error.start < sourceText.count, error.end <= sourceText.count, error.start < error.end else {
                return true // Keep error if indices are invalid
            }

            let startIndex = sourceText.index(sourceText.startIndex, offsetBy: error.start)
            let endIndex = sourceText.index(sourceText.startIndex, offsetBy: error.end)
            let errorText = String(sourceText[startIndex..<endIndex])

            return !ignoredTexts.contains(errorText)
        }

        currentErrors = filteredErrors

        showErrorUnderlines(filteredErrors, element: element)
    }

    /// Show visual underlines for errors
    private func showErrorUnderlines(_ errors: [GrammarErrorModel], element: AXUIElement?) {
        Logger.debug("AnalysisCoordinator: showErrorUnderlines called with \(errors.count) errors", category: Logger.analysis)

        // Don't show overlays during window movement or when window is off-screen
        // This prevents stale positions from being cached during the debounce period
        if overlaysHiddenDueToMovement {
            Logger.debug("AnalysisCoordinator: Skipping overlay update - window is moving", category: Logger.analysis)
            return
        }
        if overlaysHiddenDueToWindowOffScreen {
            Logger.debug("AnalysisCoordinator: Skipping overlay update - window is off-screen", category: Logger.analysis)
            return
        }

        guard let providedElement = element else {
            Logger.debug("AnalysisCoordinator: No monitored element - hiding overlays", category: Logger.analysis)
            errorOverlay.hide()
            floatingIndicator.hide()
            MenuBarController.shared?.setIconState(.active)
            return
        }

        // CRITICAL: Check if this is still the currently monitored element
        // If user switched apps while async analysis was running, the captured element
        // will be different from the current textMonitor.monitoredElement
        // In that case, we should ignore these results (they're stale)
        if let currentElement = textMonitor.monitoredElement {
            // Compare element pointers to see if they're the same
            if providedElement != currentElement {
                Logger.debug("AnalysisCoordinator: Ignoring stale analysis results - element mismatch (user switched apps)", category: Logger.analysis)
                return
            }
        } else {
            // No current element being monitored - these results are stale
            Logger.debug("AnalysisCoordinator: Ignoring stale analysis results - no element currently monitored", category: Logger.analysis)
            return
        }

        if errors.isEmpty {
            Logger.debug("AnalysisCoordinator: No errors - hiding overlays", category: Logger.analysis)
            errorOverlay.hide()
            floatingIndicator.hide()
            MenuBarController.shared?.setIconState(.active)
        } else {
            // Debug: Log context before passing to errorOverlay
            let bundleID = monitoredContext?.bundleIdentifier ?? "nil"
            let appName = monitoredContext?.applicationName ?? "nil"
            Logger.debug("AnalysisCoordinator: About to call errorOverlay.update() with context - bundleID: '\(bundleID)', appName: '\(appName)'", category: Logger.analysis)

            // Try to show visual underlines
            let underlinesCreated = errorOverlay.update(errors: errors, element: providedElement, context: monitoredContext)

            // Always show floating indicator when there are errors
            // It provides quick access to error count and suggestions
            if underlinesCreated == 0 {
                Logger.debug("AnalysisCoordinator: \(errors.count) errors detected in '\(appName)' but no underlines created - showing floating indicator only", category: Logger.analysis)
            } else {
                Logger.debug("AnalysisCoordinator: Showing \(underlinesCreated) visual underlines + floating indicator", category: Logger.analysis)
            }

            floatingIndicator.update(errors: errors, element: providedElement, context: monitoredContext)
            MenuBarController.shared?.setIconState(.active)
        }
    }

    /// Get errors for current text
    func getCurrentErrors() -> [GrammarErrorModel] {
        currentErrors
    }

    /// Dismiss error for current session (T048)
    func dismissError(_ error: GrammarErrorModel) {
        // Record statistics
        UserStatistics.shared.recordSuggestionDismissed()

        // Extract error text and persist it globally
        if let sourceText = currentSegment?.content {
            guard error.start < sourceText.count, error.end <= sourceText.count, error.start < error.end else {
                // Invalid indices, just remove from current errors
                currentErrors.removeAll { $0.start == error.start && $0.end == error.end }
                return
            }

            let startIndex = sourceText.index(sourceText.startIndex, offsetBy: error.start)
            let endIndex = sourceText.index(sourceText.startIndex, offsetBy: error.end)
            let errorText = String(sourceText[startIndex..<endIndex])

            // Persist this error text globally
            UserPreferences.shared.ignoreErrorText(errorText)
        }

        currentErrors.removeAll { $0.start == error.start && $0.end == error.end }

        // Re-filter to immediately remove any other occurrences
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
    }

    /// Ignore rule permanently (T050)
    func ignoreRulePermanently(_ ruleId: String) {
        UserPreferences.shared.ignoreRule(ruleId)

        // Re-filter current errors
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
    }

    /// Add word to custom dictionary
    func addToDictionary(_ error: GrammarErrorModel) {
        // Extract the error text
        guard let sourceText = currentSegment?.content else { return }

        guard error.start < sourceText.count, error.end <= sourceText.count, error.start < error.end else {
            return
        }

        let startIndex = sourceText.index(sourceText.startIndex, offsetBy: error.start)
        let endIndex = sourceText.index(sourceText.startIndex, offsetBy: error.end)
        let errorText = String(sourceText[startIndex..<endIndex])

        do {
            try CustomVocabulary.shared.addWord(errorText)
            print("✅ Added '\(errorText)' to custom dictionary")

            // Record statistics
            UserStatistics.shared.recordWordAddedToDictionary()
        } catch {
            print("❌ Failed to add '\(errorText)' to dictionary: \(error)")
        }

        // Re-filter current errors to immediately remove this word
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
    }

    /// Clear error cache
    func clearCache() {
        errorCache.removeAll()
        currentErrors.removeAll()
        previousText = ""
    }

    /// Apply text replacement for error (T044)
    private func applyTextReplacement(for error: GrammarErrorModel, with suggestion: String) {
        Logger.debug("applyTextReplacement called - error: '\(error.message)', suggestion: '\(suggestion)'", category: Logger.analysis)

        guard let element = textMonitor.monitoredElement else {
            Logger.debug("No monitored element for text replacement", category: Logger.analysis)
            return
        }

        Logger.debug("Have monitored element, context: \(monitoredContext?.applicationName ?? "nil")", category: Logger.analysis)

        // Use keyboard automation directly for known Electron apps
        // This avoids trying the AX API which is known to fail on Electron
        if let context = monitoredContext, context.requiresKeyboardReplacement {
            Logger.debug("Detected Electron app (\(context.applicationName)) - using keyboard automation directly", category: Logger.analysis)

            applyTextReplacementViaKeyboard(for: error, with: suggestion, element: element)
            return
        }

        // For native macOS apps, try AX API first (it's faster and preserves formatting)
        // Use selection-based replacement to preserve formatting (bold, links, code, etc.)
        // Step 1: Save current selection
        var originalSelection: CFTypeRef?
        let _ = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &originalSelection
        )

        // Step 2: Set selection to error range
        var errorRange = CFRange(location: error.start, length: error.end - error.start)
        let rangeValue = AXValueCreate(.cfRange, &errorRange)!

        let selectError = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if selectError != .success {
            // AX API failed
            // Fallback: Use clipboard + keyboard simulation
            Logger.debug("AX API selection failed (\(selectError.rawValue)), using keyboard fallback", category: Logger.analysis)

            applyTextReplacementViaKeyboard(for: error, with: suggestion, element: element)
            return
        }

        // Step 3: Replace selected text with suggestion
        // Using kAXSelectedTextAttribute preserves formatting of the surrounding text
        let replaceError = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            suggestion as CFTypeRef
        )

        if replaceError == .success {
            // Record statistics
            UserStatistics.shared.recordSuggestionApplied(category: error.category)

            // Invalidate cache (T044a)
            invalidateCacheAfterReplacement(at: error.start..<error.end)

            // Step 4: Restore original selection (optional, move cursor after replacement)
            // Most apps expect cursor to be after the replacement
            var newPosition = CFRange(location: error.start + suggestion.count, length: 0)
            let newRangeValue = AXValueCreate(.cfRange, &newPosition)!
            let _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                newRangeValue
            )
        } else {
            // AX API replacement failed
            Logger.debug("AX API replacement failed (\(replaceError.rawValue)), trying keyboard fallback", category: Logger.analysis)

            // Try keyboard fallback
            applyTextReplacementViaKeyboard(for: error, with: suggestion, element: element)
        }
    }

    /// Apply text replacement for browsers using menu action with keyboard fallback
    /// Browsers often have silently failing AX APIs, so we use SelectedTextKit's approach:
    /// 1. Try to select text range via AX API (even if it silently fails)
    /// 2. Copy suggestion to clipboard
    /// 3. Try paste via menu action (more reliable)
    /// 4. Fallback to Cmd+V if menu fails
    private func applyBrowserTextReplacement(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, context: ApplicationContext) {
        Logger.debug("Browser text replacement for \(context.applicationName)", category: Logger.analysis)

        // Step 1: Try to select the error range using AX API
        // This may silently fail in browsers, but it's fast and works sometimes
        var errorRange = CFRange(location: error.start, length: error.end - error.start)
        let rangeValue = AXValueCreate(.cfRange, &errorRange)!

        let selectResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if selectResult == .success {
            Logger.debug("AX API accepted selection for browser (range: \(error.start)-\(error.end))", category: Logger.analysis)
        } else {
            Logger.debug("AX API selection failed for browser (error: \(selectResult.rawValue)) - will try paste anyway", category: Logger.analysis)
        }

        // Step 2: Save original pasteboard content
        // Note: We save the string content, not the items themselves
        // NSPasteboardItem objects are bound to their original pasteboard
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount

        // Step 3: Copy suggestion to clipboard
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        Logger.debug("Copied suggestion to clipboard: '\(suggestion)'", category: Logger.analysis)

        // Step 4: Activate the browser
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier)
        if let targetApp = apps.first {
            targetApp.activate()
            Logger.debug("Activated \(context.applicationName)", category: Logger.analysis)
        }

        // Step 5: Wait for activation, then try paste via menu action
        let delay = context.keyboardOperationDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Try menu action paste first (more reliable for browsers)
            var pasteSucceeded = false

            // Try to find and click the Paste menu item using AX API
            if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

                // Try to find Edit > Paste menu
                if let pasteMenuItem = self.findPasteMenuItem(in: appElement) {
                    let pressResult = AXUIElementPerformAction(pasteMenuItem, kAXPressAction as CFString)
                    if pressResult == .success {
                        pasteSucceeded = true
                        Logger.debug("Pasted via menu action", category: Logger.analysis)
                    } else {
                        Logger.debug("Menu action press failed: \(pressResult.rawValue)", category: Logger.analysis)
                    }
                } else {
                    Logger.debug("Could not find Paste menu item", category: Logger.analysis)
                }
            }

            // Step 6: Fallback to keyboard shortcut if menu failed
            if !pasteSucceeded {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
                    Logger.debug("Pasted via keyboard shortcut (Cmd+V fallback)", category: Logger.analysis)
                }
            }

            // Step 7: Restore original pasteboard after a delay (SelectedTextKit uses 50ms)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // Only restore if the pasteboard hasn't been changed by something else
                // This prevents us from overwriting user's deliberate clipboard actions
                if pasteboard.changeCount == originalChangeCount + 1 {
                    // Pasteboard only has our change - safe to restore
                    if let originalContent = originalString {
                        pasteboard.clearContents()
                        pasteboard.setString(originalContent, forType: .string)
                        Logger.debug("Restored original pasteboard content: '\(originalContent.prefix(50))...'", category: Logger.analysis)
                    } else {
                        // Original clipboard was empty - just clear it
                        pasteboard.clearContents()
                        Logger.debug("Cleared pasteboard (original was empty)", category: Logger.analysis)
                    }
                } else {
                    // Clipboard was changed by user or another app - don't restore
                    Logger.debug("Skipped pasteboard restore (user modified clipboard)", category: Logger.analysis)
                }

                // Record statistics
                UserStatistics.shared.recordSuggestionApplied(category: error.category)

                // Invalidate cache
                self.invalidateCacheAfterReplacement(at: error.start..<error.end)

                Logger.debug("Browser text replacement complete", category: Logger.analysis)
            }
        }
    }

    /// Find the Paste menu item in the application's menu bar
    /// Returns the AXUIElement for the Paste menu item, or nil if not found
    private func findPasteMenuItem(in appElement: AXUIElement) -> AXUIElement? {
        // Try to get the menu bar
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success else {
            return nil
        }

        let menuBar = menuBarValue as! AXUIElement

        // Try to find "Edit" menu
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success else {
            return nil
        }

        let children = childrenValue as! [AXUIElement]

        for child in children {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String,
               title.lowercased().contains("edit") {

                // Found Edit menu, now look for Paste
                var menuChildrenValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &menuChildrenValue) == .success,
                   let menuChildren = menuChildrenValue as? [AXUIElement] {

                    for menuChild in menuChildren {
                        var itemChildrenValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(menuChild, kAXChildrenAttribute as CFString, &itemChildrenValue) == .success,
                           let items = itemChildrenValue as? [AXUIElement] {

                            for item in items {
                                var itemTitleValue: CFTypeRef?
                                if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &itemTitleValue) == .success,
                                   let itemTitle = itemTitleValue as? String,
                                   itemTitle.lowercased().contains("paste") {
                                    return item
                                }
                            }
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Apply text replacement using keyboard simulation (for Electron apps and Terminals)
    /// Uses hybrid replacement approach: try AX API first, fall back to keyboard
    private func applyTextReplacementViaKeyboard(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement) {
        guard let context = self.monitoredContext else {
            Logger.debug("No context available for keyboard replacement", category: Logger.analysis)
            return
        }

        Logger.debug("Using keyboard simulation for text replacement (app: \(context.applicationName), isTerminal: \(context.isTerminalApp), isBrowser: \(context.isBrowser))", category: Logger.analysis)

        // SPECIAL HANDLING FOR BROWSERS
        // Browsers have contenteditable areas where AX API often silently fails
        // Use simplified approach: select via AX API, then paste via menu action or Cmd+V
        // Inspired by SelectedTextKit's menu action approach
        if context.isBrowser {
            applyBrowserTextReplacement(for: error, with: suggestion, element: element, context: context)
            return
        }

        // SPECIAL HANDLING FOR TERMINALS
        // Terminal.app's AX API is completely broken - both selection AND text setting fail
        // Solution: Clear the entire command line and paste the corrected full text
        if context.isTerminalApp {
            // Try to get original cursor position via AXSelectedTextRange
            var selectedRangeValue: CFTypeRef?
            let rangeResult = AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &selectedRangeValue
            )

            var originalCursorPosition: Int?
            if rangeResult == .success, let rangeValue = selectedRangeValue {
                let range = rangeValue as! AXValue
                var cfRange = CFRange()
                let success = AXValueGetValue(range, .cfRange, &cfRange)
                if success {
                    originalCursorPosition = cfRange.location
                    Logger.debug("Terminal: Original cursor position: \(cfRange.location) (selection length: \(cfRange.length))", category: Logger.analysis)
                } else {
                    Logger.debug("Terminal: Could not extract CFRange from AXSelectedTextRange", category: Logger.analysis)
                }
            } else {
                Logger.debug("Terminal: Could not query AXSelectedTextRange (error: \(rangeResult.rawValue))", category: Logger.analysis)
            }

            var currentTextValue: CFTypeRef?
            let getTextResult = AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &currentTextValue
            )

            guard getTextResult == .success, let fullText = currentTextValue as? String else {
                Logger.debug("Failed to get current text for Terminal replacement", category: Logger.analysis)
                return
            }

            // Apply preprocessing to get just the command line text
            let parser = ContentParserFactory.shared.parser(for: context.bundleIdentifier)
            guard let commandLineText = parser.preprocessText(fullText) else {
                Logger.debug("Failed to preprocess text for Terminal", category: Logger.analysis)
                return
            }

            // Apply the correction to the command line text
            let startIndex = commandLineText.index(commandLineText.startIndex, offsetBy: error.start)
            let endIndex = commandLineText.index(commandLineText.startIndex, offsetBy: error.end)
            var correctedText = commandLineText
            correctedText.replaceSubrange(startIndex..<endIndex, with: suggestion)

            Logger.debug("Terminal: Original command: '\(commandLineText)'", category: Logger.analysis)

            Logger.debug("Terminal: Corrected command: '\(correctedText)'", category: Logger.analysis)

            // Calculate target cursor position for restoration
            var targetCursorPosition: Int?
            if let axCursorPos = originalCursorPosition {
                // Map cursor position from full text to command line coordinates
                // Find where the command line starts in the full text
                let commandRange = (fullText as NSString).range(of: commandLineText)
                if commandRange.location != NSNotFound {
                    let promptOffset = commandRange.location
                    let cursorInCommandLine = axCursorPos - promptOffset

                    Logger.debug("Terminal: Cursor in command line: \(cursorInCommandLine) (AX position: \(axCursorPos), prompt offset: \(promptOffset))", category: Logger.analysis)

                    // Calculate new cursor position after replacement
                    let errorLength = error.end - error.start
                    let replacementLength = suggestion.count
                    let lengthDelta = replacementLength - errorLength

                    if cursorInCommandLine < error.start {
                        // Cursor before error - position unchanged
                        targetCursorPosition = cursorInCommandLine
                        Logger.debug("Cursor before error - keeping at position \(cursorInCommandLine)", category: Logger.analysis)
                    } else if cursorInCommandLine >= error.end {
                        // Cursor after error - shift by length delta
                        targetCursorPosition = cursorInCommandLine + lengthDelta
                        Logger.debug("Cursor after error - moving to position \(cursorInCommandLine + lengthDelta)", category: Logger.analysis)
                    } else {
                        // Cursor inside error - move to end of replacement
                        targetCursorPosition = error.start + replacementLength
                        Logger.debug("Cursor inside error - moving to end of replacement at position \(error.start + replacementLength)", category: Logger.analysis)
                    }
                } else {
                    Logger.debug("Terminal: Could not find command line in full text - cannot map cursor position", category: Logger.analysis)
                }
            }

            // Copy corrected text to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(correctedText, forType: .string)

            Logger.debug("Copied corrected command to clipboard", category: Logger.analysis)

            // Activate Terminal
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier)
            if let targetApp = apps.first {
                targetApp.activate()
                Logger.debug("Activated Terminal for keyboard commands", category: Logger.analysis)
            }

            // Wait for activation, then clear line and paste
            // Terminal replacement strategy (T044-Terminal):
            // 1. Query AXSelectedTextRange to get original cursor position
            // 2. Ctrl+A: Move cursor to beginning of line
            // 3. Ctrl+K: Kill (delete) from cursor to end of line
            // 4. Cmd+V: Paste corrected text from clipboard
            // 5. Ctrl+A: Move back to beginning
            // 6. Send N right arrows to restore cursor position (calculated based on replacement)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Step 1: Ctrl+A to go to beginning of line
                self.pressKey(key: VirtualKeyCode.a, flags: .maskControl)

                Logger.debug("Sent Ctrl+A", category: Logger.analysis)

                // Small delay before Ctrl+K
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    // Step 2: Ctrl+K to kill (delete) to end of line
                    self.pressKey(key: VirtualKeyCode.k, flags: .maskControl)

                    Logger.debug("Sent Ctrl+K", category: Logger.analysis)

                    // Small delay before paste
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        // Step 3: Paste the corrected text
                        self.pressKey(key: VirtualKeyCode.v, flags: .maskCommand)

                        Logger.debug("Sent Cmd+V", category: Logger.analysis)

                        // Step 4: Position cursor at target location
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            if let targetPos = targetCursorPosition {
                                // Navigate to target cursor position
                                // First move to beginning
                                self.pressKey(key: VirtualKeyCode.a, flags: .maskControl)

                                Logger.debug("Sent Ctrl+A to move to beginning before cursor positioning", category: Logger.analysis)

                                // Small delay, then send right arrows to reach target position
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                                    // Send all right arrow keys rapidly (no delays between them to avoid animation)
                                    for _ in 0..<targetPos {
                                        self.pressKey(key: VirtualKeyCode.rightArrow, flags: [], withDelay: false)
                                    }

                                    Logger.debug("Terminal replacement complete (cursor at position \(targetPos))", category: Logger.analysis)

                                    // Record statistics
                                    UserStatistics.shared.recordSuggestionApplied(category: error.category)

                                    // Invalidate cache
                                    self.invalidateCacheAfterReplacement(at: error.start..<error.end)
                                }
                            } else {
                                // Fallback: move to end if we couldn't determine target position
                                self.pressKey(key: VirtualKeyCode.e, flags: .maskControl)

                                Logger.debug("Terminal replacement complete (cursor at end - position unknown)", category: Logger.analysis)

                                // Record statistics
                                UserStatistics.shared.recordSuggestionApplied(category: error.category)

                                // Invalidate cache
                                self.invalidateCacheAfterReplacement(at: error.start..<error.end)
                            }
                        }
                    }
                }
            }

            return
        }

        // For non-terminal apps, use standard keyboard navigation
        // CRITICAL FIX: Activate the target application before sending keyboard events
        // CGEventPost only sends keyboard events to the frontmost application
        // When user clicks the popover, Terminal loses focus, so we must restore it
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier)
        if let targetApp = apps.first {
            Logger.debug("Activating \(context.applicationName) to make it frontmost", category: Logger.analysis)
            targetApp.activate()
        } else {
            Logger.debug("Could not find running app with bundle ID \(context.bundleIdentifier)", category: Logger.analysis)
        }

        let delay = context.keyboardOperationDelay
        let activationDelay: TimeInterval = 0.2
        Logger.debug("Using \(delay)s keyboard delay + \(activationDelay)s activation delay for \(context.applicationName)", category: Logger.analysis)

        // Save suggestion to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        Logger.debug("Copied suggestion to clipboard: \(suggestion)", category: Logger.analysis)

        // Use keyboard navigation to select and replace text
        // Wait for app activation to complete before sending keyboard events
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            // Step 1: Go to beginning of text field (Cmd+Left = Home)
            self.pressKey(key: 123, flags: .maskCommand)

            // Wait for navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Step 2: Navigate to error start position using Right arrow
                let navigationDelay: TimeInterval = 0.001

                // Navigate to error start
                self.sendArrowKeys(count: error.start, keyCode: 124, flags: [], delay: navigationDelay) {
                    // Step 3: Select error text using Shift+Right arrow
                    let errorLength = error.end - error.start
                    self.sendArrowKeys(count: errorLength, keyCode: 124, flags: .maskShift, delay: navigationDelay) {
                        // Step 4: Paste suggestion (Cmd+V)
                        self.pressKey(key: 9, flags: .maskCommand) // Cmd+V

                        Logger.debug("Keyboard-based text replacement complete", category: Logger.analysis)

                        // Record statistics
                        UserStatistics.shared.recordSuggestionApplied(category: error.category)

                        // Invalidate cache
                        self.invalidateCacheAfterReplacement(at: error.start..<error.end)
                    }
                }
            }
        }
    }

    /// Try to replace text using AX API selection (for Terminal)
    /// Returns true if successful, false if needs to fall back to keyboard simulation
    private func tryAXSelectionReplacement(element: AXUIElement, start: Int, end: Int, suggestion: String, error: GrammarErrorModel) -> Bool {
        Logger.debug("Attempting AX API selection-based replacement for range \(start)-\(end)", category: Logger.analysis)

        // Read the original text before modification (verify we can access the element)
        var textValue: CFTypeRef?
        let getTextResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        )

        if getTextResult != .success || textValue as? String == nil {
            Logger.debug("Failed to read original text for verification", category: Logger.analysis)
            return false
        }

        // Step 1: Set the selection range to the error range
        var selectionRange = CFRange(location: start, length: end - start)
        let rangeValue = AXValueCreate(.cfRange, &selectionRange)!

        let setRangeResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if setRangeResult != .success {
            Logger.debug("Failed to set AXSelectedTextRange: error \(setRangeResult.rawValue)", category: Logger.analysis)
            return false
        }

        Logger.debug("AX API accepted selection range \(start)-\(end)", category: Logger.analysis)

        // Step 2: Replace the selected text with the suggestion
        let setTextResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            suggestion as CFTypeRef
        )

        if setTextResult != .success {
            Logger.debug("Failed to set AXSelectedText: error \(setTextResult.rawValue)", category: Logger.analysis)
            return false
        }

        // DON'T try to set the text via AX API - Terminal.app's implementation is broken
        // Selection worked - caller will handle paste after activating Terminal
        Logger.debug("AX API selection successful at \(start)-\(end), returning for paste", category: Logger.analysis)

        return true  // Success - selection is set, caller will paste
    }

    /// Send multiple arrow keys with delay between each
    private func sendArrowKeys(count: Int, keyCode: CGKeyCode, flags: CGEventFlags, delay: TimeInterval, completion: @escaping () -> Void) {
        guard count > 0 else {
            completion()
            return
        }

        var remaining = count
        func sendNext() {
            guard remaining > 0 else {
                completion()
                return
            }

            self.pressKey(key: keyCode, flags: flags)
            remaining -= 1

            if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    sendNext()
                }
            } else {
                completion()
            }
        }

        sendNext()
    }

    /// Simulate a key press event via CGEventPost
    ///
    /// This function sends keyboard events to the frontmost application using the
    /// CoreGraphics event system. Requires Accessibility permission.
    ///
    /// - Parameters:
    ///   - key: Virtual key code (use VirtualKeyCode constants)
    ///   - flags: Modifier flags (e.g., .maskControl, .maskCommand)
    ///
    /// - Important: macOS has a bug where Control modifier doesn't work unless
    ///   SecondaryFn flag is also set. This function applies the workaround automatically.
    ///
    /// - Note: This method should only be called after ensuring the target application
    ///   is frontmost, as CGEventPost sends events to the active application.
    private func pressKey(key: CGKeyCode, flags: CGEventFlags, withDelay: Bool = true) {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            Logger.debug("Failed to create CGEventSource for key press", category: Logger.analysis)
            return
        }

        // Apply macOS Control modifier bug workaround
        // The Control modifier flag doesn't work in CGEventPost unless you also
        // add SecondaryFn flag. This is a documented macOS bug.
        // Reference: https://stackoverflow.com/questions/27484330/simulate-keypress-using-swift
        var adjustedFlags = flags
        if flags.contains(.maskControl) {
            adjustedFlags.insert(.maskSecondaryFn)
        }

        if let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: true) {
            keyDown.flags = adjustedFlags
            keyDown.post(tap: .cghidEventTap)
        }

        if let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: false) {
            keyUp.flags = adjustedFlags
            keyUp.post(tap: .cghidEventTap)
        }

        // Small delay between key events (prevents event ordering issues)
        // Can be disabled for rapid repeated keys (like arrow navigation)
        if withDelay {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// Invalidate cache after text replacement (T044a)
    func invalidateCacheAfterReplacement(at range: Range<Int>) {
        // Clear overlapping errors
        currentErrors.removeAll { error in
            let errorRange = error.start..<error.end
            return errorRange.overlaps(range)
        }

        // Trigger re-analysis
        if let segment = currentSegment {
            analyzeText(segment)
        }
    }
}

// MARK: - Error Handling

extension AnalysisCoordinator {
    /// Handle overlapping errors (T043a)
    func getPriorityError(for range: Range<Int>) -> GrammarErrorModel? {
        let overlappingErrors = currentErrors.filter { error in
            let errorRange = error.start..<error.end
            return errorRange.overlaps(range)
        }

        // Return highest severity error
        return overlappingErrors.max { e1, e2 in
            severityPriority(e1.severity) < severityPriority(e2.severity)
        }
    }

    /// Get severity priority (higher = more important)
    private func severityPriority(_ severity: GrammarErrorSeverity) -> Int {
        switch severity {
        case .error: return 3
        case .warning: return 2
        case .info: return 1
        }
    }
}

// MARK: - Performance Optimizations (User Story 4)

extension AnalysisCoordinator {
    /// Find changed region using text diffing (T079)
    func findChangedRegion(oldText: String, newText: String) -> Range<String.Index>? {
        guard oldText != newText else { return nil }

        let oldChars = Array(oldText)
        let newChars = Array(newText)

        // Find common prefix
        var prefixLength = 0
        let minLength = min(oldChars.count, newChars.count)

        while prefixLength < minLength && oldChars[prefixLength] == newChars[prefixLength] {
            prefixLength += 1
        }

        // Find common suffix
        var suffixLength = 0
        let oldSuffixStart = oldChars.count - 1
        let newSuffixStart = newChars.count - 1

        while suffixLength < minLength - prefixLength &&
              oldChars[oldSuffixStart - suffixLength] == newChars[newSuffixStart - suffixLength] {
            suffixLength += 1
        }

        // Calculate changed region
        let changeStart = newText.index(newText.startIndex, offsetBy: prefixLength)
        let changeEnd = newText.index(newText.endIndex, offsetBy: -suffixLength)

        guard changeStart <= changeEnd else { return nil }

        return changeStart..<changeEnd
    }

    /// Detect sentence boundaries for context-aware analysis (T080)
    func detectSentenceBoundaries(in text: String, around range: Range<String.Index>) -> Range<String.Index> {
        let sentenceTerminators = CharacterSet(charactersIn: ".!?")

        // Find sentence start (search backward for sentence terminator)
        var sentenceStart = range.lowerBound
        var searchIndex = sentenceStart

        while searchIndex > text.startIndex {
            searchIndex = text.index(before: searchIndex)
            let char = text[searchIndex]

            if sentenceTerminators.contains(char.unicodeScalars.first!) {
                // Move past the terminator and any whitespace
                sentenceStart = text.index(after: searchIndex)
                while sentenceStart < text.endIndex && text[sentenceStart].isWhitespace {
                    sentenceStart = text.index(after: sentenceStart)
                }
                break
            }
        }

        // Find sentence end (search forward for sentence terminator)
        var sentenceEnd = range.upperBound
        searchIndex = sentenceEnd

        while searchIndex < text.endIndex {
            let char = text[searchIndex]

            if sentenceTerminators.contains(char.unicodeScalars.first!) {
                // Include the terminator
                sentenceEnd = text.index(after: searchIndex)
                break
            }

            searchIndex = text.index(after: searchIndex)
        }

        return sentenceStart..<sentenceEnd
    }

    /// Merge new analysis results with cached results (T082)
    func mergeResults(new: [GrammarErrorModel], cached: [GrammarErrorModel], changedRange: Range<Int>) -> [GrammarErrorModel] {
        var merged: [GrammarErrorModel] = []

        // Keep cached errors outside changed range
        for error in cached {
            let errorRange = error.start..<error.end
            if !errorRange.overlaps(changedRange) {
                merged.append(error)
            }
        }

        merged.append(contentsOf: new)

        // Sort by position
        return merged.sorted { $0.start < $1.start }
    }

    /// Check if edit is large enough to invalidate cache (T083)
    func isLargeEdit(oldText: String, newText: String) -> Bool {
        let diff = abs(newText.count - oldText.count)

        // Consider large if >1000 chars changed (copy/paste scenario)
        return diff > 1000
    }

    /// Purge expired cache entries (T084)
    func purgeExpiredCache() {
        let now = Date()
        var expiredKeys: [String] = []

        for (key, metadata) in cacheMetadata {
            if now.timeIntervalSince(metadata.lastAccessed) > cacheExpirationTime {
                expiredKeys.append(key)
            }
        }

        for key in expiredKeys {
            errorCache.removeValue(forKey: key)
            cacheMetadata.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            print("📦 AnalysisCoordinator: Purged \(expiredKeys.count) expired cache entries")
        }
    }

    /// Evict least recently used cache entries (T085)
    func evictLRUCacheIfNeeded() {
        guard cacheMetadata.count > maxCachedDocuments else { return }

        // Sort by last accessed time
        let sortedEntries = cacheMetadata.sorted { $0.value.lastAccessed < $1.value.lastAccessed }

        let toRemove = sortedEntries.count - maxCachedDocuments
        for i in 0..<toRemove {
            let key = sortedEntries[i].key
            errorCache.removeValue(forKey: key)
            cacheMetadata.removeValue(forKey: key)
        }

        print("📦 AnalysisCoordinator: Evicted \(toRemove) LRU cache entries")
    }

    /// Update cache with access time tracking
    private func updateErrorCache(for segment: TextSegment, with errors: [GrammarErrorModel]) {
        let cacheKey = segment.id.uuidString
        errorCache[cacheKey] = errors

        cacheMetadata[cacheKey] = CacheMetadata(
            lastAccessed: Date(),
            documentSize: segment.content.count
        )

        // Perform cache maintenance
        purgeExpiredCache()
        evictLRUCacheIfNeeded()
    }
}

// MARK: - Cache Metadata

/// Metadata for cache entries to support LRU eviction and expiration
private struct CacheMetadata {
    let lastAccessed: Date
    let documentSize: Int
}
