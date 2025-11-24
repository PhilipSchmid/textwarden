//
//  TextMeasurementStrategy.swift
//  TextWarden
//
//  Estimation using text measurement
//  Fallback strategy that works when AX APIs fail
//  Leverages TextWarden's existing ContentParser architecture
//

import Foundation
import ApplicationServices

/// Text measurement-based positioning strategy
/// Uses ContentParser's adjustBounds() as foundation
/// This is TextWarden's existing smart estimation system
class TextMeasurementStrategy: GeometryProvider {

    var strategyName: String { "TextMeasurement" }
    var priority: Int { 50 }  // Lowest priority (fallback)

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Always available as last resort
        return true
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        // Extract text segments for parser
        let startIndex = errorRange.location
        let endIndex = errorRange.location + errorRange.length

        // Safe string extraction
        guard startIndex >= 0 && endIndex <= text.count else {
            Logger.warning("TextMeasurementStrategy: Invalid range \(errorRange) for text length \(text.count)")
            return nil
        }

        let textBeforeError = String(text.prefix(startIndex))
        let errorText = String(text[text.index(text.startIndex, offsetBy: startIndex)..<text.index(text.startIndex, offsetBy: endIndex)])

        // Use ContentParser's existing smart estimation!
        // This is TextWarden's unique advantage - app-specific knowledge
        guard let adjustedBounds = parser.adjustBounds(
            element: element,
            errorRange: errorRange,
            textBeforeError: textBeforeError,
            errorText: errorText,
            fullText: text
        ) else {
            Logger.debug("TextMeasurementStrategy: Parser returned nil for bounds")
            return nil
        }

        // Convert AdjustedBounds to CGRect (Quartz coordinates from parser)
        // CRITICAL: adjustedBounds.position.y is the BASELINE (bottom of text)
        // but CGRect.origin.y expects the TOP edge, so subtract height
        // Use parser's font size for accurate height calculation
        let fontSize = parser.estimatedFontSize(context: adjustedBounds.uiContext)
        let errorHeight: CGFloat = fontSize * 1.2  // Add 20% for line height

        Logger.debug("TextMeasurement: adjustedBounds.position (Quartz baseline) = \(adjustedBounds.position), fontSize=\(fontSize), errorHeight=\(errorHeight)", category: Logger.ui)

        let quartzBounds = CGRect(
            x: adjustedBounds.position.x,
            y: adjustedBounds.position.y - errorHeight,  // Move up to get top edge
            width: adjustedBounds.errorWidth,
            height: errorHeight
        )

        Logger.debug("TextMeasurement: quartzBounds (top edge) = \(quartzBounds)", category: Logger.ui)

        // Convert from Quartz (top-left) to Cocoa (bottom-left) coordinates
        // This matches what ModernMarkerStrategy and ClassicRangeStrategy do
        let bounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        Logger.debug("TextMeasurement: bounds after Quartz→Cocoa conversion = \(bounds)", category: Logger.ui)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(bounds) else {
            Logger.debug("TextMeasurementStrategy: Converted bounds failed validation: \(bounds)")
            return nil
        }

        Logger.debug("TextMeasurementStrategy: Successfully estimated bounds (converted to Cocoa): \(bounds)")

        return GeometryResult(
            bounds: bounds,
            confidence: adjustedBounds.confidence,  // Use parser's confidence
            strategy: strategyName,
            metadata: [
                "api": "measurement-estimation",
                "parser": parser.parserName,
                "context": adjustedBounds.uiContext ?? "unknown",
                "debug_info": adjustedBounds.debugInfo
            ]
        )
    }
}
