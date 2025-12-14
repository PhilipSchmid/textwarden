//
//  AnalysisCoordinator.swift
//  TextWarden
//
//  Orchestrates text monitoring, grammar analysis, and UI presentation.
//
//  This is the main coordinator class, with functionality split across extensions:
//  - AnalysisCoordinator+GrammarAnalysis.swift - Grammar/style analysis dispatch
//  - AnalysisCoordinator+StyleChecking.swift - LLM style analysis and caching
//  - AnalysisCoordinator+WindowTracking.swift - Window movement, scroll, validation
//  - AnalysisCoordinator+TextReplacement.swift - Applying suggestions to text
//
//  Supporting classes:
//  - AIRephraseCache.swift - Thread-safe LRU cache for AI rephrase suggestions
//

import Foundation
import AppKit
@preconcurrency import ApplicationServices
import Combine

/// Coordinates grammar analysis workflow: monitoring → analysis → UI
///
/// # Testability
/// This class supports full dependency injection via `DependencyContainer`.
/// Production code uses the `shared` singleton which initializes with `.production` dependencies.
/// Tests can create instances with mock dependencies.
///
/// Example test setup:
/// ```swift
/// let mockContainer = DependencyContainer(
///     textMonitor: MockTextMonitor(),
///     grammarEngine: MockGrammarEngine(),
///     // ... other mocks
/// )
/// let coordinator = AnalysisCoordinator(dependencies: mockContainer)
/// ```
@MainActor
class AnalysisCoordinator: ObservableObject {

    // MARK: - Singleton

    static let shared = AnalysisCoordinator()

    // MARK: - Dependencies (injectable for testing, internal for extension access)

    /// Text monitor for accessibility
    let textMonitor: TextMonitor

    /// Application tracker
    let applicationTracker: ApplicationTracker

    /// Permission manager
    let permissionManager: PermissionManager

    /// Grammar analysis engine
    let grammarEngine: GrammarAnalyzing

    /// LLM style analysis engine
    let llmEngine: StyleAnalyzing

    /// User preferences
    let userPreferences: UserPreferencesProviding

    /// App configuration registry
    let appRegistry: AppConfigurationProviding

    /// Custom vocabulary
    let customVocabulary: CustomVocabularyProviding

    /// Browser URL extractor
    let browserURLExtractor: BrowserURLExtracting

    /// Position resolver
    let positionResolver: PositionResolving

    /// Statistics tracker
    let statistics: StatisticsTracking

    /// Suggestion popover
    let suggestionPopover: SuggestionPopover

    /// Error overlay window for visual underlines (lazy initialization)
    lazy var errorOverlay: ErrorOverlayWindow = {
        let window = ErrorOverlayWindow()
        Logger.debug("AnalysisCoordinator: Error overlay window created", category: Logger.ui)
        return window
    }()

    /// Floating error indicator for apps without visual underlines
    let floatingIndicator: FloatingErrorIndicator

    // MARK: - Grammar Analysis Cache (internal for cross-file extension access)

    /// Error cache mapping text segments to detected errors
    var errorCache: [String: [GrammarErrorModel]] = [:]

    /// Cache metadata for LRU eviction
    var cacheMetadata: [String: CacheMetadata] = [:]

    /// AI rephrase suggestions cache - maps original sentence text to AI-generated rephrase
    /// This cache persists across app switches and re-analyses to avoid regenerating expensive LLM suggestions
    /// Thread-safe: AIRephraseCache handles synchronization internally
    nonisolated let aiRephraseCache = AIRephraseCache()

    /// Previous text for incremental analysis
    var previousText: String = ""

    // MARK: - Published State

    /// Currently displayed errors (internal visibility for extensions)
    @Published var currentErrors: [GrammarErrorModel] = []

    /// Current text segment being analyzed (internal visibility for extensions)
    @Published var currentSegment: TextSegment?

    /// Currently monitored application context
    var monitoredContext: ApplicationContext?

    /// Current browser URL (only populated when monitoring a browser)
    private var currentBrowserURL: URL?

