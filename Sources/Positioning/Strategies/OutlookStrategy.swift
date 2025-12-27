//
//  OutlookStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Microsoft Outlook compose windows.
//
//  APPROACH:
//  Outlook has two distinct text editing contexts:
//  1. Subject field (AXTextField) - Standard AXBoundsForRange works correctly
//  2. Compose body (AXTextArea) - AXBoundsForRange works on both the main element and child elements
//
//  Unlike Slack's editor, Outlook's AX APIs return valid bounds for both element types.
//  We use AXBoundsForRange directly, with tree traversal as a fallback if needed.
//

import AppKit
import ApplicationServices

/// A segment of text with its visual bounds from the AX tree
private struct OutlookTextPart {
    let text: String
    let range: NSRange          // Character range in the full text
    let frame: CGRect           // Visual bounds from AXFrame (Quartz coordinates)
    let element: AXUIElement    // Reference to query AXBoundsForRange directly
}

/// Dedicated Outlook positioning using element-specific approaches
class OutlookStrategy: GeometryProvider {

    var strategyName: String { "Outlook" }
    var strategyType: StrategyType { .outlook }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 5 }

    private static let outlookBundleID = "com.microsoft.Outlook"

    // Outlook's default compose font (Aptos, 12pt with 1.5x spacing)
    private static let outlookFontSize: CGFloat = 12.0
    private static let outlookSpacingMultiplier: CGFloat = 1.5

    // Underline visual constants
    private static let underlineHeight: CGFloat = 2.0
    private static let xAdjustment: CGFloat = 0.0

    // TextPart cache to avoid rebuilding for each error
    private var cachedTextParts: [OutlookTextPart] = []
    private var cachedTextHash: Int = 0
    private var cachedElementFrame: CGRect = .zero

    // MARK: - GeometryProvider

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        guard bundleID == Self.outlookBundleID else { return false }

        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("OutlookStrategy: Skipping - watchdog protection active", category: Logger.ui)
            return false
        }

        // Only handle compose elements (subject field or body)
        guard OutlookContentParser.isComposeElement(element) else {
            Logger.debug("OutlookStrategy: Skipping - not a compose element", category: Logger.ui)
            return false
        }

        return true
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("OutlookStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

        // Determine element type
        let role = getRole(element)
        Logger.debug("OutlookStrategy: Element role: \(role)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let originalRange = NSRange(location: errorRange.location + offset, length: errorRange.length)

        // Route to appropriate handler based on element type
        if role == kAXTextFieldRole as String {
            // Subject field - standard AXBoundsForRange works
            return calculateSubjectFieldGeometry(
                errorRange: originalRange,
                element: element,
                text: text,
                parser: parser
            )
        } else if role == kAXTextAreaRole as String {
            // Compose body - needs tree traversal approach
            return calculateComposeBodyGeometry(
                errorRange: originalRange,
                element: element,
                text: text,
                parser: parser
            )
        }

        Logger.debug("OutlookStrategy: Unknown role '\(role)' - returning unavailable", category: Logger.ui)
        return GeometryResult.unavailable(reason: "Unknown Outlook element role")
    }

    // MARK: - Subject Field (AXTextField)

    /// Calculate geometry for subject field using standard AXBoundsForRange
    private func calculateSubjectFieldGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("OutlookStrategy: Subject field - using AXBoundsForRange", category: Logger.ui)

        // Convert grapheme cluster indices to UTF-16 for the accessibility API
        let utf16Range = TextIndexConverter.graphemeToUTF16Range(errorRange, in: text)

        var cfRange = CFRange(location: utf16Range.location, length: utf16Range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var boundsRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            rangeValue,
            &boundsRef
        )

        guard result == .success,
              let bv = boundsRef,
              CFGetTypeID(bv) == AXValueGetTypeID() else {
            Logger.debug("OutlookStrategy: Subject AXBoundsForRange failed", category: Logger.ui)
            return nil
        }

        var quartzBounds = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &quartzBounds) else {
            return nil
        }

        // Validate bounds
        if quartzBounds.width < GeometryConstants.minimumBoundsSize {
            Logger.debug("OutlookStrategy: Subject bounds too small (\(quartzBounds.width)px)", category: Logger.ui)
            return nil
        }

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("OutlookStrategy: Subject bounds validation failed", category: Logger.ui)
            return nil
        }

        Logger.debug("OutlookStrategy: Subject SUCCESS - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: [
                "api": "subject-bounds-for-range",
                "element_type": "AXTextField"
            ]
        )
    }

    // MARK: - Compose Body (AXTextArea)

    /// Calculate geometry for compose body using AXBoundsForRange
    /// Falls back to tree traversal if direct query fails
    private func calculateComposeBodyGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("OutlookStrategy: Compose body - trying AXBoundsForRange", category: Logger.ui)

        // Outlook's AXBoundsForRange uses grapheme cluster indices, NOT UTF-16
        // (Unlike Safari/WebKit which uses UTF-16)
        // Using grapheme indices directly for correct positioning
        var cfRange = CFRange(location: errorRange.location, length: errorRange.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var boundsRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            rangeValue,
            &boundsRef
        )

        if result == .success,
           let bv = boundsRef,
           CFGetTypeID(bv) == AXValueGetTypeID() {

            var quartzBounds = CGRect.zero
            guard AXValueGetValue(bv as! AXValue, .cgRect, &quartzBounds) else {
                return nil
            }

            // Validate bounds - reject suspiciously small widths
            if quartzBounds.width >= GeometryConstants.minimumBoundsSize {
                // Convert to Cocoa coordinates
                let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

                guard CoordinateMapper.validateBounds(cocoaBounds) else {
                    Logger.debug("OutlookStrategy: Body bounds validation failed", category: Logger.ui)
                    return calculateTreeTraversalFallback(
                        errorRange: errorRange,
                        element: element,
                        text: text
                    )
                }

                Logger.debug("OutlookStrategy: Body SUCCESS (AXBoundsForRange) - bounds: \(cocoaBounds)", category: Logger.ui)

                return GeometryResult(
                    bounds: cocoaBounds,
                    confidence: GeometryConstants.highConfidence,
                    strategy: strategyName,
                    metadata: [
                        "api": "body-bounds-for-range",
                        "element_type": "AXTextArea"
                    ]
                )
            }

            Logger.debug("OutlookStrategy: Body AXBoundsForRange returned small width (\(quartzBounds.width)px) - trying tree traversal", category: Logger.ui)
        } else {
            Logger.debug("OutlookStrategy: Body AXBoundsForRange failed - trying tree traversal", category: Logger.ui)
        }

        // Fallback to tree traversal if direct query fails or returns bad data
        return calculateTreeTraversalFallback(
            errorRange: errorRange,
            element: element,
            text: text
        )
    }

    /// Tree traversal fallback when AXBoundsForRange fails or returns bad data
    private func calculateTreeTraversalFallback(
        errorRange: NSRange,
        element: AXUIElement,
        text: String
    ) -> GeometryResult? {

        Logger.debug("OutlookStrategy: Using tree traversal fallback", category: Logger.ui)

        // Get element frame for validation
        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
            Logger.debug("OutlookStrategy: Could not get element frame", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Could not get element frame")
        }

        // Get primary screen height for coordinate conversion
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        let primaryScreenHeight = primaryScreen?.frame.height ?? NSScreen.main?.frame.height ?? 1080

        // Get or build TextPart map (cached for performance)
        let textHash = text.hashValue
        let textParts: [OutlookTextPart]

        if textHash == cachedTextHash && elementFrame == cachedElementFrame && !cachedTextParts.isEmpty {
            textParts = cachedTextParts
        } else {
            textParts = buildTextPartMap(from: element, fullText: text)
            cachedTextParts = textParts
            cachedTextHash = textHash
            cachedElementFrame = elementFrame
            Logger.debug("OutlookStrategy: Built \(textParts.count) TextParts", category: Logger.ui)
        }

        if textParts.isEmpty {
            Logger.debug("OutlookStrategy: No TextParts found - falling back to font metrics", category: Logger.ui)
            return calculateFontMetricsFallback(
                errorRange: errorRange,
                element: element,
                text: text,
                elementFrame: elementFrame,
                primaryScreenHeight: primaryScreenHeight
            )
        }

        // Find TextPart(s) that contain the error range
        guard let bounds = findBoundsForRange(errorRange, in: textParts, fullText: text, element: element) else {
            Logger.debug("OutlookStrategy: Could not find TextPart for range \(errorRange)", category: Logger.ui)
            return calculateFontMetricsFallback(
                errorRange: errorRange,
                element: element,
                text: text,
                elementFrame: elementFrame,
                primaryScreenHeight: primaryScreenHeight
            )
        }

        // Apply adjustments
        let quartzBounds = CGRect(
            x: bounds.origin.x + Self.xAdjustment,
            y: bounds.origin.y,
            width: bounds.width,
            height: bounds.height
        )

        // Validate bounds are within element
        let elementBottom = elementFrame.origin.y + elementFrame.height
        guard quartzBounds.origin.y >= elementFrame.origin.y - 10 &&
              quartzBounds.origin.y <= elementBottom + 10 else {
            Logger.debug("OutlookStrategy: Bounds Y outside element", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Y position outside element bounds")
        }

        // Convert to Cocoa coordinates
        let cocoaY = primaryScreenHeight - quartzBounds.origin.y - quartzBounds.height
        let cocoaBounds = CGRect(
            x: quartzBounds.origin.x,
            y: cocoaY,
            width: quartzBounds.width,
            height: quartzBounds.height
        )

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("OutlookStrategy: Final bounds validation failed", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Invalid final bounds")
        }

        Logger.debug("OutlookStrategy: Body SUCCESS (tree) - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: [
                "api": "textpart-tree",
                "textparts": "\(textParts.count)",
                "element_type": "AXTextArea"
            ]
        )
    }

    // MARK: - TextPart Tree Building

    /// Build TextPart map by traversing AX children
    /// Outlook's compose body structure varies but generally has text run children
    private func buildTextPartMap(from element: AXUIElement, fullText: String) -> [OutlookTextPart] {
        var textParts: [OutlookTextPart] = []
        var searchStart = 0

        // Get children (paragraphs/lines)
        guard let children = getChildren(element) else {
            return []
        }

        for child in children {
            let role = getRole(child)
            let frame = getFrame(child)
            let childText = getText(child)

            // Direct text run
            if role == "AXStaticText" && !childText.isEmpty && frame.width > 0 && frame.height > 0 {
                if let foundRange = findTextRange(childText, in: fullText, startingAt: searchStart) {
                    textParts.append(OutlookTextPart(text: childText, range: foundRange, frame: frame, element: child))
                    searchStart = foundRange.location + foundRange.length
                }
                continue
            }

            // Check grandchildren (nested text runs)
            if let grandchildren = getChildren(child) {
                for grandchild in grandchildren {
                    let gcRole = getRole(grandchild)
                    let gcFrame = getFrame(grandchild)
                    let gcText = getText(grandchild)

                    if gcRole == "AXStaticText" && !gcText.isEmpty && gcFrame.width > 0 && gcFrame.height > 0 {
                        if let foundRange = findTextRange(gcText, in: fullText, startingAt: searchStart) {
                            textParts.append(OutlookTextPart(text: gcText, range: foundRange, frame: gcFrame, element: grandchild))
                            searchStart = foundRange.location + foundRange.length
                        }
                    }

                    // Check one more level for deeply nested text
                    if let ggChildren = getChildren(grandchild) {
                        for ggChild in ggChildren {
                            let ggRole = getRole(ggChild)
                            let ggFrame = getFrame(ggChild)
                            let ggText = getText(ggChild)

                            if ggRole == "AXStaticText" && !ggText.isEmpty && ggFrame.width > 0 && ggFrame.height > 0 {
                                if let foundRange = findTextRange(ggText, in: fullText, startingAt: searchStart) {
                                    textParts.append(OutlookTextPart(text: ggText, range: foundRange, frame: ggFrame, element: ggChild))
                                    searchStart = foundRange.location + foundRange.length
                                }
                            }
                        }
                    }
                }
            }
        }

        return textParts
    }

    /// Find the range of a substring starting from a given position
    private func findTextRange(_ substring: String, in text: String, startingAt: Int) -> NSRange? {
        guard startingAt < text.count else { return nil }
        guard let searchStartIdx = text.index(text.startIndex, offsetBy: startingAt, limitedBy: text.endIndex) else {
            return nil
        }

        let searchRange = searchStartIdx..<text.endIndex
        if let foundRange = text.range(of: substring, range: searchRange) {
            let location = text.distance(from: text.startIndex, to: foundRange.lowerBound)
            return NSRange(location: location, length: substring.count)
        }

        return nil
    }

    // MARK: - Bounds Lookup

    /// Find visual bounds for a character range using TextPart map
    private func findBoundsForRange(_ targetRange: NSRange, in textParts: [OutlookTextPart], fullText: String, element: AXUIElement) -> CGRect? {
        let targetEnd = targetRange.location + targetRange.length

        // Find ALL TextParts that overlap with the error range
        let overlappingParts = textParts.filter { part in
            let partEnd = part.range.location + part.range.length
            return targetRange.location < partEnd && targetEnd > part.range.location
        }

        if overlappingParts.isEmpty {
            Logger.debug("OutlookStrategy: No TextPart found overlapping range \(targetRange)", category: Logger.ui)
            return nil
        }

        // If error is entirely within one TextPart, calculate sub-element position
        if overlappingParts.count == 1 {
            let part = overlappingParts[0]
            return calculateSubElementBounds(targetRange: targetRange, in: part, element: element)
        }

        // Multiple overlapping parts: union their bounds
        var unionBounds = overlappingParts[0].frame
        for part in overlappingParts.dropFirst() {
            unionBounds = unionBounds.union(part.frame)
        }

        Logger.debug("OutlookStrategy: Unioned \(overlappingParts.count) TextParts for range \(targetRange)", category: Logger.ui)
        return unionBounds
    }

    /// Calculate bounds for error within a single TextPart
    private func calculateSubElementBounds(targetRange: NSRange, in part: OutlookTextPart, element: AXUIElement) -> CGRect {
        let offsetInPart = targetRange.location - part.range.location
        let errorLength = min(targetRange.location + targetRange.length, part.range.location + part.range.length) - targetRange.location

        // Query AXBoundsForRange on the child element directly
        if let bounds = getBoundsForRange(location: offsetInPart, length: errorLength, in: part.element) {
            if bounds.width > 0 && bounds.height > 0 && bounds.height < 50 {
                Logger.debug("OutlookStrategy: AXBoundsForRange on child SUCCESS: \(bounds)", category: Logger.ui)
                return bounds
            }
        }

        // Fallback: use font measurement
        Logger.debug("OutlookStrategy: AXBoundsForRange failed, falling back to font measurement", category: Logger.ui)
        return calculateSubElementBoundsWithFontMeasurement(
            offsetInPart: offsetInPart,
            errorLength: errorLength,
            part: part
        )
    }

    /// Get bounds for a range within a child element using AXBoundsForRange
    private func getBoundsForRange(location: Int, length: Int, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var boundsRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            rangeValue,
            &boundsRef
        )

        guard result == .success,
              let bv = boundsRef,
              CFGetTypeID(bv) == AXValueGetTypeID() else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &bounds) else {
            return nil
        }

        return bounds
    }

    // Font measurement fallback - use Outlook's font configuration
    private static let fontScaleFactor: CGFloat = 0.97

    /// Fallback calculation using font measurement
    private func calculateSubElementBoundsWithFontMeasurement(
        offsetInPart: Int,
        errorLength: Int,
        part: OutlookTextPart
    ) -> CGRect {
        let font = NSFont(name: "Aptos", size: Self.outlookFontSize) ?? NSFont.systemFont(ofSize: Self.outlookFontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        // Calculate X offset using font measurement
        let textBeforeError: String
        if let startIdx = part.text.index(part.text.startIndex, offsetBy: offsetInPart, limitedBy: part.text.endIndex) {
            textBeforeError = String(part.text[..<startIdx])
        } else {
            textBeforeError = ""
        }
        let measuredXOffset = (textBeforeError as NSString).size(withAttributes: attrs).width
        let xOffset = measuredXOffset * Self.outlookSpacingMultiplier * Self.fontScaleFactor

        // Calculate error width
        let errorText: String
        if let startIdx = part.text.index(part.text.startIndex, offsetBy: offsetInPart, limitedBy: part.text.endIndex),
           let endIdx = part.text.index(part.text.startIndex, offsetBy: min(offsetInPart + errorLength, part.text.count), limitedBy: part.text.endIndex) {
            errorText = String(part.text[startIdx..<endIdx])
        } else {
            errorText = ""
        }
        let measuredErrorWidth = (errorText as NSString).size(withAttributes: attrs).width
        let errorWidth = max(measuredErrorWidth * Self.outlookSpacingMultiplier * Self.fontScaleFactor, 20.0)

        Logger.debug("OutlookStrategy: Font measurement fallback - offset=\(offsetInPart) xOffset=\(String(format: "%.1f", xOffset))", category: Logger.ui)

        return CGRect(
            x: part.frame.origin.x + xOffset,
            y: part.frame.origin.y,
            width: errorWidth,
            height: part.frame.height
        )
    }

    // MARK: - Font Metrics Fallback

    /// Fallback when tree traversal fails completely
    private func calculateFontMetricsFallback(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        elementFrame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> GeometryResult? {

        let font = NSFont(name: "Aptos", size: Self.outlookFontSize) ?? NSFont.systemFont(ofSize: Self.outlookFontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        // Find line start for X calculation
        let lineStartIndex = findLineStart(in: text, at: errorRange.location)

        guard let lineStartIdx = text.index(text.startIndex, offsetBy: lineStartIndex, limitedBy: text.endIndex),
              let errorStartIdx = text.index(text.startIndex, offsetBy: errorRange.location, limitedBy: text.endIndex) else {
            return GeometryResult.unavailable(reason: "Invalid string index")
        }

        let linePrefix = String(text[lineStartIdx..<errorStartIdx])
        let linePrefixWidth = (linePrefix as NSString).size(withAttributes: attrs).width * Self.outlookSpacingMultiplier

        // Calculate error width
        let errorEndIndex = min(errorRange.location + errorRange.length, text.count)
        guard let errorEndIdx = text.index(text.startIndex, offsetBy: errorEndIndex, limitedBy: text.endIndex) else {
            return GeometryResult.unavailable(reason: "Invalid error range")
        }
        let errorText = String(text[errorStartIdx..<errorEndIdx])
        let errorWidth = max((errorText as NSString).size(withAttributes: attrs).width * Self.outlookSpacingMultiplier, 20.0)

        // Calculate Y from line number
        let lineNumber = countNewlines(in: text, before: errorRange.location)
        let lineHeight: CGFloat = 22.0  // Outlook default line height
        let topPadding: CGFloat = 8.0
        let horizontalPadding: CGFloat = 20.0  // Outlook compose has left margin with sparkle icon

        let quartzX = elementFrame.origin.x + horizontalPadding + linePrefixWidth + Self.xAdjustment
        let quartzY = elementFrame.origin.y + topPadding + (CGFloat(lineNumber) * lineHeight) + lineHeight - Self.underlineHeight

        let quartzBounds = CGRect(x: quartzX, y: quartzY, width: errorWidth, height: Self.underlineHeight)

        // Validate
        let elementBottom = elementFrame.origin.y + elementFrame.height
        guard quartzBounds.origin.y >= elementFrame.origin.y - 5 &&
              quartzBounds.origin.y <= elementBottom + 5 else {
            return GeometryResult.unavailable(reason: "Y position outside element bounds")
        }

        // Convert to Cocoa
        let cocoaY = primaryScreenHeight - quartzBounds.origin.y - quartzBounds.height
        let cocoaBounds = CGRect(x: quartzBounds.origin.x, y: cocoaY, width: quartzBounds.width, height: quartzBounds.height)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            return GeometryResult.unavailable(reason: "Invalid final bounds")
        }

        Logger.debug("OutlookStrategy: Body SUCCESS (font-metrics) - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.mediumConfidence,
            strategy: strategyName,
            metadata: [
                "api": "font-metrics-fallback",
                "element_type": "AXTextArea"
            ]
        )
    }

    // MARK: - AX Helpers

    private func getChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        return children
    }

    private func getRole(_ element: AXUIElement) -> String {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return ""
        }
        return role
    }

    private func getText(_ element: AXUIElement) -> String {
        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef) == .success,
              let text = textRef as? String else {
            return ""
        }
        return text
    }

    private func getFrame(_ element: AXUIElement) -> CGRect {
        var frameRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameRef) == .success,
              let fRef = frameRef,
              CFGetTypeID(fRef) == AXValueGetTypeID() else {
            return .zero
        }
        var frame = CGRect.zero
        AXValueGetValue(fRef as! AXValue, .cgRect, &frame)
        return frame
    }

    // MARK: - Line Calculation Helpers

    private func countNewlines(in text: String, before index: Int) -> Int {
        guard index > 0 else { return 0 }
        let searchEnd = min(index, text.count)
        guard let searchEndIdx = text.index(text.startIndex, offsetBy: searchEnd, limitedBy: text.endIndex) else {
            return 0
        }
        let prefix = text[..<searchEndIdx]
        return prefix.filter { $0 == "\n" }.count
    }

    private func findLineStart(in text: String, at index: Int) -> Int {
        guard index > 0 else { return 0 }
        let searchEnd = min(index, text.count)
        guard let searchEndIdx = text.index(text.startIndex, offsetBy: searchEnd, limitedBy: text.endIndex) else {
            return 0
        }
        let prefix = text[..<searchEndIdx]
        if let lastNewline = prefix.lastIndex(of: "\n") {
            return text.distance(from: text.startIndex, to: lastNewline) + 1
        }
        return 0
    }
}
