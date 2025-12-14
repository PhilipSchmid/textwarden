//
//  AnalysisCoordinator+TextReplacement.swift
//  TextWarden
//
//  Text replacement functionality extracted from AnalysisCoordinator
//  Handles applying grammar suggestions to text via accessibility APIs or keyboard simulation
//

import Foundation
import AppKit
@preconcurrency import ApplicationServices

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

        // Update lastAnalyzedText to reflect the replacement
        // This prevents validateCurrentText from thinking text changed (triggering re-analysis/hiding)
        // by computing what the new text should be after applying the replacement
        if !lastAnalyzedText.isEmpty {
            let errorRange = lastAnalyzedText.index(lastAnalyzedText.startIndex, offsetBy: min(error.start, lastAnalyzedText.count))..<lastAnalyzedText.index(lastAnalyzedText.startIndex, offsetBy: min(error.end, lastAnalyzedText.count))
            var updatedText = lastAnalyzedText
            updatedText.replaceSubrange(errorRange, with: suggestion)
            lastAnalyzedText = updatedText
            Logger.debug("removeErrorAndUpdateUI: Updated lastAnalyzedText to reflect replacement", category: Logger.analysis)
        }

        Logger.debug("removeErrorAndUpdateUI: UI updated, remaining errors: \(currentErrors.count)", category: Logger.analysis)
    }

    /// Apply text replacement for error
    /// Completion is called when the replacement is done (synchronously for AX API, async for keyboard)
    func applyTextReplacement(for error: GrammarErrorModel, with suggestion: String, completion: @escaping () -> Void) {
        Logger.debug("applyTextReplacement called - error: '\(error.message)', suggestion: '\(suggestion)'", category: Logger.analysis)

        guard let element = textMonitor.monitoredElement else {
            Logger.debug("No monitored element for text replacement", category: Logger.analysis)
            completion()
            return
        }

        Logger.debug("Have monitored element, context: \(monitoredContext?.applicationName ?? "nil")", category: Logger.analysis)

        // Mark replacement start time - used by grace period checks to prevent
        // scroll handling, text validation, and text change handlers from hiding the popover
        // during and shortly after the replacement. This is set here (at the top level)
        // to ensure ALL replacement paths (AX API, keyboard, browser) get the protection.
        lastReplacementTime = Date()

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

        // Step 2: Get current text to convert grapheme indices to UTF-16
        // Harper provides error positions in grapheme clusters, but macOS AX APIs use UTF-16 code units
        // This matters for text with emojis: 😉 = 1 grapheme but 2 UTF-16 code units
        var textRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef)
        let currentText = (textResult == .success) ? (textRef as? String) : nil

        // Convert grapheme cluster indices to UTF-16 for the AX API
        let utf16Location: Int
        let utf16Length: Int
        if let text = currentText {
            let utf16Range = convertToUTF16Range(NSRange(location: error.start, length: error.end - error.start), in: text)
            utf16Location = utf16Range.location
            utf16Length = utf16Range.length
        } else {
            // Fallback to grapheme indices if text retrieval fails (may be inaccurate for emoji text)
            utf16Location = error.start
            utf16Length = error.end - error.start
        }

        // Step 3: Set selection to error range (using UTF-16 indices)
        var errorRange = CFRange(location: utf16Location, length: utf16Length)
        guard let rangeValue = AXValueCreate(.cfRange, &errorRange) else {
            Logger.debug("AXValueCreate failed, using keyboard fallback", category: Logger.analysis)
            applyTextReplacementViaKeyboard(for: error, with: suggestion, element: element, completion: completion)
            return
        }

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

            // Invalidate cache
            invalidateCacheAfterReplacement(at: error.start..<error.end)

            // Step 4: Restore original selection (optional, move cursor after replacement)
            // Most apps expect cursor to be after the replacement
            var newPosition = CFRange(location: error.start + suggestion.count, length: 0)
            if let newRangeValue = AXValueCreate(.cfRange, &newPosition) {
                let _ = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    newRangeValue
                )
            }

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
    func applyStyleTextReplacement(for suggestion: StyleSuggestionModel) {
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

            // Note: Don't call invalidateCacheAfterReplacement for style replacements
            // Style suggestions use text matching, not byte offsets, so remaining suggestions stay valid
            // Also, invalidateCacheAfterReplacement triggers re-analysis which would clear style suggestions

            // Invalidate style cache since text changed
            styleCache.removeAll()
            styleCacheMetadata.removeAll()

            // Move cursor after replacement
            var newPosition = CFRange(location: startIndex + suggestion.suggestedText.count, length: 0)
            if let newRangeValue = AXValueCreate(.cfRange, &newPosition) {
                let _ = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    newRangeValue
                )
            }

            // Remove the applied style suggestion from tracking
            removeSuggestionFromTracking(suggestion)
            // Note: Don't clear remaining suggestions - we find them by text match, not byte offset
        } else {
            Logger.debug("AX API replacement failed for style (\(replaceError.rawValue)), trying keyboard fallback", category: Logger.analysis)
            applyStyleReplacementViaKeyboard(for: suggestion, element: element)
        }
    }

    /// Apply style replacement via keyboard simulation (for Electron apps and fallback)
    func applyStyleReplacementViaKeyboard(for suggestion: StyleSuggestionModel, element: AXUIElement) {
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

            // Invalidate style cache (not grammar cache - don't trigger re-analysis)
            self?.styleCache.removeAll()
            self?.styleCacheMetadata.removeAll()
            self?.removeSuggestionFromTracking(suggestion)
            // Note: Don't clear remaining suggestions - we find them by text match, not byte offset
        }
    }

    /// Apply style replacement for browsers
    func applyStyleBrowserReplacement(for suggestion: StyleSuggestionModel, element: AXUIElement, context: ApplicationContext) {
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

            // Invalidate style cache (not grammar cache - don't trigger re-analysis)
            self?.styleCache.removeAll()
            self?.styleCacheMetadata.removeAll()
            self?.removeSuggestionFromTracking(suggestion)
            // Note: Don't clear remaining suggestions - we find them by text match, not byte offset
        }
    }

    /// Remove an applied style suggestion from tracking and update UI
    func removeSuggestionFromTracking(_ suggestion: StyleSuggestionModel) {
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
    /// Legacy completion handler wrapper - delegates to async version
    func applyMailTextReplacement(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, completion: @escaping () -> Void) {
        Task { @MainActor in
            await self.applyMailTextReplacementAsync(for: error, with: suggestion, element: element)
            completion()
        }
    }

    /// Schedule delayed re-analysis after text replacement for apps with focus bounce behavior.
    /// WebKit/Electron apps may fire AXFocusedUIElementChanged during paste, clearing the monitored element.
    /// This waits for focus to settle, then restarts monitoring to find the composition element.
    func scheduleDelayedReanalysis(startTime: Date) {
        guard let context = monitoredContext else { return }
        let appConfig = AppRegistry.shared.configuration(for: context.bundleIdentifier)
        guard appConfig.features.focusBouncesDuringPaste else { return }

        Logger.trace("Focus bounce reanalysis: T=\(Int(Date().timeIntervalSince(startTime) * 1000))ms scheduling", category: Logger.analysis)

        // Wait 300ms for focus to settle after focus bounce
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.hoverDelay) { [weak self] in
            guard let self = self else { return }
            guard let context = self.monitoredContext else { return }

            let appConfig = AppRegistry.shared.configuration(for: context.bundleIdentifier)
            guard appConfig.features.focusBouncesDuringPaste else {
                Logger.trace("Focus bounce reanalysis: skipping - app no longer has focus bounce", category: Logger.analysis)
                return
            }

            Logger.trace("Focus bounce reanalysis: T=\(Int(Date().timeIntervalSince(startTime) * 1000))ms starting", category: Logger.analysis)

            // If we have a monitored element and remaining errors, just refresh the overlay
            if self.textMonitor.monitoredElement != nil && !self.currentErrors.isEmpty {
                Logger.trace("Focus bounce reanalysis: have element and errors, refreshing overlay", category: Logger.analysis)
                if let element = self.textMonitor.monitoredElement {
                    self.showErrorUnderlines(self.currentErrors, element: element)
                }
                return
            }

            // No monitored element - restart monitoring to re-acquire the composition element
            Logger.trace("Focus bounce reanalysis: no element, restarting monitoring", category: Logger.analysis)

            self.textMonitor.stopMonitoring()
            self.textMonitor.startMonitoring(
                processID: context.processID,
                bundleIdentifier: context.bundleIdentifier,
                appName: context.applicationName
            )

            // After monitoring restarts, extract text to trigger analysis
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.mediumDelay) { [weak self] in
                guard let self = self else { return }
                Logger.trace("Focus bounce reanalysis: T=\(Int(Date().timeIntervalSince(startTime) * 1000))ms extracting text", category: Logger.analysis)

                if let element = self.textMonitor.monitoredElement {
                    self.textMonitor.extractText(from: element)
                } else {
                    Logger.debug("Focus bounce reanalysis: still no element after restart", category: Logger.analysis)
                }
            }
        }
    }

    /// WebKit-specific cache invalidation that only clears position cache, not errors.
    /// Used when removeErrorAndUpdateUI already handled error adjustments.
    /// This just clears the position cache so underlines are recalculated at new positions.
    func invalidateCacheAfterReplacementForWebKit(at range: Range<Int>) {
        Logger.trace("WebKit cache invalidation: clearing position cache only", category: Logger.analysis)

        // Clear position cache - geometry is now stale since text positions shifted
        PositionResolver.shared.clearCache()

        // Hide overlays temporarily while we recalculate positions
        errorOverlay.hide()

        // Clear previousText so the next text change triggers analysis
        previousText = ""

        // DON'T clear currentErrors - removeErrorAndUpdateUI already handled that
        // DON'T call textMonitor.extractText - we already have the correct errors
        // Just need to recalculate underline positions for remaining errors
        if let element = textMonitor.monitoredElement, !currentErrors.isEmpty {
            Logger.trace("WebKit cache invalidation: refreshing \(currentErrors.count) remaining errors", category: Logger.analysis)
            showErrorUnderlines(currentErrors, element: element)
        }
    }

    /// Apply text replacement for browsers using menu action with keyboard fallback
    /// Browsers often have silently failing AX APIs, so we use SelectedTextKit's approach:
    /// 1. Try to select text range via AX API (even if it silently fails)
    /// 2. Copy suggestion to clipboard
    /// 3. Try paste via menu action (more reliable)
    /// 4. Fallback to Cmd+V if menu fails
    func applyBrowserTextReplacement(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, context: ApplicationContext, completion: @escaping () -> Void) {
        Logger.debug("Browser text replacement for \(context.applicationName)", category: Logger.analysis)

        // Mark that we're applying a suggestion - prevents typing callback and scroll handling from hiding overlays
        lastReplacementTime = Date()

        let isMicrosoftOffice = context.bundleIdentifier == "com.microsoft.Word" ||
                                context.bundleIdentifier == "com.microsoft.Powerpoint"

        // For Microsoft Office: Get the error text from the ORIGINAL error positions in lastAnalyzedText
        // Then search for that text in the LIVE document to find current position
        // This handles position shifts from previous replacements
        let errorText: String
        let fallbackRange: CFRange?

        // Define currentError at top level - for Microsoft Office we use the original error,
        // for other apps we look up from currentErrors to get adjusted positions
        let currentError: GrammarErrorModel

        if isMicrosoftOffice {
            // For Microsoft Office, use the original error for statistics/tracking
            // The actual replacement position is determined by searching the live document
            currentError = error

            // Microsoft Office replacement strategy:
            // 1. Get live text from AXValue (handles document state correctly)
            // 2. For capitalization errors (tHis → This): find text with unusual mid-word caps
            // 3. For spelling errors (brrief → brief): search for exact error text
            // 4. Use UTF-16 offsets for position (Office AX API uses UTF-16, handles emojis)

            // Helper to convert String.Index to UTF-16 offset
            func utf16Offset(of index: String.Index, in string: String) -> Int {
                return string.utf16.distance(from: string.utf16.startIndex, to: index)
            }

            // Helper to detect unusual capitalization (mid-word capitals like "tHis")
            func hasUnusualCapitalization(_ text: String) -> Bool {
                let chars = Array(text)
                for i in 1..<chars.count {
                    // Capital letter after lowercase = unusual (e.g., "tHis")
                    if chars[i-1].isLowercase && chars[i].isUppercase {
                        return true
                    }
                }
                return false
            }

            // Get live text from document
            var liveTextRef: CFTypeRef?
            var liveText = ""
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &liveTextRef) == .success,
               let text = liveTextRef as? String {
                liveText = text
            }

            if liveText.isEmpty {
                Logger.warning("Office replacement: Could not get live text", category: Logger.analysis)
            }

            Logger.debug("Office replacement: Live text has \(liveText.count) chars, suggestion is '\(suggestion)'", category: Logger.analysis)

            var foundRange: CFRange? = nil
            var foundText = ""

            // Strategy 1: Find capitalization errors by case-insensitive search
            // Collect all matches and prioritize ones with unusual capitalization
            var allMatches: [(range: Range<String.Index>, text: String)] = []
            var searchStart = liveText.startIndex
            while searchStart < liveText.endIndex {
                let searchRange = searchStart..<liveText.endIndex
                if let range = liveText.range(of: suggestion, options: .caseInsensitive, range: searchRange) {
                    allMatches.append((range: range, text: String(liveText[range])))
                    searchStart = range.upperBound
                } else {
                    break
                }
            }

            Logger.debug("Office replacement: Found \(allMatches.count) case-insensitive matches for '\(suggestion)'", category: Logger.analysis)

            // Priority 1: Match with unusual capitalization (like "tHis")
            for match in allMatches {
                if hasUnusualCapitalization(match.text) {
                    let start = utf16Offset(of: match.range.lowerBound, in: liveText)
                    let length = match.text.utf16.count
                    foundRange = CFRange(location: start, length: length)
                    foundText = match.text
                    Logger.debug("Office replacement: Found unusual-caps '\(match.text)' at UTF-16 position \(start)-\(start + length)", category: Logger.analysis)
                    break
                }
            }

            // Priority 2: Any match that differs from suggestion (wrong case)
            if foundRange == nil {
                for match in allMatches where match.text != suggestion {
                    let start = utf16Offset(of: match.range.lowerBound, in: liveText)
                    let length = match.text.utf16.count
                    foundRange = CFRange(location: start, length: length)
                    foundText = match.text
                    Logger.debug("Office replacement: Found case-variant '\(match.text)' at UTF-16 position \(start)-\(start + length)", category: Logger.analysis)
                    break
                }
            }

            // Strategy 2: For spelling errors, extract error text and search exactly
            if foundRange == nil {
                let cachedText = self.lastAnalyzedText.isEmpty ? (self.currentSegment?.content ?? "") : self.lastAnalyzedText

                // Extract original error text from cached analysis
                // Note: error.start/end are Unicode scalar indices from Harper, need conversion
                var errorTextFromCache = ""
                let scalarCount = cachedText.unicodeScalars.count
                if !cachedText.isEmpty && error.start < scalarCount && error.end <= scalarCount,
                   let startIdx = scalarIndexToStringIndex(error.start, in: cachedText),
                   let endIdx = scalarIndexToStringIndex(error.end, in: cachedText) {
                    errorTextFromCache = String(cachedText[startIdx..<endIdx])
                    Logger.debug("Office replacement: Extracted error text '\(errorTextFromCache)' from cached text (scalar indices \(error.start)-\(error.end))", category: Logger.analysis)
                }

                // Search for exact error text in live document
                if !errorTextFromCache.isEmpty, let exactRange = liveText.range(of: errorTextFromCache) {
                    let start = utf16Offset(of: exactRange.lowerBound, in: liveText)
                    let length = errorTextFromCache.utf16.count
                    foundRange = CFRange(location: start, length: length)
                    foundText = errorTextFromCache
                    Logger.debug("Office replacement: Found exact error text '\(errorTextFromCache)' at UTF-16 position \(start)-\(start + length)", category: Logger.analysis)
                }
            }

            // Final result
            if let range = foundRange {
                fallbackRange = range
                errorText = foundText
            } else {
                // Last resort: use Harper's original positions (may be wrong with emojis)
                Logger.warning("Office replacement: Could not find error text in live document, using original positions \(error.start)-\(error.end)", category: Logger.analysis)
                fallbackRange = CFRange(location: error.start, length: error.end - error.start)
                errorText = suggestion
            }
        } else {
            // For other apps: use the existing lookup logic
            currentError = currentErrors.first { err in
                err.message == error.message && err.lintId == error.lintId && err.category == error.category
            } ?? error

            Logger.debug("Browser replacement: Using positions \(currentError.start)-\(currentError.end) (original was \(error.start)-\(error.end))", category: Logger.analysis)

            // Note: currentError.start/end are Unicode scalar indices from Harper, need conversion
            let cachedText = self.lastAnalyzedText.isEmpty ? (self.currentSegment?.content ?? self.previousText) : self.lastAnalyzedText
            let scalarCount = cachedText.unicodeScalars.count
            if !cachedText.isEmpty && currentError.start < scalarCount && currentError.end <= scalarCount,
               let startIdx = scalarIndexToStringIndex(currentError.start, in: cachedText),
               let endIdx = scalarIndexToStringIndex(currentError.end, in: cachedText) {
                errorText = String(cachedText[startIdx..<endIdx])
                Logger.debug("Browser replacement: Extracted error text '\(errorText)' from scalar positions \(currentError.start)-\(currentError.end)", category: Logger.analysis)
            } else {
                errorText = ""
                Logger.debug("Browser replacement: Could not extract error text, will use fallback", category: Logger.analysis)
            }

            if errorText.isEmpty {
                fallbackRange = CFRange(location: currentError.start, length: currentError.end - currentError.start)
            } else {
                fallbackRange = nil
            }
        }

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

        // Step 4: Activate the target app and capture reference for later
        // Capture reference BEFORE async block to ensure we paste into correct app
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier)
        let targetApp = apps.first
        if let app = targetApp {
            app.activate()
            Logger.debug("Activated \(context.applicationName) (pid: \(app.processIdentifier))", category: Logger.analysis)
        }

        // Step 5: Wait for activation, then paste (replaces selected text)
        // NOTE: We use direct paste-over-selection. While this doesn't create separate undo
        // operations in Mac Catalyst apps (undo may not work correctly), it avoids spacing
        // issues that occur with Delete+Paste approach.
        let delay = context.keyboardOperationDelay

        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.longDelay) { [weak self] in
            guard let self = self else { return }
            var pasteSucceeded = false

            // Skip menu paste for Mac Catalyst apps - AXPressAction returns success but doesn't work
            // Mac Catalyst's AX bridge is incomplete and menu actions are unreliable
            // Also skip for Microsoft Office - accessing Edit menu causes document refresh/revert issues
            let skipMenuPaste = context.isMacCatalystApp || isMicrosoftOffice
            if skipMenuPaste {
                Logger.debug("Skipping menu paste for \(context.applicationName) - using keyboard fallback", category: Logger.analysis)
            } else if let app = targetApp {
                // Try menu action paste for non-Catalyst apps (more reliable for browsers)
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                Logger.debug("Targeting app for paste: \(app.localizedName ?? "unknown") (pid: \(app.processIdentifier))", category: Logger.analysis)

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
                    Logger.debug("Could not find Paste menu item in \(app.localizedName ?? "app")", category: Logger.analysis)
                }
            } else {
                Logger.debug("No target app found for bundle: \(context.bundleIdentifier)", category: Logger.analysis)
            }

            // Step 6: For Mac Catalyst apps, use direct keyboard typing instead of paste
            // This bypasses clipboard issues entirely by simulating keystrokes with Unicode strings
            // Based on the Force-Paste approach: https://github.com/EugeneDae/Force-Paste
            if context.isMacCatalystApp {
                Logger.debug("Mac Catalyst app: Using direct keyboard typing instead of paste", category: Logger.analysis)

                // Type the suggestion character by character using CGEvent
                self.typeTextDirectly(suggestion)

                // Restore pasteboard immediately since we didn't use it
                if let originalContent = originalString {
                    pasteboard.clearContents()
                    pasteboard.setString(originalContent, forType: .string)
                    Logger.debug("Restored original pasteboard content", category: Logger.analysis)
                } else {
                    pasteboard.clearContents()
                }

                // Wait a bit for typing to complete, then finish up
                let typingDelay = Double(suggestion.count) * 0.01 + 0.1  // ~10ms per char + buffer
                DispatchQueue.main.asyncAfter(deadline: .now() + typingDelay) { [weak self] in
                    guard let self = self else { return }
                    // Record statistics
                    UserStatistics.shared.recordSuggestionApplied(category: currentError.category)

                    // Invalidate cache
                    self.invalidateCacheAfterReplacement(at: currentError.start..<currentError.end)

                    // Remove error from UI
                    let lengthDelta = suggestion.count - (currentError.end - currentError.start)
                    self.removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)

                    Logger.debug("Mac Catalyst text replacement complete via direct typing", category: Logger.analysis)
                    completion()
                }
                return
            }

            // Step 6b: For non-Catalyst apps, use keyboard shortcut fallback if menu failed
            let pasteCompleteDelay: TimeInterval
            if !pasteSucceeded {
                // Need to wait for keyboard fallback delay + paste execution time
                pasteCompleteDelay = delay + 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
                    Logger.debug("Pasted via keyboard shortcut (Cmd+V fallback)", category: Logger.analysis)
                }
            } else {
                // Menu paste is faster
                pasteCompleteDelay = 0.1
            }

            // Step 7: Wait for paste to complete, then restore pasteboard and signal completion
            let completionDelay = pasteCompleteDelay + 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) { [weak self] in
                guard let self = self else { return }
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

                // IMPORTANT: Call removeErrorAndUpdateUI FIRST
                // This removes the fixed error, updates currentSegment, and adjusts positions of remaining errors
                let lengthDelta = suggestion.count - (currentError.end - currentError.start)
                self.removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)

                // For Microsoft Office: DON'T trigger re-analysis after replacement
                // removeErrorAndUpdateUI already adjusted positions correctly, and async re-analysis
                // can produce wrong results due to timing issues (Harper might analyze stale AXValue)
                // Just clear position cache so underlines are recalculated
                let isMicrosoftOffice = context.bundleIdentifier == "com.microsoft.Word" ||
                                        context.bundleIdentifier == "com.microsoft.Powerpoint"
                if isMicrosoftOffice {
                    PositionResolver.shared.clearCache()
                    Logger.debug("Office: Skipping re-analysis, just cleared position cache", category: Logger.analysis)
                } else {
                    self.invalidateCacheAfterReplacement(at: currentError.start..<currentError.end)
                }

                Logger.debug("Browser text replacement complete (waited \(completionDelay)s)", category: Logger.analysis)

                // Signal completion to the popover - safe to advance to next error now
                completion()
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
              CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() else {
            return nil
        }
        // Safe: type verified by CFGetTypeID check above
        let menuBar = unsafeBitCast(menuBarRef, to: AXUIElement.self)

        // Try to find "Edit" menu
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let childrenArray = childrenValue as? [AXUIElement] else {
            return nil
        }

        let children = childrenArray

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
    func selectTextForReplacement(
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
                guard let currentText = currentText else {
                    Logger.debug("Could not get current text for browser replacement", category: Logger.analysis)
                    return false
                }

                guard let textRange = currentText.range(of: targetText) else {
                    Logger.debug("Could not find text '\(targetText)' in current content", category: Logger.analysis)
                    return false
                }

                // Convert grapheme indices to UTF-16 indices for AX selection
                // Required for: Mac Catalyst apps, Chromium-based browsers (like Comet), and any app using UTF-16 offsets
                // Emojis and other multi-codepoint characters cause offset issues without this conversion
                let startIndex = currentText.distance(from: currentText.startIndex, to: textRange.lowerBound)
                let utf16Range = convertToUTF16Range(NSRange(location: startIndex, length: targetText.count), in: currentText)
                var calculatedRange = CFRange(location: utf16Range.location, length: utf16Range.length)
                Logger.debug("Browser selection: Converted range from grapheme [\(startIndex), \(targetText.count)] to UTF-16 [\(utf16Range.location), \(utf16Range.length)]", category: Logger.analysis)

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
            if let text = currentText {
                let graphemeRange = NSRange(location: range.location, length: range.length)
                let utf16Range = convertToUTF16Range(graphemeRange, in: text)
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

    /// Convert grapheme cluster indices to UTF-16 code unit indices.
    /// Mac Catalyst apps and some accessibility APIs use UTF-16 code units,
    /// while Swift String indices are grapheme clusters.
    /// This matters for text containing emojis: 🖐️ is 1 grapheme but 3-4 UTF-16 code units.
    func convertToUTF16Range(_ range: NSRange, in text: String) -> NSRange {
        let textCount = text.count
        let safeLocation = min(range.location, textCount)
        let safeEndLocation = min(range.location + range.length, textCount)

        // Get String.Index for the grapheme cluster positions
        guard let startIndex = text.index(text.startIndex, offsetBy: safeLocation, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: safeEndLocation, limitedBy: text.endIndex) else {
            // Fallback to original range if conversion fails
            return range
        }

        // Extract the prefix strings and measure their UTF-16 lengths
        let prefixToStart = String(text[..<startIndex])
        let prefixToEnd = String(text[..<endIndex])

        let utf16Location = (prefixToStart as NSString).length
        let utf16EndLocation = (prefixToEnd as NSString).length
        let utf16Length = max(1, utf16EndLocation - utf16Location)

        return NSRange(location: utf16Location, length: utf16Length)
    }

    /// Convert a Unicode scalar index to a String.Index.
    /// Harper (via Rust) uses Unicode scalar indices (Rust's `char` count),
    /// but Swift String operations use grapheme cluster indices.
    /// Emojis like ❗️ are 2 scalars (U+2757 + U+FE0F) but 1 grapheme cluster.
    func scalarIndexToStringIndex(_ scalarIndex: Int, in string: String) -> String.Index? {
        let scalars = string.unicodeScalars
        var scalarCount = 0
        var currentIndex = string.startIndex

        while currentIndex < string.endIndex {
            if scalarCount == scalarIndex {
                return currentIndex
            }
            // Count how many scalars are in this grapheme cluster
            let nextIndex = string.index(after: currentIndex)
            let scalarStart = currentIndex.samePosition(in: scalars) ?? scalars.startIndex
            let scalarEnd = nextIndex.samePosition(in: scalars) ?? scalars.endIndex
            let scalarsInCluster = scalars.distance(from: scalarStart, to: scalarEnd)
            scalarCount += scalarsInCluster
            currentIndex = nextIndex
        }

        // If scalarIndex equals total scalar count, return endIndex
        if scalarCount == scalarIndex {
            return string.endIndex
        }

        return nil
    }

    /// Type text directly using CGEvent keyboard events with Unicode strings.
    /// This bypasses the clipboard entirely, which is needed for Mac Catalyst apps
    /// where clipboard paste operations are unreliable.
    /// Based on the Force-Paste approach: https://github.com/EugeneDae/Force-Paste
    /// See Apple docs: https://developer.apple.com/documentation/coregraphics/1456028-cgeventkeyboardsetunicodestring
    func typeTextDirectly(_ text: String) {
        Logger.debug("Typing text directly: '\(text)' (\(text.count) chars)", category: Logger.analysis)

        let source = CGEventSource(stateID: .hidSystemState)

        // Convert the entire text to UTF-16 for CGEventKeyboardSetUnicodeString
        var utf16Chars = Array(text.utf16)

        // Create key down event with the Unicode string
        // Virtual key 0 is 'a', but the Unicode string overrides it
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
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
    func findChildElementContainingText(_ targetText: String, in element: AXUIElement) -> (AXUIElement, Int)? {
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
           text.contains(targetText) {

            var sizeValue: CFTypeRef?
            var height: CGFloat = 0
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let size = sizeValue,
               let rectSize = safeAXValueGetSize(size) {
                height = rectSize.height
            }

            // Prefer smaller elements (paragraph-level, not document-level)
            if height > 0 && height < GeometryConstants.maximumLineHeight {
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
    /// Legacy completion handler wrapper - delegates to async version
    func applyTextReplacementViaKeyboard(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, completion: @escaping () -> Void) {
        Task { @MainActor in
            await self.applyTextReplacementViaKeyboardAsync(for: error, with: suggestion, element: element)
            completion()
        }
    }

    /// Apply text replacement using keyboard simulation (async version)
    /// Flattened async/await implementation for better readability
    @MainActor
    func applyTextReplacementViaKeyboardAsync(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement) async {
        guard let context = self.monitoredContext else {
            Logger.debug("No context available for keyboard replacement", category: Logger.analysis)
            return
        }

        Logger.debug("Using keyboard simulation for text replacement (app: \(context.applicationName), isTerminal: \(context.isTerminalApp), isBrowser: \(context.isBrowser))", category: Logger.analysis)

        // SPECIAL HANDLING FOR APPLE MAIL
        if context.bundleIdentifier == "com.apple.mail" {
            await applyMailTextReplacementAsync(for: error, with: suggestion, element: element)
            return
        }

        // SPECIAL HANDLING FOR BROWSERS, SLACK, MICROSOFT OFFICE, AND MAC CATALYST APPS
        // Use the full-featured completion-handler version via continuation
        // (The async version is simplified and missing Office/Catalyst special handling)
        let isSlack = context.bundleIdentifier == "com.tinyspeck.slackmacgap"
        let isMessages = context.bundleIdentifier == "com.apple.MobileSMS"
        let isMicrosoftOffice = context.bundleIdentifier == "com.microsoft.Word" ||
                                context.bundleIdentifier == "com.microsoft.Powerpoint"
        if context.isBrowser || isSlack || isMessages || isMicrosoftOffice || context.isMacCatalystApp {
            await withCheckedContinuation { continuation in
                self.applyBrowserTextReplacement(for: error, with: suggestion, element: element, context: context) {
                    continuation.resume()
                }
            }
            return
        }

        // SPECIAL HANDLING FOR TERMINALS
        if context.isTerminalApp {
            await applyTerminalTextReplacementAsync(for: error, with: suggestion, element: element, context: context)
            return
        }

        // For non-terminal apps, use standard keyboard navigation
        await applyStandardKeyboardReplacementAsync(for: error, with: suggestion, element: element, context: context)
    }

    /// Terminal-specific text replacement (async version)
    @MainActor
    private func applyTerminalTextReplacementAsync(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, context: ApplicationContext) async {
        // Get original cursor position
        var selectedRangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)

        var originalCursorPosition: Int?
        if rangeResult == .success, let rangeValue = selectedRangeValue, let cfRange = safeAXValueGetRange(rangeValue) {
            originalCursorPosition = cfRange.location
            Logger.debug("Terminal: Original cursor position: \(cfRange.location)", category: Logger.analysis)
        }

        // Get current text
        var currentTextValue: CFTypeRef?
        let getTextResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentTextValue)
        guard getTextResult == .success, let fullText = currentTextValue as? String else {
            Logger.debug("Failed to get current text for Terminal replacement", category: Logger.analysis)
            return
        }

        // Preprocess to get command line text
        let parser = ContentParserFactory.shared.parser(for: context.bundleIdentifier)
        guard let commandLineText = parser.preprocessText(fullText) else {
            Logger.debug("Failed to preprocess text for Terminal", category: Logger.analysis)
            return
        }

        // Apply correction
        guard let startIndex = scalarIndexToStringIndex(error.start, in: commandLineText),
              let endIndex = scalarIndexToStringIndex(error.end, in: commandLineText) else {
            Logger.warning("Terminal: Failed to convert scalar indices", category: Logger.analysis)
            return
        }
        var correctedText = commandLineText
        correctedText.replaceSubrange(startIndex..<endIndex, with: suggestion)

        Logger.debug("Terminal: Corrected command: '\(correctedText)'", category: Logger.analysis)

        // Calculate target cursor position
        var targetCursorPosition: Int?
        if let axCursorPos = originalCursorPosition {
            let commandRange = (fullText as NSString).range(of: commandLineText)
            if commandRange.location != NSNotFound {
                let promptOffset = commandRange.location
                let cursorInCommandLine = axCursorPos - promptOffset
                let errorLength = error.end - error.start
                let lengthDelta = suggestion.count - errorLength

                if cursorInCommandLine < error.start {
                    targetCursorPosition = cursorInCommandLine
                } else if cursorInCommandLine >= error.end {
                    targetCursorPosition = cursorInCommandLine + lengthDelta
                } else {
                    targetCursorPosition = error.start + suggestion.count
                }
            }
        }

        // Copy corrected text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(correctedText, forType: .string)

        // Activate Terminal
        if let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier).first {
            targetApp.activate()
        }

        // Wait for activation
        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.longDelay * 1_000_000_000))

        // Step 1: Ctrl+A to go to beginning
        pressKey(key: VirtualKeyCode.a, flags: .maskControl)
        Logger.debug("Sent Ctrl+A", category: Logger.analysis)

        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.shortDelay * 1_000_000_000))

        // Step 2: Ctrl+K to kill to end of line
        pressKey(key: VirtualKeyCode.k, flags: .maskControl)
        Logger.debug("Sent Ctrl+K", category: Logger.analysis)

        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.shortDelay * 1_000_000_000))

        // Step 3: Paste the corrected text
        pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
        Logger.debug("Sent Cmd+V", category: Logger.analysis)

        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.shortDelay * 1_000_000_000))

        // Step 4: Position cursor
        if let targetPos = targetCursorPosition {
            pressKey(key: VirtualKeyCode.a, flags: .maskControl)
            try? await Task.sleep(nanoseconds: UInt64(TimingConstants.tinyDelay * 1_000_000_000))

            for _ in 0..<targetPos {
                pressKey(key: VirtualKeyCode.rightArrow, flags: [], withDelay: false)
            }
            Logger.debug("Terminal replacement complete (cursor at position \(targetPos))", category: Logger.analysis)
        } else {
            pressKey(key: VirtualKeyCode.e, flags: .maskControl)
            Logger.debug("Terminal replacement complete (cursor at end)", category: Logger.analysis)
        }

        // Record statistics and update UI
        UserStatistics.shared.recordSuggestionApplied(category: error.category)
        invalidateCacheAfterReplacement(at: error.start..<error.end)
        let lengthDelta = suggestion.count - (error.end - error.start)
        removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)
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
            UserStatistics.shared.recordSuggestionApplied(category: currentError.category)
            invalidateCacheAfterReplacement(at: currentError.start..<currentError.end)
            removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)
            return
        }

        // Fallback: selection + paste
        Logger.debug("Mail: AXReplaceRangeWithText failed, falling back to selection + paste", category: Logger.analysis)
        let _ = MailContentParser.selectTextForReplacement(range: range, in: element)

        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        // Activate Mail
        if let mailApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first {
            mailApp.activate()
        }

        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.shortDelay * 1_000_000_000))

        pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
        UserStatistics.shared.recordSuggestionApplied(category: currentError.category)
        removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)
        invalidateCacheAfterReplacementForWebKit(at: currentError.start..<currentError.end)

        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.shortDelay * 1_000_000_000))

        if let original = originalString {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
        }
        replacementCompletedAt = Date()
        scheduleDelayedReanalysis(startTime: Date())
    }

    /// Apply text replacement for browsers and similar apps (async version)
    /// Uses keyboard navigation approach for simplicity
    @MainActor
    func applyBrowserTextReplacementAsync(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, context: ApplicationContext) async {
        Logger.debug("Browser text replacement (async) for \(context.applicationName)", category: Logger.analysis)

        lastReplacementTime = Date()

        let currentError = currentErrors.first { err in
            err.message == error.message && err.lintId == error.lintId && err.category == error.category
        } ?? error

        let lengthDelta = suggestion.count - (currentError.end - currentError.start)

        // Save clipboard
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        // Activate app
        if let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier).first {
            targetApp.activate()
        }

        let delay = context.keyboardOperationDelay

        // Use keyboard navigation approach
        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.keyboardActivationDelay * 1_000_000_000))

        // Go to beginning (Cmd+Left)
        pressKey(key: 123, flags: .maskCommand)

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        // Navigate to error start
        let navigationDelay = TimingConstants.arrowKeyDelay
        await sendArrowKeysAsync(count: currentError.start, keyCode: 124, flags: [], delay: navigationDelay)

        // Select error text
        let errorLength = currentError.end - currentError.start
        await sendArrowKeysAsync(count: errorLength, keyCode: 124, flags: .maskShift, delay: navigationDelay)

        // Paste
        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.shortDelay * 1_000_000_000))
        pressKey(key: VirtualKeyCode.v, flags: .maskCommand)

        Logger.debug("Browser paste complete", category: Logger.analysis)

        UserStatistics.shared.recordSuggestionApplied(category: currentError.category)
        removeErrorAndUpdateUI(currentError, suggestion: suggestion, lengthDelta: lengthDelta)
        invalidateCacheAfterReplacementForWebKit(at: currentError.start..<currentError.end)

        // Restore clipboard
        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.clipboardRestoreDelay * 1_000_000_000))
        if let original = originalString {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
        }
        replacementCompletedAt = Date()
        scheduleDelayedReanalysis(startTime: Date())
    }

    /// Standard keyboard-based text replacement (async version)
    @MainActor
    private func applyStandardKeyboardReplacementAsync(for error: GrammarErrorModel, with suggestion: String, element: AXUIElement, context: ApplicationContext) async {
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
        UserStatistics.shared.recordSuggestionApplied(category: error.category)
        invalidateCacheAfterReplacement(at: error.start..<error.end)
        let lengthDelta = suggestion.count - (error.end - error.start)
        removeErrorAndUpdateUI(error, suggestion: suggestion, lengthDelta: lengthDelta)
    }

    /// Try to replace text using AX API selection (for Terminal)
    /// Returns true if successful, false if needs to fall back to keyboard simulation
    func tryAXSelectionReplacement(element: AXUIElement, start: Int, end: Int, suggestion: String, error: GrammarErrorModel) -> Bool {
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

        return true  // Success - selection is set, caller will paste
    }

    /// Send multiple arrow keys with delay between each (async version)
    func sendArrowKeysAsync(count: Int, keyCode: CGKeyCode, flags: CGEventFlags, delay: TimeInterval) async {
        guard count > 0 else { return }

        for i in 0..<count {
            self.pressKey(key: keyCode, flags: flags)

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
        PositionResolver.shared.clearCache()

        let bundleID = monitoredContext?.bundleIdentifier ?? ""
        let appConfig = AppRegistry.shared.configuration(for: bundleID)

        // Check if this app requires full re-analysis (Electron, WebKit, browsers)
        // These apps have fragile byte offsets that become invalid when text shifts
        if appConfig.features.requiresFullReanalysisAfterReplacement {
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
