//
//  AXCapabilityProfile.swift
//  TextWarden
//
//  Stores the results of probing an application's accessibility capabilities.
//  Used by StrategyRecommendationEngine to auto-detect optimal configurations.
//

import Foundation

// MARK: - Probe Result

/// Result of probing a single accessibility capability
enum ProbeResult: String, Codable, CaseIterable {
    case supported      // API works and returns valid values
    case unsupported    // API not available or returns error
    case invalid        // API works but returns invalid values (zeros, window frame)
    case unknown        // Could not be tested (no text element available)
}

// MARK: - Capability Profile

/// Complete profile of an application's accessibility capabilities.
/// Stored per bundle ID and used to auto-configure unknown applications.
struct AXCapabilityProfile: Codable {
    let bundleID: String
    let probedAt: Date
    let appVersion: String?

    // Positioning capabilities
    let boundsForRange: ProbeResult
    let boundsForTextMarkerRange: ProbeResult
    let lineForIndex: ProbeResult
    let rangeForLine: ProbeResult
    let textMarkerForIndex: ProbeResult

    // Bounds quality indicators
    let boundsReturnsValidWidth: Bool
    let boundsReturnsValidHeight: Bool
    let boundsNotWindowFrame: Bool

    // Text replacement capability
    let axValueSettable: Bool

    // MARK: - Derived Properties

    /// Recommended positioning strategies based on detected capabilities
    var recommendedStrategies: [StrategyType] {
        var strategies: [StrategyType] = []

        // Tier 1: Precise strategies (best quality)
        if boundsForTextMarkerRange == .supported && boundsNotWindowFrame {
            strategies.append(.textMarker)
        }

        if boundsForRange == .supported && boundsReturnsValidWidth && boundsReturnsValidHeight && boundsNotWindowFrame {
            strategies.append(.rangeBounds)
        }

        // Tier 2: Reliable strategies
        if lineForIndex == .supported && rangeForLine == .supported {
            strategies.append(.lineIndex)
        }

        // Anchor search works if range bounds work
        if boundsForRange == .supported {
            strategies.append(.anchorSearch)
        }

        // Tier 3: Fallback (always available)
        strategies.append(.fontMetrics)

        return strategies
    }

    /// Recommended text replacement method
    var textReplacementMethod: TextReplacementMethod {
        axValueSettable ? .standard : .browserStyle
    }

    /// Whether visual underlines should be enabled
    var visualUnderlinesEnabled: Bool {
        // Enable if at least one positioning strategy works (beyond just fontMetrics fallback)
        let strategies = recommendedStrategies
        return !strategies.isEmpty && strategies != [.fontMetrics]
    }

    /// Build AppFeatures from profile with sensible defaults for non-detectable properties
    var appFeatures: AppFeatures {
        AppFeatures(
            visualUnderlinesEnabled: visualUnderlinesEnabled,
            textReplacementMethod: textReplacementMethod,
            requiresTypingPause: false,
            supportsFormattedText: false,
            childElementTraversal: true,  // Safe default - enables element tree search
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true  // Conservative - safe for all apps
        )
    }

    /// Check if profile has expired (older than 7 days)
    var isExpired: Bool {
        let expirationDays = 7.0
        let expirationInterval = expirationDays * 24 * 60 * 60
        return Date().timeIntervalSince(probedAt) > expirationInterval
    }
}
