//
//  ModernMarkerStrategy.swift
//  TextWarden
//
//  Modern positioning using opaque markers
//  Works in Electron, Chrome, Safari, and modern apps
//  THIS IS THE KEY STRATEGY FOR SLACK AND ELECTRON APPS
//

import Foundation
import ApplicationServices

/// Modern positioning using opaque marker API
/// This strategy works where traditional CFRange fails (Electron, Chrome)
class ModernMarkerStrategy: GeometryProvider {

    var strategyName: String { "ModernMarker" }
    var priority: Int { 100 }  // Highest priority

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // This strategy works best for Electron/Chromium apps
        // But we should try it for any app that supports it
        return AccessibilityBridge.supportsOpaqueMarkers(element)
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        let startIndex = errorRange.location
        let endIndex = errorRange.location + errorRange.length

        // Create opaque markers for start and end positions
        guard let startMarker = AccessibilityBridge.requestOpaqueMarker(
            at: startIndex,
            from: element
        ) else {
            let msg = "❌ ModernMarkerStrategy: Failed to create start marker at index \(startIndex)"
            Logger.debug(msg)
            NSLog(msg)
            logToDebugFile(msg)
            return nil
        }

        guard let endMarker = AccessibilityBridge.requestOpaqueMarker(
            at: endIndex,
            from: element
        ) else {
            let msg = "❌ ModernMarkerStrategy: Failed to create end marker at index \(endIndex)"
            Logger.debug(msg)
            NSLog(msg)
            logToDebugFile(msg)
            return nil
        }

        // Calculate bounds using markers
        guard let quartzBounds = AccessibilityBridge.calculateBounds(
            from: startMarker,
            to: endMarker,
            in: element
        ) else {
            let msg = "❌ ModernMarkerStrategy: Failed to calculate bounds between markers"
            Logger.debug(msg)
            NSLog(msg)
            logToDebugFile(msg)
            return nil
        }

        // Convert from Quartz (top-left) to Cocoa (bottom-left) coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("ModernMarkerStrategy: Converted bounds failed validation: \(cocoaBounds)")
            return nil
        }

        // Optional: Verify bounds are on-screen
        if !CoordinateMapper.isVisibleOnScreen(cocoaBounds) {
            Logger.warning("ModernMarkerStrategy: Bounds are off-screen: \(cocoaBounds)")
            // Continue anyway - might be on external monitor
        }

        Logger.debug("ModernMarkerStrategy: Successfully calculated bounds: \(cocoaBounds)")

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
