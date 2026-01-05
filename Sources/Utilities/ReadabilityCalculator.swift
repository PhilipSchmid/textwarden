//
//  ReadabilityCalculator.swift
//  TextWarden
//
//  Calculates readability metrics for text using various algorithms.
//  Currently implements Flesch Reading Ease, expandable for future algorithms.
//

import AppKit
import Foundation

// MARK: - Types

/// Readability algorithm types (expandable for future algorithms)
enum ReadabilityAlgorithm: String, CaseIterable, Codable, Sendable {
    case fleschReadingEase
    // Future: fleschKincaidGrade, gunningFog, smog, colemanLiau, ari
}

/// Target audience level for readability scoring
/// Each level has a minimum Flesch score threshold - text scoring below is considered too complex
enum TargetAudience: String, CaseIterable, Codable, Sendable {
    case accessible // Everyone should understand (casual writing)
    case general // Average adult reader (default writing)
    case professional // Business readers
    case technical // Specialized/formal readers
    case academic // Graduate-level readers

    /// Minimum Flesch Reading Ease score for this audience
    /// Sentences scoring below this threshold are flagged as too complex
    var minimumFleschScore: Double {
        switch self {
        case .accessible: 65.0 // ~8th grade
        case .general: 50.0 // ~10th grade
        case .professional: 40.0 // ~12th grade
        case .technical: 30.0 // College level
        case .academic: 20.0 // Graduate level
        }
    }

    /// Minimum word count for a sentence to be flagged as complex
    /// Short sentences are rarely problematic even if technically "complex"
    static let minimumWordsForComplexityCheck = 12

    /// Margin below threshold before flagging
    /// Only flag sentences that are significantly below the threshold, not borderline
    static let complexityMargin: Double = 10.0

    var displayName: String {
        switch self {
        case .accessible: "Accessible"
        case .general: "General"
        case .professional: "Professional"
        case .technical: "Technical"
        case .academic: "Academic"
        }
    }

    var gradeLevel: String {
        switch self {
        case .accessible: "8th grade"
        case .general: "10th grade"
        case .professional: "12th grade"
        case .technical: "College"
        case .academic: "Graduate"
        }
    }

    var audienceDescription: String {
        switch self {
        case .accessible: "Everyone should understand"
        case .general: "Average adult reader"
        case .professional: "Business professionals"
        case .technical: "Specialized readers"
        case .academic: "Graduate-level readers"
        }
    }

    /// Initialize from display name string
    init?(fromDisplayName name: String) {
        switch name.lowercased() {
        case "accessible": self = .accessible
        case "general": self = .general
        case "professional": self = .professional
        case "technical": self = .technical
        case "academic": self = .academic
        default: return nil
        }
    }
}

/// Result of a readability calculation
struct ReadabilityResult: Sendable {
    let score: Double
    let label: String
    let color: NSColor
    let algorithm: ReadabilityAlgorithm

    /// Emoji indicator based on score
    var emoji: String {
        switch score {
        case 70...: "🟢"
        case 60 ..< 70: "🟡"
        case 50 ..< 60: "🟠"
        case 30 ..< 50: "🟠"
        default: "🔴"
        }
    }

    /// Integer score for display
    var displayScore: Int {
        max(0, min(100, Int(score.rounded())))
    }

    /// Get color relative to target audience threshold
    /// Green = exceeds threshold, Yellow = meets threshold, Orange/Red = below threshold
    func colorForAudience(_ audience: TargetAudience) -> NSColor {
        let threshold = audience.minimumFleschScore
        let delta = score - threshold

        switch delta {
        case 10...: return .systemGreen // Excellent for audience
        case 0 ..< 10: return .systemYellow // Meeting expectations
        case -10 ..< 0: return .systemOrange // Slightly complex
        default: return .systemRed // Too complex
        }
    }

    /// Check if score meets the target audience threshold
    func meetsAudienceThreshold(_ audience: TargetAudience) -> Bool {
        score >= audience.minimumFleschScore
    }
}

/// Result of readability analysis for a single sentence
struct SentenceReadabilityResult: Sendable {
    let sentence: String
    let range: NSRange
    let score: Double
    let wordCount: Int
    let isComplex: Bool // true if below target threshold
    let targetAudience: TargetAudience

    /// Integer score for display
    var displayScore: Int {
        max(0, min(100, Int(score.rounded())))
    }
}

/// Full readability analysis including per-sentence breakdown
struct TextReadabilityAnalysis: Sendable {
    let overallResult: ReadabilityResult
    let sentenceResults: [SentenceReadabilityResult]
    let targetAudience: TargetAudience

