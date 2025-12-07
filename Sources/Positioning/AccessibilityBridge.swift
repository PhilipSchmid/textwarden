//
//  AccessibilityBridge.swift
//  TextWarden
//
//  Low-level Accessibility API wrapper
//  Handles the complex C APIs with Swift-friendly interface
//

import Foundation
import ApplicationServices

// MARK: - Safe AXValue Extraction Helpers

/// Safely extract CGRect from a CFTypeRef that should be an AXValue
/// Returns nil if the value is not an AXValue or extraction fails
func safeAXValueGetRect(_ value: CFTypeRef) -> CGRect? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    var rect = CGRect.zero
    guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else {
        return nil
    }
    return rect
}

/// Safely extract CGPoint from a CFTypeRef that should be an AXValue
/// Returns nil if the value is not an AXValue or extraction fails
func safeAXValueGetPoint(_ value: CFTypeRef) -> CGPoint? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

/// Safely extract CGSize from a CFTypeRef that should be an AXValue
/// Returns nil if the value is not an AXValue or extraction fails
func safeAXValueGetSize(_ value: CFTypeRef) -> CGSize? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else {
        return nil
    }
    return size
}

/// Safely extract CFRange from a CFTypeRef that should be an AXValue
/// Returns nil if the value is not an AXValue or extraction fails
func safeAXValueGetRange(_ value: CFTypeRef) -> CFRange? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    var range = CFRange(location: 0, length: 0)
    guard AXValueGetValue(value as! AXValue, .cfRange, &range) else {
        return nil
    }
    return range
}

/// Low-level Accessibility API wrapper
/// Isolates all C API complexity and provides clean Swift interface
enum AccessibilityBridge {

    // MARK: - Visibility Detection

    /// Get visible character range using AXVisibleCharacterRange
    /// Returns the range of characters currently visible on screen
    /// CRITICAL: Check visibility BEFORE attempting any positioning
    static func getVisibleCharacterRange(_ element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXVisibleCharacterRange" as CFString,
            &value
        )

        guard result == .success, let axValue = value else {
            Logger.debug("AccessibilityBridge: AXVisibleCharacterRange not available")
            return nil
        }

