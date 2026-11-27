//
//  RangeBoundsStrategy.swift
//  TextWarden
//
//  Range-based positioning using CFRange
//  Works in TextEdit, Notes, Mail, and most native macOS apps
//

import ApplicationServices
import Foundation

/// Range-based positioning using CFRange API
/// Traditional approach that works well for native macOS apps
class RangeBoundsStrategy: GeometryProvider {
    private let boundsForRange: (CFRange, AXUIElement) -> CGRect?

    init(boundsForRange: @escaping (CFRange, AXUIElement) -> CGRect? = AccessibilityBridge.resolveBoundsUsingRange) {
        self.boundsForRange = boundsForRange
    }

    var strategyName: String {
        "RangeBounds"
    }

    var strategyType: StrategyType {
        .rangeBounds
    }

    var tier: StrategyTier {
        .precise
    }

    var tierPriority: Int {
        20
    }

    // Uses default canHandle (returns true) - works for most native macOS apps

    func calculateGeometry(
        errorRange utf16Range: NSRange,
        element: AXUIElement,
        text _: String,
        parser: ContentParser
    ) -> GeometryResult? {
        // Check if parser provides custom bounds calculation (e.g., Mail's WebKit API)
        if parser.getBoundsForRange(range: NSRange(location: 0, length: 1), in: element) != nil {
            return calculateCustomParserGeometry(utf16Range: utf16Range, element: element, parser: parser)
        }

        let cfRange = CFRange(
            location: utf16Range.location,
            length: utf16Range.length
        )

        // Try multi-line bounds first for better accuracy on multi-line errors
        // Use UTF-16 range for the API call
        if let quartzLineBounds = AccessibilityBridge.resolveMultiLineBounds(utf16Range, in: element),
           quartzLineBounds.count > 1
        {
            // Multi-line error detected - convert all line bounds to Cocoa coordinates
            let cocoaLineBounds = quartzLineBounds.map { CoordinateMapper.toCocoaCoordinates($0) }

            // Validate all line bounds
            let validLineBounds = cocoaLineBounds.filter { CoordinateMapper.validateBounds($0) }
            guard !validLineBounds.isEmpty else {
                Logger.debug("RangeBoundsStrategy: All line bounds failed validation", category: Logger.accessibility)
                return nil
            }

            // Calculate overall bounding box from all lines
            let overallBounds = calculateOverallBounds(from: validLineBounds)

            Logger.debug("RangeBoundsStrategy: Multi-line error with \(validLineBounds.count) lines, overall bounds: \(overallBounds)", category: Logger.accessibility)

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
                    "overall_bounds": NSStringFromRect(overallBounds),
                ]
            )
        }

        // Fall back to single-range bounds (single line or when line API unavailable)
        guard let quartzBounds = boundsForRange(cfRange, element) else {
            Logger.debug("RangeBoundsStrategy: Failed to resolve bounds for range \(cfRange.location)-\(cfRange.location + cfRange.length)", category: Logger.ui)
            return nil
        }

        // Convert from Quartz (top-left) to Cocoa (bottom-left) coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("RangeBoundsStrategy: Converted bounds failed validation: \(cocoaBounds)", category: Logger.accessibility)
            return nil
        }

        // Reject suspiciously small bounds - likely garbage from broken AX APIs (e.g., Microsoft Office mso99)
        // This allows fallback strategies to try instead
        if cocoaBounds.width < GeometryConstants.minimumBoundsSize {
            Logger.warning("RangeBoundsStrategy: Bounds width suspiciously small (\(cocoaBounds.width)px < \(GeometryConstants.minimumBoundsSize)px) - rejecting to try fallback strategies", category: Logger.accessibility)
            return nil
        }

        Logger.debug("RangeBoundsStrategy: Successfully calculated bounds: \(cocoaBounds)", category: Logger.accessibility)

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
                "cocoa_bounds": NSStringFromRect(cocoaBounds),
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
    /// Fallback for apps with dedicated strategies (e.g., Mail uses MailStrategy first).
    /// If the dedicated strategy fails, this provides a secondary path via the parser.
    /// Gets start and end character bounds separately to avoid multi-char range bugs.
    private func calculateCustomParserGeometry(
        utf16Range: NSRange,
        element: AXUIElement,
        parser: ContentParser
    ) -> GeometryResult? {
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
        // Bounds are expected to be in Quartz screen coordinates (top-left origin, y increases downward)
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
            Logger.debug("RangeBoundsStrategy: Custom parser bounds failed validation: \(cocoaBounds)", category: Logger.accessibility)
            return nil
        }

        return GeometryResult(
            bounds: cocoaBounds,
            lineBounds: nil,
            confidence: 0.95,
            strategy: strategyName,
            metadata: [
                "api": "custom-parser-bounds",
                "utf16_location": utf16Range.location,
                "utf16_length": utf16Range.length,
                "quartz_screen_bounds": NSStringFromRect(quartzBounds),
                "cocoa_bounds": NSStringFromRect(cocoaBounds),
            ]
        )
    }
}
