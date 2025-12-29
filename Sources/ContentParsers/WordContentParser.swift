//
//  WordContentParser.swift
//  TextWarden
//
//  Content parser for Microsoft Word
//  Filters out toolbar/ribbon elements and focuses only on the document body
//

import Foundation
import AppKit

/// Content parser for Microsoft Word
/// Focuses only on the document text area, ignoring toolbar/ribbon elements
class WordContentParser: ContentParser {
    let bundleIdentifier: String = "com.microsoft.Word"
    let parserName: String = "Microsoft Word"

    func detectUIContext(element: AXUIElement) -> String? {
        if WordContentParser.isDocumentElement(element) {
            return "document"
        }
        return nil
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Word default is typically 11-12pt
        return 12.0
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        return 1.0
    }

    func horizontalPadding(context: String?) -> CGFloat {
        return 4.0
    }

    /// Custom text extraction for Microsoft Word
    /// The element to monitor has already been validated by isDocumentElement during element selection
    /// This method extracts text from the monitored document element
    func extractText(from element: AXUIElement) -> String? {
        // Get element role for logging
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "unknown"

        Logger.debug("WordContentParser: extractText called for element with role: \(role)", category: Logger.accessibility)

        // Use AXValue to get the document text
        // Note: AXValue is preferred for simple text extraction as it's faster than AXStringForRange.
        // AXBoundsForRange and AXStringForRange work reliably on Word 16.104+ (tested Dec 2024).
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String,
           !text.isEmpty {
            Logger.debug("WordContentParser: extractText - got AXValue (\(text.count) chars)", category: Logger.accessibility)
            return text
        }

        Logger.debug("WordContentParser: extractText - no text found via AXValue", category: Logger.accessibility)
        return nil
    }

    // MARK: - Element Filtering

