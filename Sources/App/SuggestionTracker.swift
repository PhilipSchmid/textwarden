//
//  SuggestionTracker.swift
//  TextWarden
//
//  Unified suggestion tracking for loop prevention.
//  Replaces multiple disparate mechanisms: styleCache, dismissedStyleSuggestionHashes,
//  dismissedReadabilitySentenceHashes, styleAnalysisSuppressedUntilUserEdit.
//

import Foundation

// Note: SuggestionImpact is defined in StyleTypes.swift as a public enum

/// Sensitivity level for style suggestions, controlled by user preference
enum StyleSensitivity: String, CaseIterable {
    /// Show only high-impact suggestions
    case minimal
    /// Show high and medium-impact suggestions (default)
    case balanced
    /// Show all suggestions including low-impact
    case detailed

    var displayName: String {
        switch self {
        case .minimal: "Minimal"
        case .balanced: "Balanced"
        case .detailed: "Detailed"
        }
    }

    /// Minimum impact level to show for this sensitivity
    var minimumImpact: SuggestionImpact {
        switch self {
        case .minimal: .high
        case .balanced: .medium
        case .detailed: .low
        }
    }
}

/// Unified tracking for suggestion loop prevention.
/// Tracks which text spans have been modified by accepted suggestions,
/// which suggestions have been shown, and enforces filtering criteria.
final class SuggestionTracker {
    // MARK: - Configuration

    /// Minimum confidence score to show a style suggestion (0.0-1.0)
    let confidenceThreshold: Float = 0.7

    /// Maximum number of style suggestions to show per document in auto-check mode
    let maxStyleSuggestionsPerDocument: Int = 5

    /// Cooldown period before re-suggesting the same content (seconds)
    let suggestionCooldown: TimeInterval = 300 // 5 minutes

    /// Grace period after accepting a suggestion before re-analysis (seconds)
    let modificationGracePeriod: TimeInterval = 2.0

    // MARK: - Tracking State

    /// Tracks text spans that have been modified by accepting suggestions.
    /// Key: Hash of the original text content before modification
    /// Value: Timestamp when the modification occurred
    private var modifiedSpans: [Int: Date] = [:]

    /// Tracks suggestions that have been shown to prevent repeated display.
    /// Key: Suggestion key (hash of text content + category + source)
    /// Value: Timestamp when last shown
    private var shownSuggestions: [String: Date] = [:]

    /// Tracks dismissed suggestions that should not be shown again.
    /// Key: Hash of original text content
    private var dismissedSuggestions: Set<Int> = []

    /// Tracks simplified readability sentences to prevent re-flagging.
    /// Key: Hash of the simplified (new) text
    private var simplifiedSentences: Set<Int> = []

    /// Flag to suppress auto style analysis until user makes a genuine edit.
    /// Set after user accepts/rejects a suggestion to prevent immediate re-analysis.
    private var suppressedUntilUserEdit: Bool = false

    /// Timestamp of last user-initiated text modification (not from accepting suggestions)
    private var lastUserEditTime: Date?

    /// Count of active style suggestions currently being displayed
    private var activeStyleSuggestionCount: Int = 0

    // MARK: - Public API