    /// Sentences that are too complex for the target audience
    var complexSentences: [SentenceReadabilityResult] {
        sentenceResults.filter(\.isComplex)
    }

    /// Number of sentences analyzed
    var sentenceCount: Int {
        sentenceResults.count
    }

    /// Number of complex sentences
    var complexSentenceCount: Int {
        complexSentences.count
    }
}

// MARK: - Calculator

/// Calculator for text readability metrics
/// Thread-safe: all methods are pure functions operating on input text
final class ReadabilityCalculator: Sendable {
    // MARK: - Singleton

    static let shared = ReadabilityCalculator()

    private init() {}

    // MARK: - Public API

    /// Calculate Flesch Reading Ease score for the given text
    /// Formula: 206.835 - 1.015 × (words/sentences) - 84.6 × (syllables/words)
    /// Returns nil if text has insufficient content (< 1 sentence or < 1 word)
    func fleschReadingEase(for text: String) -> ReadabilityResult? {
        let words = wordCount(text)
        let sentences = sentenceCount(text)
        let syllables = totalSyllables(text)

        // Need at least 1 word and 1 sentence for meaningful calculation
        guard words > 0, sentences > 0 else { return nil }

        let wordsPerSentence = Double(words) / Double(sentences)
        let syllablesPerWord = Double(syllables) / Double(words)

        // Flesch Reading Ease formula
        let score = 206.835 - (1.015 * wordsPerSentence) - (84.6 * syllablesPerWord)

        // Clamp to 0-100 range (formula can produce values outside this range)
        let clampedScore = max(0, min(100, score))

        return ReadabilityResult(
            score: clampedScore,
            label: labelForScore(clampedScore),
            color: colorForScore(clampedScore),
            algorithm: .fleschReadingEase
        )
    }

    // MARK: - Text Analysis Helpers

    /// Count words in text
    func wordCount(_ text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .filter { word in
                // Filter out "words" that are just punctuation
                word.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            }
        return words.count
    }

    /// Count sentences in text
    /// Handles common abbreviations to avoid false positives
    func sentenceCount(_ text: String) -> Int {
        // Common abbreviations that shouldn't end sentences
        let abbreviations = Set([
            "mr", "mrs", "ms", "dr", "prof", "sr", "jr",
            "vs", "etc", "inc", "ltd", "corp",
            "st", "ave", "blvd", "rd",
            "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
            "mon", "tue", "wed", "thu", "fri", "sat", "sun",
            "e.g", "i.e", "viz", "cf",
        ])

        var count = 0
        var i = text.startIndex

        while i < text.endIndex {
            let char = text[i]

            if char == "." || char == "!" || char == "?" {
                // Check if this is likely a sentence ending
                var isAbbreviation = false

                if char == "." {
                    // Look back for potential abbreviation
                    var wordStart = i
                    while wordStart > text.startIndex {
                        let prevIndex = text.index(before: wordStart)
                        let prevChar = text[prevIndex]
                        if prevChar.isLetter || prevChar == "." {
                            wordStart = prevIndex
                        } else {
                            break
                        }
                    }

                    if wordStart < i {
                        let word = String(text[wordStart ..< i]).lowercased()
                        // Remove any embedded periods for abbreviation check
                        let cleanWord = word.replacingOccurrences(of: ".", with: "")
                        isAbbreviation = abbreviations.contains(cleanWord) || abbreviations.contains(word)

                        // Also check for single letter abbreviations (initials)
                        if cleanWord.count == 1 {
                            isAbbreviation = true
                        }
                    }
                }

                if !isAbbreviation {
                    count += 1
                }
            }

            i = text.index(after: i)
        }

        // If no sentence-ending punctuation found but text has words, count as 1 sentence
        if count == 0, wordCount(text) > 0 {
            count = 1
        }

        return count
    }

