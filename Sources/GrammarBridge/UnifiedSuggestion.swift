// UnifiedSuggestion.swift
// TextWarden
//
// Unified suggestion model that provides a consistent interface
// for grammar, style, and readability suggestions.

import Foundation

// MARK: - Suggestion Category

/// Category of suggestion, determines visual presentation and available actions.
/// Maps to the three-section indicator: Correctness (red), Style+Clarity (purple/blue).
public enum SuggestionCategory: String, CaseIterable, Sendable {
    /// Red - Spelling, grammar, punctuation errors (Harper engine)
    case correctness
    /// Blue - Readability, sentence complexity simplification (Apple Intelligence)
    case clarity
    /// Purple - Tone, formality, word choice improvements (Apple Intelligence)
    case style

    public var displayName: String {
        switch self {
        case .correctness: "Correctness"
        case .clarity: "Clarity"
        case .style: "Style"
        }
    }

    /// Color identifier for UI theming
    public var colorName: String {
        switch self {
        case .correctness: "errorRed"
        case .clarity: "clarityBlue"
        case .style: "stylePurple"
        }
    }
}

// MARK: - Suggestion Severity

/// Severity level for suggestions, affects visual prominence.
public enum SuggestionSeverity: Int, Comparable, Sendable {
    /// Critical issue that should be fixed
    case error = 3
    /// Potential issue worth reviewing
    case warning = 2
    /// Informational suggestion
    case info = 1

    public static func < (lhs: SuggestionSeverity, rhs: SuggestionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Convert from GrammarErrorSeverity
    init(grammarSeverity: GrammarErrorSeverity) {
        switch grammarSeverity {
        case .error: self = .error
        case .warning: self = .warning
        case .info: self = .info
        }
    }
}

// MARK: - Suggestion Source

/// Source engine that produced the suggestion.
public enum SuggestionSource: String, Sendable {
    /// Harper Rust grammar engine via FFI
    case harper
    /// Apple Intelligence Foundation Models
    case appleIntelligence

    public var displayName: String {
        switch self {
        case .harper: "Grammar Check"
        case .appleIntelligence: "Apple Intelligence"
        }
    }
}

// MARK: - Unified Suggestion

/// A unified suggestion that can represent grammar errors, style improvements,
/// or readability simplifications with a consistent interface.
///
/// This model provides:
/// - Consistent presentation across all suggestion types
/// - Category-based filtering and grouping
/// - Source tracking for analytics and user preferences
/// - All metadata needed for UI display and actions
public struct UnifiedSuggestion: Identifiable, Hashable, Sendable {
    /// Unique identifier
    public let id: String

    /// Category determines visual presentation and available actions
    public let category: SuggestionCategory

    /// Character offset where the suggestion applies (start)
    public let start: Int

    /// Character offset where the suggestion applies (end)
    public let end: Int

    /// The original text that the suggestion applies to
    public let originalText: String

    /// The suggested replacement text (nil for info-only suggestions)
    public let suggestedText: String?

    /// Human-readable explanation of the suggestion
    public let message: String

    /// Severity level (error, warning, info)
    public let severity: SuggestionSeverity

    /// Which engine produced this suggestion
    public let source: SuggestionSource

    // MARK: - Category-Specific Metadata

    /// Harper lint rule ID (for "Ignore Rule" action)
    public let lintId: String?

    /// AI confidence score (0.0-1.0)
    public let confidence: Float?

    /// Diff segments for visualization (style suggestions)
    public let diff: [DiffSegmentModel]?

    /// Readability score (for clarity suggestions)
    public let readabilityScore: Int?

    /// Target audience description (for clarity suggestions)
    public let targetAudience: String?

    /// Alternative suggestions (for grammar errors with multiple options)
    public let alternatives: [String]?

    /// Writing style context (for style suggestions)
    public let writingStyle: WritingStyle?

    // MARK: - Computed Properties

    /// Range of the affected text
    public var range: Range<Int> {
        start ..< end
    }

    /// Whether this suggestion has a concrete replacement
    public var hasReplacement: Bool {
        suggestedText != nil && suggestedText != originalText
    }

