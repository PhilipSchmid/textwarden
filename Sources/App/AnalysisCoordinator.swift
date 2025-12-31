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

    /// Content parser factory
    let contentParserFactory: ContentParserProviding

    /// Typing detector
    let typingDetector: TypingDetecting

    /// Text replacement coordinator
    let textReplacementCoordinator: TextReplacementCoordinating

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
    var sidebarToggleStartTime: Date?  // Track when sidebar toggle started (for timeout)

    /// Scroll detection - uses global scroll wheel event observer
    var overlaysHiddenDueToScroll = false
    var scrollDebounceTimer: Timer?
    /// Global scroll wheel event monitor
    var scrollWheelMonitor: Any?

    /// Coordinator for app-specific position refresh triggers (e.g., Slack click-based refresh)
    let positionRefreshCoordinator = PositionRefreshCoordinator()

    /// Hover switching timer - delays popover switching when hovering from one error to another
    var hoverSwitchTimer: Timer?
    /// Pending error waiting for delayed hover switch
    var pendingHoverError: (error: GrammarErrorModel, position: CGPoint, windowFrame: CGRect?)?

    /// Time when popover was last closed via click (used to debounce rapid click events)
    var lastClickCloseTime: Date?

    /// Time when last suggestion was applied programmatically
    /// Used to suppress typing detection briefly after applying a suggestion
    /// (prevents paste-triggered AX notifications from hiding overlays)
    var lastReplacementTime: Date? {
        didSet {
            // Keep thread-safe version in sync
            updateThreadSafeReplacementTime()
        }
    }

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

    /// Whether style checking should run for the current text
    private var shouldRunStyleChecking: Bool {
        userPreferences.enableStyleChecking
    }

    /// Flag to prevent regular analysis from hiding indicator during manual style check
    var isManualStyleCheckActive: Bool = false

    /// The full text content when current style suggestions were generated
    /// Used to invalidate suggestions when the underlying text changes
    var styleAnalysisSourceText: String = ""

    /// Tracks dismissed (accepted or rejected) style suggestions by original text hash
    /// Prevents the same suggestion from reappearing after re-analysis
    var dismissedStyleSuggestionHashes: Set<Int> = []

    /// Last time auto style check was triggered (for rate limiting)
    var lastAutoStyleCheckTime: Date?

    /// Text hash from last auto style check (to avoid re-checking unchanged text)
    var lastAutoStyleCheckTextHash: Int?

    /// Whether an auto style check is currently in progress
    var isAutoStyleCheckInProgress: Bool = false

    /// Minimum interval between auto style checks (seconds)
    let autoStyleCheckMinInterval: TimeInterval = 30.0

    /// Debounce delay for auto style check after grammar completes (seconds)
    let autoStyleCheckDebounceDelay: TimeInterval = 3.0

    /// Minimum text length for auto style checking (characters)
    let autoStyleCheckMinTextLength: Int = 50

    /// Flag to prevent text-change handler from clearing errors during replacement
    /// When true, text changes are expected (we're applying a suggestion) and should not trigger re-analysis
    var isApplyingReplacement: Bool = false

    /// Returns true if we're in the middle of a replacement OR within the grace period after
    /// Use this to prevent hiding underlines/clearing highlight during and immediately after replacement
    var isInReplacementMode: Bool {
        if isApplyingReplacement { return true }
        guard let lastTime = lastReplacementTime else { return false }
        return Date().timeIntervalSince(lastTime) < TimingConstants.replacementGracePeriod
    }

    // MARK: - Thread-Safe Replacement Mode Check

    /// Thread-safe storage for last replacement time (for non-MainActor access)
    private static let replacementTimeLock = NSLock()
    nonisolated(unsafe) private static var _threadSafeLastReplacementTime: Date?

    /// Thread-safe check if we're in replacement mode
    /// Can be called from any thread (e.g., from PositionResolver)
    nonisolated static var isInReplacementModeThreadSafe: Bool {
        replacementTimeLock.lock()
        defer { replacementTimeLock.unlock() }
        guard let lastTime = _threadSafeLastReplacementTime else { return false }
        return Date().timeIntervalSince(lastTime) < TimingConstants.replacementGracePeriod
    }

    /// Update the thread-safe replacement time to match the MainActor version
    private func updateThreadSafeReplacementTime() {
        Self.replacementTimeLock.lock()
        Self._threadSafeLastReplacementTime = lastReplacementTime
        Self.replacementTimeLock.unlock()
    }

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
        self.userPreferences = dependencies.userPreferences
        self.appRegistry = dependencies.appRegistry
        self.customVocabulary = dependencies.customVocabulary
        self.browserURLExtractor = dependencies.browserURLExtractor
        self.positionResolver = dependencies.positionResolver
        self.statistics = dependencies.statistics
        self.contentParserFactory = dependencies.contentParserFactory
        self.typingDetector = dependencies.typingDetector
        self.textReplacementCoordinator = dependencies.textReplacementCoordinator
        self.suggestionPopover = dependencies.suggestionPopover
        self.floatingIndicator = dependencies.floatingIndicator

        setupMonitoring()
        setupPopoverCallbacks()
        setupOverlayCallbacks()
        setupScrollWheelMonitor()
        setupPositionRefreshCoordinator()
        setupTypingCallback()
        setupIndicatorCallbacks()
        // Window position monitoring will be started when we begin monitoring an app
    }

    // MARK: - Setup Methods

    /// Setup callback to hide underlines immediately when typing starts
    /// TypingDetector is notified for ALL apps, so this works for Slack, Notion, and other Electron apps
    private func setupTypingCallback() {
        typingDetector.onTypingStarted = { [weak self] in
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
        typingDetector.onTypingStopped = { [weak self] in
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

    /// Setup callbacks for the floating indicator
    private func setupIndicatorCallbacks() {
        // Handle click on style section when no suggestions exist - trigger style check
        floatingIndicator.onRequestStyleCheck = { [weak self] in
            guard let self = self else { return }
            Logger.debug("AnalysisCoordinator: Style check requested from capsule click", category: Logger.analysis)
            self.runManualStyleCheck()
        }

        // Handle request for generation context
        floatingIndicator.onRequestGenerationContext = { [weak self] in
            guard let self = self else { return .empty }
            return self.extractGenerationContext()
        }

        // Setup text generation popover callbacks
        setupTextGenerationCallbacks()
    }

    /// Setup callbacks for text generation popover
    private func setupTextGenerationCallbacks() {
        // Handle text generation request
        TextGenerationPopover.shared.onGenerate = { [weak self] instruction, style, context, variationSeed in
            guard let self = self else {
                throw FoundationModelsError.analysisError("Coordinator not available")
            }

            let seedInfo = variationSeed.map { " (retry seed: \($0))" } ?? ""
            Logger.debug("AnalysisCoordinator: Text generation requested - instruction: '\(instruction.prefix(30))...'\(seedInfo)", category: Logger.analysis)

            if #available(macOS 26.0, *) {
                // Create engine on demand
                let fmEngine = FoundationModelsEngine()
                fmEngine.checkAvailability()

                guard fmEngine.status.isAvailable else {
                    throw FoundationModelsError.notAvailable(fmEngine.status)
                }

                return try await fmEngine.generateText(
                    instruction: instruction,
                    context: context,
                    style: style,
                    variationSeed: variationSeed
                )
            } else {
                throw FoundationModelsError.analysisError("Text generation requires macOS 26 or later")
            }
        }

        // Handle text insertion from AI Compose
        TextGenerationPopover.shared.onInsertText = { [weak self] text in
            guard let self = self,
                  let element = self.textMonitor.monitoredElement else { return }

            Logger.debug("AnalysisCoordinator: Inserting generated text (\(text.count) chars)", category: Logger.analysis)

            // Use app-specific text replacement strategies
            Task { @MainActor in
                await self.insertGeneratedTextAsync(text, element: element)
            }
        }
    }

    /// Insert generated text at cursor or replace selection using app-specific strategies
    /// This reuses the same infrastructure as grammar/style corrections
    @MainActor
    private func insertGeneratedTextAsync(_ text: String, element: AXUIElement) async {
        guard let context = monitoredContext else {
            Logger.warning("AnalysisCoordinator: No context for text insertion", category: Logger.analysis)
            return
        }

        let appConfig = appRegistry.configuration(for: context.bundleIdentifier)

        // Check app type for strategy selection
        let isElectronApp = context.requiresKeyboardReplacement
        let isBrowser = context.isBrowser
        let isMacCatalyst = context.isMacCatalystApp
        let usesBrowserStyleReplacement = appConfig.features.textReplacementMethod == .browserStyle

        // For native macOS apps, try AX API first (it's faster and preserves formatting)
        if !isElectronApp && !isBrowser && !isMacCatalyst && !usesBrowserStyleReplacement {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )

            if result == .success {
                Logger.debug("AnalysisCoordinator: Inserted text via AX API", category: Logger.analysis)
                return
            }
            Logger.debug("AnalysisCoordinator: AX API insert failed (\(result.rawValue)), using clipboard method", category: Logger.analysis)
        }

        // For Electron apps, browsers, Catalyst apps, and apps requiring browser-style replacement:
        // Use clipboard paste with proper activation
        await insertViaClipboardAsync(text, context: context, isMacCatalyst: isMacCatalyst)
    }

    /// Insert text via clipboard paste with proper app activation (async version)
    @MainActor
    private func insertViaClipboardAsync(_ text: String, context: ApplicationContext, isMacCatalyst: Bool) async {
        Logger.debug("AnalysisCoordinator: Inserting via clipboard for \(context.applicationName)", category: Logger.analysis)

        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount

        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Activate target app so paste goes to the right window
        if let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier).first {
            targetApp.activate()
        }

        // Wait for activation
        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.longDelay * 1_000_000_000))

        // Mac Catalyst: use direct keyboard typing (clipboard paste is unreliable)
        if isMacCatalyst {
            Logger.debug("AnalysisCoordinator: Using direct typing for Mac Catalyst", category: Logger.analysis)
            typeTextDirectly(text)

            // Restore clipboard
            if let previous = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }

            let typingDelay = Double(text.count) * 0.01 + 0.1
            try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))
            return
        }

        // Try menu paste first (more reliable for some apps)
        var pasteSucceeded = false
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
            if let pasteMenuItem = findPasteMenuItem(in: appElement) {
                if AXUIElementPerformAction(pasteMenuItem, kAXPressAction as CFString) == .success {
                    pasteSucceeded = true
                    Logger.debug("AnalysisCoordinator: Pasted via menu action", category: Logger.analysis)
                }
            }
        }

        // Keyboard fallback if menu failed
        if !pasteSucceeded {
            let delay = context.keyboardOperationDelay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
            Logger.debug("AnalysisCoordinator: Pasted via Cmd+V", category: Logger.analysis)
        }

        // Wait for paste to complete
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // Restore clipboard if unchanged by user
        if pasteboard.changeCount == originalChangeCount + 1 {
            if let previous = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        Logger.debug("AnalysisCoordinator: Text insertion complete", category: Logger.analysis)
    }

    nonisolated deinit {
        // Note: Timer invalidation and event monitor removal are safe from deinit
        // because they don't access MainActor-isolated state
    }

    /// Clean up resources (timers, event monitors)
    /// Called during app termination for explicit cleanup since deinit won't be called for singletons
    func cleanup() {
        // Clean up event monitors
        if let monitor = scrollWheelMonitor {
            NSEvent.removeMonitor(monitor)
            scrollWheelMonitor = nil
        }
        positionRefreshCoordinator.stopMonitoring()

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

    /// Setup position refresh coordinator for app-specific refresh triggers
    private func setupPositionRefreshCoordinator() {
        positionRefreshCoordinator.delegate = self
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

        // Handle regenerate style suggestion - get alternative suggestion
        if #available(macOS 26.0, *) {
            suggestionPopover.onRegenerateStyleSuggestion = { [weak self] suggestion in
                guard let self = self else { return nil }
                return await self.regenerateStyleSuggestion(suggestion)
            }
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

        // Handle popover hidden - clear locked highlight
        suggestionPopover.onPopoverHidden = { [weak self] in
            self?.errorOverlay.setLockedHighlight(for: nil)
        }

        // Handle current error changed - update locked highlight
        suggestionPopover.onCurrentErrorChanged = { [weak self] error in
            self?.errorOverlay.setLockedHighlight(for: error)
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
                // Different error - switch immediately for snappy UX
                Logger.debug("AnalysisCoordinator: Different error - switching immediately", category: Logger.analysis)
                self.hoverSwitchTimer?.invalidate()
                self.hoverSwitchTimer = nil
                self.pendingHoverError = nil
                self.suggestionPopover.show(
                    error: error,
                    allErrors: self.currentErrors,
                    at: position,
                    constrainToWindow: windowFrame
                )
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

            // Schedule popover hide with delay - if user moves into popover, it will cancel
            SuggestionPopover.shared.scheduleHide()
        }

        // Handle click on underline - toggle popover (show if hidden, hide if showing same error)
        errorOverlay.onErrorClick = { [weak self] error, position, windowFrame in
            guard let self = self else { return }

            Logger.debug("AnalysisCoordinator: onErrorClick - error at \(error.start)-\(error.end)", category: Logger.analysis)

            // Debounce: ignore click if popover was just hidden by its own click-outside handler
            // This prevents the race condition where both monitors receive the same click event
            if let lastClose = self.suggestionPopover.lastClickOutsideHideTime,
               Date().timeIntervalSince(lastClose) < 0.3 {
                Logger.debug("AnalysisCoordinator: Ignoring click - popover just closed by click outside", category: Logger.analysis)
                return
            }

            // Check if popover is showing the same error - if so, hide it (toggle behavior)
            if self.suggestionPopover.isVisible && self.isSameError(error, as: self.suggestionPopover.currentError) {
                Logger.debug("AnalysisCoordinator: Click on same error - hiding popover (toggle)", category: Logger.analysis)
                self.lastClickCloseTime = Date()
                self.suggestionPopover.hide()
                self.errorOverlay.setLockedHighlight(for: nil)
            } else {
                // Different error or popover not showing - show this error
                Logger.debug("AnalysisCoordinator: Click - showing popover for error", category: Logger.analysis)
                self.suggestionPopover.show(
                    error: error,
                    allErrors: self.currentErrors,
                    at: position,
                    constrainToWindow: windowFrame
                )
                // Lock highlight on clicked error
                self.errorOverlay.setLockedHighlight(for: error)
            }
        }

        // Re-show underlines when frame stabilizes after resize
        errorOverlay.onFrameStabilized = { [weak self] in
            guard let self = self else { return }
            Logger.debug("AnalysisCoordinator: Frame stabilized - clearing position cache and re-showing underlines", category: Logger.ui)
            // Clear position cache to force fresh position calculations
            self.positionResolver.clearCache()
            // Re-show cached errors at new positions
            if !self.currentErrors.isEmpty,
               let element = self.textMonitor.monitoredElement {
                self.showErrorUnderlines(self.currentErrors, element: element)
            }
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

                        // Mac Catalyst apps need extra time for accessibility to stabilize
                        if context.isMacCatalystApp {
                            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.catalystAccessibilityDelay) { [weak self] in
                                guard let self = self else { return }
                                self.previousText = ""
                                if let el = self.textMonitor.monitoredElement {
                                    Logger.debug("AnalysisCoordinator: Same app Catalyst retry - forcing re-analysis", category: Logger.analysis)
                                    self.textMonitor.extractText(from: el)
                                }
                            }
                        }
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

                    // Mac Catalyst apps (Messages, WhatsApp) need extra time for accessibility hierarchy
                    // to fully stabilize after focus change. Add a longer retry to catch late updates.
                    if context.isMacCatalystApp {
                        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.catalystAccessibilityDelay) { [weak self] in
                            guard let self = self else { return }
                            // Force re-analysis by clearing previousText
                            self.previousText = ""
                            if let element = self.textMonitor.monitoredElement {
                                Logger.debug("AnalysisCoordinator: Catalyst retry 3 - forcing re-analysis", category: Logger.analysis)
                                self.textMonitor.extractText(from: element)
                            }
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

        // Monitor global pause state changes - hide overlays when paused, re-analyze when resumed
        UserPreferences.shared.$pauseDuration
            .dropFirst() // Skip initial value to avoid hiding on launch
            .sink { [weak self] duration in
                guard let self = self else { return }
                if duration != .active {
                    Logger.info("AnalysisCoordinator: Global pause activated (\(duration.rawValue)) - hiding overlays", category: Logger.analysis)
                    self.hideAllOverlays()
                    self.suggestionPopover.hide()
                    self.floatingIndicator.hide()
                } else {
                    // Resumed - trigger re-analysis to show errors again
                    Logger.info("AnalysisCoordinator: Global pause deactivated - triggering re-analysis", category: Logger.analysis)
                    self.triggerReanalysis()
                }
            }
            .store(in: &cancellables)

        // Monitor app-specific pause state changes - hide overlays if current app is paused
        // Track previous pause states to detect resume (key removal = resume)
        var previousAppPauses: [String: PauseDuration] = UserPreferences.shared.appPauseDurations
        UserPreferences.shared.$appPauseDurations
            .dropFirst() // Skip initial value
            .sink { [weak self] pauseDurations in
                guard let self = self,
                      let currentBundleID = self.monitoredContext?.bundleIdentifier else {
                    previousAppPauses = pauseDurations
                    return
                }

                let wasCurrentAppPaused = previousAppPauses[currentBundleID] != nil
                let isCurrentAppNowPaused = pauseDurations[currentBundleID] != nil

                if let appPause = pauseDurations[currentBundleID], appPause != .active {
                    // App is now paused
                    Logger.info("AnalysisCoordinator: App-specific pause activated for \(currentBundleID) (\(appPause.rawValue)) - hiding overlays", category: Logger.analysis)
                    self.hideAllOverlays()
                    self.suggestionPopover.hide()
                    self.floatingIndicator.hide()
                } else if wasCurrentAppPaused && !isCurrentAppNowPaused {
                    // App was paused, but key was removed (means it's now active)
                    Logger.info("AnalysisCoordinator: App-specific pause deactivated for \(currentBundleID) - triggering re-analysis", category: Logger.analysis)
                    self.triggerReanalysis()
                }

                previousAppPauses = pauseDurations
            }
            .store(in: &cancellables)

        // Monitor disabled applications - hide overlays if current app is disabled
        UserPreferences.shared.$disabledApplications
            .dropFirst() // Skip initial value
            .sink { [weak self] disabledApps in
                guard let self = self,
                      let currentBundleID = self.monitoredContext?.bundleIdentifier else { return }
                // Check if the currently monitored app was just disabled
                if disabledApps.contains(currentBundleID) {
                    Logger.info("AnalysisCoordinator: App disabled for \(currentBundleID) - hiding overlays and stopping monitoring", category: Logger.analysis)
                    self.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        // Monitor style checking toggle - clear cache when disabled
        UserPreferences.shared.$enableStyleChecking
            .dropFirst() // Skip initial value
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if !enabled {
                    Logger.info("AnalysisCoordinator: Style checking disabled - clearing style cache and suggestions", category: Logger.analysis)
                    self.clearStyleCache()
                    self.currentStyleSuggestions = []
                    // Update indicator to hide style section
                    if let element = self.textMonitor.monitoredElement,
                       let context = self.monitoredContext {
                        self.floatingIndicator.update(
                            errors: self.currentErrors,
                            styleSuggestions: [],
                            element: element,
                            context: context,
                            sourceText: self.lastAnalyzedText
                        )
                    }
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
        typingDetector.currentBundleID = context.bundleIdentifier

        Logger.debug("AnalysisCoordinator: Permission granted, calling textMonitor.startMonitoring", category: Logger.analysis)
        textMonitor.startMonitoring(
            processID: context.processID,
            bundleIdentifier: context.bundleIdentifier,
            appName: context.applicationName
        )
        Logger.debug("AnalysisCoordinator: textMonitor.startMonitoring completed", category: Logger.analysis)

        // Start position refresh coordinator for apps that need click-based position updates
        positionRefreshCoordinator.startMonitoring(bundleID: context.bundleIdentifier)

        // Start window position monitoring now that we have an element to monitor
        startWindowPositionMonitoring()

        // Start clipboard monitoring for Slack to detect when user copies text with formatting
        // This allows us to extract Quill Delta data for exclusion detection (mentions, channels, code, etc.)
        let appConfig = appRegistry.configuration(for: context.bundleIdentifier)
        if appConfig.parserType == .slack {
            Logger.info("AnalysisCoordinator: Starting Slack clipboard monitoring", category: Logger.analysis)
            if let slackParser = contentParserFactory.parser(for: context.bundleIdentifier) as? SlackContentParser {
                // Log current clipboard contents for debugging
                slackParser.logClipboardContents()
                // Start continuous clipboard monitoring to detect when user copies
                // This captures Quill Delta data containing mentions, channels, etc.
                slackParser.startClipboardMonitoring(for: "")

                // Verify our Pickle format is correct (one-time on startup)
                let roundtripOK = slackParser.verifyPickleRoundtrip()
                Logger.info("AnalysisCoordinator: Slack Pickle roundtrip test: \(roundtripOK ? "PASSED" : "FAILED")", category: Logger.analysis)
            }
        }
    }

    /// Stop monitoring
    private func stopMonitoring() {
        textMonitor.stopMonitoring()
        currentErrors = []
        currentSegment = nil
        previousText = ""  // Clear previous text so analysis runs when we return

        // Clear typing detector state
        typingDetector.currentBundleID = nil
        typingDetector.reset()

        // Reset Slack parser state (clipboard monitoring, exclusion cache)
        if let context = monitoredContext,
           let slackParser = contentParserFactory.parser(for: context.bundleIdentifier) as? SlackContentParser {
            slackParser.resetState()
        }

        // Only clear style state if not in a manual style check
        // During manual style check, preserve results so user sees them when returning
        if !isManualStyleCheckActive {
            currentStyleSuggestions = []  // Clear style suggestions
            dismissedStyleSuggestionHashes.removeAll()  // Reset dismissed tracking for new context
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

    // MARK: - Public Control Methods

    /// Hide all visual overlays (error underlines, indicator, popover)
    /// Used when disabling grammar checking via keyboard shortcut
    func hideAllOverlays() {
        errorOverlay.hide()
        DebugBorderWindow.clearAll()
        positionResolver.clearCache()
        currentErrors.removeAll()
        currentStyleSuggestions.removeAll()
        Logger.debug("AnalysisCoordinator: hideAllOverlays - cleared all visual feedback", category: Logger.ui)
    }

    /// Trigger re-analysis of current text to show errors immediately
    /// Used when enabling grammar checking via keyboard shortcut
    func triggerReanalysis() {
        guard let element = textMonitor.monitoredElement else {
            Logger.debug("AnalysisCoordinator: triggerReanalysis - no monitored element", category: Logger.analysis)
            return
        }

        // Clear previousText to force re-analysis even if text hasn't changed
        // This mirrors the behavior when returning to an app after switching away
        previousText = ""

        Logger.debug("AnalysisCoordinator: triggerReanalysis - extracting text for analysis", category: Logger.analysis)
        textMonitor.extractText(from: element)
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
    /// - Parameter isFromReplacementUI: If true, this call is from `removeErrorAndUpdateUI` and should not be skipped during replacement mode
    func applyFilters(to errors: [GrammarErrorModel], sourceText: String, element: AXUIElement?, isFromReplacementUI: Bool = false) {
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

        // Filter by custom vocabulary and macOS system dictionary
        // Skip errors that contain words from the user's custom dictionary or macOS learned words
        // Note: error.start/end are Unicode scalar indices from Harper
        let vocabulary = customVocabulary
        let useMacOSDictionary = userPreferences.enableMacOSDictionary
        let sourceScalarCount = sourceText.unicodeScalars.count
        filteredErrors = filteredErrors.filter { error in
            // Extract error text from source using scalar indices
            guard error.start < sourceScalarCount, error.end <= sourceScalarCount, error.start < error.end,
                  let startIndex = TextIndexConverter.scalarIndexToStringIndex(error.start, in: sourceText),
                  let endIndex = TextIndexConverter.scalarIndexToStringIndex(error.end, in: sourceText) else {
                return true // Keep error if indices are invalid
            }

            let errorText = String(sourceText[startIndex..<endIndex])

            // Check custom vocabulary
            if vocabulary.containsAnyWord(in: errorText) {
                return false
            }

            // Check macOS system dictionary if enabled
            if useMacOSDictionary && MacOSDictionary.shared.containsAnyWord(in: errorText) {
                return false
            }

            return true
        }

        // Filter by globally ignored error texts
        // Skip errors that match texts the user has chosen to ignore globally
        let ignoredTexts = userPreferences.ignoredErrorTexts
        filteredErrors = filteredErrors.filter { error in
            // Extract error text from source using scalar indices
            guard error.start < sourceScalarCount, error.end <= sourceScalarCount, error.start < error.end,
                  let startIndex = TextIndexConverter.scalarIndexToStringIndex(error.start, in: sourceText),
                  let endIndex = TextIndexConverter.scalarIndexToStringIndex(error.end, in: sourceText) else {
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
                          let startIdx = TextIndexConverter.scalarIndexToStringIndex(error.start, in: sourceText),
                          let endIdx = TextIndexConverter.scalarIndexToStringIndex(error.end, in: sourceText) else {
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

        // Filter out general exclusions (list markers) for all apps
        let listMarkerExclusions = TextPreprocessor.excludeListMarkers(from: sourceText)
        if !listMarkerExclusions.isEmpty {
            let beforeCount = filteredErrors.count
            filteredErrors = filteredErrors.filter { error in
                let errorRange = error.start..<error.end
                for exclusion in listMarkerExclusions {
                    if exclusion.overlaps(errorRange) {
                        return false
                    }
                }
                return true
            }
            let filteredCount = beforeCount - filteredErrors.count
            if filteredCount > 0 {
                Logger.debug("AnalysisCoordinator: Filtered \(filteredCount) errors in list markers", category: Logger.analysis)
            }
        }

        // Filter out exclusions for Slack and Teams (code blocks, blockquotes, links, mentions)
        // Both are Chromium-based and use AX attribute detection for formatted content
        if let context = monitoredContext,
           let axElement = element {
            let parserType = appRegistry.configuration(for: context.bundleIdentifier).parserType
            var exclusions: [ExclusionRange] = []

            // Slack exclusions
            if parserType == .slack,
               let slackParser = contentParserFactory.parser(for: context.bundleIdentifier) as? SlackContentParser {
                exclusions = slackParser.extractExclusions(from: axElement, text: sourceText)
            }
            // Teams exclusions
            else if parserType == .teams,
                    let teamsParser = contentParserFactory.parser(for: context.bundleIdentifier) as? TeamsContentParser {
                exclusions = teamsParser.extractExclusions(from: axElement, text: sourceText)
            }

            if !exclusions.isEmpty {
                let beforeCount = filteredErrors.count
                filteredErrors = filteredErrors.filter { error in
                    let errorRange = error.start..<error.end
                    // Check if error overlaps with any exclusion range
                    for exclusion in exclusions {
                        if exclusion.overlaps(errorRange) {
                            return false
                        }
                    }
                    return true
                }
                let filteredCount = beforeCount - filteredErrors.count
                if filteredCount > 0 {
                    Logger.info("AnalysisCoordinator: Filtered \(filteredCount) errors in \(parserType == .slack ? "Slack" : "Teams") exclusion zones", category: Logger.analysis)
                }
            }
        }

        // During replacement mode, skip updating currentErrors from re-analysis
        // because re-analysis has stale data (positions before adjustment).
        // Only allow updates from removeErrorAndUpdateUI which has correct adjusted positions.
        if isInReplacementMode && !isFromReplacementUI {
            Logger.debug("AnalysisCoordinator: Skipping currentErrors update during replacement mode (from re-analysis)", category: Logger.analysis)
            return
        }

        currentErrors = filteredErrors

        showErrorUnderlines(filteredErrors, element: element, isFromReplacementUI: isFromReplacementUI)

        // Sync the popover's error and style suggestion lists with the canonical lists
        // This ensures the popover shows the correct counts after re-analysis
        suggestionPopover.syncErrors(filteredErrors, styleSuggestions: currentStyleSuggestions)
    }

    /// Timer for Electron layout stabilization delay
    private var electronLayoutTimer: Timer?

    /// Show visual underlines for errors - internal for extension access
    /// - Parameter isFromReplacementUI: If true, this call is from `removeErrorAndUpdateUI` and should not be skipped during replacement mode
    func showErrorUnderlines(_ errors: [GrammarErrorModel], element: AXUIElement?, isFromReplacementUI: Bool = false) {
        Logger.debug("AnalysisCoordinator: showErrorUnderlines called with \(errors.count) errors, isFromReplacementUI: \(isFromReplacementUI)", category: Logger.analysis)

        // During replacement mode, skip calls from re-analysis (async completion with stale data)
        // Only allow calls from removeErrorAndUpdateUI which has the correct updated error list
        if isInReplacementMode && !isFromReplacementUI {
            Logger.debug("AnalysisCoordinator: Skipping showErrorUnderlines during replacement mode (from re-analysis)", category: Logger.analysis)
            return
        }

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
                  let startIndex = TextIndexConverter.scalarIndexToStringIndex(error.start, in: sourceText),
                  let endIndex = TextIndexConverter.scalarIndexToStringIndex(error.end, in: sourceText) else {
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
              let startIndex = TextIndexConverter.scalarIndexToStringIndex(error.start, in: sourceText),
              let endIndex = TextIndexConverter.scalarIndexToStringIndex(error.end, in: sourceText) else {
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

// MARK: - PositionRefreshDelegate

extension AnalysisCoordinator: PositionRefreshDelegate {
    /// Called when positions should be recalculated (e.g., after click in Slack)
    func positionRefreshRequested() {
        guard let element = textMonitor.monitoredElement,
              !currentErrors.isEmpty else { return }

        Logger.debug("AnalysisCoordinator: Position refresh requested - clearing cache", category: Logger.ui)

        // Clear position cache to force fresh position calculations
        positionResolver.clearCache()

        // Re-show underlines at new positions
        showErrorUnderlines(currentErrors, element: element)
    }

    /// Called when underlines should be hidden temporarily (e.g., during scroll)
    func hideUnderlinesRequested() {
        Logger.debug("AnalysisCoordinator: Hide underlines requested (scroll)", category: Logger.ui)

        // Hide the overlay (clears underlines)
        errorOverlay.hide()

        // Clear position cache since positions are now stale
        positionResolver.clearCache()
    }
}

