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

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier

        // Derive parser name from bundle ID for display purposes
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
        } else if bundleIdentifier.contains("thebrowser") {
            self.parserName = "Arc"
        } else if bundleIdentifier.contains("Brave") {
            self.parserName = "Brave"
        } else if bundleIdentifier.contains("comet") || bundleIdentifier.contains("perplexity") {
            self.parserName = "Comet"
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
        return 15.0
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // Browsers render text with standard spacing
        return 1.0
    }

    func horizontalPadding(context: String?) -> CGFloat {
        // Browsers typically have minimal left padding in contenteditable areas
        return 2.0
    }

    /// Disable visual underlines for browsers
    /// Browser positioning cannot account for zoom levels, custom CSS, or website-specific styling
    var disablesVisualUnderlines: Bool {
        return true
    }

    /// Check if an element is a browser UI element (not web content)
    /// Returns true for search fields, URL bars, find-in-page, etc.
    /// These should be skipped as they're not meaningful for grammar checking
    static func isBrowserUIElement(_ element: AXUIElement) -> Bool {
        // Get element role
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? ""

        // Get element description
        var descriptionValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionValue)
        let description = (descriptionValue as? String)?.lowercased() ?? ""

        // Get element title
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String)?.lowercased() ?? ""

        // Get element identifier
        var identifierValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)
        let identifier = (identifierValue as? String)?.lowercased() ?? ""

        // Get subrole
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        let subrole = (subroleValue as? String) ?? ""

        // Get placeholder text (often reveals search fields)
        var placeholderValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPlaceholderValueAttribute as CFString, &placeholderValue)
        let placeholder = (placeholderValue as? String)?.lowercased() ?? ""

        // Get role description (e.g., "search text field", "text field")
        var roleDescValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescValue)
        let roleDesc = (roleDescValue as? String)?.lowercased() ?? ""

        // Get element value to check for URL patterns (helps detect address bars)
        var elementValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &elementValue)
        let value = (elementValue as? String) ?? ""

        // Log attributes for debugging browser UI element detection
        Logger.debug("BrowserContentParser: Checking element - role: \(role), subrole: \(subrole), desc: '\(description.prefix(30))', title: '\(title.prefix(30))', id: '\(identifier.prefix(30))', placeholder: '\(placeholder.prefix(30))', roleDesc: '\(roleDesc)'", category: Logger.accessibility)

        // Keywords that indicate browser UI elements (not web content)
        let browserUIKeywords = [
            "find in page",
            "find on page",
            "find",              // Common label for find-in-page dialogs
            "search",
            "address",
            "url",
            "location",
            "omnibox",
            "unified field",
            "navigation",
            "bookmark",
            "tab"
        ]

        // Check if any attribute contains browser UI keywords
        let allText = "\(description) \(title) \(identifier) \(placeholder) \(roleDesc)"
        for keyword in browserUIKeywords {
            if allText.contains(keyword) {
                Logger.info("BrowserContentParser: Skipping browser UI element (matched '\(keyword)')", category: Logger.accessibility)
                return true
            }
        }

        // AXSearchField subrole is a clear indicator of a search field
        if subrole == "AXSearchField" {
            Logger.info("BrowserContentParser: Skipping AXSearchField subrole", category: Logger.accessibility)
            return true
        }

        // Check if the value looks like a URL (address bar detection)
        // This catches address bars that don't have identifying attributes
        if looksLikeURL(value) {
            Logger.info("BrowserContentParser: Skipping element with URL-like content", category: Logger.accessibility)
            return true
        }

        // Check parent chain for browser chrome indicators (up to 5 levels)
        // Find-in-page dialogs are often in sheets, popovers, or panels
        var currentElement: AXUIElement? = element
        for depth in 0..<5 {
            var parentRef: CFTypeRef?
            guard let current = currentElement,
                  AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                break
            }

            let parentElement = parent as! AXUIElement

            // Check parent role
            var parentRole: CFTypeRef?
            AXUIElementCopyAttributeValue(parentElement, kAXRoleAttribute as CFString, &parentRole)
            let parentRoleStr = (parentRole as? String) ?? ""

            // Browser UI container roles
            let browserUIRoles = ["AXToolbar", "AXSheet", "AXPopover", "AXDialog"]
            if browserUIRoles.contains(parentRoleStr) {
                Logger.debug("BrowserContentParser: Skipping element in \(parentRoleStr) (depth: \(depth))", category: Logger.accessibility)
                return true
            }

            // Check parent's title/description for find-related keywords
            var parentTitle: CFTypeRef?
            AXUIElementCopyAttributeValue(parentElement, kAXTitleAttribute as CFString, &parentTitle)
            let parentTitleStr = (parentTitle as? String)?.lowercased() ?? ""

            var parentDesc: CFTypeRef?
            AXUIElementCopyAttributeValue(parentElement, kAXDescriptionAttribute as CFString, &parentDesc)
            let parentDescStr = (parentDesc as? String)?.lowercased() ?? ""

            let parentText = "\(parentTitleStr) \(parentDescStr)"
            if parentText.contains("find") || parentText.contains("search") {
                Logger.debug("BrowserContentParser: Skipping element - parent contains find/search (depth: \(depth), text: '\(parentText.prefix(50))')", category: Logger.accessibility)
                return true
            }

            currentElement = parentElement
        }

        return false
    }

    /// Check if a string looks like a URL (for detecting address bar content)
    /// Uses pattern matching rather than URL parsing to catch partial URLs
    private static func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty or very short strings are not URLs
        guard trimmed.count >= 4 else { return false }

        // Check for common URL schemes
        let urlSchemes = ["http://", "https://", "file://", "ftp://", "about:", "chrome://", "edge://"]
        for scheme in urlSchemes {
            if trimmed.lowercased().hasPrefix(scheme) {
                return true
            }
        }

        // Check for domain-like patterns (e.g., "github.com/path", "www.example.com")
        // Look for: word.tld or word.tld/path patterns
        let domainPattern = #"^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}(/|$)"#
        if let regex = try? NSRegularExpression(pattern: domainPattern),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }

        // Check for www. prefix
        if trimmed.lowercased().hasPrefix("www.") {
            return true
        }

        // Check for localhost patterns
        if trimmed.lowercased().hasPrefix("localhost") {
            return true
        }

        return false
    }
}
