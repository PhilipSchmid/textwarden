//
//  Suggestion.swift
//  TextWarden
//
//  Model for grammar correction suggestions
//

import Foundation

/// A suggested correction for a grammar error
@objc public class SuggestionModel: NSObject {
    /// Unique identifier for this suggestion
    @objc public let suggestionId: String

    /// The replacement text to use
    @objc public let replacementText: String

    /// Plain-language explanation (8th-grade reading level)
    @objc public let explanation: String

    /// Confidence score (0.0-1.0)
    @objc public let confidence: Double

    /// Associated grammar rule ID
    @objc public let ruleId: String

    /// Initialize a suggestion
    @objc public init(
        suggestionId: String,
        replacementText: String,
        explanation: String,
        confidence: Double,
        ruleId: String
    ) {
        self.suggestionId = suggestionId
        self.replacementText = replacementText
        self.explanation = explanation
        self.confidence = confidence
        self.ruleId = ruleId
        super.init()
    }

    public override var description: String {
        "[\(Int(confidence * 100))%] \(replacementText) - \(explanation)"
    }
}

/// Collection of suggestions for a grammar error
@objc public class SuggestionsResult: NSObject {
    /// List of ranked suggestions (highest confidence first)
    @objc public let suggestions: [SuggestionModel]

    /// Initialize with suggestions array
    @objc public init(suggestions: [SuggestionModel]) {
        self.suggestions = suggestions.sorted { $0.confidence > $1.confidence }
        super.init()
    }

    /// Get the top N suggestions
    @objc public func top(_ count: Int) -> [SuggestionModel] {
        return Array(suggestions.prefix(count))
    }
}
