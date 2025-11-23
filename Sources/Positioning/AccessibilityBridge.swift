//
//  AccessibilityBridge.swift
//  Gnau
//
//  Low-level Accessibility API wrapper
//  Handles the complex C APIs with Swift-friendly interface
//

import Foundation
import ApplicationServices

/// Low-level Accessibility API wrapper
/// Isolates all C API complexity and provides clean Swift interface
enum AccessibilityBridge {

    // MARK: - Capability Detection

    /// Check if element supports modern opaque marker API
    /// Used to determine if ModernMarkerStrategy can be used
    static func supportsOpaqueMarkers(_ element: AXUIElement) -> Bool {
        // Try to create a marker for index 0 as capability test
        var indexValue: Int = 0
        guard let indexRef = CFNumberCreate(
            kCFAllocatorDefault,
            .intType,
            &indexValue
        ) else {
            return false
        }

        var markerValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerForIndex" as CFString,
            indexRef,
            &markerValue
        )

        return result == .success && markerValue != nil
    }

    // MARK: - Opaque Marker API (Modern - for Electron/Chrome)

    /// Request opaque marker for character index
    /// Returns marker that can be used with calculateBounds(from:to:)
    static func requestOpaqueMarker(
        at index: Int,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var indexValue: Int = index
        guard let indexRef = CFNumberCreate(
            kCFAllocatorDefault,
            .intType,
            &indexValue
        ) else {
            Logger.debug("Failed to create CFNumber for index \(index)")
            return nil
        }

        var markerValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerForIndex" as CFString,
            indexRef,
            &markerValue
        )

        guard result == .success, let marker = markerValue else {
            if result != .success {
                Logger.debug("Failed to create opaque marker at index \(index): AXError \(result.rawValue)")
            }
            return nil
        }

        return marker
    }

    /// Calculate bounds between two opaque markers
    /// Returns bounds in Quartz coordinates (top-left origin) - caller must convert
    static func calculateBounds(
        from startMarker: CFTypeRef,
        to endMarker: CFTypeRef,
        in element: AXUIElement
    ) -> CGRect? {
        let msg1 = "🔬 AccessibilityBridge.calculateBounds() called"
        NSLog(msg1)
        logToDebugFile(msg1)

        // Log what parameterized attributes this element supports (ONCE per session)
        struct DebugState {
            static var hasLoggedAttributes = false
        }
        if !DebugState.hasLoggedAttributes {
            logSupportedAttributes(element, bundleID: "current")
            DebugState.hasLoggedAttributes = true
        }

        // Validate markers by converting them back to indices
        if let startIndex = indexForMarker(startMarker, in: element) {
            let msg = "🔬   Start marker validates to index: \(startIndex)"
            NSLog(msg)
            logToDebugFile(msg)
        } else {
            let msg = "🔬   ⚠️ Could not get index for start marker"
            NSLog(msg)
            logToDebugFile(msg)
        }

        if let endIndex = indexForMarker(endMarker, in: element) {
            let msg = "🔬   End marker validates to index: \(endIndex)"
            NSLog(msg)
            logToDebugFile(msg)
        } else {
            let msg = "🔬   ⚠️ Could not get index for end marker"
            NSLog(msg)
            logToDebugFile(msg)
        }

        // Try to get text between markers to validate range
        if let text = getTextUsingMarkers(from: startMarker, to: endMarker, in: element) {
            let msg = "🔬   Marker range text: \"\(text)\""
            NSLog(msg)
            logToDebugFile(msg)
        } else {
            let msg = "🔬   ⚠️ Could not get text for marker range"
            NSLog(msg)
            logToDebugFile(msg)
        }

        // CRITICAL: Pass markers as a simple array
        // Some Electron apps (like Slack) expect a CFArray, not a special AXTextMarkerRange object
        let msg2 = "🔬   Creating marker range as CFArray [startMarker, endMarker]..."
        NSLog(msg2)
        logToDebugFile(msg2)

        let markerRange = [startMarker, endMarker] as CFArray

        let msg2c = "🔬   ✅ Created marker range array"
        NSLog(msg2c)
        logToDebugFile(msg2c)

        var boundsValue: CFTypeRef?
        let msg3 = "🔬   Calling AXUIElementCopyParameterizedAttributeValue with AXBoundsForTextMarkerRange..."
        NSLog(msg3)
        logToDebugFile(msg3)

        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &boundsValue
        )

        let msg4 = "🔬   AXBoundsForTextMarkerRange result: \(result.rawValue) (success=\(result == .success))"
        NSLog(msg4)
        logToDebugFile(msg4)

        guard result == .success else {
            let msg = "🔬   ❌ FAILED at AXUIElementCopyParameterizedAttributeValue - AXError code: \(result.rawValue)"
            Logger.debug(msg)
            NSLog(msg)
            logToDebugFile(msg)

            // Log what the error code means
            let errorDesc: String
            switch result {
            case .apiDisabled: errorDesc = "API disabled (user needs to enable accessibility)"
            case .notImplemented: errorDesc = "Not implemented (attribute not supported)"
            case .attributeUnsupported: errorDesc = "Attribute unsupported"
            case .invalidUIElement: errorDesc = "Invalid UI element"
            case .illegalArgument: errorDesc = "Illegal argument (marker range format wrong?)"
            case .failure: errorDesc = "Generic failure"
            default: errorDesc = "Unknown error"
            }
            let msg2 = "🔬   Error description: \(errorDesc)"
            NSLog(msg2)
            logToDebugFile(msg2)

            return nil
        }

        let msg5 = "🔬   AXBoundsForTextMarkerRange succeeded, checking boundsValue..."
        NSLog(msg5)
        logToDebugFile(msg5)

        if let bv = boundsValue {
            let typeID = CFGetTypeID(bv)
            let axValueTypeID = AXValueGetTypeID()
            let msg = "🔬   boundsValue typeID: \(typeID), AXValue typeID: \(axValueTypeID), match: \(typeID == axValueTypeID)"
            NSLog(msg)
            logToDebugFile(msg)
        } else {
            let msg = "🔬   ⚠️ boundsValue is nil even though result was success!"
            NSLog(msg)
            logToDebugFile(msg)
        }

        guard let axValue = boundsValue,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            let msg = "🔬   ❌ FAILED at type validation - boundsValue is not an AXValue"
            Logger.debug(msg)
            NSLog(msg)
            logToDebugFile(msg)
            return nil
        }

        let msg6 = "🔬   Type validation passed, extracting CGRect from AXValue..."
        NSLog(msg6)
        logToDebugFile(msg6)

        var rect = CGRect.zero
        let success = AXValueGetValue(axValue as! AXValue, .cgRect, &rect)

        let msg7 = "🔬   AXValueGetValue result: \(success), rect: \(rect)"
        NSLog(msg7)
        logToDebugFile(msg7)

        guard success else {
            let msg = "🔬   ❌ FAILED at CGRect extraction from AXValue"
            Logger.debug(msg)
            NSLog(msg)
            logToDebugFile(msg)
            return nil
        }

        // Validate bounds before returning
        let msg8 = "🔬   Validating bounds via CoordinateMapper..."
        NSLog(msg8)
        logToDebugFile(msg8)

        let isValid = CoordinateMapper.validateBounds(rect)
        let msg9 = "🔬   Bounds validation result: \(isValid)"
        NSLog(msg9)
        logToDebugFile(msg9)

        guard isValid else {
            let msg = "🔬   ❌ FAILED at bounds validation: \(rect)"
            Logger.debug(msg)
            NSLog(msg)
            logToDebugFile(msg)
            return nil
        }

        let msg10 = "🔬   ✅ SUCCESS - Returning valid bounds: \(rect)"
        NSLog(msg10)
        logToDebugFile(msg10)

        return rect
    }

    // MARK: - Classic Range API (for native apps)

    /// Resolve bounds using traditional CFRange API
    /// Returns bounds in Quartz coordinates (top-left origin) - caller must convert
    static func resolveBoundsUsingRange(
        _ range: CFRange,
        in element: AXUIElement
    ) -> CGRect? {
        guard let rangeValue = AXValueCreate(.cfRange, withUnsafePointer(to: range) { $0 }) else {
            Logger.debug("Failed to create AXValue for CFRange")
            return nil
        }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success else {
            Logger.debug("Failed to get bounds for range: AXError \(result.rawValue)")
            return nil
        }

        guard let axValue = boundsValue,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            Logger.debug("AXBoundsForRange returned non-AXValue type")
            return nil
        }

        var rect = CGRect.zero
        let success = AXValueGetValue(axValue as! AXValue, .cgRect, &rect)

        guard success else {
            Logger.debug("Failed to extract CGRect from AXValue")
            return nil
        }

        // Validate bounds before returning
        guard CoordinateMapper.validateBounds(rect) else {
            Logger.debug("Range bounds failed validation: \(rect)")
            return nil
        }

        return rect
    }

    // MARK: - Estimation (Fallback)

    /// Estimate position when all AX APIs fail
    /// Very rough estimation - last resort only
    static func estimatePosition(
        at index: Int,
        in element: AXUIElement
    ) -> CGRect? {
        // Get element frame as starting point
        guard let elementFrame = getElementFrame(element) else {
            return nil
        }

        // Rough estimation based on character index
        let averageCharWidth: CGFloat = 9.0
        let estimatedX = elementFrame.origin.x + (CGFloat(index) * averageCharWidth)
        let estimatedY = elementFrame.origin.y + (elementFrame.height * 0.25)

        return CGRect(
            x: estimatedX,
            y: estimatedY,
            width: averageCharWidth * 5,  // Assume ~5 characters
            height: elementFrame.height * 0.5
        )
    }

    // MARK: - Helper Methods

    /// Get element frame in Quartz coordinates
    private static func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let positionResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )

        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard positionResult == .success,
              sizeResult == .success,
              let position = positionValue,
              let size = sizeValue else {
            return nil
        }

        var origin = CGPoint.zero
        var rectSize = CGSize.zero

        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &rectSize) else {
            return nil
        }

        return CGRect(origin: origin, size: rectSize)
    }

    /// Get text content using modern marker API
    /// Useful for validation and debugging
    static func getTextUsingMarkers(
        from startMarker: CFTypeRef,
        to endMarker: CFTypeRef,
        in element: AXUIElement
    ) -> String? {
        let markerRange = [startMarker, endMarker] as CFArray

        var textValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRange,
            &textValue
        )

        guard result == .success, let text = textValue as? String else {
            return nil
        }

        return text
    }

    /// Convert marker back to character index
    /// Useful for validation
    static func indexForMarker(_ marker: CFTypeRef, in element: AXUIElement) -> Int? {
        var indexValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXIndexForTextMarker" as CFString,
            marker,
            &indexValue
        )

        guard result == .success,
              let number = indexValue as? NSNumber else {
            return nil
        }

        return number.intValue
    }

    /// Get all supported parameterized attributes for an element
    /// Diagnostic function to discover what APIs are available
    static func getSupportedParameterizedAttributes(_ element: AXUIElement) -> [String] {
        var attributesValue: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(
            element,
            &attributesValue
        )

        guard result == .success,
              let cfArray = attributesValue,
              let attributes = cfArray as? [String] else {
            return []
        }

        return attributes
    }

    /// Log all supported parameterized attributes for debugging
    static func logSupportedAttributes(_ element: AXUIElement, bundleID: String) {
        let attributes = getSupportedParameterizedAttributes(element)
        let msg1 = "🔎 Supported parameterized attributes for \(bundleID):"
        NSLog(msg1)
        logToDebugFile(msg1)

        for attr in attributes {
            let msg = "  📋 \(attr)"
            NSLog(msg)
            logToDebugFile(msg)
        }

        if attributes.isEmpty {
            let msg = "  ⚠️ No parameterized attributes found"
            NSLog(msg)
            logToDebugFile(msg)
        }
    }
}
