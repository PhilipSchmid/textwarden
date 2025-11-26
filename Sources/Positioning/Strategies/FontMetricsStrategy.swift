//
//  FontMetricsStrategy.swift
//  TextWarden
//
//  Font metrics-based positioning estimation
//  Fallback strategy that works when AX APIs fail
//

import Foundation
import ApplicationServices

/// Font metrics-based positioning strategy
/// Uses ContentParser's adjustBounds() for app-specific estimation
class FontMetricsStrategy: GeometryProvider {

    var strategyName: String { "FontMetrics" }
    var tier: StrategyTier { .estimated }
    var tierPriority: Int { 10 }

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Always available as estimation fallback
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
            Logger.warning("FontMetricsStrategy: Invalid range \(errorRange) for text length \(text.count)")
            return nil
        }

        let textBeforeError = String(text.prefix(startIndex))
        let errorText = String(text[text.index(text.startIndex, offsetBy: startIndex)..<text.index(text.startIndex, offsetBy: endIndex)])

        // Use ContentParser's app-specific estimation
        guard let adjustedBounds = parser.adjustBounds(
            element: element,
            errorRange: errorRange,
            textBeforeError: textBeforeError,
            errorText: errorText,
            fullText: text
        ) else {
            Logger.debug("FontMetricsStrategy: Parser returned nil for bounds")
            return nil
        }

        // Convert AdjustedBounds to CGRect
        let fontSize = parser.estimatedFontSize(context: adjustedBounds.uiContext)
        let errorHeight: CGFloat = fontSize * 1.2

        Logger.debug("FontMetrics: adjustedBounds.position = \(adjustedBounds.position), fontSize=\(fontSize), errorHeight=\(errorHeight)", category: Logger.ui)

        let quartzBounds = CGRect(
            x: adjustedBounds.position.x,
            y: adjustedBounds.position.y - errorHeight,
            width: adjustedBounds.errorWidth,
            height: errorHeight
        )

        Logger.debug("FontMetrics: quartzBounds = \(quartzBounds)", category: Logger.ui)

        // Convert from Quartz to Cocoa coordinates
        let bounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        Logger.debug("FontMetrics: bounds after conversion = \(bounds)", category: Logger.ui)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(bounds) else {
            Logger.debug("FontMetricsStrategy: Converted bounds failed validation: \(bounds)")
            return nil
        }

        Logger.debug("FontMetricsStrategy: Successfully estimated bounds: \(bounds)")

        return GeometryResult(
            bounds: bounds,
            confidence: adjustedBounds.confidence,
            strategy: strategyName,
            metadata: [
                "api": "font-metrics",
                "parser": parser.parserName,
                "context": adjustedBounds.uiContext ?? "unknown",
                "debug_info": adjustedBounds.debugInfo
            ]
        )
    }
}
