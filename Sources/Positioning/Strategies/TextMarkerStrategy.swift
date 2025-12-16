//
//  TextMarkerStrategy.swift
//  TextWarden
//
//  Positioning using opaque text markers
//  Works in Electron, Chrome, Safari, and modern apps
//

import AppKit
import ApplicationServices

/// Positioning using opaque text marker API
/// Works where traditional CFRange fails (Electron, Chrome)
class TextMarkerStrategy: GeometryProvider {

    var strategyName: String { "TextMarker" }
    var strategyType: StrategyType { .textMarker }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 1 }

    /// Get bundle ID from an AXUIElement
    private func getBundleID(from element: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"
    }

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // CRITICAL: Do NOT use TextMarkerStrategy for Apple Mail!
        // Mail's WebKit returns different coordinates for AXBoundsForTextMarkerRange vs AXBoundsForRange.
        // AXBoundsForTextMarkerRange returns bounds that are offset from visual text position,
        // while AXBoundsForRange returns correct visual coordinates.
        // RangeBoundsStrategy uses AXBoundsForRange and works correctly for Mail.
        if bundleID == "com.apple.mail" {
            Logger.debug("TextMarkerStrategy: Skipping for Mail - use RangeBoundsStrategy instead", category: Logger.ui)
            return false
        }

        // Check if we should skip AX calls (blacklisted or worker busy)
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("TextMarkerStrategy: Skipping \(bundleID) - watchdog protection active", category: Logger.ui)
            return false
        }

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

        let bundleID = getBundleID(from: element)

        // Double-check watchdog (in case status changed between canHandle and calculateGeometry)
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("TextMarkerStrategy: Skipping calculation - watchdog protection active for \(bundleID)", category: Logger.ui)
            return nil
        }

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let startIndex = errorRange.location + offset
        let endIndex = startIndex + errorRange.length

        // Track AX calls with watchdog
        AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXTextMarkerForIndex")

        guard let startMarker = AccessibilityBridge.requestOpaqueMarker(
            at: startIndex,
            from: element
        ) else {
            AXWatchdog.shared.endCall()
            Logger.debug("TextMarkerStrategy: Failed to create start marker at index \(startIndex)", category: Logger.ui)
            return nil
        }

        guard let endMarker = AccessibilityBridge.requestOpaqueMarker(
            at: endIndex,
            from: element
        ) else {
            AXWatchdog.shared.endCall()
            Logger.debug("TextMarkerStrategy: Failed to create end marker at index \(endIndex)", category: Logger.ui)
            return nil
        }

        // Update watchdog for bounds calculation
        AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXBoundsForTextMarkerRange")

        // Calculate bounds using markers
        guard let rawBounds = AccessibilityBridge.calculateBounds(
            from: startMarker,
            to: endMarker,
            in: element
        ) else {
            AXWatchdog.shared.endCall()
            Logger.debug("TextMarkerStrategy: Failed to calculate bounds between markers", category: Logger.ui)
            return nil
        }

        // AX calls complete
        AXWatchdog.shared.endCall()

        // Log raw bounds for debugging
        Logger.debug("TextMarkerStrategy: Raw bounds from AX: \(rawBounds)", category: Logger.ui)

        // CRITICAL: WebKit-based apps (Mail, Safari) return bounds in "layout coordinates",
        // not screen coordinates. We must convert using AXScreenPointForLayoutPoint.
        var screenBounds: CGRect = rawBounds

        // Try AXScreenPointForLayoutPoint first (preferred method)
        if AccessibilityBridge.supportsLayoutToScreenConversion(element) {
            if let converted = AccessibilityBridge.convertLayoutRectToScreen(rawBounds, in: element) {
                screenBounds = converted
                Logger.debug("TextMarkerStrategy: Converted layout to screen: \(screenBounds)", category: Logger.ui)
            } else {
                Logger.debug("TextMarkerStrategy: Layout-to-screen conversion failed, using fallback", category: Logger.ui)
            }
        }

        // For WebKit elements (like Mail) that don't support AXScreenPointForLayoutPoint,
        // we need to manually calculate the offset between the AX element frame and where
        // text actually renders. WebKit's AXBoundsForRange returns positions relative to
        // the internal layout, not the AXWebArea's screen position.
        //
        // The fix: Calculate the delta between AXWebArea origin and first character origin,
        // then apply this delta to correct all bounds.
        // For parsers with custom bounds (like Mail's WebKit), handle coordinate conversion
        if !AccessibilityBridge.supportsLayoutToScreenConversion(element) &&
           parser.getBoundsForRange(range: NSRange(location: 0, length: 1), in: element) != nil {
            // Get AXWebArea position
            if let areaPosition = AccessibilityBridge.getElementPosition(element) {

                // Get first character bounds to find where text actually starts
                var cfRange = CFRange(location: 0, length: 1)
                if let rangeValue = AXValueCreate(.cfRange, &cfRange) {
                    var firstCharBoundsRef: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForRange" as CFString, rangeValue, &firstCharBoundsRef) == .success,
                       let fcb = firstCharBoundsRef,
                       let firstCharBounds = safeAXValueGetRect(fcb) {

                        // Calculate the delta: how much the text content is offset from AXWebArea
                        // If first char is at X=327 and AXWebArea is at X=303, delta = 24
                        // The bounds we get are in the coordinate system where AXWebArea.origin = (0,0)
                        // We need to add the AXWebArea position to get true screen position
                        let contentOffsetX = firstCharBounds.origin.x - areaPosition.x
                        let contentOffsetY = firstCharBounds.origin.y - areaPosition.y

                        Logger.debug("TextMarkerStrategy: Mail WebKit offset correction: contentOffset=(\(contentOffsetX), \(contentOffsetY))", category: Logger.ui)
                        Logger.debug("TextMarkerStrategy: AXWebArea=\(areaPosition), firstChar=\(firstCharBounds.origin)", category: Logger.ui)

                        // The raw bounds already include this offset (they're at 375, not 72)
                        // But the overlay window is positioned at the AXWebArea, not at firstChar
                        // So we DON'T need to adjust the bounds - they're already correct screen coords
                        //
                        // The REAL issue: the overlay window frame might not match the AXWebArea exactly
                        // due to constraining. The bounds are correct, but the window position is shifted.
                        //
                        // Actually, let me verify: the bounds (375) should be correct if:
                        // - Window is at 305 (constrained from 303)
                        // - Local = 375 - 305 = 70
                        // - Screen = 305 + 70 = 375 ✓
                        //
                        // So the math IS correct. The issue must be elsewhere...
                        // Let me check if maybe the window isn't where we think it is.
                        Logger.info("TextMarkerStrategy: MAIL BOUNDS DEBUG - raw=\(rawBounds), screen should be same", category: Logger.ui)
                    }
                }
            }
        }

        // Convert from Quartz (top-left) to Cocoa (bottom-left) coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(screenBounds)

        // Validate converted bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("TextMarkerStrategy: Converted bounds failed validation: \(cocoaBounds)", category: Logger.accessibility)
            return nil
        }

        // Verify bounds are on-screen
        if !CoordinateMapper.isVisibleOnScreen(cocoaBounds) {
            Logger.warning("TextMarkerStrategy: Bounds are off-screen: \(cocoaBounds)", category: Logger.accessibility)
            // Continue anyway - might be on external monitor
        }

        Logger.debug("TextMarkerStrategy: Successfully calculated bounds: \(cocoaBounds)", category: Logger.accessibility)

        let usedLayoutConversion = AccessibilityBridge.supportsLayoutToScreenConversion(element)
        return GeometryResult.highConfidence(
            bounds: cocoaBounds,
            strategy: strategyName,
            metadata: [
                "api": "opaque-markers",
                "start_index": startIndex,
                "end_index": endIndex,
                "raw_layout_bounds": NSStringFromRect(rawBounds),
                "screen_bounds": NSStringFromRect(screenBounds),
                "cocoa_bounds": NSStringFromRect(cocoaBounds),
                "used_layout_conversion": usedLayoutConversion
            ]
        )
    }
}
