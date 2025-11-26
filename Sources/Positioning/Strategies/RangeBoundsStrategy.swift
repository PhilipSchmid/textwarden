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
        let cfRange = CFRange(
            location: errorRange.location + offset,
            length: max(1, errorRange.length)
        )

        // Get bounds using standard range API
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
}