    /// Check if a style suggestion should be shown based on all filtering criteria.
    /// - Parameters:
    ///   - originalText: The original text the suggestion applies to
    ///   - confidence: AI confidence score (0.0-1.0)
    ///   - impact: Impact level of the suggestion
    ///   - source: Source engine (harper, appleIntelligence)
    ///   - isManualCheck: Whether this is a user-triggered manual check
    ///   - sensitivity: User's configured sensitivity level
    /// - Returns: Whether the suggestion should be shown
    func shouldShowStyleSuggestion(
        originalText: String,
        confidence: Float,
        impact: SuggestionImpact,
        source: String,
        isManualCheck: Bool,
        sensitivity: StyleSensitivity
    ) -> Bool {
        // 1. Confidence threshold (always applies)
        guard confidence >= confidenceThreshold else {
            Logger.debug("SuggestionTracker: Filtered by confidence (\(confidence) < \(confidenceThreshold))", category: Logger.analysis)
            return false
        }

        // 2. Check if this text was already modified
        let textHash = originalText.hashValue
        if modifiedSpans[textHash] != nil {
            Logger.debug("SuggestionTracker: Filtered - span already modified", category: Logger.analysis)
            return false
        }

        // 3. Check if suggestion was dismissed
        if dismissedSuggestions.contains(textHash) {
            Logger.debug("SuggestionTracker: Filtered - suggestion dismissed", category: Logger.analysis)
            return false
        }

        // 4. Check cooldown for previously shown suggestions
        let suggestionKey = makeSuggestionKey(text: originalText, source: source)
        if let lastShown = shownSuggestions[suggestionKey] {
            let elapsed = Date().timeIntervalSince(lastShown)
            if elapsed < suggestionCooldown {
                Logger.debug("SuggestionTracker: Filtered - cooldown (\(Int(elapsed))s < \(Int(suggestionCooldown))s)", category: Logger.analysis)
                return false
            }
        }

        // For manual checks, show all suggestions that pass the above filters
        if isManualCheck {
            return true
        }

        // 5. Impact-based filtering (auto-check only)
        if impact < sensitivity.minimumImpact {
            Logger.debug("SuggestionTracker: Filtered - impact too low (\(impact) < \(sensitivity.minimumImpact))", category: Logger.analysis)
            return false
        }

        // 6. Frequency cap (auto-check only)
        if activeStyleSuggestionCount >= maxStyleSuggestionsPerDocument {
            Logger.debug("SuggestionTracker: Filtered - frequency cap reached (\(activeStyleSuggestionCount))", category: Logger.analysis)
            return false
        }

        return true
    }

    /// Check if a readability suggestion should be shown.
    /// - Parameters:
    ///   - sentenceText: The sentence text (original or simplified)
    ///   - isSimplified: Whether this is the simplified version being re-checked
    /// - Returns: Whether the readability suggestion should be shown
    func shouldShowReadabilitySuggestion(
        sentenceText: String,
        isSimplified: Bool = false
    ) -> Bool {
        let hash = sentenceText.hashValue

        // Don't re-flag sentences that were already simplified
        if simplifiedSentences.contains(hash) {
            Logger.debug("SuggestionTracker: Readability filtered - already simplified", category: Logger.analysis)
            return false
        }

        // If this is the simplified version being checked, don't flag it
        if isSimplified {
            return false
        }

        // Check if dismissed
        if dismissedSuggestions.contains(hash) {
            Logger.debug("SuggestionTracker: Readability filtered - dismissed", category: Logger.analysis)
            return false
        }

        return true
    }

    /// Check if auto style analysis should run.
    /// - Returns: Whether auto style analysis should proceed
    func shouldRunAutoStyleAnalysis() -> Bool {
        if suppressedUntilUserEdit {
            Logger.debug("SuggestionTracker: Auto analysis suppressed until user edit", category: Logger.analysis)
            return false
        }
        return true
    }

    // MARK: - State Updates

    /// Mark a suggestion as shown.
    /// - Parameters:
    ///   - originalText: The original text of the suggestion
    ///   - source: Source engine identifier
    func markSuggestionShown(originalText: String, source: String) {
        let key = makeSuggestionKey(text: originalText, source: source)
        shownSuggestions[key] = Date()
        activeStyleSuggestionCount += 1

        Logger.debug("SuggestionTracker: Marked suggestion shown (active: \(activeStyleSuggestionCount))", category: Logger.analysis)
    }

