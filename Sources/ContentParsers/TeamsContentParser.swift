//
//  TeamsContentParser.swift
//  TextWarden
//
//  Microsoft Teams-specific content parser.
//  Visual underlines are disabled due to broken WebView2 accessibility APIs.
//  Text analysis and the floating error indicator still work normally.
//

import Foundation
import AppKit

/// Microsoft Teams-specific content parser
/// Visual underlines are disabled because Teams' WebView2 accessibility APIs
/// don't provide accurate character positioning (AXBoundsForRange returns garbage).
/// Text analysis and corrections via the floating indicator work normally.
class TeamsContentParser: ContentParser {
    let bundleIdentifier = "com.microsoft.teams2"
    let parserName = "Teams"

    /// Cached configuration from AppRegistry
    private var config: AppConfiguration {
        AppRegistry.shared.configuration(for: bundleIdentifier)
    }

    /// Visual underlines disabled for Teams (WebView2 AX APIs broken)
    var disablesVisualUnderlines: Bool {
        return !config.features.visualUnderlinesEnabled
    }

    /// UI contexts within Teams
    private enum TeamsContext: String {
        case messageInput = "message-input"
        case searchBar = "search-bar"
        case unknown = "unknown"
    }

    func detectUIContext(element: AXUIElement) -> String? {
        var descValue: CFTypeRef?
        var identifierValue: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)

        let description = descValue as? String
        let identifier = identifierValue as? String

        if let desc = description?.lowercased() {
            if desc.contains("search") {
                return TeamsContext.searchBar.rawValue
            } else if desc.contains("message") || desc.contains("compose") || desc.contains("chat") {
                return TeamsContext.messageInput.rawValue
            }
        }

        if let id = identifier?.lowercased() {
            if id.contains("search") {
                return TeamsContext.searchBar.rawValue
            } else if id.contains("composer") || id.contains("message") || id.contains("chat") {
                return TeamsContext.messageInput.rawValue
            }
        }

        return TeamsContext.messageInput.rawValue
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        return config.fontConfig.defaultSize
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        return config.fontConfig.spacingMultiplier
    }

    func horizontalPadding(context: String?) -> CGFloat {
        return config.horizontalPadding
    }

    /// Position resolution - returns unavailable since visual underlines are disabled
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String,
        actualBundleID: String?
    ) -> GeometryResult {
        // Visual underlines are disabled for Teams due to broken WebView2 AX APIs
        return GeometryResult.unavailable(reason: "Visual underlines disabled for Teams (WebView2 AX APIs broken)")
    }

    /// Bounds adjustment - returns nil since visual underlines are disabled
    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        // Visual underlines are disabled for Teams
        return nil
    }
}