        guard let range = safeAXValueGetRange(axValue) else {
            Logger.debug("AccessibilityBridge: Could not extract CFRange from AXVisibleCharacterRange")
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    /// Check if a range is within the visible character range
    /// Returns true if range overlaps with visible area, false otherwise
    /// Used to skip positioning for text that's scrolled out of view
    static func isRangeVisible(_ range: NSRange, in element: AXUIElement) -> Bool {
        guard let visibleRange = getVisibleCharacterRange(element) else {
            // If we can't determine visibility, assume it's visible
            return true
        }

        // Sanity check: if visible range location is absurdly large (> 1 billion chars), it's invalid
        // This happens with Mail's WebKit which returns Int64.max
        if visibleRange.location > 1_000_000_000 || visibleRange.length > 1_000_000_000 {
            Logger.debug("AccessibilityBridge: Visible range is invalid (\(visibleRange)), assuming visible")
            return true
        }

        // Sanity check: if visible range has zero length, the app doesn't properly support this API
        // This happens with Mac Catalyst apps like Messages which return {0, 0}
        if visibleRange.length == 0 {
            Logger.debug("AccessibilityBridge: Visible range has zero length (\(visibleRange)), assuming visible")
            return true
        }

        // Check if ranges overlap
        let rangeEnd = range.location + range.length
        let visibleEnd = visibleRange.location + visibleRange.length

        let overlaps = range.location < visibleEnd && rangeEnd > visibleRange.location

        if !overlaps {
            Logger.debug("AccessibilityBridge: Range \(range) is outside visible range \(visibleRange)")
        }

        return overlaps
    }

    // MARK: - Edit Area Validation

    /// Get the edit area frame (the text field bounds)
    /// Used to validate that calculated bounds are within the edit area
    static func getEditAreaFrame(_ element: AXUIElement) -> CGRect? {
        return getElementFrame(element)
    }

    /// Validate that bounds are within the edit area frame
    /// Used to detect invalid positioning results
    static func validateBoundsWithinEditArea(
        _ bounds: CGRect,
        editAreaFrame: CGRect,
        tolerance: CGFloat = 50.0
    ) -> Bool {
        // Expand edit area by tolerance for edge cases
        let expandedEditArea = editAreaFrame.insetBy(dx: -tolerance, dy: -tolerance)

        // Check if bounds origin is within expanded edit area
        let originValid = expandedEditArea.contains(bounds.origin)

        if !originValid {
            Logger.debug("AccessibilityBridge: Bounds origin \(bounds.origin) is outside edit area \(editAreaFrame)")
        }

        return originValid
    }

    // MARK: - WebKit Layout-to-Screen Coordinate Conversion

    /// Convert a layout point to screen point for WebKit elements
    /// WebKit internally uses "layout coordinates" which differ from screen coordinates
    /// This is critical for Apple Mail and Safari which use WebKit for text rendering
    static func convertLayoutPointToScreen(
        _ layoutPoint: CGPoint,
        in element: AXUIElement
    ) -> CGPoint? {
        // Create AXValue for the layout point
        var point = layoutPoint
        guard let pointValue = AXValueCreate(.cgPoint, &point) else {
            Logger.warning("AccessibilityBridge: Failed to create CGPoint AXValue for layout-to-screen conversion")
            return nil
        }

        var screenPointValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXScreenPointForLayoutPoint" as CFString,
            pointValue,
            &screenPointValue
        )

        guard result == .success, let spv = screenPointValue else {
            Logger.warning("AccessibilityBridge: AXScreenPointForLayoutPoint failed with error \(result.rawValue)")
            Logger.warning("AccessibilityBridge: Attempted to convert layout point: \(layoutPoint)")
            
            // Check if element supports this attribute
            let attributes = getSupportedParameterizedAttributes(element)
            if !attributes.contains("AXScreenPointForLayoutPoint") {
                Logger.warning("AccessibilityBridge: Element does NOT support AXScreenPointForLayoutPoint!")
                Logger.warning("AccessibilityBridge: Available parameterized attributes: \(attributes)")
            }
            
            return nil
        }

        guard let screenPoint = safeAXValueGetPoint(spv) else {
            Logger.warning("AccessibilityBridge: Failed to extract CGPoint from AXScreenPointForLayoutPoint result")
            return nil
        }

        Logger.debug("AccessibilityBridge: Converted layout point \(layoutPoint) → screen point \(screenPoint)")
        return screenPoint
    }

    /// Convert a layout size to screen size for WebKit elements
    static func convertLayoutSizeToScreen(
        _ layoutSize: CGSize,
        in element: AXUIElement
    ) -> CGSize? {
        var size = layoutSize
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            return nil
        }

