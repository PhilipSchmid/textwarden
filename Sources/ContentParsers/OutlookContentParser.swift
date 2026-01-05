//
//  OutlookContentParser.swift
//  TextWarden
//
//  Content parser for Microsoft Outlook
//  Handles both subject field and compose body, filtering out toolbar/ribbon elements
//

import AppKit
import Foundation

/// Content parser for Microsoft Outlook
/// Focuses on the compose window (subject and body), ignoring toolbar/ribbon elements
class OutlookContentParser: ContentParser {
    let bundleIdentifier: String = "com.microsoft.Outlook"
    let parserName: String = "Microsoft Outlook"

    /// Configuration from AppRegistry
    private var config: AppConfiguration {
        AppRegistry.shared.configuration(for: bundleIdentifier)
    }

    func detectUIContext(element: AXUIElement) -> String? {
        if OutlookContentParser.isComposeElement(element) {
            return "compose"
        }
        return nil
    }

    func estimatedFontSize(context _: String?) -> CGFloat {
        config.fontConfig.defaultSize
    }

    func spacingMultiplier(context _: String?) -> CGFloat {
        config.fontConfig.spacingMultiplier
    }

    func horizontalPadding(context _: String?) -> CGFloat {
        config.horizontalPadding
    }

    func fontFamily(context _: String?) -> String? {
        config.fontConfig.fontFamily
    }

    /// Custom text extraction for Microsoft Outlook
    /// Avoids parameterized AX queries that crash mso99 framework
    /// Strips quoted content from reply/forward emails to only analyze user's new text
    func extractText(from element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "unknown"

        Logger.debug("OutlookContentParser: extractText called for element with role: \(role)", category: Logger.accessibility)

        // Use AXValue to get text - avoid AXStringForRange (crashes mso99)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String,
           !text.isEmpty
        {
            Logger.debug("OutlookContentParser: extractText - got AXValue (\(text.count) chars)", category: Logger.accessibility)

            // Strip quoted content from reply/forward emails
            // Only analyze the user's new text, not quoted previous messages
            let strippedText = MailContentParser.stripQuotedContent(from: text)
            if strippedText.count != text.count {
                Logger.debug("OutlookContentParser: Stripped quoted content (\(text.count) -> \(strippedText.count) chars)", category: Logger.accessibility)
            }
            return strippedText
        }

        Logger.debug("OutlookContentParser: extractText - no text found via AXValue", category: Logger.accessibility)
        return nil
    }

    // MARK: - Element Filtering

