// StyleTypes.swift
// Swift models for style checking (Apple Intelligence)

import Foundation

// MARK: - Writing Style

/// Writing style for style suggestions
public enum WritingStyle: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case formal
    case informal
    case business
    case concise

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .default: "Default"
        case .formal: "Formal"
        case .informal: "Casual"
        case .business: "Business"
        case .concise: "Concise"
        }
    }

    public var description: String {
        switch self {
        case .default: "Balanced style improvements"
        case .formal: "Professional tone, complete sentences"
        case .informal: "Friendly, conversational writing"
        case .business: "Clear, action-oriented communication"
        case .concise: "Brief and to the point, no filler"
        }
    }
}

// MARK: - Target Audience Mapping

extension WritingStyle {
    /// Target audience inferred from writing style
    /// Determines the minimum Flesch score threshold for readability
    var targetAudience: TargetAudience {
        switch self {
        case .informal: .accessible // Casual = everyone should understand
        case .default: .general // Default = average adult reader
        case .concise: .general // Concise = focus on brevity, not complexity
        case .business: .professional // Business = professional readers
        case .formal: .technical // Formal = specialized readers
        }
    }
}

// MARK: - Suggestion Impact

/// Impact level for style suggestions, used to filter out low-value suggestions
/// in automatic checks while showing them in manual checks.
public enum SuggestionImpact: Int, Comparable {
    /// High impact: Sentence restructuring, major clarity issues, significant tone mismatches
    case high = 3
    /// Medium impact: Phrase improvements, formality adjustments
    case medium = 2
    /// Low impact: Minor word preferences, optional style choices
    case low = 1

    public static func < (lhs: SuggestionImpact, rhs: SuggestionImpact) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Diff Segment

/// Kind of change in a diff
public enum DiffChangeKind: Equatable {
    case unchanged
    case added
    case removed
}

/// A segment of text in a diff
public struct DiffSegmentModel: Identifiable {
    public let id = UUID()
    public let text: String
    public let kind: DiffChangeKind

    public init(text: String, kind: DiffChangeKind) {
        self.text = text
        self.kind = kind
    }
}

// MARK: - Style Suggestion

/// A style improvement suggestion
public struct StyleSuggestionModel: Identifiable {
    public let id: String
    public let originalStart: Int
    public let originalEnd: Int
    public let originalText: String
    public let suggestedText: String
    public let explanation: String
    public let confidence: Float
    public let style: WritingStyle
    public let diff: [DiffSegmentModel]

    /// Whether this is a readability simplification suggestion (vs regular style suggestion)
    public let isReadabilitySuggestion: Bool

    /// Original readability score of the sentence (only set for readability suggestions)
    public let readabilityScore: Int?

    /// Target audience for readability suggestions
    public let targetAudience: String?

    public init(
        id: String = UUID().uuidString,
        originalStart: Int,
        originalEnd: Int,
        originalText: String,
        suggestedText: String,
        explanation: String,
        confidence: Float = 0.8,
        style: WritingStyle = .default,
        diff: [DiffSegmentModel] = [],
        isReadabilitySuggestion: Bool = false,
        readabilityScore: Int? = nil,
        targetAudience: String? = nil
    ) {
        self.id = id
        self.originalStart = originalStart
        self.originalEnd = originalEnd
        self.originalText = originalText
        self.suggestedText = suggestedText
        self.explanation = explanation
        self.confidence = confidence
        self.style = style
        self.diff = diff
        self.isReadabilitySuggestion = isReadabilitySuggestion
        self.readabilityScore = readabilityScore
        self.targetAudience = targetAudience
    }

    /// Range of the original text
    public var range: Range<Int> {
        originalStart ..< originalEnd
    }

    /// Computed impact level based on suggestion characteristics
    /// Used for filtering in auto-check mode
    public var impact: SuggestionImpact {
        // Readability suggestions are always high impact (complex sentences affect comprehension)
        if isReadabilitySuggestion {
            return .high
        }

        // Calculate based on change magnitude
        let originalLength = originalText.count
        let suggestedLength = suggestedText.count
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
        if confidence >= 0.85 {
            return .medium
        }

        // Low confidence single-word changes: low impact
        return .low
    }
}

// MARK: - Style Analysis Result

/// Result of style analysis
public struct StyleAnalysisResultModel {
    public let suggestions: [StyleSuggestionModel]
    public let analysisTimeMs: UInt64
    public let style: WritingStyle
    public let error: String?

    public var isError: Bool {
        error != nil
    }

    public init(
        suggestions: [StyleSuggestionModel] = [],
        analysisTimeMs: UInt64 = 0,
        style: WritingStyle = .default,
        error: String? = nil
    ) {
        self.suggestions = suggestions
        self.analysisTimeMs = analysisTimeMs
        self.style = style
        self.error = error
    }

    public static var empty: StyleAnalysisResultModel {
        StyleAnalysisResultModel()
    }

    public static func failure(_ message: String) -> StyleAnalysisResultModel {
        StyleAnalysisResultModel(error: message)
    }
}

// MARK: - Rejection Category

/// Category for why a suggestion was rejected
public enum SuggestionRejectionCategory: String, CaseIterable {
    case wrongMeaning = "wrong_meaning"
    case tooFormal = "too_formal"
    case tooInformal = "too_informal"
    case unnecessaryChange = "unnecessary_change"
    case wrongTerm = "wrong_term"
    case other

    public var displayName: String {
        switch self {
        case .wrongMeaning: "Changes meaning"
        case .tooFormal: "Too formal"
        case .tooInformal: "Too informal"
        case .unnecessaryChange: "Unnecessary change"
        case .wrongTerm: "Wrong term/word"
        case .other: "Other reason"
        }
    }
}
