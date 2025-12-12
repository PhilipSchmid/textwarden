//
//  MailContentParser.swift
//  TextWarden
//
//  Content parser for Apple Mail
//  Only checks text in email composition areas (new mail, reply, forward)
//  Excludes sidebar (folders), message list, search fields, etc.
//

import Foundation
import AppKit

/// Content parser for Apple Mail
/// Focuses only on email composition text, ignoring navigation UI
class MailContentParser: ContentParser {
    let bundleIdentifier: String = "com.apple.mail"
    let parserName: String = "Apple Mail"

    func detectUIContext(element: AXUIElement) -> String? {
        // Check if we're in a composition area
        if MailContentParser.isMailCompositionElement(element) {
            return "composition"
        }
        return nil
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Apple Mail uses system default font size (typically 13-14pt)
        return 13.0
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        return 1.0
    }

    func horizontalPadding(context: String?) -> CGFloat {
        return 4.0
    }

    /// Custom bounds calculation for Mail's WebKit accessibility API.
    /// Handles coordinate conversion from layout to screen space.
    func getBoundsForRange(range: NSRange, in element: AXUIElement) -> CGRect? {
        return MailContentParser.getBoundsForRange(range: range, in: element)
    }

    /// Custom text extraction for Apple Mail's WebKit-based composition area
    /// Mail's AXWebArea doesn't expose text via AXValue - text is in AXStaticText children
    /// See: https://stackoverflow.com/questions/8228459/accessibility-api-axwebarea-children-elements-or-html-source
    func extractText(from element: AXUIElement) -> String? {
        // First check if this is a composition element
        guard MailContentParser.isMailCompositionElement(element) else {
            Logger.debug("MailContentParser: extractText - not a composition element", category: Logger.accessibility)
            return nil
        }

        // Log available parameterized attributes (once per session) for debugging
        MailContentParser.logAvailableAttributes(element)

        // Try standard AXValue first (might work in some cases)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String,
           !text.isEmpty {
            Logger.debug("MailContentParser: extractText - got AXValue (\(text.count) chars)", category: Logger.accessibility)
            return text
        }

        // CRITICAL: Use AXStringForRange to get the EXACT text including newlines.
        // Mail's AXStaticText children do NOT include newline characters, but Mail's
        // AXBoundsForRange uses indices that count newlines. Using AXStringForRange
        // ensures our character indices match Mail's accessibility API exactly.
        var charCountRef: CFTypeRef?
        var mailCharCount = 0
        if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &charCountRef) == .success,
           let count = charCountRef as? Int {
            mailCharCount = count
        } else {
            Logger.debug("MailContentParser: AXNumberOfCharacters failed, trying with large range", category: Logger.accessibility)
            mailCharCount = 100_000  // Try with a large range
        }

        if mailCharCount > 0 {
            var range = CFRange(location: 0, length: mailCharCount)
            if let rangeValue = AXValueCreate(.cfRange, &range) {
                var stringRef: CFTypeRef?
                let axResult = AXUIElementCopyParameterizedAttributeValue(element, "AXStringForRange" as CFString, rangeValue, &stringRef)
                if axResult == .success,
                   let text = stringRef as? String,
                   !text.isEmpty {
                    Logger.debug("MailContentParser: AXStringForRange succeeded (\(text.count) chars)", category: Logger.accessibility)
                    return text
                }
            }
        }

        // Fallback: traverse children to find AXStaticText elements
        // Mail's AXWebArea has children: AXGroup -> AXStaticText (one per line)
        // Note: This fallback is less reliable for positioning as it may not include newlines correctly
        var collectedText: [String] = []
        MailContentParser.collectTextFromChildren(element, into: &collectedText, depth: 0, maxDepth: 10)

        if !collectedText.isEmpty {
            let fullText = collectedText.joined(separator: "\n")
            Logger.debug("MailContentParser: extractText - using fallback text extraction (\(fullText.count) chars)", category: Logger.accessibility)
            return fullText
        }

