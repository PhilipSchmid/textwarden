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

    public init(
        id: String = UUID().uuidString,
        originalStart: Int,
        originalEnd: Int,
        originalText: String,
        suggestedText: String,
        explanation: String,
        confidence: Float = 0.8,
        style: WritingStyle = .default,
        diff: [DiffSegmentModel] = []
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
    }

    /// Range of the original text
    public var range: Range<Int> {
        originalStart ..< originalEnd
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
