//
//  MailStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Apple Mail's WebKit-based compose windows.
//
//  APPROACH:
//  Mail uses WebKit for compose, which has unique AX API behavior:
//  - AXBoundsForRange uses UTF-16 code units (not grapheme clusters)
//  - AXBoundsForTextMarkerRange returns different coordinates than AXBoundsForRange
//  - The standard RangeBounds API works correctly when using UTF-16 indices
//
//  This strategy consolidates all Mail-specific logic that was previously
//  scattered across TextMarkerStrategy and RangeBoundsStrategy.
//

import AppKit
import ApplicationServices

/// Dedicated positioning strategy for Apple Mail's WebKit-based compose windows
class MailStrategy: GeometryProvider {
    var strategyName: String { "Mail" }
    var strategyType: StrategyType { .mail }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 0 }

    private static let mailBundleID = "com.apple.mail"

    // MARK: - GeometryProvider

    func canHandle(element _: AXUIElement, bundleID: String) -> Bool {
        guard bundleID == Self.mailBundleID else { return false }

        // Check watchdog protection
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("MailStrategy: Skipping - watchdog protection active", category: Logger.ui)
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
        Logger.debug("MailStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let adjustedRange = NSRange(
            location: errorRange.location + offset,
            length: max(1, errorRange.length)
        )

        // Convert grapheme cluster indices to UTF-16 code units
        // Mail's WebKit AX APIs use UTF-16 indices (critical for emoji support)
        let utf16Range = convertToUTF16Range(adjustedRange, in: element)

        Logger.debug("MailStrategy: Converted grapheme [\(adjustedRange.location), \(adjustedRange.length)] to UTF-16 [\(utf16Range.location), \(utf16Range.length)]", category: Logger.ui)

        // Get start character bounds
        let startCharRange = NSRange(location: utf16Range.location, length: 1)
        guard let startCharBounds = getBoundsForRange(range: startCharRange, in: element) else {
            Logger.debug("MailStrategy: Failed to get start char bounds at UTF-16 position \(utf16Range.location)", category: Logger.ui)
            return nil
        }

        // Get end character bounds
        let endCharPosition = utf16Range.location + utf16Range.length - 1
        let endCharRange = NSRange(location: endCharPosition, length: 1)
        guard let endCharBounds = getBoundsForRange(range: endCharRange, in: element) else {
            Logger.debug("MailStrategy: Failed to get end char bounds at UTF-16 position \(endCharPosition)", category: Logger.ui)
            return nil
        }

        // Calculate combined bounds from start of first char to end of last char
        // Bounds are in Quartz screen coordinates (top-left origin, y increases downward)
        // For multi-line text, compute the full bounding box covering all characters
        let minY = min(startCharBounds.origin.y, endCharBounds.origin.y)
        let maxY = max(startCharBounds.origin.y + startCharBounds.height,
                       endCharBounds.origin.y + endCharBounds.height)
        let minX = min(startCharBounds.origin.x, endCharBounds.origin.x)
        let maxX = max(startCharBounds.origin.x + startCharBounds.width,
                       endCharBounds.origin.x + endCharBounds.width)
        let quartzBounds = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )

        // Convert from Quartz screen → Cocoa screen
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("MailStrategy: Bounds failed validation: \(cocoaBounds)", category: Logger.accessibility)
            return nil
        }

        Logger.debug("MailStrategy: SUCCESS - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            lineBounds: nil,
            confidence: 0.95,
            strategy: strategyName,
            metadata: [
                "api": "webkit-bounds",
                "grapheme_location": adjustedRange.location,
                "grapheme_length": adjustedRange.length,
                "utf16_location": utf16Range.location,
                "utf16_length": utf16Range.length,
                "quartz_bounds": NSStringFromRect(quartzBounds),
                "cocoa_bounds": NSStringFromRect(cocoaBounds),
            ]
        )
    }

    // MARK: - WebKit Bounds Calculation

    /// Get bounds for a character range using Mail's WebKit AXBoundsForRange API.
    /// Handles layout-to-screen coordinate conversion when needed.
    private func getBoundsForRange(range: NSRange, in element: AXUIElement) -> CGRect? {
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

        guard result == .success,
              let bounds = boundsValue,
              let rect = safeAXValueGetRect(bounds)
        else {
            return nil
        }

        // Heuristic: Determine if coordinates are layout or screen
        // Layout coords have small X values, screen coords are larger
        let elementPosition = AccessibilityBridge.getElementPosition(element) ?? .zero
        let looksLikeLayoutCoords = rect.origin.x < 200 && rect.origin.x < (elementPosition.x - 100)

        if !looksLikeLayoutCoords {
            // Already screen coordinates
            return rect
        }

        // Try to convert from layout to screen
        if let screenRect = AccessibilityBridge.convertLayoutRectToScreen(rect, in: element) {
            Logger.debug("MailStrategy: Converted layout to screen coordinates", category: Logger.ui)
            return screenRect
        }

        // Conversion failed, use as-is
        return rect
    }

    // MARK: - UTF-16 Index Conversion

    /// Convert grapheme cluster indices to UTF-16 code unit indices for Mail's accessibility API.
    /// Mail's WebKit APIs (AXBoundsForRange, etc.) use UTF-16 code units,
    /// while Harper provides error positions in grapheme clusters (Swift String indices).
    /// This matters for text containing emojis: 👋 = 1 grapheme but 2 UTF-16 code units.
    private func convertToUTF16Range(_ range: NSRange, in element: AXUIElement) -> NSRange {
        // Fetch the actual text from the element using AXStringForRange
        // This ensures we're converting based on the same text that Mail's AX APIs use
        var charCountRef: CFTypeRef?
        var textLength = 0
        if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &charCountRef) == .success,
           let count = charCountRef as? Int
        {
            textLength = count
        } else {
            // Fallback: use a large range
            textLength = 100_000
        }

        // Fetch text using AXStringForRange (matches what Mail's AX APIs expect)
        var cfRange = CFRange(location: 0, length: textLength)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.debug("MailStrategy: Failed to create range value for text fetch", category: Logger.ui)
            return range
        }

        var stringRef: CFTypeRef?
        let fetchResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForRange" as CFString,
            rangeValue,
            &stringRef
        )

        guard fetchResult == .success, let text = stringRef as? String, !text.isEmpty else {
            Logger.debug("MailStrategy: AXStringForRange failed, using original range", category: Logger.ui)
            return range
        }

        Logger.debug("MailStrategy: Fetched \(text.count) characters from AX element for UTF-16 conversion", category: Logger.ui)

        // Now convert using the actual text from the element
        return TextIndexConverter.graphemeToUTF16Range(range, in: text)
    }
}
