// PreferenceLearner.swift
// Tracks user preferences from accept/reject decisions on style suggestions

import Foundation
import Combine

/// Tracks user preferences for style suggestions
///
/// Records when users accept or reject suggestions to improve future recommendations.
/// Acceptance patterns help the LLM understand preferred writing style.
/// Rejection patterns with categories help avoid similar unwanted suggestions.
@available(macOS 10.15, *)
public class PreferenceLearner: ObservableObject {

    /// Shared singleton instance
    public static let shared = PreferenceLearner()

    /// Total number of suggestions accepted in this session
    @Published public private(set) var acceptedCount: Int = 0

    /// Total number of suggestions rejected in this session
    @Published public private(set) var rejectedCount: Int = 0

    /// Acceptance rate (0.0 - 1.0) for this session
    public var acceptanceRate: Double {
        let total = acceptedCount + rejectedCount
        guard total > 0 else { return 0.0 }
        return Double(acceptedCount) / Double(total)
    }

    /// Recent acceptance decisions for display
    @Published public private(set) var recentAcceptances: [AcceptanceRecord] = []

    /// Recent rejection decisions for display
    @Published public private(set) var recentRejections: [RejectionRecord] = []

    /// Maximum number of recent records to keep in memory
    private let maxRecentRecords = 50

    private init() {}

    // MARK: - Recording Decisions

    /// Record that a suggestion was accepted
    ///
    /// - Parameters:
    ///   - suggestion: The style suggestion that was accepted
    public func recordAcceptance(_ suggestion: StyleSuggestionModel) {
        LLMEngine.shared.recordAcceptance(
            original: suggestion.originalText,
            suggested: suggestion.suggestedText,
            style: suggestion.style
        )

        acceptedCount += 1

        let record = AcceptanceRecord(
            originalText: suggestion.originalText,
            suggestedText: suggestion.suggestedText,
            style: suggestion.style,
            timestamp: Date()
        )

        recentAcceptances.insert(record, at: 0)
        if recentAcceptances.count > maxRecentRecords {
            recentAcceptances.removeLast()
        }
    }

    /// Record that a suggestion was accepted with raw values
    ///
    /// - Parameters:
    ///   - original: The original text
    ///   - suggested: The suggested replacement
    ///   - style: The writing style used
    public func recordAcceptance(
        original: String,
        suggested: String,
        style: WritingStyle
    ) {
        LLMEngine.shared.recordAcceptance(
            original: original,
            suggested: suggested,
            style: style
        )

        acceptedCount += 1

        let record = AcceptanceRecord(
            originalText: original,
            suggestedText: suggested,
            style: style,
            timestamp: Date()
        )

        recentAcceptances.insert(record, at: 0)
        if recentAcceptances.count > maxRecentRecords {
            recentAcceptances.removeLast()
        }
    }

    /// Record that a suggestion was rejected
    ///
    /// - Parameters:
    ///   - suggestion: The style suggestion that was rejected
    ///   - category: The reason for rejection
    public func recordRejection(
        _ suggestion: StyleSuggestionModel,
        category: SuggestionRejectionCategory
    ) {
        LLMEngine.shared.recordRejection(
            original: suggestion.originalText,
            suggested: suggestion.suggestedText,
            style: suggestion.style,
            category: category
        )

        rejectedCount += 1

        let record = RejectionRecord(
            originalText: suggestion.originalText,
            suggestedText: suggestion.suggestedText,
            style: suggestion.style,
            category: category,
            timestamp: Date()
        )

        recentRejections.insert(record, at: 0)
        if recentRejections.count > maxRecentRecords {
            recentRejections.removeLast()
        }
    }

    /// Record that a suggestion was rejected with raw values
    ///
    /// - Parameters:
    ///   - original: The original text
    ///   - suggested: The suggested replacement
    ///   - style: The writing style used
    ///   - category: The reason for rejection
    public func recordRejection(
        original: String,
        suggested: String,
        style: WritingStyle,
        category: SuggestionRejectionCategory
    ) {
        LLMEngine.shared.recordRejection(
            original: original,
            suggested: suggested,
            style: style,
            category: category
        )

        rejectedCount += 1

        let record = RejectionRecord(
            originalText: original,
            suggestedText: suggested,
            style: style,
            category: category,
            timestamp: Date()
        )

        recentRejections.insert(record, at: 0)
        if recentRejections.count > maxRecentRecords {
            recentRejections.removeLast()
        }
    }

    // MARK: - Statistics

    /// Get rejection counts by category
    public var rejectionsByCategory: [SuggestionRejectionCategory: Int] {
        var counts: [SuggestionRejectionCategory: Int] = [:]
        for record in recentRejections {
            counts[record.category, default: 0] += 1
        }
        return counts
    }

    /// Get the most common rejection reason
    public var mostCommonRejectionReason: SuggestionRejectionCategory? {
        rejectionsByCategory.max { $0.value < $1.value }?.key
    }

    /// Clear session statistics (but keep learned preferences in Rust engine)
    public func clearSessionStats() {
        acceptedCount = 0
        rejectedCount = 0
        recentAcceptances.removeAll()
        recentRejections.removeAll()
    }
}

// MARK: - Record Types

/// Record of an accepted suggestion
public struct AcceptanceRecord: Identifiable {
    public let id = UUID()
    public let originalText: String
    public let suggestedText: String
    public let style: WritingStyle
    public let timestamp: Date

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

/// Record of a rejected suggestion
public struct RejectionRecord: Identifiable {
    public let id = UUID()
    public let originalText: String
    public let suggestedText: String
    public let style: WritingStyle
    public let category: SuggestionRejectionCategory
    public let timestamp: Date

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Vocabulary Sync

@available(macOS 10.15, *)
extension PreferenceLearner {

    /// Sync custom vocabulary from Harper dictionary to the LLM
    ///
    /// Call this after the user adds or removes custom words from their dictionary.
    /// The LLM will use these words in its prompt to avoid flagging them.
    ///
    /// - Parameter words: Array of custom dictionary words
    public func syncVocabulary(_ words: [String]) {
        LLMEngine.shared.syncVocabulary(words)
    }
}
