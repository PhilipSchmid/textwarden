//
//  PowerPointContentParser.swift
//  TextWarden
//
//  Content parser for Microsoft PowerPoint
//  Note: Only the Notes section is accessible via macOS Accessibility API.
//  Slide text boxes are not exposed programmatically by PowerPoint.
//

import AppKit
import Foundation

/// Content parser for Microsoft PowerPoint
/// Supports Notes section only (slide text boxes are not accessible via Accessibility API)
class PowerPointContentParser: ContentParser {
    let bundleIdentifier: String = "com.microsoft.Powerpoint"
    let parserName: String = "Microsoft PowerPoint"

    func detectUIContext(element: AXUIElement) -> String? {
        if PowerPointContentParser.isSlideElement(element) {
            return "slide"
        }
        return nil
    }

    func estimatedFontSize(context _: String?) -> CGFloat {
        // PowerPoint default body text is typically 18-24pt
        18.0
    }

    func spacingMultiplier(context _: String?) -> CGFloat {
        1.0
    }

    func horizontalPadding(context _: String?) -> CGFloat {
        4.0
    }

    /// Custom text extraction for Microsoft PowerPoint Notes section
    /// The element to monitor has already been validated by isSlideElement during element selection
    func extractText(from element: AXUIElement) -> String? {
        // Get element role for logging
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "unknown"

        Logger.debug("PowerPointContentParser: extractText called for element with role: \(role)", category: Logger.accessibility)

        // Use AXValue to get the slide text
        // Note: We intentionally avoid parameterized attributes for PowerPoint (same crash risk as Word)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String,
           !text.isEmpty
        {
            Logger.debug("PowerPointContentParser: extractText - got AXValue (\(text.count) chars)", category: Logger.accessibility)
            return text
        }

        Logger.debug("PowerPointContentParser: extractText - no text found via AXValue", category: Logger.accessibility)
        return nil
    }

    // MARK: - Element Filtering

    /// Check if an element is a PowerPoint Notes text area (not toolbar/ribbon)
    /// Note: This primarily detects the Notes section AXTextArea since slide text boxes
    /// are not accessible via the macOS Accessibility API
    static func isSlideElement(_ element: AXUIElement) -> Bool {
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

        Logger.debug("PowerPointContentParser: Checking element - role: \(role), subrole: \(subrole), hasDesc: \(!description.isEmpty), hasId: \(!identifier.isEmpty), hasTitle: \(!title.isEmpty), valueLen: \(value.count)", category: Logger.accessibility)

        // EXCLUDE: Toolbar elements (ribbon controls)
        if isToolbarElement(role: role, subrole: subrole, description: description, identifier: identifier, title: title, value: value) {
            Logger.debug("PowerPointContentParser: Rejecting - toolbar/ribbon element", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Font name/style dropdowns
        if isFontElement(description: description, identifier: identifier, title: title, value: value) {
            Logger.debug("PowerPointContentParser: Rejecting - font selector element", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Menu items and popups
        if role == "AXMenuItem" || role == "AXMenu" || role == "AXPopUpButton" {
            Logger.debug("PowerPointContentParser: Rejecting - menu element", category: Logger.accessibility)
            return false
        }

        // Check parent hierarchy for toolbar/ribbon ancestors
        if hasToolbarAncestor(element) {
            Logger.debug("PowerPointContentParser: Rejecting - has toolbar ancestor", category: Logger.accessibility)
            return false
        }

        // ACCEPT: Text areas (Notes section)
        if role == kAXTextAreaRole as String {
            Logger.debug("PowerPointContentParser: Accepting - AXTextArea (Notes)", category: Logger.accessibility)
            return true
        }

        // ACCEPT: Layout areas (may be used in some contexts)
        if role == "AXLayoutArea" {
            Logger.debug("PowerPointContentParser: Accepting - AXLayoutArea", category: Logger.accessibility)
            return true
        }

        // ACCEPT: Text fields that are NOT in toolbar and have content
        if role == kAXTextFieldRole as String {
            let valueLength = value.count
            if valueLength > 0 {
                Logger.debug("PowerPointContentParser: Accepting - AXTextField with content (\(valueLength) chars)", category: Logger.accessibility)
                return true
            }
        }

        Logger.debug("PowerPointContentParser: Rejecting - role '\(role)' not recognized as slide content", category: Logger.accessibility)
        return false
    }

    /// Check if the element appears to be a toolbar/ribbon control
    private static func isToolbarElement(role: String, subrole _: String, description: String, identifier: String, title: String, value _: String) -> Bool {
        // Toolbar-related roles
        let toolbarRoles = ["AXToolbar", "AXGroup", "AXButton", "AXCheckBox", "AXRadioButton"]
        if toolbarRoles.contains(role), !role.contains("Text") {
            return true
        }

        // Toolbar-related keywords in description/identifier
        let toolbarKeywords = ["toolbar", "ribbon", "format", "home", "insert", "layout", "view", "review", "design", "transitions", "animations", "slideshow"]
        for keyword in toolbarKeywords {
            if description.contains(keyword) || identifier.contains(keyword) || title.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Check if the element is a font selector
    private static func isFontElement(description: String, identifier: String, title _: String, value: String) -> Bool {
        // Font-related keywords
        let fontKeywords = ["font", "typeface", "aptos", "calibri", "arial", "times", "helvetica", "style", "body"]
        for keyword in fontKeywords {
            if description.contains(keyword) || identifier.contains(keyword) {
                return true
            }
        }

        // Check if value looks like a font name (parenthesized suffix like "Aptos (Body)")
        if value.contains("("), value.contains(")"), value.count < 50 {
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
               CFGetTypeID(parent) == AXUIElementGetTypeID()
            {
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
}