        var screenSizeValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXScreenSizeForLayoutSize" as CFString,
            sizeValue,
            &screenSizeValue
        )

        guard result == .success, let ssv = screenSizeValue else {
            return nil
        }

        return safeAXValueGetSize(ssv)
    }

    /// Convert a layout rect to screen rect for WebKit elements
    /// This is the main function used to convert WebKit bounds to screen coordinates
    static func convertLayoutRectToScreen(
        _ layoutRect: CGRect,
        in element: AXUIElement
    ) -> CGRect? {
        // Convert origin
        guard let screenOrigin = convertLayoutPointToScreen(layoutRect.origin, in: element) else {
            Logger.debug("AccessibilityBridge: Layout-to-screen origin conversion failed")
            return nil
        }

        // Convert size (optional - size usually doesn't change much)
        let screenSize: CGSize
        if let convertedSize = convertLayoutSizeToScreen(layoutRect.size, in: element) {
            screenSize = convertedSize
        } else {
            // Fall back to same size if conversion fails
            screenSize = layoutRect.size
        }

        let screenRect = CGRect(origin: screenOrigin, size: screenSize)
        Logger.debug("AccessibilityBridge: Converted layout rect \(layoutRect) to screen rect \(screenRect)")
        return screenRect
    }

    /// Check if element supports WebKit layout-to-screen coordinate conversion
    /// Returns true for WebKit-based apps like Mail, Safari
    static func supportsLayoutToScreenConversion(_ element: AXUIElement) -> Bool {
        let attributes = getSupportedParameterizedAttributes(element)
        return attributes.contains("AXScreenPointForLayoutPoint")
    }

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
        Logger.debug("AccessibilityBridge.calculateBounds() called", category: Logger.accessibility)

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
            Logger.debug("  Start marker validates to index: \(startIndex)", category: Logger.accessibility)
        } else {
            Logger.debug("  Could not get index for start marker", category: Logger.accessibility)
        }

        if let endIndex = indexForMarker(endMarker, in: element) {
            Logger.debug("  End marker validates to index: \(endIndex)", category: Logger.accessibility)
        } else {
            Logger.debug("  Could not get index for end marker", category: Logger.accessibility)
        }

        // Try to get text between markers to validate range
        if let text = getTextUsingMarkers(from: startMarker, to: endMarker, in: element) {
            Logger.debug("  Marker range text: \"\(text)\"", category: Logger.accessibility)
        } else {
            Logger.debug("  Could not get text for marker range", category: Logger.accessibility)
        }

        // Method 1: Use AXTextMarkerRangeForUnorderedTextMarkers API to create proper range
        Logger.info("  Trying AXTextMarkerRangeForUnorderedTextMarkers to create proper range...", category: Logger.accessibility)

        let markerPair = [startMarker, endMarker] as CFArray
        var rangeValue: CFTypeRef?

        let rangeResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
            markerPair,
            &rangeValue
        )

        Logger.info("  AXTextMarkerRangeForUnorderedTextMarkers result: \(rangeResult.rawValue)", category: Logger.accessibility)

        var markerRange: CFTypeRef
        if rangeResult == .success, let properRange = rangeValue {
            Logger.info("  ✓ Created proper marker range via AXTextMarkerRangeForUnorderedTextMarkers", category: Logger.accessibility)
            markerRange = properRange
        } else {
            // Fallback: Pass markers as simple array (some apps accept this)
            Logger.info("  AXTextMarkerRangeForUnorderedTextMarkers failed (\(rangeResult.rawValue)), using array fallback", category: Logger.accessibility)
            markerRange = markerPair
        }

        var boundsValue: CFTypeRef?
        Logger.debug("  Calling AXUIElementCopyParameterizedAttributeValue with AXBoundsForTextMarkerRange...", category: Logger.accessibility)

        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &boundsValue
        )

        Logger.debug("  AXBoundsForTextMarkerRange result: \(result.rawValue) (success=\(result == .success))", category: Logger.accessibility)

        guard result == .success else {
            Logger.debug("  FAILED at AXUIElementCopyParameterizedAttributeValue - AXError code: \(result.rawValue)", category: Logger.accessibility)

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
            Logger.debug("  Error description: \(errorDesc)", category: Logger.accessibility)

            return nil
        }

        Logger.debug("  AXBoundsForTextMarkerRange succeeded, checking boundsValue...", category: Logger.accessibility)

        if let bv = boundsValue {
            let typeID = CFGetTypeID(bv)
            let axValueTypeID = AXValueGetTypeID()
            Logger.debug("  boundsValue typeID: \(typeID), AXValue typeID: \(axValueTypeID), match: \(typeID == axValueTypeID)", category: Logger.accessibility)
        } else {
            Logger.debug("  boundsValue is nil even though result was success!", category: Logger.accessibility)
        }

        guard let axValue = boundsValue,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            Logger.debug("  FAILED at type validation - boundsValue is not an AXValue", category: Logger.accessibility)
            return nil
        }

        Logger.debug("  Type validation passed, extracting CGRect from AXValue...", category: Logger.accessibility)

        guard let rect = safeAXValueGetRect(axValue) else {
            Logger.debug("  FAILED at CGRect extraction from AXValue", category: Logger.accessibility)
            return nil
        }

        Logger.debug("  AXValueGetValue result: true, rect: \(rect)", category: Logger.accessibility)

        // Validate bounds before returning
        Logger.debug("  Validating bounds via CoordinateMapper...", category: Logger.accessibility)

        let isValid = CoordinateMapper.validateBounds(rect)
        Logger.debug("  Bounds validation result: \(isValid)", category: Logger.accessibility)

        guard isValid else {
            Logger.debug("  FAILED at bounds validation: \(rect)", category: Logger.accessibility)
            return nil
        }

        Logger.debug("  SUCCESS - Returning valid bounds: \(rect)", category: Logger.accessibility)

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

        guard let rect = safeAXValueGetRect(axValue) else {
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

    // MARK: - Multi-Line Bounds API

    /// Calculate per-line bounds for a text range that may span multiple lines
    /// Returns an array of bounds, one for each line the range spans
    /// Returns nil if line-based APIs are not available
    /// Returns bounds in Quartz coordinates (top-left origin) - caller must convert
    static func resolveMultiLineBounds(
        _ range: NSRange,
        in element: AXUIElement
    ) -> [CGRect]? {
        // First, get the overall bounds to check if this might be multi-line
        let cfRange = CFRange(location: range.location, length: range.length)
        guard let overallBounds = resolveBoundsUsingRange(cfRange, in: element) else {
            Logger.debug("AccessibilityBridge: Could not get overall bounds for range \(range)")
            return nil
        }

        // Estimate typical line height by getting bounds for a single character
        var typicalLineHeight: CGFloat = 20.0  // Default fallback
        let singleCharRange = CFRange(location: range.location, length: 1)
        if let charBounds = resolveBoundsUsingRange(singleCharRange, in: element) {
            typicalLineHeight = max(charBounds.height, 12.0)  // At least 12px
        }

        // Check if bounds suggest multi-line (height > 1.5x typical line height)
        let estimatedLineCount = Int(ceil(overallBounds.height / typicalLineHeight))
        let likelyMultiLine = overallBounds.height > typicalLineHeight * 1.5

        Logger.debug("AccessibilityBridge: Range \(range) overall bounds: \(overallBounds), lineHeight: \(typicalLineHeight), estimatedLines: \(estimatedLineCount), likelyMultiLine: \(likelyMultiLine)")

        // Try to get line numbers from AX API
        let startLine = tryGetLineForIndex(range.location, in: element)
        let endIndex = range.location + range.length - 1
        let endLine = tryGetLineForIndex(max(0, endIndex), in: element)

        let axReportsMultiLine = startLine != nil && endLine != nil && startLine != endLine

        Logger.debug("AccessibilityBridge: AX reports lines \(startLine ?? -1) to \(endLine ?? -1), axReportsMultiLine: \(axReportsMultiLine)")

        // If AX says single-line AND bounds don't suggest multi-line, return single bounds
        if !axReportsMultiLine && !likelyMultiLine {
            Logger.debug("AccessibilityBridge: Treating as single-line (AX and bounds agree)")
            return [overallBounds]
        }

        // Try Method 1: Use AXRangeForLine to get each line's character range
        // Only if AX reported valid different line numbers
        var lineBounds: [CGRect] = []

        if axReportsMultiLine, let start = startLine, let end = endLine {
            var rangeForLineWorks = true

            for lineNum in start...end {
                // Get the character range for this line
                guard let lineRange = tryGetRangeForLine(lineNum, in: element) else {
                    Logger.debug("AccessibilityBridge: AXRangeForLine failed for line \(lineNum)")
                    rangeForLineWorks = false
                    break
                }

                // Calculate the intersection of our error range with this line's range
                let lineStart = lineRange.location
                let lineEnd = lineRange.location + lineRange.length
                let errorStart = range.location
                let errorEnd = range.location + range.length

                let intersectStart = max(lineStart, errorStart)
                let intersectEnd = min(lineEnd, errorEnd)

                guard intersectStart < intersectEnd else {
                    Logger.debug("AccessibilityBridge: No intersection for line \(lineNum)")
                    continue
                }

                let intersectRange = CFRange(location: intersectStart, length: intersectEnd - intersectStart)

                // Get bounds for this portion of text
                if let bounds = resolveBoundsUsingRange(intersectRange, in: element) {
                    lineBounds.append(bounds)
                    Logger.debug("AccessibilityBridge: Line \(lineNum) bounds: \(bounds)")
                }
            }

            if rangeForLineWorks && !lineBounds.isEmpty {
                Logger.debug("AccessibilityBridge: Calculated \(lineBounds.count) line bounds using AXRangeForLine")
                return lineBounds
            }
        }

        // Method 2: Sample characters to detect line breaks using Y-coordinate changes
        // For very long ranges, sample every N characters to find approximate line boundaries
        Logger.debug("AccessibilityBridge: Falling back to Y-coordinate sampling for multi-line bounds (estimatedLines: \(estimatedLineCount))")
        lineBounds = []

        let rangeLength = range.length

        // Sample rate: check every ~10 characters, but at least sample each expected line
        let sampleStep = max(1, min(10, rangeLength / max(estimatedLineCount * 3, 1)))

        var lineBreakIndices: [Int] = [range.location]  // Start of first line
        var lastY: CGFloat?

        var sampleIndex = range.location
        while sampleIndex < range.location + range.length {
            let charRange = CFRange(location: sampleIndex, length: 1)
            if let charBounds = resolveBoundsUsingRange(charRange, in: element) {
                // Detect line change by Y coordinate change (more than half line height = new line)
                if let prevY = lastY {
                    let yDiff = abs(charBounds.origin.y - prevY)
                    if yDiff > charBounds.height * 0.5 {
                        // Line break detected - find exact boundary with binary search
                        let exactBreak = findLineBreak(
                            between: lineBreakIndices.last ?? range.location,
                            and: sampleIndex,
                            in: element,
                            previousY: prevY
                        ) ?? sampleIndex
                        lineBreakIndices.append(exactBreak)
                        Logger.debug("AccessibilityBridge: Detected line break at index \(exactBreak)")
                    }
                }
                lastY = charBounds.origin.y
            }
            sampleIndex += sampleStep
        }

        // Add end of range as final boundary
        lineBreakIndices.append(range.location + range.length)

        // Convert line break indices to bounds
        for i in 0..<(lineBreakIndices.count - 1) {
            let lineStart = lineBreakIndices[i]
            let lineEnd = lineBreakIndices[i + 1]
            let lineLength = lineEnd - lineStart

            if lineLength > 0 {
                let lineRange = CFRange(location: lineStart, length: lineLength)
                if let bounds = resolveBoundsUsingRange(lineRange, in: element) {
                    lineBounds.append(bounds)
                    Logger.debug("AccessibilityBridge: Line \(i) bounds from sampling: \(bounds)")
                }
            }
        }

        // If we found multiple lines via sampling, return them
        if lineBounds.count > 1 {
            Logger.debug("AccessibilityBridge: Calculated \(lineBounds.count) line bounds using Y-coordinate sampling")
            return lineBounds
        }

        // Method 3: Geometric fallback - split the overall bounds into estimated line segments
        // This is used when AX APIs don't support line-level queries but we know it's multi-line
        Logger.debug("AccessibilityBridge: Using geometric fallback to split bounds into \(estimatedLineCount) lines")
        lineBounds = []

        for lineIndex in 0..<estimatedLineCount {
            // Calculate the Y position for this line segment
            // Overall bounds are in Quartz (top-left origin), so Y increases downward
            let lineY = overallBounds.origin.y + (CGFloat(lineIndex) * typicalLineHeight)

            // For the width, we need to estimate where each line starts and ends
            // For the first line, start at the left edge of overall bounds
            // For middle lines, assume they span the full width
            // For the last line, it may end before the right edge

            let lineRect: CGRect
            if lineIndex == 0 {
                // First line - starts at overall X, width is full or to end of line
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: overallBounds.width,
                    height: typicalLineHeight
                )
            } else if lineIndex == estimatedLineCount - 1 {
                // Last line - may not span full width
                // Estimate based on proportional text
                let lastLineWidth = min(overallBounds.width, overallBounds.width * 0.7)  // Estimate 70% for last line
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: lastLineWidth,
                    height: typicalLineHeight
                )
            } else {
                // Middle lines - span full width
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: overallBounds.width,
                    height: typicalLineHeight
                )
            }

            lineBounds.append(lineRect)
            Logger.debug("AccessibilityBridge: Geometric line \(lineIndex) bounds: \(lineRect)")
        }

        if !lineBounds.isEmpty {
            Logger.debug("AccessibilityBridge: Created \(lineBounds.count) line bounds using geometric split")
            return lineBounds
        }

        // Ultimate fallback - return the overall bounds as single element
        Logger.debug("AccessibilityBridge: All methods failed, returning overall bounds as single line")
        return [overallBounds]
    }

    /// Binary search to find exact line break point between two indices
    private static func findLineBreak(
        between start: Int,
        and end: Int,
        in element: AXUIElement,
        previousY: CGFloat
    ) -> Int? {
        guard end > start + 1 else { return end }

        var low = start
        var high = end

        while high - low > 1 {
            let mid = (low + high) / 2
            let charRange = CFRange(location: mid, length: 1)

            if let charBounds = resolveBoundsUsingRange(charRange, in: element) {
                let yDiff = abs(charBounds.origin.y - previousY)
                if yDiff > charBounds.height * 0.5 {
                    // Line break is before or at mid
                    high = mid
                } else {
                    // Line break is after mid
                    low = mid
                }
            } else {
                // Can't get bounds, move forward
                low = mid
            }
        }

        return high
    }

    // MARK: - Estimation (Fallback)

    /// Estimate position when all AX APIs fail
    /// Very rough estimation - last resort only
    static func estimatePosition(
        at index: Int,
        in element: AXUIElement
    ) -> CGRect? {
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

        guard let origin = safeAXValueGetPoint(position),
              let rectSize = safeAXValueGetSize(size) else {
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
        Logger.debug("Supported parameterized attributes for \(bundleID):", category: Logger.accessibility)

        for attr in attributes {
            Logger.debug("  \(attr)", category: Logger.accessibility)
        }

        if attributes.isEmpty {
            Logger.debug("  No parameterized attributes found", category: Logger.accessibility)
        }
    }

    // MARK: - Comprehensive Notion Diagnostic

    /// Comprehensive diagnostic to find ANY working positioning method for Notion
    /// This function tries EVERY possible AX API method and logs results
    static func runNotionDiagnostic(_ element: AXUIElement) -> NotionDiagnosticResult {
        var result = NotionDiagnosticResult()

        Logger.info("=== NOTION AX DIAGNOSTIC START ===")

        // 1. Get basic element info
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        result.role = roleValue as? String ?? "unknown"
        Logger.info("Element role: \(result.role)")

        // 2. Get element frame
        if let frame = getElementFrame(element) {
            result.elementFrame = frame
            Logger.info("Element frame: \(frame)")
        }

        // 3. Get text content
        var textValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        if let text = textValue as? String {
            result.textLength = text.count
            result.textPreview = String(text.prefix(100))
            Logger.info("Text length: \(text.count), preview: '\(String(text.prefix(50)))'")
        }

        // 4. List all supported attributes
        var attrNames: CFArray?
        if AXUIElementCopyAttributeNames(element, &attrNames) == .success,
           let names = attrNames as? [String] {
            result.supportedAttributes = names
            Logger.info("Supported attributes (\(names.count)): \(names.joined(separator: ", "))")
        }

        // 5. List all supported parameterized attributes
        result.supportedParamAttributes = getSupportedParameterizedAttributes(element)
        Logger.info("Supported parameterized attributes: \(result.supportedParamAttributes.joined(separator: ", "))")

        // 6. Try AXBoundsForRange with different ranges
        Logger.info("--- Testing AXBoundsForRange ---")
        let testRanges: [(String, CFRange)] = [
            ("char0", CFRange(location: 0, length: 1)),
            ("char0-5", CFRange(location: 0, length: 5)),
            ("char10-15", CFRange(location: 10, length: 5)),
            ("char50-55", CFRange(location: 50, length: 5)),
        ]

        for (name, range) in testRanges {
            if let bounds = tryGetBoundsForRange(range, in: element) {
                Logger.info("  \(name): \(bounds) ✓")
                result.workingRangeBounds[name] = bounds
            } else {
                Logger.info("  \(name): FAILED ✗")
            }
        }

        // 7. Try AXLineForIndex - get which line a character is on
        Logger.info("--- Testing AXLineForIndex ---")
        for index in [0, 10, 50, 100] {
            if let lineNum = tryGetLineForIndex(index, in: element) {
                Logger.info("  Index \(index) -> Line \(lineNum) ✓")
                result.lineForIndex[index] = lineNum
            } else {
                Logger.info("  Index \(index): FAILED ✗")
            }
        }

        // 8. Try AXRangeForLine - get character range for a line
        Logger.info("--- Testing AXRangeForLine ---")
        for line in [0, 1, 2, 3] {
            if let range = tryGetRangeForLine(line, in: element) {
                Logger.info("  Line \(line) -> Range(\(range.location), \(range.length)) ✓")
                result.rangeForLine[line] = range

                // Also try to get bounds for this line
                let cfRange = CFRange(location: range.location, length: range.length)
                if let bounds = tryGetBoundsForRange(cfRange, in: element) {
                    Logger.info("    Line \(line) bounds: \(bounds) ✓")
                    result.lineBounds[line] = bounds
                }
            } else {
                Logger.info("  Line \(line): FAILED ✗")
            }
        }

        // 9. Try AXInsertionPointLineNumber
        Logger.info("--- Testing Insertion Point ---")
        var insertionLineValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointLineNumber" as CFString, &insertionLineValue) == .success,
           let lineNum = insertionLineValue as? Int {
            result.insertionPointLine = lineNum
            Logger.info("  AXInsertionPointLineNumber: \(lineNum) ✓")
        } else {
            Logger.info("  AXInsertionPointLineNumber: FAILED ✗")
        }

        // 10. Try AXSelectedTextRange (cursor position)
        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
           let selectedRangeValue = selectedRangeValue,
           let selectedRange = safeAXValueGetRange(selectedRangeValue) {
            result.cursorPosition = selectedRange.location
            Logger.info("  Cursor position: \(selectedRange.location) ✓")

            // Try to get bounds AT cursor position
            let cursorRange = CFRange(location: selectedRange.location, length: 1)
            if let cursorBounds = tryGetBoundsForRange(cursorRange, in: element) {
                result.cursorBounds = cursorBounds
                Logger.info("  Cursor bounds: \(cursorBounds) ✓")
            }
        }

        // 11. Try AXNumberOfCharacters
        var numCharsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &numCharsValue) == .success,
           let numChars = numCharsValue as? Int {
            result.numberOfCharacters = numChars
            Logger.info("  AXNumberOfCharacters: \(numChars) ✓")
        }

        // 12. Try to find children with bounds
        Logger.info("--- Testing Children Hierarchy ---")
        result.childrenWithBounds = findChildrenWithValidBounds(element, depth: 0, maxDepth: 5)
        Logger.info("  Found \(result.childrenWithBounds.count) children with valid bounds")

        // 13. Check AXVisibleCharacterRange
        if let visibleRange = getVisibleCharacterRange(element) {
            result.visibleRange = visibleRange
            Logger.info("  AXVisibleCharacterRange: \(visibleRange) ✓")
        }

        Logger.info("=== NOTION AX DIAGNOSTIC END ===")

        return result
    }

    /// Try to get bounds for a range, returning nil on failure
    private static func tryGetBoundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
        guard let rangeValue = AXValueCreate(.cfRange, withUnsafePointer(to: range) { $0 }) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success, let bv = boundsValue,
              let rect = safeAXValueGetRect(bv) else {
            return nil
        }

        // Return even if bounds seem invalid - we want to see what we get
        return rect
    }

    /// Try to get line number for character index
    private static func tryGetLineForIndex(_ index: Int, in element: AXUIElement) -> Int? {
        var indexValue = index
        guard let indexRef = CFNumberCreate(kCFAllocatorDefault, .intType, &indexValue) else {
            return nil
        }

        var lineValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXLineForIndex" as CFString,
            indexRef,
            &lineValue
        )

        guard result == .success, let line = lineValue as? Int else {
            return nil
        }

        return line
    }

    /// Try to get character range for a line number
    private static func tryGetRangeForLine(_ lineNumber: Int, in element: AXUIElement) -> NSRange? {
        var lineValue = lineNumber
        guard let lineRef = CFNumberCreate(kCFAllocatorDefault, .intType, &lineValue) else {
            return nil
        }

        var rangeValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXRangeForLine" as CFString,
            lineRef,
            &rangeValue
        )

        guard result == .success, let rv = rangeValue,
              let range = safeAXValueGetRange(rv) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    /// Recursively find children that have valid bounds
    private static func findChildrenWithValidBounds(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int
    ) -> [ChildBoundsInfo] {
        guard depth < maxDepth else { return [] }

        var results: [ChildBoundsInfo] = []

        // Get children
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return results
        }

        for (index, child) in children.prefix(20).enumerated() {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? "unknown"

            // Get child's frame
            if let frame = getElementFrame(child), frame.width > 0 && frame.height > 0 && frame.height < 200 {
                // Get text if available
                var textValue: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &textValue)
                let text = textValue as? String

                let info = ChildBoundsInfo(
                    depth: depth,
                    index: index,
                    role: role,
                    frame: frame,
                    textPreview: text?.prefix(30).description
                )
                results.append(info)

                Logger.debug("    Child[\(depth)][\(index)] role=\(role) frame=\(frame) text='\(text?.prefix(20) ?? "nil")'")
            }

            // Recurse
            results.append(contentsOf: findChildrenWithValidBounds(child, depth: depth + 1, maxDepth: maxDepth))
        }

        return results
    }
}

