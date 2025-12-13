//
//  AnalysisCoordinator+StyleChecking.swift
//  TextWarden
//
//  Style checking and performance optimization functionality extracted from AnalysisCoordinator.
//  Handles LLM-based style analysis, AI-enhanced readability suggestions, and style caching.
//

import Foundation
import AppKit
@preconcurrency import ApplicationServices

// MARK: - Performance Optimizations (User Story 4)

extension AnalysisCoordinator {
    /// Find changed region using text diffing
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

    /// Detect sentence boundaries for context-aware analysis
    func detectSentenceBoundaries(in text: String, around range: Range<String.Index>) -> Range<String.Index> {
        let sentenceTerminators = CharacterSet(charactersIn: ".!?")

        // Find sentence start (search backward for sentence terminator)
        var sentenceStart = range.lowerBound
        var searchIndex = sentenceStart

        while searchIndex > text.startIndex {
            searchIndex = text.index(before: searchIndex)
            let char = text[searchIndex]

            if let firstScalar = char.unicodeScalars.first,
               sentenceTerminators.contains(firstScalar) {
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

            if let firstScalar = char.unicodeScalars.first,
               sentenceTerminators.contains(firstScalar) {
                // Include the terminator
                sentenceEnd = text.index(after: searchIndex)
                break
            }

            searchIndex = text.index(after: searchIndex)
        }

        return sentenceStart..<sentenceEnd
    }

    /// Merge new analysis results with cached results
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

    /// Check if edit is large enough to invalidate cache
    func isLargeEdit(oldText: String, newText: String) -> Bool {
        let diff = abs(newText.count - oldText.count)

        // Consider large if >1000 chars changed (copy/paste scenario)
        return diff > 1000
    }

    /// Purge expired cache entries
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

    /// Evict least recently used cache entries
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
    func updateErrorCache(for segment: TextSegment, with errors: [GrammarErrorModel]) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.aiInferenceRetryDelay) { [weak self] in
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

        // Capture UserPreferences values on main thread before async dispatch
        let modelId = UserPreferences.shared.selectedModelId
        let preset = UserPreferences.shared.styleInferencePreset
        let confidenceThreshold = Float(UserPreferences.shared.styleConfidenceThreshold)

        // Run style analysis in background
        styleAnalysisQueue.async { [weak self] in
            guard self != nil else { return }

            let segmentContent = text

            Logger.info("AnalysisCoordinator: Running manual style analysis on \(segmentContent.count) chars", category: Logger.llm)

            let startTime = Date()
            let styleResult = LLMEngine.shared.analyzeStyle(segmentContent, style: style)
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

            Logger.info("AnalysisCoordinator: Manual style check completed in \(latencyMs)ms, \(styleResult.suggestions.count) suggestions", category: Logger.llm)

            // Update statistics with model and preset context (dispatch to main since UserStatistics is @MainActor)
            DispatchQueue.main.async {
                UserStatistics.shared.recordStyleSuggestions(
                    count: styleResult.suggestions.count,
                    latencyMs: Double(latencyMs),
                    modelId: modelId,
                    preset: preset
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if !styleResult.isError {
                    let threshold = confidenceThreshold
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

                    // Clear the flag after the checkmark display period
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.aiInferenceRetryDelay) { [weak self] in
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

                    // Clear the flag after the checkmark display period
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.aiInferenceRetryDelay) { [weak self] in
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
    func enhanceErrorsWithCachedAI(
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

            // Check if we have a cached AI suggestion (thread-safe access)
            let cachedRephrase = aiRephraseCacheQueue.sync { aiRephraseCache[sentence] }
            if let cachedRephrase = cachedRephrase {
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
    func enhanceReadabilityErrorsWithAI(
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

                // Access cache on dedicated queue to avoid race conditions
                aiRephraseCacheQueue.sync {
                    rephrased = self.aiRephraseCache[sentence]
                }

                if rephrased != nil {
                    Logger.info("AnalysisCoordinator: Using cached AI rephrase for sentence of length \(sentence.count)", category: Logger.llm)
                } else {
                    Logger.debug("AnalysisCoordinator: Generating AI rephrase for sentence of length \(sentence.count)", category: Logger.llm)

                    // Generate AI suggestion
                    rephrased = LLMEngine.shared.rephraseSentence(sentence)

                    // Cache the result on dedicated queue
                    if let newRephrase = rephrased {
                        aiRephraseCacheQueue.sync {
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
struct CacheMetadata {
    let lastAccessed: Date
    let documentSize: Int
}

/// Metadata for style cache entries
struct StyleCacheMetadata {
    let lastAccessed: Date
    let style: String // The writing style used for this analysis
}
