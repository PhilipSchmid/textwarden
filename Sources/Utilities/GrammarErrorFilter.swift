//
//  GrammarErrorFilter.swift
//  TextWarden
//
//  Shared filtering logic for grammar errors
//  Used by both AnalysisCoordinator and SketchPadViewModel
//

import Foundation

/// Configuration for grammar error filtering
struct GrammarFilterConfig {
    /// Enabled error categories (e.g., "Spelling", "Grammar", "Style")
    let enabledCategories: Set<String>

    /// Lint IDs of rules that have been ignored/dismissed
    let ignoredRules: Set<String>

    /// Error texts that have been globally ignored
    let ignoredErrorTexts: Set<String>

    /// Whether to use macOS system dictionary for filtering
    let useMacOSDictionary: Bool

    /// Create configuration from UserPreferences
    @MainActor
    static func fromPreferences(_ preferences: UserPreferences) -> GrammarFilterConfig {
        GrammarFilterConfig(
            enabledCategories: preferences.enabledCategories,
            ignoredRules: preferences.ignoredRules,
            ignoredErrorTexts: preferences.ignoredErrorTexts,
            useMacOSDictionary: preferences.enableMacOSDictionary
        )
    }
}

/// Shared grammar error filtering logic
/// This is used by both AnalysisCoordinator and SketchPadViewModel
enum GrammarErrorFilter {
    /// Apply standard filters to grammar errors
    /// Returns filtered errors based on user preferences and vocabularies
    ///
    /// - Parameters:
    ///   - errors: Raw errors from grammar engine
    ///   - sourceText: The text that was analyzed
    ///   - config: Filter configuration
    ///   - customVocabulary: Custom vocabulary provider (defaults to CustomVocabulary.shared)
    /// - Returns: Filtered errors
    @MainActor
    static func filter(
        errors: [GrammarErrorModel],
        sourceText: String,
        config: GrammarFilterConfig,
        customVocabulary: CustomVocabularyProviding
    ) -> [GrammarErrorModel] {
        var filteredErrors = errors

        // 1. HARD-CODED: Always exclude Harper's "Readability" category errors
        // We use our own ReadabilityCalculator instead
        filteredErrors = filteredErrors.filter { $0.category != "Readability" }

        // 2. Filter by enabled categories (e.g., Spelling, Grammar, Style)
        filteredErrors = filteredErrors.filter { error in
            config.enabledCategories.contains(error.category)
        }

        // 3. Deduplicate consecutive identical errors
        // This prevents flooding the UI with repeated errors
        filteredErrors = deduplicateErrors(filteredErrors)

        // 4. Filter by dismissed/ignored rules
        filteredErrors = filteredErrors.filter { error in
            !config.ignoredRules.contains(error.lintId)
        }

        // 5. Filter by custom vocabulary and macOS system dictionary
        // Note: error.start/end are Unicode scalar indices from Harper
        let sourceScalarCount = sourceText.unicodeScalars.count
        filteredErrors = filteredErrors.filter { error in
            guard let errorText = extractErrorText(error: error, sourceText: sourceText, scalarCount: sourceScalarCount) else {
                return true // Keep error if indices are invalid
            }

            // Check custom vocabulary
            if customVocabulary.containsAnyWord(in: errorText) {
                Logger.debug("GrammarErrorFilter: Filtering error for custom vocabulary word: '\(errorText)'", category: Logger.analysis)
                return false
            }

            // Check macOS system dictionary if enabled
            if config.useMacOSDictionary, MacOSDictionary.shared.containsAnyWord(in: errorText) {
                return false
            }

            return true
        }

        // 6. Filter by globally ignored error texts
        filteredErrors = filteredErrors.filter { error in
            guard let errorText = extractErrorText(error: error, sourceText: sourceText, scalarCount: sourceScalarCount) else {
                return true // Keep error if indices are invalid
            }
            return !config.ignoredErrorTexts.contains(errorText)
        }

        // 7. Filter repeated whitespace errors that occur at the start of lines
        // These are intentional for markdown list indentation (e.g., "  - nested item")
        filteredErrors = filteredErrors.filter { error in
            // Check if this is a repeated whitespace error
            let isWhitespaceError = error.lintId.lowercased().contains("whitespace") ||
                error.lintId.lowercased().contains("repeated") ||
                error.message.lowercased().contains("2 spaces") ||
                error.message.lowercased().contains("spaces where there should be")

            guard isWhitespaceError else { return true }

            // Check if this error occurs at the start of a line (markdown indentation)
            return !isAtStartOfLine(position: error.start, in: sourceText)
        }

        return filteredErrors
    }

    /// Check if a position is at the start of a line (after a newline or at position 0)
    private static func isAtStartOfLine(position: Int, in text: String) -> Bool {
        // Position 0 is always start of line
        if position == 0 { return true }

        // Get the character before the position
        guard let stringIndex = TextIndexConverter.scalarIndexToStringIndex(position, in: text) else {
            return false
        }

        // Check if we're at the start of the string
        if stringIndex == text.startIndex { return true }

        // Get the previous character
        let previousIndex = text.index(before: stringIndex)
        let previousChar = text[previousIndex]

        // Check if the previous character is a newline
        return previousChar == "\n" || previousChar == "\r"
    }

    // MARK: - Private Helpers

    /// Extract error text from source using scalar indices
    private static func extractErrorText(error: GrammarErrorModel, sourceText: String, scalarCount: Int) -> String? {
        guard error.start < scalarCount, error.end <= scalarCount, error.start < error.end,
              let startIndex = TextIndexConverter.scalarIndexToStringIndex(error.start, in: sourceText),
              let endIndex = TextIndexConverter.scalarIndexToStringIndex(error.end, in: sourceText)
        else {
            return nil
        }
        return String(sourceText[startIndex ..< endIndex])
    }

    /// Deduplicate consecutive identical errors at the same position
    /// This prevents issues like 157 "Horizontal ellipsis" errors flooding the UI
    private static func deduplicateErrors(_ errors: [GrammarErrorModel]) -> [GrammarErrorModel] {
        guard !errors.isEmpty else { return errors }

        var deduplicated: [GrammarErrorModel] = []
        var currentGroup: [GrammarErrorModel] = [errors[0]]

        for i in 1 ..< errors.count {
            let current = errors[i]
            let previous = errors[i - 1]

            // Check if this error is identical to the previous one AND at the same position
            // Errors at different positions should NOT be deduplicated (e.g., same typo twice)
            if current.message == previous.message,
               current.category == previous.category,
               current.lintId == previous.lintId,
               current.start == previous.start,
               current.end == previous.end
            {
                // Same error at same position - add to current group
                currentGroup.append(current)
            } else {
                // Different error or same error at different position - save one representative
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
}
