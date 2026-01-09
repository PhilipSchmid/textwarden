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
//  5. Return nil on failure to let FontMetricsStrategy handle fallback via ContentParser config
//

import AppKit
import ApplicationServices

/// A segment of text with its visual bounds from the AX tree
private struct TextPart: BoundedTextPart {
    let text: String
    let range: NSRange // Character range in the full text
    let frame: CGRect // Visual bounds from AXFrame (Quartz coordinates)
    let element: AXUIElement // Reference to query AXBoundsForRange directly
}

/// Dedicated Slack positioning using AX tree traversal for bounds
class SlackStrategy: GeometryProvider {
    var strategyName: String { "Slack" }
    var strategyType: StrategyType { .slack }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 0 }

    private static let slackBundleID = "com.tinyspeck.slackmacgap"

    // TextPart cache to avoid rebuilding for each error
    private var cachedTextParts: [TextPart] = []
    private var cachedTextHash: Int = 0
    private var cachedElementFrame: CGRect = .zero

    // MARK: - Cache Management

    /// Clear internal cache (called when formatting changes)
    func clearInternalCache() {
        cachedTextParts = []
        cachedTextHash = 0
        cachedElementFrame = .zero
    }

    // MARK: - GeometryProvider

    func canHandle(element _: AXUIElement, bundleID: String) -> Bool {
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

        if textHash == cachedTextHash, elementFrame == cachedElementFrame, !cachedTextParts.isEmpty {
            // Use cached TextParts
            textParts = cachedTextParts
        } else {
            // Rebuild TextPart map
            textParts = buildTextPartMap(from: element, fullText: text)
            cachedTextParts = textParts
            cachedTextHash = textHash
            cachedElementFrame = elementFrame
            Logger.debug("SlackStrategy: Built \(textParts.count) TextParts", category: Logger.ui)
            // Log each TextPart's range for debugging coverage gaps
            for (idx, part) in textParts.enumerated() {
                Logger.trace("SlackStrategy: TextPart[\(idx)] range=\(part.range) text=\"\(part.text.prefix(30))...\"", category: Logger.ui)
            }
        }

        if textParts.isEmpty {
            Logger.debug("SlackStrategy: No TextParts found - letting chain continue to FontMetricsStrategy", category: Logger.ui)
            return nil
        }

        // Log TextPart coverage for debugging
        if !textParts.isEmpty {
            let minPos = textParts.map(\.range.location).min() ?? 0
            let maxPos = textParts.map { $0.range.location + $0.range.length }.max() ?? 0
            Logger.debug("SlackStrategy: TextParts cover range \(minPos)-\(maxPos), target: \(originalRange)", category: Logger.ui)
        }

        // STEP 2: Find TextPart(s) that contain the error range
        guard let bounds = findBoundsForRange(originalRange, in: textParts, fullText: text, element: element) else {
            Logger.debug("SlackStrategy: Could not find TextPart for range \(originalRange) - letting chain continue", category: Logger.ui)
            return nil
        }

        Logger.debug("SlackStrategy: TextPart bounds (Quartz): \(bounds)", category: Logger.ui)

        // STEP 3: Use full text bounds (not just underline height)
        // This allows the highlight to cover the full word when hovering
        // The overlay will draw the underline at the bottom of these bounds
        let quartzBounds = bounds

        // STEP 4: Validate bounds are within element
        let elementBottom = elementFrame.origin.y + elementFrame.height
        guard quartzBounds.origin.y >= elementFrame.origin.y - 10,
              quartzBounds.origin.y <= elementBottom + 10
        else {
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
                "textparts": "\(textParts.count)",
            ]
        )
    }

    // MARK: - TextPart Tree Building

    /// Build TextPart map by traversing AX children recursively
    /// Slack's editor has: AXTextArea (root) → AXGroup (paragraphs) → AXStaticText/AXGroup/AXLink (text runs)
    /// Uses string search to find exact positions instead of manual offset tracking
    private func buildTextPartMap(from element: AXUIElement, fullText: String) -> [TextPart] {
        var textParts: [TextPart] = []
        var searchStart = 0 // Where to start searching for next TextPart

        // Recursively collect all text parts from the AX tree
        collectTextParts(
            from: element,
            fullText: fullText,
            searchStart: &searchStart,
            textParts: &textParts,
            depth: 0
        )

        // Check for gaps in coverage and log them
        logCoverageGaps(textParts: textParts, fullTextLength: fullText.count)

        return textParts
    }

    /// Recursively collect TextParts from an element and its children
    /// Handles arbitrary nesting depth and various element types (AXStaticText, AXGroup, AXLink, AXButton)
    private func collectTextParts(
        from element: AXUIElement,
        fullText: String,
        searchStart: inout Int,
        textParts: inout [TextPart],
        depth: Int
    ) {
        // Prevent infinite recursion
        guard depth < 10 else {
            Logger.trace("SlackStrategy: Max depth reached at level \(depth)", category: Logger.ui)
            return
        }

        // Get children of this element
        guard let children = getChildren(element) else {
            // No children - check if this element itself has text
            let text = getText(element)
            let frame = getFrame(element)
            if !text.isEmpty, frame.width > 0, frame.height > 0 {
                if let foundRange = findTextRange(text, in: fullText, startingAt: searchStart) {
                    textParts.append(TextPart(text: text, range: foundRange, frame: frame, element: element))
                    searchStart = foundRange.location + foundRange.length
                }
            }
            return
        }

        for child in children {
            let role = getRole(child)
            let frame = getFrame(child)
            let text = getText(child)

            // Check if this is a text-bearing element
            let isTextElement = role == "AXStaticText"
            let isContainerElement = role == "AXGroup" || role == "AXLink" || role == "AXButton"

            if isTextElement, !text.isEmpty, frame.width > 0, frame.height > 0 {
                // Direct text element - add it
                if let foundRange = findTextRange(text, in: fullText, startingAt: searchStart) {
                    textParts.append(TextPart(text: text, range: foundRange, frame: frame, element: child))
                    searchStart = foundRange.location + foundRange.length
                } else {
                    // Text not found at expected position - try searching from beginning
                    // This handles cases where AX tree order doesn't match visual order
                    // (common with mentions, links, and formatted text in Slack)
                    if let foundRange = findTextRange(text, in: fullText, startingAt: 0) {
                        // Only add if this range isn't already covered by another TextPart
                        let alreadyCovered = textParts.contains { part in
                            part.range.location <= foundRange.location &&
                                part.range.location + part.range.length >= foundRange.location + foundRange.length
                        }
                        if !alreadyCovered {
                            textParts.append(TextPart(text: text, range: foundRange, frame: frame, element: child))
                            Logger.trace("SlackStrategy: Found text '\(text.prefix(20))...' at \(foundRange.location) (out of order)", category: Logger.ui)
                        }
                    }
                }
            } else if isContainerElement {
                // Container element - recurse into it
                // But first check if it has text directly (some AXGroup elements have AXValue)
                if !text.isEmpty, frame.width > 0, frame.height > 0 {
                    if let foundRange = findTextRange(text, in: fullText, startingAt: searchStart) {
                        textParts.append(TextPart(text: text, range: foundRange, frame: frame, element: child))
                        searchStart = foundRange.location + foundRange.length
                    }
                }
                // Recurse into children
                collectTextParts(
                    from: child,
                    fullText: fullText,
                    searchStart: &searchStart,
                    textParts: &textParts,
                    depth: depth + 1
                )
            }
        }
    }

    /// Log any gaps in TextPart coverage for debugging
    private func logCoverageGaps(textParts: [TextPart], fullTextLength: Int) {
        guard !textParts.isEmpty else { return }

        // Sort by position
        let sorted = textParts.sorted { $0.range.location < $1.range.location }

        var gaps: [(start: Int, end: Int)] = []
        var lastEnd = 0

        for part in sorted {
            if part.range.location > lastEnd {
                gaps.append((start: lastEnd, end: part.range.location))
            }
            lastEnd = max(lastEnd, part.range.location + part.range.length)
        }

        // Check for gap at the end
        if lastEnd < fullTextLength {
            gaps.append((start: lastEnd, end: fullTextLength))
        }

        // Log significant gaps (more than just whitespace)
        for gap in gaps where gap.end - gap.start > 10 {
            Logger.warning("SlackStrategy: Coverage gap \(gap.start)-\(gap.end) (\(gap.end - gap.start) chars)", category: Logger.ui)
        }
    }

    /// Find the range of a substring starting from a given position
    private func findTextRange(_ substring: String, in text: String, startingAt: Int) -> NSRange? {
        guard startingAt < text.count else { return nil }
        guard let searchStartIdx = text.index(text.startIndex, offsetBy: startingAt, limitedBy: text.endIndex) else {
            return nil
        }

        let searchRange = searchStartIdx ..< text.endIndex
        if let foundRange = text.range(of: substring, range: searchRange) {
            let location = text.distance(from: text.startIndex, to: foundRange.lowerBound)
            return NSRange(location: location, length: substring.count)
        }

        return nil
    }

    // MARK: - Bounds Lookup

    /// Find visual bounds for a character range using TextPart map
    /// For multi-TextPart errors, unions overlapping bounds
    private func findBoundsForRange(_ targetRange: NSRange, in textParts: [TextPart], fullText _: String, element: AXUIElement) -> CGRect? {
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

        // Multiple overlapping parts: use shared utility for correct sub-element bounds calculation
        let unionBounds = TextPartBoundsCalculator.calculateMultiPartBounds(
            targetRange: targetRange,
            overlappingParts: overlappingParts,
            getBoundsForRange: getBoundsForRange
        )

        Logger.debug("SlackStrategy: Calculated sub-bounds for \(overlappingParts.count) TextParts for range \(targetRange)", category: Logger.ui)
        return unionBounds
    }

    /// Calculate bounds for error within a single TextPart
    /// Uses AXBoundsForRange on the child element for pixel-perfect positioning
    /// Returns nil if AX query fails - let FontMetricsStrategy handle fallback
    private func calculateSubElementBounds(targetRange: NSRange, in part: TextPart, element _: AXUIElement) -> CGRect? {
        let offsetInPart = targetRange.location - part.range.location
        let errorLength = min(targetRange.location + targetRange.length, part.range.location + part.range.length) - targetRange.location

        // Query AXBoundsForRange on the child element directly
        // The local range is relative to the TextPart, not the full text
        if let bounds = getBoundsForRange(location: offsetInPart, length: errorLength, in: part.element) {
            // Validate bounds are reasonable for single-line text
            // Chromium's AXBoundsForRange can return multi-line bounds for ranges in large TextParts
            let isSingleLineHeight = bounds.height > 0 && bounds.height <= 30 // Single line text is ~19px at 15pt
            let isReasonableWidth = bounds.width > 0 && bounds.width <= CGFloat(errorLength) * 20 // ~20px max per char

            if isSingleLineHeight, isReasonableWidth {
                Logger.debug("SlackStrategy: AXBoundsForRange on child SUCCESS: \(bounds)", category: Logger.ui)
                return bounds
            } else {
                Logger.debug("SlackStrategy: AXBoundsForRange returned suspicious multi-line bounds (h=\(bounds.height), w=\(bounds.width) for \(errorLength) chars) - rejecting", category: Logger.ui)
            }
        }

        // AXBoundsForRange failed or returned invalid bounds - return nil to let chain continue
        Logger.debug("SlackStrategy: AXBoundsForRange on child failed - letting chain continue", category: Logger.ui)
        return nil
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
              CFGetTypeID(bv) == AXValueGetTypeID()
        else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &bounds) else {
            return nil
        }

        return bounds
    }

    // MARK: - AX Helpers

    private func getChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }
        return children
    }

    private func getRole(_ element: AXUIElement) -> String {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String
        else {
            return ""
        }
        return role
    }

    private func getText(_ element: AXUIElement) -> String {
        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef) == .success,
              let text = textRef as? String
        else {
            return ""
        }
        return text
    }

    private func getFrame(_ element: AXUIElement) -> CGRect {
        var frameRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameRef) == .success,
              let fRef = frameRef,
              CFGetTypeID(fRef) == AXValueGetTypeID()
        else {
            return .zero
        }
        var frame = CGRect.zero
        AXValueGetValue(fRef as! AXValue, .cgRect, &frame)
        return frame
    }
}
