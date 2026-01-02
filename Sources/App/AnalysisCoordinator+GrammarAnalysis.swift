//
//  AnalysisCoordinator+GrammarAnalysis.swift
//  TextWarden
//
//  Grammar analysis functionality extracted from AnalysisCoordinator.
//  Handles text analysis, Harper grammar engine integration, and LLM style analysis dispatch.
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation

// MARK: - Grammar Analysis

extension AnalysisCoordinator {
    // MARK: - Configuration Capture

    /// Configuration for grammar analysis captured from UserPreferences
    struct GrammarConfig {
        let dialect: String
        let enableInternetAbbrev: Bool
        let enableGenZSlang: Bool
        let enableITTerminology: Bool
        let enableBrandNames: Bool
        let enablePersonNames: Bool
        let enableLastNames: Bool
        let enableLanguageDetection: Bool
        let excludedLanguages: [String]
        let enforceOxfordComma: Bool
        let checkEllipsis: Bool
        let checkUnclosedQuotes: Bool
        let checkDashes: Bool
    }

    /// Capture grammar preferences on main thread before async dispatch
    func captureGrammarConfig() -> GrammarConfig {
        GrammarConfig(
            dialect: userPreferences.selectedDialect,
            enableInternetAbbrev: userPreferences.enableInternetAbbreviations,
            enableGenZSlang: userPreferences.enableGenZSlang,
            enableITTerminology: userPreferences.enableITTerminology,
            enableBrandNames: userPreferences.enableBrandNames,
            enablePersonNames: userPreferences.enablePersonNames,
            enableLastNames: userPreferences.enableLastNames,
            enableLanguageDetection: userPreferences.enableLanguageDetection,
            excludedLanguages: Array(userPreferences.excludedLanguages.map { UserPreferences.languageCode(for: $0) }),
            enforceOxfordComma: userPreferences.enforceOxfordComma,
            checkEllipsis: userPreferences.checkEllipsis,
            checkUnclosedQuotes: userPreferences.checkUnclosedQuotes,
            checkDashes: userPreferences.checkDashes
        )
    }

    // MARK: - Main Analysis Entry Points

