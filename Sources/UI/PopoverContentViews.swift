//
//  PopoverContentViews.swift
//  TextWarden
//
//  SwiftUI content views for the suggestion popover.
//  Includes grammar error context, unified content, and popover layout views.
//

import SwiftUI

// MARK: - Readability Tips Helper

/// Static helper to generate improvement tips based on readability score
/// Used by StylePopoverContentView for readability suggestions
enum ReadabilityTipsHelper {
    /// Get improvement tips based on readability score
    /// Matches the logic in ReadabilityResult.improvementTips
    static func tips(forScore score: Int) -> [String] {
        switch score {
        case 70...:
            [] // Good readability, no tips needed
        case 60 ..< 70:
            [
                "Consider breaking longer sentences into shorter ones",
                "Replace some complex words with simpler alternatives",
            ]
        case 50 ..< 60:
            [
                "Use shorter sentences (aim for 15-20 words)",
                "Replace multi-syllable words where possible",
                "Break up long paragraphs",
            ]
        case 30 ..< 50:
            [
                "Significantly shorten your sentences",
                "Use simpler, everyday vocabulary",
                "Consider your audience's reading level",
                "Remove unnecessary jargon",
            ]
        default:
            [
                "Rewrite using much simpler language",
                "Keep sentences under 15 words",
                "Use common, one or two-syllable words",
                "Consider breaking into multiple shorter pieces",
            ]
        }
    }
}

// MARK: - Readability Tips Hover View

/// Shows "Readability Tips" row that displays a tooltip popup on hover
/// This avoids expanding/collapsing the main popover which causes layout jumps
struct ExpandableReadabilityTipsView: View {
    let score: Int
    let targetAudience: String?
    let colors: AppColors
    let fontSize: CGFloat

    @State private var isHovering = false

    private var tips: [String] {
        ReadabilityTipsHelper.tips(forScore: score)
    }

    var body: some View {
        // Only show if there are tips to display
        if !tips.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11))
                    .foregroundColor(isHovering ? colors.textPrimary : colors.textSecondary)

                Text("Readability Tips")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(isHovering ? colors.textPrimary : colors.textSecondary)

                Spacer()
            }
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .popover(isPresented: $isHovering, arrowEdge: .trailing) {
                ReadabilityTipsPopoverContent(
                    score: score,
                    targetAudience: targetAudience,
                    tips: tips,
                    colors: colors,
                    fontSize: fontSize
                )
            }
        }
    }
}

/// Content for the readability tips popover (shown on hover)
/// Styled to match the main suggestion popover with gradient background
private struct ReadabilityTipsPopoverContent: View {
    let score: Int
    let targetAudience: String?
    let tips: [String]
    let colors: AppColors
    let fontSize: CGFloat

    @ObservedObject private var preferences = UserPreferences.shared
    @Environment(\.colorScheme) private var systemColorScheme

    /// Effective color scheme based on user preference
    private var effectiveColorScheme: ColorScheme {
        switch preferences.overlayTheme {
        case "Light":
            .light
        case "Dark":
            .dark
        default:
            systemColorScheme
        }
    }

    /// Colors for the effective color scheme
    private var themedColors: AppColors {
        AppColors(for: effectiveColorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)

                Text("Readability Tips")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(themedColors.textPrimary)
            }

            Divider()
                .background(themedColors.border.opacity(0.3))

