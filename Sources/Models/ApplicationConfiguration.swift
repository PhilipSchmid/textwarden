//
//  ApplicationConfiguration.swift
//  Gnau
//
//  Application-specific configuration (timing, fonts, layout)
//  Separated from ApplicationContext to follow Single Responsibility Principle
//

import Foundation
import AppKit

/// Provides app-specific configuration for text replacement and rendering
/// This class handles all tunable parameters that vary by application
class ApplicationConfiguration {

    // MARK: - Keyboard Operation Timing

    /// Get recommended timing delay for keyboard operations (in seconds)
    /// Based on (redacted)'s "fast_batching_selection_wait" approach
    static func keyboardOperationDelay(for bundleIdentifier: String) -> TimeInterval {
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            // Slack needs longer delays due to React rendering
            return 0.15
        case "com.hnc.Discord":
            // Discord is also React-based
            return 0.15
        case "com.microsoft.VSCode":
            // VS Code is faster
            return 0.08
        case "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser":
            // Chromium browsers need moderate delays for contenteditable areas
            return 0.10
        case "com.apple.Safari":
            // Safari is generally faster
            return 0.08
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
            // Firefox has known issues, use longer delay
            return 0.12
        default:
            // Default delay based on app type
            if isElectronApp(bundleIdentifier) {
                return 0.1
            } else if isBrowser(bundleIdentifier) {
                return 0.10
            }
            return 0.05
        }
    }

    // MARK: - Font and Rendering

    /// Estimated font size for text measurement (heuristic-based)
    /// Used when AX API bounds are unavailable or implausible
    static func estimatedFontSize(for bundleIdentifier: String) -> CGFloat {
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            return 15.0
        case "com.hnc.Discord":
            return 15.0
        case "com.microsoft.VSCode":
            return 14.0
        default:
            return isElectronApp(bundleIdentifier) ? 15.0 : 13.0
        }
    }

    /// Character width correction factor (per character)
    /// Accounts for cumulative rendering differences between NSFont measurement
    /// and actual app rendering. Applied as: measuredWidth - (charCount * correction)
    static func characterWidthCorrection(for bundleIdentifier: String) -> CGFloat {
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            // Disable correction - use raw NSFont measurement
            // Font measurement appears more accurate than expected
            return 0.0
        case "com.hnc.Discord":
            return 0.0
        default:
            return 0.0
        }
    }

    // MARK: - Layout and Padding

    /// Horizontal padding inside text input elements
    /// Used for estimation when AX API fails
    static func estimatedLeftPadding(for bundleIdentifier: String) -> CGFloat {
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            // Slack's message input has approximately 12px left padding
            return 12.0
        case "com.hnc.Discord":
            return 12.0
        case "com.microsoft.VSCode":
            return 10.0
        default:
            return isElectronApp(bundleIdentifier) ? 12.0 : 8.0
        }
    }

    // MARK: - Feature Support

    /// Check if this app supports format-preserving replacements
    /// Future feature: preserve bold/italic/links when replacing text
    static func supportsFormatPreservation(for bundleIdentifier: String) -> Bool {
        // For now, only native macOS apps support this
        return !isElectronApp(bundleIdentifier) && !isChromiumBased(bundleIdentifier)
    }

    // MARK: - Private Helpers

    /// Check if bundle identifier is an Electron app
    private static func isElectronApp(_ bundleIdentifier: String) -> Bool {
        let electronApps: Set<String> = [
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "com.microsoft.VSCode",
            "com.electron.app",
            "com.github.GitHubClient",
            "com.microsoft.teams",
            "com.notion.desktop"
        ]
        return electronApps.contains(bundleIdentifier) || bundleIdentifier.contains("electron")
    }

    /// Check if bundle identifier is a Chromium-based browser
    private static func isChromiumBased(_ bundleIdentifier: String) -> Bool {
        let chromiumApps: Set<String> = [
            "com.google.Chrome",
            "com.google.Chrome.beta",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "org.chromium.Chromium"
        ]
        return chromiumApps.contains(bundleIdentifier) || bundleIdentifier.contains("chromium")
    }

    /// Check if bundle identifier is a browser (Chromium or otherwise)
    private static func isBrowser(_ bundleIdentifier: String) -> Bool {
        let browserApps: Set<String> = [
            "com.apple.Safari",
            "org.mozilla.firefox",
            "org.mozilla.firefoxdeveloperedition",
            "com.operasoftware.Opera"
        ]
        return isChromiumBased(bundleIdentifier) || browserApps.contains(bundleIdentifier)
    }
}
