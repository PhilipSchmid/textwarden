//
//  ClaudeContentParser.swift
//  TextWarden
//
//  Claude-specific content parser for the Anthropic desktop app.
//  Claude is an Electron app that shares Chromium's newline handling with Slack.
//

import AppKit
import Foundation

/// Claude-specific content parser
/// Uses ChromiumStrategy positioning with newline offset adjustments (like Slack)
class ClaudeContentParser: ContentParser {
    let bundleIdentifier = "com.anthropic.claudefordesktop"
    let parserName = "Claude"

    /// Cached configuration from AppRegistry
    private var config: AppConfiguration {
        AppRegistry.shared.configuration(for: bundleIdentifier)
    }

    /// Visual underlines enabled from AppConfiguration
    var disablesVisualUnderlines: Bool {
        !config.features.visualUnderlinesEnabled
    }

    /// Claude needs UTF-16 conversion for correct emoji handling in Chromium selection APIs
    var requiresUTF16Conversion: Bool {
        true
    }

    /// Calculate selection offset for Claude
    /// Claude's Electron/Chromium selection API treats certain characters differently than AXValue:
    /// - Newlines: Each \n in AXValue is zero-width in selection terms
    /// - Backticks: Code block markers are in AX text but may not render visually
    func selectionOffset(at position: Int, in text: String) -> Int {
        guard position > 0 else { return 0 }

        let endIndex = min(position, text.count)
        guard let endStringIndex = text.index(text.startIndex, offsetBy: endIndex, limitedBy: text.endIndex) else {
            return 0
        }

        let prefix = String(text[..<endStringIndex])

        // Count newlines - Chromium selection API treats these as zero-width
        return prefix.count(where: { $0 == "\n" })
    }

    func detectUIContext(element _: AXUIElement) -> String? {
        "prompt-input" // Claude has a single main input context
    }

    func estimatedFontSize(context _: String?) -> CGFloat {
        config.fontConfig.defaultSize
    }

    func spacingMultiplier(context _: String?) -> CGFloat {
        config.fontConfig.spacingMultiplier
    }

    func horizontalPadding(context _: String?) -> CGFloat {
        config.horizontalPadding
    }

    /// Use the multi-strategy PositionResolver for positioning
    /// ChromiumStrategy works well for Electron apps like Claude
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String
    ) -> GeometryResult {
        PositionResolver.shared.resolvePosition(
            for: errorRange,
            in: element,
            text: text,
            parser: self,
            bundleID: bundleIdentifier
        )
    }

    /// Bounds adjustment using ChromiumStrategy approach
    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        let context = detectUIContext(element: element)
        let fontSize = estimatedFontSize(context: context)

        // Try cursor-anchored positioning first
        if let cursorResult = getCursorAnchoredPosition(
            element: element,
            errorRange: errorRange,
            textBeforeError: textBeforeError,
            errorText: errorText,
            fullText: fullText,
            context: context,
            fontSize: fontSize
        ) {
            return cursorResult
        }

        // Try direct AX bounds for the error range
        if let bounds = AccessibilityBridge.getBoundsForRange(errorRange, in: element),
           bounds.origin.x > 0, bounds.origin.y > 0
        {
            return AdjustedBounds(
                position: NSPoint(x: bounds.origin.x, y: bounds.origin.y),
                errorWidth: bounds.width,
                confidence: 0.9,
                uiContext: context,
                debugInfo: "Claude AX bounds (direct)"
            )
        }

        // Fall back to text measurement
        return getTextMeasurementFallback(
            element: element,
            errorRange: errorRange,
            textBeforeError: textBeforeError,
            errorText: errorText,
            context: context,
            fontSize: fontSize
        )
    }

    // MARK: - Cursor-Anchored Positioning

    private func getCursorAnchoredPosition(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError _: String,
        errorText: String,
        fullText: String,
        context: String?,
        fontSize: CGFloat
    ) -> AdjustedBounds? {
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
            let rangeRef = selectedRangeValue,
            let selectedRange = safeAXValueGetRange(rangeRef)
        else {
            return nil
        }

        let cursorPosition = selectedRange.location

        // Try to get bounds at cursor position
        var cursorBounds: CGRect?

        // Method 1: AXInsertionPointFrame
        var insertionPointValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointFrame" as CFString, &insertionPointValue) == .success,
           let axValue = insertionPointValue,
           let frame = safeAXValueGetRect(axValue)
        {
            if frame.width >= 0, frame.height > GeometryConstants.minimumBoundsSize, frame.height < GeometryConstants.conservativeMaxLineHeight {
                cursorBounds = frame
            }
        }

        // Method 2: Bounds for character at cursor
        if cursorBounds == nil {
            if let bounds = AccessibilityBridge.getBoundsForRange(NSRange(location: cursorPosition, length: 1), in: element),
               bounds.origin.x > 0, bounds.origin.y > 0
            {
                cursorBounds = bounds
            }
        }

        guard let cursor = cursorBounds else {
            return nil
        }

        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let multiplier = spacingMultiplier(context: context)

        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width * multiplier, 20.0)

        let charsBetween = errorRange.location - cursorPosition
        var xPosition: CGFloat

        if charsBetween >= 0 {
            let textBetween = String(fullText.dropFirst(cursorPosition).prefix(charsBetween))
            let offsetWidth = (textBetween as NSString).size(withAttributes: attributes).width * multiplier
            xPosition = cursor.origin.x + offsetWidth
        } else {
            let textBetween = String(fullText.dropFirst(errorRange.location).prefix(-charsBetween))
            let offsetWidth = (textBetween as NSString).size(withAttributes: attributes).width * multiplier
            xPosition = cursor.origin.x - offsetWidth
        }

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: cursor.origin.y),
            errorWidth: errorWidth,
            confidence: 0.80,
            uiContext: context,
            debugInfo: "Claude cursor-anchored"
        )
    }

    // MARK: - Text Measurement Fallback

    private func getTextMeasurementFallback(
        element: AXUIElement,
        errorRange _: NSRange,
        textBeforeError: String,
        errorText: String,
        context: String?,
        fontSize: CGFloat
    ) -> AdjustedBounds? {
        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
            return nil
        }

        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let multiplier = spacingMultiplier(context: context)
        let padding = horizontalPadding(context: context)

        let lineHeight: CGFloat = fontSize * 1.5
        let availableWidth = elementFrame.width - (padding * 2) - 20

        let textBeforeWidth = (textBeforeError as NSString).size(withAttributes: attributes).width * multiplier
        let errorLine = Int(textBeforeWidth / availableWidth)

        let xOffsetOnLine = textBeforeWidth.truncatingRemainder(dividingBy: availableWidth)
        let xPosition = elementFrame.origin.x + padding + xOffsetOnLine

        let baseErrorWidth = (errorText as NSString).size(withAttributes: attributes).width
        let adjustedErrorWidth = max(baseErrorWidth * multiplier, 20.0)

        let topPadding: CGFloat = 10.0
        let yPosition = elementFrame.origin.y + topPadding + (CGFloat(errorLine) * lineHeight) + (lineHeight * 0.85)

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: yPosition),
            errorWidth: adjustedErrorWidth,
            confidence: 0.60,
            uiContext: context,
            debugInfo: "Claude text measurement (line: \(errorLine))"
        )
    }
}