// MARK: - Diagnostic Result Structures

struct NotionDiagnosticResult {
    var role: String = ""
    var elementFrame: CGRect?
    var textLength: Int = 0
    var textPreview: String = ""
    var supportedAttributes: [String] = []
    var supportedParamAttributes: [String] = []
    var workingRangeBounds: [String: CGRect] = [:]
    var lineForIndex: [Int: Int] = [:]
    var rangeForLine: [Int: NSRange] = [:]
    var lineBounds: [Int: CGRect] = [:]
    var insertionPointLine: Int?
    var cursorPosition: Int?
    var cursorBounds: CGRect?
    var numberOfCharacters: Int?
    var visibleRange: NSRange?
    var childrenWithBounds: [ChildBoundsInfo] = []

    /// Check if we have any working positioning method
    var hasWorkingMethod: Bool {
        return !workingRangeBounds.isEmpty ||
               !lineBounds.isEmpty ||
               cursorBounds != nil ||
               !childrenWithBounds.isEmpty
    }

    /// Get the best available method description
    var bestMethodDescription: String {
        if !lineBounds.isEmpty {
            return "Line-based bounds (AXRangeForLine + AXBoundsForRange)"
        }
        if cursorBounds != nil {
            return "Cursor-relative positioning"
        }
        if !workingRangeBounds.isEmpty {
            return "Direct range bounds"
        }
        if !childrenWithBounds.isEmpty {
            return "Children element bounds"
        }
        return "No working method found"
    }
}