    /// Impact level for filtering (derived from category and characteristics)
    public var impact: SuggestionImpact {
        switch category {
        case .correctness:
            // Grammar errors are always high impact (spelling mistakes, etc.)
            return severity == .error ? .high : .medium
        case .clarity:
            // Readability issues are high impact (affect comprehension)
            return .high
        case .style:
            // Style suggestions use the impact calculation from StyleSuggestionModel
            if let conf = confidence {
                let originalLength = originalText.count
                let suggestedLength = suggestedText?.count ?? originalLength
                let lengthDiff = abs(originalLength - suggestedLength)

                // Sentence restructuring: significant length change (>30%) = high impact
                if originalLength > 20, Double(lengthDiff) / Double(originalLength) > 0.3 {
                    return .high
                }

                // Phrase-level changes (multiple words): medium impact
                let wordCount = originalText.split(separator: " ").count
                if wordCount >= 3 {
                    return .medium
                }

                // Single word changes: depends on confidence
                if conf >= 0.85 {
                    return .medium
                }
            }
            return .low
        }
    }

    // MARK: - Initialization

    public init(
        id: String = UUID().uuidString,
        category: SuggestionCategory,
        start: Int,
        end: Int,
        originalText: String,
        suggestedText: String?,
        message: String,
        severity: SuggestionSeverity = .warning,
        source: SuggestionSource,
        lintId: String? = nil,
        confidence: Float? = nil,
        diff: [DiffSegmentModel]? = nil,
        readabilityScore: Int? = nil,
        targetAudience: String? = nil,
        alternatives: [String]? = nil,
        writingStyle: WritingStyle? = nil
    ) {
        self.id = id
        self.category = category
        self.start = start
        self.end = end
        self.originalText = originalText
        self.suggestedText = suggestedText
        self.message = message
        self.severity = severity
        self.source = source
        self.lintId = lintId
        self.confidence = confidence
        self.diff = diff
        self.readabilityScore = readabilityScore
        self.targetAudience = targetAudience
        self.alternatives = alternatives
        self.writingStyle = writingStyle
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: UnifiedSuggestion, rhs: UnifiedSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Conversion Extensions

public extension GrammarErrorModel {
    /// Convert grammar error to unified suggestion format.
    /// - Parameter text: The full text being analyzed (to extract original text)
    /// - Returns: UnifiedSuggestion representing this grammar error
    func toUnifiedSuggestion(in text: String) -> UnifiedSuggestion {
        // Extract original text from the full text using the error range
        let originalText = if let startIndex = text.index(text.startIndex, offsetBy: start, limitedBy: text.endIndex),
                              let endIndex = text.index(text.startIndex, offsetBy: end, limitedBy: text.endIndex),
                              startIndex < endIndex
        {
            String(text[startIndex ..< endIndex])
        } else {
            ""
        }

        // Use first suggestion as the primary replacement
        let suggestedText = suggestions.first

        return UnifiedSuggestion(
            id: "\(lintId)-\(start)-\(end)",
            category: .correctness,
            start: start,
            end: end,
            originalText: originalText,
            suggestedText: suggestedText,
            message: message,
            severity: SuggestionSeverity(grammarSeverity: severity),
            source: .harper,
            lintId: lintId,
            alternatives: suggestions.count > 1 ? Array(suggestions.dropFirst()) : nil
        )
    }
}

public extension StyleSuggestionModel {
    /// Convert style suggestion to unified suggestion format.
    /// - Returns: UnifiedSuggestion representing this style suggestion
    func toUnifiedSuggestion() -> UnifiedSuggestion {
        // Determine category based on whether this is a readability suggestion
        let category: SuggestionCategory = isReadabilitySuggestion ? .clarity : .style

        // Map severity based on confidence
        let severity: SuggestionSeverity = if confidence >= 0.85 {
            .warning
        } else {
            .info
        }

        return UnifiedSuggestion(
            id: id,
            category: category,
            start: originalStart,
            end: originalEnd,
            originalText: originalText,
            suggestedText: suggestedText,
            message: explanation,
            severity: severity,
            source: .appleIntelligence,
            confidence: confidence,
            diff: diff,
            readabilityScore: readabilityScore,
            targetAudience: targetAudience,
            writingStyle: style
        )
    }
}