    /// Analysis queue for background processing
    let analysisQueue = DispatchQueue(label: "com.textwarden.analysis", qos: .userInitiated)

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Maximum number of cached documents
    let maxCachedDocuments = 10

    /// Cache expiration time in seconds
    let cacheExpirationTime: TimeInterval = TimingConstants.analysisCacheExpiration

    // MARK: - Window Tracking State (internal for cross-file extension access)

    /// Window position and size tracking
    var lastWindowFrame: CGRect?
    var windowPositionTimer: Timer?
    var windowMovementDebounceTimer: Timer?
    var overlaysHiddenDueToMovement = false
    var overlaysHiddenDueToWindowOffScreen = false
    var positionSyncRetryCount = 0
    let maxPositionSyncRetries = 20  // Max 20 retries * 50ms = 1000ms max wait
    var lastElementPosition: CGPoint?  // Track element position for stability check
    var lastResizeTime: Date?  // Track when window was last resized (for Electron settling)
    var contentStabilityCount = 0  // Count consecutive stable position samples (for resize)
    var lastCharacterBounds: CGRect?  // Track actual character position to detect content reflow
    var lastElementFrame: CGRect?  // Track AXUIElement frame for text field resize detection (Mac Catalyst)

    /// Scroll detection - uses global scroll wheel event observer
    var overlaysHiddenDueToScroll = false
    var scrollDebounceTimer: Timer?
    /// Global scroll wheel event monitor
    var scrollWheelMonitor: Any?

    /// Hover switching timer - delays popover switching when hovering from one error to another
    var hoverSwitchTimer: Timer?
    /// Pending error waiting for delayed hover switch
    var pendingHoverError: (error: GrammarErrorModel, position: CGPoint, windowFrame: CGRect?)?

    /// Time when last suggestion was applied programmatically
    /// Used to suppress typing detection briefly after applying a suggestion
    /// (prevents paste-triggered AX notifications from hiding overlays)
    var lastReplacementTime: Date?

    /// Time when a conversation switch was detected in a Mac Catalyst chat app
    /// Used to prevent validateCurrentText() from racing with handleConversationSwitchInChatApp()
    var lastConversationSwitchTime: Date?

    /// Text validation timer for Mac Catalyst apps
    /// Periodically checks if source text has changed (since kAXValueChangedNotification is unreliable)
    var textValidationTimer: Timer?

    // MARK: - LLM Style Checking

    /// Currently displayed style suggestions from LLM analysis (internal visibility for extensions)
    @Published var currentStyleSuggestions: [StyleSuggestionModel] = []

    /// Style analysis queue for background LLM processing
    let styleAnalysisQueue = DispatchQueue(label: "com.textwarden.styleanalysis", qos: .userInitiated)

    /// Style cache - maps text hash to style suggestions (LLM results are expensive, cache aggressively)
    var styleCache: [String: [StyleSuggestionModel]] = [:]

    /// Style cache metadata for LRU eviction
    var styleCacheMetadata: [String: StyleCacheMetadata] = [:]

    /// Maximum cached style results
    let maxStyleCacheEntries = 20

    /// Style cache expiration time (longer than grammar since LLM is slower)
    let styleCacheExpirationTime: TimeInterval = TimingConstants.styleCacheExpiration

    /// Debounce timer for style analysis - prevents queue buildup during rapid typing
    var styleDebounceTimer: Timer?

    /// Debounce delay for style analysis (seconds) - wait for typing to pause
    let styleDebounceDelay: TimeInterval = TimingConstants.styleDebounce

    /// Generation ID for style analysis - incremented on each text change
    /// Used to detect and skip stale analysis (when text changed during LLM inference)
    var styleAnalysisGeneration: UInt64 = 0

    /// Whether LLM style checking should run for the current text
    private var shouldRunStyleChecking: Bool {
        userPreferences.enableStyleChecking && llmEngine.isReady
    }

    /// Flag to prevent regular analysis from hiding indicator during manual style check
    var isManualStyleCheckActive: Bool = false

    /// The full text content when current style suggestions were generated
    /// Used to invalidate suggestions when the underlying text changes
    var styleAnalysisSourceText: String = ""

