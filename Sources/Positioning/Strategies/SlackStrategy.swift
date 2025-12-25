//
//  SlackStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Slack's Electron-based Quill editor.
//
//  APPROACH:
//  Slack's main AXTextArea doesn't support standard AXBoundsForRange queries (returns garbage).
//  However, child AXStaticText elements DO support AXBoundsForRange with local ranges.
//
//  Strategy:
//  1. Traverse AX children tree to find all AXStaticText elements (text runs)
//  2. Build a TextPart map: character ranges → visual frames + element references
//  3. For each error, find the overlapping TextPart(s)
//  4. Query AXBoundsForRange on the child element with local range offset
//  5. Fall back to font measurement only if AX query fails
//

import AppKit
import ApplicationServices

/// A segment of text with its visual bounds from the AX tree
private struct TextPart {
    let text: String
    let range: NSRange          // Character range in the full text
    let frame: CGRect           // Visual bounds from AXFrame (Quartz coordinates)
    let element: AXUIElement    // Reference to query AXBoundsForRange directly
}

/// Dedicated Slack positioning using AX tree traversal for bounds
class SlackStrategy: GeometryProvider {

    var strategyName: String { "Slack" }
    var strategyType: StrategyType { .slack }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 0 }

    private static let slackBundleID = "com.tinyspeck.slackmacgap"

    // Slack's fixed font size (verified via AXAttributedStringForRange)
    private static let slackFontSize: CGFloat = 15.0

    // Underline visual constants
    private static let underlineHeight: CGFloat = 3.0  // Height for fallback underline rect
    private static let xAdjustment: CGFloat = 0.0      // No adjustment needed - AXBoundsForRange is accurate

    // TextPart cache to avoid rebuilding for each error
    private var cachedTextParts: [TextPart] = []
    private var cachedTextHash: Int = 0
    private var cachedElementFrame: CGRect = .zero

    // MARK: - GeometryProvider

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        guard bundleID == Self.slackBundleID else { return false }

        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("SlackStrategy: Skipping - watchdog protection active", category: Logger.ui)
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

        Logger.debug("SlackStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let originalRange = NSRange(location: errorRange.location + offset, length: errorRange.length)

        // Get element frame for validation
        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
            Logger.debug("SlackStrategy: Could not get element frame", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Could not get element frame")
        }

        Logger.debug("SlackStrategy: Element frame (Quartz): \(elementFrame)", category: Logger.ui)

        // Get PRIMARY screen height for coordinate conversion
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        let primaryScreenHeight = primaryScreen?.frame.height ?? NSScreen.main?.frame.height ?? 1080

        // STEP 1: Get or build TextPart map (cached for performance)
        let textHash = text.hashValue
        let textParts: [TextPart]

        if textHash == cachedTextHash && elementFrame == cachedElementFrame && !cachedTextParts.isEmpty {
            // Use cached TextParts
            textParts = cachedTextParts
        } else {
            // Rebuild TextPart map
            textParts = buildTextPartMap(from: element, fullText: text)
            cachedTextParts = textParts
            cachedTextHash = textHash
            cachedElementFrame = elementFrame
            Logger.debug("SlackStrategy: Built \(textParts.count) TextParts", category: Logger.ui)
        }

        if textParts.isEmpty {
            Logger.debug("SlackStrategy: No TextParts found - falling back to element-based calculation", category: Logger.ui)
            return calculateFallbackGeometry(
                errorRange: originalRange,
                element: element,
                text: text,
                elementFrame: elementFrame,
                primaryScreenHeight: primaryScreenHeight
            )
        }

        // STEP 2: Find TextPart(s) that contain the error range
        guard let bounds = findBoundsForRange(originalRange, in: textParts, fullText: text, element: element) else {
            Logger.debug("SlackStrategy: Could not find TextPart for range \(originalRange)", category: Logger.ui)
            return calculateFallbackGeometry(
                errorRange: originalRange,
                element: element,
                text: text,
                elementFrame: elementFrame,
                primaryScreenHeight: primaryScreenHeight
            )
        }

        Logger.debug("SlackStrategy: TextPart bounds (Quartz): \(bounds)", category: Logger.ui)

        // STEP 3: Use full text bounds (not just underline height)
        // This allows the highlight to cover the full word when hovering
        // The overlay will draw the underline at the bottom of these bounds
        let quartzBounds = CGRect(
            x: bounds.origin.x + Self.xAdjustment,
            y: bounds.origin.y,
            width: bounds.width,
            height: bounds.height
        )

        // STEP 4: Validate bounds are within element
        let elementBottom = elementFrame.origin.y + elementFrame.height
        guard quartzBounds.origin.y >= elementFrame.origin.y - 10 &&
              quartzBounds.origin.y <= elementBottom + 10 else {
            Logger.debug("SlackStrategy: Bounds Y \(quartzBounds.origin.y) outside element (\(elementFrame.origin.y) to \(elementBottom))", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Y position outside element bounds")
        }

        // STEP 5: Convert to Cocoa coordinates
        let cocoaY = primaryScreenHeight - quartzBounds.origin.y - quartzBounds.height
        let cocoaBounds = CGRect(
            x: quartzBounds.origin.x,
            y: cocoaY,
            width: quartzBounds.width,
            height: quartzBounds.height
        )

        Logger.debug("SlackStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("SlackStrategy: Final bounds validation failed", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Invalid final bounds")
        }

        Logger.debug("SlackStrategy: SUCCESS (textpart-tree) - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: [
                "api": "textpart-tree",
                "textparts": "\(textParts.count)"
            ]
        )
    }

    // MARK: - TextPart Tree Building

    /// Build TextPart map by traversing AX children
    /// Slack's editor has: AXTextArea (root) → AXGroup (paragraphs) → AXStaticText/AXGroup (text runs)
    /// Uses string search to find exact positions instead of manual offset tracking
    private func buildTextPartMap(from element: AXUIElement, fullText: String) -> [TextPart] {
        var textParts: [TextPart] = []
        var searchStart = 0  // Where to start searching for next TextPart

        // Get children (paragraphs/lines)
        guard let paragraphs = getChildren(element) else {
            return []
        }

        for paragraph in paragraphs {
            // Get grandchildren (text runs within this paragraph)
            guard let textRuns = getChildren(paragraph) else {
                // Paragraph might have text directly
                let paragraphText = getText(paragraph)
                if !paragraphText.isEmpty {
                    let frame = getFrame(paragraph)
                    if frame.width > 0 && frame.height > 0 {
                        if let foundRange = findTextRange(paragraphText, in: fullText, startingAt: searchStart) {
                            textParts.append(TextPart(text: paragraphText, range: foundRange, frame: frame, element: paragraph))
                            searchStart = foundRange.location + foundRange.length
                        }
                    }
                }
                continue
            }

            for textRun in textRuns {
                let role = getRole(textRun)
                let frame = getFrame(textRun)
                let runText = getText(textRun)

                if role == "AXStaticText" && !runText.isEmpty && frame.width > 0 && frame.height > 0 {
                    // Direct text run - find its position by string search
                    if let foundRange = findTextRange(runText, in: fullText, startingAt: searchStart) {
                        textParts.append(TextPart(text: runText, range: foundRange, frame: frame, element: textRun))
                        searchStart = foundRange.location + foundRange.length
                    }
                } else if role == "AXGroup" {
                    // Could be formatting group (bold, italic, code) - check for text inside
                    if let nestedRuns = getChildren(textRun) {
                        for nestedRun in nestedRuns {
                            let nestedRole = getRole(nestedRun)
                            let nestedFrame = getFrame(nestedRun)
                            let nestedText = getText(nestedRun)

                            if nestedRole == "AXStaticText" && !nestedText.isEmpty &&
                               nestedFrame.width > 0 && nestedFrame.height > 0 {
                                if let foundRange = findTextRange(nestedText, in: fullText, startingAt: searchStart) {
                                    textParts.append(TextPart(text: nestedText, range: foundRange, frame: nestedFrame, element: nestedRun))
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
    /// For multi-TextPart errors, unions overlapping bounds
    private func findBoundsForRange(_ targetRange: NSRange, in textParts: [TextPart], fullText: String, element: AXUIElement) -> CGRect? {
        let targetEnd = targetRange.location + targetRange.length

        // Find ALL TextParts that overlap with the error range
        let overlappingParts = textParts.filter { part in
            let partEnd = part.range.location + part.range.length
            // Check for overlap
            return targetRange.location < partEnd && targetEnd > part.range.location
        }

        if overlappingParts.isEmpty {
            Logger.debug("SlackStrategy: No TextPart found overlapping range \(targetRange)", category: Logger.ui)
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

        Logger.debug("SlackStrategy: Unioned \(overlappingParts.count) TextParts for range \(targetRange)", category: Logger.ui)
        return unionBounds
    }

    /// Calculate bounds for error within a single TextPart
    /// Uses AXBoundsForRange on the child element for pixel-perfect positioning
    /// Falls back to font measurement if the API call fails
    private func calculateSubElementBounds(targetRange: NSRange, in part: TextPart, element: AXUIElement) -> CGRect {
        let offsetInPart = targetRange.location - part.range.location
        let errorLength = min(targetRange.location + targetRange.length, part.range.location + part.range.length) - targetRange.location

        // Query AXBoundsForRange on the child element directly
        // The local range is relative to the TextPart, not the full text
        if let bounds = getBoundsForRange(location: offsetInPart, length: errorLength, in: part.element) {
            // Validate bounds are reasonable
            if bounds.width > 0 && bounds.height > 0 && bounds.height < 50 {
                Logger.debug("SlackStrategy: AXBoundsForRange on child SUCCESS: \(bounds)", category: Logger.ui)
                return bounds
            }
        }

        // Fallback: use font measurement (should rarely be needed now)
        Logger.debug("SlackStrategy: AXBoundsForRange failed, falling back to font measurement", category: Logger.ui)
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

    // Font measurement fallback - used when AXBoundsForRange fails
    private static let fontScaleFactor: CGFloat = 0.97

    /// Fallback calculation using font measurement
    private func calculateSubElementBoundsWithFontMeasurement(
        offsetInPart: Int,
        errorLength: Int,
        part: TextPart
    ) -> CGRect {
        let font = NSFont.systemFont(ofSize: Self.slackFontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        // Calculate X offset using font measurement with fixed scale factor
        let textBeforeError: String
        if let startIdx = part.text.index(part.text.startIndex, offsetBy: offsetInPart, limitedBy: part.text.endIndex) {
            textBeforeError = String(part.text[..<startIdx])
        } else {
            textBeforeError = ""
        }
        let measuredXOffset = (textBeforeError as NSString).size(withAttributes: attrs).width
        let xOffset = measuredXOffset * Self.fontScaleFactor

        // Calculate error width similarly
        let errorText: String
        if let startIdx = part.text.index(part.text.startIndex, offsetBy: offsetInPart, limitedBy: part.text.endIndex),
           let endIdx = part.text.index(part.text.startIndex, offsetBy: min(offsetInPart + errorLength, part.text.count), limitedBy: part.text.endIndex) {
            errorText = String(part.text[startIdx..<endIdx])
        } else {
            errorText = ""
        }
        let measuredErrorWidth = (errorText as NSString).size(withAttributes: attrs).width
        let errorWidth = max(measuredErrorWidth * Self.fontScaleFactor, 20.0)

        Logger.debug("SlackStrategy: Font measurement fallback - offset=\(offsetInPart) xOffset=\(String(format: "%.1f", xOffset))", category: Logger.ui)

        return CGRect(
            x: part.frame.origin.x + xOffset,
            y: part.frame.origin.y,
            width: errorWidth,
            height: part.frame.height
        )
    }

    // MARK: - Fallback Calculation

    /// Fallback when TextPart tree traversal fails (e.g., empty editor)
    private func calculateFallbackGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        elementFrame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> GeometryResult? {

        let font = NSFont.systemFont(ofSize: Self.slackFontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        // Find line start for X calculation
        let lineStartIndex = findLineStart(in: text, at: errorRange.location)

        guard let lineStartIdx = text.index(text.startIndex, offsetBy: lineStartIndex, limitedBy: text.endIndex),
              let errorStartIdx = text.index(text.startIndex, offsetBy: errorRange.location, limitedBy: text.endIndex) else {
            return GeometryResult.unavailable(reason: "Invalid string index")
        }

        let linePrefix = String(text[lineStartIdx..<errorStartIdx])
        let linePrefixWidth = (linePrefix as NSString).size(withAttributes: attrs).width

        // Calculate error width
        let errorEndIndex = min(errorRange.location + errorRange.length, text.count)
        guard let errorEndIdx = text.index(text.startIndex, offsetBy: errorEndIndex, limitedBy: text.endIndex) else {
            return GeometryResult.unavailable(reason: "Invalid error range")
        }
        let errorText = String(text[errorStartIdx..<errorEndIdx])
        let errorWidth = max((errorText as NSString).size(withAttributes: attrs).width, 20.0)

        // Calculate Y from line number
        let lineNumber = countNewlines(in: text, before: errorRange.location)
        let lineHeight: CGFloat = 22.0
        let topPadding: CGFloat = 8.0

        let quartzX = elementFrame.origin.x + linePrefixWidth + Self.xAdjustment
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

        Logger.debug("SlackStrategy: SUCCESS (fallback) - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.mediumConfidence,
            strategy: strategyName,
            metadata: ["api": "calculated-fallback"]
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
