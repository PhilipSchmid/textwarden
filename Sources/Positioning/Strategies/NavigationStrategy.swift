//
//  NavigationStrategy.swift
//  TextWarden
//
//  Navigation-based positioning strategy
//  Uses synthetic key events to move the cursor and measure position.
//

import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Navigation-based positioning strategy
/// Uses synthetic key events to move cursor and measure real screen position.
/// Works when standard AX APIs fail.
class NavigationStrategy: GeometryProvider {

    var strategyName: String { "Navigation" }
    var tier: StrategyTier { .reliable }  // Promoted - this is key for Chromium apps!
    var tierPriority: Int { 4 }  // Try before SelectionBounds and FontMetrics

    // Key codes for arrow keys
    private let kVK_LeftArrow: CGKeyCode = 123
    private let kVK_RightArrow: CGKeyCode = 124

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // DISABLED: This strategy uses synthetic arrow key presses which interferes with typing.
        // The cursor movement is visible to the user and makes the app unusable.
        // We need a non-invasive approach for Chromium apps.
        return false
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("NavigationStrategy: Starting for range \(errorRange)", category: Logger.ui)

        // Step 1: Get current cursor position
        guard let originalSelection = getCurrentSelection(element: element) else {
            Logger.debug("NavigationStrategy: Could not get current selection")
            return nil
        }

        let originalPosition = originalSelection.location
        Logger.debug("NavigationStrategy: Original cursor at \(originalPosition)")

        // Adjust for UI element offset if needed
        var targetPosition = errorRange.location
        if let notionParser = parser as? NotionContentParser {
            targetPosition = errorRange.location + notionParser.textReplacementOffset
        }

        Logger.debug("NavigationStrategy: Target position is \(targetPosition)")

        // Step 2: Calculate how many arrow keys to press
        let delta = targetPosition - originalPosition

        // Step 3: Move cursor using arrow keys
        let moved = moveCursorByArrowKeys(delta: delta, element: element)
        if !moved {
            Logger.debug("NavigationStrategy: Failed to move cursor")
            return nil
        }

        usleep(20000)  // 20ms for UI update

        // Step 4: Get cursor bounds at new position
        let cursorBounds = getCursorBounds(element: element, position: targetPosition)

        // Step 5: Always restore original position
        let restoreDelta = originalPosition - targetPosition
        let _ = moveCursorByArrowKeys(delta: restoreDelta, element: element)

        guard let bounds = cursorBounds else {
            Logger.debug("NavigationStrategy: Could not get cursor bounds at target")
            return nil
        }

        // Validate bounds
        guard bounds.width >= 0 && bounds.height > 0 && bounds.height < 100 else {
            Logger.debug("NavigationStrategy: Invalid bounds \(bounds)")
            return nil
        }

        // Calculate error width
        let fontSize = parser.estimatedFontSize(context: nil)
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let errorEnd = min(errorRange.location + errorRange.length, text.count)
        let errorStart = min(errorRange.location, text.count)
        // Safe string slicing to handle UTF-16/character count mismatches
        guard let errorStartIdx = text.index(text.startIndex, offsetBy: errorStart, limitedBy: text.endIndex),
              let errorEndIdx = text.index(text.startIndex, offsetBy: errorEnd, limitedBy: text.endIndex),
              errorStartIdx <= errorEndIdx else {
            Logger.debug("NavigationStrategy: String index out of bounds for error text")
            return nil
        }
        let errorText = String(text[errorStartIdx..<errorEndIdx])
        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 20.0)

        let finalBounds = CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y,
            width: errorWidth,
            height: bounds.height
        )

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(finalBounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("NavigationStrategy: Converted bounds failed validation")
            return nil
        }

        Logger.debug("NavigationStrategy: Success! Bounds: \(cocoaBounds)")

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.90,
            strategy: strategyName,
            metadata: [
                "api": "cursor-navigation",
                "delta": "\(delta)",
                "measured_at": "\(targetPosition)"
            ]
        )
    }

    // MARK: - Selection Management

    private func getCurrentSelection(element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success, let axValue = value else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    // MARK: - Cursor Movement

    private func moveCursorByArrowKeys(delta: Int, element: AXUIElement) -> Bool {
        if delta == 0 {
            return true
        }

        let keyCode: CGKeyCode = delta > 0 ? kVK_RightArrow : kVK_LeftArrow
        let steps = abs(delta)

        // Limit steps to avoid long waits
        guard steps < 500 else {
            Logger.debug("NavigationStrategy: Delta \(delta) too large, skipping")
            return false
        }

        Logger.debug("NavigationStrategy: Moving cursor by \(delta) chars (\(steps) key presses)")

        for _ in 0..<steps {
            if !pressKey(keyCode: keyCode) {
                return false
            }
            usleep(1000)  // 1ms between presses
        }

        return true
    }

    private func pressKey(keyCode: CGKeyCode) -> Bool {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            return false
        }

        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    // MARK: - Cursor Bounds

    private func getCursorBounds(element: AXUIElement, position: Int) -> CGRect? {
        // Try AXInsertionPointFrame FIRST - this is more reliable after synthetic navigation
        // AXBoundsForRange often returns bogus (0,0,0,0) data in Chromium apps
        var insertionValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointFrame" as CFString, &insertionValue) == .success,
           let axValue = insertionValue,
           CFGetTypeID(axValue) == AXValueGetTypeID() {
            var frame = CGRect.zero
            if AXValueGetValue(axValue as! AXValue, .cgRect, &frame) {
                // Validate the frame
                if frame.height > 5 && frame.height < 100 && frame.origin.x > 0 {
                    Logger.debug("NavigationStrategy: Got valid bounds from AXInsertionPointFrame: \(frame)")
                    return frame
                } else {
                    Logger.debug("NavigationStrategy: AXInsertionPointFrame returned invalid frame: \(frame)")
                }
            }
        }

        // Fallback to AXBoundsForRange
        var cfRange = CFRange(location: position, length: 1)
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

        if result == .success, let bv = boundsValue,
           CFGetTypeID(bv) == AXValueGetTypeID() {
            var bounds = CGRect.zero
            if AXValueGetValue(bv as! AXValue, .cgRect, &bounds) {
                // Validate bounds - Chromium bug returns (0, y, 0, 0)
                if bounds.width > 0 && bounds.height > 5 && bounds.origin.x > 0 {
                    Logger.debug("NavigationStrategy: Got valid bounds from AXBoundsForRange: \(bounds)")
                    return bounds
                } else {
                    Logger.debug("NavigationStrategy: AXBoundsForRange returned invalid bounds: \(bounds)")
                }
            }
        }

        Logger.debug("NavigationStrategy: Could not get valid cursor bounds at position \(position)")
        return nil
    }
}
