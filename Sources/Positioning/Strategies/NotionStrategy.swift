//
//  NotionStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Notion's Electron-based editor.
//
//  APPROACH:
//  Notion's main AXTextArea doesn't support standard AXBoundsForRange queries (returns 0,y,0,0).
//  However, child AXStaticText elements DO support AXBoundsForRange with local ranges.
//  This is the exact same pattern as Slack and Teams (all Chromium-based Electron apps).
//
//  Strategy:
//  1. Traverse AX children tree to find all AXStaticText elements (text runs)
//  2. Build a TextPart map: character ranges → visual frames + element references
//  3. For each error, find the overlapping TextPart(s)
//  4. Query AXBoundsForRange on the child element with local range offset
//  5. Return nil on failure to let other strategies handle fallback
//
//  Key insight from diagnostic:
//  - Parent AXTextArea returns (0, y, 0, 0) - broken
//  - Child AXStaticText returns valid bounds like (951, 404, 38, 19) - works!
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

/// Dedicated Notion positioning using AX tree traversal for bounds
class NotionStrategy: GeometryProvider {
    var strategyName: String { "Notion" }
    var strategyType: StrategyType { .notion }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 0 }

    private static let notionBundleIDs = ["notion.id", "com.notion.id", "com.notion.desktop"]

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
        guard Self.notionBundleIDs.contains(bundleID) else { return false }

        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("NotionStrategy: Skipping - watchdog protection active", category: Logger.ui)
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
        Logger.trace("NotionStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        // NotionContentParser filters UI elements and stores the offset
        let offset = parser.textReplacementOffset
        let originalRange = NSRange(location: errorRange.location + offset, length: errorRange.length)

        // Debug: Extract error text from filtered text to verify position
        let filteredScalars = text.unicodeScalars
        if errorRange.location < filteredScalars.count,
           let startIdx = filteredScalars.index(filteredScalars.startIndex, offsetBy: errorRange.location, limitedBy: filteredScalars.endIndex),
           let endIdx = filteredScalars.index(startIdx, offsetBy: min(errorRange.length, 10), limitedBy: filteredScalars.endIndex),
           let strStart = String.Index(startIdx, within: text),
           let strEnd = String.Index(endIdx, within: text)
        {
            let errorText = String(text[strStart ..< strEnd])
            Logger.debug("NotionStrategy: Error '\(errorText)' at filtered pos \(errorRange.location), offset=\(offset), original pos=\(originalRange.location)", category: Logger.ui)
        }

        // Get element frame for validation
        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
            Logger.debug("NotionStrategy: Could not get element frame", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Could not get element frame")
        }

        Logger.trace("NotionStrategy: Element frame (Quartz): \(elementFrame)", category: Logger.ui)

        // Get PRIMARY screen height for coordinate conversion
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        let primaryScreenHeight = primaryScreen?.frame.height ?? NSScreen.main?.frame.height ?? 1080

        // Get full (unfiltered) text from element for TextPart mapping
        let fullText = getFullTextFromElement(element) ?? text

        // STEP 1: Get or build TextPart map (cached for performance)
        let textHash = fullText.hashValue
        let textParts: [TextPart]

        if textHash == cachedTextHash, elementFrame == cachedElementFrame, !cachedTextParts.isEmpty {
            // Use cached TextParts
            textParts = cachedTextParts
        } else {
            // Rebuild TextPart map
            textParts = buildTextPartMap(from: element, fullText: fullText)
            cachedTextParts = textParts
            cachedTextHash = textHash
            cachedElementFrame = elementFrame
            Logger.debug("NotionStrategy: Built \(textParts.count) TextParts", category: Logger.ui)
        }

        if textParts.isEmpty {
            Logger.debug("NotionStrategy: No TextParts found - allowing fallback strategies", category: Logger.ui)
            return nil // Return nil to allow fallback strategies to try
        }

        // STEP 2: Find TextPart(s) that contain the error range
        let bounds: CGRect

        if let textPartBounds = findBoundsForRange(originalRange, in: textParts, fullText: fullText, element: element) {
            bounds = textPartBounds
        } else {
            // TextPart not found - this block is "virtualized" by Notion (exists in text but no AX child)
            //
            // UX DECISION: Don't draw underlines for virtualized blocks.
            // Interpolated positions are often visibly wrong (10-20px off), which looks broken.
            // Instead, we return nil here so:
            // - No underline is drawn for this error
            // - The error still appears in the error indicator count
            // - Users can still fix it via the error menu
            //
            // This is better UX than showing mispositioned underlines that confuse users.
            Logger.debug("NotionStrategy: No TextPart for range \(originalRange) - block is virtualized, skipping underline (error still in indicator)", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Block virtualized - no AX child element")
        }

        Logger.trace("NotionStrategy: TextPart bounds (Quartz): \(bounds)", category: Logger.ui)

        // STEP 3: Validate bounds are within element frame
        // Notion's AXBoundsForRange sometimes returns coordinates for scrolled-out content
        let elementBottom = elementFrame.origin.y + elementFrame.height
        guard bounds.origin.y >= elementFrame.origin.y - 50,
              bounds.origin.y <= elementBottom + 50,
              bounds.width > 0, bounds.height > 0, bounds.height < 100
        else {
            Logger.debug("NotionStrategy: Bounds validation failed - bounds=\(bounds), elementFrame=\(elementFrame)", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Bounds outside visible element area")
        }

        // STEP 4: Convert to Cocoa coordinates
        let cocoaY = primaryScreenHeight - bounds.origin.y - bounds.height
        let cocoaBounds = CGRect(
            x: bounds.origin.x,
            y: cocoaY,
            width: bounds.width,
            height: bounds.height
        )

        Logger.trace("NotionStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("NotionStrategy: Final bounds validation failed", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Invalid final bounds")
        }

        Logger.debug("NotionStrategy: SUCCESS (textpart-tree) - bounds: \(cocoaBounds)", category: Logger.ui)

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

    /// Maximum recursion depth for tree traversal (prevents infinite loops)
    private static let maxTreeDepth = 15 // Notion has deeper nesting than Teams

    /// Build TextPart map by recursively traversing entire AX tree
    /// Notion uses various nesting for blocks, headers, callouts, etc.
    private func buildTextPartMap(from element: AXUIElement, fullText: String) -> [TextPart] {
        var textParts: [TextPart] = []
        var searchStart = 0

        // Recursively collect all AXStaticText elements from the tree
        collectTextParts(from: element, fullText: fullText, searchStart: &searchStart, into: &textParts, depth: 0)

        Logger.trace("NotionStrategy: Collected \(textParts.count) TextParts from tree", category: Logger.ui)
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
        guard depth < Self.maxTreeDepth else {
            Logger.debug("NotionStrategy: Max depth \(Self.maxTreeDepth) reached", category: Logger.ui)
            return
        }

        let role = getRole(element)
        let text = getText(element)
        let frame = getFrame(element)

        // Log all elements we visit for debugging
        if !text.isEmpty, text.count < 100 {
            Logger.trace("NotionStrategy: [depth=\(depth)] role=\(role), text='\(text.prefix(30))...', frame=\(frame)", category: Logger.ui)
        }

        // If this is an AXStaticText with valid bounds, add it as a TextPart
        // INCLUDE whitespace-only text like "  " - they have valid Y positions for interpolation anchors!
        if role == "AXStaticText" {
            // Log why we might skip this element
            if frame.width <= 0 || frame.height <= 0 {
                Logger.trace("NotionStrategy: Skipping AXStaticText '\(text.prefix(20))...' - invalid frame: \(frame)", category: Logger.ui)
            } else if frame.height >= 150 {
                Logger.trace("NotionStrategy: Skipping AXStaticText '\(text.prefix(20))...' - frame too tall: \(frame.height)", category: Logger.ui)
            } else if text.isEmpty {
                Logger.trace("NotionStrategy: Skipping AXStaticText - completely empty text", category: Logger.ui)
            } else {
                // Valid AXStaticText - try to find in fullText
                if let foundRange = findTextRange(text, in: fullText, startingAt: searchStart) {
                    textParts.append(TextPart(text: text, range: foundRange, frame: frame, element: element))
                    searchStart = foundRange.location + foundRange.length
                    Logger.trace("NotionStrategy: Found TextPart '\(text.prefix(20))...' at range \(foundRange)", category: Logger.ui)
                }
                // If not found from searchStart, try from beginning (handles out-of-order AX tree)
                else if let foundRange = findTextRange(text, in: fullText, startingAt: 0) {
                    // Only add if we haven't already added a TextPart covering this range
                    let alreadyCovered = textParts.contains { part in
                        part.range.location == foundRange.location && part.range.length == foundRange.length
                    }
                    if !alreadyCovered {
                        textParts.append(TextPart(text: text, range: foundRange, frame: frame, element: element))
                        Logger.trace("NotionStrategy: Found TextPart '\(text.prefix(20))...' at range \(foundRange) (from start)", category: Logger.ui)
                    }
                } else {
                    // Text not found in fullText - log for debugging
                    Logger.debug("NotionStrategy: AXStaticText '\(text.prefix(30))...' NOT FOUND in fullText (searchStart=\(searchStart))", category: Logger.ui)
                }
            }
            // AXStaticText is a leaf - don't recurse further
            return
        }

        // Recurse into children for all container types
        // This handles: AXGroup, AXTextArea (heading/text entry area), etc.
        guard let children = getChildren(element) else {
            if depth < 3 {
                Logger.trace("NotionStrategy: [depth=\(depth)] role=\(role) has no children", category: Logger.ui)
            }
            return
        }

        for child in children {
            collectTextParts(from: child, fullText: fullText, searchStart: &searchStart, into: &textParts, depth: depth + 1)
        }
    }

    /// Find the range of a substring starting from a given position.
    /// Returns Unicode scalar positions to match Harper's error positions.
    private func findTextRange(_ substring: String, in text: String, startingAt: Int) -> NSRange? {
        let scalars = text.unicodeScalars
        guard startingAt < scalars.count,
              let searchStartScalarIdx = scalars.index(scalars.startIndex, offsetBy: startingAt, limitedBy: scalars.endIndex)
        else {
            return nil
        }

        // Convert scalar index to String.Index for range search
        guard let searchStartIdx = String.Index(searchStartScalarIdx, within: text) else {
            return nil
        }

        let searchRange = searchStartIdx ..< text.endIndex
        if let foundRange = text.range(of: substring, range: searchRange) {
            // Convert found range to Unicode scalar positions
            let foundScalarIdx = foundRange.lowerBound.samePosition(in: scalars) ?? scalars.startIndex
            let location = scalars.distance(from: scalars.startIndex, to: foundScalarIdx)
            let length = substring.unicodeScalars.count
            return NSRange(location: location, length: length)
        }

        return nil
    }

    // MARK: - Bounds Lookup

    /// Find visual bounds for a character range using TextPart map
    /// For multi-TextPart errors, unions overlapping bounds
    private func findBoundsForRange(_ targetRange: NSRange, in textParts: [TextPart], fullText _: String, element _: AXUIElement) -> CGRect? {
        let targetEnd = targetRange.location + targetRange.length

        // Find TextParts that CONTAIN the error range (error starts within TextPart)
        // This is stricter than just "overlap" - the error must start at or after the TextPart start
        let containingParts = textParts.filter { part in
            let partEnd = part.range.location + part.range.length
            // Error must start within this TextPart (not before it)
            return targetRange.location >= part.range.location && targetRange.location < partEnd
        }

        if containingParts.isEmpty {
            // Also check for partial overlap where error spans multiple TextParts
            let overlappingParts = textParts.filter { part in
                let partEnd = part.range.location + part.range.length
                return targetRange.location < partEnd && targetEnd > part.range.location
            }

            if !overlappingParts.isEmpty {
                Logger.trace("NotionStrategy: Error \(targetRange) partially overlaps \(overlappingParts.count) TextParts but doesn't start in any", category: Logger.ui)
            } else {
                Logger.trace("NotionStrategy: No TextPart found overlapping range \(targetRange)", category: Logger.ui)
            }
            return nil
        }

        // If error starts in one TextPart, calculate sub-element position
        if containingParts.count == 1 {
            let part = containingParts[0]
            if let bounds = calculateSubElementBounds(targetRange: targetRange, in: part) {
                return bounds
            }
            // If calculateSubElementBounds returned nil (e.g., negative offset), try fallback
            return nil
        }

        // Multiple containing parts: use shared utility for correct sub-element bounds calculation
        let unionBounds = TextPartBoundsCalculator.calculateMultiPartBounds(
            targetRange: targetRange,
            overlappingParts: containingParts,
            getBoundsForRange: getBoundsForRange
        )

        Logger.trace("NotionStrategy: Calculated sub-bounds for \(containingParts.count) TextParts for range \(targetRange)", category: Logger.ui)
        return unionBounds
    }

    /// Calculate bounds for error within a single TextPart
    /// Uses AXBoundsForRange on the child element for pixel-perfect positioning
    private func calculateSubElementBounds(targetRange: NSRange, in part: TextPart) -> CGRect? {
        // Calculate Unicode scalar offsets within the TextPart
        // Both targetRange and part.range are in Unicode scalars (matching Harper's positions)
        let scalarOffsetInPart = targetRange.location - part.range.location
        let scalarLength = min(targetRange.location + targetRange.length, part.range.location + part.range.length) - targetRange.location

        // SAFETY CHECK: Ensure offset is non-negative
        // A negative offset means the error starts BEFORE this TextPart - this is a matching bug
        guard scalarOffsetInPart >= 0 else {
            Logger.warning("NotionStrategy: Negative scalar offset \(scalarOffsetInPart) - error range \(targetRange) doesn't match TextPart range \(part.range)", category: Logger.ui)
            return nil // Return nil to try next TextPart or fallback
        }

        // Also ensure the error actually overlaps with this TextPart's content
        let partScalarCount = part.text.unicodeScalars.count
        guard scalarOffsetInPart < partScalarCount else {
            Logger.trace("NotionStrategy: Scalar offset \(scalarOffsetInPart) beyond TextPart length \(partScalarCount)", category: Logger.ui)
            return nil
        }

        // Debug: Show what character we're starting at within the TextPart
        let scalars = part.text.unicodeScalars
        if let startScalarIdx = scalars.index(scalars.startIndex, offsetBy: scalarOffsetInPart, limitedBy: scalars.endIndex),
           let strIdx = String.Index(startScalarIdx, within: part.text)
        {
            let charAtOffset = String(part.text[strIdx...].prefix(1))
            Logger.debug("NotionStrategy: TextPart '\(part.text.prefix(15))...' range=\(part.range), offset=\(scalarOffsetInPart) -> char '\(charAtOffset)'", category: Logger.ui)
        }

        // CRITICAL: Convert Unicode scalar indices to UTF-16 code unit indices
        // Harper uses Unicode scalars, macOS accessibility APIs use UTF-16 code units
        // This is essential for text containing emojis (e.g., 💪🏼 = 2 scalars but 4 UTF-16 units)
        let scalarRange = NSRange(location: scalarOffsetInPart, length: scalarLength)
        let utf16Range = TextIndexConverter.scalarToUTF16Range(scalarRange, in: part.text)

        Logger.debug("NotionStrategy: scalarRange=\(scalarRange) -> utf16Range=\(utf16Range)", category: Logger.ui)

        // Query AXBoundsForRange on the child element directly
        // The local range is relative to the TextPart text, in UTF-16 code units
        if let bounds = getBoundsForRange(location: utf16Range.location, length: utf16Range.length, in: part.element) {
            // Validate bounds are reasonable
            if bounds.width > 0, bounds.height > 0, bounds.height < 100 {
                Logger.trace("NotionStrategy: AXBoundsForRange on child SUCCESS: \(bounds)", category: Logger.ui)
                return bounds
            }
        }

        // AXBoundsForRange failed - fall back to TextPart's overall frame
        // This is less precise but better than nothing
        Logger.trace("NotionStrategy: AXBoundsForRange on child failed - using TextPart frame", category: Logger.ui)
        return part.frame
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

    private func getFullTextFromElement(_ element: AXUIElement) -> String? {
        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef) == .success,
              let text = textRef as? String
        else {
            return nil
        }
        return text
    }

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
