//
//  SelectionBoundsStrategy.swift
//  TextWarden
//
//  Selection-based positioning strategy
//  Sets selection to the target range and queries selection bounds.
//

import Foundation
import ApplicationServices

/// Selection-based positioning strategy
/// Sets selection to error range, reads bounds, restores original selection
class SelectionBoundsStrategy: GeometryProvider {

    var strategyName: String { "SelectionBounds" }
    var tier: StrategyTier { .fallback }
    var tierPriority: Int { 10 }

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Exclude Notion - this strategy manipulates selection which causes cursor flickering
        let notionBundleIDs: Set<String> = [
            "notion.id",
            "com.notion.id"
        ]

        if notionBundleIDs.contains(bundleID) {
            return false
        }

        let chromiumBasedApps: Set<String> = [
            "com.slack.Slack",
            "com.microsoft.VSCode",
            "com.spotify.client",
            "com.discord.Discord",
            "com.figma.Desktop"
        ]

        return chromiumBasedApps.contains(bundleID)
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("SelectionBoundsStrategy: Attempting for range \(errorRange)", category: Logger.ui)

        // Step 1: Save current selection
        guard let originalSelection = getCurrentSelection(element: element) else {
            Logger.debug("SelectionBoundsStrategy: Could not get current selection")
            return nil
        }

        Logger.debug("SelectionBoundsStrategy: Saved original selection at \(originalSelection.location), length \(originalSelection.length)")

        // Step 2: Set selection to error range (adjusted for offset)
        var adjustedRange = errorRange
        if let notionParser = parser as? NotionContentParser {
            adjustedRange = NSRange(
                location: errorRange.location + notionParser.textReplacementOffset,
                length: errorRange.length
            )
        }

        guard setSelection(element: element, range: adjustedRange) else {
            Logger.debug("SelectionBoundsStrategy: Could not set selection to error range")
            return nil
        }

        usleep(10000)  // 10ms for UI update

        // Step 3: Get bounds for the selection
        let bounds = getSelectionBounds(element: element, range: adjustedRange)

        // Step 4: Restore original selection (always do this)
        let restored = setSelection(element: element, range: originalSelection)
        if !restored {
            Logger.warning("SelectionBoundsStrategy: Could not restore original selection!")
        }

        guard let boundsRect = bounds else {
            Logger.debug("SelectionBoundsStrategy: Could not get bounds for selection")
            return nil
        }

        // Validate bounds
        guard boundsRect.width > 0 && boundsRect.height > 0 && boundsRect.height < 200 else {
            Logger.debug("SelectionBoundsStrategy: Invalid bounds \(boundsRect)")
            return nil
        }

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(boundsRect)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("SelectionBoundsStrategy: Converted bounds failed validation")
            return nil
        }

        Logger.debug("SelectionBoundsStrategy: Success! Bounds: \(cocoaBounds)")

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.85,
            strategy: strategyName,
            metadata: [
                "api": "selection-bounds",
                "original_selection": "\(originalSelection)",
                "adjusted_range": "\(adjustedRange)"
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

    private func getSelectionBounds(element: AXUIElement, range: NSRange) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
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

        guard result == .success, let bv = boundsValue else {
            Logger.debug("SelectionBoundsStrategy: AXBoundsForRange failed with code \(result.rawValue)")
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &bounds) else {
            return nil
        }

        return bounds
    }
}
