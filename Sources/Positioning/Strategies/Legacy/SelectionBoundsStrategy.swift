//
//  SelectionBoundsStrategy.swift
//  TextWarden
//
//  Selection-based positioning strategy using insertion point frame.
//  For Chromium/Electron apps where AXBoundsForRange returns invalid data.
//
//  Key insight: Set cursor position (zero-length selection), then query
//  AXInsertionPointFrame which often works even when AXBoundsForRange fails.
//

import Foundation
import ApplicationServices
import AppKit

/// Selection-based positioning strategy using insertion point frame
/// Sets cursor position, gets AXInsertionPointFrame, then calculates bounds
class SelectionBoundsStrategy: GeometryProvider {

    var strategyName: String { "SelectionBounds" }
    var strategyType: StrategyType { .selectionBounds }
    var tier: StrategyTier { .fallback }
    var tierPriority: Int { 5 }

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // DISABLED: This strategy manipulates cursor position which interferes with typing.
        // The selection movement is visible to the user and makes the app unusable.
        // We need a non-invasive approach for Chromium apps.
        return false
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("SelectionBoundsStrategy: Attempting for range \(errorRange) in '\(text.prefix(50))...'", category: Logger.ui)

        // Step 1: Save current selection
        guard let originalSelection = getCurrentSelection(element: element) else {
            Logger.debug("SelectionBoundsStrategy: Could not get current selection")
            return nil
        }

        Logger.debug("SelectionBoundsStrategy: Saved original selection at \(originalSelection.location), length \(originalSelection.length)")

        // Step 2: Calculate adjusted range (for offset like in Notion)
        let offset = parser.textReplacementOffset
        let adjustedStart = errorRange.location + offset
        let adjustedEnd = adjustedStart + errorRange.length

        // Step 3: Set cursor to START of error (zero-length selection)
        guard setSelection(element: element, range: NSRange(location: adjustedStart, length: 0)) else {
            Logger.debug("SelectionBoundsStrategy: Could not set cursor to error start")
            restoreSelection(element: element, originalSelection: originalSelection)
            return nil
        }

        usleep(GeometryConstants.shortUIDelay)

        // Step 4: Get insertion point frame at START of error
        guard let startFrame = getInsertionPointFrame(element: element) else {
            Logger.debug("SelectionBoundsStrategy: Could not get insertion point frame at start")
            restoreSelection(element: element, originalSelection: originalSelection)
            return nil
        }

        Logger.debug("SelectionBoundsStrategy: Start frame at \(adjustedStart): \(startFrame)")

        // Step 5: Set cursor to END of error
        guard setSelection(element: element, range: NSRange(location: adjustedEnd, length: 0)) else {
            Logger.debug("SelectionBoundsStrategy: Could not set cursor to error end")
            restoreSelection(element: element, originalSelection: originalSelection)
            return nil
        }

        usleep(GeometryConstants.shortUIDelay)

        // Step 6: Get insertion point frame at END of error
        guard let endFrame = getInsertionPointFrame(element: element) else {
            Logger.debug("SelectionBoundsStrategy: Could not get insertion point frame at end")
            restoreSelection(element: element, originalSelection: originalSelection)
            return nil
        }

        Logger.debug("SelectionBoundsStrategy: End frame at \(adjustedEnd): \(endFrame)")

        // Step 7: Restore original selection (always do this)
        restoreSelection(element: element, originalSelection: originalSelection)

        // Step 8: Calculate bounds from start and end positions
        // Check if start and end are on same line (same Y coordinate)
        let sameLineThreshold: CGFloat = 5.0
        let sameY = abs(startFrame.origin.y - endFrame.origin.y) < sameLineThreshold

        var quartzBounds: CGRect

        if sameY {
            // Single line: bounds span from start.x to end.x
            let width = max(endFrame.origin.x - startFrame.origin.x, 10.0)
            quartzBounds = CGRect(
                x: startFrame.origin.x,
                y: startFrame.origin.y,
                width: width,
                height: startFrame.height
            )
            Logger.debug("SelectionBoundsStrategy: Single line bounds: \(quartzBounds)")
        } else {
            // Multi-line: use start position, estimate width from error text
            let errorText = String(text.dropFirst(errorRange.location).prefix(errorRange.length))
            let font = NSFont.systemFont(ofSize: parser.estimatedFontSize(context: nil))
            let textWidth = (errorText as NSString).size(withAttributes: [.font: font]).width
            let adjustedWidth = textWidth * parser.spacingMultiplier(context: nil)

            quartzBounds = CGRect(
                x: startFrame.origin.x,
                y: startFrame.origin.y,
                width: max(adjustedWidth, 10.0),
                height: startFrame.height
            )
            Logger.debug("SelectionBoundsStrategy: Multi-line, using estimated width: \(quartzBounds)")
        }

        // Validate bounds
        guard quartzBounds.width > 0 && quartzBounds.height > 0 && quartzBounds.height < GeometryConstants.maximumLineHeight else {
            Logger.debug("SelectionBoundsStrategy: Invalid bounds \(quartzBounds)")
            return nil
        }

        // Step 9: Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("SelectionBoundsStrategy: Converted bounds failed validation")
            return nil
        }

        Logger.info("SelectionBoundsStrategy: SUCCESS! Bounds: \(cocoaBounds)")

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.reliableConfidence,
            strategy: strategyName,
            metadata: [
                "api": "insertion-point-frame",
                "start_frame": "\(startFrame)",
                "end_frame": "\(endFrame)",
                "same_line": sameY
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

        guard let range = safeAXValueGetRange(axValue) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    private func setSelection(element: AXUIElement, range: NSRange) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        return result == .success
    }

    private func restoreSelection(element: AXUIElement, originalSelection: NSRange) {
        if !setSelection(element: element, range: originalSelection) {
            Logger.warning("SelectionBoundsStrategy: Could not restore original selection!")
        }
    }

    /// Get the cursor position frame using AXInsertionPointFrame
    /// This API works in Chromium when AXBoundsForRange fails
    private func getInsertionPointFrame(element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXInsertionPointFrame" as CFString,
            &value
        )

        guard result == .success, let axValue = value else {
            Logger.debug("SelectionBoundsStrategy: AXInsertionPointFrame failed: \(result.rawValue)")
            return nil
        }

        guard let frame = safeAXValueGetRect(axValue) else {
            Logger.debug("SelectionBoundsStrategy: Could not extract CGRect from AXInsertionPointFrame")
            return nil
        }

        // Validate frame - Chromium bug may return zero dimensions or negative coordinates
        guard frame.height > GeometryConstants.minimumBoundsSize && frame.height < GeometryConstants.conservativeMaxLineHeight else {
            Logger.debug("SelectionBoundsStrategy: Invalid frame height: \(frame)")
            return nil
        }

        guard frame.origin.x > 0 else {
            Logger.debug("SelectionBoundsStrategy: Invalid frame x position: \(frame)")
            return nil
        }

        return frame
    }
}
