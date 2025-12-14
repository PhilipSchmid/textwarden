//
//  AnalysisCoordinator+GrammarAnalysis.swift
//  TextWarden
//
//  Grammar analysis functionality extracted from AnalysisCoordinator.
//  Handles text analysis, Harper grammar engine integration, and LLM style analysis dispatch.
//

import Foundation
import AppKit
@preconcurrency import ApplicationServices

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
        let enableSentenceStartCapitalization: Bool
    }

    /// Capture grammar preferences on main thread before async dispatch
    func captureGrammarConfig() -> GrammarConfig {
        GrammarConfig(
            dialect: UserPreferences.shared.selectedDialect,
            enableInternetAbbrev: UserPreferences.shared.enableInternetAbbreviations,
            enableGenZSlang: UserPreferences.shared.enableGenZSlang,
            enableITTerminology: UserPreferences.shared.enableITTerminology,
            enableBrandNames: UserPreferences.shared.enableBrandNames,
            enablePersonNames: UserPreferences.shared.enablePersonNames,
            enableLastNames: UserPreferences.shared.enableLastNames,
            enableLanguageDetection: UserPreferences.shared.enableLanguageDetection,
            excludedLanguages: Array(UserPreferences.shared.excludedLanguages.map { UserPreferences.languageCode(for: $0) }),
            enableSentenceStartCapitalization: UserPreferences.shared.enableSentenceStartCapitalization
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
        let dialect = UserPreferences.shared.selectedDialect
        let enableInternetAbbrev = UserPreferences.shared.enableInternetAbbreviations
        let enableGenZSlang = UserPreferences.shared.enableGenZSlang
        let enableITTerminology = UserPreferences.shared.enableITTerminology
        let enableBrandNames = UserPreferences.shared.enableBrandNames
        let enablePersonNames = UserPreferences.shared.enablePersonNames
        let enableLastNames = UserPreferences.shared.enableLastNames
        let enableLanguageDetection = UserPreferences.shared.enableLanguageDetection
        let excludedLanguages = Array(UserPreferences.shared.excludedLanguages.map { UserPreferences.languageCode(for: $0) })
        let enableSentenceStartCapitalization = UserPreferences.shared.enableSentenceStartCapitalization

        // Simplified: For large docs, still analyze full text but async
        // Full incremental diff would require text diffing algorithm
        analysisQueue.async { [weak self] in
            guard let self = self else { return }

            let result = GrammarEngine.shared.analyzeText(
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
                enableSentenceStartCapitalization: enableSentenceStartCapitalization
            )

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
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

    // MARK: - Grammar Analysis Helpers

    /// Run grammar analysis asynchronously
    func runGrammarAnalysis(
        segment: TextSegment,
        text: String,
        config: GrammarConfig,
        element: AXUIElement?
    ) {
        analysisQueue.async { [weak self] in
            guard let self = self else { return }

            Logger.debug("AnalysisCoordinator: Calling Harper grammar engine...", category: Logger.analysis)

            let grammarResult = GrammarEngine.shared.analyzeText(
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
                enableSentenceStartCapitalization: config.enableSentenceStartCapitalization
            )

            Logger.debug("AnalysisCoordinator: Harper returned \(grammarResult.errors.count) error(s)", category: Logger.analysis)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.handleGrammarResults(
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

        UserStatistics.shared.recordDetailedAnalysisSession(
            wordsProcessed: wordCount,
            errorsFound: result.errors.count,
            bundleIdentifier: monitoredContext?.bundleIdentifier,
            categoryBreakdown: categoryBreakdown,
            latencyMs: Double(result.analysisTimeMs)
        )

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
            let wordCount = trimmed.split(separator: " ").filter { !$0.isEmpty }.count
            if wordCount >= minWords {
                return true
            }
        }

        return false
    }

    // MARK: - Style Analysis Helpers

    /// Check if auto style checking should run
    func shouldRunAutoStyleChecking() -> Bool {
        let styleCheckingEnabled = UserPreferences.shared.enableStyleChecking
        let autoStyleChecking = UserPreferences.shared.autoStyleChecking
        let llmInitialized = LLMEngine.shared.isInitialized
        let modelLoaded = LLMEngine.shared.isModelLoaded()
        let loadedModelId = LLMEngine.shared.getLoadedModelId()
        let shouldRun = styleCheckingEnabled && autoStyleChecking && llmInitialized && modelLoaded

        Logger.info("AnalysisCoordinator: Style check eligibility - enabled=\(styleCheckingEnabled), auto=\(autoStyleChecking), llmInit=\(llmInitialized), modelLoaded=\(modelLoaded), modelId='\(loadedModelId)', willRun=\(shouldRun)", category: Logger.llm)
        return shouldRun
    }

    /// Run debounced style analysis
    func runDebouncedStyleAnalysis(text: String) {
        let minWords = UserPreferences.shared.styleMinSentenceWords
        guard containsSentenceWithMinWords(text, minWords: minWords) else {
            Logger.debug("AnalysisCoordinator: No sentence with \(minWords)+ words - skipping style", category: Logger.llm)
            return
        }

        styleAnalysisGeneration &+= 1
        let currentGeneration = styleAnalysisGeneration

        styleDebounceTimer?.invalidate()
        styleDebounceTimer = nil

        // Check cache first
        let cacheKey = computeStyleCacheKey(text: text)
        if let cached = styleCache[cacheKey] {
            Logger.debug("AnalysisCoordinator: Using cached style results (\(cached.count) suggestions)", category: Logger.analysis)
            currentStyleSuggestions = cached
            styleAnalysisSourceText = text
            return
        }

        // Start debounce timer
        Logger.debug("AnalysisCoordinator: Style analysis debounced - waiting \(styleDebounceDelay)s", category: Logger.llm)

        styleDebounceTimer = Timer.scheduledTimer(withTimeInterval: styleDebounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      currentGeneration == self.styleAnalysisGeneration else {
                    Logger.debug("AnalysisCoordinator: Style debounce skipped - generation mismatch", category: Logger.llm)
                    return
                }

                Logger.info("AnalysisCoordinator: Style debounce complete - queuing LLM (gen=\(currentGeneration))", category: Logger.llm)
                self.executeLLMStyleAnalysis(
                    text: text,
                    cacheKey: cacheKey,
                    generation: currentGeneration
                )
            }
        }
    }

    /// Execute LLM style analysis on background queue
    func executeLLMStyleAnalysis(text: String, cacheKey: String, generation: UInt64) {
        let styleName = UserPreferences.shared.selectedWritingStyle
        let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default
        let confidenceThreshold = Float(UserPreferences.shared.styleConfidenceThreshold)

        styleAnalysisQueue.async { [weak self] in
            guard self != nil else { return }

            Logger.info("AnalysisCoordinator: Starting LLM style analysis (gen=\(generation))...", category: Logger.llm)
            let styleResult = LLMEngine.shared.analyzeStyle(text, style: style)
            Logger.debug("AnalysisCoordinator: LLM returned \(styleResult.suggestions.count) suggestion(s)", category: Logger.analysis)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.handleStyleResults(
                    styleResult,
                    text: text,
                    cacheKey: cacheKey,
                    generation: generation,
                    styleName: styleName,
                    confidenceThreshold: confidenceThreshold
                )
            }
        }
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
                element: element,
                context: monitoredContext,
                sourceText: lastAnalyzedText
            )
        }
    }
}