    /// Analyze text with incremental support - internal for extension access
    func analyzeText(_ segment: TextSegment) {
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
    func analyzeFullText(_ segment: TextSegment) {
        Logger.debug("AnalysisCoordinator: analyzeFullText called", category: Logger.analysis)

        let capturedElement = textMonitor.monitoredElement
        let segmentContent = segment.content
        lastAnalyzedText = segmentContent

        // Run grammar analysis (immediate, fast ~10ms)
        let grammarConfig = captureGrammarConfig()
        runGrammarAnalysis(
            segment: segment,
            text: segmentContent,
            config: grammarConfig,
            element: capturedElement
        )

        // Run style analysis if enabled (debounced, slow ~35s)
        let shouldRunStyle = shouldRunAutoStyleChecking()
        if shouldRunStyle {
            runDebouncedStyleAnalysis(text: segmentContent)
        } else {
            styleDebounceTimer?.invalidate()
            styleDebounceTimer = nil
        }
    }

    /// Analyze only changed portion
    func analyzeChangedPortion(_ segment: TextSegment) {
        // CRITICAL: Capture the monitored element BEFORE async operation
        let capturedElement = textMonitor.monitoredElement
        let segmentContent = segment.content

        // Capture UserPreferences values on main thread before async dispatch
        let dialect = userPreferences.selectedDialect
        let enableInternetAbbrev = userPreferences.enableInternetAbbreviations
        let enableGenZSlang = userPreferences.enableGenZSlang
        let enableITTerminology = userPreferences.enableITTerminology
        let enableBrandNames = userPreferences.enableBrandNames
        let enablePersonNames = userPreferences.enablePersonNames
        let enableLastNames = userPreferences.enableLastNames
        let enableLanguageDetection = userPreferences.enableLanguageDetection
        let excludedLanguages = Array(userPreferences.excludedLanguages.map { UserPreferences.languageCode(for: $0) })
        let enforceOxfordComma = userPreferences.enforceOxfordComma
        let checkEllipsis = userPreferences.checkEllipsis
        let checkUnclosedQuotes = userPreferences.checkUnclosedQuotes
        let checkDashes = userPreferences.checkDashes

        // Capture grammar engine reference before async dispatch
        let grammarEngineRef = grammarEngine

        // Simplified: For large docs, still analyze full text but async
        // Full incremental diff would require text diffing algorithm
        analysisQueue.async { [weak self] in
            guard let self else { return }

            let result = grammarEngineRef.analyzeText(
                segmentContent,
                dialect: dialect,
                enableInternetAbbrev: enableInternetAbbrev,
                enableGenZSlang: enableGenZSlang,
                enableITTerminology: enableITTerminology,
                enableBrandNames: enableBrandNames,
                enablePersonNames: enablePersonNames,
                enableLastNames: enableLastNames,
                enableLanguageDetection: enableLanguageDetection,
                excludedLanguages: excludedLanguages,
                enforceOxfordComma: enforceOxfordComma,
                checkEllipsis: checkEllipsis,
                checkUnclosedQuotes: checkUnclosedQuotes,
                checkDashes: checkDashes
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                updateErrorCache(for: segment, with: result.errors)
                applyFilters(to: result.errors, sourceText: segmentContent, element: capturedElement)

                // Record statistics with full details
                let wordCount = segmentContent.split(separator: " ").count

                // Compute category breakdown
                var categoryBreakdown: [String: Int] = [:]
                for error in result.errors {
                    categoryBreakdown[error.category, default: 0] += 1
                }

                statistics.recordDetailedAnalysisSession(
                    wordsProcessed: wordCount,
                    errorsFound: result.errors.count,
                    bundleIdentifier: monitoredContext?.bundleIdentifier,
                    categoryBreakdown: categoryBreakdown,
                    latencyMs: Double(result.analysisTimeMs)
                )
            }
        }
    }

    // MARK: - Grammar Analysis Helpers

    /// Run grammar analysis asynchronously
    func runGrammarAnalysis(
        segment: TextSegment,
        text: String,
        config: GrammarConfig,
        element: AXUIElement?
    ) {
        // Capture grammar engine reference before async dispatch
        let grammarEngineRef = grammarEngine

        analysisQueue.async { [weak self] in
            guard let self else { return }

            Logger.debug("AnalysisCoordinator: Calling Harper grammar engine...", category: Logger.analysis)

            let grammarResult = grammarEngineRef.analyzeText(
                text,
                dialect: config.dialect,
                enableInternetAbbrev: config.enableInternetAbbrev,
                enableGenZSlang: config.enableGenZSlang,
                enableITTerminology: config.enableITTerminology,
                enableBrandNames: config.enableBrandNames,
                enablePersonNames: config.enablePersonNames,
                enableLastNames: config.enableLastNames,
                enableLanguageDetection: config.enableLanguageDetection,
                excludedLanguages: config.excludedLanguages,
                enforceOxfordComma: config.enforceOxfordComma,
                checkEllipsis: config.checkEllipsis,
                checkUnclosedQuotes: config.checkUnclosedQuotes,
                checkDashes: config.checkDashes
            )

            Logger.debug("AnalysisCoordinator: Harper returned \(grammarResult.errors.count) error(s)", category: Logger.analysis)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                handleGrammarResults(
                    grammarResult,
                    segment: segment,
                    text: text,
                    element: element
                )
            }
        }
    }

