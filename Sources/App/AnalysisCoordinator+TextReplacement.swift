//
//  AnalysisCoordinator+TextReplacement.swift
//  TextWarden
//
//  Text replacement functionality extracted from AnalysisCoordinator
//  Handles applying grammar suggestions to text via accessibility APIs or keyboard simulation
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation

// MARK: - Text Replacement

extension AnalysisCoordinator {
    /// Remove error from tracking and update UI immediately
    /// Called after successfully applying a suggestion to remove underlines
    /// Also adjusts positions of remaining errors to account for text length change
    /// - Parameters:
    ///   - error: The error that was fixed
    ///   - suggestion: The replacement text that was applied
    ///   - lengthDelta: The change in text length (suggestion.count - errorLength)
    func removeErrorAndUpdateUI(_ error: GrammarErrorModel, suggestion: String, lengthDelta: Int = 0) {
        Logger.debug("removeErrorAndUpdateUI: Removing error at \(error.start)-\(error.end), message: '\(error.message)', lengthDelta: \(lengthDelta)", category: Logger.analysis)

        // Log current errors for debugging position drift
        Logger.debug("removeErrorAndUpdateUI: currentErrors BEFORE removal (\(currentErrors.count) total):", category: Logger.analysis)
        for (i, err) in currentErrors.enumerated() {
            Logger.debug("  [\(i)] \(err.start)-\(err.end): '\(err.message)'", category: Logger.analysis)
        }

        // Remove the error from currentErrors
        // Primary match on position, fallback on message+lintId+category for exact same error
        let beforeCount = currentErrors.count
        currentErrors.removeAll { err in
            // Exact position match
            if err.start == error.start, err.end == error.end {
                Logger.debug("removeErrorAndUpdateUI: MATCH by position \(err.start)-\(err.end)", category: Logger.analysis)
                return true
            }
            // Exact content match (same error type at same position range length)
            // This handles cases where the error was identified by content rather than position
            if err.message == error.message,
               err.lintId == error.lintId,
               err.category == error.category,
               (err.end - err.start) == (error.end - error.start)
            {
                Logger.debug("removeErrorAndUpdateUI: MATCH by content (err at \(err.start)-\(err.end), target at \(error.start)-\(error.end))", category: Logger.analysis)
                return true
            }
            return false
        }
        let removedCount = beforeCount - currentErrors.count
        if removedCount == 0 {
            Logger.warning("removeErrorAndUpdateUI: NO MATCH FOUND! Looking for \(error.start)-\(error.end) '\(error.message)' (lintId: \(error.lintId), category: \(error.category))", category: Logger.analysis)
        } else {
            Logger.debug("removeErrorAndUpdateUI: Removed \(removedCount) error(s), \(currentErrors.count) remaining", category: Logger.analysis)
        }

        // Update currentSegment with the new text content
        // This is CRITICAL: the underline positions are calculated from currentSegment.content
        // If we don't update it, subsequent errors will have incorrect underline positions
        if let segment = currentSegment {
            var newContent = segment.content
            // Use TextIndexConverter to convert Harper's Unicode scalar indices to Swift String.Index
            // Harper uses Rust char indices (Unicode scalars), but Swift String uses grapheme clusters
            // Example: "👨‍👩‍👧" is 1 grapheme cluster but 7 Unicode scalars
            guard let startIdx = TextIndexConverter.scalarIndexToStringIndex(error.start, in: newContent),
                  let endIdx = TextIndexConverter.scalarIndexToStringIndex(error.end, in: newContent),
                  startIdx < endIdx
            else {
                Logger.warning("removeErrorAndUpdateUI: Invalid range for string replacement (error: \(error.start)-\(error.end), scalar count: \(newContent.unicodeScalars.count))", category: Logger.analysis)
                return
            }
            newContent.replaceSubrange(startIdx ..< endIdx, with: suggestion)
            currentSegment = segment.with(content: newContent)
            Logger.debug("removeErrorAndUpdateUI: Updated currentSegment content (new length: \(newContent.count))", category: Logger.analysis)
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

            // Also adjust readability analysis sentence positions
            // This prevents readability underlines from shifting after replacement
            if let analysis = currentReadabilityAnalysis {
                let adjustedSentences = analysis.sentenceResults.map { sentence -> SentenceReadabilityResult in
                    // Only adjust sentences that start after or at the replacement point
                    if sentence.range.location >= error.end {
                        let adjustedRange = NSRange(
                            location: sentence.range.location + lengthDelta,
                            length: sentence.range.length
                        )
                        return SentenceReadabilityResult(
                            sentence: sentence.sentence,
                            range: adjustedRange,
                            score: sentence.score,
                            wordCount: sentence.wordCount,
                            isComplex: sentence.isComplex,
                            targetAudience: sentence.targetAudience
                        )
                    }
                    // If replacement happened within this sentence, adjust the length
                    else if sentence.range.location < error.end,
                            sentence.range.location + sentence.range.length > error.start
                    {
                        let adjustedRange = NSRange(
                            location: sentence.range.location,
                            length: sentence.range.length + lengthDelta
                        )
                        return SentenceReadabilityResult(
                            sentence: sentence.sentence,
                            range: adjustedRange,
                            score: sentence.score,
                            wordCount: sentence.wordCount,
                            isComplex: sentence.isComplex,
                            targetAudience: sentence.targetAudience
                        )
                    }
                    return sentence
                }
                currentReadabilityAnalysis = TextReadabilityAnalysis(
                    overallResult: analysis.overallResult,
                    sentenceResults: adjustedSentences,
                    targetAudience: analysis.targetAudience
                )
                Logger.debug("removeErrorAndUpdateUI: Adjusted \(adjustedSentences.count) readability sentence positions", category: Logger.analysis)
            }
        }

        // Don't hide the popover here - let it manage its own visibility
        // The popover automatically advances to the next error or hides itself

        // Reset typing detector so underlines show immediately after replacement
        // (replacement triggers text changes which set isCurrentlyTyping=true)
        TypingDetector.shared.reset()

        // Update the overlay and indicator immediately
        // Pass isFromReplacementUI: true so this call isn't skipped during replacement mode
        let sourceText = currentSegment?.content ?? ""
        applyFilters(to: currentErrors, sourceText: sourceText, element: textMonitor.monitoredElement, isFromReplacementUI: true)

        // Sync popover's errors with our updated currentErrors
        // The popover and coordinator adjust positions independently during replacement,
        // which can cause them to get out of sync. This ensures they match.
        suggestionPopover.syncErrorsAfterReplacement(currentErrors)

        // Now re-sync the highlight with the (now correct) popover error
        if let currentPopoverError = suggestionPopover.currentError {
            Logger.debug("removeErrorAndUpdateUI: Setting highlight for error at \(currentPopoverError.start)-\(currentPopoverError.end)", category: Logger.analysis)
            errorOverlay.setLockedHighlight(for: currentPopoverError)
        } else {
            Logger.debug("removeErrorAndUpdateUI: No current popover error to highlight", category: Logger.analysis)
        }

        // Update lastAnalyzedText to reflect the replacement
        // This prevents validateCurrentText from thinking text changed (triggering re-analysis/hiding)
        // by computing what the new text should be after applying the replacement
        // Use TextIndexConverter for proper Unicode scalar → String.Index conversion
        if !lastAnalyzedText.isEmpty,
           let startIndex = TextIndexConverter.scalarIndexToStringIndex(error.start, in: lastAnalyzedText),
           let endIndex = TextIndexConverter.scalarIndexToStringIndex(error.end, in: lastAnalyzedText),
           startIndex <= endIndex
        {
            var updatedText = lastAnalyzedText
            updatedText.replaceSubrange(startIndex ..< endIndex, with: suggestion)
            lastAnalyzedText = updatedText
            Logger.debug("removeErrorAndUpdateUI: Updated lastAnalyzedText to reflect replacement", category: Logger.analysis)
        }

        Logger.debug("removeErrorAndUpdateUI: UI updated, remaining errors: \(currentErrors.count)", category: Logger.analysis)
    }

    // MARK: - New Coordinator-Based Replacement

    /// Apply text replacement using the new TextReplacementCoordinator.
    /// This is the simplified, declarative approach based on app configuration.
    /// Currently used alongside the legacy method for incremental migration.
    @MainActor
    func applyReplacementViaCoordinator(for error: GrammarErrorModel, with suggestion: String) async -> Bool {
        Logger.debug("applyReplacementViaCoordinator called - error range: \(error.start)-\(error.end)", category: Logger.analysis)

        guard let element = textMonitor.monitoredElement else {
            Logger.debug("No monitored element for text replacement", category: Logger.analysis)
            return false
        }

        guard let context = monitoredContext else {
            Logger.debug("No monitored context for text replacement", category: Logger.analysis)
            return false
        }

        // Get current text from element
        var textRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef)
        guard textResult == .success, let currentText = textRef as? String else {
            Logger.debug("Could not get current text for replacement", category: Logger.analysis)
            return false
        }

