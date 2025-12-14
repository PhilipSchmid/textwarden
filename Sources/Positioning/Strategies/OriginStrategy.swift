//
//  OriginStrategy.swift
//  TextWarden
//
//  Position extraction strategy for Chromium/Electron apps
//  Some apps return valid position (x, y) but zero width/height from AXBoundsForRange.
//  This strategy extracts just the position and estimates dimensions.
//

import Foundation
import AppKit
import ApplicationServices

/// Position extraction strategy
/// Uses AXBoundsForRange position even when width/height are zero
class OriginStrategy: GeometryProvider {

    var strategyName: String { "Origin" }
    var strategyType: StrategyType { .origin }
    var tier: StrategyTier { .reliable }
    var tierPriority: Int { 20 }

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Designed for Chromium/Electron apps that return zero dimensions
        let chromiumApps: Set<String> = [
            "notion.id",
            "com.notion.id",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "org.chromium.Chromium",
            "com.tinyspeck.slackmacgap",
        ]
        return chromiumApps.contains(bundleID)
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("OriginStrategy: Starting for range \(errorRange)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let originalRange = NSRange(location: errorRange.location + offset, length: errorRange.length)

        // Get raw bounds without validation (using original coordinates)
        guard let rawBounds = getRawBoundsForRange(originalRange, in: element) else {
            Logger.debug("OriginStrategy: Could not get raw bounds", category: Logger.accessibility)
            return nil
        }

        Logger.debug("OriginStrategy: Raw bounds from AX: \(rawBounds)", category: Logger.ui)

        // Check if position is valid (even if dimensions are zero)
        let hasValidPosition = rawBounds.origin.y > 0 &&
                               rawBounds.origin.y < 10000 &&
                               !rawBounds.origin.x.isNaN &&
                               !rawBounds.origin.y.isNaN

        guard hasValidPosition else {
            Logger.debug("OriginStrategy: Position not valid - x=\(rawBounds.origin.x), y=\(rawBounds.origin.y)", category: Logger.accessibility)
            return nil
        }

        Logger.debug("OriginStrategy: Position is VALID! x=\(rawBounds.origin.x), y=\(rawBounds.origin.y)", category: Logger.ui)

        // Estimate dimensions using font measurement
        let context = parser.detectUIContext(element: element)
        let fontSize = parser.estimatedFontSize(context: context)
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Get error text (using original coordinates)
        let errorEndIndex = min(originalRange.location + originalRange.length, text.count)
        let errorStartIndex = min(originalRange.location, text.count)
        guard errorStartIndex < errorEndIndex else {
            Logger.debug("OriginStrategy: Invalid error indices", category: Logger.accessibility)
            return nil
        }

        // Safe string slicing to handle UTF-16/character count mismatches
        guard let errorStartIdx = text.index(text.startIndex, offsetBy: errorStartIndex, limitedBy: text.endIndex),
              let errorEndIdx = text.index(text.startIndex, offsetBy: errorEndIndex, limitedBy: text.endIndex),
              errorStartIdx <= errorEndIdx else {
            Logger.debug("OriginStrategy: String index out of bounds for error text", category: Logger.accessibility)
            return nil
        }
        let errorText = String(text[errorStartIdx..<errorEndIdx])
        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 20.0)
        let errorHeight = fontSize * 1.3

        Logger.debug("OriginStrategy: Estimated width=\(errorWidth), height=\(errorHeight) for '\(errorText)'", category: Logger.ui)

        // Construct bounds using valid position and estimated dimensions
        let quartzBounds = CGRect(
            x: rawBounds.origin.x,
            y: rawBounds.origin.y,
            width: errorWidth,
            height: errorHeight
        )

        Logger.debug("OriginStrategy: Quartz bounds: \(quartzBounds)", category: Logger.ui)

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        Logger.debug("OriginStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        // Validate final bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("OriginStrategy: Final bounds validation failed: \(cocoaBounds)", category: Logger.accessibility)
            return nil
        }

        Logger.debug("OriginStrategy: SUCCESS - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.85,
            strategy: strategyName,
            metadata: [
                "api": "origin-extraction",
                "raw_position": "(\(rawBounds.origin.x), \(rawBounds.origin.y))",
                "raw_dimensions": "(\(rawBounds.width), \(rawBounds.height))",
                "estimated_dimensions": "(\(errorWidth), \(errorHeight))"
            ]
        )
    }

    // MARK: - Raw AX Access (bypasses validation)

    private func getRawBoundsForRange(_ range: NSRange, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: max(1, range.length))
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success,
              let bv = boundsValue,
              let bounds = safeAXValueGetRect(bv) else {
            Logger.debug("OriginStrategy: AXBoundsForRange failed with error \(result.rawValue)", category: Logger.accessibility)
            return nil
        }

        return bounds
    }
}
