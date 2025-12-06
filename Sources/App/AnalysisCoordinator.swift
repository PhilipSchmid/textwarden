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
        Logger.debug("AnalysisCoordinator: Error overlay window created", category: Logger.ui)
        return window
    }()

    /// Floating error indicator for apps without visual underlines
    private let floatingIndicator = FloatingErrorIndicator.shared

    /// Error cache mapping text segments to detected errors
    private var errorCache: [String: [GrammarErrorModel]] = [:]

    /// Cache metadata for LRU eviction (T085)
    private var cacheMetadata: [String: CacheMetadata] = [:]

    /// AI rephrase suggestions cache - maps original sentence text to AI-generated rephrase
    /// This cache persists across app switches and re-analyses to avoid regenerating expensive LLM suggestions
    private var aiRephraseCache: [String: String] = [:]

    /// Maximum entries in AI rephrase cache before LRU eviction
    private let aiRephraseCacheMaxEntries = 50

    /// Previous text for incremental analysis
    private var previousText: String = ""

    /// Currently displayed errors
    @Published private(set) var currentErrors: [GrammarErrorModel] = []

    /// Current text segment being analyzed
    @Published private(set) var currentSegment: TextSegment?

    /// Currently monitored application context
    private var monitoredContext: ApplicationContext?

    /// Current browser URL (only populated when monitoring a browser)
    private var currentBrowserURL: URL?

    /// Analysis queue for background processing
    private let analysisQueue = DispatchQueue(label: "com.textwarden.analysis", qos: .userInitiated)

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Maximum number of cached documents (T085)
    private let maxCachedDocuments = 10

    /// Cache expiration time in seconds (T084)
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes

    /// Window position and size tracking
    private var lastWindowFrame: CGRect?
    private var windowPositionTimer: Timer?
    private var windowMovementDebounceTimer: Timer?
    private var overlaysHiddenDueToMovement = false
    private var overlaysHiddenDueToWindowOffScreen = false
    private var positionSyncRetryCount = 0
    private let maxPositionSyncRetries = 20  // Max 20 retries * 50ms = 1000ms max wait
    private var lastElementPosition: CGPoint?  // Track element position for stability check
    private var lastResizeTime: Date?  // Track when window was last resized (for Electron settling)
    private var contentStabilityCount = 0  // Count consecutive stable position samples (for resize)
    private var lastCharacterBounds: CGRect?  // Track actual character position to detect content reflow

    /// Scroll detection - uses global scroll wheel event observer
    private var overlaysHiddenDueToScroll = false
    private var scrollDebounceTimer: Timer?
    /// Global scroll wheel event monitor
    private var scrollWheelMonitor: Any?

    /// Hover switching timer - delays popover switching when hovering from one error to another
    private var hoverSwitchTimer: Timer?
    /// Pending error waiting for delayed hover switch
    private var pendingHoverError: (error: GrammarErrorModel, position: CGPoint, windowFrame: CGRect?)?

    /// Time when last suggestion was applied programmatically
    /// Used to suppress typing detection briefly after applying a suggestion
    /// (prevents paste-triggered AX notifications from hiding overlays)
    private var lastReplacementTime: Date?

    // MARK: - LLM Style Checking

    /// Currently displayed style suggestions from LLM analysis
    @Published private(set) var currentStyleSuggestions: [StyleSuggestionModel] = []

    /// Style analysis queue for background LLM processing
    private let styleAnalysisQueue = DispatchQueue(label: "com.textwarden.styleanalysis", qos: .userInitiated)

    /// Style cache - maps text hash to style suggestions (LLM results are expensive, cache aggressively)
    private var styleCache: [String: [StyleSuggestionModel]] = [:]

    /// Style cache metadata for LRU eviction
    private var styleCacheMetadata: [String: StyleCacheMetadata] = [:]

    /// Maximum cached style results
    private let maxStyleCacheEntries = 20

    /// Style cache expiration time (longer than grammar since LLM is slower)
    private let styleCacheExpirationTime: TimeInterval = 600 // 10 minutes

    /// Debounce timer for style analysis - prevents queue buildup during rapid typing
    private var styleDebounceTimer: Timer?

    /// Debounce delay for style analysis (seconds) - wait for typing to pause
    private let styleDebounceDelay: TimeInterval = 2.0

    /// Generation ID for style analysis - incremented on each text change
    /// Used to detect and skip stale analysis (when text changed during LLM inference)
    private var styleAnalysisGeneration: UInt64 = 0

    /// Whether LLM style checking should run for the current text
    private var shouldRunStyleChecking: Bool {
        UserPreferences.shared.enableStyleChecking && LLMEngine.shared.isReady
    }

    /// Flag to prevent regular analysis from hiding indicator during manual style check
    private var isManualStyleCheckActive: Bool = false

    /// The full text content when current style suggestions were generated
    /// Used to invalidate suggestions when the underlying text changes
    private var styleAnalysisSourceText: String = ""

    /// Flag to prevent text-change handler from clearing errors during replacement
    /// When true, text changes are expected (we're applying a suggestion) and should not trigger re-analysis
    private var isApplyingReplacement: Bool = false

    /// Last analyzed source text (for popover context display)
    private var lastAnalyzedText: String = ""

    private init() {
        setupMonitoring()
        setupPopoverCallbacks()
        setupOverlayCallbacks()
        setupScrollWheelMonitor()
        setupTypingCallback()
        // Window position monitoring will be started when we begin monitoring an app
    }

    /// Setup callback to hide underlines immediately when typing starts
    /// TypingDetector is notified for ALL apps, so this works for Slack, Notion, and other Electron apps
    private func setupTypingCallback() {
        TypingDetector.shared.onTypingStarted = { [weak self] in
            guard let self = self else { return }

            // Check if we're monitoring an app that requires typing pause
            guard let bundleID = self.textMonitor.currentContext?.bundleIdentifier else { return }
            let appConfig = AppRegistry.shared.configuration(for: bundleID)

            // Only act on keyboard events for apps that delay AX notifications (like Notion)
            // For apps like Slack that send immediate AX notifications, this callback won't fire
            // (filtered out in TypingDetector.handleKeyDown)
            if appConfig.features.delaysAXNotifications {
                // Skip if we just applied a suggestion programmatically
                // (prevents paste-triggered AX notifications from hiding overlays we just showed)
                if let lastReplacement = self.lastReplacementTime,
                   Date().timeIntervalSince(lastReplacement) < 0.5 {
                    Logger.debug("AnalysisCoordinator: Ignoring typing callback - just applied suggestion", category: Logger.ui)
                    return
                }

                Logger.debug("AnalysisCoordinator: Typing detected in \(appConfig.displayName) - hiding overlay and clearing cache", category: Logger.ui)

                // Hide overlay immediately
                self.errorOverlay.hide()

                // CRITICAL: Clear position cache since text is changing
                // This prevents stale positions from being used when underlines reappear
                PositionResolver.shared.clearCache()
            }
        }

        // Setup callback for when typing stops
        // This is critical for apps like Notion that don't send timely AX notifications
        TypingDetector.shared.onTypingStopped = { [weak self] in
            guard let self = self else { return }
            guard let element = self.textMonitor.monitoredElement else { return }

            Logger.debug("AnalysisCoordinator: Typing stopped - clearing errors and extracting text", category: Logger.ui)

            // Clear errors and previous text to force complete re-analysis
            // This ensures fresh positions are calculated after text reflow
            self.currentErrors = []
            self.previousText = ""

            // Proactively extract text since Notion may not send AX notifications
            self.textMonitor.extractText(from: element)
        }
    }

    deinit {
        if let monitor = scrollWheelMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Setup global scroll wheel event monitor for detecting scroll events
    private func setupScrollWheelMonitor() {
        scrollWheelMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return }

            // Only process if we're actively monitoring and have errors displayed
            guard self.textMonitor.monitoredElement != nil, !self.currentErrors.isEmpty else { return }

            // Verify scroll is from the monitored app's window
            guard event.windowNumber > 0,
                  let monitoredBundleID = self.textMonitor.currentContext?.bundleIdentifier,
                  let frontApp = NSWorkspace.shared.frontmostApplication,
                  frontApp.bundleIdentifier == monitoredBundleID else { return }

            // Filter out trackpad touches with no actual movement
            let deltaY = event.scrollingDeltaY
            let deltaX = event.scrollingDeltaX
            guard abs(deltaY) > 1 || abs(deltaX) > 1 else { return }

            DispatchQueue.main.async {
                self.handleScrollStarted()
            }
        }
        Logger.debug("Scroll wheel monitor installed", category: Logger.analysis)
    }

    /// Setup popover callbacks
    private func setupPopoverCallbacks() {
        // Handle apply suggestion (T044, T044a)
        suggestionPopover.onApplySuggestion = { [weak self] error, suggestion, completion in
            guard let self = self else {
                completion()
                return
            }
            self.applyTextReplacement(for: error, with: suggestion, completion: completion)
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

        // Handle accept style suggestion - apply text replacement
        suggestionPopover.onAcceptStyleSuggestion = { [weak self] suggestion in
            guard let self = self else { return }
            self.applyStyleTextReplacement(for: suggestion)
        }

        // Handle reject style suggestion - remove from tracking (indicator update handled in removeSuggestionFromTracking)
        suggestionPopover.onRejectStyleSuggestion = { [weak self] suggestion, category in
            guard let self = self else { return }
            Logger.debug("AnalysisCoordinator: Style suggestion rejected with reason: \(category.rawValue)", category: Logger.analysis)
            self.removeSuggestionFromTracking(suggestion)
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
                // CRITICAL: Clear all cached errors when switching apps to prevent
                // showing stale errors from the previous application
                self.currentErrors = []
                self.currentSegment = nil
                self.previousText = ""
                // Don't clear style suggestions if manual style check is in progress
                // The user triggered it and wants to see results when they return
                if !self.isManualStyleCheckActive {
                    self.currentStyleSuggestions = []
                }
            }

            self.errorOverlay.hide()
            self.suggestionPopover.hide()
            // Don't hide floating indicator if manual style check is in progress
            // Keep showing results (or spinner) so user sees them when they return
            if !self.isManualStyleCheckActive {
                self.floatingIndicator.hide()
            }

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
                    } else {
                        // Element was cleared by stopMonitoring - restart monitoring to find text field
                        Logger.debug("AnalysisCoordinator: Same app but element nil (was stopped) - restarting monitoring", category: Logger.analysis)
                        self.startMonitoring(context: context)
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

        // Monitor IMMEDIATE text changes (before debounce) - hide overlays right away
        textMonitor.onImmediateTextChange = { [weak self] text, context in
            guard let self = self else { return }

            // For apps that require typing pause: hide overlay immediately when any text change is detected
            let appConfig = AppRegistry.shared.configuration(for: context.bundleIdentifier)
            if appConfig.features.requiresTypingPause {
                Logger.debug("AnalysisCoordinator: Immediate text change in \(context.applicationName) - hiding overlay", category: Logger.ui)
                self.errorOverlay.hide()
                // Also clear position cache since positions will be stale
                PositionResolver.shared.clearCache()
            }
        }

        // Monitor permission changes
        permissionManager.$isPermissionGranted
            .sink { [weak self] isGranted in
                Logger.info("AnalysisCoordinator: Permission status changed to \(isGranted)", category: Logger.permissions)
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

        // Update TypingDetector with current bundle ID for keyboard event filtering
        TypingDetector.shared.currentBundleID = context.bundleIdentifier

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

        // Clear typing detector state
        TypingDetector.shared.currentBundleID = nil
        TypingDetector.shared.reset()

        // Only clear style state if not in a manual style check
        // During manual style check, preserve results so user sees them when returning
        if !isManualStyleCheckActive {
            currentStyleSuggestions = []  // Clear style suggestions
            styleDebounceTimer?.invalidate()  // Cancel pending style analysis
            styleDebounceTimer = nil
            styleAnalysisGeneration &+= 1  // Invalidate any in-flight analysis
            floatingIndicator.hide()
        }

        errorOverlay.hide()
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
        scrollDebounceTimer?.invalidate()
        scrollDebounceTimer = nil
        lastWindowFrame = nil
        lastResizeTime = nil
        contentStabilityCount = 0
        lastCharacterBounds = nil
        overlaysHiddenDueToMovement = false
        overlaysHiddenDueToWindowOffScreen = false
        overlaysHiddenDueToScroll = false
    }

    /// Check if window has moved, resized, or content has scrolled
    private func checkWindowPosition() {
        guard let element = textMonitor.monitoredElement else {
            lastWindowFrame = nil
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

    /// Handle scroll started - hide underlines only (keep indicator visible)
    private func handleScrollStarted() {
        // Cancel any pending restore first
        scrollDebounceTimer?.invalidate()
        scrollDebounceTimer = nil

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
            self?.restoreUnderlinesAfterScroll()
        }
    }

    /// Restore underlines after scroll has stopped
    private func restoreUnderlinesAfterScroll() {
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
    private func getWindowFrame(for element: AXUIElement) -> CGRect? {
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
    private func getWindowPosition(for element: AXUIElement) -> CGPoint? {
        return getWindowFrame(for: element)?.origin
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.overlaysHiddenDueToMovement else { return }
                self.finalizeOverlayReshow()
            }
            return
        }

        // For non-resize or non-Electron, just apply minimum settle time
        if let resizeTime = lastResizeTime {
            let timeSinceResize = Date().timeIntervalSince(resizeTime)
            let requiredSettleTime: TimeInterval = 0.15

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
    private func getFirstCharacterBounds(for element: AXUIElement) -> CGRect? {
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
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var bounds = CGRect.zero
        if AXValueGetValue(value as! AXValue, .cgRect, &bounds) {
            return bounds
        }
        return nil
    }

    /// Actually show the overlays after all stability checks pass
    private func completeOverlayReshow() {
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

                // Convert from CGWindow (Quartz) to Cocoa coordinates
                // Quartz origin is at TOP-LEFT of PRIMARY display (with menu bar)
                // Cocoa origin is at BOTTOM-LEFT of PRIMARY display
                // The primary display is the one with Cocoa frame origin at (0, 0)
                let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
                let screenHeight = primaryScreen?.frame.height ?? NSScreen.main?.frame.height ?? 0
                let cocoaY = screenHeight - y - height
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
            // Don't hide indicator during manual style check (showing checkmark/results)
            if !isManualStyleCheckActive {
                floatingIndicator.hide()
            }
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

        // CRITICAL: If text has changed, handle cache invalidation appropriately
        // BUT: Skip this if we're actively applying a replacement - we handle that separately
        if text != previousText && !isApplyingReplacement {
            Logger.debug("AnalysisCoordinator: Text changed - hiding overlay immediately for re-analysis", category: Logger.analysis)
            errorOverlay.hide()

            // For Electron apps: Clear ALL caches when text changes
            // Electron apps have fragile positioning - byte offsets become invalid when text shifts
            let appConfig = AppRegistry.shared.configuration(for: context.bundleIdentifier)
            if appConfig.category == .electron || appConfig.category == .browser {
                Logger.debug("AnalysisCoordinator: Electron app - clearing position cache and errors", category: Logger.analysis)
                PositionResolver.shared.clearCache()
                currentErrors.removeAll()
            }
        } else if text != previousText && isApplyingReplacement {
            Logger.debug("AnalysisCoordinator: Text changed during replacement - skipping cache clear (positions already adjusted)", category: Logger.analysis)
        }

        // Clear style suggestions if the full text has changed from when they were generated
        // This handles the case where user selects text, runs style check, then edits elsewhere
        // The suggestions are only valid for the exact text state they were analyzed against
        if !currentStyleSuggestions.isEmpty && text != styleAnalysisSourceText && !isApplyingReplacement {
            Logger.debug("AnalysisCoordinator: Clearing style suggestions - source text changed", category: Logger.analysis)
            currentStyleSuggestions.removeAll()
            styleAnalysisSourceText = ""
            floatingIndicator.hide()
        }

        // If we have cached errors for this exact text, show them immediately
        // This provides instant feedback when returning from browser UI elements (like Cmd+F)
        // A fresh analysis will still run to catch any changes
        // NOTE: For Electron apps, currentErrors was cleared above, so this won't trigger
        if let cachedSegment = currentSegment,
           cachedSegment.content == text,
           !currentErrors.isEmpty,
           let element = textMonitor.monitoredElement {
            Logger.debug("AnalysisCoordinator: Restoring cached errors immediately (\(currentErrors.count) errors)", category: Logger.analysis)
            showErrorUnderlines(currentErrors, element: element)
        }

        // Restore cached style suggestions if available for this text
        // This provides instant feedback when returning to the app after switching away
        // Only restore if the full text matches what was analyzed (styleAnalysisSourceText)
        if currentStyleSuggestions.isEmpty && (styleAnalysisSourceText.isEmpty || text == styleAnalysisSourceText) {
            let styleCacheKey = computeStyleCacheKey(text: text)
            if let cachedStyleSuggestions = styleCache[styleCacheKey], !cachedStyleSuggestions.isEmpty {
                Logger.debug("AnalysisCoordinator: Restoring cached style suggestions (\(cachedStyleSuggestions.count) suggestions)", category: Logger.analysis)
                currentStyleSuggestions = cachedStyleSuggestions
                styleAnalysisSourceText = text

                // Update cache access time
                let styleName = UserPreferences.shared.selectedWritingStyle
                styleCacheMetadata[styleCacheKey] = StyleCacheMetadata(
                    lastAccessed: Date(),
                    style: styleName
                )

                // Update the floating indicator to show the restored style suggestions
                if let element = textMonitor.monitoredElement {
                    floatingIndicator.update(
                        errors: currentErrors,
                        styleSuggestions: currentStyleSuggestions,
                        element: element,
                        context: monitoredContext,
                        sourceText: text
                    )
                }
            }
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
            // Check if we're in a browser and the current website is disabled
            if context.isBrowser {
                // Extract current URL from browser
                currentBrowserURL = BrowserURLExtractor.shared.extractURL(
                    processID: context.processID,
                    bundleIdentifier: context.bundleIdentifier
                )

                if let url = currentBrowserURL {
                    Logger.debug("AnalysisCoordinator: Browser URL detected: \(url)", category: Logger.analysis)

                    // Check if this website is disabled
                    if !UserPreferences.shared.isEnabled(forURL: url) {
                        Logger.debug("AnalysisCoordinator: Website \(url.host ?? "unknown") is disabled - skipping analysis", category: Logger.analysis)
                        // Hide any existing overlays for disabled websites
                        errorOverlay.hide()
                        // Don't hide indicator during manual style check (showing checkmark/results)
                        if !isManualStyleCheckActive {
                            floatingIndicator.hide()
                        }
                        currentErrors = []
                        return
                    }
                } else {
                    Logger.debug("AnalysisCoordinator: Could not extract URL from browser", category: Logger.analysis)
                }
            } else {
                currentBrowserURL = nil
            }

            Logger.debug("AnalysisCoordinator: Calling analyzeText()", category: Logger.analysis)
            analyzeText(segment)
        } else {
            Logger.debug("AnalysisCoordinator: Analysis disabled in preferences", category: Logger.analysis)
        }
    }

    /// Analyze text with incremental support (T039)
    private func analyzeText(_ segment: TextSegment) {
        // Skip analysis if we're actively applying a replacement
        // The text will be re-analyzed after the replacement completes
        if isApplyingReplacement {
            Logger.debug("AnalysisCoordinator: Skipping analysis during replacement", category: Logger.analysis)
            return
        }

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

    /// Analyze full text with DECOUPLED grammar and style checking
    /// Grammar results are shown immediately; style results are added asynchronously
    private func analyzeFullText(_ segment: TextSegment) {
        Logger.debug("AnalysisCoordinator: analyzeFullText called", category: Logger.analysis)

        // CRITICAL: Capture the monitored element BEFORE async operation
        let capturedElement = textMonitor.monitoredElement
        let segmentContent = segment.content

        // Store for popover context display
        lastAnalyzedText = segmentContent

        // Detailed logging for style checking eligibility
        // Auto style checking requires both enableStyleChecking AND autoStyleChecking
        // Manual style checks (via shortcut) only require enableStyleChecking
        let styleCheckingEnabled = UserPreferences.shared.enableStyleChecking
        let autoStyleChecking = UserPreferences.shared.autoStyleChecking
        let llmInitialized = LLMEngine.shared.isInitialized
        let modelLoaded = LLMEngine.shared.isModelLoaded()
        let loadedModelId = LLMEngine.shared.getLoadedModelId()
        let runStyleChecking = styleCheckingEnabled && autoStyleChecking && llmInitialized && modelLoaded

        Logger.info("AnalysisCoordinator: Style check eligibility - enabled=\(styleCheckingEnabled), auto=\(autoStyleChecking), llmInit=\(llmInitialized), modelLoaded=\(modelLoaded), modelId='\(loadedModelId)', willRun=\(runStyleChecking)", category: Logger.llm)

        // ========== GRAMMAR ANALYSIS (immediate) ==========
        // Grammar analysis runs independently and updates UI as soon as it completes
        // This ensures fast feedback (~10ms) without waiting for slow LLM analysis
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

            let grammarResult = GrammarEngine.shared.analyzeText(
                segmentContent,
                dialect: dialect,
                enableInternetAbbrev: enableInternetAbbrev,
                enableGenZSlang: enableGenZSlang,
                enableITTerminology: enableITTerminology,
                enableLanguageDetection: enableLanguageDetection,
                excludedLanguages: excludedLanguages,
                enableSentenceStartCapitalization: enableSentenceStartCapitalization
            )

            Logger.debug("AnalysisCoordinator: Harper returned \(grammarResult.errors.count) error(s)", category: Logger.analysis)

            // Update UI immediately with grammar results - don't wait for style analysis
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Pre-populate errors with cached AI suggestions before displaying
                // This ensures cached suggestions show immediately without "Generating" state
                let errorsWithCachedAI = self.enhanceErrorsWithCachedAI(
                    grammarResult.errors,
                    sourceText: segmentContent
                )

                self.updateErrorCache(for: segment, with: errorsWithCachedAI)
                self.applyFilters(to: errorsWithCachedAI, sourceText: segmentContent, element: capturedElement)

                // Record grammar statistics
                let wordCount = segmentContent.split(separator: " ").count
                var categoryBreakdown: [String: Int] = [:]
                for error in grammarResult.errors {
                    categoryBreakdown[error.category, default: 0] += 1
                }

                UserStatistics.shared.recordDetailedAnalysisSession(
                    wordsProcessed: wordCount,
                    errorsFound: grammarResult.errors.count,
                    bundleIdentifier: self.monitoredContext?.bundleIdentifier,
                    categoryBreakdown: categoryBreakdown,
                    latencyMs: Double(grammarResult.analysisTimeMs)
                )

                Logger.debug("AnalysisCoordinator: Grammar analysis complete, UI updated", category: Logger.analysis)

                // Asynchronously enhance readability errors with AI suggestions
                // This runs in the background and updates UI when ready
                // Pass errorsWithCachedAI so it skips already-enhanced errors
                self.enhanceReadabilityErrorsWithAI(
                    errors: errorsWithCachedAI,
                    sourceText: segmentContent,
                    element: capturedElement,
                    segment: segment
                )
            }
        }

        // ========== STYLE ANALYSIS (debounced, async, independent) ==========
        // Style analysis runs completely independently on a separate queue
        // DEBOUNCED: Wait for typing to pause before starting expensive LLM analysis
        // This prevents queue buildup during rapid typing (each call takes ~35 seconds)
        if runStyleChecking {
            // Check if text contains at least one sentence with minimum word count
            // Split into sentences and check if any has enough words
            let minWords = UserPreferences.shared.styleMinSentenceWords
            let hasQualifyingSentence = containsSentenceWithMinWords(segmentContent, minWords: minWords)

            guard hasQualifyingSentence else {
                Logger.debug("AnalysisCoordinator: No sentence with \(minWords)+ words - skipping style analysis", category: Logger.llm)
                // Don't clear existing suggestions - they remain valid until explicitly removed via accept/reject
                // This prevents the indicator from briefly disappearing when accepting a suggestion
                // (text change triggers re-analysis, but we shouldn't lose remaining suggestions)
                return
            }

            // Increment generation ID on every text change
            // This allows us to detect and skip stale analysis
            styleAnalysisGeneration &+= 1
            let currentGeneration = styleAnalysisGeneration

            // Cancel any pending debounce timer
            styleDebounceTimer?.invalidate()

            // Check cache first (instant, no debounce needed)
            let cacheKey = computeStyleCacheKey(text: segmentContent)
            if let cached = styleCache[cacheKey] {
                Logger.debug("AnalysisCoordinator: Using cached style results (\(cached.count) suggestions)", category: Logger.analysis)
                DispatchQueue.main.async { [weak self] in
                    self?.currentStyleSuggestions = cached
                    self?.styleAnalysisSourceText = segmentContent
                }
                return
            }

            // Start debounce timer - only trigger LLM after typing pauses
            Logger.debug("AnalysisCoordinator: Style analysis debounced - waiting \(styleDebounceDelay)s for typing to pause", category: Logger.llm)

            styleDebounceTimer = Timer.scheduledTimer(withTimeInterval: styleDebounceDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }

                // Check if text has changed since timer was set (generation mismatch)
                guard currentGeneration == self.styleAnalysisGeneration else {
                    Logger.debug("AnalysisCoordinator: Style debounce timer fired but generation mismatch (\(currentGeneration) != \(self.styleAnalysisGeneration)) - skipping", category: Logger.llm)
                    return
                }

                Logger.info("AnalysisCoordinator: Style debounce complete - queuing LLM analysis (gen=\(currentGeneration))", category: Logger.llm)

                self.styleAnalysisQueue.async { [weak self] in
                    guard let self = self else { return }

                    // Check generation AGAIN before starting expensive LLM call
                    // Another text change might have happened while waiting in queue
                    guard currentGeneration == self.styleAnalysisGeneration else {
                        Logger.debug("AnalysisCoordinator: Skipping stale LLM call (gen=\(currentGeneration), current=\(self.styleAnalysisGeneration))", category: Logger.llm)
                        return
                    }

                    Logger.info("AnalysisCoordinator: Starting LLM style analysis (gen=\(currentGeneration))...", category: Logger.llm)

                    let styleName = UserPreferences.shared.selectedWritingStyle
                    let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default

                    let styleResult = LLMEngine.shared.analyzeStyle(segmentContent, style: style)

                    Logger.debug("AnalysisCoordinator: LLM returned \(styleResult.suggestions.count) suggestion(s)", category: Logger.analysis)

                    // Update UI with style results (independently of grammar)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }

                        // Final staleness check before updating UI
                        // If user typed more while LLM was processing, discard results
                        guard currentGeneration == self.styleAnalysisGeneration else {
                            Logger.debug("AnalysisCoordinator: Discarding stale LLM results (gen=\(currentGeneration), current=\(self.styleAnalysisGeneration))", category: Logger.llm)
                            return
                        }

                        if !styleResult.isError {
                            let threshold = Float(UserPreferences.shared.styleConfidenceThreshold)
                            let filteredSuggestions = styleResult.suggestions.filter { $0.confidence >= threshold }
                            self.currentStyleSuggestions = filteredSuggestions
                            self.styleAnalysisSourceText = segmentContent

                            // Cache the results
                            self.styleCache[cacheKey] = filteredSuggestions
                            self.styleCacheMetadata[cacheKey] = StyleCacheMetadata(
                                lastAccessed: Date(),
                                style: styleName
                            )
                            self.evictStyleCacheIfNeeded()

                            Logger.info("AnalysisCoordinator: \(filteredSuggestions.count) style suggestion(s) above threshold (gen=\(currentGeneration))", category: Logger.llm)

                            // Update floating indicator to show style suggestions
                            if !filteredSuggestions.isEmpty, let element = self.textMonitor.monitoredElement {
                                self.floatingIndicator.update(
                                    errors: self.currentErrors,
                                    styleSuggestions: filteredSuggestions,
                                    element: element,
                                    context: self.monitoredContext,
                                    sourceText: self.lastAnalyzedText
                                )
                            }
                        } else {
                            self.currentStyleSuggestions = []
                            Logger.warning("AnalysisCoordinator: Style analysis returned error: \(styleResult.error ?? "unknown")", category: Logger.analysis)
                        }
                    }
                }
            }
        } else {
            // Auto style checking disabled - just cancel any pending timer
            // DON'T clear existing suggestions - they might be from a manual style check
            // and should persist until the user switches apps or edits text
            styleDebounceTimer?.invalidate()
            styleDebounceTimer = nil
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

    /// Check if text contains at least one sentence with the minimum word count
    /// Used to gate style analysis - no point running expensive LLM on short snippets
    private func containsSentenceWithMinWords(_ text: String, minWords: Int) -> Bool {
        // Split text into sentences using common sentence terminators
        // This handles: "Hello. World!" → ["Hello", " World"]
        let sentenceTerminators = CharacterSet(charactersIn: ".!?")
        let sentences = text.components(separatedBy: sentenceTerminators)

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Count words in this sentence
            let wordCount = trimmed.split(separator: " ").filter { !$0.isEmpty }.count
            if wordCount >= minWords {
                return true
            }
        }

        return false
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

        // Filter out Notion-specific false positives
        // French spaces errors in Notion are often triggered by placeholder text artifacts
        // (e.g., "Write, press 'space' for AI" placeholder creates invisible whitespace patterns)
        if let context = monitoredContext,
           AppRegistry.shared.configuration(for: context.bundleIdentifier).parserType == .notion {
            filteredErrors = filteredErrors.filter { error in
                // Filter French spaces errors where the error text is just whitespace
                // These are false positives from Notion's placeholder handling
                if error.message.lowercased().contains("french spaces") {
                    guard error.start < sourceText.count, error.end <= sourceText.count, error.start < error.end else {
                        return true
                    }
                    let startIdx = sourceText.index(sourceText.startIndex, offsetBy: error.start)
                    let endIdx = sourceText.index(sourceText.startIndex, offsetBy: error.end)
                    let errorText = String(sourceText[startIdx..<endIdx])
                    // Filter if error text is just whitespace
                    if errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Logger.debug("Filtering Notion French spaces false positive", category: Logger.analysis)
                        return false
                    }
                }
                return true
            }
        }

        currentErrors = filteredErrors

        showErrorUnderlines(filteredErrors, element: element)
    }

    /// Timer for Electron layout stabilization delay
    private var electronLayoutTimer: Timer?

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

        // For Electron apps: Add a small delay to let the DOM stabilize
        // Electron apps (Notion, Slack) may have stale AX positions briefly after text changes
        let bundleID = monitoredContext?.bundleIdentifier ?? ""
        let appConfig = AppRegistry.shared.configuration(for: bundleID)
        if appConfig.category == .electron {
            // Cancel any pending layout timer
            electronLayoutTimer?.invalidate()

            // Delay showing underlines to let Electron's DOM stabilize
            electronLayoutTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                self?.showErrorUnderlinesInternal(errors, element: element)
            }
            return
        }

        showErrorUnderlinesInternal(errors, element: element)
    }

    /// Internal method to actually show underlines (after any stabilization delay)
    private func showErrorUnderlinesInternal(_ errors: [GrammarErrorModel], element: AXUIElement?) {

        guard let providedElement = element else {
            Logger.debug("AnalysisCoordinator: No monitored element - hiding overlays", category: Logger.analysis)
            errorOverlay.hide()
            // Don't hide indicator during manual style check (showing checkmark/results)
            if !isManualStyleCheckActive {
                floatingIndicator.hide()
            }
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

        // Check if we have anything to show (errors OR style suggestions)
        let hasErrors = !errors.isEmpty
        let hasStyleSuggestions = !currentStyleSuggestions.isEmpty

        if !hasErrors && !hasStyleSuggestions {
            Logger.debug("AnalysisCoordinator: No errors or style suggestions - hiding overlays", category: Logger.analysis)
            errorOverlay.hide()
            // Don't hide indicator during manual style check (showing checkmark/results)
            if !isManualStyleCheckActive {
                floatingIndicator.hide()
            }
            MenuBarController.shared?.setIconState(.active)
        } else {
            // Debug: Log context before passing to errorOverlay
            let bundleID = monitoredContext?.bundleIdentifier ?? "nil"
            let appName = monitoredContext?.applicationName ?? "nil"

            if hasErrors {
                Logger.debug("AnalysisCoordinator: About to call errorOverlay.update() with context - bundleID: '\(bundleID)', appName: '\(appName)'", category: Logger.analysis)

                // Try to show visual underlines for grammar errors
                // Pass the analyzed text so overlay can detect if text has changed
                let sourceText = currentSegment?.content
                let underlinesCreated = errorOverlay.update(errors: errors, element: providedElement, context: monitoredContext, sourceText: sourceText)

                if underlinesCreated == 0 {
                    Logger.debug("AnalysisCoordinator: \(errors.count) errors detected in '\(appName)' but no underlines created - showing floating indicator only", category: Logger.analysis)
                } else {
                    Logger.debug("AnalysisCoordinator: Showing \(underlinesCreated) visual underlines + floating indicator", category: Logger.analysis)
                }
            } else {
                // No grammar errors but have style suggestions - hide error overlay
                errorOverlay.hide()
            }

            // Show floating indicator with errors and/or style suggestions
            // Don't update indicator during manual style check (preserves checkmark display)
            if !isManualStyleCheckActive {
                Logger.debug("AnalysisCoordinator: Updating floating indicator - errors=\(errors.count), styleSuggestions=\(currentStyleSuggestions.count)", category: Logger.analysis)
                floatingIndicator.update(
                    errors: errors,
                    styleSuggestions: currentStyleSuggestions,
                    element: providedElement,
                    context: monitoredContext,
                    sourceText: lastAnalyzedText
                )
            } else {
                Logger.debug("AnalysisCoordinator: Skipping indicator update - manual style check in progress", category: Logger.analysis)
            }
            MenuBarController.shared?.setIconState(.active)
        }
    }

    /// Get errors for current text
    func getCurrentErrors() -> [GrammarErrorModel] {
        currentErrors
    }

    /// Get the current browser URL (nil if not in a browser or URL couldn't be extracted)
    func getCurrentBrowserURL() -> URL? {
        currentBrowserURL
    }

    /// Get the current browser domain (e.g., "github.com")
    func getCurrentBrowserDomain() -> String? {
        currentBrowserURL?.host?.lowercased()
    }

    /// Check if currently monitoring a browser
    func isMonitoringBrowser() -> Bool {
        monitoredContext?.isBrowser ?? false
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
            Logger.info("Added '\(errorText)' to custom dictionary", category: Logger.analysis)

            // Record statistics
            UserStatistics.shared.recordWordAddedToDictionary()
        } catch {
            Logger.error("Failed to add '\(errorText)' to dictionary: \(error)", category: Logger.analysis)
        }

        // Re-filter current errors to immediately remove this word
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
    }

    /// Clear error cache
    func clearCache() {
        errorCache.removeAll()
        currentErrors.removeAll()
        previousText = ""
        // Also clear style cache
        styleCache.removeAll()
        styleCacheMetadata.removeAll()
        currentStyleSuggestions.removeAll()
    }

    /// Remove error from tracking and update UI immediately
    /// Called after successfully applying a suggestion to remove underlines
    /// Also adjusts positions of remaining errors to account for text length change
    /// - Parameters:
    ///   - error: The error that was fixed
    ///   - suggestion: The replacement text that was applied
    ///   - lengthDelta: The change in text length (suggestion.count - errorLength)
    private func removeErrorAndUpdateUI(_ error: GrammarErrorModel, suggestion: String, lengthDelta: Int = 0) {
        Logger.debug("removeErrorAndUpdateUI: Removing error at \(error.start)-\(error.end), suggestion: '\(suggestion)', lengthDelta: \(lengthDelta)", category: Logger.analysis)

        // Remove the error from currentErrors
        currentErrors.removeAll { $0.start == error.start && $0.end == error.end }

        // Update currentSegment with the new text content
        // This is CRITICAL: the underline positions are calculated from currentSegment.content
        // If we don't update it, subsequent errors will have incorrect underline positions
        if let segment = currentSegment {
            var newContent = segment.content
            let startIdx = newContent.index(newContent.startIndex, offsetBy: min(error.start, newContent.count))
            let endIdx = newContent.index(newContent.startIndex, offsetBy: min(error.end, newContent.count))
            if startIdx <= endIdx && endIdx <= newContent.endIndex {
                newContent.replaceSubrange(startIdx..<endIdx, with: suggestion)
                currentSegment = segment.with(content: newContent)
                Logger.debug("removeErrorAndUpdateUI: Updated currentSegment content (new length: \(newContent.count))", category: Logger.analysis)
            }
        }

        // Adjust positions of remaining errors that come after the fixed error
        if lengthDelta != 0 {
            currentErrors = currentErrors.map { err in
                if err.start >= error.end {
                    return GrammarErrorModel(
                        start: err.start + lengthDelta,
                        end: err.end + lengthDelta,
                        message: err.message,
                        severity: err.severity,
                        category: err.category,
                        lintId: err.lintId,
                        suggestions: err.suggestions
                    )
                }
                return err
            }
        }

        // Don't hide the popover here - let it manage its own visibility
        // The popover automatically advances to the next error or hides itself

        // Update the overlay and indicator immediately
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)

        Logger.debug("removeErrorAndUpdateUI: UI updated, remaining errors: \(currentErrors.count)", category: Logger.analysis)
    }

    /// Apply text replacement for error (T044)
    /// Completion is called when the replacement is done (synchronously for AX API, async for keyboard)
    private func applyTextReplacement(for error: GrammarErrorModel, with suggestion: String, completion: @escaping () -> Void) {
        Logger.debug("applyTextReplacement called - error: '\(error.message)', suggestion: '\(suggestion)'", category: Logger.analysis)

        guard let element = textMonitor.monitoredElement else {
            Logger.debug("No monitored element for text replacement", category: Logger.analysis)
            completion()
            return
        }

        Logger.debug("Have monitored element, context: \(monitoredContext?.applicationName ?? "nil")", category: Logger.analysis)

        // Set flag to prevent text-change handler from clearing errors during replacement
        isApplyingReplacement = true

        // Wrap the completion to reset the flag
        let wrappedCompletion: () -> Void = { [weak self] in
            self?.isApplyingReplacement = false
            completion()
        }

        // Use keyboard automation directly for known Electron apps
        // This avoids trying the AX API which is known to fail on Electron
        if let context = monitoredContext, context.requiresKeyboardReplacement {
            Logger.debug("Detected Electron app (\(context.applicationName)) - using keyboard automation directly", category: Logger.analysis)

            applyTextReplacementViaKeyboard(for: error, with: suggestion, element: element, completion: wrappedCompletion)
            return
        }

        // Apple Mail: use WebKit-specific AXReplaceRangeWithText API
        // Standard AX selection + kAXSelectedTextAttribute doesn't work for Mail's WebKit
        if let context = monitoredContext, context.bundleIdentifier == "com.apple.mail" {
            Logger.debug("Detected Apple Mail - using WebKit-specific text replacement", category: Logger.analysis)
            applyMailTextReplacement(for: error, with: suggestion, element: element, completion: wrappedCompletion)
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

            applyTextReplacementViaKeyboard(for: error, with: suggestion, element: element, completion: completion)
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

            // Step 5: Remove error from UI immediately
            // Calculate length delta to adjust positions of remaining errors
            let lengthDelta = suggestion.count - (error.end - error.start)
            removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)

            // AX API is synchronous - call completion immediately
            wrappedCompletion()
        } else {
            // AX API replacement failed
            Logger.debug("AX API replacement failed (\(replaceError.rawValue)), trying keyboard fallback", category: Logger.analysis)

            // Try keyboard fallback
            applyTextReplacementViaKeyboard(for: error, with: suggestion, element: element, completion: wrappedCompletion)
        }
    }

    /// Apply text replacement for a style suggestion
    /// Similar to applyTextReplacement but uses StyleSuggestionModel's positions and suggested text
    private func applyStyleTextReplacement(for suggestion: StyleSuggestionModel) {
        Logger.debug("applyStyleTextReplacement called - original: '\(suggestion.originalText)', suggested: '\(suggestion.suggestedText)'", category: Logger.analysis)

        guard let element = textMonitor.monitoredElement else {
            Logger.debug("No monitored element for style text replacement", category: Logger.analysis)
            return
        }

        Logger.debug("Have monitored element for style replacement, context: \(monitoredContext?.applicationName ?? "nil")", category: Logger.analysis)

        // Use keyboard automation directly for known Electron apps
        if let context = monitoredContext, context.requiresKeyboardReplacement {
            Logger.debug("Detected Electron app (\(context.applicationName)) - using keyboard automation for style replacement", category: Logger.analysis)
            applyStyleReplacementViaKeyboard(for: suggestion, element: element)
            return
        }

        // For native macOS apps, try AX API first
        // CRITICAL: Get current text and find the ACTUAL position of the original text
        // The positions from Rust are byte offsets which don't match macOS character indices
        // Also, after previous replacements, positions may have shifted
        var currentTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentTextRef)

        guard textResult == .success,
              let currentText = currentTextRef as? String else {
            Logger.debug("Could not get current text for style replacement, using keyboard fallback", category: Logger.analysis)
            applyStyleReplacementViaKeyboard(for: suggestion, element: element)
            return
        }

        // Find the actual position of the original text in the current content
        guard let range = currentText.range(of: suggestion.originalText) else {
            Logger.debug("Could not find original text '\(suggestion.originalText)' in current content, skipping", category: Logger.analysis)
            // Remove from tracking since we can't apply it
            removeSuggestionFromTracking(suggestion)
            return
        }

        // Convert Swift range to character indices for AX API
        let startIndex = currentText.distance(from: currentText.startIndex, to: range.lowerBound)
        let length = suggestion.originalText.count

        Logger.debug("Found original text at character position \(startIndex), length \(length) (Rust reported \(suggestion.originalStart)-\(suggestion.originalEnd))", category: Logger.analysis)

        // Step 1: Save current selection
        var originalSelection: CFTypeRef?
        let _ = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &originalSelection
        )

        // Step 2: Set selection to the found text range
        var suggestionRange = CFRange(location: startIndex, length: length)
        let rangeValue = AXValueCreate(.cfRange, &suggestionRange)!

        let selectError = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if selectError != .success {
            Logger.debug("AX API selection failed for style replacement (\(selectError.rawValue)), using keyboard fallback", category: Logger.analysis)
            applyStyleReplacementViaKeyboard(for: suggestion, element: element)
            return
        }

        // Step 3: Replace selected text with suggested text
        let replaceError = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            suggestion.suggestedText as CFTypeRef
        )

        if replaceError == .success {
            Logger.debug("Style replacement successful via AX API", category: Logger.analysis)

            // Note: Don't call invalidateCacheAfterReplacement for style replacements
            // Style suggestions use text matching, not byte offsets, so remaining suggestions stay valid
            // Also, invalidateCacheAfterReplacement triggers re-analysis which would clear style suggestions

            // Invalidate style cache since text changed
            styleCache.removeAll()
            styleCacheMetadata.removeAll()

            // Move cursor after replacement
            var newPosition = CFRange(location: startIndex + suggestion.suggestedText.count, length: 0)
            let newRangeValue = AXValueCreate(.cfRange, &newPosition)!
            let _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                newRangeValue
            )

            // Remove the applied style suggestion from tracking
            removeSuggestionFromTracking(suggestion)
            // Note: Don't clear remaining suggestions - we find them by text match, not byte offset
        } else {
            Logger.debug("AX API replacement failed for style (\(replaceError.rawValue)), trying keyboard fallback", category: Logger.analysis)
            applyStyleReplacementViaKeyboard(for: suggestion, element: element)
        }
    }

    /// Apply style replacement via keyboard simulation (for Electron apps and fallback)
    private func applyStyleReplacementViaKeyboard(for suggestion: StyleSuggestionModel, element: AXUIElement) {
        guard let context = self.monitoredContext else {
            Logger.debug("No context available for style keyboard replacement", category: Logger.analysis)
            return
        }

        Logger.debug("Using keyboard simulation for style replacement (app: \(context.applicationName))", category: Logger.analysis)

        // For browsers, use the browser-specific approach
        if context.isBrowser {
            applyStyleBrowserReplacement(for: suggestion, element: element, context: context)
            return
        }

        // Get current text and find the ACTUAL position of the original text
        // The positions from Rust are byte offsets which don't match macOS character indices
        var currentTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentTextRef)

        guard textResult == .success,
              let currentText = currentTextRef as? String else {
            Logger.debug("Could not get current text for style keyboard replacement", category: Logger.analysis)
            return
        }

        // Find the actual position of the original text in the current content
        guard let range = currentText.range(of: suggestion.originalText) else {
            Logger.debug("Could not find original text '\(suggestion.originalText)' in current content for keyboard replacement", category: Logger.analysis)
            removeSuggestionFromTracking(suggestion)
            return
        }

        // Convert Swift range to character indices for AX API
        let startIndex = currentText.distance(from: currentText.startIndex, to: range.lowerBound)
        let length = suggestion.originalText.count

        // Standard keyboard approach: select range, paste replacement
        // Step 1: Try to select the range using AX API
        var suggestionRange = CFRange(location: startIndex, length: length)
        let rangeValue = AXValueCreate(.cfRange, &suggestionRange)!

        let selectResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if selectResult != .success {
            Logger.debug("Could not select text range for style replacement (error: \(selectResult.rawValue))", category: Logger.analysis)
            return
        }

        // Step 2: Copy suggestion to clipboard
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(suggestion.suggestedText, forType: .string)

        // Step 3: Simulate paste
        let delay = context.keyboardOperationDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pressKey(key: VirtualKeyCode.v, flags: .maskCommand)

            // Restore original clipboard after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let original = originalString {
                    pasteboard.clearContents()
                    pasteboard.setString(original, forType: .string)
                }
            }

            // Invalidate style cache (not grammar cache - don't trigger re-analysis)
            self?.styleCache.removeAll()
            self?.styleCacheMetadata.removeAll()
            self?.removeSuggestionFromTracking(suggestion)
            // Note: Don't clear remaining suggestions - we find them by text match, not byte offset
        }
    }

    /// Apply style replacement for browsers
    private func applyStyleBrowserReplacement(for suggestion: StyleSuggestionModel, element: AXUIElement, context: ApplicationContext) {
        Logger.debug("Browser style replacement for \(context.applicationName)", category: Logger.analysis)

        // Select the text to replace (handles Notion child element traversal internally)
        guard selectTextForReplacement(
            targetText: suggestion.originalText,
            fallbackRange: nil,  // Style suggestions use text search, not byte offsets
            element: element,
            context: context
        ) else {
            Logger.debug("Failed to select text for style replacement", category: Logger.analysis)
            removeSuggestionFromTracking(suggestion)
            return
        }

        // Save original pasteboard and copy suggestion
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(suggestion.suggestedText, forType: .string)

        // Step 3: Activate the browser
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier)
        if let targetApp = apps.first {
            targetApp.activate()
        }

        // Step 4: Try paste via menu action or keyboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            var pasteSucceeded = false

            // Try menu action first
            if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
                if let pasteMenuItem = self?.findPasteMenuItem(in: appElement) {
                    let pressResult = AXUIElementPerformAction(pasteMenuItem, kAXPressAction as CFString)
                    if pressResult == .success {
                        pasteSucceeded = true
                        Logger.debug("Style pasted via menu action", category: Logger.analysis)
                    }
                }
            }

            // Fallback to keyboard if menu failed
            if !pasteSucceeded {
                self?.pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
                Logger.debug("Style pasted via keyboard simulation", category: Logger.analysis)
            }

            // Restore original clipboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let original = originalString {
                    pasteboard.clearContents()
                    pasteboard.setString(original, forType: .string)
                }
            }

            // Invalidate style cache (not grammar cache - don't trigger re-analysis)
            self?.styleCache.removeAll()
            self?.styleCacheMetadata.removeAll()
            self?.removeSuggestionFromTracking(suggestion)
            // Note: Don't clear remaining suggestions - we find them by text match, not byte offset
        }
    }

    /// Remove an applied style suggestion from tracking and update UI
    private func removeSuggestionFromTracking(_ suggestion: StyleSuggestionModel) {
        // Remove from current suggestions
        currentStyleSuggestions.removeAll { $0.id == suggestion.id }

        // Update popover's allStyleSuggestions
        suggestionPopover.allStyleSuggestions.removeAll { $0.id == suggestion.id }

        Logger.debug("Removed style suggestion from tracking, remaining: \(currentStyleSuggestions.count)", category: Logger.analysis)

        // Update the floating indicator with remaining suggestions
        if currentStyleSuggestions.isEmpty {
            // No more suggestions - hide indicator
            Logger.debug("AnalysisCoordinator: No remaining style suggestions, hiding indicator", category: Logger.analysis)
            floatingIndicator.hide()
        } else {
            // Update indicator with remaining count
            Logger.debug("AnalysisCoordinator: \(currentStyleSuggestions.count) style suggestions remaining, updating indicator", category: Logger.analysis)
            if let element = textMonitor.monitoredElement {
                floatingIndicator.update(
                    errors: [],
                    styleSuggestions: currentStyleSuggestions,
                    element: element,
                    context: monitoredContext,
                    sourceText: lastAnalyzedText
                )
            }
        }
    }

    /// Apply text replacement for Apple Mail using AXReplaceRangeWithText
    /// Mail's WebKit composition area supports this proper API, which preserves formatting
    private func applyMailTextReplacement(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, completion: @escaping () -> Void) {
        Logger.debug("Mail text replacement using AXReplaceRangeWithText", category: Logger.analysis)

        // Mark that we're applying a suggestion - prevents typing callback from hiding overlays
        lastReplacementTime = Date()

        // Look up the CURRENT error position from currentErrors
        let currentError = currentErrors.first { err in
            err.message == error.message && err.lintId == error.lintId && err.category == error.category
        } ?? error

        Logger.debug("Mail replacement: Using positions \(currentError.start)-\(currentError.end)", category: Logger.analysis)

        let range = NSRange(location: currentError.start, length: currentError.end - currentError.start)
        let lengthDelta = suggestion.count - (currentError.end - currentError.start)

        // Try the proper WebKit API first
        if MailContentParser.replaceText(range: range, with: suggestion, in: element) {
            Logger.info("Mail: AXReplaceRangeWithText succeeded", category: Logger.analysis)
            // Update UI immediately so popover shows next error
            removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)
            completion()
            return
        }

        // Fallback: try selection + paste approach
        Logger.debug("Mail: AXReplaceRangeWithText failed, falling back to selection + paste", category: Logger.analysis)

        let selectSuccess = MailContentParser.selectTextForReplacement(range: range, in: element)
        Logger.debug("Mail: Selection \(selectSuccess ? "succeeded" : "failed")", category: Logger.analysis)

        // Even if selection fails, try paste anyway
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        // Activate Mail
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail")
        if let mailApp = apps.first {
            mailApp.activate()
        }

        // Wait then paste - use shorter delays for native apps (50ms is enough)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
            Logger.debug("Mail: Pasted via Cmd+V", category: Logger.analysis)

            // Update UI immediately so popover shows next error
            self?.removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)

            // Restore clipboard and complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let original = originalString {
                    pasteboard.clearContents()
                    pasteboard.setString(original, forType: .string)
                }
                completion()
            }
        }
    }

    /// Apply text replacement for browsers using menu action with keyboard fallback
    /// Browsers often have silently failing AX APIs, so we use SelectedTextKit's approach:
    /// 1. Try to select text range via AX API (even if it silently fails)
    /// 2. Copy suggestion to clipboard
    /// 3. Try paste via menu action (more reliable)
    /// 4. Fallback to Cmd+V if menu fails
    private func applyBrowserTextReplacement(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, context: ApplicationContext, completion: @escaping () -> Void) {
        Logger.debug("Browser text replacement for \(context.applicationName)", category: Logger.analysis)

        // CRITICAL: Look up the CURRENT error position from currentErrors
        // The popover may have stale positions if previous replacements shifted the text
        // Match by message + lintId + category (should uniquely identify the error)
        let currentError = currentErrors.first { err in
            err.message == error.message && err.lintId == error.lintId && err.category == error.category
        } ?? error  // Fallback to original if not found

        Logger.debug("Browser replacement: Using positions \(currentError.start)-\(currentError.end) (original was \(error.start)-\(error.end))", category: Logger.analysis)

        // Get the error text for selection using CURRENT positions
        let cachedText = self.currentSegment?.content ?? self.previousText
        let errorText: String
        if !cachedText.isEmpty && currentError.start < cachedText.count && currentError.end <= cachedText.count {
            let startIdx = cachedText.index(cachedText.startIndex, offsetBy: currentError.start)
            let endIdx = cachedText.index(cachedText.startIndex, offsetBy: currentError.end)
            errorText = String(cachedText[startIdx..<endIdx])
            Logger.debug("Browser replacement: Extracted error text '\(errorText)' from positions \(currentError.start)-\(currentError.end)", category: Logger.analysis)
        } else {
            // Fallback: use error range directly (may not work for Notion)
            errorText = ""
            Logger.debug("Browser replacement: Could not extract error text, will use fallback", category: Logger.analysis)
        }

        // Select the text to replace (handles Notion child element traversal internally)
        let fallbackRange = errorText.isEmpty ? CFRange(location: currentError.start, length: currentError.end - currentError.start) : nil
        let targetText = errorText.isEmpty ? suggestion : errorText

        _ = selectTextForReplacement(
            targetText: targetText,
            fallbackRange: fallbackRange,
            element: element,
            context: context
        )

        // Save original pasteboard content
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
            // Calculate when the paste will complete
            let pasteCompleteDelay: TimeInterval
            if !pasteSucceeded {
                // Need to wait for keyboard fallback delay + paste execution time
                pasteCompleteDelay = delay + 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
                    Logger.debug("Pasted via keyboard shortcut (Cmd+V fallback)", category: Logger.analysis)
                }
            } else {
                // Menu paste is faster
                pasteCompleteDelay = 0.1
            }

            // Step 7: Wait for paste to complete, then restore pasteboard and signal completion
            // IMPORTANT: Must wait long enough for Electron apps to process the paste
            let completionDelay = pasteCompleteDelay + 0.15  // Extra buffer for Electron processing
            DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) {
                // Restore original pasteboard
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
                UserStatistics.shared.recordSuggestionApplied(category: currentError.category)

                // Invalidate cache - use currentError's CURRENT positions
                self.invalidateCacheAfterReplacement(at: currentError.start..<currentError.end)

                // Remove error from UI immediately
                // Calculate length delta to adjust positions of remaining errors
                let lengthDelta = suggestion.count - (currentError.end - currentError.start)
                self.removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)

                Logger.debug("Browser text replacement complete (waited \(completionDelay)s)", category: Logger.analysis)

                // Signal completion to the popover - safe to advance to next error now
                completion()
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

    /// Select text in an AX element for replacement
    /// Handles Notion/Electron apps by traversing child elements to find paragraph-relative offsets
    /// Returns true if selection succeeded (or was attempted), false if it failed critically
    private func selectTextForReplacement(
        targetText: String,
        fallbackRange: CFRange?,
        element: AXUIElement,
        context: ApplicationContext
    ) -> Bool {
        let isNotion = context.bundleIdentifier == "notion.id" || context.bundleIdentifier == "com.notion.id"
        let isSlack = context.bundleIdentifier == "com.tinyspeck.slackmacgap"
        let isMail = context.bundleIdentifier == "com.apple.mail"

        // Apple Mail: use WebKit-specific marker-based selection
        if isMail {
            Logger.debug("Mail: Using WebKit-specific text selection for '\(targetText)'", category: Logger.analysis)

            if let range = fallbackRange {
                let nsRange = NSRange(location: range.location, length: range.length)
                let success = MailContentParser.selectTextForReplacement(range: nsRange, in: element)
                if success {
                    Logger.debug("Mail: WebKit selection succeeded", category: Logger.analysis)
                } else {
                    Logger.debug("Mail: WebKit selection failed - paste may go to wrong location", category: Logger.analysis)
                }
                return true  // Always try paste even if selection fails
            } else {
                // Try to find the text position
                if let currentText = extractCurrentText(from: element),
                   let textRange = currentText.range(of: targetText) {
                    let start = currentText.distance(from: currentText.startIndex, to: textRange.lowerBound)
                    let nsRange = NSRange(location: start, length: targetText.count)
                    let success = MailContentParser.selectTextForReplacement(range: nsRange, in: element)
                    Logger.debug("Mail: Text search + selection \(success ? "succeeded" : "failed")", category: Logger.analysis)
                    return true
                }
                Logger.debug("Mail: Could not find text to select", category: Logger.analysis)
                return true  // Still try paste
            }
        }

        // Electron apps (Notion, Slack) need child element traversal for selection
        if isNotion || isSlack {
            let appName = isNotion ? "Notion" : "Slack"
            Logger.debug("\(appName): Looking for text '\(targetText)' to select", category: Logger.analysis)

            // Try to find child element containing the text and select within it
            if let (childElement, offsetInChild) = findChildElementContainingText(targetText, in: element) {
                var childRange = CFRange(location: offsetInChild, length: targetText.count)
                guard let childRangeValue = AXValueCreate(.cfRange, &childRange) else {
                    Logger.debug("\(appName): Failed to create AXValue for child range", category: Logger.analysis)
                    return false
                }

                let childSelectResult = AXUIElementSetAttributeValue(
                    childElement,
                    kAXSelectedTextRangeAttribute as CFString,
                    childRangeValue
                )

                if childSelectResult == .success {
                    Logger.debug("\(appName): Selected text in child element (range: \(offsetInChild)-\(offsetInChild + targetText.count))", category: Logger.analysis)
                } else {
                    Logger.debug("\(appName): Child selection failed (\(childSelectResult.rawValue))", category: Logger.analysis)
                }
                return true
            } else {
                Logger.debug("\(appName): Could not find child element, falling back to main element", category: Logger.analysis)
                return true  // Let caller try paste anyway
            }
        } else {
            // Standard browser: try AX API selection directly
            // This may silently fail, but it's fast and works sometimes
            guard var range = fallbackRange else {
                // Need to find text in current element content
                var currentTextRef: CFTypeRef?
                let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentTextRef)

                guard textResult == .success,
                      let currentText = currentTextRef as? String else {
                    Logger.debug("Could not get current text for browser replacement", category: Logger.analysis)
                    return false
                }

                guard let textRange = currentText.range(of: targetText) else {
                    Logger.debug("Could not find text '\(targetText)' in current content", category: Logger.analysis)
                    return false
                }

                let startIndex = currentText.distance(from: currentText.startIndex, to: textRange.lowerBound)
                var calculatedRange = CFRange(location: startIndex, length: targetText.count)
                guard let rangeValue = AXValueCreate(.cfRange, &calculatedRange) else {
                    Logger.debug("Failed to create AXValue for range", category: Logger.analysis)
                    return false
                }

                let selectResult = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    rangeValue
                )

                if selectResult == .success {
                    Logger.debug("AX API accepted selection for browser", category: Logger.analysis)
                } else {
                    Logger.debug("AX API selection failed (\(selectResult.rawValue)) - will try paste anyway", category: Logger.analysis)
                }
                return true
            }

            guard let rangeValue = AXValueCreate(.cfRange, &range) else {
                Logger.debug("Failed to create AXValue for fallback range", category: Logger.analysis)
                return false
            }

            let selectResult = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            )

            if selectResult == .success {
                Logger.debug("AX API accepted selection (range: \(range.location)-\(range.location + range.length))", category: Logger.analysis)
            } else {
                Logger.debug("AX API selection failed (\(selectResult.rawValue)) - will try paste anyway", category: Logger.analysis)
            }
            return true
        }
    }

    /// Extract current text from an element (for text search during replacement)
    /// Handles Mail's WebKit-based elements that need child traversal
    private func extractCurrentText(from element: AXUIElement) -> String? {
        // First try standard AXValue
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String,
           !text.isEmpty {
            return text
        }

        // For Mail/WebKit: use MailContentParser's extraction
        if let parser = ContentParserFactory.shared.parser(for: "com.apple.mail") as? MailContentParser {
            return parser.extractText(from: element)
        }

        return nil
    }

    /// Find the child element containing the target text and return the offset within that element
    /// Used for Notion and other Electron apps where document-level offsets don't work
    private func findChildElementContainingText(_ targetText: String, in element: AXUIElement) -> (AXUIElement, Int)? {
        var candidates: [(element: AXUIElement, text: String, offset: Int)] = []
        collectTextElements(in: element, depth: 0, maxDepth: 10, candidates: &candidates, targetText: targetText)

        for candidate in candidates {
            guard let range = candidate.text.range(of: targetText) else { continue }
            let offset = candidate.text.distance(from: candidate.text.startIndex, to: range.lowerBound)
            Logger.debug("Found '\(targetText)' in child element at offset \(offset)", category: Logger.analysis)
            return (candidate.element, offset)
        }

        return nil
    }

    /// Collect child text elements for element tree traversal
    private func collectTextElements(
        in element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        candidates: inout [(element: AXUIElement, text: String, offset: Int)],
        targetText: String
    ) {
        guard depth < maxDepth else { return }

        var textValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
           let text = textValue as? String,
           text.contains(targetText) {

            var sizeValue: CFTypeRef?
            var height: CGFloat = 0
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let size = sizeValue {
                var rectSize = CGSize.zero
                // Force cast is safe: AXValueGetValue returns false if type doesn't match
                if AXValueGetValue(size as! AXValue, .cgSize, &rectSize) {
                    height = rectSize.height
                }
            }

            // Prefer smaller elements (paragraph-level, not document-level)
            if height > 0 && height < 200 {
                candidates.append((element: element, text: text, offset: 0))
                Logger.debug("Candidate element height=\(height), text length=\(text.count)", category: Logger.analysis)
            }
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children.prefix(100) {
                collectTextElements(in: child, depth: depth + 1, maxDepth: maxDepth, candidates: &candidates, targetText: targetText)
            }
        }
    }

    /// Apply text replacement using keyboard simulation (for Electron apps and Terminals)
    /// Uses hybrid replacement approach: try AX API first, fall back to keyboard
    private func applyTextReplacementViaKeyboard(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, completion: @escaping () -> Void) {
        guard let context = self.monitoredContext else {
            Logger.debug("No context available for keyboard replacement", category: Logger.analysis)
            completion()
            return
        }

        Logger.debug("Using keyboard simulation for text replacement (app: \(context.applicationName), isTerminal: \(context.isTerminalApp), isBrowser: \(context.isBrowser))", category: Logger.analysis)

        // SPECIAL HANDLING FOR APPLE MAIL
        // Mail's WebKit composition area supports AXReplaceRangeWithText - use it directly
        let isMail = context.bundleIdentifier == "com.apple.mail"
        if isMail {
            applyMailTextReplacement(for: error, with: suggestion, element: element, completion: completion)
            return
        }

        // SPECIAL HANDLING FOR BROWSERS AND SLACK
        // Browsers and Slack have contenteditable areas where AX API often silently fails
        // Use simplified approach: select via AX API, then paste via menu action or Cmd+V
        // Inspired by SelectedTextKit's menu action approach
        let isSlack = context.bundleIdentifier == "com.tinyspeck.slackmacgap"
        if context.isBrowser || isSlack {
            applyBrowserTextReplacement(for: error, with: suggestion, element: element, context: context, completion: completion)
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

                                    // Remove error from UI immediately
                                    let lengthDelta = suggestion.count - (error.end - error.start)
                                    self.removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)

                                    // Signal completion
                                    completion()
                                }
                            } else {
                                // Fallback: move to end if we couldn't determine target position
                                self.pressKey(key: VirtualKeyCode.e, flags: .maskControl)

                                Logger.debug("Terminal replacement complete (cursor at end - position unknown)", category: Logger.analysis)

                                // Record statistics
                                UserStatistics.shared.recordSuggestionApplied(category: error.category)

                                // Invalidate cache
                                self.invalidateCacheAfterReplacement(at: error.start..<error.end)

                                // Remove error from UI immediately
                                let lengthDelta = suggestion.count - (error.end - error.start)
                                self.removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)

                                // Signal completion
                                completion()
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

                        // Remove error from UI immediately
                        let lengthDelta = suggestion.count - (error.end - error.start)
                        self.removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)

                        // Signal completion
                        completion()
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
        // Clear position cache - geometry is now stale since text positions shifted
        PositionResolver.shared.clearCache()

        // Check if this is an Electron app (Notion, etc.) where positioning is fragile
        let bundleID = monitoredContext?.bundleIdentifier ?? ""
        let appConfig = AppRegistry.shared.configuration(for: bundleID)
        let isElectronApp = appConfig.category == .electron || appConfig.category == .browser

        if isElectronApp {
            // For Electron apps: Clear ALL errors and force complete re-analysis
            // Their byte offsets become invalid when text shifts, causing underline drift
            currentErrors.removeAll()
            errorOverlay.hide()
            floatingIndicator.hide()

            // Force fresh analysis by clearing cached text and re-extracting
            // This triggers immediate re-analysis instead of waiting for next AX notification
            previousText = ""
            if let element = textMonitor.monitoredElement {
                textMonitor.extractText(from: element)
            }
        } else {
            // For native apps: Just clear overlapping errors and trigger re-analysis
            // Native apps handle position updates more reliably
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
            Logger.debug("AnalysisCoordinator: Purged \(expiredKeys.count) expired cache entries", category: Logger.performance)
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

        Logger.debug("AnalysisCoordinator: Evicted \(toRemove) LRU cache entries", category: Logger.performance)
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

    // MARK: - Style Cache Methods

    /// Compute a cache key for style analysis based on text content, style, model, and preset
    /// Uses a hash to keep keys short while being collision-resistant
    /// Includes model ID and preset so changing these triggers re-analysis of the same text
    func computeStyleCacheKey(text: String) -> String {
        let style = UserPreferences.shared.selectedWritingStyle
        let modelId = UserPreferences.shared.selectedModelId
        let preset = UserPreferences.shared.styleInferencePreset
        let combined = "\(text.hashValue)_\(style)_\(modelId)_\(preset)"
        return combined
    }

    /// Evict old style cache entries
    func evictStyleCacheIfNeeded() {
        // First, purge expired entries
        let now = Date()
        var expiredKeys: [String] = []

        for (key, metadata) in styleCacheMetadata {
            if now.timeIntervalSince(metadata.lastAccessed) > styleCacheExpirationTime {
                expiredKeys.append(key)
            }
        }

        for key in expiredKeys {
            styleCache.removeValue(forKey: key)
            styleCacheMetadata.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            Logger.debug("Style cache: Purged \(expiredKeys.count) expired entries", category: Logger.llm)
        }

        // Then, evict LRU if still over limit
        guard styleCacheMetadata.count > maxStyleCacheEntries else { return }

        let sortedEntries = styleCacheMetadata.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        let toRemove = sortedEntries.count - maxStyleCacheEntries

        for i in 0..<toRemove {
            let key = sortedEntries[i].key
            styleCache.removeValue(forKey: key)
            styleCacheMetadata.removeValue(forKey: key)
        }

        Logger.debug("Style cache: Evicted \(toRemove) LRU entries", category: Logger.llm)
    }

    /// Clear style cache (e.g., when model changes)
    func clearStyleCache() {
        styleCache.removeAll()
        styleCacheMetadata.removeAll()
        Logger.debug("Style cache cleared", category: Logger.llm)
    }

    // MARK: - Manual Style Check

    /// Run a manual style check triggered by keyboard shortcut
    /// If text is selected, only analyzes the selected portion; otherwise analyzes all text
    /// First checks cache for instant results, otherwise shows spinning indicator and runs analysis
    func runManualStyleCheck() {
        Logger.info("AnalysisCoordinator: runManualStyleCheck() triggered", category: Logger.llm)

        // Get current monitored element and context
        guard let element = textMonitor.monitoredElement,
              let context = monitoredContext else {
            Logger.warning("AnalysisCoordinator: No monitored element for manual style check", category: Logger.llm)
            return
        }

        // Check if LLM is ready
        guard LLMEngine.shared.isInitialized && LLMEngine.shared.isModelLoaded() else {
            Logger.warning("AnalysisCoordinator: LLM not ready for manual style check", category: Logger.llm)
            return
        }

        // Check for selected text first - if user has text selected, only analyze that
        // Otherwise fall back to analyzing all text
        let selectedText = getSelectedText()
        let isSelectionMode = selectedText != nil

        // Always capture full text for invalidation tracking
        guard let fullText = getCurrentText(), !fullText.isEmpty else {
            Logger.warning("AnalysisCoordinator: No text available for manual style check", category: Logger.llm)
            return
        }

        // Text to analyze is either the selection or the full text
        let text = selectedText ?? fullText

        if isSelectionMode {
            Logger.info("AnalysisCoordinator: Manual style check - analyzing selected text (\(text.count) chars)", category: Logger.llm)
        }

        let styleName = UserPreferences.shared.selectedWritingStyle
        let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default

        // Check cache first - instant results if text hasn't changed
        // Note: Cache is keyed by analyzed text, but we also need full text to match for validity
        let cacheKey = computeStyleCacheKey(text: text)
        if let cached = styleCache[cacheKey], fullText == styleAnalysisSourceText {
            Logger.info("AnalysisCoordinator: Manual style check - using cached results (\(cached.count) suggestions)", category: Logger.llm)

            // Update cache access time
            styleCacheMetadata[cacheKey] = StyleCacheMetadata(
                lastAccessed: Date(),
                style: styleName
            )

            // Set flag and show results immediately
            isManualStyleCheckActive = true
            currentStyleSuggestions = cached
            styleAnalysisSourceText = fullText

            // Show checkmark and results immediately (no spinning needed)
            floatingIndicator.showStyleSuggestionsReady(
                count: cached.count,
                styleSuggestions: cached
            )

            // Clear the flag after the checkmark display period
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                self?.isManualStyleCheckActive = false
            }

            return
        }

        // Cache miss - run LLM analysis
        Logger.debug("AnalysisCoordinator: Manual style check - cache miss, running LLM analysis", category: Logger.llm)

        // Set flag to prevent regular analysis from hiding indicator
        isManualStyleCheckActive = true

        // Show spinning indicator immediately
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.floatingIndicator.showStyleCheckInProgress(element: element, context: context)
        }

        // Capture fullText for setting styleAnalysisSourceText when analysis completes
        let capturedFullText = fullText

        // Run style analysis in background
        styleAnalysisQueue.async { [weak self] in
            guard let self = self else { return }

            let segmentContent = text

            Logger.info("AnalysisCoordinator: Running manual style analysis on \(segmentContent.count) chars", category: Logger.llm)

            let startTime = Date()
            let styleResult = LLMEngine.shared.analyzeStyle(segmentContent, style: style)
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

            Logger.info("AnalysisCoordinator: Manual style check completed in \(latencyMs)ms, \(styleResult.suggestions.count) suggestions", category: Logger.llm)

            // Update statistics with model and preset context
            let modelId = UserPreferences.shared.selectedModelId
            let preset = UserPreferences.shared.styleInferencePreset
            UserStatistics.shared.recordStyleSuggestions(
                count: styleResult.suggestions.count,
                latencyMs: Double(latencyMs),
                modelId: modelId,
                preset: preset
            )

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if !styleResult.isError {
                    let threshold = Float(UserPreferences.shared.styleConfidenceThreshold)
                    let filteredSuggestions = styleResult.suggestions.filter { $0.confidence >= threshold }
                    self.currentStyleSuggestions = filteredSuggestions
                    self.styleAnalysisSourceText = capturedFullText

                    // Cache the results for instant access next time
                    self.styleCache[cacheKey] = filteredSuggestions
                    self.styleCacheMetadata[cacheKey] = StyleCacheMetadata(
                        lastAccessed: Date(),
                        style: styleName
                    )
                    self.evictStyleCacheIfNeeded()

                    // Update indicator to show results (checkmark first, then transition)
                    self.floatingIndicator.showStyleSuggestionsReady(
                        count: filteredSuggestions.count,
                        styleSuggestions: filteredSuggestions
                    )

                    // Clear the flag after the checkmark display period (6 seconds to be safe)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                        self?.isManualStyleCheckActive = false
                    }

                    Logger.info("AnalysisCoordinator: Manual style check - showing \(filteredSuggestions.count) suggestions (cached for next time)", category: Logger.llm)
                } else {
                    // Error occurred - still show checkmark to indicate completion, then hide
                    self.currentStyleSuggestions = []

                    // Show checkmark even for errors so user knows check completed
                    self.floatingIndicator.showStyleSuggestionsReady(
                        count: 0,
                        styleSuggestions: []
                    )

                    // Clear the flag after the checkmark display period (6 seconds to be safe)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                        self?.isManualStyleCheckActive = false
                    }

                    Logger.warning("AnalysisCoordinator: Manual style analysis returned error: \(styleResult.error ?? "unknown")", category: Logger.llm)
                }
            }
        }
    }

    /// Get current text from monitored element
    private func getCurrentText() -> String? {
        guard let element = textMonitor.monitoredElement else { return nil }

        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)

        guard result == .success, let value = valueRef as? String else {
            return nil
        }

        return value
    }

    /// Get currently selected text from monitored element, if any
    /// Returns nil if no text is selected (cursor only) or if selection cannot be retrieved
    private func getSelectedText() -> String? {
        guard let element = textMonitor.monitoredElement else { return nil }

        // First check if there's a selection range with non-zero length
        guard let range = AccessibilityBridge.getSelectedTextRange(element),
              range.length > 0 else {
            return nil
        }

        // Get the selected text content
        var selectedTextRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        guard result == .success, let selectedText = selectedTextRef as? String, !selectedText.isEmpty else {
            return nil
        }

        return selectedText
    }

    // MARK: - AI-Enhanced Readability Suggestions

    /// Synchronously enhance errors with cached AI suggestions (main thread only)
    /// This is called before displaying errors to immediately show cached suggestions
    /// without going through the async enhancement flow
    private func enhanceErrorsWithCachedAI(
        _ errors: [GrammarErrorModel],
        sourceText: String
    ) -> [GrammarErrorModel] {
        // Only process readability errors that might have cached suggestions
        var enhancedErrors = errors

        for (index, error) in errors.enumerated() {
            // Check if this is a readability error without suggestions
            guard error.category == "Readability",
                  error.message.lowercased().contains("words long"),
                  error.suggestions.isEmpty else {
                continue
            }

            // Extract the sentence text
            let start = error.start
            let end = error.end

            guard start >= 0, end <= sourceText.count, start < end else {
                continue
            }

            let startIndex = sourceText.index(sourceText.startIndex, offsetBy: start)
            let endIndex = sourceText.index(sourceText.startIndex, offsetBy: end)
            let sentence = String(sourceText[startIndex..<endIndex])

            // Check if we have a cached AI suggestion
            if let cachedRephrase = aiRephraseCache[sentence] {
                Logger.info("AnalysisCoordinator: Pre-populating cached AI rephrase for sentence of length \(sentence.count)", category: Logger.llm)

                // Create enhanced error with cached AI suggestion
                let enhancedError = GrammarErrorModel(
                    start: error.start,
                    end: error.end,
                    message: error.message,
                    severity: error.severity,
                    category: error.category,
                    lintId: error.lintId,
                    suggestions: [sentence, cachedRephrase]
                )
                enhancedErrors[index] = enhancedError
            }
        }

        return enhancedErrors
    }

    /// Enhance readability errors (like LongSentences) with AI-generated rephrase suggestions
    /// This runs asynchronously after grammar analysis and updates the UI when suggestions are ready
    private func enhanceReadabilityErrorsWithAI(
        errors: [GrammarErrorModel],
        sourceText: String,
        element: AXUIElement?,
        segment: TextSegment
    ) {
        // Check if AI enhancement is available
        let styleCheckingEnabled = UserPreferences.shared.enableStyleChecking
        let llmInitialized = LLMEngine.shared.isInitialized
        let modelLoaded = LLMEngine.shared.isModelLoaded()

        guard styleCheckingEnabled && llmInitialized && modelLoaded else {
            Logger.debug("AnalysisCoordinator: AI enhancement skipped - style checking not available", category: Logger.llm)
            return
        }

        // Find readability errors that have no suggestions (long sentences)
        // The lint ID format is "Category::message_key", e.g., "Readability::this_sentence_is_50_words_long"
        // We check if:
        // 1. Category is "Readability" (error.category == "Readability")
        // 2. Message contains "words long" (indicates long sentence lint)
        // 3. Has no suggestions from Harper
        let readabilityErrorsWithoutSuggestions = errors.filter { error in
            error.category == "Readability" &&
            error.message.lowercased().contains("words long") &&
            error.suggestions.isEmpty
        }

        // Debug logging for all errors
        for error in errors {
            Logger.debug("AnalysisCoordinator: Error - category=\(error.category), lintId=\(error.lintId), suggestions=\(error.suggestions.count)", category: Logger.llm)
        }

        guard !readabilityErrorsWithoutSuggestions.isEmpty else {
            return
        }

        Logger.info("AnalysisCoordinator: Found \(readabilityErrorsWithoutSuggestions.count) readability error(s) needing AI suggestions", category: Logger.llm)

        // Process each readability error asynchronously
        styleAnalysisQueue.async { [weak self] in
            guard let self = self else { return }

            var enhancedErrors: [GrammarErrorModel] = []

            for error in readabilityErrorsWithoutSuggestions {
                // Extract the problematic sentence from source text
                let start = error.start
                let end = error.end

                guard start >= 0, end <= sourceText.count, start < end else {
                    Logger.warning("AnalysisCoordinator: Invalid error range for AI enhancement", category: Logger.llm)
                    continue
                }

                let startIndex = sourceText.index(sourceText.startIndex, offsetBy: start)
                let endIndex = sourceText.index(sourceText.startIndex, offsetBy: end)
                let sentence = String(sourceText[startIndex..<endIndex])

                // Check AI rephrase cache first
                var rephrased: String?

                // Access cache on main thread to avoid race conditions
                DispatchQueue.main.sync {
                    rephrased = self.aiRephraseCache[sentence]
                }

                if rephrased != nil {
                    Logger.info("AnalysisCoordinator: Using cached AI rephrase for sentence of length \(sentence.count)", category: Logger.llm)
                } else {
                    Logger.debug("AnalysisCoordinator: Generating AI rephrase for sentence of length \(sentence.count)", category: Logger.llm)

                    // Generate AI suggestion
                    rephrased = LLMEngine.shared.rephraseSentence(sentence)

                    // Cache the result on main thread
                    if let newRephrase = rephrased {
                        DispatchQueue.main.sync {
                            // Evict old entries if cache is full
                            if self.aiRephraseCache.count >= self.aiRephraseCacheMaxEntries {
                                // Remove first (oldest) entry - simple FIFO eviction
                                if let firstKey = self.aiRephraseCache.keys.first {
                                    self.aiRephraseCache.removeValue(forKey: firstKey)
                                }
                            }
                            self.aiRephraseCache[sentence] = newRephrase
                            Logger.debug("AnalysisCoordinator: Cached AI rephrase (cache size: \(self.aiRephraseCache.count))", category: Logger.llm)
                        }
                    }
                }

                if let finalRephrase = rephrased {
                    Logger.info("AnalysisCoordinator: AI rephrase available", category: Logger.llm)

                    // Create enhanced error with AI suggestion
                    // Store both original sentence (index 0) and rephrase (index 1) for Before/After display
                    let enhancedError = GrammarErrorModel(
                        start: error.start,
                        end: error.end,
                        message: error.message,
                        severity: error.severity,
                        category: error.category,
                        lintId: error.lintId,
                        suggestions: [sentence, finalRephrase]
                    )
                    enhancedErrors.append(enhancedError)
                } else {
                    Logger.debug("AnalysisCoordinator: AI rephrase failed for sentence", category: Logger.llm)
                }
            }

            // Update UI with enhanced errors
            guard !enhancedErrors.isEmpty else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Replace the original readability errors with enhanced versions
                var updatedErrors = self.currentErrors

                for enhancedError in enhancedErrors {
                    // Find and replace the matching error
                    if let index = updatedErrors.firstIndex(where: { existingError in
                        existingError.start == enhancedError.start &&
                        existingError.end == enhancedError.end &&
                        existingError.lintId == enhancedError.lintId
                    }) {
                        updatedErrors[index] = enhancedError
                        Logger.debug("AnalysisCoordinator: Replaced error at index \(index) with AI-enhanced version", category: Logger.llm)
                    }
                }

                // Update the error list and UI
                self.currentErrors = updatedErrors
                self.updateErrorCache(for: segment, with: updatedErrors)

                // Refresh the error overlay (underlines and popover) with updated errors
                if let element = element, let context = self.monitoredContext {
                    _ = self.errorOverlay.update(errors: updatedErrors, element: element, context: context)
                }

                // Refresh the floating indicator if visible
                if let element = element {
                    self.floatingIndicator.update(
                        errors: updatedErrors,
                        styleSuggestions: self.currentStyleSuggestions,
                        element: element,
                        context: self.monitoredContext,
                        sourceText: self.lastAnalyzedText
                    )
                }

                // Auto-refresh the popover if it's showing the updated error
                // This enables seamless transition from "loading" to "Before/After" view
                self.suggestionPopover.updateErrors(updatedErrors)

                Logger.info("AnalysisCoordinator: Updated UI with \(enhancedErrors.count) AI-enhanced readability error(s)", category: Logger.llm)
            }
        }
    }
}

// MARK: - Cache Metadata

/// Metadata for cache entries to support LRU eviction and expiration
private struct CacheMetadata {
    let lastAccessed: Date
    let documentSize: Int
}

/// Metadata for style cache entries
private struct StyleCacheMetadata {
    let lastAccessed: Date
    let style: String // The writing style used for this analysis
}
