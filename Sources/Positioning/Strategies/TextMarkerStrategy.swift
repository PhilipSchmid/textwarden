//
//  TextMarkerStrategy.swift
//  TextWarden
//
//  Positioning using opaque text markers
//  Works in Electron, Chrome, Safari, and modern apps
//

import Foundation
import ApplicationServices

/// Positioning using opaque text marker API
/// Works where traditional CFRange fails (Electron, Chrome)
class TextMarkerStrategy: GeometryProvider {

    var strategyName: String { "TextMarker" }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 1 }  // TESTING: Run first to see TextMarker results on Slack

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Works best for Electron/Chromium apps
        // Try for any app that supports opaque markers
        return AccessibilityBridge.supportsOpaqueMarkers(element)
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let startIndex = errorRange.location + offset
        let endIndex = startIndex + errorRange.length

        guard let startMarker = AccessibilityBridge.requestOpaqueMarker(
            at: startIndex,
            from: element
        ) else {
            Logger.debug("TextMarkerStrategy: Failed to create start marker at index \(startIndex)", category: Logger.ui)
            return nil
        }

        guard let endMarker = AccessibilityBridge.requestOpaqueMarker(
            at: endIndex,
            from: element
        ) else {
            Logger.debug("TextMarkerStrategy: Failed to create end marker at index \(endIndex)", category: Logger.ui)
            return nil
        }

        // Calculate bounds using markers
        guard let quartzBounds = AccessibilityBridge.calculateBounds(
            from: startMarker,
            to: endMarker,
            in: element
        ) else {
            Logger.debug("TextMarkerStrategy: Failed to calculate bounds between markers", category: Logger.ui)
            return nil
        }

        // Convert from Quartz (top-left) to Cocoa (bottom-left) coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("TextMarkerStrategy: Converted bounds failed validation: \(cocoaBounds)")
            return nil
        }

        // Verify bounds are on-screen
        if !CoordinateMapper.isVisibleOnScreen(cocoaBounds) {
            Logger.warning("TextMarkerStrategy: Bounds are off-screen: \(cocoaBounds)")
            // Continue anyway - might be on external monitor
        }

        Logger.debug("TextMarkerStrategy: Successfully calculated bounds: \(cocoaBounds)")

        return GeometryResult.highConfidence(
            bounds: cocoaBounds,
            strategy: strategyName,
            metadata: [
                "api": "opaque-markers",
                "start_index": startIndex,
                "end_index": endIndex,
                "quartz_bounds": NSStringFromRect(quartzBounds),
                "cocoa_bounds": NSStringFromRect(cocoaBounds)
            ]
        )
    }
}
