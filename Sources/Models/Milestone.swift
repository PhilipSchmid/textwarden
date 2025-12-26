//
//  Milestone.swift
//  TextWarden
//
//  Milestone definitions for donation prompts
//

import Foundation
import Combine

/// Types of milestones that can be reached
enum MilestoneType: String, Codable, CaseIterable {
    case activeDays = "active_days"
    case appliedFixes = "applied_fixes"
    case styleSuggestions = "style_suggestions"

    var emoji: String {
        switch self {
        case .activeDays: return "📅"
        case .appliedFixes: return "✨"
        case .styleSuggestions: return "🎨"
        }
    }

    var label: String {
        switch self {
        case .activeDays: return "Active Days"
        case .appliedFixes: return "Fixes Applied"
        case .styleSuggestions: return "Style Improvements"
        }
    }

    var thresholds: [Int] {
        switch self {
        case .activeDays: return [30, 90, 365]
        case .appliedFixes: return [100, 500, 1000]
        case .styleSuggestions: return [50, 200]
        }
    }
}

/// A specific milestone that can be achieved
struct Milestone: Codable, Hashable, Identifiable {
    let type: MilestoneType
    let threshold: Int

    var id: String {
        "\(type.rawValue)_\(threshold)"
    }

    var emoji: String {
        type.emoji
    }

    var celebrationEmoji: String {
        switch threshold {
        case 1...10: return "🎉"
        case 11...50: return "🏆"
        case 51...100: return "⭐"
        case 101...500: return "🌟"
        default: return "🚀"
        }
    }

    /// User-friendly message for this milestone
    var message: String {
        switch type {
        case .activeDays:
            switch threshold {
            case 30: return "A full month of polished prose!"
            case 90: return "Three months of writing excellence!"
            case 365: return "A whole year of flawless writing!"
            default: return "\(threshold) days of great writing!"
            }
        case .appliedFixes:
            switch threshold {
            case 100: return "100 errors fixed!"
            case 500: return "500 corrections made!"
            case 1000: return "1,000 improvements applied!"
            default: return "\(threshold) fixes applied!"
            }
        case .styleSuggestions:
            switch threshold {
            case 50: return "50 clearer sentences!"
            case 200: return "200 polished phrases!"
            default: return "\(threshold) style enhancements!"
            }
        }
    }

    /// Headline for the celebration card
    var headline: String {
        switch threshold {
        case 1...25: return "Great Start!"
        case 26...100: return "Impressive Progress!"
        case 101...500: return "Amazing Achievement!"
        default: return "Legendary Milestone!"
        }
    }
}

/// Manages milestone detection and tracking
@MainActor
class MilestoneManager: ObservableObject {
    static let shared = MilestoneManager(preferences: .shared, statistics: .shared)

    private let preferences: UserPreferences
    private let statistics: UserStatistics

    @Published var pendingMilestone: Milestone?

    private init(preferences: UserPreferences, statistics: UserStatistics) {
        self.preferences = preferences
        self.statistics = statistics
    }

    /// Check for any milestones that should be shown
    /// Returns the highest priority unshown milestone, if any
    func checkForMilestones() -> Milestone? {
        // Don't show if user has permanently disabled milestones
        guard !preferences.milestonesDisabled else {
            return nil
        }

        var highestMilestone: Milestone?

        for type in MilestoneType.allCases {
            let currentValue = currentValue(for: type)
            let shownMilestones = preferences.shownMilestones

            for threshold in type.thresholds {
                if currentValue >= threshold {
                    let milestone = Milestone(type: type, threshold: threshold)
                    if !shownMilestones.contains(milestone.id) {
                        // Prefer higher thresholds and more impressive milestones
                        if highestMilestone == nil || threshold > highestMilestone!.threshold {
                            highestMilestone = milestone
                        }
                    }
                }
            }
        }

        pendingMilestone = highestMilestone
        return highestMilestone
    }

    /// Create a sample milestone for troubleshooting/preview purposes
    /// Returns a milestone that can be shown regardless of actual user statistics
    func createPreviewMilestone() -> Milestone {
        // Use the first threshold of applied fixes as a representative milestone
        return Milestone(type: .appliedFixes, threshold: 100)
    }

    /// Get current value for a milestone type
    private func currentValue(for type: MilestoneType) -> Int {
        switch type {
        case .activeDays:
            return statistics.activeDays.count
        case .appliedFixes:
            return statistics.suggestionsApplied
        case .styleSuggestions:
            return statistics.styleSuggestionsAccepted
        }
    }

    /// Mark a milestone as shown (won't be shown again)
    func markMilestoneShown(_ milestone: Milestone) {
        preferences.shownMilestones.insert(milestone.id)
        if pendingMilestone?.id == milestone.id {
            pendingMilestone = nil
        }
        Logger.info("Milestone marked as shown: \(milestone.id)", category: Logger.general)
    }

    /// Clear pending milestone without marking as shown (user dismissed)
    func dismissPendingMilestone() {
        if let milestone = pendingMilestone {
            markMilestoneShown(milestone)
        }
    }

    /// Permanently disable all milestone prompts
    func disableMilestonesForever() {
        preferences.milestonesDisabled = true
        pendingMilestone = nil
        Logger.info("Milestones permanently disabled by user", category: Logger.general)
    }
}
