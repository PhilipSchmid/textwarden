//
//  ApplicationConfiguration.swift
//  TextWarden
//
//  Application-specific configuration for text replacement and rendering.
//  Uses AppRegistry as the source of truth for app categorization.
//

import AppKit
import Foundation

/// Provides app-specific configuration for text replacement and rendering
/// Uses AppRegistry for app categorization, adds timing-specific configuration
class ApplicationConfiguration {
    // MARK: - Keyboard Operation Timing

    /// Get recommended timing delay for keyboard operations (in seconds)
    /// Based on app category with app-specific overrides for known slow apps
    static func keyboardOperationDelay(for bundleIdentifier: String) -> TimeInterval {
        // App-specific overrides for known timing requirements
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            // Slack needs longer delays due to React rendering
            return 0.15
        case "com.hnc.Discord":
            // Discord is also React-based
            return 0.15
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
            // Firefox has known issues, use longer delay
            return 0.12
        default:
            break
        }

        // Use AppRegistry category for default timing
        let config = AppRegistry.shared.configuration(for: bundleIdentifier)
        switch config.category {
        case .electron:
            return 0.10
        case .browser:
            return 0.10
        case .native, .custom:
            return 0.05
        }
    }

    // MARK: - Font and Rendering

    /// Estimated font size for text measurement (heuristic-based)
    /// Delegates to AppRegistry configuration
    static func estimatedFontSize(for bundleIdentifier: String) -> CGFloat {
        let config = AppRegistry.shared.configuration(for: bundleIdentifier)
        return config.fontConfig.defaultSize
    }

    /// Character width correction factor (per character)
    /// Accounts for cumulative rendering differences between NSFont measurement
    /// and actual app rendering. Applied as: measuredWidth - (charCount * correction)
    static func characterWidthCorrection(for _: String) -> CGFloat {
        // Currently disabled for all apps - raw NSFont measurement is accurate enough
        0.0
    }

    // MARK: - Layout and Padding

    /// Horizontal padding inside text input elements
    /// Delegates to AppRegistry configuration
    static func estimatedLeftPadding(for bundleIdentifier: String) -> CGFloat {
        let config = AppRegistry.shared.configuration(for: bundleIdentifier)
        return config.horizontalPadding
    }

    // MARK: - Feature Support

    /// Check if this app supports format-preserving replacements
    /// Future feature: preserve bold/italic/links when replacing text
    static func supportsFormatPreservation(for bundleIdentifier: String) -> Bool {
        let config = AppRegistry.shared.configuration(for: bundleIdentifier)
        return config.features.supportsFormattedText
    }

    /// Check if this app requires keyboard-based text replacement
    /// Returns true for apps where AX API setValue is known to fail
    static func requiresKeyboardReplacement(for bundleIdentifier: String) -> Bool {
        let config = AppRegistry.shared.configuration(for: bundleIdentifier)
        return config.features.textReplacementMethod != .standard
    }
}
