//
//  BrowserContentParser.swift
//  TextWarden
//
//  Content parser for web browsers (Chrome, Safari, Firefox, etc.)
//  Browsers have contenteditable areas with specific rendering characteristics
//

import Foundation
import AppKit

/// Content parser for web browsers
/// Handles Chrome, Safari, Firefox, Edge, and other browsers
class BrowserContentParser: ContentParser {
    let bundleIdentifier: String
    let parserName: String

    /// Supported browser bundle identifiers
    static let supportedBrowsers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.microsoft.edgemac",         // Edge
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.operasoftware.Opera"
    ]

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier

        if bundleIdentifier.contains("Chrome") {
            self.parserName = "Chrome"
        } else if bundleIdentifier.contains("Safari") {
            self.parserName = "Safari"
        } else if bundleIdentifier.contains("firefox") {
            self.parserName = "Firefox"
        } else if bundleIdentifier.contains("edgemac") {
            self.parserName = "Edge"
        } else if bundleIdentifier.contains("Opera") {
            self.parserName = "Opera"
        } else {
            self.parserName = "Browser"
        }
    }

    func detectUIContext(element: AXUIElement) -> String? {
        // Browsers mostly use contenteditable areas
        // Could differentiate between search bars vs text areas in the future
        return "contenteditable"
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Most browsers use 14-16px for contenteditable areas
        // Chrome/Safari default to 16px, Firefox to 14px
        switch bundleIdentifier {
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
            return 14.0
        case "com.apple.Safari":
            return 16.0
        case "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser":
            return 16.0
        default:
            return 15.0
        }
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // Browsers render text with standard spacing
        // No correction needed - use raw NSFont measurement
        return 1.0
    }

    func horizontalPadding(context: String?) -> CGFloat {
        // Browsers typically have minimal left padding in contenteditable areas
        // Some have a small indent for the caret
        switch bundleIdentifier {
        case "com.apple.Safari":
            // Safari has ~2px padding
            return 2.0
        case "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser":
            // Chrome has ~1px padding
            return 1.0
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
            // Firefox has ~2px padding
            return 2.0
        default:
            return 2.0
        }
    }

    /// Disable visual underlines for browsers (positioning is unreliable without DOM access)
    /// Browser positioning cannot account for zoom levels, custom CSS, or website-specific styling
    /// This causes underlines to appear in the wrong location
    /// Instead, show floating error indicator (same as terminals)
    var disablesVisualUnderlines: Bool {
        return true
    }
}
