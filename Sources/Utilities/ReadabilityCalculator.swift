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