    /// Count syllables in a single word using vowel group counting
    func syllableCount(_ word: String) -> Int {
        let lowercased = word.lowercased()

        // Remove non-letter characters
        let cleaned = lowercased.filter(\.isLetter)

        guard !cleaned.isEmpty else { return 0 }

        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var previousWasVowel = false

        for char in cleaned {
            let isVowel = vowels.contains(char)

            // Count transitions from consonant to vowel (vowel groups)
            if isVowel, !previousWasVowel {
                count += 1
            }

            previousWasVowel = isVowel
        }

        // Adjust for silent 'e' at end
        if cleaned.hasSuffix("e"), count > 1 {
            // Check if it's not a "le" ending which is usually pronounced
            if !cleaned.hasSuffix("le") || cleaned.count <= 2 {
                count -= 1
            }
        }

        // Handle "ed" endings that don't add a syllable
        if cleaned.hasSuffix("ed"), count > 1 {
            let beforeEd = cleaned.dropLast(2)
            if let lastChar = beforeEd.last, !vowels.contains(lastChar) {
                // Consonant before "ed" - "ed" is usually silent (e.g., "walked")
                // Exception: if ends in 't' or 'd', "ed" is pronounced (e.g., "wanted")
                if lastChar != "t", lastChar != "d" {
                    count -= 1
                }
            }
        }

        // Handle "es" endings
        if cleaned.hasSuffix("es"), count > 1 {
            let beforeEs = cleaned.dropLast(2)
            if let lastChar = beforeEs.last {
                // "es" adds syllable after s, x, z, ch, sh sounds
                let sibilants: Set<Character> = ["s", "x", "z"]
                if !sibilants.contains(lastChar) {
                    // Check for "ch" or "sh" before "es"
                    if beforeEs.count >= 2 {
                        let suffix = String(beforeEs.suffix(2))
                        if suffix != "ch", suffix != "sh" {
                            count -= 1
                        }
                    } else {
                        count -= 1
                    }
                }
            }
        }

        // Minimum 1 syllable per word
        return max(1, count)
    }

    /// Count total syllables in text
    func totalSyllables(_ text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .filter { word in
                word.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            }

        return words.reduce(0) { $0 + syllableCount($1) }
    }

    // MARK: - Sentence-Level Analysis

    /// Split text into individual sentences with their ranges
    /// Uses NSLinguisticTagger for accurate sentence boundary detection
    func splitIntoSentences(_ text: String) -> [(sentence: String, range: NSRange)] {
        guard !text.isEmpty else { return [] }

        var rawResults: [(String, NSRange)] = []

        text.enumerateSubstrings(
            in: text.startIndex ..< text.endIndex,
            options: .bySentences
        ) { substring, substringRange, _, _ in
            guard let sentence = substring else { return }

            // Trim whitespace but preserve the original range for positioning
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Convert String.Index range to NSRange
            let nsRange = NSRange(substringRange, in: text)

            // Find the trimmed sentence's position within the original range
            if let trimmedRange = sentence.range(of: trimmed) {
                let offset = sentence.distance(from: sentence.startIndex, to: trimmedRange.lowerBound)
                let adjustedLocation = nsRange.location + offset
                let adjustedRange = NSRange(location: adjustedLocation, length: trimmed.count)
                rawResults.append((trimmed, adjustedRange))
            } else {
                rawResults.append((trimmed, nsRange))
            }
        }

        // Post-process to merge sentence fragments split by parenthetical punctuation.
        // Example: "I wanted to ask (next week?) to discuss..." incorrectly splits at "?"
        // A fragment starting with lowercase after a parenthetical ending should be merged.
        return mergeParentheticalFragments(rawResults, in: text)
    }

