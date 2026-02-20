//
//  ClaudeStrategy.swift
//  TextWarden
//
//  Positioning strategy for Claude Desktop (Electron app).
//
//  Claude's AX API characteristics:
//  - The main AXTextArea returns garbage for AXBoundsForRange
//  - BUT: Child AXStaticText elements have VALID AXBoundsForRange!
//  - Solution: Traverse the tree to find AXStaticText containing the error
//

import AppKit
import ApplicationServices
import Foundation

/// Tree-traversal positioning strategy for Claude Desktop
///
/// Finds the AXStaticText child element containing the error and uses
/// its AXBoundsForRange for accurate positioning.
class ClaudeStrategy: GeometryProvider {
    var strategyName: String {
        "Claude"
    }

    var strategyType: StrategyType {
        .claude
    }

    var tier: StrategyTier {
        .precise
    }

    var tierPriority: Int {
        0
    }

    // MARK: - Thread Safety

    private static let stateQueue = DispatchQueue(label: "com.textwarden.claude-strategy", qos: .userInitiated)

    // MARK: - Cache State

    private static var _boundsCache: [NSRange: CGRect] = [:]
    private static var _cachedText: String = ""
    private static var _cachedElementFrame: CGRect = .zero
    private static var _lastTextChangeTime: Date = .distantPast

    /// Cached visible range to detect scrolling
    private static var _cachedVisibleRange: NSRange = .init(location: 0, length: 0)

    /// Cached text segments from tree traversal (expensive to compute)
    private static var _cachedSegments: [(element: AXUIElement, startOffset: Int, text: String)] = []
    private static var _segmentsCacheText: String = ""

    /// Minimum time text must be stable before measuring
    private static let typingPauseThreshold: TimeInterval = 0.3

    // MARK: - Public Interface

    func canHandle(element _: AXUIElement, bundleID: String) -> Bool {
        bundleID == "com.anthropic.claudefordesktop"
    }

    /// Called when text changes to track typing activity
    static func notifyTextChange() {
        stateQueue.sync {
            _lastTextChangeTime = Date()
        }
    }

    /// Check if user is currently typing
    static var isCurrentlyTyping: Bool {
        stateQueue.sync {
            Date().timeIntervalSince(_lastTextChangeTime) < typingPauseThreshold
        }
    }

    /// Clear cache when text changes or scroll detected
    static func invalidateCache() {
        stateQueue.sync {
            _boundsCache.removeAll()
            _cachedText = ""
            _cachedElementFrame = .zero
            _cachedVisibleRange = NSRange(location: 0, length: 0)
            _cachedSegments.removeAll()
            _segmentsCacheText = ""
        }
    }

    // MARK: - Geometry Calculation

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {
        let offset = parser.textReplacementOffset
        let startIndex = errorRange.location + offset
        let graphemeRange = NSRange(location: startIndex, length: errorRange.length)

        // IMPORTANT: Don't use bounds cache for Claude/Electron
        // Claude's AXVisibleCharacterRange always returns the full text (doesn't report actual
        // visible range), so we can't detect scroll to invalidate the cache. Without reliable
        // scroll detection, cached bounds become stale and cause underlines at wrong positions.
        // Always recalculate bounds fresh.

        // Don't measure while user is typing
        guard !ClaudeStrategy.isCurrentlyTyping else {
            Logger.debug("ClaudeStrategy: Skipping - user is typing", category: Logger.analysis)
            return GeometryResult.unavailable(reason: "Waiting for typing pause")
        }

        // Find bounds using tree traversal
        guard let bounds = findBoundsInTree(
            for: graphemeRange,
            element: element,
            fullText: text
        ) else {
            Logger.debug("ClaudeStrategy: Failed to find bounds in tree for range \(graphemeRange)", category: Logger.analysis)
            // Return unavailable (not nil) to prevent fallback to other strategies
            // which would give incorrect positions for Claude's Electron text area
            return GeometryResult.unavailable(reason: "Could not locate error in Claude AX tree")
        }

        // Convert from Quartz to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(bounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("ClaudeStrategy: Bounds failed validation", category: Logger.ui)
            return nil
        }