    /// Process grammar results and update UI
    func handleGrammarResults(
        _ result: GrammarAnalysisResult,
        segment: TextSegment,
        text: String,
        element: AXUIElement?
    ) {
        let errorsWithCachedAI = enhanceErrorsWithCachedAI(result.errors, sourceText: text)
        updateErrorCache(for: segment, with: errorsWithCachedAI)
        applyFilters(to: errorsWithCachedAI, sourceText: text, element: element)

        // Record statistics
        let wordCount = text.split(separator: " ").count
        var categoryBreakdown: [String: Int] = [:]
        for error in result.errors {
            categoryBreakdown[error.category, default: 0] += 1
        }

        statistics.recordDetailedAnalysisSession(
            wordsProcessed: wordCount,
            errorsFound: result.errors.count,
            bundleIdentifier: monitoredContext?.bundleIdentifier,
            categoryBreakdown: categoryBreakdown,
            latencyMs: Double(result.analysisTimeMs)
        )

        // Calculate readability score if enabled and text has sufficient length
        if userPreferences.showReadabilityScore, wordCount >= 30 {
            // Get target audience from user preference
            let targetAudience = TargetAudience(fromDisplayName: userPreferences.selectedTargetAudience) ?? .general

            // Run sentence-level analysis if feature is enabled
            if userPreferences.sentenceComplexityHighlightingEnabled,
               let analysis = ReadabilityCalculator.shared.analyzeForTargetAudience(text, targetAudience: targetAudience)
            {
                currentReadabilityAnalysis = analysis
                currentReadabilityResult = analysis.overallResult
                Logger.debug("AnalysisCoordinator: Readability analysis complete - \(analysis.complexSentenceCount) complex sentences for \(targetAudience.displayName) audience", category: Logger.analysis)

                // Update readability underlines if there are complex sentences and element is available
                if let element, userPreferences.showReadabilityUnderlines, !analysis.complexSentences.isEmpty {
                    errorOverlay.updateReadabilityUnderlines(
                        complexSentences: analysis.complexSentences,
                        element: element,
                        context: monitoredContext,
                        text: text
                    )
                } else {
                    errorOverlay.clearReadabilityUnderlines()
                }
            } else {
                // Feature disabled - just calculate overall readability without sentence analysis
                currentReadabilityResult = ReadabilityCalculator.shared.fleschReadingEase(for: text)
                currentReadabilityAnalysis = nil
                errorOverlay.clearReadabilityUnderlines()
            }
        } else {
            currentReadabilityResult = nil
            currentReadabilityAnalysis = nil
            errorOverlay.clearReadabilityUnderlines()
        }

        Logger.debug("AnalysisCoordinator: Grammar analysis complete, UI updated", category: Logger.analysis)

        // Enhance readability errors with AI suggestions
        enhanceReadabilityErrorsWithAI(
            errors: errorsWithCachedAI,
            sourceText: text,
            element: element,
            segment: segment
        )
    }

    /// Check if text has changed significantly
    func textHasChangedSignificantly(_ newText: String) -> Bool {
        let oldCount = previousText.count
        let newCount = newText.count

        // Consider significant if >10% change or >100 chars
        let diff = abs(newCount - oldCount)
        return diff > 100 || diff > oldCount / 10
    }

    /// Check if text contains at least one sentence with the minimum word count
    /// Used to gate style analysis - no point running expensive LLM on short snippets
    func containsSentenceWithMinWords(_ text: String, minWords: Int) -> Bool {
        // Split text into sentences using common sentence terminators
        // This handles: "Hello. World!" → ["Hello", " World"]
        let sentenceTerminators = CharacterSet(charactersIn: ".!?")
        let sentences = text.components(separatedBy: sentenceTerminators)

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Count words in this sentence
            let wordCount = trimmed.split(separator: " ").count(where: { !$0.isEmpty })
            if wordCount >= minWords {
                return true
            }
        }

