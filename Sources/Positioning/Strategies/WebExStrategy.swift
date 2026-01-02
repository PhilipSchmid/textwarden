//
//  WebExStrategy.swift
//  TextWarden
//
//  Dedicated positioning strategy for Cisco WebEx chat.
//
//  APPROACH:
//  WebEx uses standard Cocoa text views where AXBoundsForRange works directly.
//  This is a minimal strategy - tries AXBoundsForRange and returns nil on failure
//  to let FontMetricsStrategy handle fallback via WebExContentParser config.
//

import AppKit
import ApplicationServices

/// Dedicated WebEx positioning using standard AXBoundsForRange
class WebExStrategy: GeometryProvider {
    var strategyName: String { "WebEx" }
    var strategyType: StrategyType { .webex }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 6 }

    private static let webexBundleID = "Cisco-Systems.Spark"

    // MARK: - GeometryProvider

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        guard bundleID == Self.webexBundleID else { return false }

        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("WebExStrategy: Skipping - watchdog protection active", category: Logger.ui)
            return false
        }

        guard WebExContentParser.isComposeElement(element) else {
            Logger.debug("WebExStrategy: Skipping - not a compose element", category: Logger.ui)
            return false
        }

        return true
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser _: ContentParser
    ) -> GeometryResult? {
        Logger.debug("WebExStrategy: Calculating for range \(errorRange) in text length \(text.count)", category: Logger.ui)

        // Convert grapheme cluster indices to UTF-16 code unit indices
        // Native Cocoa APIs (including AXBoundsForRange) use UTF-16 indexing
        // Emojis like 😉 are 1 grapheme but 2 UTF-16 code units, causing position drift without conversion
        let utf16Range = TextIndexConverter.graphemeToUTF16Range(errorRange, in: text)
        Logger.debug("WebExStrategy: Converted range \(errorRange) to UTF-16 \(utf16Range)", category: Logger.ui)

        // Try AXBoundsForRange directly (WebEx uses standard Cocoa APIs)
        var cfRange = CFRange(location: utf16Range.location, length: utf16Range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.debug("WebExStrategy: Failed to create range value", category: Logger.ui)
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
            Logger.debug("WebExStrategy: AXBoundsForRange failed - letting chain continue", category: Logger.ui)
            return nil
        }

        var quartzBounds = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &quartzBounds),
              quartzBounds.width >= GeometryConstants.minimumBoundsSize
        else {
            Logger.debug("WebExStrategy: Bounds too small or invalid - letting chain continue", category: Logger.ui)
            return nil
        }

        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("WebExStrategy: Bounds validation failed", category: Logger.ui)
            return nil
        }

        Logger.debug("WebExStrategy: SUCCESS - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: ["api": "bounds-for-range"]
        )
    }
}