        Logger.debug("ClaudeStrategy: Found bounds \(cocoaBounds) for range \(graphemeRange)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.95, // High confidence for direct AX bounds
            strategy: strategyName,
            metadata: [
                "api": "tree-traversal",
                "skip_resolver_cache": true,
            ]
        )
    }

    // MARK: - Tree Traversal

    /// Find bounds for a range by traversing child elements
    private func findBoundsInTree(
        for range: NSRange,
        element: AXUIElement,
        fullText: String
    ) -> CGRect? {
        // IMPORTANT: Don't cache segments for Claude/Electron apps
        // Electron recycles AXUIElements unpredictably during scroll, making cached
        // element references stale even when text content hasn't changed.
        // Always rebuild the segment map to ensure we have fresh element references.
        var segments: [(element: AXUIElement, startOffset: Int, text: String)] = []
        collectTextSegmentsWithPositions(from: element, fullText: fullText, into: &segments)
        Logger.debug("ClaudeStrategy: Built fresh segments (\(segments.count) segments)", category: Logger.analysis)

        // Find the segment containing our error range
        for segment in segments {
            let segmentEnd = segment.startOffset + segment.text.count

            // Check if this segment contains the start of our range
            if range.location >= segment.startOffset, range.location < segmentEnd {
                // Calculate local range within this segment
                let localStart = range.location - segment.startOffset
                let availableLength = segment.text.count - localStart
                let localLength = min(range.length, availableLength)

                guard localLength > 0 else { continue }

                let localRange = NSRange(location: localStart, length: localLength)

                // Get bounds for this local range
                if let bounds = getBoundsForRange(localRange, in: segment.element) {
                    Logger.debug("ClaudeStrategy: Found bounds in segment at offset \(segment.startOffset), local range \(localRange)", category: Logger.analysis)
                    return bounds
                }
            }
        }

        Logger.debug("ClaudeStrategy: No segment found containing range \(range)", category: Logger.analysis)
        return nil
    }

    /// Optimized segment collection - find actual positions in full text
    private func collectTextSegmentsWithPositions(
        from element: AXUIElement,
        fullText: String,
        into segments: inout [(element: AXUIElement, startOffset: Int, text: String)]
    ) {
        // Collect all AXStaticText elements with their text
        var textElements: [(element: AXUIElement, text: String)] = []
        collectStaticTextElements(from: element, into: &textElements, maxDepth: 10)

        // Find each segment's actual position in the full text
        // AXStaticText segments don't include newlines/bullets between paragraphs
        var searchStart = 0
        for (elem, text) in textElements {
            guard !text.isEmpty else { continue }

            // Search for this text in the full text starting from where we left off
            let searchRange = NSRange(location: searchStart, length: fullText.count - searchStart)
            if let range = Range(searchRange, in: fullText),
               let foundRange = fullText.range(of: text, range: range)
            {
                let offset = fullText.distance(from: fullText.startIndex, to: foundRange.lowerBound)
                segments.append((element: elem, startOffset: offset, text: text))
                // Move search start past this segment
                searchStart = offset + text.count
            } else {
                // Fallback: try searching from beginning (in case of out-of-order segments)
                if let foundRange = fullText.range(of: text) {
                    let offset = fullText.distance(from: fullText.startIndex, to: foundRange.lowerBound)
                    segments.append((element: elem, startOffset: offset, text: text))
                }
            }
        }
    }

    /// Collect all AXStaticText elements with working bounds
    private func collectStaticTextElements(
        from element: AXUIElement,
        into results: inout [(element: AXUIElement, text: String)],
        maxDepth: Int,
        currentDepth: Int = 0
    ) {
        guard currentDepth < maxDepth else { return }

        // Check if this is a static text element
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           role == "AXStaticText"
        {
            // Get its text
            if let text = getText(element), !text.isEmpty {
                results.append((element: element, text: text))
                return // Don't recurse into children of text elements
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return
        }

        for child in children {
            collectStaticTextElements(from: child, into: &results, maxDepth: maxDepth, currentDepth: currentDepth + 1)
        }
    }

    /// Get text value of element
    private func getText(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    /// Get bounds for range using AXBoundsForRange
    private func getBoundsForRange(_ range: NSRange, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        ) == .success,
            let bv = boundsRef,
            CFGetTypeID(bv) == AXValueGetTypeID()
        else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // Validate bounds
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        return rect
    }

    // MARK: - Cache Management

    private func invalidateCacheIfNeeded(element: AXUIElement, text: String) {
        let currentFrame = AccessibilityBridge.getElementFrame(element) ?? .zero
        let currentVisibleRange = getVisibleRange(element)

        ClaudeStrategy.stateQueue.sync {
            let textChanged = text != ClaudeStrategy._cachedText
            let frameChanged = currentFrame != ClaudeStrategy._cachedElementFrame && ClaudeStrategy._cachedElementFrame != .zero

            // Detect scroll if the visible range start changed (more than 10 chars to avoid AX API jitter)
            let previousRange = ClaudeStrategy._cachedVisibleRange
            let scrollDetected = previousRange.length > 0 &&
                abs(currentVisibleRange.location - previousRange.location) > 10

            if textChanged || frameChanged || scrollDetected {
                if scrollDetected {
                    Logger.debug("ClaudeStrategy: Scroll detected (visible range: \(previousRange.location) -> \(currentVisibleRange.location)) - clearing bounds cache", category: Logger.ui)
                }

                let hasPrefix = text.hasPrefix(ClaudeStrategy._cachedText)
                let textAppended = !ClaudeStrategy._cachedText.isEmpty && hasPrefix && !frameChanged && !scrollDetected

                if !textAppended {
                    ClaudeStrategy._boundsCache.removeAll()
                    // Clear segments cache on scroll too - Electron rebuilds the AX tree
                    // when scrolling, so cached AXUIElement references become stale
                    if textChanged || scrollDetected {
                        ClaudeStrategy._cachedSegments.removeAll()
                        ClaudeStrategy._segmentsCacheText = ""
                    }
                }

                ClaudeStrategy._cachedText = text
                ClaudeStrategy._cachedElementFrame = currentFrame
                ClaudeStrategy._cachedVisibleRange = currentVisibleRange
            } else if ClaudeStrategy._cachedElementFrame == .zero {
                ClaudeStrategy._cachedElementFrame = currentFrame
                ClaudeStrategy._cachedVisibleRange = currentVisibleRange
            }
        }
    }

    /// Get the current visible character range for scroll detection
    private func getVisibleRange(_ element: AXUIElement) -> NSRange {
        var visibleRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &visibleRangeRef) == .success,
              let vr = visibleRangeRef,
              CFGetTypeID(vr) == AXValueGetTypeID()
        else {
            return NSRange(location: 0, length: 0)
        }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(vr as! AXValue, .cfRange, &cfRange) else {
            return NSRange(location: 0, length: 0)
        }

        return NSRange(location: cfRange.location, length: cfRange.length)
    }
}
