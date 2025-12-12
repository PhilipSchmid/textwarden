//
//  ChromiumStrategy.swift
//  TextWarden
//
//  Positioning strategy for Chromium-based apps (Slack, MS Teams, etc.)
//  Chromium's standard AXBoundsForRange returns invalid values, so we use the
//  AXSelectedTextMarkerRange + AXBoundsForTextMarkerRange approach instead.
//

import Foundation
import AppKit
import ApplicationServices

/// Chromium-based app positioning strategy
///
/// Works with Slack (Electron), MS Teams (Edge WebView2), and other Chromium apps.
/// Uses selection-based marker range positioning which requires cursor manipulation.
/// To avoid interfering with typing, we cache bounds and only update when:
/// - Text content changes
/// - Element frame changes (resize, line wrap)
/// - Formatting changes (bold, italic, code, etc.)
class ChromiumStrategy: GeometryProvider {

    var strategyName: String { "Chromium" }
    var strategyType: StrategyType { .chromium }
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
    private static let typingPauseThreshold: TimeInterval = TimingConstants.typingPauseThreshold

    // MARK: - Cursor Restoration State

    private static var savedCursorPosition: CFRange?
    private static var savedCursorElement: AXUIElement?
    private static var measurementInProgress: Bool = false

    // MARK: - Stale Data Detection

    private static var lastMeasuredBounds: CGRect?
    private static var consecutiveSameBoundsCount: Int = 0