            // Target audience info (if available)
            if let audience = targetAudience {
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.system(size: 11))
                        .foregroundColor(themedColors.textSecondary)
                    Text("Target audience: \(audience)")
                        .font(.system(size: fontSize * 0.9))
                        .foregroundColor(themedColors.textSecondary)
                }
                .padding(.bottom, 2)
            }

            // Score indicator
            HStack(spacing: 6) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 11))
                    .foregroundColor(themedColors.textSecondary)
                Text("Current score: \(score)")
                    .font(.system(size: fontSize * 0.9))
                    .foregroundColor(themedColors.textSecondary)
            }
            .padding(.bottom, 4)

            // Improvement tips
            Text("How to improve:")
                .font(.system(size: fontSize * 0.9, weight: .medium))
                .foregroundColor(themedColors.textPrimary)

            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundColor(themedColors.textSecondary)
                    Text(tip)
                        .font(.system(size: fontSize * 0.9))
                        .foregroundColor(themedColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        // Match the main popover styling: gradient background with subtle border
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [themedColors.backgroundGradientTop, themedColors.backgroundGradientBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                themedColors.border.opacity(0.5),
                                themedColors.border.opacity(0.2),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .colorScheme(effectiveColorScheme)
    }
}

// MARK: - Hover Tooltip

/// Custom tooltip modifier for buttons in non-activating panels where .help() doesn't work
struct HoverTooltipModifier: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()

                if hovering {
                    // Show tooltip after delay
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s delay
                        if !Task.isCancelled {
                            await MainActor.run {
                                showTooltip = true
                            }
                        }
                    }
                } else {
                    showTooltip = false
                }
            }
            .overlay(alignment: .top) {
                if showTooltip {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.85))
                        )
                        .offset(y: -28)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(1000)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showTooltip)
    }
}

extension View {
    func hoverTooltip(_ text: String) -> some View {
        modifier(HoverTooltipModifier(text: text))
    }
}

// MARK: - Sentence Context View

/// Helper to extract sentence containing error and highlight the error word(s)
struct SentenceContextView: View {
    let sourceText: String
    let error: GrammarErrorModel
    let allErrors: [GrammarErrorModel]
    let colors: AppColors
    let textSize: CGFloat

    /// Maximum word count for sentences (Harper's long sentence threshold is 40)
    private let maxSentenceWords = 40

    /// Check if an error is the current one being displayed
    private func isCurrentError(_ err: GrammarErrorModel) -> Bool {
        err.start == error.start && err.end == error.end && err.lintId == error.lintId
    }

    /// Convert a Unicode scalar index to a String.Index
    /// Harper uses Rust's char indices (Unicode scalar values), but Swift uses grapheme cluster indices.
    /// Emojis like ❗️ are 2 scalars (U+2757 + U+FE0F) but 1 grapheme cluster.
    private func scalarIndexToStringIndex(_ scalarIndex: Int, in string: String) -> String.Index? {
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

    /// Get the number of Unicode scalars up to a String.Index
    private func stringIndexToScalarIndex(_ stringIndex: String.Index, in string: String) -> Int {
        let scalars = string.unicodeScalars
        let scalarStart = string.startIndex.samePosition(in: scalars) ?? scalars.startIndex
        let scalarEnd = stringIndex.samePosition(in: scalars) ?? scalars.endIndex
        return scalars.distance(from: scalarStart, to: scalarEnd)
    }

    /// Extract expected error text from error message (backticks) or suggestions
    private func extractExpectedText(from error: GrammarErrorModel) -> String? {
        // Try to extract from backticks in message (e.g., "Did you mean to spell `staand` this way?")
        let message = error.message
        if let backtickStart = message.firstIndex(of: "`"),
           let backtickEnd = message[message.index(after: backtickStart)...].firstIndex(of: "`")
        {
            let word = String(message[message.index(after: backtickStart) ..< backtickEnd])
            if !word.isEmpty { return word }
        }

        // For errors with length > 0, try to extract from sourceText at the expected position
        // This is a fallback when we can't determine expected text from message
        return nil
    }

    /// Correct error position if it has drifted due to prior text replacements
    /// Returns the corrected (start, end) scalar positions, or original if no drift detected or correction not possible
    private func correctErrorPosition(_ err: GrammarErrorModel, in text: String) -> (start: Int, end: Int) {
        let scalarCount = text.unicodeScalars.count
        guard err.start >= 0, err.end <= scalarCount, err.start < err.end else {
            return (err.start, err.end)
        }

        // Extract text at current position
        let startIdx = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: err.start)
        let endIdx = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: err.end)
        let extractedText = String(text.unicodeScalars[startIdx ..< endIdx])

