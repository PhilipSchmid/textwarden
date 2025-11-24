//
//  ClassicRangeStrategy.swift
//  TextWarden
//
//  Classic range-based positioning
//  Works in TextEdit, Notes, Mail, and most native macOS apps
//

import Foundation
import ApplicationServices

/// Classic range-based positioning using CFRange
/// Traditional approach that works well for native macOS apps
class ClassicRangeStrategy: GeometryProvider {

    var strategyName: String { "ClassicRange" }
    var priority: Int { 80 }  // Medium priority

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // This strategy works for most native macOS apps
        // It tends to fail for Electron apps, so we prioritize ModernMarkerStrategy
        // But we should still try it as a fallback
        return true  // Always available
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        let cfRange = CFRange(
            location: errorRange.location,
            length: max(1, errorRange.length)  // Ensure at least 1 character length
        )

        // Try to get bounds using classic API
        guard let quartzBounds = AccessibilityBridge.resolveBoundsUsingRange(
            cfRange,
            in: element
        ) else {
            Logger.debug("ClassicRangeStrategy: Failed to resolve bounds for range \(cfRange.location)-\(cfRange.location + cfRange.length)", category: Logger.ui)
            return nil
        }

        // Convert from Quartz (top-left) to Cocoa (bottom-left) coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("ClassicRangeStrategy: Converted bounds failed validation: \(cocoaBounds)")
            return nil
        }

        // Check if bounds are reasonable (not zero-width)
        if cocoaBounds.width < 5.0 {
            Logger.warning("ClassicRangeStrategy: Bounds width suspiciously small: \(cocoaBounds.width)px")
            // Continue anyway - might be valid for single character
        }

        Logger.debug("ClassicRangeStrategy: Successfully calculated bounds: \(cocoaBounds)")

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.90,  // Slightly lower than ModernMarker
            strategy: strategyName,
            metadata: [
                "api": "classic-range",
                "range_location": cfRange.location,
                "range_length": cfRange.length,
                "quartz_bounds": NSStringFromRect(quartzBounds),
                "cocoa_bounds": NSStringFromRect(cocoaBounds)
            ]
        )
    }
}
