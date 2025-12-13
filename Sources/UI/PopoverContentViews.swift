//
//  PopoverContentViews.swift
//  TextWarden
//
//  SwiftUI content views for the suggestion popover.
//  Includes grammar error context, unified content, and popover layout views.
//

import SwiftUI

// MARK: - Unified Content View

/// Unified content view that switches between grammar and style suggestion content
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
        return err.start == error.start && err.end == error.end && err.lintId == error.lintId
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
        let sentenceStartScalar: Int  // Offset in source text (Unicode scalar index)
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
            if char == ":" && searchIndex < sourceText.endIndex && sourceText[searchIndex].isNewline {
                sentenceStart = searchIndex
                break
            }

            // Newline acts as sentence boundary when it's a line break in a list
            // (detected by checking if current line starts with a list marker)
            if char.isNewline {
                // Check if this newline starts a new logical sentence (e.g., list item)
                var checkIndex = searchIndex
                // Skip whitespace after newline
                while checkIndex < sourceText.endIndex && sourceText[checkIndex].isWhitespace && !sourceText[checkIndex].isNewline {
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
        while sentenceStart < sourceText.endIndex &&
              (sourceText[sentenceStart].isWhitespace || sourceText[sentenceStart].isNewline) {
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
                while sentenceStart < sourceText.endIndex &&
                      sourceText[sentenceStart].isWhitespace {
                    sentenceStart = sourceText.index(after: sentenceStart)
                }
            } else if char == "-" || char == "*" {
                // Check if followed by whitespace (list marker) vs part of a word
                let nextIndex = sourceText.index(after: sentenceStart)
                if nextIndex < sourceText.endIndex && sourceText[nextIndex].isWhitespace {
                    sentenceStart = nextIndex
                    while sentenceStart < sourceText.endIndex &&
                          sourceText[sentenceStart].isWhitespace {
                        sentenceStart = sourceText.index(after: sentenceStart)
                    }
                }
            } else if char.isNumber {
                // Check for numbered list like "1. " or "1) "
                var checkIndex = sentenceStart
                while checkIndex < sourceText.endIndex && sourceText[checkIndex].isNumber {
                    checkIndex = sourceText.index(after: checkIndex)
                }
                if checkIndex < sourceText.endIndex {
                    let afterNumber = sourceText[checkIndex]
                    if afterNumber == "." || afterNumber == ")" {
                        let afterPunc = sourceText.index(after: checkIndex)
                        if afterPunc < sourceText.endIndex && sourceText[afterPunc].isWhitespace {
                            // This is a numbered list marker, skip it
                            sentenceStart = afterPunc
                            while sentenceStart < sourceText.endIndex &&
                                  sourceText[sentenceStart].isWhitespace {
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
        var sentence = String(sourceText[sentenceStart..<sentenceEnd])

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
        var errorRanges: [(range: Range<String.Index>, category: String, isCurrent: Bool)] = []
        for err in errorsInSentence {
            // Calculate relative scalar indices within the sentence
            let relativeStartScalar = err.start - sentenceStartScalarOffset
            let relativeEndScalar = err.end - sentenceStartScalarOffset

            guard relativeStartScalar >= 0, relativeEndScalar <= sentence.unicodeScalars.count else { continue }

            // Convert scalar indices to String.Index using the helper
            if let startIdx = scalarIndexToStringIndex(relativeStartScalar, in: sentence),
               let endIdx = scalarIndexToStringIndex(relativeEndScalar, in: sentence),
               startIdx < endIdx {
                errorRanges.append((range: startIdx..<endIdx, category: err.category, isCurrent: isCurrentError(err)))
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
            let wordEnd = charCount + word.count + 1  // +1 for space
            if charCount <= errorOffset && errorOffset < wordEnd {
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
        result += words[startWord..<endWord].joined(separator: " ")
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
                let beforeText = String(sentence[currentIndex..<errorRange.range.lowerBound])
                result = result + Text(beforeText).foregroundColor(colors.textPrimary)
            }

            // Add highlighted error text
            // Current error: underline + bold + color
            // Other errors: color only (slightly muted) - no underline
            let errorText = String(sentence[errorRange.range])
            let categoryColor = colors.categoryColor(for: errorRange.category)

            if errorRange.isCurrent {
                // Current error - full highlight with underline
                result = result + Text(errorText)
                    .foregroundColor(categoryColor)
                    .fontWeight(.semibold)
                    .underline(true, color: categoryColor)
            } else {
                // Other errors in same sentence - color only, no underline
                result = result + Text(errorText)
                    .foregroundColor(categoryColor.opacity(0.8))
                    .fontWeight(.medium)
            }

            currentIndex = errorRange.range.upperBound
        }

        // Add remaining text after last error (primary color for good contrast)
        if currentIndex < sentence.endIndex {
            let afterText = String(sentence[currentIndex...])
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

/// SwiftUI content view for popover
struct PopoverContentView: View {
    @ObservedObject var popover: SuggestionPopover
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.colorScheme) var systemColorScheme

    /// Effective color scheme based on user preference (overlay theme for popovers)
    private var effectiveColorScheme: ColorScheme {
        switch preferences.overlayTheme {
        case "Light":
            return .light
        case "Dark":
            return .dark
        default: // "System"
            return systemColorScheme
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = popover.currentError {
                // Main content with category indicator and message
                HStack(alignment: .top, spacing: 10) {
                    // Subtle category indicator
                    Circle()
                        .fill(colors.categoryColor(for: error.category))
                        .frame(width: 6, height: 6)
                        .padding(.top, 8)
                        .accessibilityLabel("Category: \(error.category)")

                    VStack(alignment: .leading, spacing: 12) {
                        // Filter out empty and whitespace-only suggestions (computed early for conditional display)
                        // Empty suggestions mean "delete this" - don't show empty buttons
                        let validSuggestions = error.suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                        // Check if we have actionable suggestions (not AI rephrase which shows differently)
                        let isAIRephrase = error.category == "Readability" && validSuggestions.count == 2
                        let hasRegularSuggestions = !validSuggestions.isEmpty && !isAIRephrase

                        // Clean category label
                        Text(error.category.uppercased())
                            .font(.system(size: captionTextSize, weight: .semibold, design: .rounded))
                            .foregroundColor(colors.textSecondary)
                            .tracking(0.6)
                            .accessibilityLabel("Category: \(error.category)")

                        // Show error message only when there are no actionable suggestions
                        // When suggestions exist, the sentence context makes the issue clear
                        if !hasRegularSuggestions {
                            Text(error.message)
                                .font(.system(size: bodyTextSize))
                                .foregroundColor(colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Error: \(error.message)")
                        }

                        // Show sentence context with highlighted error word(s)
                        // Uses bodyTextSize to respect typography setting
                        if !popover.sourceText.isEmpty {
                            SentenceContextView(
                                sourceText: popover.sourceText,
                                error: error,
                                allErrors: popover.allErrors,
                                colors: colors,
                                textSize: bodyTextSize
                            )
                        }

                        // Check if this is a readability error awaiting AI suggestion
                        let isLoadingAI = error.category == "Readability" &&
                            error.message.lowercased().contains("words long") &&
                            validSuggestions.isEmpty

                        if isLoadingAI {
                            // Show loading indicator while AI generates suggestion
                            HStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.85)
                                    .tint(Color.purple)
                                Text("Generating AI suggestion...")
                                    .font(.system(size: bodyTextSize))
                                    .foregroundColor(colors.textSecondary)
                                    .italic()
                            }
                            .padding(.top, 4)
                            .accessibilityLabel("Generating AI suggestion, please wait")

                        } else if isAIRephrase {
                            let originalText = validSuggestions[0]
                            let rephraseText = validSuggestions[1]

                            // Show AI rephrase in before/after format like style suggestions
                            VStack(alignment: .leading, spacing: 8) {
                                // Original text
                                HStack(alignment: .top, spacing: 8) {
                                    Text("Before:")
                                        .font(.system(size: bodyTextSize * 0.85, weight: .medium))
                                        .foregroundColor(colors.textSecondary)
                                        .frame(width: 50, alignment: .leading)
                                    Text(originalText)
                                        .font(.system(size: bodyTextSize))
                                        .foregroundColor(.red.opacity(0.85))
                                        .strikethrough(true, color: .red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Original text: \(originalText)")

                                // AI suggested text
                                HStack(alignment: .top, spacing: 8) {
                                    Text("After:")
                                        .font(.system(size: bodyTextSize * 0.85, weight: .medium))
                                        .foregroundColor(colors.textSecondary)
                                        .frame(width: 50, alignment: .leading)
                                    Text(rephraseText)
                                        .font(.system(size: bodyTextSize))
                                        .foregroundColor(.green)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Suggested text: \(rephraseText)")
                            }
                            .padding(.vertical, 4)

                            // Accept button for AI suggestion
                            Button(action: {
                                popover.applySuggestion(rephraseText)
                            }) {
                                Label("Apply AI Suggestion", systemImage: "sparkles")
                                    .font(.system(size: bodyTextSize, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(popover.isProcessing ? Color.purple.opacity(0.5) : Color.purple)
                                    )
                                    .shadow(color: Color.purple.opacity(0.25), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .disabled(popover.isProcessing)
                            .keyboardShortcut("1", modifiers: .command)
                            .help("Apply AI suggestion (⌘1)")
                            .accessibilityLabel("Apply AI rephrase suggestion")
                            .accessibilityHint("Double tap to replace the long sentence with AI-improved version")

                        } else if !validSuggestions.isEmpty {
                            // Standard suggestion buttons (for regular grammar errors)
                            // Use FlowLayout to wrap buttons if they don't fit in one row
                            FlowLayout(spacing: 6) {
                                ForEach(Array(validSuggestions.prefix(3).enumerated()), id: \.offset) { index, suggestion in
                                    Button(action: {
                                        popover.applySuggestion(suggestion)
                                    }) {
                                        Text(suggestion)
                                            .font(.system(size: bodyTextSize, weight: .medium))
                                            .foregroundColor(.white)
                                            .fixedSize(horizontal: true, vertical: false)  // Never truncate
                                            .padding(.horizontal, 8)  // Reduced from 10 to fit more buttons
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 7)
                                                    .fill(popover.isProcessing ? colors.primary.opacity(0.5) : colors.primary)
                                            )
                                            .shadow(color: colors.primary.opacity(0.25), radius: 4, x: 0, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(popover.isProcessing)
                                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                                    .help("Apply suggestion (⌘\(index + 1))")
                                    .accessibilityLabel("Apply suggestion: \(suggestion)")
                                    .accessibilityHint("Double tap to apply this suggestion")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Clean close button - aligned to top, doesn't push content up
                    Button(action: { popover.hide() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(colors.backgroundRaised)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: .option)
                    .help("Close (⌥Esc)")
                    .accessibilityLabel("Close suggestion popover")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 18)

                // Bottom action bar with subtle border
                Divider()
                    .background(colors.border)

                HStack(spacing: 12) {
                    // Ignore button - Light blue accent
                    Button(action: { popover.dismissError() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(
                                    Color(
                                        hue: 215/360,
                                        saturation: 0.30,
                                        brightness: effectiveColorScheme == .dark ? 0.18 : 0.93
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(
                                            Color(hue: 215/360, saturation: 0.40, brightness: effectiveColorScheme == .dark ? 0.30 : 0.80),
                                            lineWidth: 1
                                        )
                                )
                                .frame(width: 34, height: 34)
                            Image(systemName: "eye.slash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(
                                    Color(hue: 215/360, saturation: 0.70, brightness: effectiveColorScheme == .dark ? 0.75 : 0.45)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Ignore this error")
                    .accessibilityLabel("Ignore this error")
                    .accessibilityHint("Double tap to dismiss this error for this session")

                    // Ignore Rule button - Medium blue accent
                    Button(action: { popover.ignoreRule() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(
                                    Color(
                                        hue: 215/360,
                                        saturation: 0.35,
                                        brightness: effectiveColorScheme == .dark ? 0.20 : 0.91
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(
                                            Color(hue: 215/360, saturation: 0.45, brightness: effectiveColorScheme == .dark ? 0.35 : 0.75),
                                            lineWidth: 1
                                        )
                                )
                                .frame(width: 34, height: 34)
                            Image(systemName: "nosign")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(
                                    Color(hue: 215/360, saturation: 0.75, brightness: effectiveColorScheme == .dark ? 0.70 : 0.40)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Never show this rule again")
                    .accessibilityLabel("Never show this rule")
                    .accessibilityHint("Double tap to permanently ignore this grammar rule")

                    if error.category == "Spelling" {
                        Button(action: { popover.addToDictionary() }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(
                                        Color(
                                            hue: 215/360,
                                            saturation: 0.50,
                                            brightness: effectiveColorScheme == .dark ? 0.25 : 0.88
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(colors.primary.opacity(0.5), lineWidth: 1)
                                    )
                                    .frame(width: 34, height: 34)
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(colors.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Add this word to your personal dictionary")
                        .accessibilityLabel("Add to dictionary")
                        .accessibilityHint("Double tap to add this word to your personal dictionary")
                    }

                    Spacer()

                    // Navigation controls (show when multiple items total - grammar errors + style suggestions)
                    if popover.totalItemCount > 1 {
                        Text("\(popover.unifiedIndex + 1) of \(popover.totalItemCount)")
                            .font(.system(size: captionTextSize, weight: .semibold))
                            .foregroundColor(
                                Color(hue: 215/360, saturation: 0.65, brightness: effectiveColorScheme == .dark ? 0.80 : 0.50)
                            )
                            .accessibilityLabel("Error \(popover.unifiedIndex + 1) of \(popover.totalItemCount)")

                        HStack(spacing: 6) {
                            Button(action: { popover.previousUnifiedItem() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(hue: 215/360, saturation: 0.70, brightness: effectiveColorScheme == .dark ? 0.60 : 0.55),
                                                Color(hue: 215/360, saturation: 0.75, brightness: effectiveColorScheme == .dark ? 0.50 : 0.48)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(6)
                                    .shadow(color: colors.primary.opacity(0.2), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.upArrow, modifiers: [])
                            .help("Previous (↑)")
                            .accessibilityLabel("Previous error")
                            .accessibilityHint("Double tap to go to the previous error")

                            Button(action: { popover.nextUnifiedItem() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(hue: 215/360, saturation: 0.70, brightness: effectiveColorScheme == .dark ? 0.60 : 0.55),
                                                Color(hue: 215/360, saturation: 0.75, brightness: effectiveColorScheme == .dark ? 0.50 : 0.48)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(6)
                                    .shadow(color: colors.primary.opacity(0.2), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.downArrow, modifiers: [])
                            .help("Next (↓)")
                            .accessibilityLabel("Next error")
                            .accessibilityHint("Double tap to go to the next error")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            } else {
                Text("No errors to display")
                    .foregroundColor(colors.textSecondary)
                    .padding()
                    .accessibilityLabel("No grammar errors to display")
            }
        }
        // Apply Liquid Glass styling (macOS 26-inspired frosted glass effect)
        .liquidGlass(
            style: .regular,
            tint: .blue,
            cornerRadius: 14,
            opacity: preferences.suggestionOpacity
        )
        // Fixed width based on content type, vertical sizing to content
        .frame(width: isAIRephraseError ? 500 : 380)
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
            return (.red, "exclamationmark.circle.fill")
        case .warning:
            return (.orange, "exclamationmark.triangle.fill")
        case .info:
            return (.blue, "info.circle.fill")
        }
    }

    /// Get severity color only
    private func severityColor(for severity: GrammarErrorSeverity) -> Color {
        switch severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
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
            return "Error: Critical grammar issue"
        case .warning:
            return "Warning: Grammar suggestion"
        case .info:
            return "Info: Style recommendation"
        }
    }
}
