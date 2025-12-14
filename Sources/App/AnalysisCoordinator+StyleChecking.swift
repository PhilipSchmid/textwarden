//
//  AnalysisCoordinator+StyleChecking.swift
//  TextWarden
//
//  Style checking and performance optimization functionality extracted from AnalysisCoordinator.
//  Handles Foundation Models-based style analysis, AI-enhanced readability suggestions, and style caching.
//

import Foundation
import AppKit
@preconcurrency import ApplicationServices
import FoundationModels

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

        // Calculate changed region using safe index operations
        guard let changeStart = newText.index(newText.startIndex, offsetBy: prefixLength, limitedBy: newText.endIndex),
              let changeEnd = newText.index(newText.endIndex, offsetBy: -suffixLength, limitedBy: newText.startIndex),
              changeStart <= changeEnd else {
            return nil
        }

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

    /// Compute a cache key for style analysis based on text content, style, and temperature preset
    /// Uses a hash to keep keys short while being collision-resistant
    /// Includes temperature preset so changing it triggers re-analysis of the same text
    func computeStyleCacheKey(text: String) -> String {
        let style = userPreferences.selectedWritingStyle
        let temperaturePreset = userPreferences.styleTemperaturePreset
        let combined = "\(text.hashValue)_\(style)_fm_\(temperaturePreset)"
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
        Logger.info("AnalysisCoordinator: runManualStyleCheck() triggered", category: Logger.analysis)

        // Get current monitored element and context
        guard let element = textMonitor.monitoredElement,
              let context = monitoredContext else {
            Logger.warning("AnalysisCoordinator: No monitored element for manual style check", category: Logger.analysis)
            return
        }

        // Check if Foundation Models is available (requires macOS 26+)
        guard #available(macOS 26.0, *) else {
            Logger.warning("AnalysisCoordinator: Foundation Models requires macOS 26+", category: Logger.analysis)
            return
        }

        runManualStyleCheckWithFM(element: element, context: context)
    }

    /// Internal implementation of manual style check using Foundation Models
    @available(macOS 26.0, *)
    private func runManualStyleCheckWithFM(element: AXUIElement, context: ApplicationContext) {
        // Create engine on demand
        let fmEngine = FoundationModelsEngine()
        fmEngine.checkAvailability()

        guard fmEngine.status.isAvailable else {
            Logger.warning("AnalysisCoordinator: Foundation Models not available: \(fmEngine.status.userMessage)", category: Logger.analysis)
            return
        }

        // Check for selected text first - if user has text selected, only analyze that
        // Otherwise fall back to analyzing all text
        let selection = selectedText()
        let isSelectionMode = selection != nil

        // Always capture full text for invalidation tracking
        guard let fullText = currentText(), !fullText.isEmpty else {
            Logger.warning("AnalysisCoordinator: No text available for manual style check", category: Logger.analysis)
            return
        }

        // Text to analyze is either the selection or the full text
        let text = selection ?? fullText

        if isSelectionMode {
            Logger.info("AnalysisCoordinator: Manual style check - analyzing selected text (\(text.count) chars)", category: Logger.analysis)
        }

        let styleName = userPreferences.selectedWritingStyle
        let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default

        // Check cache first - instant results if text hasn't changed
        // Note: Cache is keyed by analyzed text, but we also need full text to match for validity
        let cacheKey = computeStyleCacheKey(text: text)
        if let cached = styleCache[cacheKey], fullText == styleAnalysisSourceText {
            Logger.info("AnalysisCoordinator: Manual style check - using cached results (\(cached.count) suggestions)", category: Logger.analysis)

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

        // Cache miss - run Foundation Models analysis
        Logger.debug("AnalysisCoordinator: Manual style check - cache miss, running Foundation Models analysis", category: Logger.analysis)

        // Set flag to prevent regular analysis from hiding indicator
        isManualStyleCheckActive = true

        // Show spinning indicator immediately
        floatingIndicator.showStyleCheckInProgress(element: element, context: context)

        // Capture fullText for setting styleAnalysisSourceText when analysis completes
        let capturedFullText = fullText

        // Capture UserPreferences values on main thread before async dispatch
        let temperaturePresetName = userPreferences.styleTemperaturePreset
        let temperaturePreset = StyleTemperaturePreset(rawValue: temperaturePresetName) ?? .balanced

        // Get custom vocabulary for context
        let vocabulary = customVocabulary.allWords()

        // Run style analysis using Foundation Models
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            let segmentContent = text

            Logger.info("AnalysisCoordinator: Running Foundation Models style analysis on \(segmentContent.count) chars", category: Logger.analysis)

            let startTime = Date()

            do {
                let suggestions = try await fmEngine.analyzeStyle(
                    segmentContent,
                    style: style,
                    temperaturePreset: temperaturePreset,
                    customVocabulary: vocabulary
                )

                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

                Logger.info("AnalysisCoordinator: Foundation Models analysis completed in \(latencyMs)ms, \(suggestions.count) suggestions", category: Logger.analysis)

                // Update statistics
                self.statistics.recordStyleSuggestions(
                    count: suggestions.count,
                    latencyMs: Double(latencyMs),
                    modelId: "apple-foundation-models",
                    preset: temperaturePresetName
                )

                self.currentStyleSuggestions = suggestions
                self.styleAnalysisSourceText = capturedFullText

                // Cache the results for instant access next time
                self.styleCache[cacheKey] = suggestions
                self.styleCacheMetadata[cacheKey] = StyleCacheMetadata(
                    lastAccessed: Date(),
                    style: styleName
                )
                self.evictStyleCacheIfNeeded()

                // Update indicator to show results (checkmark first, then transition)
                self.floatingIndicator.showStyleSuggestionsReady(
                    count: suggestions.count,
                    styleSuggestions: suggestions
                )

                // Clear the flag after the checkmark display period
                DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.aiInferenceRetryDelay) { [weak self] in
                    self?.isManualStyleCheckActive = false
                }

                Logger.info("AnalysisCoordinator: Manual style check - showing \(suggestions.count) suggestions (cached for next time)", category: Logger.analysis)

            } catch {
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

                Logger.warning("AnalysisCoordinator: Foundation Models analysis failed after \(latencyMs)ms: \(error)", category: Logger.analysis)

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
            }
        }
    }

    /// Current text from monitored element
    private func currentText() -> String? {
        guard let element = textMonitor.monitoredElement else { return nil }

        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)

        guard result == .success, let value = valueRef as? String else {
            return nil
        }

        return value
    }

    /// Currently selected text from monitored element, if any
    /// Returns nil if no text is selected (cursor only) or if selection cannot be retrieved
    private func selectedText() -> String? {
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

            // Extract the sentence text using safe index operations
            let start = error.start
            let end = error.end

            guard start >= 0, start < end,
                  let startIndex = sourceText.index(sourceText.startIndex, offsetBy: start, limitedBy: sourceText.endIndex),
                  let endIndex = sourceText.index(sourceText.startIndex, offsetBy: end, limitedBy: sourceText.endIndex),
                  startIndex <= endIndex else {
                continue
            }

            let sentence = String(sourceText[startIndex..<endIndex])

            // Check if we have a cached AI suggestion (thread-safe via AIRephraseCache)
            if let cachedRephrase = aiRephraseCache.get(sentence) {
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
        let styleCheckingEnabled = userPreferences.enableStyleChecking
        let llmInitialized = llmEngine.isInitialized
        let modelLoaded = llmEngine.isModelLoaded()

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

        // Capture LLM engine reference before async dispatch
        let llmEngineRef = llmEngine

        // Process each readability error asynchronously
        styleAnalysisQueue.async { [weak self] in
            guard let self = self else { return }

            var enhancedErrors: [GrammarErrorModel] = []

            for error in readabilityErrorsWithoutSuggestions {
                // Extract the problematic sentence from source text using safe index operations
                let start = error.start
                let end = error.end

                guard start >= 0, start < end,
                      let startIndex = sourceText.index(sourceText.startIndex, offsetBy: start, limitedBy: sourceText.endIndex),
                      let endIndex = sourceText.index(sourceText.startIndex, offsetBy: end, limitedBy: sourceText.endIndex),
                      startIndex <= endIndex else {
                    Logger.warning("AnalysisCoordinator: Invalid error range for AI enhancement", category: Logger.llm)
                    continue
                }

                let sentence = String(sourceText[startIndex..<endIndex])

                // Check AI rephrase cache first (thread-safe via AIRephraseCache)
                var rephrased = self.aiRephraseCache.get(sentence)

                if rephrased != nil {
                    Logger.info("AnalysisCoordinator: Using cached AI rephrase for sentence of length \(sentence.count)", category: Logger.llm)
                } else {
                    Logger.debug("AnalysisCoordinator: Generating AI rephrase for sentence of length \(sentence.count)", category: Logger.llm)

                    // Generate AI suggestion
                    rephrased = llmEngineRef.rephraseSentence(sentence)

                    // Cache the result (thread-safe, handles LRU eviction internally)
                    if let newRephrase = rephrased {
                        aiRephraseCache.set(sentence, value: newRephrase)
                        Logger.debug("AnalysisCoordinator: Cached AI rephrase (cache size: \(aiRephraseCache.count))", category: Logger.llm)
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