    /// Flag to prevent text-change handler from clearing errors during replacement
    /// When true, text changes are expected (we're applying a suggestion) and should not trigger re-analysis
    var isApplyingReplacement: Bool = false

    /// Timestamp when replacement completed in an app with focus bounce behavior.
    /// Some apps (like Mail's WebKit) fire multiple AXFocusedUIElementChanged notifications
    /// during paste, causing the monitored element to temporarily become nil.
    /// During the grace period, we preserve the popover to avoid flicker.
    var replacementCompletedAt: Date?

    /// Grace period after replacement to preserve popover in apps with focus bounce behavior.
    /// Focus typically settles within 300-500ms after paste operation completes.
    let focusBounceGracePeriod: TimeInterval = TimingConstants.focusBounceGrace

    /// Check if we're within the focus bounce grace period after replacement
    func isWithinFocusBounceGracePeriod() -> Bool {
        guard let completedAt = replacementCompletedAt else { return false }
        return Date().timeIntervalSince(completedAt) < focusBounceGracePeriod
    }

    /// Last analyzed source text (for popover context display)
    var lastAnalyzedText: String = ""

    // MARK: - Initialization

    /// Initialize with default production dependencies
    private convenience init() {
        self.init(dependencies: .production)
    }

    /// Initialize with custom dependencies (for testing)
    /// - Parameter dependencies: Container with all dependencies
    init(dependencies: DependencyContainer) {
        self.textMonitor = dependencies.textMonitor
        self.applicationTracker = dependencies.applicationTracker
        self.permissionManager = dependencies.permissionManager
        self.grammarEngine = dependencies.grammarEngine
        self.llmEngine = dependencies.llmEngine
        self.userPreferences = dependencies.userPreferences
        self.appRegistry = dependencies.appRegistry
        self.customVocabulary = dependencies.customVocabulary
        self.browserURLExtractor = dependencies.browserURLExtractor
        self.positionResolver = dependencies.positionResolver
        self.statistics = dependencies.statistics
        self.suggestionPopover = dependencies.suggestionPopover
        self.floatingIndicator = dependencies.floatingIndicator

        setupMonitoring()
        setupPopoverCallbacks()
        setupOverlayCallbacks()
        setupScrollWheelMonitor()
        setupTypingCallback()
        // Window position monitoring will be started when we begin monitoring an app
    }

    // MARK: - Setup Methods

