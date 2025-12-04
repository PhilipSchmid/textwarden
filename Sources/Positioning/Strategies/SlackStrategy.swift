//
//  SlackStrategy.swift
//  TextWarden
//
//  Slack-specific positioning strategy using selection-based marker range positioning.
//  Chromium's standard AXBoundsForRange returns invalid values, so we use the
//  AXSelectedTextMarkerRange + AXBoundsForTextMarkerRange approach instead.
//

import Foundation
import AppKit
import ApplicationServices

/// Slack-specific positioning strategy
///
/// Uses selection-based marker range positioning which requires cursor manipulation.
/// To avoid interfering with typing, we cache bounds and only update when:
/// - Text content changes
/// - Element frame changes (resize, line wrap)
/// - Formatting changes (bold, italic, code, etc.)
class SlackStrategy: GeometryProvider {

    var strategyName: String { "Slack" }
    var tier: StrategyTier { .precise }
    var tierPriority: Int { 5 }

    // MARK: - Cache State

    private static var boundsCache: [NSRange: CGRect] = [:]
    private static var cachedText: String = ""
    private static var cachedElementFrame: CGRect = .zero
    private static var cachedAttributedStringHash: Int = 0

    // MARK: - Typing Detection State

    private static var lastTextChangeTime: Date = .distantPast
    private static var textFirstSeenTime: Date = .distantPast

    /// Minimum time text must be stable before measuring (avoids cursor interference during typing)
    private static let typingPauseThreshold: TimeInterval = 1.5

    // MARK: - Cursor Restoration State

    private static var savedCursorPosition: CFRange?
    private static var savedCursorElement: AXUIElement?
    private static var measurementInProgress: Bool = false

    // MARK: - Stale Data Detection

    private static var lastMeasuredBounds: CGRect?
    private static var consecutiveSameBoundsCount: Int = 0