struct ChildBoundsInfo {
    let depth: Int
    let index: Int
    let role: String
    let frame: CGRect
    let textPreview: String?
}

// MARK: - InsertionPointFrame Strategy

extension AccessibilityBridge {

    /// Get AXInsertionPointFrame for current cursor position
    /// Works in Chromium when AXBoundsForRange fails
    static func getInsertionPointFrame(_ element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXInsertionPointFrame" as CFString,
            &value
        )

        guard result == .success, let axValue = value else {
            Logger.debug("AccessibilityBridge: AXInsertionPointFrame failed with error \(result.rawValue)")
            return nil
        }

        guard let rect = safeAXValueGetRect(axValue) else {
            Logger.debug("AccessibilityBridge: Could not extract CGRect from AXInsertionPointFrame")
            return nil
        }

        return rect
    }

    /// Get current selection range
    static func getSelectedTextRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success, let axValue = value else {
            return nil
        }

        return safeAXValueGetRange(axValue)
    }

    /// Set selection range - used for cursor-based positioning
    /// Returns true if successful
    static func setSelectedTextRange(_ element: AXUIElement, location: Int, length: Int = 0) -> Bool {
        var range = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            Logger.debug("AccessibilityBridge: Failed to create CFRange value")
            return false
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if result != .success {
            Logger.debug("AccessibilityBridge: Failed to set selection range, error \(result.rawValue)")
        }

        return result == .success
    }

}
