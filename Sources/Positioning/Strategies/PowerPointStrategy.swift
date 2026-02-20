//
//  PowerPointStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Microsoft PowerPoint Notes section.
//
//  APPROACH:
//  PowerPoint exposes only the Notes section via macOS Accessibility API.
//  Slide text boxes are NOT accessible programmatically.
//
//  The Notes section uses an AXTextArea element with working AXBoundsForRange.
//  This strategy is very similar to WordStrategy since both use flat AXTextArea
//  elements with direct bounds queries.
//

import AppKit
import ApplicationServices

/// Dedicated PowerPoint positioning using AXBoundsForRange on Notes section
class PowerPointStrategy: GeometryProvider {
    var strategyName: String {
        "PowerPoint"
    }

    var strategyType: StrategyType {
        .powerpoint
    }

    var tier: StrategyTier {
        .precise
    }

    var tierPriority: Int {
        5
    }

    private static let powerpointBundleID = "com.microsoft.Powerpoint"

    // MARK: - GeometryProvider

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        guard bundleID == Self.powerpointBundleID else { return false }

        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("PowerPointStrategy: Skipping - watchdog protection active", category: Logger.ui)
            return false
        }

        // Only handle Notes text areas
        guard PowerPointContentParser.isSlideElement(element) else {
            Logger.debug("PowerPointStrategy: Skipping - not a Notes element", category: Logger.ui)
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
        Logger.debug("PowerPointStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

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
            Logger.debug("PowerPointStrategy: All line bounds failed validation", category: Logger.ui)
            return nil
        }

        // Calculate overall bounding box from all lines
        let overallBounds = calculateOverallBounds(from: validLineBounds)

        Logger.debug("PowerPointStrategy: Multi-line error with \(validLineBounds.count) lines, bounds: \(overallBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: overallBounds,
            lineBounds: validLineBounds,
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: [
                "api": "powerpoint-multiline-bounds",
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
            Logger.debug("PowerPointStrategy: Failed to create CFRange value", category: Logger.ui)
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
            Logger.debug("PowerPointStrategy: AXBoundsForRange failed with error \(result.rawValue)", category: Logger.ui)
            return nil
        }

        var quartzBounds = CGRect.zero
        // Safe: CFGetTypeID verified this is an AXValue
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(bv as! AXValue, .cgRect, &quartzBounds) else {
            Logger.debug("PowerPointStrategy: Failed to extract CGRect from AXValue", category: Logger.ui)
            return nil
        }

        // Validate bounds - reject suspiciously small widths
        if quartzBounds.width < GeometryConstants.minimumBoundsSize {
            Logger.debug("PowerPointStrategy: Bounds width too small (\(quartzBounds.width)px)", category: Logger.ui)
            return nil
        }

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("PowerPointStrategy: Bounds validation failed: \(cocoaBounds)", category: Logger.ui)
            return nil
        }

        Logger.debug("PowerPointStrategy: SUCCESS - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: [
                "api": "powerpoint-bounds-for-range",
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