        return false
    }

    // MARK: - Style Analysis Helpers

    /// Check if auto style checking should run
    /// Returns true if style checking is enabled (auto checking is now always on when enabled)
    func shouldRunAutoStyleChecking() -> Bool {
        let styleCheckingEnabled = userPreferences.enableStyleChecking
        Logger.debug("AnalysisCoordinator: Style check eligibility - enabled=\(styleCheckingEnabled)", category: Logger.llm)
        return styleCheckingEnabled
    }

    /// Run debounced style analysis after grammar check completes
    /// Uses Apple Intelligence (Foundation Models) with defensive rate limiting
    func runDebouncedStyleAnalysis(text: String) {
        // Cancel any pending style check
        styleDebounceTimer?.invalidate()

        // Schedule new style check with debounce delay
        styleDebounceTimer = Timer.scheduledTimer(withTimeInterval: autoStyleCheckDebounceDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.executeAutoStyleCheck(text: text)
            }
        }
    }

    /// Execute auto style check with defensive rate limiting
    private func executeAutoStyleCheck(text: String) {
        // Guard: Don't run if already in progress
        guard !isAutoStyleCheckInProgress else {
            Logger.debug("Auto style check: Skipping - already in progress", category: Logger.llm)
            return
        }

        // Guard: Don't run if manual style check is active
        guard !isManualStyleCheckActive else {
            Logger.debug("Auto style check: Skipping - manual check active", category: Logger.llm)
            return
        }

        // Guard: Minimum text length
        guard text.count >= autoStyleCheckMinTextLength else {
            Logger.debug("Auto style check: Skipping - text too short (\(text.count) < \(autoStyleCheckMinTextLength))", category: Logger.llm)
            return
        }

        // Guard: Rate limiting - minimum interval between checks
        if let lastCheck = lastAutoStyleCheckTime {
            let elapsed = Date().timeIntervalSince(lastCheck)
            guard elapsed >= autoStyleCheckMinInterval else {
                Logger.debug("Auto style check: Skipping - too soon (\(Int(elapsed))s < \(Int(autoStyleCheckMinInterval))s)", category: Logger.llm)
                return
            }
        }

        // Guard: Text must have changed since last check
        let textHash = text.hashValue
        if let lastHash = lastAutoStyleCheckTextHash, lastHash == textHash {
            Logger.debug("Auto style check: Skipping - text unchanged", category: Logger.llm)
            return
        }

        // Guard: Apple Intelligence must be available (macOS 26+)
        guard #available(macOS 26.0, *) else {
            Logger.debug("Auto style check: Skipping - requires macOS 26+", category: Logger.llm)
            return
        }

        // Guard: Must have monitored element and context
        guard let element = textMonitor.monitoredElement,
              let context = monitoredContext
        else {
            Logger.debug("Auto style check: Skipping - no monitored element", category: Logger.llm)
            return
        }

        // All guards passed - run the style check
        Logger.info("Auto style check: Starting analysis (\(text.count) chars)", category: Logger.llm)

        isAutoStyleCheckInProgress = true
        lastAutoStyleCheckTime = Date()
        lastAutoStyleCheckTextHash = textHash

        // Run the actual style check using Foundation Models
        runAutoStyleCheckWithFM(text: text, element: element, context: context)
    }

    /// Run auto style check using Foundation Models (Apple Intelligence)
    @available(macOS 26.0, *)
    private func runAutoStyleCheckWithFM(text: String, element _: AXUIElement, context _: ApplicationContext) {
        let fmEngine = FoundationModelsEngine()
        fmEngine.checkAvailability()

        guard fmEngine.status.isAvailable else {
            Logger.warning("Auto style check: Apple Intelligence not available - \(fmEngine.status.userMessage)", category: Logger.llm)
            isAutoStyleCheckInProgress = false
            return
        }

        let styleName = userPreferences.selectedWritingStyle
        let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default

        // Check cache first
        let cacheKey = computeStyleCacheKey(text: text)
        if let cached = styleCache[cacheKey], text == styleAnalysisSourceText {
            var filteredCached = cached.filter { !dismissedStyleSuggestionHashes.contains($0.originalText.hashValue) }
            filteredCached = filterStyleSuggestionsNotOverlappingGrammarErrors(filteredCached, grammarErrors: currentErrors)

            Logger.debug("Auto style check: Cache hit, \(filteredCached.count) suggestion(s)", category: Logger.llm)

            styleCacheMetadata[cacheKey] = StyleCacheMetadata(lastAccessed: Date(), style: styleName)
            currentStyleSuggestions = filteredCached
            styleAnalysisSourceText = text

            floatingIndicator.showStyleSuggestionsReady(count: filteredCached.count, styleSuggestions: filteredCached)
            isAutoStyleCheckInProgress = false
            return
        }

        // Cache miss - run analysis
        Logger.debug("Auto style check: Cache miss, running analysis", category: Logger.llm)

        // Show loading state on indicator
        floatingIndicator.setStyleLoading(true)

        // Capture generation for staleness check
        styleAnalysisGeneration &+= 1
        let capturedGeneration = styleAnalysisGeneration

        // Capture readability settings
        let sentenceComplexityEnabled = userPreferences.sentenceComplexityHighlightingEnabled
        let targetAudienceName = userPreferences.selectedTargetAudience
        let targetAudience = TargetAudience(fromDisplayName: targetAudienceName) ?? .general
        let readabilityAnalysis = currentReadabilityAnalysis

        Task {
            do {
                let suggestions = try await fmEngine.analyzeStyle(text, style: style)

                await MainActor.run {
                    // Check if still valid (text may have changed during analysis)
                    guard capturedGeneration == self.styleAnalysisGeneration else {
                        Logger.debug("Auto style check: Stale result, discarding", category: Logger.llm)
                        self.isAutoStyleCheckInProgress = false
                        return
                    }

                    // Filter suggestions
                    var filtered = suggestions.filter { !self.dismissedStyleSuggestionHashes.contains($0.originalText.hashValue) }
                    filtered = self.filterStyleSuggestionsNotOverlappingGrammarErrors(filtered, grammarErrors: self.currentErrors)

                    // Update state with style suggestions
                    self.currentStyleSuggestions = filtered
                    self.styleAnalysisSourceText = text
                }

                // Generate readability simplifications for complex sentences (if enabled)
                if sentenceComplexityEnabled,
                   let analysis = readabilityAnalysis,
                   !analysis.complexSentences.isEmpty
                {
                    Logger.debug("Auto style check: Generating simplifications for \(analysis.complexSentences.count) complex sentence(s)", category: Logger.llm)

                    for sentence in analysis.complexSentences.prefix(3) {
                        do {
                            let alternatives = try await fmEngine.simplifySentence(
                                sentence.sentence,
                                targetAudience: targetAudience,
                                writingStyle: style
                            )

                            // Only store suggestion if we got a non-empty alternative
                            if let firstAlternative = alternatives.first, !firstAlternative.isEmpty {
                                let suggestion = StyleSuggestionModel(
                                    id: "readability-\(sentence.range.location)-0",
                                    originalStart: sentence.range.location,
                                    originalEnd: sentence.range.location + sentence.range.length,
                                    originalText: sentence.sentence,
                                    suggestedText: firstAlternative,
                                    explanation: "Simplified for \(targetAudience.displayName) audience",
                                    confidence: 0.85,
                                    style: style,
                                    isReadabilitySuggestion: true,
                                    readabilityScore: Int(sentence.score),
                                    targetAudience: targetAudience.displayName
                                )

                                await MainActor.run {
                                    self.currentStyleSuggestions.append(suggestion)
                                }
                            }
                        } catch {
                            Logger.warning("Auto style check: Failed to simplify sentence - \(error.localizedDescription)", category: Logger.llm)
                        }
                    }
                }

                await MainActor.run {
                    Logger.info("Auto style check: Complete, \(self.currentStyleSuggestions.count) total suggestion(s)", category: Logger.llm)

                    // Cache combined results (style + readability)
                    self.styleCache[cacheKey] = self.currentStyleSuggestions
                    self.styleCacheMetadata[cacheKey] = StyleCacheMetadata(lastAccessed: Date(), style: styleName)

                    // Update indicator
                    self.floatingIndicator.showStyleSuggestionsReady(count: self.currentStyleSuggestions.count, styleSuggestions: self.currentStyleSuggestions)
                    self.isAutoStyleCheckInProgress = false
                }
            } catch {
                await MainActor.run {
                    Logger.error("Auto style check failed: \(error)", category: Logger.llm)
                    self.floatingIndicator.setStyleLoading(false)
                    self.isAutoStyleCheckInProgress = false
                }
            }
        }
    }

    /// Execute style analysis
    /// Note: This is now a no-op - use FoundationModelsEngine for style analysis
    func executeLLMStyleAnalysis(text _: String, cacheKey _: String, generation _: UInt64) {
        // Style analysis via Rust LLM is removed
        // Use FoundationModelsEngine for Apple Intelligence style analysis
    }

    /// Process style results and update UI
    func handleStyleResults(
        _ result: StyleAnalysisResultModel,
        text: String,
        cacheKey: String,
        generation: UInt64,
        styleName: String,
        confidenceThreshold: Float
    ) {
        guard generation == styleAnalysisGeneration else {
            Logger.debug("AnalysisCoordinator: Discarding stale LLM results (gen=\(generation))", category: Logger.llm)
            return
        }

        guard !result.isError else {
            currentStyleSuggestions = []
            Logger.warning("AnalysisCoordinator: Style analysis error: \(result.error ?? "unknown")", category: Logger.analysis)
            return
        }

        let filteredSuggestions = result.suggestions.filter { $0.confidence >= confidenceThreshold }
        currentStyleSuggestions = filteredSuggestions
        styleAnalysisSourceText = text

        // Cache results
        styleCache[cacheKey] = filteredSuggestions
        styleCacheMetadata[cacheKey] = StyleCacheMetadata(lastAccessed: Date(), style: styleName)
        evictStyleCacheIfNeeded()

        Logger.info("AnalysisCoordinator: \(filteredSuggestions.count) style suggestion(s) above threshold (gen=\(generation))", category: Logger.llm)

        // Update floating indicator
        if !filteredSuggestions.isEmpty, let element = textMonitor.monitoredElement {
            floatingIndicator.update(
                errors: currentErrors,
                styleSuggestions: filteredSuggestions,
                readabilityResult: currentReadabilityResult,
                readabilityAnalysis: currentReadabilityAnalysis,
                element: element,
                context: monitoredContext,
                sourceText: lastAnalyzedText
            )
        }
    }
}