    // MARK: - Public Interface

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        return bundleID == "com.tinyspeck.slackmacgap"
    }

    /// Callback to hide underlines immediately when typing starts
    static var onTypingStarted: (() -> Void)?

    /// Called when text changes to track typing activity
    static func notifyTextChange() {
        lastTextChangeTime = Date()
        textFirstSeenTime = Date()
        savedCursorPosition = nil
        savedCursorElement = nil
        measurementInProgress = false

        DispatchQueue.main.async {
            onTypingStarted?()
        }
    }

    /// Check if user is currently typing
    static var isCurrentlyTyping: Bool {
        Date().timeIntervalSince(textFirstSeenTime) < typingPauseThreshold
    }

    /// Restore cursor position after measurements complete
    static func restoreCursorPosition() {
        guard measurementInProgress,
              let position = savedCursorPosition,
              let element = savedCursorElement else {
            return
        }

        var pos = position
        if let restoreValue = AXValueCreate(.cfRange, &pos) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, restoreValue)
            usleep(15000)  // 15ms for Chromium to process
        }

        savedCursorPosition = nil
        savedCursorElement = nil
        measurementInProgress = false
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
        let adjustedRange = NSRange(location: startIndex, length: errorRange.length)

        // Check cache invalidation conditions
        invalidateCacheIfNeeded(element: element, text: text)

        // Return cached bounds if available
        if let cachedBounds = SlackStrategy.boundsCache[adjustedRange] {
            let cocoaBounds = convertQuartzToCocoa(cachedBounds)
            return GeometryResult(
                bounds: cocoaBounds,
                confidence: 0.90,
                strategy: strategyName,
                metadata: ["api": "cached", "skip_conversion": true, "skip_resolver_cache": true]
            )
        }

        // Don't measure while user is typing
        guard !SlackStrategy.isCurrentlyTyping else {
            return GeometryResult.unavailable(reason: "Waiting for typing pause")
        }

        // Save cursor once before first measurement
        saveCursorPosition(element: element)

        // Measure bounds using selection-based approach
        guard let bounds = measureBoundsViaSelection(element: element, range: adjustedRange) else {
            return nil
        }

        // Cache and return
        SlackStrategy.boundsCache[adjustedRange] = bounds
        let cocoaBounds = convertQuartzToCocoa(bounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            return nil
        }

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.95,
            strategy: strategyName,
            metadata: ["api": "selection-marker-range", "skip_conversion": true, "skip_resolver_cache": true]
        )
    }

    // MARK: - Cache Management

    private func invalidateCacheIfNeeded(element: AXUIElement, text: String) {
        let currentFrame = getElementFrame(element: element) ?? .zero
        let oldText = SlackStrategy.cachedText

        let textChanged = text != oldText
        let frameChanged = currentFrame != SlackStrategy.cachedElementFrame && SlackStrategy.cachedElementFrame != .zero

        // Only check formatting if text didn't change (pure formatting change)
        // When text changes, the attributed string hash will also change, so we use text prefix check instead
        let formattingChanged: Bool
        if !textChanged {
            let currentAttrHash = getAttributedStringHash(element: element)
            formattingChanged = currentAttrHash != SlackStrategy.cachedAttributedStringHash && SlackStrategy.cachedAttributedStringHash != 0
            if formattingChanged || SlackStrategy.cachedAttributedStringHash == 0 {
                SlackStrategy.cachedAttributedStringHash = currentAttrHash
            }
        } else {
            formattingChanged = false
        }

        if textChanged || frameChanged || formattingChanged {
            // Smart cache preservation: if text was only appended (no changes to existing text),
            // keep the cache for existing ranges since their positions haven't changed.
            // BUT: if formatting changed, we must clear the cache because character widths may have changed.
            let hasPrefix = text.hasPrefix(oldText)
            let textAppended = !oldText.isEmpty && hasPrefix && !frameChanged && !formattingChanged

            if textAppended {
                // Text was appended at the end - preserve existing cache entries
                SlackStrategy.cachedAttributedStringHash = getAttributedStringHash(element: element)
            } else {
                // Text changed in a way that affects existing positions - clear cache
                SlackStrategy.boundsCache.removeAll()
                SlackStrategy.lastMeasuredBounds = nil
                SlackStrategy.consecutiveSameBoundsCount = 0
                SlackStrategy.cachedAttributedStringHash = getAttributedStringHash(element: element)
            }

            SlackStrategy.cachedText = text
            SlackStrategy.cachedElementFrame = currentFrame
        } else {
            // Initialize tracking on first run
            if SlackStrategy.cachedElementFrame == .zero {
                SlackStrategy.cachedElementFrame = currentFrame
            }
            if SlackStrategy.cachedAttributedStringHash == 0 {
                SlackStrategy.cachedAttributedStringHash = getAttributedStringHash(element: element)
            }
        }
    }

    // MARK: - Selection-Based Measurement

    private func saveCursorPosition(element: AXUIElement) {
        guard !SlackStrategy.measurementInProgress else { return }

        var selValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selValue) == .success,
              let sv = selValue else { return }

        var range = CFRange(location: 0, length: 0)
        if AXValueGetValue(sv as! AXValue, .cfRange, &range) {
            SlackStrategy.savedCursorPosition = range
            SlackStrategy.savedCursorElement = element
            SlackStrategy.measurementInProgress = true
        }
    }

    /// Measure bounds by setting selection and reading AXBoundsForTextMarkerRange
    private func measureBoundsViaSelection(element: AXUIElement, range: NSRange) -> CGRect? {
        var targetRange = CFRange(location: range.location, length: range.length)
        guard let targetValue = AXValueCreate(.cfRange, &targetRange) else { return nil }

        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, targetValue) == .success else {
            return nil
        }

        // Wait for Chromium to process selection change
        usleep(20000)  // 20ms

        // Poll for valid bounds with stale data detection
        for attempt in 0..<8 {
            if attempt > 0 {
                usleep(15000)  // 15ms between retries
            }

            guard let bounds = readSelectedTextBounds(element: element) else { continue }

            // Detect stale data (Chromium returning previous selection's bounds)
            if let lastBounds = SlackStrategy.lastMeasuredBounds,
               abs(bounds.origin.x - lastBounds.origin.x) < 1 &&
               abs(bounds.origin.y - lastBounds.origin.y) < 1 &&
               abs(bounds.width - lastBounds.width) < 1 {
                SlackStrategy.consecutiveSameBoundsCount += 1
                if attempt < 6 { continue }
            } else {
                SlackStrategy.consecutiveSameBoundsCount = 0
            }

            SlackStrategy.lastMeasuredBounds = bounds
            return bounds
        }

        return nil
    }

    private func readSelectedTextBounds(element: AXUIElement) -> CGRect? {
        var markerRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeRef) == .success,
              let markerRange = markerRangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &boundsRef
        ) == .success, let bv = boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &rect),
              rect.width > 0 && rect.height > 0 && rect.height < 100 else { return nil }

        return rect
    }

    // MARK: - Element Inspection

    private func getElementFrame(element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var pos = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: pos, size: size)
    }

    /// Get hash of attributed string to detect formatting changes (bold, italic, code, etc.)
    private func getAttributedStringHash(element: AXUIElement) -> Int {
        var textLengthValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &textLengthValue) == .success,
              let length = textLengthValue as? Int, length > 0 else {
            return 0
        }

        var cfRange = CFRange(location: 0, length: min(length, 1000))
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return 0 }

        var attrStringValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForRange" as CFString,
            rangeValue,
            &attrStringValue
        ) == .success, let attrString = attrStringValue as? NSAttributedString else {
            return 0
        }

        var hasher = Hasher()
        hasher.combine(attrString.string)

        attrString.enumerateAttributes(in: NSRange(location: 0, length: attrString.length), options: []) { attrs, range, _ in
            hasher.combine(range.location)
            hasher.combine(range.length)
            hasher.combine(attrs.count)
            for key in attrs.keys {
                hasher.combine(key.rawValue)
            }
        }

        return hasher.finalize()
    }

    // MARK: - Coordinate Conversion

    private func convertQuartzToCocoa(_ quartzRect: CGRect) -> CGRect {
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        guard let screenHeight = primaryScreen?.frame.height ?? NSScreen.main?.frame.height else {
            return quartzRect
        }

        var cocoaRect = quartzRect
        cocoaRect.origin.y = screenHeight - quartzRect.origin.y - quartzRect.height
        return cocoaRect
    }
}
