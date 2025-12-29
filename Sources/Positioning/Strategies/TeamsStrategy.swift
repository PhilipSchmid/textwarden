//
//  TeamsStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Microsoft Teams' WebView2-based chat compose.
//
//  APPROACH:
//  Teams' main AXTextArea doesn't support standard AXBoundsForRange queries (returns garbage).
//  However, child AXStaticText elements DO support AXBoundsForRange with local ranges.
//  This is the exact same pattern as Slack (both are Chromium-based Electron apps).
//
//  Strategy:
//  1. Traverse AX children tree to find all AXStaticText elements (text runs)
//  2. Build a TextPart map: character ranges → visual frames + element references
//  3. For each error, find the overlapping TextPart(s)
//  4. Query AXBoundsForRange on the child element with local range offset
//  5. Return nil on failure to let FontMetricsStrategy handle fallback
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

/// Dedicated Teams positioning using AX tree traversal for bounds
class TeamsStrategy: GeometryProvider {

    var strategyName: String { "Teams" }
    var strategyType: StrategyType { .teams }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 0 }

    private static let teamsBundleID = "com.microsoft.teams2"

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

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        guard bundleID == Self.teamsBundleID else { return false }

        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("TeamsStrategy: Skipping - watchdog protection active", category: Logger.ui)
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

        Logger.trace("TeamsStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let originalRange = NSRange(location: errorRange.location + offset, length: errorRange.length)

        // Get element frame for validation
        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
            Logger.debug("TeamsStrategy: Could not get element frame", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Could not get element frame")
        }

        Logger.trace("TeamsStrategy: Element frame (Quartz): \(elementFrame)", category: Logger.ui)

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
            Logger.trace("TeamsStrategy: Built \(textParts.count) TextParts", category: Logger.ui)
        }

        if textParts.isEmpty {
            Logger.debug("TeamsStrategy: No TextParts found - returning unavailable", category: Logger.ui)
            return GeometryResult.unavailable(reason: "No TextParts found in Teams AX tree")
        }

        // STEP 2: Find TextPart(s) that contain the error range
        guard let bounds = findBoundsForRange(originalRange, in: textParts, fullText: text, element: element) else {
            Logger.debug("TeamsStrategy: Could not find TextPart for range \(originalRange) - returning unavailable", category: Logger.ui)
            return GeometryResult.unavailable(reason: "No TextPart overlapping error range")
        }

        Logger.trace("TeamsStrategy: TextPart bounds (Quartz): \(bounds)", category: Logger.ui)

        // STEP 3: Use full text bounds (not just underline height)
        // This allows the highlight to cover the full word when hovering
        // The overlay will draw the underline at the bottom of these bounds
        let quartzBounds = bounds

        // STEP 4: Validate bounds are within element frame
        // Teams' AXBoundsForRange sometimes returns coordinates for scrolled-out content
        // or in a different coordinate space. Reject these to avoid wrong underlines.
        let elementBottom = elementFrame.origin.y + elementFrame.height
        guard quartzBounds.origin.y >= elementFrame.origin.y - 20 &&
              quartzBounds.origin.y <= elementBottom + 20 &&
              quartzBounds.height > 0 && quartzBounds.height < 100 else {
            Logger.debug("TeamsStrategy: Bounds validation failed - Y=\(quartzBounds.origin.y) not in [\(elementFrame.origin.y)-20, \(elementBottom)+20]", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Bounds outside visible element area")
        }

        // STEP 5: Convert to Cocoa coordinates
        let cocoaY = primaryScreenHeight - quartzBounds.origin.y - quartzBounds.height
        let cocoaBounds = CGRect(
            x: quartzBounds.origin.x,
            y: cocoaY,
            width: quartzBounds.width,
            height: quartzBounds.height
        )

        Logger.trace("TeamsStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("TeamsStrategy: Final bounds validation failed", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Invalid final bounds")
        }

        Logger.debug("TeamsStrategy: SUCCESS (textpart-tree) - bounds: \(cocoaBounds)", category: Logger.ui)

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

    /// Maximum recursion depth for tree traversal (prevents infinite loops)
    private static let maxTreeDepth = 10

    /// Build TextPart map by recursively traversing entire AX tree
    /// Teams uses various nesting for blockquotes, code blocks, etc.
    /// This recursive approach handles arbitrary nesting depths.
    private func buildTextPartMap(from element: AXUIElement, fullText: String) -> [TextPart] {
        var textParts: [TextPart] = []
        var searchStart = 0

        // Recursively collect all AXStaticText elements from the tree
        collectTextParts(from: element, fullText: fullText, searchStart: &searchStart, into: &textParts, depth: 0)

        Logger.trace("TeamsStrategy: Collected \(textParts.count) TextParts from tree", category: Logger.ui)
        return textParts
    }

    /// Recursively traverse AX tree and collect TextParts
    private func collectTextParts(
        from element: AXUIElement,
        fullText: String,
        searchStart: inout Int,
        into textParts: inout [TextPart],
        depth: Int
    ) {
        // Prevent infinite recursion
        guard depth < Self.maxTreeDepth else { return }

        let role = getRole(element)
        let text = getText(element)
        let frame = getFrame(element)

        // If this is an AXStaticText with valid bounds, add it as a TextPart
        if role == "AXStaticText" && !text.isEmpty && frame.width > 0 && frame.height > 0 {
            // Try to find text starting from searchStart
            if let foundRange = findTextRange(text, in: fullText, startingAt: searchStart) {
                textParts.append(TextPart(text: text, range: foundRange, frame: frame, element: element))
                searchStart = foundRange.location + foundRange.length
            }
            // If not found from searchStart, try from beginning (handles out-of-order AX tree)
            else if let foundRange = findTextRange(text, in: fullText, startingAt: 0) {
                // Only add if we haven't already added a TextPart covering this range
                let alreadyCovered = textParts.contains { part in
                    part.range.location == foundRange.location && part.range.length == foundRange.length
                }
                if !alreadyCovered {
                    textParts.append(TextPart(text: text, range: foundRange, frame: frame, element: element))
                }
            }
            // AXStaticText is a leaf - don't recurse further
            return
        }

        // Recurse into children for all container types
        // This handles: AXGroup, AXList, blockquote wrappers, code block wrappers, etc.
        guard let children = getChildren(element) else { return }

        for child in children {
            collectTextParts(from: child, fullText: fullText, searchStart: &searchStart, into: &textParts, depth: depth + 1)
        }
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
            Logger.trace("TeamsStrategy: No TextPart found overlapping range \(targetRange)", category: Logger.ui)
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

        Logger.trace("TeamsStrategy: Unioned \(overlappingParts.count) TextParts for range \(targetRange)", category: Logger.ui)
        return unionBounds
    }

    /// Calculate bounds for error within a single TextPart
    /// Uses AXBoundsForRange on the child element for pixel-perfect positioning
    /// Returns nil if AX query fails - let FontMetricsStrategy handle fallback
    private func calculateSubElementBounds(targetRange: NSRange, in part: TextPart, element: AXUIElement) -> CGRect? {
        let offsetInPart = targetRange.location - part.range.location
        let errorLength = min(targetRange.location + targetRange.length, part.range.location + part.range.length) - targetRange.location

        // Query AXBoundsForRange on the child element directly
        // The local range is relative to the TextPart, not the full text
        if let bounds = getBoundsForRange(location: offsetInPart, length: errorLength, in: part.element) {
            // Validate bounds are reasonable
            if bounds.width > 0 && bounds.height > 0 && bounds.height < 50 {
                Logger.trace("TeamsStrategy: AXBoundsForRange on child SUCCESS: \(bounds)", category: Logger.ui)
                return bounds
            }
        }

        // AXBoundsForRange failed - return nil to let chain continue to FontMetricsStrategy
        Logger.trace("TeamsStrategy: AXBoundsForRange on child failed - letting chain continue", category: Logger.ui)
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
              CFGetTypeID(bv) == AXValueGetTypeID() else {
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
}
