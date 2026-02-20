//
//  WordStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Microsoft Word documents.
//
//  APPROACH:
//  Word exposes a single AXTextArea element containing the document text.
//  Unlike Outlook's compose body which has child elements, Word's document
//  view is flat - all text is in one element with no children.
//
//  Word's AXBoundsForRange API works reliably (tested with Word 16.104+).
//  We use direct AXBoundsForRange queries with line-based fallback for
//  multi-line error ranges.
//

import AppKit
import ApplicationServices

/// Dedicated Word positioning using AXBoundsForRange
class WordStrategy: GeometryProvider {
    var strategyName: String {
        "Word"
    }

    var strategyType: StrategyType {
        .word
    }

    var tier: StrategyTier {
        .precise
    }

    var tierPriority: Int {
        5
    }

    private static let wordBundleID = "com.microsoft.Word"

    // MARK: - GeometryProvider

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        guard bundleID == Self.wordBundleID else { return false }

        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("WordStrategy: Skipping - watchdog protection active", category: Logger.ui)
            return false
        }

        // Only handle document text areas
        guard WordContentParser.isDocumentElement(element) else {
            Logger.debug("WordStrategy: Skipping - not a document element", category: Logger.ui)
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
        Logger.debug("WordStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let originalRange = NSRange(location: errorRange.location + offset, length: errorRange.length)

        // Convert grapheme cluster indices to UTF-16 for the accessibility API
        let utf16Range = TextIndexConverter.graphemeToUTF16Range(originalRange, in: text)

        // Try multi-line bounds first for better accuracy on multi-line errors
        if let result = calculateMultiLineBounds(utf16Range: utf16Range, element: element) {
            return result
        }

        // Fall back to single-range bounds
        return calculateSingleRangeBounds(utf16Range: utf16Range, element: element)
    }

    // MARK: - Multi-Line Bounds

    /// Calculate bounds for potentially multi-line error ranges
    private func calculateMultiLineBounds(utf16Range: NSRange, element: AXUIElement) -> GeometryResult? {
        guard let quartzLineBounds = AccessibilityBridge.resolveMultiLineBounds(utf16Range, in: element),
              quartzLineBounds.count > 1
        else {
            return nil
        }

        // Multi-line error detected - convert all line bounds to Cocoa coordinates
        let cocoaLineBounds = quartzLineBounds.map { CoordinateMapper.toCocoaCoordinates($0) }

        // Validate all line bounds
        let validLineBounds = cocoaLineBounds.filter { CoordinateMapper.validateBounds($0) }
        guard !validLineBounds.isEmpty else {
            Logger.debug("WordStrategy: All line bounds failed validation", category: Logger.ui)
            return nil
        }

        // Calculate overall bounding box from all lines
        let overallBounds = calculateOverallBounds(from: validLineBounds)

        Logger.debug("WordStrategy: Multi-line error with \(validLineBounds.count) lines, bounds: \(overallBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: overallBounds,
            lineBounds: validLineBounds,
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: [
                "api": "word-multiline-bounds",
                "utf16_location": utf16Range.location,
                "utf16_length": utf16Range.length,
                "line_count": validLineBounds.count,
            ]
        )
    }

    // MARK: - Single Range Bounds

    /// Calculate bounds for single-line or when multi-line detection unavailable
    private func calculateSingleRangeBounds(utf16Range: NSRange, element: AXUIElement) -> GeometryResult? {
        var cfRange = CFRange(location: utf16Range.location, length: utf16Range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.debug("WordStrategy: Failed to create CFRange value", category: Logger.ui)
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
            Logger.debug("WordStrategy: AXBoundsForRange failed with error \(result.rawValue)", category: Logger.ui)
            return nil
        }

        var quartzBounds = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &quartzBounds) else {
            Logger.debug("WordStrategy: Failed to extract CGRect from AXValue", category: Logger.ui)
            return nil
        }

        // Validate bounds - reject suspiciously small widths
        if quartzBounds.width < GeometryConstants.minimumBoundsSize {
            Logger.debug("WordStrategy: Bounds width too small (\(quartzBounds.width)px)", category: Logger.ui)
            return nil
        }

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("WordStrategy: Bounds validation failed: \(cocoaBounds)", category: Logger.ui)
            return nil
        }

        Logger.debug("WordStrategy: SUCCESS - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: [
                "api": "word-bounds-for-range",
                "utf16_location": utf16Range.location,
                "utf16_length": utf16Range.length,
            ]
        )
    }

    // MARK: - Helpers

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
}