    /// Check if an element is the Word document content area (not toolbar/ribbon)
    static func isDocumentElement(_ element: AXUIElement) -> Bool {
        // Get element properties
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String ?? ""

        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        let description = (descRef as? String)?.lowercased() ?? ""

        var identifierRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef)
        let identifier = (identifierRef as? String)?.lowercased() ?? ""

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String)?.lowercased() ?? ""

        // Also get AXValue to check its content
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let value = valueRef as? String ?? ""

        Logger.debug("WordContentParser: Checking element - role: \(role), subrole: \(subrole), hasDesc: \(!description.isEmpty), hasId: \(!identifier.isEmpty), hasTitle: \(!title.isEmpty), valueLen: \(value.count)", category: Logger.accessibility)

        // EXCLUDE: Toolbar elements (ribbon controls)
        if isToolbarElement(role: role, subrole: subrole, description: description, identifier: identifier, title: title, value: value) {
            Logger.debug("WordContentParser: Rejecting - toolbar/ribbon element", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Font name/style dropdowns (the "Aptos (Body)" problem)
        if isFontElement(description: description, identifier: identifier, title: title, value: value) {
            Logger.debug("WordContentParser: Rejecting - font selector element", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Menu items and popups
        if role == "AXMenuItem" || role == "AXMenu" || role == "AXPopUpButton" {
            Logger.debug("WordContentParser: Rejecting - menu element", category: Logger.accessibility)
            return false
        }

        // Check parent hierarchy for toolbar/ribbon ancestors
        if hasToolbarAncestor(element) {
            Logger.debug("WordContentParser: Rejecting - has toolbar ancestor", category: Logger.accessibility)
            return false
        }

        // ACCEPT: Text areas (document body)
        if role == kAXTextAreaRole as String {
            Logger.debug("WordContentParser: Accepting - AXTextArea (document body)", category: Logger.accessibility)
            return true
        }

        // ACCEPT: Scroll areas that contain text (Word document view)
        if role == "AXScrollArea" {
            // Check if it has text content (not just a scroll container)
            var charCountRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &charCountRef) == .success,
               let charCount = charCountRef as? Int,
               charCount > 0 {
                Logger.debug("WordContentParser: Accepting - AXScrollArea with \(charCount) characters", category: Logger.accessibility)
                return true
            }
        }

        // ACCEPT: Generic text fields that are NOT in toolbar and have substantial content
        if role == kAXTextFieldRole as String {
            // Single-line text fields in the document area (like search/replace in doc)
            // But NOT the font dropdown (already filtered above)
            let valueLength = value.count
            if valueLength > 50 {
                // Likely document content, not a toolbar control
                Logger.debug("WordContentParser: Accepting - AXTextField with substantial content (\(valueLength) chars)", category: Logger.accessibility)
                return true
            }
        }

        Logger.debug("WordContentParser: Rejecting - role '\(role)' not recognized as document content", category: Logger.accessibility)
        return false
    }

    /// Check if the element appears to be a toolbar/ribbon control
    private static func isToolbarElement(role: String, subrole: String, description: String, identifier: String, title: String, value: String) -> Bool {
        // Toolbar-related roles
        let toolbarRoles = ["AXToolbar", "AXGroup", "AXButton", "AXCheckBox", "AXRadioButton"]
        if toolbarRoles.contains(role) && !role.contains("Text") {
            return true
        }

        // Toolbar-related keywords in description/identifier
        let toolbarKeywords = ["toolbar", "ribbon", "format", "home", "insert", "layout", "view", "review", "references"]
        for keyword in toolbarKeywords {
            if description.contains(keyword) || identifier.contains(keyword) || title.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Check if the element is a font selector
    private static func isFontElement(description: String, identifier: String, title: String, value: String) -> Bool {
        // Font-related keywords
        let fontKeywords = ["font", "typeface", "aptos", "calibri", "arial", "times", "helvetica", "style", "body"]
        for keyword in fontKeywords {
            if description.contains(keyword) || identifier.contains(keyword) {
                return true
            }
        }

        // Check if value looks like a font name (parenthesized suffix like "Aptos (Body)")
        if value.contains("(") && value.contains(")") && value.count < 50 {
            // Likely a font name like "Aptos (Body)" or "Calibri (Body)"
            let fontNamePattern = #"^[A-Za-z\s]+ \([A-Za-z]+\)$"#
            if value.range(of: fontNamePattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    /// Check if element has a toolbar ancestor in its parent hierarchy
    private static func hasToolbarAncestor(_ element: AXUIElement, maxDepth: Int = 10) -> Bool {
        var currentElement: AXUIElement? = element
        var depth = 0

        while let current = currentElement, depth < maxDepth {
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef,
               CFGetTypeID(parent) == AXUIElementGetTypeID() {
                // Safe: type verified by CFGetTypeID check above
                let parentElement = unsafeBitCast(parent, to: AXUIElement.self)

                // Check parent's role
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(parentElement, kAXRoleAttribute as CFString, &roleRef)
                let role = roleRef as? String ?? ""

                // Check parent's identifier
                var identifierRef: CFTypeRef?
                AXUIElementCopyAttributeValue(parentElement, kAXIdentifierAttribute as CFString, &identifierRef)
                let identifier = (identifierRef as? String)?.lowercased() ?? ""

                // Check for toolbar/ribbon indicators
                if role == "AXToolbar" || identifier.contains("toolbar") || identifier.contains("ribbon") {
                    return true
                }

                currentElement = parentElement
                depth += 1
            } else {
                break
            }
        }

        return false
    }

    // MARK: - Find Document Element

    /// Search for the actual document text area starting from an element
    /// Used when the focused element is a toolbar control
    static func findDocumentElement(from element: AXUIElement) -> AXUIElement? {
        // First, get the application element
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXTopLevelUIElement" as CFString, &appRef) == .success ||
              AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &appRef) == .success,
              let app = appRef,
              CFGetTypeID(app) == AXUIElementGetTypeID() else {
            return nil
        }
        // Safe: type verified by CFGetTypeID check above
        var current = unsafeBitCast(app, to: AXUIElement.self)

        // Walk up to find the window
        var windowElement: AXUIElement?
        for _ in 0..<20 {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            if role == "AXWindow" {
                windowElement = current
                break
            }

            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef,
               CFGetTypeID(parent) == AXUIElementGetTypeID() {
                // Safe: type verified by CFGetTypeID check above
                current = unsafeBitCast(parent, to: AXUIElement.self)
            } else {
                break
            }
        }

        guard let window = windowElement else {
            Logger.debug("WordContentParser: Could not find window element", category: Logger.accessibility)
            return nil
        }

        // Search window's descendants for a text area
        return findTextAreaInHierarchy(window, maxDepth: 15)
    }

    /// Recursively search for a text area element
    private static func findTextAreaInHierarchy(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 15) -> AXUIElement? {
        if depth > maxDepth { return nil }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Found a text area - check if it's the document
        if role == kAXTextAreaRole as String {
            // Verify it's not in a toolbar
            if !hasToolbarAncestor(element) {
                Logger.debug("WordContentParser: Found document text area at depth \(depth)", category: Logger.accessibility)
                return element
            }
        }

        // Check children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let found = findTextAreaInHierarchy(child, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }

        return nil
    }
}
