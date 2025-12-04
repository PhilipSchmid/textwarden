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
        let cfRange = CFRange(
            location: adjustedRange.location,
            length: adjustedRange.length
        )

        // Try multi-line bounds first for better accuracy on multi-line errors
        if let quartzLineBounds = AccessibilityBridge.resolveMultiLineBounds(adjustedRange, in: element),
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
}