        // Get expected text
        guard let expectedText = extractExpectedText(from: err) else {
            return (err.start, err.end)
        }

        // If extracted matches expected, no drift
        if extractedText == expectedText {
            return (err.start, err.end)
        }

        // Search nearby positions for expected text
        let searchRadius = 5
        let errorLength = err.end - err.start

        for offset in -searchRadius ... searchRadius where offset != 0 {
            let testStart = err.start + offset
            let testEnd = testStart + errorLength
            guard testStart >= 0, testEnd <= scalarCount else { continue }

            let testStartIdx = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: testStart)
            let testEndIdx = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: testEnd)
            let testText = String(text.unicodeScalars[testStartIdx ..< testEndIdx])

            if testText == expectedText {
                return (testStart, testEnd)
            }
        }

        // Could not correct - return original
        return (err.start, err.end)
    }

    var body: some View {
        if let sentenceInfo = extractSentenceWithErrors() {
            // Sentence context - no background box, just the text with highlights
            buildHighlightedText(sentenceInfo: sentenceInfo)
                .font(.system(size: textSize))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Sentence info containing the sentence text and error ranges within it
    private struct SentenceInfo {
        let sentence: String
        let sentenceStartScalar: Int // Offset in source text (Unicode scalar index)
        let errorRanges: [(range: Range<String.Index>, category: String, isCurrent: Bool)]
        let isTruncated: Bool
    }

    /// Extract the sentence containing the current error
    private func extractSentenceWithErrors() -> SentenceInfo? {
        // Harper uses Unicode scalar indices, so check against scalar count
        let scalarCount = sourceText.unicodeScalars.count
        guard error.start < scalarCount, error.end <= scalarCount else {
            return nil
        }

        // Convert error.start (scalar index) to String.Index
        guard let errorStartIndex = scalarIndexToStringIndex(error.start, in: sourceText) else {
            return nil
        }

        // Find sentence start by searching backwards for:
        // 1. Sentence terminators: . ! ? followed by space/newline
        // 2. Colon followed by newline (list headers like "Title:")
        // 3. Double newline (paragraph break)
        var sentenceStart = sourceText.startIndex
        var searchIndex = errorStartIndex
        while searchIndex > sourceText.startIndex {
            let prevIndex = sourceText.index(before: searchIndex)
            let char = sourceText[prevIndex]

            // Standard sentence terminators
            if char == "." || char == "!" || char == "?" {
                // Check if this is end of previous sentence (followed by space/newline or at error position)
                if searchIndex == errorStartIndex || sourceText[searchIndex].isWhitespace || sourceText[searchIndex].isNewline {
                    sentenceStart = searchIndex
                    break
                }
            }

            // Colon followed by newline acts as sentence boundary (list headers)
            if char == ":", searchIndex < sourceText.endIndex, sourceText[searchIndex].isNewline {
                sentenceStart = searchIndex
                break
            }

            // Newline acts as sentence boundary when:
            // 1. It's part of a paragraph break (multiple consecutive newlines)
            // 2. It's a line break in a list (followed by list marker)
            if char.isNewline {
                // Check for multiple consecutive newlines (paragraph break)
                // This is especially important for Notion's block-based structure
                if searchIndex < sourceText.endIndex, sourceText[searchIndex].isNewline {
                    // Double newline found - treat as paragraph boundary
                    sentenceStart = searchIndex
                    break
                }

                // Check if this newline starts a new logical sentence (e.g., list item)
                var checkIndex = searchIndex
                // Skip whitespace after newline
                while checkIndex < sourceText.endIndex, sourceText[checkIndex].isWhitespace, !sourceText[checkIndex].isNewline {
                    checkIndex = sourceText.index(after: checkIndex)
                }
                // If followed by list marker or error is on this line, treat newline as boundary
                if checkIndex < sourceText.endIndex {
                    let nextChar = sourceText[checkIndex]
                    let listBullets: Set<Character> = ["•", "◦", "‣", "⁃", "▪", "▸", "►", "○", "■", "□", "●", "-", "*"]
                    if listBullets.contains(nextChar) || nextChar.isNumber {
                        sentenceStart = searchIndex
                        break
                    }
                }
            }

            searchIndex = prevIndex
        }

        // Skip leading whitespace and newlines
        while sentenceStart < sourceText.endIndex,
              sourceText[sentenceStart].isWhitespace || sourceText[sentenceStart].isNewline
        {
            sentenceStart = sourceText.index(after: sentenceStart)
        }

        // Skip list markers (bullets, numbers, etc.) at the start of sentences
        // Common markers: • ◦ ‣ ⁃ ▪ ▸ ► - * followed by whitespace
        // Also numbered lists: 1. 2. a) b) etc.
        if sentenceStart < sourceText.endIndex {
            let char = sourceText[sentenceStart]
            let listBullets: Set<Character> = ["•", "◦", "‣", "⁃", "▪", "▸", "►", "○", "■", "□", "●"]

            if listBullets.contains(char) {
                // Skip bullet and following whitespace
                sentenceStart = sourceText.index(after: sentenceStart)
                while sentenceStart < sourceText.endIndex,
                      sourceText[sentenceStart].isWhitespace
                {
                    sentenceStart = sourceText.index(after: sentenceStart)
                }
            } else if char == "-" || char == "*" {
                // Check if followed by whitespace (list marker) vs part of a word
                let nextIndex = sourceText.index(after: sentenceStart)
                if nextIndex < sourceText.endIndex, sourceText[nextIndex].isWhitespace {
                    sentenceStart = nextIndex
                    while sentenceStart < sourceText.endIndex,
                          sourceText[sentenceStart].isWhitespace
                    {
                        sentenceStart = sourceText.index(after: sentenceStart)
                    }
                }
            } else if char.isNumber {
                // Check for numbered list like "1. " or "1) "
                var checkIndex = sentenceStart
                while checkIndex < sourceText.endIndex, sourceText[checkIndex].isNumber {
                    checkIndex = sourceText.index(after: checkIndex)
                }
                if checkIndex < sourceText.endIndex {
                    let afterNumber = sourceText[checkIndex]
                    if afterNumber == "." || afterNumber == ")" {
                        let afterPunc = sourceText.index(after: checkIndex)
                        if afterPunc < sourceText.endIndex, sourceText[afterPunc].isWhitespace {
                            // This is a numbered list marker, skip it
                            sentenceStart = afterPunc
                            while sentenceStart < sourceText.endIndex,
                                  sourceText[sentenceStart].isWhitespace
                            {
                                sentenceStart = sourceText.index(after: sentenceStart)
                            }
                        }
                    }
                }
            }
        }

        // Find sentence end by searching forwards for . ! ? or newline (for list items)
        var sentenceEnd = sourceText.endIndex
        searchIndex = errorStartIndex
        while searchIndex < sourceText.endIndex {
            let char = sourceText[searchIndex]
            if char == "." || char == "!" || char == "?" {
                // Include the punctuation in the sentence
                sentenceEnd = sourceText.index(after: searchIndex)
                break
            }
            // Newline ends sentence for list items
            if char.isNewline {
                sentenceEnd = searchIndex
                break
            }
            searchIndex = sourceText.index(after: searchIndex)
        }

        // sentenceStartOffset is in scalar indices (for arithmetic with error.start/end)
        let sentenceStartScalarOffset = stringIndexToScalarIndex(sentenceStart, in: sourceText)
        var sentence = String(sourceText[sentenceStart ..< sentenceEnd])

        // Check if sentence is too long and needs truncation
        let wordCount = sentence.split(separator: " ").count
        var isTruncated = false

        if wordCount > maxSentenceWords {
            // Truncate around the error position (convert scalar offset to grapheme offset for truncation)
            let errorScalarOffsetInSentence = error.start - sentenceStartScalarOffset
            // Convert scalar offset to approximate grapheme offset for truncation (OK to be approximate)
            let approxGraphemeOffset = min(errorScalarOffsetInSentence, sentence.count)
            sentence = truncateSentence(sentence, errorOffset: approxGraphemeOffset)
            isTruncated = true
        }

        // Find all errors in this sentence using scalar indices
        let sentenceEndScalarOffset = stringIndexToScalarIndex(sentenceEnd, in: sourceText)
        let errorsInSentence = allErrors.filter { err in
            err.start >= sentenceStartScalarOffset && err.end <= sentenceEndScalarOffset
        }

        // Build error ranges relative to the sentence
        // Apply position drift correction to handle cases where error positions have drifted
        // due to prior text replacements not being properly reflected in currentErrors
        var errorRanges: [(range: Range<String.Index>, category: String, isCurrent: Bool)] = []
        for err in errorsInSentence {
            // Correct for position drift if needed
            let corrected = correctErrorPosition(err, in: sourceText)

            // Calculate relative scalar indices within the sentence
            let relativeStartScalar = corrected.start - sentenceStartScalarOffset
            let relativeEndScalar = corrected.end - sentenceStartScalarOffset

            guard relativeStartScalar >= 0, relativeEndScalar <= sentence.unicodeScalars.count else {
                continue
            }

            // Convert scalar indices to String.Index using the helper
            if let startIdx = scalarIndexToStringIndex(relativeStartScalar, in: sentence),
               let endIdx = scalarIndexToStringIndex(relativeEndScalar, in: sentence),
               startIdx < endIdx
            {
                errorRanges.append((range: startIdx ..< endIdx, category: err.category, isCurrent: isCurrentError(err)))
            }
        }

        return SentenceInfo(
            sentence: sentence,
            sentenceStartScalar: sentenceStartScalarOffset,
            errorRanges: errorRanges,
            isTruncated: isTruncated
        )
    }

    /// Truncate a long sentence around the error position
    private func truncateSentence(_ sentence: String, errorOffset: Int) -> String {
        let words = sentence.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count > maxSentenceWords else { return sentence }

        // Find which word contains the error
        var charCount = 0
        var errorWordIndex = 0
        for (index, word) in words.enumerated() {
            let wordEnd = charCount + word.count + 1 // +1 for space
            if charCount <= errorOffset, errorOffset < wordEnd {
                errorWordIndex = index
                break
            }
            charCount = wordEnd
        }

        // Show words around the error (about 15 words on each side)
        let contextWords = 15
        let startWord = max(0, errorWordIndex - contextWords)
        let endWord = min(words.count, errorWordIndex + contextWords + 1)

        var result = ""
        if startWord > 0 {
            result += "..."
        }
        result += words[startWord ..< endWord].joined(separator: " ")
        if endWord < words.count {
            result += "..."
        }

        return result
    }

    /// Build the highlighted text view
    @ViewBuilder
    private func buildHighlightedText(sentenceInfo: SentenceInfo) -> some View {
        let sentence = sentenceInfo.sentence

        if sentenceInfo.errorRanges.isEmpty {
            Text(sentence)
                .foregroundColor(colors.textPrimary)
        } else {
            // Build Text with highlights using + concatenation
            buildAttributedTextView(sentence: sentence, errorRanges: sentenceInfo.errorRanges)
        }
    }

    /// Build attributed text with highlighted error words
    /// Current error gets underline + color, other errors get color only (no underline)
    private func buildAttributedTextView(sentence: String, errorRanges: [(range: Range<String.Index>, category: String, isCurrent: Bool)]) -> Text {
        // Sort ranges by start position
        let sortedRanges = errorRanges.sorted { $0.range.lowerBound < $1.range.lowerBound }

        var result = Text("")
        var currentIndex = sentence.startIndex

        for errorRange in sortedRanges {
            // Add text before this error (primary color for good contrast)
            if currentIndex < errorRange.range.lowerBound {
                let beforeText = String(sentence[currentIndex ..< errorRange.range.lowerBound])
                // swiftlint:disable:next shorthand_operator
                result = result + Text(beforeText).foregroundColor(colors.textPrimary)
            }

            // Add highlighted error text
            // Current error: underline + bold + color
            // Other errors: color only (slightly muted) - no underline
            let errorText = String(sentence[errorRange.range])
            let categoryColor = colors.categoryColor(for: errorRange.category)

            if errorRange.isCurrent {
                // Current error - full highlight with underline
                // swiftlint:disable:next shorthand_operator
                result = result + Text(errorText)
                    .foregroundColor(categoryColor)
                    .fontWeight(.semibold)
                    .underline(true, color: categoryColor)
            } else {
                // Other errors in same sentence - color only, no underline
                // swiftlint:disable:next shorthand_operator
                result = result + Text(errorText)
                    .foregroundColor(categoryColor.opacity(0.8))
                    .fontWeight(.medium)
            }

            currentIndex = errorRange.range.upperBound
        }

        // Add remaining text after last error (primary color for good contrast)
        if currentIndex < sentence.endIndex {
            let afterText = String(sentence[currentIndex...])
            // swiftlint:disable:next shorthand_operator
            result = result + Text(afterText).foregroundColor(colors.textPrimary)
        }

        return result
    }
}

struct UnifiedPopoverContentView: View {
    @ObservedObject var popover: SuggestionPopover

    var body: some View {
        // Use rebuildCounter as view identity to force complete re-layout
        // Without this, SwiftUI may cache the LiquidGlass background size
        Group {
            switch popover.mode {
            case .grammarError:
                PopoverContentView(popover: popover)
            case .styleSuggestion:
                StylePopoverContentView(popover: popover)
            }
        }
        .id(popover.rebuildCounter)
    }
}

/// SwiftUI content view for error popover - Compact design with vertical suggestions
struct PopoverContentView: View {
    @ObservedObject var popover: SuggestionPopover
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.colorScheme) var systemColorScheme
    @State private var hoveredSuggestion: String?

    /// Effective color scheme based on user preference (overlay theme for popovers)
    private var effectiveColorScheme: ColorScheme {
        switch preferences.overlayTheme {
        case "Light":
            .light
        case "Dark":
            .dark
        default: // "System"
            systemColorScheme
        }
    }

    /// App color scheme
    private var colors: AppColors {
        AppColors(for: effectiveColorScheme)
    }

    /// Base text size from preferences
    private var baseTextSize: CGFloat {
        CGFloat(preferences.suggestionTextSize)
    }

    /// Caption text size (85% of base)
    private var captionTextSize: CGFloat {
        baseTextSize * 0.85
    }

    /// Body text size (100% of base)
    private var bodyTextSize: CGFloat {
        baseTextSize
    }

    /// Check if current error is an AI rephrase suggestion (needs wider popover)
    private var isAIRephraseError: Bool {
        guard let error = popover.currentError else { return false }
        let validSuggestions = error.suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return error.category == "Readability" && validSuggestions.count == 2
    }

    /// Format category for display (e.g., "Spelling" -> "Spelling mistake")
    private func formatCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "spelling":
            "Spelling mistake"
        case "capitalization":
            "Capitalization"
        case "grammar":
            "Grammar"
        case "punctuation":
            "Punctuation"
        case "readability":
            "Readability"
        case "style":
            "Style suggestion"
        default:
            category
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = popover.currentError {
                let validSuggestions = error.suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let isAIRephrase = error.category == "Readability" && validSuggestions.count == 2
                // Note: AI enhancement for readability errors is disabled, so we don't show loading state
                // Readability errors without suggestions just display the error message like any other error

                // Header row with category and close button
                HStack(alignment: .center, spacing: 8) {
                    // Category indicator dot with subtle glow
                    Circle()
                        .fill(colors.categoryColor(for: error.category))
                        .frame(width: 8, height: 8)
                        .shadow(color: colors.categoryColor(for: error.category).opacity(0.4), radius: 3, x: 0, y: 0)

                    // Category label
                    Text(formatCategory(error.category))
                        .font(.system(size: captionTextSize, weight: .semibold))
                        .foregroundColor(colors.textPrimary.opacity(0.85))
                        .lineLimit(1)

                    Spacer()

                    // Close button with hover effect
                    Button(action: { popover.hide() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(colors.textTertiary)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(colors.backgroundRaised.opacity(0.01))
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: .option)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Status message (shown when action fails)
                if let statusMessage = popover.statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(statusMessage)
                            .font(.system(size: captionTextSize))
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }

                // Sentence context (shown when opened from indicator for better context)
                if popover.openedFromIndicator, !popover.sourceText.isEmpty {
                    SentenceContextView(
                        sourceText: popover.sourceText,
                        error: error,
                        allErrors: popover.allErrors,
                        colors: colors,
                        textSize: bodyTextSize
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }

                // Content area
                VStack(alignment: .leading, spacing: 2) {
                    if isAIRephrase {
                        // AI rephrase - show before/after
                        let originalText = validSuggestions[0]
                        let rephraseText = validSuggestions[1]

                        VStack(alignment: .leading, spacing: 6) {
                            Text(originalText)
                                .font(.system(size: bodyTextSize - 1))
                                .foregroundColor(.red.opacity(0.8))
                                .strikethrough(true, color: .red.opacity(0.6))
                                .lineLimit(2)

                            Button(action: { popover.applySuggestion(rephraseText) }) {
                                Text(rephraseText)
                                    .font(.system(size: bodyTextSize, weight: .medium))
                                    .foregroundColor(colors.primary)
                                    .lineLimit(3)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut("1", modifiers: .command)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)

                    } else if !validSuggestions.isEmpty {
                        // Vertical list of clickable suggestions with Tahoe-style hover
                        // Non-hovered state uses link color + underline to hint at interactivity
                        ForEach(Array(validSuggestions.prefix(5).enumerated()), id: \.offset) { index, suggestion in
                            Button(action: { popover.applySuggestion(suggestion) }) {
                                Text(suggestion)
                                    .font(.system(size: bodyTextSize, weight: .medium))
                                    .foregroundColor(
                                        hoveredSuggestion == suggestion
                                            ? colors.link // Bright link color on hover
                                            : colors.link // High-contrast link color
                                    )
                                    .underline(
                                        hoveredSuggestion != suggestion, // Show underline when NOT hovered
                                        pattern: .dot, // Dotted underline for subtle hint
                                        color: colors.linkSubtle
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(hoveredSuggestion == suggestion ? colors.link.opacity(0.15) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(popover.isProcessing)
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                            .help("Apply suggestion (⌘\(index + 1))")
                            .onHover { isHovered in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    hoveredSuggestion = isHovered ? suggestion : nil
                                }
                            }
                        }

                    } else {
                        // No suggestions - show the error message
                        Text(error.message)
                            .font(.system(size: bodyTextSize - 1))
                            .foregroundColor(colors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                }

                // Action bar with icon buttons and navigation (subtle background)
                HStack(spacing: 6) {
                    // Ignore button
                    Button(action: { popover.dismissError() }) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12))
                            .foregroundColor(colors.textSecondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .hoverTooltip("Ignore")

                    // Ignore Rule button
                    Button(action: { popover.ignoreRule() }) {
                        Image(systemName: "nosign")
                            .font(.system(size: 12))
                            .foregroundColor(colors.textSecondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .hoverTooltip("Ignore rule")

                    // Add to Dictionary (for spelling only)
                    if error.category == "Spelling" {
                        Button(action: { popover.addToDictionary() }) {
                            Image(systemName: "text.badge.plus")
                                .font(.system(size: 12))
                                .foregroundColor(colors.textSecondary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .hoverTooltip("Add to dictionary")
                    }

                    Spacer()

                    // Navigation controls - only shown when popover opened from indicator
                    if popover.openedFromIndicator, popover.totalItemCount > 1 {
                        Text("\(popover.unifiedIndex + 1) of \(popover.totalItemCount)")
                            .font(.system(size: captionTextSize - 1, weight: .medium))
                            .foregroundColor(colors.textSecondary.opacity(0.7))

                        HStack(spacing: 2) {
                            Button(action: {
                                Logger.trace("Grammar popover: Previous button clicked", category: Logger.ui)
                                popover.previousUnifiedItem()
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(colors.textSecondary)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.upArrow, modifiers: [])
                            .hoverTooltip("Previous")

                            Button(action: {
                                Logger.trace("Grammar popover: Next button clicked", category: Logger.ui)
                                popover.nextUnifiedItem()
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(colors.textSecondary)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.downArrow, modifiers: [])
                            .hoverTooltip("Next")
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 10,
                        topTrailingRadius: 0
                    )
                    .fill(colors.backgroundElevated.opacity(0.5))
                )

            } else {
                Text("No errors to display")
                    .foregroundColor(colors.textSecondary)
                    .padding()
                    .accessibilityLabel("No grammar errors to display")
            }
        }
        // Tahoe-style background: subtle gradient with refined border
        .background(
            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [colors.backgroundGradientTop, colors.backgroundGradientBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Subtle inner border for definition
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                colors.border.opacity(0.5),
                                colors.border.opacity(0.2),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        // Width: 400 for indicator with sentence context (match style popover), 300 for AI rephrase, 220 for inline
        .frame(width: popover.openedFromIndicator && !popover.sourceText.isEmpty ? 400 : (isAIRephraseError ? 300 : 220))
        .fixedSize(horizontal: false, vertical: true)
        .colorScheme(effectiveColorScheme)
        .accessibilityElement(children: .contain)
    }

    /// Severity indicator with color
    @ViewBuilder
    private func severityIndicator(for severity: GrammarErrorSeverity) -> some View {
        let (color, icon) = severityStyle(for: severity)

        Image(systemName: icon)
            .foregroundColor(color)
            .font(.title3)
    }

    /// Get severity color and icon
    private func severityStyle(for severity: GrammarErrorSeverity) -> (Color, String) {
        switch severity {
        case .error:
            (.red, "exclamationmark.circle.fill")
        case .warning:
            (.orange, "exclamationmark.triangle.fill")
        case .info:
            (.blue, "info.circle.fill")
        }
    }

    /// Get severity color only
    private func severityColor(for severity: GrammarErrorSeverity) -> Color {
        switch severity {
        case .error:
            .red
        case .warning:
            .orange
        case .info:
            .blue
        }
    }

    /// Get severity color for high contrast mode
    @ViewBuilder
    private func severityColorForContrast(for severity: GrammarErrorSeverity) -> some View {
        let baseColor = severityColor(for: severity)

        // In high contrast mode, increase color intensity
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            baseColor.brightness(-0.2)
        } else {
            baseColor
        }
    }

    /// Accessibility label for severity
    private func severityAccessibilityLabel(for severity: GrammarErrorSeverity) -> String {
        switch severity {
        case .error:
            "Error: Critical grammar issue"
        case .warning:
            "Warning: Grammar suggestion"
        case .info:
            "Info: Style recommendation"
        }
    }
}