    /// Bundle IDs of Chromium-based apps that use this strategy
    private static let chromiumBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",  // Slack
        "com.microsoft.teams2"         // Microsoft Teams
    ]

    // MARK: - Public Interface

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Check if this is a Chromium-based app that should use this strategy
        // Apps must be in preferredStrategies with .chromium to use this
        let config = AppRegistry.shared.configuration(for: bundleID)
        return config.preferredStrategies.contains(.chromium)
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
        if let cachedBounds = ChromiumStrategy.boundsCache[adjustedRange] {
            let cocoaBounds = convertQuartzToCocoa(cachedBounds)
            return GeometryResult(
                bounds: cocoaBounds,
                confidence: 0.90,
                strategy: strategyName,
                metadata: ["api": "cached", "skip_conversion": true, "skip_resolver_cache": true]
            )
        }

        // Don't measure while user is typing
        guard !ChromiumStrategy.isCurrentlyTyping else {
            Logger.debug("ChromiumStrategy: Skipping - user is typing", category: Logger.analysis)
            return GeometryResult.unavailable(reason: "Waiting for typing pause")
        }

        // Save cursor once before first measurement
        saveCursorPosition(element: element)

        // Measure bounds using selection-based approach
        guard var bounds = measureBoundsViaSelection(element: element, range: adjustedRange) else {
            Logger.debug("ChromiumStrategy: measureBoundsViaSelection returned nil for range \(adjustedRange)", category: Logger.analysis)
            return nil
        }

        // Handle Teams case: position is valid but width is -1 (needs estimation)
        if bounds.width < 0 {
            // Estimate width based on error text length
            let errorText: String
            if let startIdx = text.index(text.startIndex, offsetBy: errorRange.location, limitedBy: text.endIndex),
               let endIdx = text.index(startIdx, offsetBy: errorRange.length, limitedBy: text.endIndex) {
                errorText = String(text[startIdx..<endIdx])
            } else {
                errorText = ""
            }

            // Use system font for estimation (reasonable for most apps)
            let font = NSFont.systemFont(ofSize: 15)
            let estimatedWidth = (errorText as NSString).size(withAttributes: [.font: font]).width
            bounds = CGRect(x: bounds.origin.x, y: bounds.origin.y, width: max(estimatedWidth, 20), height: bounds.height)
            Logger.debug("ChromiumStrategy: Estimated width \(estimatedWidth) for '\(errorText)'", category: Logger.analysis)
        }

        // Cache and return
        ChromiumStrategy.boundsCache[adjustedRange] = bounds
        let cocoaBounds = convertQuartzToCocoa(bounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            return nil
        }

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: bounds.width > 0 ? 0.95 : 0.85,  // Slightly lower confidence for estimated width
            strategy: strategyName,
            metadata: ["api": "selection-marker-range", "skip_conversion": true, "skip_resolver_cache": true]
        )
    }

    // MARK: - Cache Management

    private func invalidateCacheIfNeeded(element: AXUIElement, text: String) {
        let currentFrame = AccessibilityBridge.getElementFrame(element) ?? .zero
        let oldText = ChromiumStrategy.cachedText

        let textChanged = text != oldText
        let frameChanged = currentFrame != ChromiumStrategy.cachedElementFrame && ChromiumStrategy.cachedElementFrame != .zero

        // Only check formatting if text didn't change (pure formatting change)
        // When text changes, the attributed string hash will also change, so we use text prefix check instead
        let formattingChanged: Bool
        if !textChanged {
            let currentAttrHash = getAttributedStringHash(element: element)
            formattingChanged = currentAttrHash != ChromiumStrategy.cachedAttributedStringHash && ChromiumStrategy.cachedAttributedStringHash != 0
            if formattingChanged || ChromiumStrategy.cachedAttributedStringHash == 0 {
                ChromiumStrategy.cachedAttributedStringHash = currentAttrHash
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
                ChromiumStrategy.cachedAttributedStringHash = getAttributedStringHash(element: element)
            } else {
                // Text changed in a way that affects existing positions - clear cache
                ChromiumStrategy.boundsCache.removeAll()
                ChromiumStrategy.lastMeasuredBounds = nil
                ChromiumStrategy.consecutiveSameBoundsCount = 0
                ChromiumStrategy.cachedAttributedStringHash = getAttributedStringHash(element: element)
            }

            ChromiumStrategy.cachedText = text
            ChromiumStrategy.cachedElementFrame = currentFrame
        } else {
            // Initialize tracking on first run
            if ChromiumStrategy.cachedElementFrame == .zero {
                ChromiumStrategy.cachedElementFrame = currentFrame
            }
            if ChromiumStrategy.cachedAttributedStringHash == 0 {
                ChromiumStrategy.cachedAttributedStringHash = getAttributedStringHash(element: element)
            }
        }
    }

    // MARK: - Selection-Based Measurement

    private func saveCursorPosition(element: AXUIElement) {
        guard !ChromiumStrategy.measurementInProgress else { return }

        var selValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selValue) == .success,
              let sv = selValue,
              let range = safeAXValueGetRange(sv) else { return }

        ChromiumStrategy.savedCursorPosition = CFRange(location: range.location, length: range.length)
        ChromiumStrategy.savedCursorElement = element
        ChromiumStrategy.measurementInProgress = true
    }

    /// Measure bounds by setting selection and reading AXBoundsForTextMarkerRange
    private func measureBoundsViaSelection(element: AXUIElement, range: NSRange) -> CGRect? {
        var targetRange = CFRange(location: range.location, length: range.length)
        guard let targetValue = AXValueCreate(.cfRange, &targetRange) else {
            Logger.debug("ChromiumStrategy: Failed to create AXValue for range", category: Logger.analysis)
            return nil
        }

        let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, targetValue)
        guard setResult == .success else {
            Logger.debug("ChromiumStrategy: Failed to set selection - error \(setResult.rawValue)", category: Logger.analysis)
            return nil
        }

        // Wait for Chromium to process selection change
        usleep(20000)  // 20ms

        // Poll for valid bounds with stale data detection
        for attempt in 0..<8 {
            if attempt > 0 {
                usleep(15000)  // 15ms between retries
            }

            guard let bounds = readSelectedTextBounds(element: element) else {
                if attempt == 7 {
                    Logger.debug("ChromiumStrategy: readSelectedTextBounds returned nil after 8 attempts", category: Logger.analysis)
                }
                continue
            }

            // Detect stale data (Chromium returning previous selection's bounds)
            if let lastBounds = ChromiumStrategy.lastMeasuredBounds,
               abs(bounds.origin.x - lastBounds.origin.x) < 1 &&
               abs(bounds.origin.y - lastBounds.origin.y) < 1 &&
               abs(bounds.width - lastBounds.width) < 1 {
                ChromiumStrategy.consecutiveSameBoundsCount += 1
                if attempt < 6 { continue }
            } else {
                ChromiumStrategy.consecutiveSameBoundsCount = 0
            }

            Logger.debug("ChromiumStrategy: Got bounds \(bounds) on attempt \(attempt)", category: Logger.analysis)
            ChromiumStrategy.lastMeasuredBounds = bounds
            return bounds
        }

        Logger.debug("ChromiumStrategy: All 8 attempts failed to get valid bounds", category: Logger.analysis)
        return nil
    }

    private func readSelectedTextBounds(element: AXUIElement) -> CGRect? {
        var markerRangeRef: CFTypeRef?
        let markerResult = AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeRef)
        guard markerResult == .success, let markerRange = markerRangeRef else {
            // This is expected to fail sometimes during polling
            return nil
        }

        var boundsRef: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &boundsRef
        )
        guard boundsResult == .success,
              let bv = boundsRef,
              let rect = safeAXValueGetRect(bv) else {
            return nil
        }

        // Validate bounds
        // For Teams (WebView2), we may get valid position but zero dimensions
        // In that case, we'll use the position and estimate dimensions
        if rect.width > 0 && rect.height > 0 && rect.height < 100 {
            return rect
        }

        // Check if we have a valid position even with zero/invalid dimensions
        // This happens with MS Teams - position is correct but dimensions are 0
        if rect.origin.x > 0 && rect.origin.y > 0 && (rect.width == 0 || rect.height == 0) {
            Logger.debug("ChromiumStrategy: Got position with zero dimensions \(rect) - will estimate size", category: Logger.analysis)
            // Return with a marker height, width will be calculated by caller
            return CGRect(x: rect.origin.x, y: rect.origin.y, width: -1, height: 18)  // -1 width = needs estimation
        }

        Logger.debug("ChromiumStrategy: Rejected bounds \(rect) - invalid", category: Logger.analysis)
        return nil
    }

    // MARK: - Element Inspection

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