        Logger.debug("MailContentParser: extractText - no text found", category: Logger.accessibility)
        return nil
    }

    // MARK: - WebKit Attribute Diagnostics

    private static var hasLoggedAttributes = false

    /// Log available attributes for debugging WebKit accessibility
    private static func logAvailableAttributes(_ element: AXUIElement) {
        guard !hasLoggedAttributes else { return }
        hasLoggedAttributes = true

        Logger.info("MailContentParser: === Logging Mail AXWebArea attributes ===", category: Logger.accessibility)

        // Log standard attributes
        var attrNamesRef: CFArray?
        if AXUIElementCopyAttributeNames(element, &attrNamesRef) == .success,
           let attrNames = attrNamesRef as? [String] {
            Logger.info("MailContentParser: Standard attributes (\(attrNames.count)):", category: Logger.accessibility)
            for attr in attrNames.sorted() {
                Logger.debug("  - \(attr)", category: Logger.accessibility)
            }
        }

        // Log parameterized attributes (critical for WebKit)
        var paramAttrNamesRef: CFArray?
        if AXUIElementCopyParameterizedAttributeNames(element, &paramAttrNamesRef) == .success,
           let paramAttrNames = paramAttrNamesRef as? [String] {
            Logger.info("MailContentParser: Parameterized attributes (\(paramAttrNames.count)):", category: Logger.accessibility)
            for attr in paramAttrNames.sorted() {
                Logger.debug("  - \(attr)", category: Logger.accessibility)
            }

            // Check for critical WebKit attributes
            let hasTextMarkerForIndex = paramAttrNames.contains("AXTextMarkerForIndex")
            let hasBoundsForTextMarkerRange = paramAttrNames.contains("AXBoundsForTextMarkerRange")
            let hasStringForTextMarkerRange = paramAttrNames.contains("AXStringForTextMarkerRange")

            Logger.info("MailContentParser: Critical attributes check:", category: Logger.accessibility)
            Logger.info("  - AXTextMarkerForIndex: \(hasTextMarkerForIndex ? "✓" : "✗")", category: Logger.accessibility)
            Logger.info("  - AXBoundsForTextMarkerRange: \(hasBoundsForTextMarkerRange ? "✓" : "✗")", category: Logger.accessibility)
            Logger.info("  - AXStringForTextMarkerRange: \(hasStringForTextMarkerRange ? "✓" : "✗")", category: Logger.accessibility)
        } else {
            Logger.warning("MailContentParser: Could not get parameterized attributes", category: Logger.accessibility)
        }

        // Check for start/end text markers
        var startMarkerRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXStartTextMarker" as CFString, &startMarkerRef) == .success {
            Logger.info("MailContentParser: Has AXStartTextMarker ✓", category: Logger.accessibility)
        } else {
            Logger.info("MailContentParser: Has AXStartTextMarker ✗", category: Logger.accessibility)
        }

        var endMarkerRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEndTextMarker" as CFString, &endMarkerRef) == .success {
            Logger.info("MailContentParser: Has AXEndTextMarker ✓", category: Logger.accessibility)
        } else {
            Logger.info("MailContentParser: Has AXEndTextMarker ✗", category: Logger.accessibility)
        }

        Logger.info("MailContentParser: === End attribute logging ===", category: Logger.accessibility)
    }

    // MARK: - WebKit Text Operations (Bounds, Selection, Replacement)

    /// Get bounds for a character range in Mail's WebKit composition.
    /// Handles coordinate conversion from layout to screen space when needed.
    static func getBoundsForRange(
        range: NSRange,
        in element: AXUIElement
    ) -> CGRect? {
        // Use AXBoundsForRange (CFRange based)
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            rangeValue,
            &boundsValue
        )

        if result == .success,
           let bounds = boundsValue,
           let rect = safeAXValueGetRect(bounds) {
            // Heuristic: Determine if coordinates are layout or screen
            // Layout coords have small X values, screen coords are larger
            var posRef: CFTypeRef?
            var elementPosition = CGPoint.zero
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
               let pv = posRef,
               let pos = safeAXValueGetPoint(pv) {
                elementPosition = pos
            }

            let looksLikeLayoutCoords = rect.origin.x < 200 && rect.origin.x < (elementPosition.x - 100)

            if !looksLikeLayoutCoords {
                // Already screen coordinates
                return rect
            }

            // Try to convert from layout to screen
            if let screenRect = AccessibilityBridge.convertLayoutRectToScreen(rect, in: element) {
                return screenRect
            } else {
                // Conversion failed, use as-is
                return rect
            }
        }

        // Fall through to text marker method
        return tryTextMarkerBounds(range: range, element: element)
    }

    /// Try getting bounds using text marker API (fallback method)
    private static func tryTextMarkerBounds(range: NSRange, element: AXUIElement) -> CGRect? {
        guard let startMarker = createTextMarker(at: range.location, in: element),
              let endMarker = createTextMarker(at: range.location + range.length, in: element),
              let markerRange = createTextMarkerRange(start: startMarker, end: endMarker, in: element) else {
            return nil
        }

        var markerBoundsValue: CFTypeRef?
        let markerResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &markerBoundsValue
        )

        if markerResult == .success,
           let bounds = markerBoundsValue,
           let rect = safeAXValueGetRect(bounds) {
            // Check if conversion is needed (same heuristic as CFRange method)
            var posRef: CFTypeRef?
            var elementPosition = CGPoint.zero
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
               let pv = posRef,
               let pos = safeAXValueGetPoint(pv) {
                elementPosition = pos
            }

            let looksLikeLayoutCoords = rect.origin.x < 200 && rect.origin.x < (elementPosition.x - 100)

            if !looksLikeLayoutCoords {
                return rect
            }

            // Try layout→screen conversion
            if let screenRect = AccessibilityBridge.convertLayoutRectToScreen(rect, in: element) {
                return screenRect
            } else {
                return rect
            }
        }

        return nil
    }

    /// Replace text in Mail using AXReplaceRangeWithText (the WebKit accessibility API)
    static func replaceText(
        range: NSRange,
        with replacement: String,
        in element: AXUIElement
    ) -> Bool {
        Logger.info("MailContentParser: replaceText range \(range.location)-\(range.location + range.length) with '\(replacement)'", category: Logger.accessibility)

        // Convert grapheme cluster indices to UTF-16 for Mail's accessibility API
        let utf16Range = convertToUTF16Range(range, in: element)
        Logger.debug("MailContentParser: replaceText UTF-16 conversion: grapheme [\(range.location), \(range.length)] -> UTF-16 [\(utf16Range.location), \(utf16Range.length)]", category: Logger.accessibility)

        // Method 1: AXReplaceRangeWithText - the proper API for WebKit
        // Parameter is an array: [CFRange, String]
        var cfRange = CFRange(location: utf16Range.location, length: utf16Range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.debug("MailContentParser: Failed to create CFRange", category: Logger.accessibility)
            return false
        }

        let params = [rangeValue, replacement as CFString] as CFArray

        var resultValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXReplaceRangeWithText" as CFString,
            params,
            &resultValue
        )

        if result == .success {
            Logger.info("MailContentParser: AXReplaceRangeWithText succeeded!", category: Logger.accessibility)
            return true
        }

        Logger.debug("MailContentParser: AXReplaceRangeWithText failed: \(result.rawValue)", category: Logger.accessibility)

        // Return false so caller can use selection + paste fallback
        return false
    }

    /// Select text in Mail's WebKit composition area
    /// Uses AXSelectedTextMarkerRange or CFRange selection
    static func selectTextForReplacement(
        range: NSRange,
        in element: AXUIElement
    ) -> Bool {
        Logger.debug("MailContentParser: selectTextForReplacement range: \(range.location)-\(range.location + range.length)", category: Logger.accessibility)

        // Convert grapheme cluster indices to UTF-16 for Mail's accessibility API
        let utf16Range = convertToUTF16Range(range, in: element)
        Logger.debug("MailContentParser: selectTextForReplacement UTF-16 conversion: grapheme [\(range.location), \(range.length)] -> UTF-16 [\(utf16Range.location), \(utf16Range.length)]", category: Logger.accessibility)

        // Method 1: Use text markers (most reliable for WebKit)
        if let startMarker = createTextMarker(at: utf16Range.location, in: element),
           let endMarker = createTextMarker(at: utf16Range.location + utf16Range.length, in: element) {

            // Create marker range
            if let markerRange = createTextMarkerRange(start: startMarker, end: endMarker, in: element) {
                let result = AXUIElementSetAttributeValue(
                    element,
                    "AXSelectedTextMarkerRange" as CFString,
                    markerRange
                )
                if result == .success {
                    Logger.info("MailContentParser: Selection via AXSelectedTextMarkerRange succeeded", category: Logger.accessibility)
                    return true
                } else {
                    Logger.debug("MailContentParser: AXSelectedTextMarkerRange failed: \(result.rawValue)", category: Logger.accessibility)
                }
            }
        }

        // Method 2: Standard CFRange-based selection (also using UTF-16 range)
        Logger.debug("MailContentParser: Trying CFRange selection", category: Logger.accessibility)
        var cfRange = CFRange(location: utf16Range.location, length: utf16Range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if result == .success {
            Logger.info("MailContentParser: CFRange selection succeeded", category: Logger.accessibility)
            return true
        }

        Logger.debug("MailContentParser: CFRange selection failed: \(result.rawValue)", category: Logger.accessibility)
        return false
    }

    /// Create a text marker for a character index
    private static func createTextMarker(at index: Int, in element: AXUIElement) -> CFTypeRef? {
        var indexValue: Int = index
        guard let indexRef = CFNumberCreate(kCFAllocatorDefault, .intType, &indexValue) else {
            return nil
        }

        var markerValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerForIndex" as CFString,
            indexRef,
            &markerValue
        )

        if result == .success, let marker = markerValue {
            return marker
        }

        Logger.debug("MailContentParser: AXTextMarkerForIndex failed for index \(index): \(result.rawValue)", category: Logger.accessibility)
        return nil
    }

    /// Create a text marker range from start and end markers
    private static func createTextMarkerRange(
        start: CFTypeRef,
        end: CFTypeRef,
        in element: AXUIElement
    ) -> CFTypeRef? {
        // Try AXTextMarkerRangeForUnorderedTextMarkers
        let markerPair = [start, end] as CFArray
        var rangeValue: CFTypeRef?

        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
            markerPair,
            &rangeValue
        )

        if result == .success, let range = rangeValue {
            return range
        }

        // Try AXTextMarkerRangeForTextMarkers (ordered version)
        let result2 = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerRangeForTextMarkers" as CFString,
            markerPair,
            &rangeValue
        )

        if result2 == .success, let range = rangeValue {
            return range
        }

        Logger.debug("MailContentParser: createTextMarkerRange failed", category: Logger.accessibility)
        return nil
    }

    // MARK: - UTF-16 Index Conversion

    /// Convert grapheme cluster indices to UTF-16 code unit indices for Mail's accessibility API.
    /// Mail's WebKit APIs (AXBoundsForRange, AXTextMarkerForIndex, etc.) use UTF-16 code units,
    /// while Harper provides error positions in grapheme clusters (Swift String indices).
    /// This matters for text containing emojis: 👋 = 1 grapheme but 2 UTF-16 code units.
    private static func convertToUTF16Range(_ range: NSRange, in element: AXUIElement) -> NSRange {
        // Fetch the actual text from the element using AXStringForRange
        // This ensures we're converting based on the same text that Mail's AX APIs use
        var charCountRef: CFTypeRef?
        var textLength = 0
        if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &charCountRef) == .success,
           let count = charCountRef as? Int {
            textLength = count
        } else {
            // Fallback: use a large range
            textLength = 100_000
        }

        // Fetch text using AXStringForRange (matches what Mail's AX APIs expect)
        var cfRange = CFRange(location: 0, length: textLength)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.debug("MailContentParser: Failed to create range value for text fetch", category: Logger.accessibility)
            return range
        }

        var stringRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForRange" as CFString,
            rangeValue,
            &stringRef
        )

        guard result == .success, let text = stringRef as? String, !text.isEmpty else {
            Logger.debug("MailContentParser: AXStringForRange failed, using original range", category: Logger.accessibility)
            return range
        }

        // Now convert grapheme cluster indices to UTF-16 code unit indices
        let textCount = text.count
        let safeLocation = min(range.location, textCount)
        let safeEndLocation = min(range.location + range.length, textCount)

        // Get String.Index for the grapheme cluster positions
        guard let startIndex = text.index(text.startIndex, offsetBy: safeLocation, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: safeEndLocation, limitedBy: text.endIndex) else {
            // Fallback to original range if conversion fails
            return range
        }

        // Extract the prefix strings and measure their UTF-16 lengths
        let prefixToStart = String(text[..<startIndex])
        let prefixToEnd = String(text[..<endIndex])

        let utf16Location = (prefixToStart as NSString).length
        let utf16EndLocation = (prefixToEnd as NSString).length
        let utf16Length = max(1, utf16EndLocation - utf16Location)

        return NSRange(location: utf16Location, length: utf16Length)
    }

    // MARK: - Child Element Traversal

    /// Recursively collect text from AXStaticText children
    private static func collectTextFromChildren(_ element: AXUIElement, into texts: inout [String], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        // Get role of this element
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // If this is a static text element, get its value
        if role == kAXStaticTextRole as String {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let text = valueRef as? String,
               !text.isEmpty {
                texts.append(text)
            }
            return  // Don't recurse into static text children
        }

        // Get children and recurse
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            collectTextFromChildren(child, into: &texts, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    /// Check if an element is an Apple Mail composition area (not sidebar/navigation)
    /// Returns true ONLY for actual email composition text areas
    /// Returns false for folder list, message list, search, etc.
    static func isMailCompositionElement(_ element: AXUIElement) -> Bool {
        // Get the role of the element
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Get the subrole
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String ?? ""

        // Get role description
        var roleDescRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescRef)
        let roleDesc = (roleDescRef as? String)?.lowercased() ?? ""

        // Get identifier
        var identifierRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef)
        let identifier = (identifierRef as? String)?.lowercased() ?? ""

        // Get description
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        let description = (descRef as? String)?.lowercased() ?? ""

        Logger.debug("MailContentParser: Checking element - role: \(role), subrole: \(subrole), roleDesc: \(roleDesc), id: \(identifier), desc: \(description)", category: Logger.accessibility)

        // EXCLUDE: Outline rows (sidebar folder items like "Archiv", "Inbox", etc.)
        if subrole == "AXOutlineRow" || role == "AXOutlineRow" {
            Logger.debug("MailContentParser: Rejecting - outline row (sidebar item)", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Outline elements (the sidebar itself)
        if role == "AXOutline" {
            Logger.debug("MailContentParser: Rejecting - outline (sidebar)", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Table rows (message list items)
        if role == "AXRow" || subrole == "AXTableRow" {
            Logger.debug("MailContentParser: Rejecting - table row (message list)", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Cells (table cells in message list or sidebar)
        if role == "AXCell" {
            Logger.debug("MailContentParser: Rejecting - cell (list item)", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Static text (labels, not editable)
        if role == kAXStaticTextRole as String {
            Logger.debug("MailContentParser: Rejecting - static text", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Search fields
        if subrole == "AXSearchField" || roleDesc.contains("search") || identifier.contains("search") {
            Logger.debug("MailContentParser: Rejecting - search field", category: Logger.accessibility)
            return false
        }

        // EXCLUDE: Text fields that are NOT message body (To, CC, Subject fields are AXTextField)
        // The message body is typically AXTextArea or AXWebArea
        if role == kAXTextFieldRole as String {
            // To, CC, BCC, Subject fields are single-line text fields - skip them
            // They often have identifiers or descriptions indicating their purpose
            let fieldText = "\(identifier) \(description) \(roleDesc)"
            if fieldText.contains("to") || fieldText.contains("cc") || fieldText.contains("bcc") ||
               fieldText.contains("subject") || fieldText.contains("recipient") ||
               fieldText.contains("address") {
                Logger.debug("MailContentParser: Rejecting - header field (To/CC/Subject)", category: Logger.accessibility)
                return false
            }
            // Other single-line text fields in Mail are typically not the message body
            Logger.debug("MailContentParser: Rejecting - text field (not message body)", category: Logger.accessibility)
            return false
        }

        // INCLUDE: Text areas (the main composition body)
        if role == kAXTextAreaRole as String {
            Logger.debug("MailContentParser: Accepting - text area (composition body)", category: Logger.accessibility)
            return true
        }

        // INCLUDE: Web areas (Mail uses WebKit for rich text composition)
        if role == "AXWebArea" {
            Logger.debug("MailContentParser: Accepting - web area (rich text composition)", category: Logger.accessibility)
            return true
        }

        // Check parent hierarchy to see if we're inside a composition window
        // Composition windows have specific structure
        if isInsideCompositionWindow(element) {
            Logger.debug("MailContentParser: Accepting - inside composition window", category: Logger.accessibility)
            return true
        }

        Logger.debug("MailContentParser: Rejecting - unknown element type", category: Logger.accessibility)
        return false
    }

    /// Check if element is inside a Mail composition window (not main viewer)
    private static func isInsideCompositionWindow(_ element: AXUIElement) -> Bool {
        var currentElement: AXUIElement? = element

        // Walk up the parent hierarchy (up to 15 levels for Mail's deep hierarchy)
        for depth in 0..<15 {
            var parentRef: CFTypeRef?
            guard let current = currentElement,
                  AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                break
            }

            let parentElement = parent as! AXUIElement

            // Get parent's role
            var parentRole: CFTypeRef?
            AXUIElementCopyAttributeValue(parentElement, kAXRoleAttribute as CFString, &parentRole)
            let parentRoleStr = parentRole as? String ?? ""

            // Get parent's subrole
            var parentSubrole: CFTypeRef?
            AXUIElementCopyAttributeValue(parentElement, kAXSubroleAttribute as CFString, &parentSubrole)
            let parentSubroleStr = parentSubrole as? String ?? ""

            // Get parent's title
            var parentTitle: CFTypeRef?
            AXUIElementCopyAttributeValue(parentElement, kAXTitleAttribute as CFString, &parentTitle)
            let parentTitleStr = (parentTitle as? String)?.lowercased() ?? ""

            // REJECT: If we find an outline (sidebar), we're not in composition
            if parentRoleStr == "AXOutline" {
                Logger.debug("MailContentParser: Parent hierarchy contains outline at depth \(depth) - not composition", category: Logger.accessibility)
                return false
            }

            // REJECT: If we find a table (message list), we're not in composition
            if parentRoleStr == "AXTable" {
                Logger.debug("MailContentParser: Parent hierarchy contains table at depth \(depth) - not composition", category: Logger.accessibility)
                return false
            }

            // ACCEPT: Standard windows with composition-related titles
            if parentRoleStr == "AXWindow" {
                // Composition windows often have titles like "New Message", "Re:", "Fwd:", etc.
                // or in German: "Neue E-Mail", "AW:", "WG:", etc.
                let compositionIndicators = [
                    "new message", "neue", "re:", "aw:", "fwd:", "wg:",
                    "reply", "forward", "antwort", "weiterleiten",
                    "compose", "draft", "entwurf"
                ]
                for indicator in compositionIndicators {
                    if parentTitleStr.contains(indicator) {
                        Logger.debug("MailContentParser: Found composition window title '\(parentTitleStr)' at depth \(depth)", category: Logger.accessibility)
                        return true
                    }
                }

                // If we're in a window but it doesn't look like composition,
                // check if the element is a text area (already accepted) vs sidebar
                // Don't immediately reject - the window might be untitled new message
            }

            // ACCEPT: Scroll areas that might contain the message editor
            // (the composition body is inside a scroll area)
            if parentRoleStr == "AXScrollArea" && parentSubroleStr != "AXOutlineRow" {
                // This could be the composition scroll area
                // Continue checking to see if we're really in composition
            }

            currentElement = parentElement
        }

        // If we didn't find definitive composition or rejection signals,
        // rely on the element's own properties (already checked in isMailCompositionElement)
        return false
    }
}
