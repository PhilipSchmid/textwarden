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

    // MARK: - Thread Safety

    /// Serial queue to protect all static mutable state from concurrent access
    private static let stateQueue = DispatchQueue(label: "com.textwarden.chromium-strategy", qos: .userInitiated)

    // MARK: - Cache State (protected by stateQueue)

    private static var _boundsCache: [NSRange: CGRect] = [:]
    private static var _cachedText: String = ""
    private static var _cachedElementFrame: CGRect = .zero
    private static var _cachedAttributedStringHash: Int = 0

    // MARK: - Typing Detection State (protected by stateQueue)

    /// Tracks when text last changed - used to detect typing pauses before measuring
    private static var _lastTextChangeTime: Date = .distantPast

    /// Minimum time text must be stable before measuring (avoids cursor interference during typing)
    private static let typingPauseThreshold: TimeInterval = TimingConstants.typingPauseThreshold

    // MARK: - Cursor Restoration State (protected by stateQueue)

    private static var _savedCursorPosition: CFRange?
    private static var _savedCursorElement: AXUIElement?
    private static var _measurementInProgress: Bool = false

    // MARK: - Stale Data Detection (protected by stateQueue)

    private static var _lastMeasuredBounds: CGRect?
    private static var _consecutiveSameBoundsCount: Int = 0

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
        stateQueue.sync {
            _lastTextChangeTime = Date()
            _savedCursorPosition = nil
            _savedCursorElement = nil
            _measurementInProgress = false
        }

        DispatchQueue.main.async {
            onTypingStarted?()
        }
    }

    /// Check if user is currently typing (text changed recently)
    static var isCurrentlyTyping: Bool {
        stateQueue.sync {
            Date().timeIntervalSince(_lastTextChangeTime) < typingPauseThreshold
        }
    }

    /// Restore cursor position after measurements complete
    static func restoreCursorPosition() {
        let (shouldRestore, position, element) = stateQueue.sync { () -> (Bool, CFRange?, AXUIElement?) in
            guard _measurementInProgress,
                  let pos = _savedCursorPosition,
                  let elem = _savedCursorElement else {
                return (false, nil, nil)
            }
            return (true, pos, elem)
        }

        guard shouldRestore, var pos = position, let element = element else { return }

        if let restoreValue = AXValueCreate(.cfRange, &pos) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, restoreValue)
            usleep(GeometryConstants.chromiumShortDelay)
        }

        stateQueue.sync {
            _savedCursorPosition = nil
            _savedCursorElement = nil
            _measurementInProgress = false
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

        // Note: Emoji detection is handled at PositionResolver level before strategies are called.
        // Apps with hasEmbeddedImagePositioningIssues=true skip all positioning when emojis are detected.

        // Apply app-specific selection offset (e.g., Slack/Claude need newline adjustment)
        let selectionOffset = parser.selectionOffset(at: graphemeRange.location, in: text)

        // Calculate selection range based on app requirements
        let selectionRange: NSRange
        if parser.requiresUTF16Conversion {
            // Convert grapheme cluster indices to UTF-16 code unit indices
            // This is needed for apps like Claude where emojis cause position drift
            let utf16Range = TextIndexConverter.graphemeToUTF16Range(graphemeRange, in: text)
            let adjustedLocation = max(0, utf16Range.location - selectionOffset)
            selectionRange = NSRange(location: adjustedLocation, length: utf16Range.length)

            if utf16Range.location != graphemeRange.location || selectionOffset > 0 {
                Logger.debug("ChromiumStrategy: UTF-16 + offset [\(graphemeRange.location)] -> UTF-16 [\(utf16Range.location)] - \(selectionOffset) -> [\(selectionRange.location)]", category: Logger.ui)
            }
        } else {
            // Standard behavior: just apply selection offset to grapheme range
            let adjustedLocation = max(0, graphemeRange.location - selectionOffset)
            selectionRange = NSRange(location: adjustedLocation, length: graphemeRange.length)

            if selectionOffset > 0 {
                Logger.debug("ChromiumStrategy: Selection offset adjustment [\(graphemeRange.location)] - \(selectionOffset) -> [\(selectionRange.location)]", category: Logger.ui)
            }
        }

        // Check cache invalidation conditions
        invalidateCacheIfNeeded(element: element, text: text)

        // Return cached bounds if available - cache key uses grapheme range since error positions
        // come in grapheme terms, but bounds were measured using UTF-16 selection
        if let cachedBounds = ChromiumStrategy.stateQueue.sync(execute: { ChromiumStrategy._boundsCache[graphemeRange] }) {
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

        // Log the selection range we're about to use
        Logger.debug("ChromiumStrategy: Setting selection for grapheme range \(graphemeRange) -> selection range \(selectionRange)", category: Logger.analysis)

        // Measure bounds using selection-based approach (with emoji offset correction)
        guard var bounds = measureBoundsViaSelection(element: element, range: selectionRange) else {
            Logger.debug("ChromiumStrategy: measureBoundsViaSelection returned nil for range \(selectionRange)", category: Logger.analysis)
            return nil
        }

        // Validate bounds aren't unreasonably large (catches Slack's bogus bounds for special formatting)
        // A typical character is ~8-12px wide, so max ~15px per char is generous
        let maxReasonableWidth = CGFloat(errorRange.length) * 15.0 + 50.0
        let maxReasonableHeight: CGFloat = 30.0  // Single line text should be ~18-22px

        if bounds.width > maxReasonableWidth && bounds.width > 200 {
            Logger.debug("ChromiumStrategy: Rejecting bounds - width \(bounds.width)px too large for \(errorRange.length) chars (max: \(maxReasonableWidth)px)", category: Logger.analysis)
            return nil
        }

        if bounds.height > maxReasonableHeight {
            Logger.debug("ChromiumStrategy: Rejecting bounds - height \(bounds.height)px too large (max: \(maxReasonableHeight)px)", category: Logger.analysis)
            return nil
        }

        // Validate bounds Y is within element frame (catches emoji-induced position drift)
        // Emojis in Slack cause Chromium's text markers to be offset from AXValue positions.
        // When bounds Y is outside the element, it means the position drift is severe.
        if let elementFrame = AccessibilityBridge.getElementFrame(element) {
            let tolerance: CGFloat = 50.0  // Allow some tolerance for rounding
            let minY = elementFrame.origin.y - tolerance
            let maxY = elementFrame.origin.y + elementFrame.height + tolerance

            if bounds.origin.y < minY || bounds.origin.y > maxY {
                Logger.debug("ChromiumStrategy: Rejecting bounds - Y \(bounds.origin.y) outside element bounds [\(minY), \(maxY)] (emoji drift?)", category: Logger.analysis)
                return nil
            }
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
            Logger.debug("ChromiumStrategy: Estimated width \(estimatedWidth) for \(errorText.count) chars", category: Logger.analysis)
        }

        // Cache and return (thread-safe access) - cache key uses grapheme range
        ChromiumStrategy.stateQueue.sync { ChromiumStrategy._boundsCache[graphemeRange] = bounds }
        let cocoaBounds = convertQuartzToCocoa(bounds)

        // Log coordinate transformation for debugging multi-line issues
        Logger.debug("ChromiumStrategy: Quartz bounds \(bounds) -> Cocoa bounds \(cocoaBounds)", category: Logger.ui)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("ChromiumStrategy: Bounds failed validation", category: Logger.ui)
            return nil
        }

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: bounds.width > 0 ? GeometryConstants.highConfidence : GeometryConstants.goodConfidence,
            strategy: strategyName,
            metadata: ["api": "selection-marker-range", "skip_conversion": true, "skip_resolver_cache": true]
        )
    }

    // MARK: - Cache Management

    private func invalidateCacheIfNeeded(element: AXUIElement, text: String) {
        let currentFrame = AccessibilityBridge.getElementFrame(element) ?? .zero
        let currentAttrHash = getAttributedStringHash(element: element)

        ChromiumStrategy.stateQueue.sync {
            let oldText = ChromiumStrategy._cachedText

            let textChanged = text != oldText
            let frameChanged = currentFrame != ChromiumStrategy._cachedElementFrame && ChromiumStrategy._cachedElementFrame != .zero

            // Only check formatting if text didn't change (pure formatting change)
            // When text changes, the attributed string hash will also change, so we use text prefix check instead
            let formattingChanged: Bool
            if !textChanged {
                formattingChanged = currentAttrHash != ChromiumStrategy._cachedAttributedStringHash && ChromiumStrategy._cachedAttributedStringHash != 0
                if formattingChanged || ChromiumStrategy._cachedAttributedStringHash == 0 {
                    ChromiumStrategy._cachedAttributedStringHash = currentAttrHash
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
                    ChromiumStrategy._cachedAttributedStringHash = currentAttrHash
                } else {
                    // Text changed in a way that affects existing positions - clear cache
                    ChromiumStrategy._boundsCache.removeAll()
                    ChromiumStrategy._lastMeasuredBounds = nil
                    ChromiumStrategy._consecutiveSameBoundsCount = 0
                    ChromiumStrategy._cachedAttributedStringHash = currentAttrHash
                }

                ChromiumStrategy._cachedText = text
                ChromiumStrategy._cachedElementFrame = currentFrame
            } else {
                // Initialize tracking on first run
                if ChromiumStrategy._cachedElementFrame == .zero {
                    ChromiumStrategy._cachedElementFrame = currentFrame
                }
                if ChromiumStrategy._cachedAttributedStringHash == 0 {
                    ChromiumStrategy._cachedAttributedStringHash = currentAttrHash
                }
            }
        }
    }

    // MARK: - Selection-Based Measurement

    private func saveCursorPosition(element: AXUIElement) {
        // Check if measurement already in progress (thread-safe)
        let alreadyInProgress = ChromiumStrategy.stateQueue.sync { ChromiumStrategy._measurementInProgress }
        guard !alreadyInProgress else { return }

        var selValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selValue) == .success,
              let sv = selValue,
              let range = safeAXValueGetRange(sv) else { return }

        ChromiumStrategy.stateQueue.sync {
            ChromiumStrategy._savedCursorPosition = CFRange(location: range.location, length: range.length)
            ChromiumStrategy._savedCursorElement = element
            ChromiumStrategy._measurementInProgress = true
        }
    }

    /// Measure bounds by setting selection and reading AXBoundsForTextMarkerRange
    private func measureBoundsViaSelection(element: AXUIElement, range: NSRange) -> CGRect? {
        // Get element frame to detect "whole line" stale bounds
        let elementFrame = AccessibilityBridge.getElementFrame(element)

        var targetRange = CFRange(location: range.location, length: range.length)
        guard let targetValue = AXValueCreate(.cfRange, &targetRange) else {
            Logger.debug("ChromiumStrategy: Failed to create AXValue for range", category: Logger.analysis)
            return nil
        }

        // First, try to clear selection by setting an empty range at position 0
        // This helps reset Slack's accessibility state before setting our target selection
        var emptyRange = CFRange(location: 0, length: 0)
        if let emptyValue = AXValueCreate(.cfRange, &emptyRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, emptyValue)
            usleep(GeometryConstants.chromiumShortDelay)
        }

        let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, targetValue)
        guard setResult == .success else {
            Logger.debug("ChromiumStrategy: Failed to set selection - error \(setResult.rawValue)", category: Logger.analysis)
            return nil
        }

        // Wait for Chromium to process selection change - use longer delay for better reliability
        usleep(GeometryConstants.chromiumMediumDelay * 3)

        // Poll for valid bounds with stale data detection
        for attempt in 0..<10 {
            if attempt > 0 {
                usleep(GeometryConstants.chromiumShortDelay)
            }

            guard let bounds = readSelectedTextBounds(element: element) else {
                if attempt == 9 {
                    Logger.debug("ChromiumStrategy: readSelectedTextBounds returned nil after 10 attempts", category: Logger.analysis)
                }
                continue
            }

            // Detect stale/bogus bounds:
            // 1. Bounds matching previous measurement exactly (stale)
            // 2. Bounds width close to element width (likely whole-line bounds)
            let isStaleData = ChromiumStrategy.stateQueue.sync { () -> Bool in
                if let lastBounds = ChromiumStrategy._lastMeasuredBounds,
                   abs(bounds.origin.x - lastBounds.origin.x) < 1 &&
                   abs(bounds.origin.y - lastBounds.origin.y) < 1 &&
                   abs(bounds.width - lastBounds.width) < 1 {
                    ChromiumStrategy._consecutiveSameBoundsCount += 1
                    return true
                } else {
                    ChromiumStrategy._consecutiveSameBoundsCount = 0
                    return false
                }
            }

            // Also check for "whole line" bounds - width close to element width
            let isWholeLine: Bool
            if let frame = elementFrame {
                // If bounds width is > 80% of element width, it's likely bogus whole-line bounds
                isWholeLine = bounds.width > frame.width * 0.8
            } else {
                isWholeLine = false
            }

            if (isStaleData || isWholeLine) && attempt < 8 {
                if isWholeLine {
                    Logger.debug("ChromiumStrategy: Skipping whole-line bounds \(bounds.width)px on attempt \(attempt)", category: Logger.analysis)
                }
                continue
            }

            Logger.debug("ChromiumStrategy: Got bounds \(bounds) on attempt \(attempt)", category: Logger.analysis)
            ChromiumStrategy.stateQueue.sync { ChromiumStrategy._lastMeasuredBounds = bounds }
            return bounds
        }

        Logger.debug("ChromiumStrategy: All 10 attempts failed to get valid bounds", category: Logger.analysis)
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
        if rect.width > 0 && rect.height > 0 && rect.height < GeometryConstants.conservativeMaxLineHeight {
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