        // Get app configuration
        let appConfig = appRegistry.configuration(for: context.bundleIdentifier)

        // Set replacement flag
        lastReplacementTime = Date()
        isApplyingReplacement = true
        defer { isApplyingReplacement = false }

        // Execute replacement via coordinator
        let result = await textReplacementCoordinator.replace(
            error: error,
            suggestion: suggestion,
            element: element,
            currentText: currentText,
            appConfig: appConfig
        )

        // Handle result
        switch result {
        case .success, .unverified:
            // Record statistics
            statistics.recordSuggestionApplied(category: error.category)

            // Calculate length delta for position adjustment
            let lengthDelta = TextReplacementCoordinator.lengthDelta(for: error, suggestion: suggestion)

            // Update UI and adjust positions
            removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)

            // Invalidate cache
            invalidateCacheAfterReplacement(at: error.start ..< error.end)

            return true

        case let .failed(error):
            Logger.warning("Replacement via coordinator failed: \(error)", category: Logger.analysis)
            return false
        }
    }

    // MARK: - Legacy Replacement Methods (to be removed after migration)

    /// Apply text replacement for error (async version)
    @MainActor
    func applyTextReplacementAsync(for error: GrammarErrorModel, with suggestion: String) async {
        Logger.debug("applyTextReplacementAsync called - error range: \(error.start)-\(error.end)", category: Logger.analysis)

        guard let element = textMonitor.monitoredElement else {
            Logger.debug("No monitored element for text replacement", category: Logger.analysis)
            return
        }

        Logger.debug("Have monitored element, context: \(monitoredContext?.applicationName ?? "nil")", category: Logger.analysis)

        lastReplacementTime = Date()
        isApplyingReplacement = true
        defer { isApplyingReplacement = false }

        // Use keyboard automation directly for known Electron apps
        if let context = monitoredContext, context.requiresKeyboardReplacement {
            Logger.debug("Detected Electron app (\(context.applicationName)) - using keyboard automation directly", category: Logger.analysis)
            await applyTextReplacementViaKeyboardAsync(for: error, with: suggestion, element: element)
            return
        }

        // Apple Mail: use WebKit-specific AXReplaceRangeWithText API
        if let context = monitoredContext {
            let appBehavior = AppBehaviorRegistry.shared.behavior(for: context.bundleIdentifier)
            if appBehavior.knownQuirks.contains(.usesMailReplaceRangeAPI) {
                Logger.debug("Detected Mail-style app - using WebKit-specific text replacement", category: Logger.analysis)
                await applyMailTextReplacementAsync(for: error, with: suggestion, element: element)
                return
            }
        }

        // Check if app config requires browser-style replacement (e.g., Pages, Word)
        // Some native apps report AX API success but don't actually change the text
        if let context = monitoredContext {
            let appConfig = appRegistry.configuration(for: context.bundleIdentifier)
            if appConfig.features.textReplacementMethod == .browserStyle {
                Logger.debug("App config requires browser-style replacement for \(context.applicationName)", category: Logger.analysis)
                await applyTextReplacementViaKeyboardAsync(for: error, with: suggestion, element: element)
                return
            }
        }

        // For native macOS apps, try AX API first (it's faster and preserves formatting)
        var textRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef)
        let currentText = (textResult == .success) ? (textRef as? String) : nil

        let utf16Location: Int
        let utf16Length: Int
        if let text = currentText {
            let utf16Range = TextIndexConverter.graphemeToUTF16Range(NSRange(location: error.start, length: error.end - error.start), in: text)
            utf16Location = utf16Range.location
            utf16Length = utf16Range.length
        } else {
            utf16Location = error.start
            utf16Length = error.end - error.start
        }

        var errorRange = CFRange(location: utf16Location, length: utf16Length)
        guard let rangeValue = AXValueCreate(.cfRange, &errorRange) else {
            Logger.debug("AXValueCreate failed, using keyboard fallback", category: Logger.analysis)
            await applyTextReplacementViaKeyboardAsync(for: error, with: suggestion, element: element)
            return
        }

        let selectError = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        if selectError != .success {
            Logger.debug("AX API selection failed (\(selectError.rawValue)), using keyboard fallback", category: Logger.analysis)
            await applyTextReplacementViaKeyboardAsync(for: error, with: suggestion, element: element)
            return
        }

        let replaceError = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, suggestion as CFTypeRef)
        if replaceError == .success {
            statistics.recordSuggestionApplied(category: error.category)
            invalidateCacheAfterReplacement(at: error.start ..< error.end)

            var newPosition = CFRange(location: error.start + suggestion.count, length: 0)
            if let newRangeValue = AXValueCreate(.cfRange, &newPosition) {
                _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
            }

            let lengthDelta = suggestion.count - (error.end - error.start)
            removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)
        } else {
            Logger.debug("AX API replacement failed (\(replaceError.rawValue)), trying keyboard fallback", category: Logger.analysis)
            await applyTextReplacementViaKeyboardAsync(for: error, with: suggestion, element: element)
        }
    }

    /// Apply text replacement for a style suggestion
    /// Similar to applyTextReplacement but uses StyleSuggestionModel's positions and suggested text
    func applyStyleTextReplacement(for suggestion: StyleSuggestionModel) {
        guard let element = textMonitor.monitoredElement else {
            Logger.debug("Style replacement: No monitored element", category: Logger.analysis)
            return
        }

        // Set replacement flag to prevent text change handler from clearing style suggestions
        lastReplacementTime = Date()
        isApplyingReplacement = true
        defer { isApplyingReplacement = false }

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
              let currentText = currentTextRef as? String
        else {
            Logger.debug("Could not get current text for style replacement, using keyboard fallback", category: Logger.analysis)
            applyStyleReplacementViaKeyboard(for: suggestion, element: element)
            return
        }

        // Find the actual position of the original text in the current content
        guard let range = currentText.range(of: suggestion.originalText) else {
            Logger.debug("Style replacement: original text not found in current content (\(suggestion.originalText.count) chars)", category: Logger.analysis)
            removeSuggestionFromTracking(suggestion)
            return
        }

        // Convert Swift range to character indices for AX API
        let startIndex = currentText.distance(from: currentText.startIndex, to: range.lowerBound)
        let length = suggestion.originalText.count

        Logger.trace("Style replacement at position \(startIndex)-\(startIndex + length)", category: Logger.analysis)

        // Step 1: Save current selection
        var originalSelection: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &originalSelection
        )

        // Step 2: Set selection to the found text range
        var suggestionRange = CFRange(location: startIndex, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &suggestionRange) else {
            Logger.debug("AXValueCreate failed for style replacement, using keyboard fallback", category: Logger.analysis)
            applyStyleReplacementViaKeyboard(for: suggestion, element: element)
            return
        }

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

            // Clear manual style check flag to allow indicator updates
            isManualStyleCheckActive = false

            // Clear grammar errors - their positions are now invalid after text replacement
            // They'll be recalculated on the next text change event
            currentErrors.removeAll()
            errorOverlay.hide()
            positionResolver.clearCache()

            // Invalidate style cache since text changed
            styleCache.removeAll()
            styleCacheMetadata.removeAll()

            // Update styleAnalysisSourceText to reflect the new text after replacement
            // This prevents remaining style suggestions from being cleared on next text change
            let newText = currentText.replacingCharacters(
                in: range,
                with: suggestion.suggestedText
            )
            styleAnalysisSourceText = newText

            // Move cursor after replacement
            var newPosition = CFRange(location: startIndex + suggestion.suggestedText.count, length: 0)
            if let newRangeValue = AXValueCreate(.cfRange, &newPosition) {
                _ = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    newRangeValue
                )
            }

            // Remove the applied style suggestion from tracking
            removeSuggestionFromTracking(suggestion)

            // Schedule re-analysis after grace period to restore grammar underlines
            schedulePostStyleReplacementAnalysis()
        } else {
            Logger.debug("AX API replacement failed for style (\(replaceError.rawValue)), trying keyboard fallback", category: Logger.analysis)
            applyStyleReplacementViaKeyboard(for: suggestion, element: element)
        }
    }

    /// Apply style replacement via keyboard simulation (for Electron apps and fallback)
    func applyStyleReplacementViaKeyboard(for suggestion: StyleSuggestionModel, element: AXUIElement) {
        guard let context = monitoredContext else {
            Logger.debug("No context available for style keyboard replacement", category: Logger.analysis)
            return
        }

        Logger.debug("Using keyboard simulation for style replacement (app: \(context.applicationName))", category: Logger.analysis)

        // For browsers and apps requiring browser-style replacement, use the browser-specific approach
        // These apps require child element traversal for proper text selection
        let appBehavior = AppBehaviorRegistry.shared.behavior(for: context.bundleIdentifier)
        if context.isBrowser || appBehavior.knownQuirks.contains(.requiresBrowserStyleReplacement) {
            applyStyleBrowserReplacement(for: suggestion, element: element, context: context)
            return
        }

        // Get current text and find the ACTUAL position of the original text
        // The positions from Rust are byte offsets which don't match macOS character indices
        var currentTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentTextRef)

        guard textResult == .success,
              let currentText = currentTextRef as? String
        else {
            Logger.debug("Could not get current text for style keyboard replacement", category: Logger.analysis)
            return
        }

        // Find the actual position of the original text in the current content
        guard let range = currentText.range(of: suggestion.originalText) else {
            Logger.debug("Could not find original text in current content for keyboard replacement", category: Logger.analysis)
            removeSuggestionFromTracking(suggestion)
            return
        }

        // Convert Swift range to character indices for AX API
        let startIndex = currentText.distance(from: currentText.startIndex, to: range.lowerBound)
        let length = suggestion.originalText.count

        // Standard keyboard approach: select range, paste replacement
        // Step 1: Try to select the range using AX API
        var suggestionRange = CFRange(location: startIndex, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &suggestionRange) else {
            Logger.debug("AXValueCreate failed for style keyboard replacement", category: Logger.analysis)
            return
        }

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
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.hoverDelay) {
                if let original = originalString {
                    pasteboard.clearContents()
                    pasteboard.setString(original, forType: .string)
                }
            }

            // Clear manual style check flag to allow indicator updates
            self?.isManualStyleCheckActive = false

            // Clear grammar errors - their positions are now invalid after text replacement
            self?.currentErrors.removeAll()
            self?.errorOverlay.hide()
            self?.positionResolver.clearCache()

            // Invalidate style cache since text changed
            self?.styleCache.removeAll()
            self?.styleCacheMetadata.removeAll()

            // Update styleAnalysisSourceText to the current text after replacement
            // This prevents remaining style suggestions from being cleared on next text change
            if let element = self?.textMonitor.monitoredElement {
                var textRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef)
                if result == .success, let newText = textRef as? String {
                    self?.styleAnalysisSourceText = newText
                }
            }

            self?.removeSuggestionFromTracking(suggestion)

            // Schedule re-analysis after grace period to restore grammar underlines
            self?.schedulePostStyleReplacementAnalysis()
        }
    }

    /// Apply style replacement for browsers
    func applyStyleBrowserReplacement(for suggestion: StyleSuggestionModel, element: AXUIElement, context: ApplicationContext) {
        Logger.debug("Browser style replacement for \(context.applicationName)", category: Logger.analysis)

        // Select the text to replace (handles Notion child element traversal internally)
        guard selectTextForReplacement(
            targetText: suggestion.originalText,
            fallbackRange: nil, // Style suggestions use text search, not byte offsets
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
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.longDelay) { [weak self] in
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
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.hoverDelay) {
                if let original = originalString {
                    pasteboard.clearContents()
                    pasteboard.setString(original, forType: .string)
                }
            }

            // Clear manual style check flag to allow indicator updates
            self?.isManualStyleCheckActive = false

            // Clear grammar errors - their positions are now invalid after text replacement
            self?.currentErrors.removeAll()
            self?.errorOverlay.hide()
            self?.positionResolver.clearCache()

            // Invalidate style cache since text changed
            self?.styleCache.removeAll()
            self?.styleCacheMetadata.removeAll()

            // Update styleAnalysisSourceText to the current text after replacement
            // This prevents remaining style suggestions from being cleared on next text change
            if let element = self?.textMonitor.monitoredElement {
                var textRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef)
                if result == .success, let newText = textRef as? String {
                    self?.styleAnalysisSourceText = newText
                }
            }

            self?.removeSuggestionFromTracking(suggestion)

            // Schedule re-analysis after grace period to restore grammar underlines
            self?.schedulePostStyleReplacementAnalysis()
        }
    }

    /// Remove an applied style suggestion from tracking and update UI
    func removeSuggestionFromTracking(_ suggestion: StyleSuggestionModel) {
        // Track this suggestion as dismissed so it won't reappear after re-analysis
        dismissedStyleSuggestionHashes.insert(suggestion.originalText.hashValue)

        // Remove from current suggestions
        let countBefore = currentStyleSuggestions.count
        currentStyleSuggestions.removeAll { $0.id == suggestion.id }

        // Also validate and remove any stale suggestions whose original text no longer exists
        // This handles the case where text changed and other suggestions became invalid
        if let element = textMonitor.monitoredElement {
            var currentTextRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentTextRef)
            if result == .success, let currentText = currentTextRef as? String, !currentText.isEmpty {
                let staleSuggestions = currentStyleSuggestions.filter { !currentText.contains($0.originalText) }
                if !staleSuggestions.isEmpty {
                    Logger.debug("Removing \(staleSuggestions.count) stale suggestions whose text no longer exists", category: Logger.analysis)
                    currentStyleSuggestions.removeAll { suggestion in
                        !currentText.contains(suggestion.originalText)
                    }
                }
                // Update the source text to current
                styleAnalysisSourceText = currentText
            }
        }
        let countAfter = currentStyleSuggestions.count

        // Update popover's allStyleSuggestions
        suggestionPopover.allStyleSuggestions = currentStyleSuggestions

        Logger.debug("Removed style suggestion '\(suggestion.id)' from tracking, before: \(countBefore), after: \(countAfter) (validated against current text)", category: Logger.analysis)

        // Update the floating indicator with remaining suggestions
        if currentStyleSuggestions.isEmpty, currentErrors.isEmpty {
            // No more suggestions or errors - hide indicator
            Logger.debug("AnalysisCoordinator: No remaining suggestions/errors, hiding indicator", category: Logger.analysis)
            floatingIndicator.hide()
        } else {
            // Update indicator with remaining count
            Logger.debug("AnalysisCoordinator: \(currentStyleSuggestions.count) style suggestions, \(currentErrors.count) errors remaining", category: Logger.analysis)
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
            } else {
                // Element not available - update style count directly
                Logger.debug("AnalysisCoordinator: No element, updating style count directly", category: Logger.analysis)
                floatingIndicator.updateStyleSuggestions(currentStyleSuggestions)
            }
        }
    }

    /// Schedule re-analysis after the replacement grace period ends.
    /// Called after style replacements to restore grammar underlines with correct positions.
    func schedulePostStyleReplacementAnalysis() {
        // Wait for the replacement grace period to end, plus a small buffer
        let delay = TimingConstants.replacementGracePeriod + 0.1

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard let element = textMonitor.monitoredElement else {
                Logger.debug("Post-style replacement analysis: no monitored element", category: Logger.analysis)
                return
            }

            // Extract current text and trigger analysis
            if let text = extractTextSynchronously(from: element) {
                Logger.debug("Post-style replacement analysis: triggering re-analysis (\(text.count) chars)", category: Logger.analysis)

                // Clear previousText to force re-analysis (otherwise analyzeText skips if text matches)
                previousText = ""

                let segment = TextSegment(
                    content: text,
                    startIndex: 0,
                    endIndex: text.count,
                    context: monitoredContext ?? ApplicationContext(bundleIdentifier: "", processID: 0, applicationName: "")
                )
                currentSegment = segment
                analyzeText(segment)
            }
        }
    }

    /// Schedule delayed re-analysis after text replacement for apps with focus bounce behavior.
    /// WebKit/Electron apps may fire AXFocusedUIElementChanged during paste, clearing the monitored element.
    /// This waits for focus to settle, then restarts monitoring to find the composition element.
    func scheduleDelayedReanalysis(startTime: Date) {
        guard let context = monitoredContext else { return }
        let appConfig = appRegistry.configuration(for: context.bundleIdentifier)
        guard appConfig.features.focusBouncesDuringPaste else { return }

        Logger.trace("Focus bounce reanalysis: T=\(Int(Date().timeIntervalSince(startTime) * 1000))ms scheduling", category: Logger.analysis)

        // Wait 300ms for focus to settle after focus bounce
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.hoverDelay) { [weak self] in
            guard let self else { return }
            guard let context = monitoredContext else { return }

            let appConfig = appRegistry.configuration(for: context.bundleIdentifier)
            guard appConfig.features.focusBouncesDuringPaste else {
                Logger.trace("Focus bounce reanalysis: skipping - app no longer has focus bounce", category: Logger.analysis)
                return
            }

            Logger.trace("Focus bounce reanalysis: T=\(Int(Date().timeIntervalSince(startTime) * 1000))ms starting", category: Logger.analysis)

            // If we have a monitored element and remaining errors, just refresh the overlay
            if textMonitor.monitoredElement != nil, !currentErrors.isEmpty {
                Logger.trace("Focus bounce reanalysis: have element and errors, refreshing overlay", category: Logger.analysis)
                if let element = textMonitor.monitoredElement {
                    showErrorUnderlines(currentErrors, element: element)
                }
                return
            }

            // No monitored element - restart monitoring to re-acquire the composition element
            Logger.trace("Focus bounce reanalysis: no element, restarting monitoring", category: Logger.analysis)

            textMonitor.stopMonitoring()
            textMonitor.startMonitoring(
                processID: context.processID,
                bundleIdentifier: context.bundleIdentifier,
                appName: context.applicationName
            )

            // After monitoring restarts, extract text to trigger analysis
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.mediumDelay) { [weak self] in
                guard let self else { return }
                Logger.trace("Focus bounce reanalysis: T=\(Int(Date().timeIntervalSince(startTime) * 1000))ms extracting text", category: Logger.analysis)

                if let element = textMonitor.monitoredElement {
                    textMonitor.extractText(from: element)
                } else {
                    Logger.debug("Focus bounce reanalysis: still no element after restart", category: Logger.analysis)
                }
            }
        }
    }

    /// Find the Paste menu item in the application's menu bar
    /// Returns the AXUIElement for the Paste menu item, or nil if not found
    func findPasteMenuItem(in appElement: AXUIElement) -> AXUIElement? {
        // Try to get the menu bar
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarRef = menuBarValue,
              CFGetTypeID(menuBarRef) == AXUIElementGetTypeID()
        else {
            return nil
        }
        // Safe: type verified by CFGetTypeID check above
        let menuBar = unsafeBitCast(menuBarRef, to: AXUIElement.self)

        // Try to find "Edit" menu
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let childrenArray = childrenValue as? [AXUIElement]
        else {
            return nil
        }

        let children = childrenArray

        for child in children {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String,
               title.lowercased().contains("edit")
            {
                // Found Edit menu, now look for Paste
                var menuChildrenValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &menuChildrenValue) == .success,
                   let menuChildren = menuChildrenValue as? [AXUIElement]
                {
                    for menuChild in menuChildren {
                        var itemChildrenValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(menuChild, kAXChildrenAttribute as CFString, &itemChildrenValue) == .success,
                           let items = itemChildrenValue as? [AXUIElement]
                        {
                            for item in items {
                                var itemTitleValue: CFTypeRef?
                                if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &itemTitleValue) == .success,
                                   let itemTitle = itemTitleValue as? String,
                                   itemTitle.lowercased().contains("paste")
                                {
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
    /// Handles Electron/WebKit apps using app configuration features
    /// Returns true if selection succeeded (or was attempted), false if it failed critically
    func selectTextForReplacement(
        targetText: String,
        fallbackRange: CFRange?,
        element: AXUIElement,
        context: ApplicationContext
    ) -> Bool {
        // Get app configuration for feature-based decisions
        let appConfig = AppRegistry.shared.effectiveConfiguration(for: context.bundleIdentifier)
        let appName = appConfig.displayName

        // WebKit-based apps (Mail): use TextMarker APIs for text selection
        if appConfig.features.usesWebKitMarkerSelection {
            Logger.debug("\(appName): Using WebKit-specific text selection", category: Logger.analysis)

            if let range = fallbackRange {
                let nsRange = NSRange(location: range.location, length: range.length)
                let success = MailContentParser.selectTextForReplacement(range: nsRange, in: element)
                if success {
                    Logger.debug("\(appName): WebKit selection succeeded", category: Logger.analysis)
                } else {
                    Logger.debug("\(appName): WebKit selection failed - paste may go to wrong location", category: Logger.analysis)
                }
                return true // Always try paste even if selection fails
            } else {
                // Try to find the text position
                if let currentText = extractCurrentText(from: element),
                   let textRange = currentText.range(of: targetText)
                {
                    let start = currentText.distance(from: currentText.startIndex, to: textRange.lowerBound)
                    let nsRange = NSRange(location: start, length: targetText.count)
                    let success = MailContentParser.selectTextForReplacement(range: nsRange, in: element)
                    Logger.debug("\(appName): Text search + selection \(success ? "succeeded" : "failed")", category: Logger.analysis)
                    return true
                }
                Logger.debug("\(appName): Could not find text to select", category: Logger.analysis)
                return true // Still try paste
            }
        }

        // Electron apps with child element traversal (Slack, Teams, Notion, Claude, etc.)
        if appConfig.features.childElementTraversal {
            Logger.trace("\(appName): Looking for text to select (\(targetText.count) chars)", category: Logger.analysis)

            // For single-character whitespace/punctuation errors, searching for just " " is ambiguous.
            // Instead, search for expanded context (e.g., "7 day") but only select the single character.
            let cachedText = lastAnalyzedText.isEmpty ? (currentSegment?.content ?? previousText) : lastAnalyzedText
            var searchText = targetText
            var singleCharOffsetInContext: Int?

            if targetText.count == 1, let char = targetText.first, char.isWhitespace || char.isPunctuation {
                // Get the fallback range position to find context
                if let range = fallbackRange {
                    let dummyError = GrammarErrorModel(
                        start: range.location,
                        end: range.location + range.length,
                        message: "", severity: .info, category: "", lintId: ""
                    )
                    if let context = findSingleCharErrorContext(error: dummyError, in: cachedText) {
                        searchText = context.context
                        singleCharOffsetInContext = context.offset
                        Logger.debug("\(appName): Using context '\(searchText)' for single-char selection (offset: \(context.offset))", category: Logger.analysis)
                    }
                }
            }

            // Try to find child element containing the text and select within it
            if let (childElement, offsetInChild) = findChildElementContainingText(searchText, in: element) {
                // Get the child element's text for UTF-16 conversion
                // Slack/Notion use Chromium which expects UTF-16 indices, not grapheme clusters
                var childTextRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(childElement, kAXValueAttribute as CFString, &childTextRef) == .success,
                      let childText = childTextRef as? String
                else {
                    Logger.debug("\(appName): Could not get child element text for UTF-16 conversion", category: Logger.analysis)
                    return false
                }

                // Calculate the actual selection range
                // For single-char errors with context, adjust to select only the character
                let selectionOffset: Int
                let selectionLength: Int
                if let singleCharOffset = singleCharOffsetInContext {
                    // Select only the single character within the found context
                    selectionOffset = offsetInChild + singleCharOffset
                    selectionLength = 1
                    Logger.trace("\(appName): Adjusted selection to single char at offset \(selectionOffset)", category: Logger.analysis)
                } else {
                    selectionOffset = offsetInChild
                    selectionLength = searchText.count
                }

                // Convert grapheme indices to UTF-16 indices
                let utf16Range = TextIndexConverter.graphemeToUTF16Range(
                    NSRange(location: selectionOffset, length: selectionLength),
                    in: childText
                )
                var childRange = CFRange(location: utf16Range.location, length: utf16Range.length)

                Logger.trace("\(appName): UTF-16 range \(utf16Range.location)-\(utf16Range.location + utf16Range.length) (from grapheme \(selectionOffset)-\(selectionOffset + selectionLength))", category: Logger.analysis)

                guard let childRangeValue = AXValueCreate(.cfRange, &childRange) else {
                    Logger.debug("\(appName): Failed to create AXValue for child range", category: Logger.analysis)
                    return false
                }

                let childSelectResult = AXUIElementSetAttributeValue(
                    childElement,
                    kAXSelectedTextRangeAttribute as CFString,
                    childRangeValue
                )

                if childSelectResult != .success {
                    Logger.debug("\(appName): Child selection failed (\(childSelectResult.rawValue)) - aborting", category: Logger.analysis)
                    return false // Selection failed - caller should abort
                }
                return true
            } else {
                Logger.debug("\(appName): Could not find child element containing text - selection failed", category: Logger.analysis)
                return false // Selection failed - caller should abort
            }
        } else {
            // Standard browser / Mac Catalyst: try AX API selection directly
            // This may silently fail, but it's fast and works sometimes
            //
            // All apps using UTF-16 indices need conversion (Mac Catalyst, Chromium browsers, etc.)
            // Emojis and other multi-codepoint characters cause offset issues without this.

            // Get the current text content (needed for UTF-16 conversion)
            var currentTextRef: CFTypeRef?
            let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentTextRef)
            let currentText = (textResult == .success) ? (currentTextRef as? String) : nil

            guard var range = fallbackRange else {
                // Need to find text in current element content
                guard let currentText else {
                    Logger.debug("Could not get current text for browser replacement", category: Logger.analysis)
                    return false
                }

                guard let textRange = currentText.range(of: targetText) else {
                    Logger.debug("Could not find target text in current content", category: Logger.analysis)
                    return false
                }

                // Convert grapheme indices to UTF-16 indices for AX selection
                // Required for: Mac Catalyst apps, Chromium-based browsers, and any app using UTF-16 offsets
                // Emojis and other multi-codepoint characters cause offset issues without this conversion
                // Skip for apps that use grapheme indices (like native macOS and Microsoft Office apps)
                let appBehavior = AppBehaviorRegistry.shared.behavior(for: context.bundleIdentifier)
                let startIndex = currentText.distance(from: currentText.startIndex, to: textRange.lowerBound)
                var calculatedRange: CFRange
                if !appBehavior.usesUTF16TextIndices {
                    calculatedRange = CFRange(location: startIndex, length: targetText.count)
                    Logger.debug("Grapheme app selection: Using grapheme range [\(startIndex), \(targetText.count)]", category: Logger.analysis)
                } else {
                    let utf16Range = TextIndexConverter.graphemeToUTF16Range(NSRange(location: startIndex, length: targetText.count), in: currentText)
                    calculatedRange = CFRange(location: utf16Range.location, length: utf16Range.length)
                    Logger.debug("Browser selection: Converted range from grapheme [\(startIndex), \(targetText.count)] to UTF-16 [\(utf16Range.location), \(utf16Range.length)]", category: Logger.analysis)
                }

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

            // Convert fallback range to UTF-16 if we have the text
            // Required for browsers and Mac Catalyst apps that use UTF-16 offsets
            // Skip for apps that use grapheme indices (like native macOS and Microsoft Office apps)
            let appBehaviorForFallback = AppBehaviorRegistry.shared.behavior(for: context.bundleIdentifier)
            if let text = currentText, appBehaviorForFallback.usesUTF16TextIndices {
                let graphemeRange = NSRange(location: range.location, length: range.length)
                let utf16Range = TextIndexConverter.graphemeToUTF16Range(graphemeRange, in: text)
                range = CFRange(location: utf16Range.location, length: utf16Range.length)
                Logger.debug("Browser selection: Converted fallback range from grapheme [\(graphemeRange.location), \(graphemeRange.length)] to UTF-16 [\(utf16Range.location), \(utf16Range.length)]", category: Logger.analysis)
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

    /// Type text directly using CGEvent keyboard events with Unicode strings.
    /// This bypasses the clipboard entirely, which is needed for Mac Catalyst apps
    /// where clipboard paste operations are unreliable.
    /// Based on the Force-Paste approach: https://github.com/EugeneDae/Force-Paste
    /// See Apple docs: https://developer.apple.com/documentation/coregraphics/1456028-cgeventkeyboardsetunicodestring
    func typeTextDirectly(_ text: String) {
        Logger.debug("Typing text directly (\(text.count) chars)", category: Logger.analysis)

        let source = CGEventSource(stateID: .hidSystemState)

        // Convert the entire text to UTF-16 for CGEventKeyboardSetUnicodeString
        var utf16Chars = Array(text.utf16)

        // Create key down event with the Unicode string
        // Virtual key 0 is 'a', but the Unicode string overrides it
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            Logger.error("Failed to create CGEvent for typing", category: Logger.analysis)
            return
        }

        // Set the Unicode string on the key down event
        // This tells the system to input these exact characters regardless of keyboard layout
        keyDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)

        // Post the events to simulate typing
        // Using .cghidEventTap posts to the HID system, which is more reliable
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        Logger.debug("Posted keyboard events for direct typing", category: Logger.analysis)
    }

    /// Extract current text from an element (for text search during replacement)
    /// Handles Mail's WebKit-based elements that need child traversal
    func extractCurrentText(from element: AXUIElement) -> String? {
        // First try standard AXValue
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String,
           !text.isEmpty
        {
            return text
        }

        // For Mail/WebKit: use MailContentParser's extraction
        if let parser = contentParserFactory.parser(for: "com.apple.mail") as? MailContentParser {
            return parser.extractText(from: element)
        }

        return nil
    }

    /// Find the child element containing the target text and return the offset within that element
    /// Used for Notion and other Electron apps where document-level offsets don't work
    func findChildElementContainingText(_ targetText: String, in element: AXUIElement) -> (AXUIElement, Int)? {
        var candidates: [(element: AXUIElement, text: String, offset: Int)] = []
        collectTextElements(in: element, depth: 0, maxDepth: 10, candidates: &candidates, targetText: targetText)

        // Sort by text length ascending to prefer most specific (smallest) element
        // Parent elements contain child text, so smaller = more specific
        let sortedCandidates = candidates.sorted { $0.text.count < $1.text.count }

        for candidate in sortedCandidates {
            guard let range = candidate.text.range(of: targetText) else { continue }
            let offset = candidate.text.distance(from: candidate.text.startIndex, to: range.lowerBound)
            Logger.trace("Found target text in child element (size \(candidate.text.count)) at offset \(offset)", category: Logger.analysis)
            return (candidate.element, offset)
        }

        // Fallback: If no child element matched (e.g., for readability suggestions that span
        // multiple child elements), try the root element directly. This handles cases where
        // the target text is longer than what fits in a single paragraph element.
        var textValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
           let rootText = textValue as? String,
           let range = rootText.range(of: targetText)
        {
            let offset = rootText.distance(from: rootText.startIndex, to: range.lowerBound)
            Logger.debug("Fallback: Using root element for text selection (offset \(offset))", category: Logger.analysis)
            return (element, offset)
        }

        return nil
    }

    /// Collect child text elements for element tree traversal
    func collectTextElements(
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
           text.contains(targetText)
        {
            var sizeValue: CFTypeRef?
            var height: CGFloat = 0
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let size = sizeValue,
               let rectSize = safeAXValueGetSize(size)
            {
                height = rectSize.height
            }

            // Prefer smaller elements (paragraph-level, not document-level)
            if height > 0, height < GeometryConstants.maximumLineHeight {
                candidates.append((element: element, text: text, offset: 0))
                Logger.trace("Candidate element: height=\(Int(height)), length=\(text.count)", category: Logger.analysis)
            }
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement]
        {
            for child in children.prefix(100) {
                collectTextElements(in: child, depth: depth + 1, maxDepth: maxDepth, candidates: &candidates, targetText: targetText)
            }
        }
    }

    /// Apply text replacement using keyboard simulation (for Electron apps and Terminals)
    /// Flattened async/await implementation for better readability
    @MainActor
    func applyTextReplacementViaKeyboardAsync(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement) async {
        guard let context = monitoredContext else {
            Logger.debug("No context available for keyboard replacement", category: Logger.analysis)
            return
        }

        Logger.debug("Using keyboard simulation for text replacement (app: \(context.applicationName), isBrowser: \(context.isBrowser))", category: Logger.analysis)

        // Get app behavior for quirk checks
        let appBehavior = AppBehaviorRegistry.shared.behavior(for: context.bundleIdentifier)

        // SPECIAL HANDLING FOR APPLE MAIL (uses WebKit's AXReplaceRangeWithText API)
        if appBehavior.knownQuirks.contains(.usesMailReplaceRangeAPI) {
            await applyMailTextReplacementAsync(for: error, with: suggestion, element: element)
            return
        }

        // SLACK: Try format-preserving replacement first (preserves bold, italic, code, etc.)
        if appBehavior.knownQuirks.contains(.hasSlackFormatPreservingReplacement) {
            if let slackParser = contentParserFactory.parser(for: context.bundleIdentifier) as? SlackContentParser {
                // Get current text for the replacement
                var textRef: CFTypeRef?
                let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef)
                let currentText = (textResult == .success) ? (textRef as? String) ?? "" : ""

                Logger.info("Slack: Attempting format-preserving replacement (\(suggestion.count) chars)", category: Logger.analysis)

                let result = await slackParser.applyFormatPreservingReplacement(
                    errorStart: error.start,
                    errorEnd: error.end,
                    originalText: currentText,
                    suggestion: suggestion,
                    element: element
                )

                switch result {
                case .success:
                    Logger.info("Slack: Format-preserving replacement succeeded", category: Logger.analysis)
                    statistics.recordSuggestionApplied(category: error.category)
                    // For format-preserving replacement, we know exactly what changed.
                    // Don't do full re-analysis - just clear position cache and adjust errors.
                    // Full re-analysis would clear currentErrors and break popover/highlight sync.
                    positionResolver.clearCache()
                    let lengthDelta = suggestion.count - (error.end - error.start)
                    // CRITICAL: Set lastReplacementTime to enable grace period
                    // Without this, isInReplacementMode returns false after isApplyingReplacement clears,
                    // allowing AX notifications to trigger re-analysis with stale error positions
                    lastReplacementTime = Date()
                    // Reset typing detector so underlines show immediately after replacement
                    // (paste triggers text change which sets isCurrentlyTyping=true)
                    TypingDetector.shared.reset()
                    removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)
                    replacementCompletedAt = Date()
                    // Schedule delayed reanalysis to catch any issues, but don't force immediate re-analysis
                    scheduleDelayedReanalysis(startTime: Date())
                    return

                case .fallbackToPlainText:
                    Logger.info("Slack: Format-preserving failed, falling back to plain text replacement", category: Logger.analysis)
                    // Continue to browser replacement below

                case let .failed(reason):
                    Logger.warning("Slack: Format-preserving failed: \(reason), falling back to plain text", category: Logger.analysis)
                    // Continue to browser replacement below
                }
            }
        }

        // Check if app requires browser-style replacement (via quirk or AppRegistry config)
        let appConfig = appRegistry.configuration(for: context.bundleIdentifier)
        let usesBrowserStyleFromConfig = appConfig.features.textReplacementMethod == .browserStyle
        let usesBrowserStyleFromQuirk = appBehavior.knownQuirks.contains(.requiresBrowserStyleReplacement)

        if usesBrowserStyleFromQuirk || usesBrowserStyleFromConfig || context.isBrowser || context.isMacCatalystApp {
            await applyBrowserTextReplacementAsync(for: error, with: suggestion, element: element, context: context)
            return
        }

        // Use standard keyboard navigation for remaining apps
        await applyStandardKeyboardReplacementAsync(for: error, with: suggestion, element: element, context: context)
    }

    /// Apply text replacement for Apple Mail (async version)
    @MainActor
    func applyMailTextReplacementAsync(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement) async {
        Logger.debug("Mail text replacement using AXReplaceRangeWithText (async)", category: Logger.analysis)

        lastReplacementTime = Date()

        let currentError = currentErrors.first { err in
            err.message == error.message && err.lintId == error.lintId && err.category == error.category
        } ?? error

        let range = NSRange(location: currentError.start, length: currentError.end - currentError.start)
        let lengthDelta = suggestion.count - (currentError.end - currentError.start)

        // Try the proper WebKit API first
        if MailContentParser.replaceText(range: range, with: suggestion, in: element) {
            Logger.info("Mail: AXReplaceRangeWithText succeeded", category: Logger.analysis)
            statistics.recordSuggestionApplied(category: currentError.category)
            invalidateCacheAfterReplacement(at: currentError.start ..< currentError.end)
            removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)
            return
        }

        // Fallback: selection + keyboard typing (preserves formatting)
        // Using keyboard typing instead of paste preserves the formatting of the selected text
        Logger.debug("Mail: AXReplaceRangeWithText failed, falling back to selection + keyboard typing", category: Logger.analysis)
        _ = MailContentParser.selectTextForReplacement(range: range, in: element)

        // Activate Mail
        if let mailApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first {
            mailApp.activate()
        }

        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.shortDelay * 1_000_000_000))

        // Type the replacement text directly - this inherits the formatting from the selection
        typeTextDirectly(suggestion)

        // Wait for typing to complete (longer for longer text)
        let typingDelay = Double(suggestion.count) * 0.01 + 0.1
        try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))

        statistics.recordSuggestionApplied(category: currentError.category)
        // Follow Slack's pattern: clear cache, reset typing detector, then update UI
        // This ensures underlines and highlight remain visible for the next error
        positionResolver.clearCache()
        TypingDetector.shared.reset()
        removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)

        replacementCompletedAt = Date()
        scheduleDelayedReanalysis(startTime: Date())
    }

    /// Apply text replacement for browsers, Office, and Catalyst apps (async version)
    @MainActor
    func applyBrowserTextReplacementAsync(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, context: ApplicationContext) async {
        Logger.debug("Browser text replacement (async) for \(context.applicationName)", category: Logger.analysis)

        lastReplacementTime = Date()

        // Check if app requires focus+paste replacement (Office, Pages, etc.)
        let appBehaviorForReplacement = AppBehaviorRegistry.shared.behavior(for: context.bundleIdentifier)
        let usesOfficeStyleReplacement = appBehaviorForReplacement.knownQuirks.contains(.requiresFocusPasteReplacement)

        // Find error text and position based on app type
        let (errorText, fallbackRange, currentError) = usesOfficeStyleReplacement
            ? findOfficeErrorPosition(error: error, suggestion: suggestion, element: element)
            : findBrowserErrorPosition(error: error)

        let targetText = errorText.isEmpty ? suggestion : errorText

        // Microsoft Office and Pages: use clipboard paste with explicit element focus
        // Direct AX replacement (AXSelectedText) reports success but doesn't actually work
        // We need to: 1) Focus the element, 2) Set selection, 3) Activate app, 4) Paste via keyboard
        if usesOfficeStyleReplacement, let range = fallbackRange {
            Logger.debug("Office-style: Using focused clipboard replacement at \(range.location)-\(range.location + range.length) for \(context.applicationName)", category: Logger.analysis)

            // Step 1: Focus the specific element (Notes area in PowerPoint, document in Word)
            let focusResult = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if focusResult != .success {
                Logger.debug("Office: Could not focus element (\(focusResult.rawValue))", category: Logger.analysis)
            }

            // Step 2: Set selection range on the element
            var selectionRange = CFRange(location: range.location, length: range.length)
            if let rangeValue = AXValueCreate(.cfRange, &selectionRange) {
                let selectResult = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    rangeValue
                )
                if selectResult == .success {
                    Logger.debug("Office: Selection set successfully", category: Logger.analysis)
                } else {
                    Logger.debug("Office: Selection failed (\(selectResult.rawValue))", category: Logger.analysis)
                }
            }

            // Step 3: Prepare clipboard
            let pasteboard = NSPasteboard.general
            let originalString = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            pasteboard.setString(suggestion, forType: .string)

            // Step 4: Activate the Office app so Cmd+V goes to the right window
            if let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier).first {
                targetApp.activate()
                Logger.debug("Office: Activated \(context.applicationName)", category: Logger.analysis)
            }

            // Small delay for activation and selection to take effect
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Step 5: Paste via keyboard
            pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
            Logger.debug("Office: Pasted via Cmd+V", category: Logger.analysis)

            // Restore clipboard
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if let original = originalString {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }

            statistics.recordSuggestionApplied(category: currentError.category)
            positionResolver.clearCache()
            let lengthDelta = suggestion.count - (currentError.end - currentError.start)
            removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)
            return
        }

        let selectionSucceeded = selectTextForReplacement(targetText: targetText, fallbackRange: fallbackRange, element: element, context: context)

        // If selection failed, abort to prevent pasting at wrong location
        if !selectionSucceeded {
            Logger.warning("Selection failed - aborting replacement to prevent text corruption", category: Logger.analysis)
            SuggestionPopover.shared.showStatusMessage("Could not select text - try clicking on the error first")
            return
        }

        // Validate selection before paste to prevent wrong placement
        // This applies to:
        // - Apps with virtualized content (Teams) where errors may scroll out of view
        // - Apps with unreliable AX selection (Slack) where selection can fail silently
        // - Browser-style replacement apps where selection issues cause text corruption
        if appBehaviorForReplacement.knownQuirks.contains(.requiresSelectionValidationBeforePaste) ||
            appBehaviorForReplacement.knownQuirks.contains(.requiresBrowserStyleReplacement),
            !targetText.isEmpty
        {
            // Small delay for selection to take effect
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // Check if selection matches expected text
            var selectedTextRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
               let selectedText = selectedTextRef as? String
            {
                if selectedText != targetText {
                    Logger.warning("Selection mismatch (got \(selectedText.count) chars, expected \(targetText.count) chars) - error may be scrolled out of view, aborting", category: Logger.analysis)
                    SuggestionPopover.shared.showStatusMessage("Scroll to see this error first")
                    return
                }
                Logger.debug("Selection validated (\(targetText.count) chars)", category: Logger.analysis)
            } else {
                Logger.warning("Could not validate selection - aborting to prevent wrong placement", category: Logger.analysis)
                SuggestionPopover.shared.showStatusMessage("Scroll to see this error first")
                return
            }
        }

        // Perform clipboard-based replacement
        await performClipboardReplacement(
            suggestion: suggestion,
            currentError: currentError,
            context: context,
            usesFocusPasteReplacement: usesOfficeStyleReplacement
        )
    }

    /// Find error position in Microsoft Office documents using UTF-16 search
    private func findOfficeErrorPosition(error: GrammarErrorModel, suggestion: String, element: AXUIElement) -> (errorText: String, fallbackRange: CFRange?, currentError: GrammarErrorModel) {
        // Get live text from document
        var liveTextRef: CFTypeRef?
        var liveText = ""
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &liveTextRef) == .success,
           let text = liveTextRef as? String
        {
            liveText = text
        }

        // Primary strategy: Extract exact error text from cached content using Harper's positions
        // This is the most reliable approach because it uses the precise error location
        let cachedText = lastAnalyzedText.isEmpty ? (currentSegment?.content ?? "") : lastAnalyzedText
        let scalarCount = cachedText.unicodeScalars.count

        if !cachedText.isEmpty, error.start < scalarCount, error.end <= scalarCount,
           let startIdx = TextIndexConverter.scalarIndexToStringIndex(error.start, in: cachedText),
           let endIdx = TextIndexConverter.scalarIndexToStringIndex(error.end, in: cachedText)
        {
            let errorText = String(cachedText[startIdx ..< endIdx])
            Logger.debug("Office: Looking for error text (\(errorText.count) chars) in live document", category: Logger.analysis)

            // Find this exact error text in the live document
            if let exactRange = liveText.range(of: errorText) {
                let start = utf16Offset(of: exactRange.lowerBound, in: liveText)
                let range = CFRange(location: start, length: errorText.utf16.count)
                Logger.debug("Office: Found error at UTF-16 position \(start)", category: Logger.analysis)
                return (errorText, range, error)
            }
        }

        // Fallback: use error positions directly (may be inaccurate if text changed)
        Logger.debug("Office: Falling back to direct position \(error.start)-\(error.end)", category: Logger.analysis)
        return (suggestion, CFRange(location: error.start, length: error.end - error.start), error)
    }

    /// Find error position for browsers and standard apps
    /// Returns: (errorText, fallbackRange, currentError)
    /// - errorText: The actual error text to replace
    /// - fallbackRange: Position of error (always provided for single-char errors to enable context lookup)
    private func findBrowserErrorPosition(error: GrammarErrorModel) -> (errorText: String, fallbackRange: CFRange?, currentError: GrammarErrorModel) {
        // Match by position first (most reliable), then fall back to message/lintId matching
        let currentError = currentErrors.first { err in
            err.start == error.start && err.end == error.end
        } ?? currentErrors.first { err in
            err.message == error.message && err.lintId == error.lintId && err.category == error.category
        } ?? error

        let cachedText = lastAnalyzedText.isEmpty ? (currentSegment?.content ?? previousText) : lastAnalyzedText
        let scalarCount = cachedText.unicodeScalars.count

        if !cachedText.isEmpty, currentError.start < scalarCount, currentError.end <= scalarCount,
           let startIdx = TextIndexConverter.scalarIndexToStringIndex(currentError.start, in: cachedText),
           let endIdx = TextIndexConverter.scalarIndexToStringIndex(currentError.end, in: cachedText)
        {
            let errorText = String(cachedText[startIdx ..< endIdx])

            // For single-character whitespace/punctuation errors, ALWAYS provide the fallback range
            // This allows selectTextForReplacement to use context-aware selection
            if errorText.count == 1, let char = errorText.first, char.isWhitespace || char.isPunctuation {
                let fallbackRange = CFRange(location: currentError.start, length: currentError.end - currentError.start)
                Logger.debug("Browser position: Single-char error '\(errorText)', providing position \(currentError.start)-\(currentError.end) for context lookup", category: Logger.analysis)
                return (errorText, fallbackRange, currentError)
            }

            return (errorText, nil, currentError)
        } else {
            let fallbackRange = CFRange(location: currentError.start, length: currentError.end - currentError.start)
            return ("", fallbackRange, currentError)
        }
    }

    /// For single-character errors, find expanded context for disambiguation but return offset within that context
    /// Returns: (contextText, offsetWithinContext) or nil if not applicable
    private func findSingleCharErrorContext(error: GrammarErrorModel, in text: String) -> (context: String, offset: Int)? {
        let errorLength = error.end - error.start
        guard errorLength == 1 else { return nil }

        let scalarCount = text.unicodeScalars.count
        guard error.start < scalarCount, error.end <= scalarCount else {
            Logger.debug("findSingleCharErrorContext: Error position \(error.start)-\(error.end) outside text bounds (\(scalarCount) scalars)", category: Logger.analysis)
            return nil
        }

        guard let errorIdx = TextIndexConverter.scalarIndexToStringIndex(error.start, in: text) else {
            Logger.debug("findSingleCharErrorContext: Failed to convert scalar index \(error.start) to string index", category: Logger.analysis)
            return nil
        }

        let char = text[errorIdx]
        guard char.isWhitespace || char.isPunctuation else { return nil }

        // Find word boundaries around the error
        var expandedStart = error.start
        var expandedEnd = error.end

        // Scan backward for word start
        if expandedStart > 0 {
            guard let idx = TextIndexConverter.scalarIndexToStringIndex(expandedStart - 1, in: text) else {
                Logger.debug("findSingleCharErrorContext: Failed to convert backward scan index \(expandedStart - 1)", category: Logger.analysis)
                return nil
            }
            var searchIdx = idx
            while searchIdx >= text.startIndex {
                let c = text[searchIdx]
                if c.isWhitespace || c.isNewline {
                    let nextIdx = text.index(after: searchIdx)
                    expandedStart = text.distance(from: text.startIndex, to: nextIdx)
                    break
                }
                expandedStart = text.distance(from: text.startIndex, to: searchIdx)
                if searchIdx == text.startIndex { break }
                searchIdx = text.index(before: searchIdx)
            }
        }

        // Scan forward for word end
        if expandedEnd < scalarCount {
            guard let idx = TextIndexConverter.scalarIndexToStringIndex(expandedEnd, in: text) else {
                Logger.debug("findSingleCharErrorContext: Failed to convert forward scan index \(expandedEnd)", category: Logger.analysis)
                return nil
            }
            var searchIdx = idx
            while searchIdx < text.endIndex {
                let c = text[searchIdx]
                if c.isWhitespace || c.isNewline {
                    expandedEnd = text.distance(from: text.startIndex, to: searchIdx)
                    break
                }
                searchIdx = text.index(after: searchIdx)
                expandedEnd = text.distance(from: text.startIndex, to: searchIdx)
            }
        }

        // Extract context and calculate offset
        guard let startIdx = TextIndexConverter.scalarIndexToStringIndex(expandedStart, in: text),
              let endIdx = TextIndexConverter.scalarIndexToStringIndex(expandedEnd, in: text),
              startIdx < endIdx
        else {
            Logger.debug("findSingleCharErrorContext: Failed to extract context at \(expandedStart)-\(expandedEnd)", category: Logger.analysis)
            return nil
        }

        let contextText = String(text[startIdx ..< endIdx])
        let offsetWithinContext = error.start - expandedStart

        // Only return if we actually expanded
        guard contextText.count > 1 else { return nil }

        return (contextText, offsetWithinContext)
    }

    /// Perform clipboard-based text replacement with activation, paste, and restore
    @MainActor
    private func performClipboardReplacement(suggestion: String, currentError: GrammarErrorModel, context: ApplicationContext, usesFocusPasteReplacement: Bool) async {
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        // Activate target app
        let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier).first
        targetApp?.activate()

        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.longDelay * 1_000_000_000))

        // Mac Catalyst: use direct keyboard typing
        if context.isMacCatalystApp {
            await performCatalystDirectTyping(suggestion: suggestion, currentError: currentError, pasteboard: pasteboard, originalString: originalString)
            return
        }

        // Apps with position 0 paragraph creation bug: use direct typing to avoid it
        // Some Chromium contenteditable apps create new paragraphs when pasting at position 0
        let appBehavior = AppBehaviorRegistry.shared.behavior(for: context.bundleIdentifier)
        if appBehavior.knownQuirks.contains(.requiresDirectTypingAtPosition0), currentError.start == 0 {
            Logger.debug("Position 0: Using direct typing to avoid paragraph bug", category: Logger.analysis)
            await performCatalystDirectTyping(suggestion: suggestion, currentError: currentError, pasteboard: pasteboard, originalString: originalString)
            return
        }

        // Try menu paste first (unless skipped for Catalyst/focus-paste apps)
        var pasteSucceeded = false
        let skipMenuPaste = context.isMacCatalystApp || usesFocusPasteReplacement

        if !skipMenuPaste, let app = targetApp {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            if let pasteMenuItem = findPasteMenuItem(in: appElement) {
                if AXUIElementPerformAction(pasteMenuItem, kAXPressAction as CFString) == .success {
                    pasteSucceeded = true
                    Logger.debug("Pasted via menu action", category: Logger.analysis)
                }
            }
        }

        // Keyboard fallback if menu failed
        let delay = context.keyboardOperationDelay
        let pasteCompleteDelay: TimeInterval
        if !pasteSucceeded {
            pasteCompleteDelay = delay + 0.1
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
            Logger.debug("Pasted via Cmd+V fallback", category: Logger.analysis)
        } else {
            pasteCompleteDelay = 0.1
        }

        try? await Task.sleep(nanoseconds: UInt64((pasteCompleteDelay + 0.15) * 1_000_000_000))

        // Restore clipboard if unchanged
        if pasteboard.changeCount == originalChangeCount + 1 {
            if let original = originalString {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        // Finalize replacement
        statistics.recordSuggestionApplied(category: currentError.category)
        let lengthDelta = suggestion.count - (currentError.end - currentError.start)
        removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)

        if usesFocusPasteReplacement {
            positionResolver.clearCache()
        } else {
            invalidateCacheAfterReplacement(at: currentError.start ..< currentError.end)
        }

        Logger.debug("Browser text replacement complete", category: Logger.analysis)
    }

    /// Handle Mac Catalyst apps using direct keyboard typing instead of clipboard paste
    @MainActor
    private func performCatalystDirectTyping(suggestion: String, currentError: GrammarErrorModel, pasteboard: NSPasteboard, originalString: String?) async {
        Logger.debug("Mac Catalyst: Using direct keyboard typing", category: Logger.analysis)
        typeTextDirectly(suggestion)

        if let original = originalString {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
        } else {
            pasteboard.clearContents()
        }

        let typingDelay = Double(suggestion.count) * 0.01 + 0.1
        try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))

        statistics.recordSuggestionApplied(category: currentError.category)
        invalidateCacheAfterReplacement(at: currentError.start ..< currentError.end)
        let lengthDelta = suggestion.count - (currentError.end - currentError.start)
        removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)
    }

    /// Convert String.Index to UTF-16 offset
    private func utf16Offset(of index: String.Index, in string: String) -> Int {
        string.utf16.distance(from: string.utf16.startIndex, to: index)
    }

    /// Standard keyboard-based text replacement (async version)
    @MainActor
    private func applyStandardKeyboardReplacementAsync(for error: GrammarErrorModel, with suggestion: String, element _: AXUIElement, context: ApplicationContext) async {
        // Activate target application
        if let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier).first {
            Logger.debug("Activating \(context.applicationName) to make it frontmost", category: Logger.analysis)
            targetApp.activate()
        }

        let delay = context.keyboardOperationDelay
        Logger.debug("Using \(delay)s keyboard delay for \(context.applicationName)", category: Logger.analysis)

        // Save suggestion to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        // Wait for activation
        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.keyboardActivationDelay * 1_000_000_000))

        // Step 1: Go to beginning (Cmd+Left)
        pressKey(key: 123, flags: .maskCommand)

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        // Step 2: Navigate to error start
        let navigationDelay = TimingConstants.arrowKeyDelay
        await sendArrowKeysAsync(count: error.start, keyCode: 124, flags: [], delay: navigationDelay)

        // Step 3: Select error text (Shift+Right)
        let errorLength = error.end - error.start
        await sendArrowKeysAsync(count: errorLength, keyCode: 124, flags: .maskShift, delay: navigationDelay)

        // Step 4: Paste (Cmd+V)
        pressKey(key: 9, flags: .maskCommand)

        Logger.debug("Keyboard-based text replacement complete", category: Logger.analysis)

        // Record statistics and update UI
        statistics.recordSuggestionApplied(category: error.category)
        invalidateCacheAfterReplacement(at: error.start ..< error.end)
        let lengthDelta = suggestion.count - (error.end - error.start)
        removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)
    }

    /// Try to replace text using AX API selection (for Terminal)
    /// Returns true if successful, false if needs to fall back to keyboard simulation
    func tryAXSelectionReplacement(element: AXUIElement, start: Int, end: Int, suggestion: String, error _: GrammarErrorModel) -> Bool {
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
        guard let rangeValue = AXValueCreate(.cfRange, &selectionRange) else {
            Logger.debug("AXValueCreate failed for selection range", category: Logger.analysis)
            return false
        }

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

        return true // Success - selection is set, caller will paste
    }

    /// Send multiple arrow keys with delay between each (async version)
    func sendArrowKeysAsync(count: Int, keyCode: CGKeyCode, flags: CGEventFlags, delay: TimeInterval) async {
        guard count > 0 else { return }

        for i in 0 ..< count {
            pressKey(key: keyCode, flags: flags)

            // Add delay between keys (except after the last one)
            if i < count - 1 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Send multiple arrow keys with delay between each (legacy completion handler)
    func sendArrowKeys(count: Int, keyCode: CGKeyCode, flags: CGEventFlags, delay: TimeInterval, completion: @escaping () -> Void) {
        Task { @MainActor in
            await self.sendArrowKeysAsync(count: count, keyCode: keyCode, flags: flags, delay: delay)
            completion()
        }
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
    func pressKey(key: CGKeyCode, flags: CGEventFlags, withDelay: Bool = true) {
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
            // Keep run loop responsive instead of blocking the thread
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// Invalidate cache after text replacement
    func invalidateCacheAfterReplacement(at range: Range<Int>) {
        // Clear position cache - geometry is now stale since text positions shifted
        positionResolver.clearCache()

        let bundleID = monitoredContext?.bundleIdentifier ?? ""
        let appConfig = appRegistry.configuration(for: bundleID)

        // Check if this app requires full re-analysis (Electron, WebKit, browsers)
        // These apps have fragile byte offsets that become invalid when text shifts
        if appConfig.features.requiresFullReanalysisAfterReplacement {
            // IMPORTANT: If we're in replacement mode, removeErrorAndUpdateUI has already:
            // - Removed the fixed error
            // - Adjusted positions of remaining errors
            // - Updated the popover and locked highlight
            // Don't undo that work! Just schedule delayed re-analysis to verify.
            if isInReplacementMode {
                Logger.trace("Cache invalidation: in replacement mode, scheduling delayed re-analysis", category: Logger.analysis)
                scheduleDelayedReanalysis(startTime: Date())
                return
            }

            Logger.trace("Cache invalidation: full re-analysis required for \(appConfig.displayName)", category: Logger.analysis)
            // Clear ALL errors and force complete re-analysis
            currentErrors.removeAll()
            errorOverlay.hide()
            floatingIndicator.hide()

            // Force fresh analysis by clearing cached text and re-extracting
            previousText = ""
            if let element = textMonitor.monitoredElement {
                Logger.trace("Cache invalidation: extracting text for re-analysis", category: Logger.analysis)
                textMonitor.extractText(from: element)
            } else {
                Logger.debug("Cache invalidation: no monitored element for re-analysis", category: Logger.analysis)
            }
        } else {
            Logger.trace("Cache invalidation: incremental update for native app", category: Logger.analysis)
            // For native apps: Just clear overlapping errors and trigger re-analysis
            currentErrors.removeAll { error in
                let errorRange = error.start ..< error.end
                return errorRange.overlaps(range)
            }

            // Trigger re-analysis
            if let segment = currentSegment {
                analyzeText(segment)
            }
        }
    }

    // MARK: - Fix All Obvious Errors

    /// Apply all single-suggestion fixes at once.
    /// Filters errors to only those with exactly one suggestion (obvious fixes),
    /// then applies them from end to start to avoid position shifts affecting earlier errors.
    /// Returns the number of fixes applied.
    @MainActor
    @discardableResult
    func applyAllSingleSuggestionFixes() async -> Int {
        // Safety check: ensure we have a monitored element
        guard let element = textMonitor.monitoredElement else {
            Logger.debug("Fix all obvious: No monitored element", category: Logger.analysis)
            return 0
        }

        // Safety check: validate that current text matches what we analyzed
        // This prevents applying fixes at wrong positions after app switch/refocus
        var currentTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentTextRef)
        if textResult == .success, let currentText = currentTextRef as? String {
            // Compare with lastAnalyzedText to ensure positions are still valid
            if !lastAnalyzedText.isEmpty, currentText != lastAnalyzedText {
                Logger.warning("Fix all obvious: Text content changed since analysis, skipping to avoid wrong positions", category: Logger.analysis)
                // Trigger re-analysis so errors get updated positions
                textMonitor.extractText(from: element)
                return 0
            }
        }

        // Filter to errors with exactly one suggestion
        let obviousFixes = currentErrors.filter { $0.suggestions.count == 1 }

        guard !obviousFixes.isEmpty else {
            Logger.debug("Fix all obvious: No single-suggestion errors to fix", category: Logger.analysis)
            return 0
        }

        Logger.info("Fix all obvious: Applying \(obviousFixes.count) fixes", category: Logger.analysis)

        // Sort by position descending (end to start) so text shifts don't affect earlier errors
        let sortedFixes = obviousFixes.sorted { $0.start > $1.start }

        // Hide popover during bulk fix
        SuggestionPopover.shared.hide()

        var fixCount = 0

        for error in sortedFixes {
            guard let suggestion = error.suggestions.first else { continue }

            Logger.debug("Fix all obvious: Applying fix at \(error.start)-\(error.end)", category: Logger.analysis)

            // Apply the fix
            await applyTextReplacementAsync(for: error, with: suggestion)
            fixCount += 1

            // Small delay between fixes for reliability (especially for keyboard-based replacements)
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        Logger.info("Fix all obvious: Applied \(fixCount) fixes", category: Logger.analysis)

        return fixCount
    }
}
