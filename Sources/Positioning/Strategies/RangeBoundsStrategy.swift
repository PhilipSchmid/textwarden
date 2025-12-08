//
//  RangeBoundsStrategy.swift
//  TextWarden
//
//  Range-based positioning using CFRange
//  Works in TextEdit, Notes, Mail, and most native macOS apps
//

import Foundation
import ApplicationServices

/// Range-based positioning using CFRange API
/// Traditional approach that works well for native macOS apps
class RangeBoundsStrategy: GeometryProvider {

    var strategyName: String { "RangeBounds" }
    var strategyType: StrategyType { .rangeBounds }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 20 }

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Works for most native macOS apps
        // May fail for Electron apps, but serves as reliable fallback
        return true
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let adjustedRange = NSRange(
            location: errorRange.location + offset,
            length: max(1, errorRange.length)
        )

        // Check if parser provides custom bounds calculation (e.g., Mail's WebKit API)
        if parser.getBoundsForRange(range: NSRange(location: 0, length: 1), in: element) != nil {
            return calculateCustomParserGeometry(adjustedRange: adjustedRange, element: element, parser: parser)
        }

        // Convert grapheme cluster indices to UTF-16 indices for the accessibility API
        // macOS accessibility APIs use UTF-16 code units, not grapheme clusters
        // This is critical for text containing emojis (e.g., 😉 = 1 grapheme but 2 UTF-16 units)
        let utf16Range = convertToUTF16Range(adjustedRange, in: text)

        let cfRange = CFRange(
            location: utf16Range.location,
            length: utf16Range.length
        )

        // Try multi-line bounds first for better accuracy on multi-line errors
        // Use UTF-16 range for the API call
        let utf16NSRange = NSRange(location: utf16Range.location, length: utf16Range.length)
        if let quartzLineBounds = AccessibilityBridge.resolveMultiLineBounds(utf16NSRange, in: element),
           quartzLineBounds.count > 1 {
            // Multi-line error detected - convert all line bounds to Cocoa coordinates
            let cocoaLineBounds = quartzLineBounds.map { CoordinateMapper.toCocoaCoordinates($0) }

            // Validate all line bounds
            let validLineBounds = cocoaLineBounds.filter { CoordinateMapper.validateBounds($0) }
            guard !validLineBounds.isEmpty else {
                Logger.debug("RangeBoundsStrategy: All line bounds failed validation")
                return nil
            }

            // Calculate overall bounding box from all lines
            let overallBounds = calculateOverallBounds(from: validLineBounds)

            Logger.debug("RangeBoundsStrategy: Multi-line error with \(validLineBounds.count) lines, overall bounds: \(overallBounds)")

            return GeometryResult(
                bounds: overallBounds,
                lineBounds: validLineBounds,
                confidence: 0.90,
                strategy: strategyName,
                metadata: [
                    "api": "range-bounds-multiline",
                    "range_location": cfRange.location,
                    "range_length": cfRange.length,
                    "line_count": validLineBounds.count,
                    "overall_bounds": NSStringFromRect(overallBounds)
                ]
            )
        }

        // Fall back to single-range bounds (single line or when line API unavailable)
        guard let quartzBounds = AccessibilityBridge.resolveBoundsUsingRange(
            cfRange,
            in: element
        ) else {
            Logger.debug("RangeBoundsStrategy: Failed to resolve bounds for range \(cfRange.location)-\(cfRange.location + cfRange.length)", category: Logger.ui)
            return nil
        }

        // Convert from Quartz (top-left) to Cocoa (bottom-left) coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("RangeBoundsStrategy: Converted bounds failed validation: \(cocoaBounds)")
            return nil
        }

        // Check for suspiciously small bounds
        if cocoaBounds.width < 5.0 {
            Logger.warning("RangeBoundsStrategy: Bounds width suspiciously small: \(cocoaBounds.width)px")
        }

        Logger.debug("RangeBoundsStrategy: Successfully calculated bounds: \(cocoaBounds)")

        return GeometryResult(
            bounds: cocoaBounds,
            lineBounds: nil,
            confidence: 0.90,
            strategy: strategyName,
            metadata: [
                "api": "range-bounds",
                "range_location": cfRange.location,
                "range_length": cfRange.length,
                "quartz_bounds": NSStringFromRect(quartzBounds),
                "cocoa_bounds": NSStringFromRect(cocoaBounds)
            ]
        )
    }

    /// Calculate the overall bounding box that encompasses all line bounds
    private func calculateOverallBounds(from lineBounds: [CGRect]) -> CGRect {
        guard let first = lineBounds.first else { return .zero }

        var minX = first.minX
        var minY = first.minY
        var maxX = first.maxX
        var maxY = first.maxY

        for bounds in lineBounds.dropFirst() {
            minX = min(minX, bounds.minX)
            minY = min(minY, bounds.minY)
            maxX = max(maxX, bounds.maxX)
            maxY = max(maxY, bounds.maxY)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Custom Parser Bounds

    /// Calculate geometry using parser's custom bounds calculation.
    /// Used for apps with non-standard accessibility APIs (e.g., Mail's WebKit).
    /// Gets start and end character bounds separately to avoid multi-char range bugs.
    private func calculateCustomParserGeometry(
        adjustedRange: NSRange,
        element: AXUIElement,
        parser: ContentParser
    ) -> GeometryResult? {
        // For custom parser apps like Mail, we need to convert grapheme cluster indices
        // to UTF-16 code units. But we must use the ACTUAL text from the AX element,
        // not the filtered `text` parameter which may be different.
        // Mail's AXBoundsForRange uses UTF-16 code units matching AXStringForRange.
        let utf16Range = convertToUTF16RangeUsingElement(adjustedRange, in: element)

        // Get start character bounds
        let startCharRange = NSRange(location: utf16Range.location, length: 1)
        guard let startCharBounds = parser.getBoundsForRange(range: startCharRange, in: element) else {
            Logger.debug("RangeBoundsStrategy: Custom parser failed to get start char bounds at UTF-16 position \(utf16Range.location)", category: Logger.ui)
            return nil
        }

        // Get end character bounds
        let endCharPosition = utf16Range.location + utf16Range.length - 1
        let endCharRange = NSRange(location: endCharPosition, length: 1)
        guard let endCharBounds = parser.getBoundsForRange(range: endCharRange, in: element) else {
            Logger.debug("RangeBoundsStrategy: Custom parser failed to get end char bounds at UTF-16 position \(endCharPosition)", category: Logger.ui)
            return nil
        }

        // Calculate combined bounds from start of first char to end of last char
        // Bounds are expected to be in Quartz screen coordinates (top-left origin)
        let quartzBounds = CGRect(
            x: startCharBounds.origin.x,
            y: startCharBounds.origin.y,
            width: (endCharBounds.origin.x + endCharBounds.width) - startCharBounds.origin.x,
            height: startCharBounds.height
        )

        // Convert from Quartz screen → Cocoa screen
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("RangeBoundsStrategy: Custom parser bounds failed validation: \(cocoaBounds)")
            return nil
        }

        return GeometryResult(
            bounds: cocoaBounds,
            lineBounds: nil,
            confidence: 0.95,
            strategy: strategyName,
            metadata: [
                "api": "custom-parser-bounds",
                "grapheme_location": adjustedRange.location,
                "grapheme_length": adjustedRange.length,
                "utf16_location": utf16Range.location,
                "utf16_length": utf16Range.length,
                "quartz_screen_bounds": NSStringFromRect(quartzBounds),
                "cocoa_bounds": NSStringFromRect(cocoaBounds)
            ]
        )
    }

    // MARK: - UTF-16 Conversion

    /// Convert grapheme cluster indices to UTF-16 code unit indices by fetching text from the AX element.
    /// This is used for custom parser apps like Mail where the passed `text` parameter might not match
    /// the accessibility API's text (due to filtering/processing).
    /// Uses AXStringForRange to get the actual text that matches Mail's AXBoundsForRange indices.
    private func convertToUTF16RangeUsingElement(_ range: NSRange, in element: AXUIElement) -> NSRange {
        // Fetch the actual text from the element using AXStringForRange
        // This ensures we're converting based on the same text that AXBoundsForRange uses
        var charCountRef: CFTypeRef?
        var textLength = 0
        if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &charCountRef) == .success,
           let count = charCountRef as? Int {
            textLength = count
        } else {
            // Fallback: use a large range
            textLength = 100_000
        }

        // Fetch text using AXStringForRange (matches what AXBoundsForRange expects)
        var cfRange = CFRange(location: 0, length: textLength)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.debug("RangeBoundsStrategy: Failed to create range value for text fetch", category: Logger.ui)
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
            Logger.debug("RangeBoundsStrategy: AXStringForRange failed, using original range", category: Logger.ui)
            return range
        }

        Logger.debug("RangeBoundsStrategy: Fetched \(text.count) characters from AX element for UTF-16 conversion", category: Logger.ui)

        // Now convert using the actual text from the element
        return convertToUTF16Range(range, in: text)
    }

    /// Convert grapheme cluster indices to UTF-16 code unit indices.
    /// macOS accessibility APIs (AXBoundsForRange, etc.) use UTF-16 code units,
    /// while Swift String indices are grapheme clusters.
    /// This matters for text containing emojis: 😉 is 1 grapheme but 2 UTF-16 code units.
    private func convertToUTF16Range(_ range: NSRange, in text: String) -> NSRange {
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

        Logger.debug("RangeBoundsStrategy: UTF-16 conversion: grapheme [\(range.location), \(range.length)] -> UTF-16 [\(utf16Location), \(utf16Length)]", category: Logger.ui)

        return NSRange(location: utf16Location, length: utf16Length)
    }

}