    /// Merge sentence fragments that were incorrectly split by punctuation inside parentheses.
    /// Example: "Please call me (maybe tomorrow?) and we can discuss." may split at "?" incorrectly.
    /// We detect this by checking what precedes the opening parenthesis - if it's a word (not
    /// sentence-ending punctuation), the parenthetical is part of the same sentence.
    private func mergeParentheticalFragments(_ sentences: [(String, NSRange)], in text: String) -> [(String, NSRange)] {
        guard sentences.count > 1 else { return sentences }

        var merged: [(String, NSRange)] = []

        var i = 0
        while i < sentences.count {
            var (currentSentence, currentRange) = sentences[i]

            // Look ahead and merge fragments that appear to be continuations
            while i + 1 < sentences.count {
                let (nextSentence, nextRange) = sentences[i + 1]
                guard let firstChar = nextSentence.first else { break }

                // Check if next fragment looks like a continuation:
                // 1. Starts with lowercase letter (e.g., "to continue...")
                // 2. Starts with closing bracket (e.g., ") and then...")
                let startsWithLowercase = firstChar.isLowercase
                let startsWithClosingBracket = firstChar == ")" || firstChar == "]"

                guard startsWithLowercase || startsWithClosingBracket else {
                    break
                }

                // Key check: Was the parenthetical part of a sentence or a standalone?
                // Look at what comes BEFORE the opening parenthesis in the current fragment.
                // If the "(" is preceded by a word (not . ! ?), the parenthetical is inline.
                let parentheticalIsInline = isParentheticalInline(currentSentence)

                // Also check for unclosed brackets (split happened inside parentheses)
                let openParens = currentSentence.count { $0 == "(" }
                let closeParens = currentSentence.count { $0 == ")" }
                let openBrackets = currentSentence.count { $0 == "[" }
                let closeBrackets = currentSentence.count { $0 == "]" }
                let hasUnclosedParenthesis = openParens > closeParens || openBrackets > closeBrackets

                // Must have inline parenthetical OR unclosed brackets to merge
                guard parentheticalIsInline || hasUnclosedParenthesis else {
                    break
                }

                // Merge: extract the combined text from the original
                let combinedEnd = nextRange.location + nextRange.length
                let combinedLength = combinedEnd - currentRange.location

                // Get the merged text from the original string
                if let startIdx = text.index(text.startIndex, offsetBy: currentRange.location, limitedBy: text.endIndex),
                   let endIdx = text.index(startIdx, offsetBy: combinedLength, limitedBy: text.endIndex)
                {
                    currentSentence = String(text[startIdx ..< endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                    currentRange = NSRange(location: currentRange.location, length: currentSentence.count)
                } else {
                    // Fallback: simple concatenation
                    currentSentence = currentSentence + " " + nextSentence
                    currentRange = NSRange(location: currentRange.location, length: combinedLength)
                }

                i += 1
            }

            merged.append((currentSentence, currentRange))
            i += 1
        }

        return merged
    }

    /// Check if a parenthetical in the sentence is inline (part of the sentence) vs standalone.
    /// Returns true if the opening "(" is preceded by a word character (not sentence-ending punctuation).
    /// Example: "I asked (yesterday?) about..." -> true (inline, "asked" precedes "(")
    /// Example: "I asked. (Yesterday?) He replied." -> false (standalone, "." precedes "(")
    private func isParentheticalInline(_ sentence: String) -> Bool {
        // Find the last opening parenthesis or bracket
        guard let lastOpenParen = sentence.lastIndex(where: { $0 == "(" || $0 == "[" }) else {
            return false
        }

        // Get the character before the opening parenthesis (skipping whitespace)
        var checkIndex = lastOpenParen
        while checkIndex > sentence.startIndex {
            checkIndex = sentence.index(before: checkIndex)
            let char = sentence[checkIndex]

            // Skip whitespace
            if char.isWhitespace {
                continue
            }

            // If we find sentence-ending punctuation, it's NOT inline
            if char == "." || char == "!" || char == "?" || char == ":" || char == ";" {
                return false
            }

            // If we find a word character or closing quote, it IS inline
            if char.isLetter || char.isNumber || char == "\"" || char == "'" || char == ")" || char == "]" {
                return true
            }

            // Any other character (like comma), consider it inline
            return true
        }

        // Opening paren is at the start of the sentence
        return false
    }

    /// Calculate Flesch Reading Ease for a single sentence
    /// Adapted formula for single sentences with minimum thresholds
    func fleschReadingEaseForSentence(_ sentence: String) -> Double? {
        let words = wordCount(sentence)

        // Skip very short sentences (less than 3 words)
        guard words >= 3 else { return nil }

        let syllables = totalSyllables(sentence)
        guard syllables > 0 else { return nil }

        // For single sentences, we use words per sentence = total words (since it's 1 sentence)
        let wordsPerSentence = Double(words)
        let syllablesPerWord = Double(syllables) / Double(words)

        // Standard Flesch formula
        let score = 206.835 - (1.015 * wordsPerSentence) - (84.6 * syllablesPerWord)

        // Clamp to 0-100 range
        return max(0, min(100, score))
    }

    /// Perform full readability analysis with per-sentence breakdown
    /// Returns nil if text has insufficient content
    func analyzeForTargetAudience(
        _ text: String,
        targetAudience: TargetAudience
    ) -> TextReadabilityAnalysis? {
        // Get overall readability first
        guard let overallResult = fleschReadingEase(for: text) else {
            Logger.debug("ReadabilityCalculator: analyzeForTargetAudience - no overall result", category: Logger.analysis)
            return nil
        }

        // Split into sentences and analyze each
        let sentences = splitIntoSentences(text)
        Logger.debug("ReadabilityCalculator: analyzeForTargetAudience - found \(sentences.count) sentences, threshold=\(targetAudience.minimumFleschScore)", category: Logger.analysis)

        // Cap at 50 sentences for performance
        let sentencesToAnalyze = Array(sentences.prefix(50))

        var sentenceResults: [SentenceReadabilityResult] = []

        for (sentence, range) in sentencesToAnalyze {
            // Skip code-like content (contains backticks or looks like code)
            if sentence.contains("`") || looksLikeCode(sentence) {
                continue
            }

            guard let score = fleschReadingEaseForSentence(sentence) else {
                Logger.trace("ReadabilityCalculator: skipping sentence (no score) - '\(sentence.prefix(50))...'", category: Logger.analysis)
                continue
            }

            let words = wordCount(sentence)

            // Skip short sentences - they're rarely problematic even if technically "complex"
            guard words >= TargetAudience.minimumWordsForComplexityCheck else {
                Logger.trace("ReadabilityCalculator: skipping short sentence (\(words) words) - '\(sentence.prefix(30))...'", category: Logger.analysis)
                continue
            }

            // Only flag as complex if SIGNIFICANTLY below threshold (not just borderline)
            // This reduces noise from sentences that are just barely below the threshold
            let effectiveThreshold = targetAudience.minimumFleschScore - TargetAudience.complexityMargin
            let isComplex = score < effectiveThreshold
            Logger.debug("ReadabilityCalculator: sentence score=\(Int(score)), words=\(words), threshold=\(Int(effectiveThreshold)), isComplex=\(isComplex) - '\(sentence.prefix(50))...'", category: Logger.analysis)

            let result = SentenceReadabilityResult(
                sentence: sentence,
                range: range,
                score: score,
                wordCount: words,
                isComplex: isComplex,
                targetAudience: targetAudience
            )

            sentenceResults.append(result)
        }

        return TextReadabilityAnalysis(
            overallResult: overallResult,
            sentenceResults: sentenceResults,
            targetAudience: targetAudience
        )
    }

    /// Check if text looks like code (simple heuristic)
    private func looksLikeCode(_ text: String) -> Bool {
        // Check for common code patterns
        let codeIndicators = [
            "func ", "var ", "let ", "class ", "struct ", "enum ", // Swift
            "function ", "const ", "=>", // JavaScript
            "def ", "import ", "from ", // Python
            "->", "::", "&&", "||", "==", "!=", // General operators
        ]

        for indicator in codeIndicators {
            if text.contains(indicator) {
                return true
            }
        }

        // Check if mostly special characters
        let letterCount = text.filter(\.isLetter).count
        let totalCount = text.count
        if totalCount > 10, Double(letterCount) / Double(totalCount) < 0.5 {
            return true
        }

        return false
    }

    // MARK: - Score Interpretation

    /// Get human-readable label for a Flesch Reading Ease score
    private func labelForScore(_ score: Double) -> String {
        switch score {
        case 90...: "Very Easy"
        case 80 ..< 90: "Easy"
        case 70 ..< 80: "Fairly Easy"
        case 60 ..< 70: "Standard"
        case 50 ..< 60: "Fairly Difficult"
        case 30 ..< 50: "Difficult"
        default: "Very Difficult"
        }
    }

    /// Get color for a Flesch Reading Ease score
    private func colorForScore(_ score: Double) -> NSColor {
        switch score {
        case 70...: .systemGreen
        case 60 ..< 70: .systemYellow
        case 50 ..< 60: .systemOrange
        case 30 ..< 50: .systemOrange
        default: .systemRed
        }
    }
}

// MARK: - Readability Tips

extension ReadabilityResult {
    /// Get improvement tips based on score
    var improvementTips: [String] {
        guard algorithm == .fleschReadingEase else { return [] }

        switch score {
        case 70...:
            return [] // Good readability, no tips needed
        case 60 ..< 70:
            return [
                "Consider breaking longer sentences into shorter ones",
                "Replace some complex words with simpler alternatives",
            ]
        case 50 ..< 60:
            return [
                "Use shorter sentences (aim for 15-20 words)",
                "Replace multi-syllable words where possible",
                "Break up long paragraphs",
            ]
        case 30 ..< 50:
            return [
                "Significantly shorten your sentences",
                "Use simpler, everyday vocabulary",
                "Consider your audience's reading level",
                "Remove unnecessary jargon",
            ]
        default:
            return [
                "Rewrite using much simpler language",
                "Keep sentences under 15 words",
                "Use common, one or two-syllable words",
                "Consider breaking into multiple shorter pieces",
            ]
        }
    }

    /// Brief description of what the score means
    var interpretation: String {
        switch score {
        case 90...:
            "Very easy to read. Clear and simple language."
        case 80 ..< 90:
            "Easy to read. Conversational and accessible."
        case 70 ..< 80:
            "Fairly easy to read. Good for most audiences."
        case 60 ..< 70:
            "Standard readability. Clear but slightly complex."
        case 50 ..< 60:
            "Fairly difficult to read. Consider simplifying."
        case 30 ..< 50:
            "Difficult to read. Try shorter sentences and simpler words."
        default:
            "Very difficult to read. Needs significant simplification."
        }
    }
}