    /// Mark a suggestion as accepted (text was replaced).
    /// - Parameters:
    ///   - originalText: The original text that was replaced
    ///   - newText: The new text that replaced it (for readability tracking)
    ///   - isReadability: Whether this was a readability suggestion
    func markSuggestionAccepted(
        originalText: String,
        newText: String,
        isReadability: Bool
    ) {
        let originalHash = originalText.hashValue

        // Track the modified span
        modifiedSpans[originalHash] = Date()

        // Track dismissed so we don't re-suggest
        dismissedSuggestions.insert(originalHash)

        // For readability suggestions, track the new (simplified) text and all its
        // individual sentences so we don't re-flag them as complex.
        // The LLM may return multiple sentences in the simplified text, but
        // NLTokenizer (used by ReadabilityCalculator) will detect them as separate sentences.
        // We must split the text using the SAME method that will later detect them.
        if isReadability {
            // Split into individual sentences using ReadabilityCalculator
            let sentences = ReadabilityCalculator.shared.splitIntoSentences(newText)
            for (sentenceText, _) in sentences {
                let sentenceHash = sentenceText.hashValue
                simplifiedSentences.insert(sentenceHash)
                Logger.debug("SuggestionTracker: Stored readability sentence hash: \(sentenceHash)", category: Logger.analysis)
            }
            // Also store hash of the full text in case it matches as one sentence
            let fullNormalized = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            let fullHash = fullNormalized.hashValue
            simplifiedSentences.insert(fullHash)

            Logger.debug("SuggestionTracker: Marked readability accepted (original: \(originalHash), sentences: \(sentences.count + 1))", category: Logger.analysis)
        } else {
            Logger.debug("SuggestionTracker: Marked suggestion accepted (hash: \(originalHash))", category: Logger.analysis)
        }

        // Suppress auto analysis until user makes a genuine edit
        suppressedUntilUserEdit = true

        // Decrement active count
        activeStyleSuggestionCount = max(0, activeStyleSuggestionCount - 1)
    }

    /// Mark a suggestion as dismissed (rejected without accepting).
    /// - Parameter originalText: The original text of the suggestion
    func markSuggestionDismissed(originalText: String) {
        let hash = originalText.hashValue
        dismissedSuggestions.insert(hash)

        Logger.debug("SuggestionTracker: Marked suggestion dismissed (hash: \(hash))", category: Logger.analysis)

        // Suppress auto analysis until user makes a genuine edit
        suppressedUntilUserEdit = true

        // Decrement active count
        activeStyleSuggestionCount = max(0, activeStyleSuggestionCount - 1)
    }

    /// Notify the tracker that the user made a genuine text edit.
    /// This re-enables auto style analysis.
    /// - Parameter isGenuineEdit: Whether this is a user edit (not from accepting suggestions)
    func notifyTextChanged(isGenuineEdit: Bool) {
        if isGenuineEdit {
            lastUserEditTime = Date()

            // Re-enable auto analysis after user makes changes
            if suppressedUntilUserEdit {
                suppressedUntilUserEdit = false
                Logger.debug("SuggestionTracker: Re-enabled auto analysis after user edit", category: Logger.analysis)
            }
        }
    }

    /// Invalidate tracking for text changes (rebase).
    /// Called when the underlying text has changed significantly.
    func invalidateForTextChange() {
        // Clear shown suggestions (they may no longer apply)
        shownSuggestions.removeAll()

        // Reset active count
        activeStyleSuggestionCount = 0

        Logger.debug("SuggestionTracker: Invalidated for text change", category: Logger.analysis)
    }

    /// Reset all tracking state (e.g., when switching documents).
    func reset() {
        modifiedSpans.removeAll()
        shownSuggestions.removeAll()
        dismissedSuggestions.removeAll()
        simplifiedSentences.removeAll()
        suppressedUntilUserEdit = false
        lastUserEditTime = nil
        activeStyleSuggestionCount = 0

        Logger.debug("SuggestionTracker: Reset all tracking state", category: Logger.analysis)
    }

    /// Reset dismissed suggestions only (keep other state).
    /// Called when switching to a new text field within the same document.
    func resetDismissed() {
        dismissedSuggestions.removeAll()
        suppressedUntilUserEdit = false

        Logger.debug("SuggestionTracker: Reset dismissed suggestions", category: Logger.analysis)
    }

    /// Update active suggestion count (called when suggestions are filtered/removed).
    /// - Parameter count: New active suggestion count
    func updateActiveCount(_ count: Int) {
        activeStyleSuggestionCount = count
    }

    // MARK: - Private Helpers

    private func makeSuggestionKey(text: String, source: String) -> String {
        "\(text.hashValue):\(source)"
    }
}
