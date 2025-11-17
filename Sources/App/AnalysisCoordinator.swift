//
//  AnalysisCoordinator.swift
//  Gnau
//
//  Orchestrates text monitoring, grammar analysis, and UI presentation
//

import Foundation
import AppKit
import ApplicationServices
import Combine

/// Debug file logging
func logToDebugFile(_ message: String) {
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

    /// Floating error indicator (Grammarly-style) for apps without visual underlines
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
    private let analysisQueue = DispatchQueue(label: "com.gnau.analysis", qos: .userInitiated)

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Maximum number of cached documents (T085)
    private let maxCachedDocuments = 10

    /// Cache expiration time in seconds (T084)
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes

    private init() {
        setupMonitoring()
        setupPopoverCallbacks()
        setupOverlayCallbacks()
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
    }

    /// Setup overlay callbacks for hover-based popup
    private func setupOverlayCallbacks() {
        // Show popup when hovering over error underline
        errorOverlay.onErrorHover = { [weak self] error, position in
            guard let self = self else { return }
            // Cancel any pending hide when showing new error
            self.suggestionPopover.cancelHide()
            self.suggestionPopover.show(
                error: error,
                allErrors: self.currentErrors,
                at: position
            )
        }

        // Don't schedule hide when hover ends - let the popover's own mouse tracking handle it
        // This allows users to freely move between the underline and popover without triggering hide
        errorOverlay.onHoverEnd = { [weak self] in
            guard let self = self else { return }
            // Don't call scheduleHide() here - the popover will hide when mouse leaves IT, not the underline
            print("📍 AnalysisCoordinator: Hover ended on underline (not scheduling hide)")
        }
    }

    /// Setup text monitoring and application tracking (T037)
    private func setupMonitoring() {
        print("📍 AnalysisCoordinator: Setting up monitoring...")

        // Monitor application changes
        applicationTracker.onApplicationChange = { [weak self] context in
            guard let self = self else { return }
            print("📱 AnalysisCoordinator: Application changed to \(context.applicationName) (\(context.bundleIdentifier))")

            // Check if this is the same app we're already monitoring
            let isSameApp = self.monitoredContext?.bundleIdentifier == context.bundleIdentifier

            // Hide overlay and popover from previous application
            self.errorOverlay.hide()
            self.suggestionPopover.hide()

            // Start monitoring new application if enabled
            if context.shouldCheck() {
                if isSameApp {
                    print("🔄 AnalysisCoordinator: Returning to same app - forcing re-analysis")
                    // CRITICAL: Set context even for same app (might have been cleared when switching away)
                    self.monitoredContext = context
                    // Same app - but we might have missed an intermediate app switch (e.g., Gnau's menu bar)
                    // Force re-analysis by temporarily clearing previousText
                    let savedPreviousText = self.previousText
                    self.previousText = ""

                    if let element = self.textMonitor.monitoredElement {
                        self.textMonitor.extractText(from: element)
                    }

                    // Restore previousText after extraction to prevent unnecessary re-analysis on next edit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.previousText.isEmpty {
                            self.previousText = savedPreviousText
                        }
                    }
                } else {
                    print("✅ AnalysisCoordinator: New application - starting monitoring")
                    self.monitoredContext = context  // Set BEFORE startMonitoring
                    self.startMonitoring(context: context)

                    // Trigger re-analysis after monitoring is established
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let element = self.textMonitor.monitoredElement {
                            print("🔄 AnalysisCoordinator: Re-extracting text after new app monitoring established")
                            self.textMonitor.extractText(from: element)
                        } else {
                            print("⚠️ AnalysisCoordinator: No monitored element found after app switch")
                        }
                    }
                }
            } else {
                print("⏸️ AnalysisCoordinator: Application not in check list - stopping monitoring")
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
            let logMsg1 = "📱 AnalysisCoordinator: Found existing active application: \(currentApp.applicationName) (\(currentApp.bundleIdentifier))"
            let logMsg2 = "📊 AnalysisCoordinator: Should check? \(currentApp.shouldCheck())"
            let logMsg3 = "📊 AnalysisCoordinator: Context isEnabled: \(currentApp.isEnabled)"
            let logMsg4 = "📊 AnalysisCoordinator: Global isEnabled: \(UserPreferences.shared.isEnabled)"
            let logMsg5 = "📊 AnalysisCoordinator: Is in disabled apps? \(UserPreferences.shared.disabledApplications.contains(currentApp.bundleIdentifier))"
            NSLog(logMsg1)
            NSLog(logMsg2)
            NSLog(logMsg3)
            NSLog(logMsg4)
            NSLog(logMsg5)
            logToDebugFile(logMsg1)
            logToDebugFile(logMsg2)
            logToDebugFile(logMsg3)
            logToDebugFile(logMsg4)
            logToDebugFile(logMsg5)
            if currentApp.shouldCheck() {
                let msg = "✅ AnalysisCoordinator: Starting monitoring for existing app"
                NSLog(msg)
                logToDebugFile(msg)
                self.monitoredContext = currentApp  // Set BEFORE startMonitoring
                startMonitoring(context: currentApp)
            } else {
                let msg = "⏸️ AnalysisCoordinator: Existing app not in check list"
                NSLog(msg)
                logToDebugFile(msg)
            }
        } else {
            let msg = "⚠️ AnalysisCoordinator: No active application detected yet"
            NSLog(msg)
            logToDebugFile(msg)
        }
    }

    /// Start monitoring a specific application
    private func startMonitoring(context: ApplicationContext) {
        let msg1 = "🎯 AnalysisCoordinator: startMonitoring called for \(context.applicationName)"
        NSLog(msg1)
        logToDebugFile(msg1)
        guard permissionManager.isPermissionGranted else {
            let msg = "❌ AnalysisCoordinator: Accessibility permissions not granted"
            NSLog(msg)
            logToDebugFile(msg)
            return
        }

        let msg2 = "✅ AnalysisCoordinator: Permission granted, calling textMonitor.startMonitoring"
        NSLog(msg2)
        logToDebugFile(msg2)
        textMonitor.startMonitoring(
            processID: context.processID,
            bundleIdentifier: context.bundleIdentifier,
            appName: context.applicationName
        )
        let msg3 = "✅ AnalysisCoordinator: textMonitor.startMonitoring completed"
        NSLog(msg3)
        logToDebugFile(msg3)
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
        MenuBarController.shared?.setIconState(.active)
    }

    /// Resume monitoring after permission grant
    private func resumeMonitoring() {
        if let context = applicationTracker.activeApplication,
           context.shouldCheck() {
            self.monitoredContext = context  // Set BEFORE startMonitoring
            startMonitoring(context: context)
        }
    }

    /// Handle text change and trigger analysis (T038)
    private func handleTextChange(_ text: String, in context: ApplicationContext) {
        let msg1 = "📝 AnalysisCoordinator: Text changed in \(context.applicationName) (\(text.count) chars)"
        NSLog(msg1)
        logToDebugFile(msg1)

        let segment = TextSegment(
            content: text,
            startIndex: 0,
            endIndex: text.count,
            context: context
        )

        currentSegment = segment

        // Perform analysis
        let isEnabled = UserPreferences.shared.isEnabled
        let msg2 = "📊 AnalysisCoordinator: Grammar checking enabled: \(isEnabled)"
        NSLog(msg2)
        logToDebugFile(msg2)

        if isEnabled {
            let msg3 = "✅ AnalysisCoordinator: Calling analyzeText()"
            NSLog(msg3)
            logToDebugFile(msg3)
            analyzeText(segment)
        } else {
            let msg3 = "⏸️ AnalysisCoordinator: Analysis disabled in preferences"
            NSLog(msg3)
            logToDebugFile(msg3)
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
        let msg1 = "🔬 AnalysisCoordinator: analyzeFullText called"
        NSLog(msg1)
        logToDebugFile(msg1)

        // CRITICAL: Capture the monitored element BEFORE async operation
        let capturedElement = textMonitor.monitoredElement
        let segmentContent = segment.content

        analysisQueue.async { [weak self] in
            guard let self = self else { return }

            let msg2 = "🧬 AnalysisCoordinator: Calling Harper grammar engine..."
            NSLog(msg2)
            logToDebugFile(msg2)

            let dialect = UserPreferences.shared.selectedDialect
            let enableInternetAbbrev = UserPreferences.shared.enableInternetAbbreviations
            let enableGenZSlang = UserPreferences.shared.enableGenZSlang
            let enableITTerminology = UserPreferences.shared.enableITTerminology
            let enableLanguageDetection = UserPreferences.shared.enableLanguageDetection
            let excludedLanguages = Array(UserPreferences.shared.excludedLanguages.map { UserPreferences.languageCode(for: $0) })
            let result = GrammarEngine.shared.analyzeText(
                segmentContent,
                dialect: dialect,
                enableInternetAbbrev: enableInternetAbbrev,
                enableGenZSlang: enableGenZSlang,
                enableITTerminology: enableITTerminology,
                enableLanguageDetection: enableLanguageDetection,
                excludedLanguages: excludedLanguages
            )

            let msg3 = "📊 AnalysisCoordinator: Harper returned \(result.errors.count) error(s)"
            NSLog(msg3)
            logToDebugFile(msg3)

            DispatchQueue.main.async {
                let msg4 = "💾 AnalysisCoordinator: Updating error cache and applying filters..."
                NSLog(msg4)
                logToDebugFile(msg4)

                self.updateErrorCache(for: segment, with: result.errors)
                self.applyFilters(to: result.errors, sourceText: segmentContent, element: capturedElement)

                // Record statistics
                let wordCount = segmentContent.split(separator: " ").count
                UserStatistics.shared.recordAnalysisSession(
                    wordsProcessed: wordCount,
                    errorsFound: result.errors.count
                )

                let msg5 = "✅ AnalysisCoordinator: Analysis complete"
                NSLog(msg5)
                logToDebugFile(msg5)
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
            let result = GrammarEngine.shared.analyzeText(
                segmentContent,
                dialect: dialect,
                enableInternetAbbrev: enableInternetAbbrev,
                enableGenZSlang: enableGenZSlang,
                enableITTerminology: enableITTerminology,
                enableLanguageDetection: enableLanguageDetection,
                excludedLanguages: excludedLanguages
            )

            DispatchQueue.main.async {
                self.updateErrorCache(for: segment, with: result.errors)
                self.applyFilters(to: result.errors, sourceText: segmentContent, element: capturedElement)

                // Record statistics
                let wordCount = segmentContent.split(separator: " ").count
                UserStatistics.shared.recordAnalysisSession(
                    wordsProcessed: wordCount,
                    errorsFound: result.errors.count
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
        let msg1 = "🔍 AnalysisCoordinator: applyFilters called with \(errors.count) errors"
        NSLog(msg1)
        logToDebugFile(msg1)

        var filteredErrors = errors

        // Log error categories
        for error in errors {
            let msg = "  📋 Error category: '\(error.category)', message: '\(error.message)'"
            NSLog(msg)
            logToDebugFile(msg)
        }

        // Filter by category (e.g., Spelling, Grammar, Style)
        let enabledCategories = UserPreferences.shared.enabledCategories
        let msgCat = "🏷️ AnalysisCoordinator: Enabled categories: \(enabledCategories)"
        NSLog(msgCat)
        logToDebugFile(msgCat)

        filteredErrors = filteredErrors.filter { error in
            let contains = enabledCategories.contains(error.category)
            if !contains {
                let msg = "  ❌ Filtering out error with category: '\(error.category)'"
                NSLog(msg)
                logToDebugFile(msg)
            }
            return contains
        }

        let msg2 = "  After category filter: \(filteredErrors.count) errors"
        NSLog(msg2)
        logToDebugFile(msg2)

        // Deduplicate consecutive identical errors (Issue #2)
        // This prevents 157 "Horizontal ellipsis" errors from flooding the UI
        filteredErrors = deduplicateErrors(filteredErrors)

        let msg3 = "  After deduplication: \(filteredErrors.count) errors"
        NSLog(msg3)
        logToDebugFile(msg3)

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

        // Show underlines for errors (hover-based popup)
        showErrorUnderlines(filteredErrors, element: element)
    }

    /// Show visual underlines for errors (LanguageTool/Grammarly style)
    private func showErrorUnderlines(_ errors: [GrammarErrorModel], element: AXUIElement?) {
        let msg1 = "📍 AnalysisCoordinator: showErrorUnderlines called with \(errors.count) errors"
        NSLog(msg1)
        logToDebugFile(msg1)

        guard let monitoredElement = element else {
            let msg = "⚠️ AnalysisCoordinator: No monitored element - hiding overlays"
            NSLog(msg)
            logToDebugFile(msg)
            errorOverlay.hide()
            floatingIndicator.hide()
            MenuBarController.shared?.setIconState(.active)
            return
        }

        if errors.isEmpty {
            let msg = "📍 AnalysisCoordinator: No errors - hiding overlays"
            NSLog(msg)
            logToDebugFile(msg)
            errorOverlay.hide()
            floatingIndicator.hide()
            MenuBarController.shared?.setIconState(.active)
        } else {
            // Debug: Log context before passing to errorOverlay
            let bundleID = monitoredContext?.bundleIdentifier ?? "nil"
            let appName = monitoredContext?.applicationName ?? "nil"
            let msg = "🔍 AnalysisCoordinator: About to call errorOverlay.update() with context - bundleID: '\(bundleID)', appName: '\(appName)'"
            NSLog(msg)
            logToDebugFile(msg)

            // Try to show visual underlines
            let underlinesCreated = errorOverlay.update(errors: errors, element: monitoredElement, context: monitoredContext)

            // If we have errors but no underlines were created, show floating indicator
            // This happens when:
            // - Terminal apps (positioning unreliable)
            // - Electron apps with broken AX APIs
            // - Any app where bounds calculation fails
            if underlinesCreated == 0 {
                let appName = monitoredContext?.applicationName ?? "unknown"
                let msg = "⚠️ AnalysisCoordinator: \(errors.count) errors detected in '\(appName)' but no underlines created - showing floating indicator"
                NSLog(msg)
                logToDebugFile(msg)
                floatingIndicator.update(errors: errors, element: monitoredElement, context: monitoredContext)
                MenuBarController.shared?.setIconState(.error)
            } else {
                let msg = "✅ AnalysisCoordinator: Showing \(underlinesCreated) visual underlines"
                NSLog(msg)
                logToDebugFile(msg)
                floatingIndicator.hide()  // Hide floating indicator when showing visual underlines
                MenuBarController.shared?.setIconState(.active)
            }
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

        // Add to custom vocabulary (use CustomVocabulary, not UserPreferences)
        do {
            try CustomVocabulary.shared.addWord(errorText)
            print("✅ Added '\(errorText)' to custom dictionary")
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
        guard let element = textMonitor.monitoredElement else {
            print("No monitored element for text replacement")
            return
        }

        // Inspired by Grammarly: Use keyboard automation directly for known Electron apps
        // This avoids trying the AX API which is known to fail on Electron
        if let context = monitoredContext, context.requiresKeyboardReplacement {
            let msg = "🎯 Detected Electron app (\(context.applicationName)) - using keyboard automation directly"
            NSLog(msg)
            logToDebugFile(msg)

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
            let msg = "⚠️ AX API selection failed (\(selectError.rawValue)), using keyboard fallback"
            NSLog(msg)
            logToDebugFile(msg)

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
            let msg = "⚠️ AX API replacement failed (\(replaceError.rawValue)), trying keyboard fallback"
            NSLog(msg)
            logToDebugFile(msg)

            // Try keyboard fallback
            applyTextReplacementViaKeyboard(for: error, with: suggestion, element: element)
        }
    }

    /// Apply text replacement using keyboard simulation (for Electron apps and Terminals)
    /// Inspired by Grammarly's hybrid replacement approach
    private func applyTextReplacementViaKeyboard(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement) {
        guard let context = self.monitoredContext else {
            NSLog("❌ No context available for keyboard replacement")
            return
        }

        let msg1 = "⌨️ Using keyboard simulation for text replacement (app: \(context.applicationName), isTerminal: \(context.isTerminalApp))"
        NSLog(msg1)
        logToDebugFile(msg1)

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
                    let msg = "📍 Terminal: Original cursor position: \(cfRange.location) (selection length: \(cfRange.length))"
                    NSLog(msg)
                    logToDebugFile(msg)
                } else {
                    let msg = "⚠️ Terminal: Could not extract CFRange from AXSelectedTextRange"
                    NSLog(msg)
                    logToDebugFile(msg)
                }
            } else {
                let msg = "⚠️ Terminal: Could not query AXSelectedTextRange (error: \(rangeResult.rawValue))"
                NSLog(msg)
                logToDebugFile(msg)
            }

            // Get the current text and apply the correction
            var currentTextValue: CFTypeRef?
            let getTextResult = AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &currentTextValue
            )

            guard getTextResult == .success, let fullText = currentTextValue as? String else {
                let msg = "❌ Failed to get current text for Terminal replacement"
                NSLog(msg)
                logToDebugFile(msg)
                return
            }

            // Apply preprocessing to get just the command line text
            let parser = ContentParserFactory.shared.parser(for: context.bundleIdentifier)
            guard let commandLineText = parser.preprocessText(fullText) else {
                let msg = "❌ Failed to preprocess text for Terminal"
                NSLog(msg)
                logToDebugFile(msg)
                return
            }

            // Apply the correction to the command line text
            let startIndex = commandLineText.index(commandLineText.startIndex, offsetBy: error.start)
            let endIndex = commandLineText.index(commandLineText.startIndex, offsetBy: error.end)
            var correctedText = commandLineText
            correctedText.replaceSubrange(startIndex..<endIndex, with: suggestion)

            let msg2 = "📝 Terminal: Original command: '\(commandLineText)'"
            NSLog(msg2)
            logToDebugFile(msg2)

            let msg3 = "📝 Terminal: Corrected command: '\(correctedText)'"
            NSLog(msg3)
            logToDebugFile(msg3)

            // Calculate target cursor position for restoration
            var targetCursorPosition: Int?
            if let axCursorPos = originalCursorPosition {
                // Map cursor position from full text to command line coordinates
                // Find where the command line starts in the full text
                let commandRange = (fullText as NSString).range(of: commandLineText)
                if commandRange.location != NSNotFound {
                    let promptOffset = commandRange.location
                    let cursorInCommandLine = axCursorPos - promptOffset

                    let msg = "📍 Terminal: Cursor in command line: \(cursorInCommandLine) (AX position: \(axCursorPos), prompt offset: \(promptOffset))"
                    NSLog(msg)
                    logToDebugFile(msg)

                    // Calculate new cursor position after replacement
                    let errorLength = error.end - error.start
                    let replacementLength = suggestion.count
                    let lengthDelta = replacementLength - errorLength

                    if cursorInCommandLine < error.start {
                        // Cursor before error - position unchanged
                        targetCursorPosition = cursorInCommandLine
                        let msg2 = "📍 Cursor before error - keeping at position \(cursorInCommandLine)"
                        NSLog(msg2)
                        logToDebugFile(msg2)
                    } else if cursorInCommandLine >= error.end {
                        // Cursor after error - shift by length delta
                        targetCursorPosition = cursorInCommandLine + lengthDelta
                        let msg2 = "📍 Cursor after error - moving to position \(cursorInCommandLine + lengthDelta)"
                        NSLog(msg2)
                        logToDebugFile(msg2)
                    } else {
                        // Cursor inside error - move to end of replacement
                        targetCursorPosition = error.start + replacementLength
                        let msg2 = "📍 Cursor inside error - moving to end of replacement at position \(error.start + replacementLength)"
                        NSLog(msg2)
                        logToDebugFile(msg2)
                    }
                } else {
                    let msg = "⚠️ Terminal: Could not find command line in full text - cannot map cursor position"
                    NSLog(msg)
                    logToDebugFile(msg)
                }
            }

            // Copy corrected text to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(correctedText, forType: .string)

            let msg4 = "📋 Copied corrected command to clipboard"
            NSLog(msg4)
            logToDebugFile(msg4)

            // Activate Terminal
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier)
            if let targetApp = apps.first {
                targetApp.activate(options: .activateIgnoringOtherApps)
                let msg = "🎯 Activated Terminal for keyboard commands"
                NSLog(msg)
                logToDebugFile(msg)
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

                let msg1 = "⌨️ Sent Ctrl+A"
                NSLog(msg1)
                logToDebugFile(msg1)

                // Small delay before Ctrl+K
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    // Step 2: Ctrl+K to kill (delete) to end of line
                    self.pressKey(key: VirtualKeyCode.k, flags: .maskControl)

                    let msg2 = "⌨️ Sent Ctrl+K"
                    NSLog(msg2)
                    logToDebugFile(msg2)

                    // Small delay before paste
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        // Step 3: Paste the corrected text
                        self.pressKey(key: VirtualKeyCode.v, flags: .maskCommand)

                        let msg3 = "⌨️ Sent Cmd+V"
                        NSLog(msg3)
                        logToDebugFile(msg3)

                        // Step 4: Position cursor at target location
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            if let targetPos = targetCursorPosition {
                                // Navigate to target cursor position
                                // First move to beginning
                                self.pressKey(key: VirtualKeyCode.a, flags: .maskControl)

                                let msg = "⌨️ Sent Ctrl+A to move to beginning before cursor positioning"
                                NSLog(msg)
                                logToDebugFile(msg)

                                // Small delay, then send right arrows to reach target position
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                                    // Send all right arrow keys rapidly (no delays between them to avoid animation)
                                    for _ in 0..<targetPos {
                                        self.pressKey(key: VirtualKeyCode.rightArrow, flags: [], withDelay: false)
                                    }

                                    let msg2 = "✅ Terminal replacement complete (cursor at position \(targetPos))"
                                    NSLog(msg2)
                                    logToDebugFile(msg2)

                                    // Record statistics
                                    UserStatistics.shared.recordSuggestionApplied(category: error.category)

                                    // Invalidate cache
                                    self.invalidateCacheAfterReplacement(at: error.start..<error.end)
                                }
                            } else {
                                // Fallback: move to end if we couldn't determine target position
                                self.pressKey(key: VirtualKeyCode.e, flags: .maskControl)

                                let msg = "✅ Terminal replacement complete (cursor at end - position unknown)"
                                NSLog(msg)
                                logToDebugFile(msg)

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
            let msg = "🎯 Activating \(context.applicationName) to make it frontmost"
            NSLog(msg)
            logToDebugFile(msg)
            targetApp.activate(options: .activateIgnoringOtherApps)
        } else {
            let msg = "⚠️ Could not find running app with bundle ID \(context.bundleIdentifier)"
            NSLog(msg)
            logToDebugFile(msg)
        }

        // Get app-specific timing based on Grammarly's approach
        let delay = context.keyboardOperationDelay
        // Add extra delay for app activation to complete
        let activationDelay: TimeInterval = 0.2
        let msg2 = "⏱️ Using \(delay)s keyboard delay + \(activationDelay)s activation delay for \(context.applicationName)"
        NSLog(msg2)
        logToDebugFile(msg2)

        // Save suggestion to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        let msg3 = "📋 Copied suggestion to clipboard: \(suggestion)"
        NSLog(msg3)
        logToDebugFile(msg3)

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

                        let msg = "✅ Keyboard-based text replacement complete"
                        NSLog(msg)
                        logToDebugFile(msg)

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
        let msg1 = "🔧 Attempting AX API selection-based replacement for range \(start)-\(end)"
        NSLog(msg1)
        logToDebugFile(msg1)

        // Read the original text before modification
        var textValue: CFTypeRef?
        let getTextResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        )

        let originalText: String
        if getTextResult == .success, let text = textValue as? String {
            originalText = text
        } else {
            let msg = "❌ Failed to read original text for verification"
            NSLog(msg)
            logToDebugFile(msg)
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
            let msg = "❌ Failed to set AXSelectedTextRange: error \(setRangeResult.rawValue)"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        let msg2 = "✅ AX API accepted selection range \(start)-\(end)"
        NSLog(msg2)
        logToDebugFile(msg2)

        // Step 2: Replace the selected text with the suggestion
        let setTextResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            suggestion as CFTypeRef
        )

        if setTextResult != .success {
            let msg = "❌ Failed to set AXSelectedText: error \(setTextResult.rawValue)"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        // DON'T try to set the text via AX API - Terminal.app's implementation is broken
        // Selection worked - caller will handle paste after activating Terminal
        let msg3 = "✅ AX API selection successful at \(start)-\(end), returning for paste"
        NSLog(msg3)
        logToDebugFile(msg3)

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
        // Create proper event source (required for reliable keyboard simulation)
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            let msg = "❌ Failed to create CGEventSource for key press"
            NSLog(msg)
            logToDebugFile(msg)
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

        // Create and post key down event
        if let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: true) {
            keyDown.flags = adjustedFlags
            keyDown.post(tap: .cghidEventTap)
        }

        // Create and post key up event
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

        // Add new errors
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

        // Remove oldest entries
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

        // Update metadata
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