    /// Setup callback to hide underlines immediately when typing starts
    /// TypingDetector is notified for ALL apps, so this works for Slack, Notion, and other Electron apps
    private func setupTypingCallback() {
        TypingDetector.shared.onTypingStarted = { [weak self] in
            guard let self = self else { return }

            // Check if we're monitoring an app that requires typing pause
            guard let bundleID = self.textMonitor.currentContext?.bundleIdentifier else { return }
            let appConfig = self.appRegistry.configuration(for: bundleID)

            // Only act on keyboard events for apps that delay AX notifications (like Notion)
            // For apps like Slack that send immediate AX notifications, this callback won't fire
            // (filtered out in TypingDetector.handleKeyDown)
            if appConfig.features.delaysAXNotifications {
                // Skip if we just applied a suggestion programmatically
                // (prevents paste-triggered AX notifications from hiding overlays we just showed)
                if let lastReplacement = self.lastReplacementTime,
                   Date().timeIntervalSince(lastReplacement) < TimingConstants.replacementGracePeriod {
                    Logger.debug("AnalysisCoordinator: Ignoring typing callback - just applied suggestion", category: Logger.ui)
                    return
                }

                // Don't hide overlay - that causes flickering while typing
                // Just clear position cache so underlines update correctly after re-analysis
                Logger.trace("AnalysisCoordinator: Typing detected in \(appConfig.displayName) - clearing position cache", category: Logger.ui)
                self.positionResolver.clearCache()
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

    nonisolated deinit {
        // Note: Timer invalidation and event monitor removal are safe from deinit
        // because they don't access MainActor-isolated state
    }

    /// Clean up resources (timers, event monitors)
    /// Called during app termination for explicit cleanup since deinit won't be called for singletons
    func cleanup() {
        // Clean up event monitor
        if let monitor = scrollWheelMonitor {
            NSEvent.removeMonitor(monitor)
            scrollWheelMonitor = nil
        }

        // Invalidate all timers to prevent memory leaks
        windowPositionTimer?.invalidate()
        windowPositionTimer = nil
        windowMovementDebounceTimer?.invalidate()
        windowMovementDebounceTimer = nil
        scrollDebounceTimer?.invalidate()
        scrollDebounceTimer = nil
        hoverSwitchTimer?.invalidate()
        hoverSwitchTimer = nil
        textValidationTimer?.invalidate()
        textValidationTimer = nil
        styleDebounceTimer?.invalidate()
        styleDebounceTimer = nil
        electronLayoutTimer?.invalidate()
        electronLayoutTimer = nil

        // Clear pending state
        pendingHoverError = nil

        Logger.info("AnalysisCoordinator cleanup complete", category: Logger.lifecycle)
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

            DispatchQueue.main.async { [weak self] in
                self?.handleScrollStarted()
            }
        }
        Logger.debug("Scroll wheel monitor installed", category: Logger.analysis)
    }

    /// Setup popover callbacks
    private func setupPopoverCallbacks() {
        // Handle apply suggestion
        suggestionPopover.onApplySuggestion = { [weak self] error, suggestion in
            guard let self = self else { return }
            await self.applyTextReplacementAsync(for: error, with: suggestion)
        }

        // Handle dismiss error
        suggestionPopover.onDismissError = { [weak self] error in
            guard let self = self else { return }
            self.dismissError(error)
        }

        // Handle ignore rule
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

                // Schedule delayed switch
                self.hoverSwitchTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.hoverDelay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
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

    // MARK: - Monitoring Control

    /// Setup text monitoring and application tracking
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.mediumDelay) { [weak self] in
                        guard let self = self else { return }
                        if let element = self.textMonitor.monitoredElement {
                            Logger.debug("AnalysisCoordinator: Retry 1 - extracting text", category: Logger.analysis)
                            self.textMonitor.extractText(from: element)
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.hoverDelay) { [weak self] in
                        guard let self = self else { return }
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

        // Monitor text changes
        textMonitor.onTextChange = { [weak self] text, context in
            guard let self = self else { return }
            self.handleTextChange(text, in: context)
        }

        // Monitor IMMEDIATE text changes (before debounce)
        // Note: We no longer hide overlays here to avoid flickering during typing
        // Overlays will update naturally after the debounced re-analysis completes
        textMonitor.onImmediateTextChange = { [weak self] text, context in
            guard let self = self else { return }

            // Just clear the position cache so underlines update correctly after re-analysis
            // Don't hide overlays - that causes flickering while typing
            let appConfig = self.appRegistry.configuration(for: context.bundleIdentifier)
            if appConfig.features.requiresTypingPause {
                Logger.trace("AnalysisCoordinator: Immediate text change in \(context.applicationName) - clearing position cache", category: Logger.ui)
                self.positionResolver.clearCache()
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
            Logger.debug("AnalysisCoordinator: Global isEnabled: \(userPreferences.isEnabled)", category: Logger.analysis)
            Logger.debug("AnalysisCoordinator: Is in disabled apps? \(userPreferences.disabledApplications.contains(currentApp.bundleIdentifier))", category: Logger.analysis)
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
    func startMonitoring(context: ApplicationContext) {
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

    // MARK: - Debug Border Management

    /// Update debug borders based on current window position and visibility
    /// Called periodically to keep debug borders in sync with monitored window
    func updateDebugBorders() {
        guard let element = textMonitor.monitoredElement else {
            DebugBorderWindow.clearAll()
            return
        }

        // Check if any debug borders are enabled
        let showCGWindow = userPreferences.showDebugBorderCGWindowCoords
        let showCocoa = userPreferences.showDebugBorderCocoaCoords
        let showTextBounds = userPreferences.showDebugBorderTextFieldBounds

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
                if let best = bestWindow {
                    if area > best.area {
                        bestWindow = (cgFrame: cgFrame, cocoaFrame: cocoaFrame, area: area)
                    }
                } else {
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

    // MARK: - Text Analysis

    /// Handle text change and trigger analysis
    func handleTextChange(_ text: String, in context: ApplicationContext) {
        Logger.debug("AnalysisCoordinator: Text changed in \(context.applicationName) (\(text.count) chars)", category: Logger.analysis)

        // Don't process text changes during a conversation switch in Mac Catalyst apps
        if let switchTime = lastConversationSwitchTime,
           Date().timeIntervalSince(switchTime) < 0.6 {
            Logger.debug("AnalysisCoordinator: Ignoring text change - conversation switch in progress", category: Logger.analysis)
            return
        }

        let appConfig = appRegistry.configuration(for: context.bundleIdentifier)

        // Handle case when no element is being monitored (e.g., browser UI element)
        if textMonitor.monitoredElement == nil {
            if handleNoMonitoredElement(appConfig: appConfig) {
                return
            }
        }

        // We have a valid monitored element - show debug borders immediately
        updateDebugBorders()

        // Handle cache invalidation based on text changes
        let isInReplacementGracePeriod = lastReplacementTime.map { Date().timeIntervalSince($0) < TimingConstants.replacementGracePeriod } ?? false
        invalidateCachesForTextChange(
            text: text,
            context: context,
            appConfig: appConfig,
            isInReplacementGracePeriod: isInReplacementGracePeriod
        )

        // Restore cached content if applicable
        restoreCachedContent(text: text)

        // Create segment for analysis
        let segment = TextSegment(
            content: text,
            startIndex: 0,
            endIndex: text.count,
            context: context
        )
        currentSegment = segment

        // Perform analysis if enabled
        guard userPreferences.isEnabled else {
            Logger.debug("AnalysisCoordinator: Analysis disabled in preferences", category: Logger.analysis)
            return
        }

        // Check browser URL and skip if website is disabled
        if shouldSkipAnalysisForDisabledWebsite(context: context) {
            return
        }

        Logger.debug("AnalysisCoordinator: Calling analyzeText()", category: Logger.analysis)
        analyzeText(segment)
    }

    // MARK: - handleTextChange Helpers

    /// Check if we should preserve popover during focus bounces.
    /// Some apps (like Messages via Mac Catalyst) briefly lose focus during paste operations,
    /// which would otherwise cause the popover to hide incorrectly.
    private func shouldPreservePopoverDuringFocusBounce(appConfig: AppConfiguration) -> Bool {
        guard appConfig.features.focusBouncesDuringPaste else { return false }
        return isApplyingReplacement || isWithinFocusBounceGracePeriod()
    }

    /// Handle case when no monitored element exists (browser UI, etc.)
    /// Returns true if the caller should return early
    private func handleNoMonitoredElement(appConfig: AppConfiguration) -> Bool {
        if shouldPreservePopoverDuringFocusBounce(appConfig: appConfig) {
            Logger.debug("AnalysisCoordinator: Focus bounce app - preserving popover during replacement/grace period", category: Logger.analysis)
            errorOverlay.hide()
            previousText = ""
            return true
        }

        Logger.debug("AnalysisCoordinator: No monitored element - hiding overlays immediately", category: Logger.analysis)
        errorOverlay.hide()
        if !isManualStyleCheckActive {
            floatingIndicator.hide()
        }
        suggestionPopover.hide()
        DebugBorderWindow.clearAll()
        previousText = ""
        return true
    }

    /// Invalidate caches based on text changes
    private func invalidateCachesForTextChange(
        text: String,
        context: ApplicationContext,
        appConfig: AppConfiguration,
        isInReplacementGracePeriod: Bool
    ) {
        // Skip during active replacement
        if text != previousText && isApplyingReplacement {
            Logger.debug("AnalysisCoordinator: Text changed during replacement - skipping cache clear", category: Logger.analysis)
            return
        }

        guard text != previousText && !isApplyingReplacement && !isInReplacementGracePeriod else {
            return
        }

        let isTyping = detectTypingChange(newText: text, oldText: previousText)

        if text.isEmpty {
            // Text cleared (e.g., message sent)
            Logger.debug("AnalysisCoordinator: Text is now empty - clearing all errors", category: Logger.analysis)
            errorOverlay.hide()
            if !isManualStyleCheckActive { floatingIndicator.hide() }
            currentErrors.removeAll()
            positionResolver.clearCache()
        } else if !isTyping {
            // Significant change (e.g., switching chats)
            Logger.debug("AnalysisCoordinator: Text changed significantly - hiding overlays", category: Logger.analysis)
            errorOverlay.hide()
            if !isManualStyleCheckActive { floatingIndicator.hide() }
            positionResolver.clearCache()
        } else {
            // Normal typing - just clear position cache
            Logger.debug("AnalysisCoordinator: Typing detected - clearing position cache", category: Logger.analysis)
            positionResolver.clearCache()
        }

        // Electron/browser apps need full cache clear on significant changes
        if (appConfig.category == .electron || appConfig.category == .browser) && !isTyping {
            Logger.debug("AnalysisCoordinator: Electron/browser significant change - clearing errors", category: Logger.analysis)
            currentErrors.removeAll()
        }

        // Clear style suggestions if source text changed
        if !currentStyleSuggestions.isEmpty && text != styleAnalysisSourceText {
            Logger.debug("AnalysisCoordinator: Clearing style suggestions - source text changed", category: Logger.analysis)
            currentStyleSuggestions.removeAll()
            styleAnalysisSourceText = ""
            floatingIndicator.hide()
        }
    }

    /// Detect if text change is normal typing vs significant change
    private func detectTypingChange(newText: String, oldText: String) -> Bool {
        let lengthDelta = abs(newText.count - oldText.count)
        guard lengthDelta <= 5 else { return false }

        let oldPrefix = oldText.prefix(max(0, oldText.count - 5))
        let newPrefix = newText.prefix(max(0, newText.count - 5))
        let oldSuffix = oldText.suffix(max(0, oldText.count - 5))
        let newSuffix = newText.suffix(max(0, newText.count - 5))

        return newText.hasPrefix(oldPrefix) ||
               oldText.hasPrefix(newPrefix) ||
               newText.hasSuffix(oldSuffix) ||
               oldText.hasSuffix(newSuffix)
    }

    /// Restore cached errors and style suggestions
    private func restoreCachedContent(text: String) {
        // Restore cached errors
        if let cachedSegment = currentSegment,
           cachedSegment.content == text,
           !currentErrors.isEmpty,
           let element = textMonitor.monitoredElement {
            Logger.debug("AnalysisCoordinator: Restoring cached errors (\(currentErrors.count) errors)", category: Logger.analysis)
            showErrorUnderlines(currentErrors, element: element)
        }

        // Restore cached style suggestions
        guard currentStyleSuggestions.isEmpty,
              styleAnalysisSourceText.isEmpty || text == styleAnalysisSourceText else {
            return
        }

        let styleCacheKey = computeStyleCacheKey(text: text)
        guard let cachedStyleSuggestions = styleCache[styleCacheKey],
              !cachedStyleSuggestions.isEmpty else {
            return
        }

        Logger.debug("AnalysisCoordinator: Restoring cached style suggestions (\(cachedStyleSuggestions.count))", category: Logger.analysis)
        currentStyleSuggestions = cachedStyleSuggestions
        styleAnalysisSourceText = text

        let styleName = userPreferences.selectedWritingStyle
        styleCacheMetadata[styleCacheKey] = StyleCacheMetadata(
            lastAccessed: Date(),
            style: styleName
        )

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

    /// Check if analysis should be skipped for disabled website
    /// Returns true if analysis should be skipped
    private func shouldSkipAnalysisForDisabledWebsite(context: ApplicationContext) -> Bool {
        guard context.isBrowser else {
            currentBrowserURL = nil
            return false
        }

        currentBrowserURL = browserURLExtractor.extractURL(
            processID: context.processID,
            bundleIdentifier: context.bundleIdentifier
        )

        guard let url = currentBrowserURL else {
            Logger.debug("AnalysisCoordinator: Could not extract URL from browser", category: Logger.analysis)
            return false
        }

        Logger.debug("AnalysisCoordinator: Browser URL detected: \(url)", category: Logger.analysis)

        guard !userPreferences.isEnabled(forURL: url) else {
            return false
        }

        Logger.debug("AnalysisCoordinator: Website \(url.host ?? "unknown") is disabled - skipping", category: Logger.analysis)
        errorOverlay.hide()
        if !isManualStyleCheckActive { floatingIndicator.hide() }
        currentErrors = []
        return true
    }

    // Note: Grammar analysis methods (analyzeText, analyzeFullText, analyzeChangedPortion, etc.)
    // are implemented in AnalysisCoordinator+GrammarAnalysis.swift

    // Note: updateErrorCache is now implemented in the Performance Optimizations extension

    /// Deduplicate consecutive identical errors at the same position
    /// This prevents flooding the UI with 157 "Horizontal ellipsis" errors when they're all at the same spot
    /// But keeps separate errors for the same misspelling at different positions in the text
    private func deduplicateErrors(_ errors: [GrammarErrorModel]) -> [GrammarErrorModel] {
        guard !errors.isEmpty else { return errors }

        var deduplicated: [GrammarErrorModel] = []
        var currentGroup: [GrammarErrorModel] = [errors[0]]

        for i in 1..<errors.count {
            let current = errors[i]
            let previous = errors[i-1]

            // Check if this error is identical to the previous one AND at the same position
            // Errors at different positions should NOT be deduplicated (e.g., same typo twice)
            if current.message == previous.message &&
               current.category == previous.category &&
               current.lintId == previous.lintId &&
               current.start == previous.start &&
               current.end == previous.end {
                // Same error at same position - add to current group
                currentGroup.append(current)
            } else {
                // Different error or same error at different position - save one representative from the group
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

    /// Apply filters based on user preferences - internal for extension access
    func applyFilters(to errors: [GrammarErrorModel], sourceText: String, element: AXUIElement?) {
        Logger.debug("AnalysisCoordinator: applyFilters called with \(errors.count) errors", category: Logger.analysis)

        var filteredErrors = errors

        // Log error categories
        for error in errors {
            Logger.debug("  Error category: '\(error.category)', message: '\(error.message)'", category: Logger.analysis)
        }

        // Filter by category (e.g., Spelling, Grammar, Style)
        let enabledCategories = userPreferences.enabledCategories
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

        // Filter by dismissed rules
        let dismissedRules = userPreferences.ignoredRules
        filteredErrors = filteredErrors.filter { error in
            !dismissedRules.contains(error.lintId)
        }

        // Filter by custom vocabulary
        // Skip errors that contain words from the user's custom dictionary
        // Note: error.start/end are Unicode scalar indices from Harper
        let vocabulary = customVocabulary
        let sourceScalarCount = sourceText.unicodeScalars.count
        filteredErrors = filteredErrors.filter { error in
            // Extract error text from source using scalar indices
            guard error.start < sourceScalarCount, error.end <= sourceScalarCount, error.start < error.end,
                  let startIndex = scalarIndexToStringIndex(error.start, in: sourceText),
                  let endIndex = scalarIndexToStringIndex(error.end, in: sourceText) else {
                return true // Keep error if indices are invalid
            }

            let errorText = String(sourceText[startIndex..<endIndex])

            return !vocabulary.containsAnyWord(in: errorText)
        }

        // Filter by globally ignored error texts
        // Skip errors that match texts the user has chosen to ignore globally
        let ignoredTexts = userPreferences.ignoredErrorTexts
        filteredErrors = filteredErrors.filter { error in
            // Extract error text from source using scalar indices
            guard error.start < sourceScalarCount, error.end <= sourceScalarCount, error.start < error.end,
                  let startIndex = scalarIndexToStringIndex(error.start, in: sourceText),
                  let endIndex = scalarIndexToStringIndex(error.end, in: sourceText) else {
                return true // Keep error if indices are invalid
            }

            let errorText = String(sourceText[startIndex..<endIndex])

            return !ignoredTexts.contains(errorText)
        }

        // Filter out Notion-specific false positives
        // French spaces errors in Notion are often triggered by placeholder text artifacts
        // (e.g., "Write, press 'space' for AI" placeholder creates invisible whitespace patterns)
        if let context = monitoredContext,
           appRegistry.configuration(for: context.bundleIdentifier).parserType == .notion {
            filteredErrors = filteredErrors.filter { error in
                // Filter French spaces errors where the error text is just whitespace
                // These are false positives from Notion's placeholder handling
                if error.message.lowercased().contains("french spaces") {
                    guard error.start < sourceScalarCount, error.end <= sourceScalarCount, error.start < error.end,
                          let startIdx = scalarIndexToStringIndex(error.start, in: sourceText),
                          let endIdx = scalarIndexToStringIndex(error.end, in: sourceText) else {
                        return true
                    }
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

    /// Show visual underlines for errors - internal for extension access
    func showErrorUnderlines(_ errors: [GrammarErrorModel], element: AXUIElement?) {
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
        let appConfig = appRegistry.configuration(for: bundleID)
        if appConfig.category == .electron {
            // Cancel any pending layout timer
            electronLayoutTimer?.invalidate()

            // Delay showing underlines to let Electron's DOM stabilize
            electronLayoutTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.textSettleTime, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.showErrorUnderlinesInternal(errors, element: element)
                }
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

    // MARK: - Public API

    /// Errors for current text
    func errors() -> [GrammarErrorModel] {
        currentErrors
    }

    /// Current browser URL (nil if not in a browser or URL couldn't be extracted)
    func browserURL() -> URL? {
        currentBrowserURL
    }

    /// Current browser domain (e.g., "github.com")
    func browserDomain() -> String? {
        currentBrowserURL?.host?.lowercased()
    }

    /// Check if currently monitoring a browser
    func isMonitoringBrowser() -> Bool {
        monitoredContext?.isBrowser ?? false
    }

    /// Dismiss error for current session
    func dismissError(_ error: GrammarErrorModel) {
        // Record statistics
        statistics.recordSuggestionDismissed()

        // Extract error text and persist it globally
        // Note: error.start/end are Unicode scalar indices from Harper
        if let sourceText = currentSegment?.content {
            let scalarCount = sourceText.unicodeScalars.count
            guard error.start < scalarCount, error.end <= scalarCount, error.start < error.end,
                  let startIndex = scalarIndexToStringIndex(error.start, in: sourceText),
                  let endIndex = scalarIndexToStringIndex(error.end, in: sourceText) else {
                // Invalid indices, just remove from current errors
                currentErrors.removeAll { $0.start == error.start && $0.end == error.end }
                return
            }

            let errorText = String(sourceText[startIndex..<endIndex])

            // Persist this error text globally
            userPreferences.ignoreErrorText(errorText)
        }

        currentErrors.removeAll { $0.start == error.start && $0.end == error.end }

        // Re-filter to immediately remove any other occurrences
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
    }

    /// Ignore rule permanently
    func ignoreRulePermanently(_ ruleId: String) {
        userPreferences.ignoreRule(ruleId)

        // Re-filter current errors
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement)
    }

    /// Add word to custom dictionary
    func addToDictionary(_ error: GrammarErrorModel) {
        // Extract the error text
        // Note: error.start/end are Unicode scalar indices from Harper
        guard let sourceText = currentSegment?.content else { return }

        let scalarCount = sourceText.unicodeScalars.count
        guard error.start < scalarCount, error.end <= scalarCount, error.start < error.end,
              let startIndex = scalarIndexToStringIndex(error.start, in: sourceText),
              let endIndex = scalarIndexToStringIndex(error.end, in: sourceText) else {
            return
        }

        let errorText = String(sourceText[startIndex..<endIndex])

        do {
            try customVocabulary.addWord(errorText)
            Logger.info("Added '\(errorText)' to custom dictionary", category: Logger.analysis)

            // Record statistics
            statistics.recordWordAddedToDictionary()
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

}

// MARK: - Error Handling

extension AnalysisCoordinator {
    /// Priority error for overlapping range
    func priorityError(for range: Range<Int>) -> GrammarErrorModel? {
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

