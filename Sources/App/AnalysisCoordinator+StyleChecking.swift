//
//  AnalysisCoordinator+StyleChecking.swift
//  TextWarden
//
//  Style checking and performance optimization functionality extracted from AnalysisCoordinator.
//  Handles Apple Intelligence style analysis, AI-enhanced readability suggestions, and style caching.
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

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

        while prefixLength < minLength, oldChars[prefixLength] == newChars[prefixLength] {
            prefixLength += 1
        }

        // Find common suffix
        var suffixLength = 0
        let oldSuffixStart = oldChars.count - 1
        let newSuffixStart = newChars.count - 1

        while suffixLength < minLength - prefixLength,
              oldChars[oldSuffixStart - suffixLength] == newChars[newSuffixStart - suffixLength]
        {
            suffixLength += 1
        }

        // Calculate changed region using safe index operations
        guard let changeStart = newText.index(newText.startIndex, offsetBy: prefixLength, limitedBy: newText.endIndex),
              let changeEnd = newText.index(newText.endIndex, offsetBy: -suffixLength, limitedBy: newText.startIndex),
              changeStart <= changeEnd
        else {
            return nil
        }

        return changeStart ..< changeEnd
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
               sentenceTerminators.contains(firstScalar)
            {
                // Move past the terminator and any whitespace
                sentenceStart = text.index(after: searchIndex)
                while sentenceStart < text.endIndex, text[sentenceStart].isWhitespace {
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
               sentenceTerminators.contains(firstScalar)
            {
                // Include the terminator
                sentenceEnd = text.index(after: searchIndex)
                break
            }

            searchIndex = text.index(after: searchIndex)
        }

        return sentenceStart ..< sentenceEnd
    }

    /// Merge new analysis results with cached results
    func mergeResults(new: [GrammarErrorModel], cached: [GrammarErrorModel], changedRange: Range<Int>) -> [GrammarErrorModel] {
        var merged: [GrammarErrorModel] = []

        // Keep cached errors outside changed range
        for error in cached {
            let errorRange = error.start ..< error.end
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
        for i in 0 ..< toRemove {
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

        for i in 0 ..< toRemove {
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
        Logger.debug("Style check triggered", category: Logger.llm)

        // Get current monitored element and context
        guard let element = textMonitor.monitoredElement,
              let context = monitoredContext
        else {
            Logger.debug("Style check: No monitored element", category: Logger.llm)
            return
        }

        // Check if Apple Intelligence is available (requires macOS 26+)
        guard #available(macOS 26.0, *) else {
            Logger.warning("Apple Intelligence: Requires macOS 26 or later", category: Logger.llm)
            return
        }

        runManualStyleCheckWithFM(element: element, context: context)
    }

    /// Internal implementation of manual style check using Apple Intelligence
    @available(macOS 26.0, *)
    private func runManualStyleCheckWithFM(element: AXUIElement, context: ApplicationContext) {
        // Create engine on demand
        let fmEngine = FoundationModelsEngine()
        fmEngine.checkAvailability()

        guard fmEngine.status.isAvailable else {
            Logger.warning("Apple Intelligence: Not available - \(fmEngine.status.userMessage)", category: Logger.llm)
            return
        }

        // Check for selected text first - if user has text selected, only analyze that
        // Otherwise fall back to analyzing all text
        let selection = selectedText()
        let isSelectionMode = selection != nil

        // Always capture full text for invalidation tracking
        guard let fullText = currentText(), !fullText.isEmpty else {
            Logger.debug("Style check: No text available", category: Logger.llm)
            return
        }

        // Text to analyze is either the selection or the full text
        let text = selection ?? fullText

        if isSelectionMode {
            Logger.debug("Style check: Analyzing selection (\(text.count) chars)", category: Logger.llm)
        }

        let styleName = userPreferences.selectedWritingStyle
        let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default

        // Check cache first - instant results if text hasn't changed
        // Note: Cache is keyed by analyzed text, but we also need full text to match for validity
        let cacheKey = computeStyleCacheKey(text: text)
        if let cached = styleCache[cacheKey], fullText == styleAnalysisSourceText {
            // Get style sensitivity from user preferences
            let sensitivityName = userPreferences.styleSensitivity
            let sensitivity = StyleSensitivity(rawValue: sensitivityName) ?? .balanced

            // Filter using SuggestionTracker (unified loop prevention)
            // Manual style check shows all suggestions that pass basic filters
            var filteredCached = cached.filter { suggestion in
                suggestionTracker.shouldShowStyleSuggestion(
                    originalText: suggestion.originalText,
                    confidence: suggestion.confidence,
                    impact: suggestion.impact,
                    source: "appleIntelligence",
                    isManualCheck: true,
                    sensitivity: sensitivity
                )
            }

            // Filter out suggestions that overlap with grammar errors (to avoid duplicating spelling/grammar fixes)
            filteredCached = filterStyleSuggestionsNotOverlappingGrammarErrors(filteredCached, grammarErrors: currentErrors)

            Logger.debug("Style check: Cache hit, \(cached.count) suggestion(s), \(filteredCached.count) after filtering", category: Logger.llm)

            // Update cache access time
            styleCacheMetadata[cacheKey] = StyleCacheMetadata(
                lastAccessed: Date(),
                style: styleName
            )

            // Set flag and show results immediately
            isManualStyleCheckActive = true
            currentStyleSuggestions = filteredCached
            styleAnalysisSourceText = fullText

            // Show checkmark and results immediately (no spinning needed)
            floatingIndicator.showStyleSuggestionsReady(
                count: filteredCached.count,
                styleSuggestions: filteredCached
            )

            // Clear the flag after the checkmark display period
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.aiInferenceRetryDelay) { [weak self] in
                self?.isManualStyleCheckActive = false
            }

            return
        }

        // Cache miss - run Apple Intelligence analysis
        Logger.debug("Style check: Cache miss, running analysis", category: Logger.llm)

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

        // Capture readability settings for simplification
        let readabilityEnabled = userPreferences.readabilityEnabled
        let targetAudienceName = userPreferences.selectedTargetAudience
        let targetAudience = TargetAudience(fromDisplayName: targetAudienceName) ?? .general
        let readabilityAnalysis = currentReadabilityAnalysis

        // Run style analysis using Apple Intelligence
        Task { @MainActor [weak self] in
            guard let self else { return }

            let segmentContent = text

            Logger.debug("Style check: Starting analysis (\(segmentContent.count) chars)", category: Logger.llm)

            let startTime = Date()

            do {
                let suggestions = try await fmEngine.analyzeStyle(
                    segmentContent,
                    style: style,
                    temperaturePreset: temperaturePreset,
                    customVocabulary: vocabulary
                )

                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

                // Get style sensitivity from user preferences
                let sensitivityName = self.userPreferences.styleSensitivity
                let sensitivity = StyleSensitivity(rawValue: sensitivityName) ?? .balanced

                // Filter using SuggestionTracker (unified loop prevention)
                // Manual style check shows all suggestions that pass basic filters
                var filteredSuggestions = suggestions.filter { suggestion in
                    self.suggestionTracker.shouldShowStyleSuggestion(
                        originalText: suggestion.originalText,
                        confidence: suggestion.confidence,
                        impact: suggestion.impact,
                        source: "appleIntelligence",
                        isManualCheck: true,
                        sensitivity: sensitivity
                    )
                }

                // Filter out suggestions that overlap with grammar errors (to avoid duplicating spelling/grammar fixes)
                let beforeGrammarFilter = filteredSuggestions.count
                filteredSuggestions = filterStyleSuggestionsNotOverlappingGrammarErrors(filteredSuggestions, grammarErrors: currentErrors)
                let removedByGrammarFilter = beforeGrammarFilter - filteredSuggestions.count

                Logger.debug("Style check: Completed in \(latencyMs)ms, \(suggestions.count) suggestion(s), \(filteredSuggestions.count) after filtering (\(removedByGrammarFilter) overlapped grammar errors)", category: Logger.llm)

                // Update statistics
                statistics.recordStyleSuggestions(
                    count: filteredSuggestions.count,
                    latencyMs: Double(latencyMs),
                    modelId: "apple-foundation-models",
                    preset: temperaturePresetName
                )

                currentStyleSuggestions = filteredSuggestions
                styleAnalysisSourceText = capturedFullText

                // Generate readability simplifications for complex sentences (if enabled)
                if readabilityEnabled,
                   let analysis = readabilityAnalysis,
                   !analysis.complexSentences.isEmpty
                {
                    Logger.debug("Style check: Generating simplifications for \(analysis.complexSentences.count) complex sentence(s)", category: Logger.llm)

                    // Process up to 3 complex sentences
                    for sentence in analysis.complexSentences.prefix(3) {
                        do {
                            let alternatives = try await fmEngine.simplifySentence(
                                sentence.sentence,
                                targetAudience: targetAudience,
                                writingStyle: style
                            )

                            // Create a StyleSuggestionModel for the first alternative only
                            // (user can retry for more alternatives)
                            // Only store suggestion if we got a non-empty alternative
                            if let firstAlternative = alternatives.first, !firstAlternative.isEmpty {
                                // Calculate readability score for the SIMPLIFIED text, not the original
                                let simplifiedScore = Int(ReadabilityCalculator.shared.fleschReadingEaseForSentence(firstAlternative) ?? 0)
                                Logger.debug("Style check: Simplified text score: \(simplifiedScore) (original: \(sentence.score))", category: Logger.llm)

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
                                    readabilityScore: simplifiedScore,
                                    targetAudience: targetAudience.displayName
                                )

                                // Remove any existing suggestion for the same original text range
                                // This ensures only one suggestion per sentence (better UX)
                                currentStyleSuggestions.removeAll { existing in
                                    existing.originalStart == suggestion.originalStart &&
                                        existing.originalEnd == suggestion.originalEnd
                                }
                                currentStyleSuggestions.append(suggestion)
                            }

                            Logger.debug("Style check: Generated simplification for sentence at \(sentence.range.location)", category: Logger.llm)

                        } catch {
                            Logger.warning("Style check: Failed to simplify sentence - \(error.localizedDescription)", category: Logger.llm)
                            // Continue with other sentences even if one fails
                        }
                    }
                }

                // Cache the combined results (style + readability) - filtering happens at display time
                styleCache[cacheKey] = currentStyleSuggestions
                styleCacheMetadata[cacheKey] = StyleCacheMetadata(
                    lastAccessed: Date(),
                    style: styleName
                )
                evictStyleCacheIfNeeded()

                // Update indicator to show results (checkmark first, then transition)
                // Use currentStyleSuggestions which includes both style AND readability suggestions
                floatingIndicator.showStyleSuggestionsReady(
                    count: currentStyleSuggestions.count,
                    styleSuggestions: currentStyleSuggestions
                )

                // Clear the flag after the checkmark display period
                DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.aiInferenceRetryDelay) { [weak self] in
                    self?.isManualStyleCheckActive = false
                }

            } catch {
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

                Logger.warning("Style check: Failed after \(latencyMs)ms", category: Logger.llm)

                // Error occurred - still show checkmark to indicate completion, then hide
                currentStyleSuggestions = []

                // Show checkmark even for errors so user knows check completed
                floatingIndicator.showStyleSuggestionsReady(
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

    /// Regenerate a style suggestion to get an alternative
    @available(macOS 26.0, *)
    func regenerateStyleSuggestion(_ suggestion: StyleSuggestionModel) async -> StyleSuggestionModel? {
        Logger.debug("AnalysisCoordinator: Regenerating suggestion for text (\(suggestion.originalText.count) chars, readability: \(suggestion.isReadabilitySuggestion))", category: Logger.analysis)

        // Create engine on demand
        let fmEngine = FoundationModelsEngine()
        fmEngine.checkAvailability()

        guard fmEngine.status.isAvailable else {
            Logger.warning("Apple Intelligence: Not available for regeneration - \(fmEngine.status.userMessage)", category: Logger.llm)
            return nil
        }

        do {
            // Handle readability suggestions differently - use simplifySentence instead of style regeneration
            if suggestion.isReadabilitySuggestion {
                let targetAudience = TargetAudience(fromDisplayName: suggestion.targetAudience ?? "General") ?? .general

                Logger.debug("AnalysisCoordinator: Using simplifySentence for readability regeneration", category: Logger.analysis)

                let alternatives = try await fmEngine.simplifySentence(
                    suggestion.originalText,
                    targetAudience: targetAudience,
                    writingStyle: suggestion.style,
                    previousSuggestion: suggestion.suggestedText
                )

                // Pick the first alternative that's different from the current suggestion
                if let newAlternative = alternatives.first(where: { $0 != suggestion.suggestedText }) ?? alternatives.first {
                    let newSuggestion = StyleSuggestionModel(
                        id: suggestion.id,
                        originalStart: suggestion.originalStart,
                        originalEnd: suggestion.originalEnd,
                        originalText: suggestion.originalText,
                        suggestedText: newAlternative,
                        explanation: "Simplified for \(targetAudience.displayName) audience",
                        confidence: suggestion.confidence,
                        style: suggestion.style,
                        isReadabilitySuggestion: true,
                        readabilityScore: suggestion.readabilityScore,
                        targetAudience: suggestion.targetAudience
                    )

                    Logger.debug("AnalysisCoordinator: Readability regeneration successful - new suggestion: '\(newSuggestion.suggestedText.prefix(30))...'", category: Logger.analysis)

                    // Update the tracking
                    if let index = currentStyleSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
                        currentStyleSuggestions[index] = newSuggestion
                    }

                    return newSuggestion
                } else {
                    Logger.debug("AnalysisCoordinator: Readability regeneration returned no alternatives", category: Logger.analysis)
                    return nil
                }
            }

            // Regular style suggestion - use style regeneration
            let sourceText = !styleAnalysisSourceText.isEmpty ? styleAnalysisSourceText : (currentText() ?? suggestion.originalText)

            let newSuggestion = try await fmEngine.regenerateStyleSuggestion(
                originalText: sourceText,
                previousSuggestion: suggestion,
                style: suggestion.style,
                customVocabulary: Array(UserPreferences.shared.customDictionary)
            )

            if let newSuggestion {
                Logger.debug("AnalysisCoordinator: Regeneration successful - new suggestion: '\(newSuggestion.suggestedText.prefix(30))...'", category: Logger.analysis)

                // Update the tracking
                if let index = currentStyleSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    currentStyleSuggestions[index] = newSuggestion
                }
            } else {
                Logger.debug("AnalysisCoordinator: Regeneration returned no different suggestion", category: Logger.analysis)
            }

            return newSuggestion
        } catch {
            Logger.error("AnalysisCoordinator: Regeneration failed - \(error.localizedDescription)", category: Logger.analysis)
            return nil
        }
    }

    /// Currently selected text from monitored element, if any
    /// Returns nil if no text is selected (cursor only) or if selection cannot be retrieved
    private func selectedText() -> String? {
        guard let element = textMonitor.monitoredElement else { return nil }

        // First check if there's a selection range with non-zero length
        guard let range = AccessibilityBridge.getSelectedTextRange(element),
              range.length > 0
        else {
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
                  error.suggestions.isEmpty
            else {
                continue
            }

            // Extract the sentence text using safe index operations
            let start = error.start
            let end = error.end

            guard start >= 0, start < end,
                  let startIndex = sourceText.index(sourceText.startIndex, offsetBy: start, limitedBy: sourceText.endIndex),
                  let endIndex = sourceText.index(sourceText.startIndex, offsetBy: end, limitedBy: sourceText.endIndex),
                  startIndex <= endIndex
            else {
                continue
            }

            let sentence = String(sourceText[startIndex ..< endIndex])

            // Check if we have a cached AI suggestion (thread-safe via AIRephraseCache)
            if let cachedRephrase = aiRephraseCache.get(sentence) {
                Logger.debug("AI rephrase: Using cached result", category: Logger.llm)

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
    /// Note: Auto-enhancement is disabled. Users can manually trigger style checking via the popover.
    func enhanceReadabilityErrorsWithAI(
        errors _: [GrammarErrorModel],
        sourceText _: String,
        element _: AXUIElement?,
        segment _: TextSegment
    ) {
        // Auto AI enhancement for readability errors is disabled
        // Users can manually trigger style checking which uses FoundationModelsEngine
    }

    // MARK: - Style Suggestion Filtering

    /// Filter out style suggestions that overlap with existing grammar errors.
    /// This prevents duplicate suggestions where the style engine suggests fixing
    /// spelling/grammar issues that Harper has already flagged.
    func filterStyleSuggestionsNotOverlappingGrammarErrors(
        _ suggestions: [StyleSuggestionModel],
        grammarErrors: [GrammarErrorModel]
    ) -> [StyleSuggestionModel] {
        guard !grammarErrors.isEmpty else { return suggestions }

        return suggestions.filter { suggestion in
            // Check if this style suggestion overlaps with any grammar error
            let suggestionRange = suggestion.originalStart ..< suggestion.originalEnd

            for error in grammarErrors {
                let errorRange = error.start ..< error.end

                // Check for overlap
                if suggestionRange.overlaps(errorRange) {
                    Logger.debug("Style filter: Removing suggestion overlapping grammar error at \(error.start)-\(error.end)", category: Logger.llm)
                    return false
                }
            }

            return true
        }
    }

    /// Clean up stale readability suggestions that no longer correspond to complex sentences.
    /// Called when readability analysis completes with updated complex sentence list.
    func cleanupStaleReadabilitySuggestions(currentComplexRanges: [NSRange]) {
        let before = currentStyleSuggestions.count
        let readabilityBefore = currentStyleSuggestions.filter(\.isReadabilitySuggestion).count

        if currentComplexRanges.isEmpty {
            // No complex sentences - remove ALL readability suggestions
            currentStyleSuggestions.removeAll(where: \.isReadabilitySuggestion)
        } else {
            // Remove readability suggestions that don't match any current complex sentence range
            currentStyleSuggestions.removeAll { suggestion in
                guard suggestion.isReadabilitySuggestion else { return false }

                let suggestionRange = NSRange(location: suggestion.originalStart, length: suggestion.originalEnd - suggestion.originalStart)

                // Check if this suggestion's range matches any current complex sentence
                let hasMatchingComplexSentence = currentComplexRanges.contains { complexRange in
                    // Allow some tolerance for range matching (text might have shifted slightly)
                    complexRange.location == suggestionRange.location &&
                        abs(complexRange.length - suggestionRange.length) <= 2
                }

                return !hasMatchingComplexSentence
            }
        }

        let removed = before - currentStyleSuggestions.count
        if removed > 0 {
            Logger.debug("AnalysisCoordinator: Cleaned up \(removed) stale readability suggestions (\(readabilityBefore) before, \(currentComplexRanges.count) current complex sentences)", category: Logger.analysis)

            // Update the indicator to reflect the change
            if let element = textMonitor.monitoredElement {
                floatingIndicator.update(
                    errors: currentErrors,
                    styleSuggestions: currentStyleSuggestions,
                    readabilityResult: currentReadabilityResult,
                    readabilityAnalysis: currentReadabilityAnalysis,
                    element: element,
                    context: monitoredContext,
                    sourceText: lastAnalyzedText
                )
            }
        }
    }

    // MARK: - Text Generation Context

    /// Extract context for text generation from the current monitored element
    /// Uses windowed extraction for large documents to keep context manageable
    func extractGenerationContext() -> GenerationContext {
        guard let element = textMonitor.monitoredElement else {
            Logger.debug("AnalysisCoordinator: extractGenerationContext - no monitored element", category: Logger.analysis)
            return .empty
        }

        // Check for selected text first
        let selection = selectedText()
        if let selected = selection, !selected.isEmpty {
            Logger.debug("AnalysisCoordinator: extractGenerationContext - using selection (\(selected.count) chars)", category: Logger.analysis)
            return GenerationContext(
                selectedText: selected,
                surroundingText: currentText(),
                fullTextLength: currentText()?.count ?? 0,
                cursorPosition: nil,
                source: .selection
            )
        }

        // No selection - get text around cursor
        guard let fullText = currentText(), !fullText.isEmpty else {
            Logger.debug("AnalysisCoordinator: extractGenerationContext - no text available", category: Logger.analysis)
            return .empty
        }

        // Get cursor position
        let cursorPos = getCursorPosition(element: element) ?? 0

        // For small documents, use full text
        if fullText.count <= 2000 {
            Logger.debug("AnalysisCoordinator: extractGenerationContext - using full document (\(fullText.count) chars)", category: Logger.analysis)
            return GenerationContext(
                selectedText: nil,
                surroundingText: fullText,
                fullTextLength: fullText.count,
                cursorPosition: cursorPos,
                source: .documentStart
            )
        }

        // For large documents, extract window around cursor
        // 1000 chars before, 500 chars after
        let windowStart = max(0, cursorPos - 1000)
        let windowEnd = min(fullText.count, cursorPos + 500)

        // Safe index operations
        guard let startIdx = fullText.index(fullText.startIndex, offsetBy: windowStart, limitedBy: fullText.endIndex),
              let endIdx = fullText.index(fullText.startIndex, offsetBy: windowEnd, limitedBy: fullText.endIndex),
              startIdx < endIdx
        else {
            return GenerationContext(
                selectedText: nil,
                surroundingText: nil,
                fullTextLength: fullText.count,
                cursorPosition: cursorPos,
                source: .none
            )
        }

        let window = String(fullText[startIdx ..< endIdx])
        Logger.debug("AnalysisCoordinator: extractGenerationContext - using window (\(window.count) chars around cursor)", category: Logger.analysis)

        return GenerationContext(
            selectedText: nil,
            surroundingText: window,
            fullTextLength: fullText.count,
            cursorPosition: cursorPos,
            source: .cursorWindow
        )
    }

    /// Get cursor position from element
    private func getCursorPosition(element: AXUIElement) -> Int? {
        guard let range = AccessibilityBridge.getSelectedTextRange(element) else {
            return nil
        }
        return range.location
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
