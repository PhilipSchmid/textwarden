//
//  ProtonMailStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Proton Mail's Electron-based Rooster editor.
//
//  APPROACH:
//  Proton Mail's main AXTextArea (domId="rooster-editor") returns full element bounds for
//  AXBoundsForRange. However, child AXStaticText elements DO support AXBoundsForRange with
//  local ranges, similar to Slack and Teams.
//
//  Strategy:
//  1. Traverse AX children tree to find all AXStaticText elements (text runs)
//  2. Build a TextPart map: character ranges → visual frames + element references
//  3. For each error, find the overlapping TextPart(s)
//  4. Query AXBoundsForRange on the child element with local range offset
//  5. Handle UTF-16 emoji offsets for correct character positioning
//

import AppKit
import ApplicationServices

/// A segment of text with its visual bounds from the AX tree
private struct TextPart {
    let text: String
    let range: NSRange // Character range in the full text
    let frame: CGRect // Visual bounds from AXFrame (Quartz coordinates)
    let element: AXUIElement // Reference to query AXBoundsForRange directly
}

/// Dedicated Proton Mail positioning using AX tree traversal for bounds
class ProtonMailStrategy: GeometryProvider {
    var strategyName: String { "ProtonMail" }
    var strategyType: StrategyType { .protonMail }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 0 }

    private static let protonMailBundleID = "ch.protonmail.desktop"

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
        guard bundleID == Self.protonMailBundleID else { return false }

        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("ProtonMailStrategy: Skipping - watchdog protection active", category: Logger.ui)
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
        Logger.debug("ProtonMailStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let originalRange = NSRange(location: errorRange.location + offset, length: errorRange.length)

        // Get element frame for validation
        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
            Logger.debug("ProtonMailStrategy: Could not get element frame", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Could not get element frame")
        }

        Logger.debug("ProtonMailStrategy: Element frame (Quartz): \(elementFrame)", category: Logger.ui)

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
            Logger.debug("ProtonMailStrategy: Built \(textParts.count) TextParts", category: Logger.ui)
        }

        if textParts.isEmpty {
            Logger.debug("ProtonMailStrategy: No TextParts found - letting chain continue", category: Logger.ui)
            return nil
        }

        // STEP 2: Find TextPart(s) that contain the error range
        guard let bounds = findBoundsForRange(originalRange, in: textParts, fullText: text, element: element) else {
            Logger.debug("ProtonMailStrategy: Could not find TextPart for range \(originalRange) - letting chain continue", category: Logger.ui)
            return nil
        }

        Logger.debug("ProtonMailStrategy: TextPart bounds (Quartz): \(bounds)", category: Logger.ui)

        // STEP 3: Validate bounds are within element
        let elementBottom = elementFrame.origin.y + elementFrame.height
        guard bounds.origin.y >= elementFrame.origin.y - 10,
              bounds.origin.y <= elementBottom + 10
        else {
            Logger.debug("ProtonMailStrategy: Bounds Y \(bounds.origin.y) outside element (\(elementFrame.origin.y) to \(elementBottom))", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Y position outside element bounds")
        }

        // STEP 4: Convert to Cocoa coordinates
        let cocoaY = primaryScreenHeight - bounds.origin.y - bounds.height
        let cocoaBounds = CGRect(
            x: bounds.origin.x,
            y: cocoaY,
            width: bounds.width,
            height: bounds.height
        )

        Logger.debug("ProtonMailStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("ProtonMailStrategy: Final bounds validation failed", category: Logger.ui)
            return GeometryResult.unavailable(reason: "Invalid final bounds")
        }

        Logger.debug("ProtonMailStrategy: SUCCESS (textpart-tree) - bounds: \(cocoaBounds)", category: Logger.ui)

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

    /// Build TextPart map by traversing AX children
    /// Proton Mail's editor has mixed structure:
    ///   - AXTextArea → AXGroup → AXStaticText (normal paragraphs)
    ///   - AXTextArea → AXStaticText (direct children, e.g., after style insertions)
    /// Uses string search to find exact positions which handles emojis correctly
    private func buildTextPartMap(from element: AXUIElement, fullText: String) -> [TextPart] {
        var textParts: [TextPart] = []
        var searchStart = 0 // Where to start searching for next TextPart

        // Get children (can be AXGroup paragraphs OR direct AXStaticText elements)
        guard let children = getChildren(element) else {
            return []
        }

        for child in children {
            let childRole = getRole(child)

            // Handle direct AXStaticText children (inserted text like "Best regards,")
            if childRole == "AXStaticText" {
                let childText = getText(child)
                let childFrame = getFrame(child)
                if !childText.isEmpty, childFrame.width > 0, childFrame.height > 0 {
                    if let foundRange = findTextRange(childText, in: fullText, startingAt: searchStart) {
                        textParts.append(TextPart(text: childText, range: foundRange, frame: childFrame, element: child))
                        searchStart = foundRange.location + foundRange.length
                    }
                }
                continue
            }

            // Handle AXGroup paragraphs
            guard childRole == "AXGroup" else { continue }
            let paragraph = child

            // Get grandchildren (text runs within this paragraph)
            guard let textRuns = getChildren(paragraph) else {
                // Paragraph might have text directly
                let paragraphText = getText(paragraph)
                if !paragraphText.isEmpty {
                    let frame = getFrame(paragraph)
                    if frame.width > 0, frame.height > 0 {
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

                if role == "AXStaticText", !runText.isEmpty, frame.width > 0, frame.height > 0 {
                    // Direct text run - find its position by string search
                    if let foundRange = findTextRange(runText, in: fullText, startingAt: searchStart) {
                        textParts.append(TextPart(text: runText, range: foundRange, frame: frame, element: textRun))
                        searchStart = foundRange.location + foundRange.length
                    }
                } else if role == "AXGroup" {
                    // Could be formatting group (bold, italic, links) - check for text inside
                    if let nestedRuns = getChildren(textRun) {
                        for nestedRun in nestedRuns {
                            let nestedRole = getRole(nestedRun)
                            let nestedFrame = getFrame(nestedRun)
                            let nestedText = getText(nestedRun)

                            if nestedRole == "AXStaticText", !nestedText.isEmpty,
                               nestedFrame.width > 0, nestedFrame.height > 0
                            {
                                if let foundRange = findTextRange(nestedText, in: fullText, startingAt: searchStart) {
                                    textParts.append(TextPart(text: nestedText, range: foundRange, frame: nestedFrame, element: nestedRun))
                                    searchStart = foundRange.location + foundRange.length
                                }
                            } else if nestedRole == "AXGroup" {
                                // Handle deeper nesting (e.g., bold + italic)
                                if let deeperRuns = getChildren(nestedRun) {
                                    for deeperRun in deeperRuns {
                                        let deeperRole = getRole(deeperRun)
                                        let deeperFrame = getFrame(deeperRun)
                                        let deeperText = getText(deeperRun)

                                        if deeperRole == "AXStaticText", !deeperText.isEmpty,
                                           deeperFrame.width > 0, deeperFrame.height > 0
                                        {
                                            if let foundRange = findTextRange(deeperText, in: fullText, startingAt: searchStart) {
                                                textParts.append(TextPart(text: deeperText, range: foundRange, frame: deeperFrame, element: deeperRun))
                                                searchStart = foundRange.location + foundRange.length
                                            }
                                        }
                                    }
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
            Logger.debug("ProtonMailStrategy: No TextPart found overlapping range \(targetRange)", category: Logger.ui)
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

        Logger.debug("ProtonMailStrategy: Unioned \(overlappingParts.count) TextParts for range \(targetRange)", category: Logger.ui)
        return unionBounds
    }

    /// Calculate bounds for error within a single TextPart
    /// Uses AXBoundsForRange on the child element for pixel-perfect positioning
    /// Returns nil if AX query fails - let next strategy handle fallback
    private func calculateSubElementBounds(targetRange: NSRange, in part: TextPart, element _: AXUIElement) -> CGRect? {
        let offsetInPart = targetRange.location - part.range.location
        let errorLength = min(targetRange.location + targetRange.length, part.range.location + part.range.length) - targetRange.location

        // Convert Swift character offset to UTF-16 offset for AX API
        // This handles emojis correctly since AX API uses UTF-16 indices
        let partText = part.text
        let utf16Offset = convertToUTF16Offset(characterOffset: offsetInPart, in: partText)
        let utf16Length = convertToUTF16Length(characterOffset: offsetInPart, length: errorLength, in: partText)

        Logger.debug("ProtonMailStrategy: Character offset \(offsetInPart) → UTF-16 offset \(utf16Offset), length \(errorLength) → \(utf16Length)", category: Logger.ui)

        // Query AXBoundsForRange on the child element directly
        // The local range is relative to the TextPart, not the full text
        if let bounds = getBoundsForRange(location: utf16Offset, length: utf16Length, in: part.element) {
            // Validate bounds are reasonable
            if bounds.width > 0, bounds.height > 0, bounds.height < 50 {
                Logger.debug("ProtonMailStrategy: AXBoundsForRange on child SUCCESS: \(bounds)", category: Logger.ui)
                return bounds
            }
        }

        // AXBoundsForRange failed - fall back to using the TextPart's frame
        Logger.debug("ProtonMailStrategy: AXBoundsForRange on child failed - using TextPart frame", category: Logger.ui)
        return part.frame
    }

    /// Convert Swift character offset to UTF-16 offset
    private func convertToUTF16Offset(characterOffset: Int, in text: String) -> Int {
        guard characterOffset > 0 else { return 0 }
        guard let endIndex = text.index(text.startIndex, offsetBy: characterOffset, limitedBy: text.endIndex) else {
            return text.utf16.count
        }
        return text.utf16.distance(from: text.utf16.startIndex, to: endIndex.samePosition(in: text.utf16) ?? text.utf16.endIndex)
    }

    /// Convert Swift character length to UTF-16 length
    private func convertToUTF16Length(characterOffset: Int, length: Int, in text: String) -> Int {
        guard let startIndex = text.index(text.startIndex, offsetBy: characterOffset, limitedBy: text.endIndex),
              let endIndex = text.index(startIndex, offsetBy: length, limitedBy: text.endIndex)
        else {
            return length
        }
        guard let utf16Start = startIndex.samePosition(in: text.utf16),
              let utf16End = endIndex.samePosition(in: text.utf16)
        else {
            return length
        }
        return text.utf16.distance(from: utf16Start, to: utf16End)
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