    /// Check if an element is a valid Outlook compose element (subject or body)
    static func isComposeElement(_ element: AXUIElement) -> Bool {
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

        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let value = valueRef as? String ?? ""

        Logger.debug("OutlookContentParser: Checking element - role: \(role), subrole: \(subrole), desc: \(description), id: \(identifier), title: \(title), valueLen: \(value.count)", category: Logger.accessibility)

        // EXCLUDE: Toolbar/ribbon elements
        if isToolbarElement(role: role, subrole: subrole, description: description, identifier: identifier, title: title, value: value) {
            Logger.debug("OutlookContentParser: Rejecting - toolbar/ribbon element", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Font selectors (like "Aptos (Body)")
        if isFontElement(description: description, identifier: identifier, title: title, value: value) {
            Logger.debug("OutlookContentParser: Rejecting - font selector element", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Menu items and popups
        if role == "AXMenuItem" || role == "AXMenu" || role == "AXPopUpButton" {
            Logger.debug("OutlookContentParser: Rejecting - menu element", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Address fields (To, Cc, Bcc)
        if isAddressField(description: description, identifier: identifier, title: title) {
            Logger.debug("OutlookContentParser: Rejecting - address field", category: Logger.accessibility)
            return false
        }

        // Check parent hierarchy for toolbar/ribbon ancestors
        if hasToolbarAncestor(element) {
            Logger.debug("OutlookContentParser: Rejecting - has toolbar ancestor", category: Logger.accessibility)
            return false
        }

        // ACCEPT: Text areas (compose body)
        if role == kAXTextAreaRole as String {
            Logger.debug("OutlookContentParser: Accepting - AXTextArea (compose body)", category: Logger.accessibility)
            return true
        }

        // ACCEPT: Text fields that appear to be subject line
        if role == kAXTextFieldRole as String {
            // Subject field typically has "subject" in description/identifier or has meaningful content
            if description.contains("subject") || identifier.contains("subject") || title.contains("subject") {
                Logger.debug("OutlookContentParser: Accepting - AXTextField (subject field)", category: Logger.accessibility)
                return true
            }
            // Also accept text fields with substantial content that aren't address fields
            if value.count > 3, !isAddressLikeContent(value) {
                Logger.debug("OutlookContentParser: Accepting - AXTextField with content (\(value.count) chars)", category: Logger.accessibility)
                return true
            }
        }

        // ACCEPT: Scroll areas with text content (alternative compose view)
        if role == "AXScrollArea" {
            var charCountRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &charCountRef) == .success,
               let charCount = charCountRef as? Int,
               charCount > 0
            {
                Logger.debug("OutlookContentParser: Accepting - AXScrollArea with \(charCount) characters", category: Logger.accessibility)
                return true
            }
        }

        Logger.debug("OutlookContentParser: Rejecting - role '\(role)' not recognized as compose content", category: Logger.accessibility)
        return false
    }

    /// Check if the element appears to be a toolbar/ribbon control
    private static func isToolbarElement(role: String, subrole _: String, description: String, identifier: String, title: String, value _: String) -> Bool {
        // AXTextArea is always a text editing area, never a toolbar control
        // (even if description/title contains keywords like "message copilot")
        if role == kAXTextAreaRole as String {
            return false
        }

        let toolbarRoles = ["AXToolbar", "AXGroup", "AXButton", "AXCheckBox", "AXRadioButton"]
        if toolbarRoles.contains(role), !role.contains("Text") {
            return true
        }

        let toolbarKeywords = ["toolbar", "ribbon", "format", "home", "insert", "view", "message", "options", "help"]
        for keyword in toolbarKeywords {
            if description.contains(keyword) || identifier.contains(keyword) || title.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Check if the element is a font selector
    private static func isFontElement(description: String, identifier: String, title _: String, value: String) -> Bool {
        let fontKeywords = ["font", "typeface", "aptos", "calibri", "arial", "times", "helvetica", "style", "body"]
        for keyword in fontKeywords {
            if description.contains(keyword) || identifier.contains(keyword) {
                return true
            }
        }

        // Check for font name pattern like "Aptos (Body)"
        if value.contains("("), value.contains(")"), value.count < 50 {
            let fontNamePattern = #"^[A-Za-z\s]+ \([A-Za-z]+\)$"#
            if value.range(of: fontNamePattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    /// Check if the element is an address field (To, Cc, Bcc)
    private static func isAddressField(description: String, identifier: String, title: String) -> Bool {
        let addressKeywords = ["to:", "cc:", "bcc:", "from:", "recipient"]
        for keyword in addressKeywords {
            if description.contains(keyword) || identifier.contains(keyword) || title.contains(keyword) {
                return true
            }
        }
        return false
    }

    /// Check if the value looks like an email address or address list
    private static func isAddressLikeContent(_ value: String) -> Bool {
        // Simple heuristic: contains @ and looks like email
        value.contains("@") && value.contains(".")
    }

    /// Check if element has a toolbar ancestor in its parent hierarchy
    private static func hasToolbarAncestor(_ element: AXUIElement, maxDepth: Int = 10) -> Bool {
        var currentElement: AXUIElement? = element
        var depth = 0

        while let current = currentElement, depth < maxDepth {
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef,
               CFGetTypeID(parent) == AXUIElementGetTypeID()
            {
                let parentElement = unsafeBitCast(parent, to: AXUIElement.self)

                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(parentElement, kAXRoleAttribute as CFString, &roleRef)
                let role = roleRef as? String ?? ""

                var identifierRef: CFTypeRef?
                AXUIElementCopyAttributeValue(parentElement, kAXIdentifierAttribute as CFString, &identifierRef)
                let identifier = (identifierRef as? String)?.lowercased() ?? ""

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

    // MARK: - Find Compose Element

    /// Search for the compose body element starting from the focused element
    /// Used when Outlook focuses on AXStaticText instead of the actual editable area
    static func findComposeElement(from element: AXUIElement) -> AXUIElement? {
        Logger.debug("OutlookContentParser: Searching for compose element from focused element...", category: Logger.accessibility)

        // Strategy 1: Search siblings of the focused element
        // Outlook often focuses on static text that's adjacent to the editable area
        if let sibling = findEditableSibling(of: element) {
            Logger.debug("OutlookContentParser: Found editable sibling!", category: Logger.accessibility)
            return sibling
        }

        // Strategy 2: Search parent's children (go up one level and search down)
        var parentRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
           let parent = parentRef,
           CFGetTypeID(parent) == AXUIElementGetTypeID()
        {
            let parentElement = unsafeBitCast(parent, to: AXUIElement.self)

            if let editableInParent = findTextAreaInHierarchy(parentElement, maxDepth: 5) {
                Logger.debug("OutlookContentParser: Found editable element in parent hierarchy!", category: Logger.accessibility)
                return editableInParent
            }
        }

        // Strategy 3: Walk up to the window and search down
        if let windowElement = findWindowAncestor(element) {
            if let editableInWindow = findTextAreaInHierarchy(windowElement, maxDepth: 15) {
                Logger.debug("OutlookContentParser: Found editable element in window hierarchy!", category: Logger.accessibility)
                return editableInWindow
            }
        }

        Logger.debug("OutlookContentParser: Could not find compose element", category: Logger.accessibility)
        return nil
    }

    /// Find an editable sibling of the given element
    private static func findEditableSibling(of element: AXUIElement) -> AXUIElement? {
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
              let parent = parentRef,
              CFGetTypeID(parent) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let parentElement = unsafeBitCast(parent, to: AXUIElement.self)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parentElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            // Look for text area or text field siblings
            if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
                // Verify it's a compose element, not a toolbar element
                if isComposeElement(child) {
                    return child
                }
            }
        }

        return nil
    }

    /// Find the window ancestor of an element
    private static func findWindowAncestor(_ element: AXUIElement) -> AXUIElement? {
        var current = element

        for _ in 0 ..< 20 {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            if role == "AXWindow" {
                return current
            }

            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef,
               CFGetTypeID(parent) == AXUIElementGetTypeID()
            {
                current = unsafeBitCast(parent, to: AXUIElement.self)
            } else {
                break
            }
        }

        return nil
    }

    /// Recursively search for a text area element in hierarchy
    private static func findTextAreaInHierarchy(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 15) -> AXUIElement? {
        if depth > maxDepth { return nil }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Found a text area - check if it's the compose body (not toolbar)
        if role == kAXTextAreaRole as String {
            if !hasToolbarAncestor(element), isComposeElement(element) {
                Logger.debug("OutlookContentParser: Found compose text area at depth \(depth)", category: Logger.accessibility)
                return element
            }
        }

        // Check children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        // Limit children to check to prevent slowdown
        for child in children.prefix(30) {
            if let found = findTextAreaInHierarchy(child, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }

        return nil
    }
}
