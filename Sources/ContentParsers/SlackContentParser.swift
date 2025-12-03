//
//  SlackContentParser.swift
//  TextWarden
//
//  Slack-specific content parser using multi-strategy positioning
//  Leverages TextMarkerStrategy for Chromium/Electron apps
//

import Foundation
import AppKit

/// Slack-specific content parser
/// Uses the multi-strategy PositionResolver for reliable text positioning in Electron apps
class SlackContentParser: ContentParser {
    let bundleIdentifier = "com.tinyspeck.slackmacgap"
    let parserName = "Slack"

    /// Diagnostic result from probing Slack's AX capabilities
    private static var diagnosticResult: NotionDiagnosticResult?
    private static var hasRunDiagnostic = false

    /// UI contexts within Slack with different rendering characteristics
    private enum SlackContext: String {
        case messageInput = "message-input"
        case searchBar = "search-bar"
        case threadReply = "thread-reply"
        case editMessage = "edit-message"
        case unknown = "unknown"
    }

    func detectUIContext(element: AXUIElement) -> String? {
        var descValue: CFTypeRef?
        var identifierValue: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)

        let description = descValue as? String
        let identifier = identifierValue as? String

        if let desc = description?.lowercased() {
            if desc.contains("search") {
                return SlackContext.searchBar.rawValue
            } else if desc.contains("thread") || desc.contains("reply") {
                return SlackContext.threadReply.rawValue
            } else if desc.contains("edit") {
                return SlackContext.editMessage.rawValue
            } else if desc.contains("message") || desc.contains("compose") {
                return SlackContext.messageInput.rawValue
            }
        }

        if let id = identifier?.lowercased() {
            if id.contains("search") {
                return SlackContext.searchBar.rawValue
            } else if id.contains("thread") {
                return SlackContext.threadReply.rawValue
            } else if id.contains("composer") || id.contains("message") {
                return SlackContext.messageInput.rawValue
            }
        }

        return SlackContext.messageInput.rawValue
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Slack uses consistent 15pt font across all UI contexts
        return 15.0
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // Slack's Chromium renderer displays text ~6% narrower than NSFont measures
        guard let ctx = context else {
            return 0.94
        }

        let slackContext = SlackContext(rawValue: ctx) ?? .unknown

        switch slackContext {
        case .messageInput, .threadReply, .editMessage:
            return 0.94
        case .searchBar:
            return 0.96
        case .unknown:
            return 0.94
        }
    }

    func horizontalPadding(context: String?) -> CGFloat {
        guard let ctx = context else {
            return 12.0
        }

        let slackContext = SlackContext(rawValue: ctx) ?? .unknown

        switch slackContext {
        case .searchBar:
            return 16.0
        default:
            return 12.0
        }
    }

    /// Use the multi-strategy PositionResolver for positioning
    /// This leverages TextMarkerStrategy which works well for Chromium/Electron apps
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String
    ) -> GeometryResult {
        // Run diagnostic ONCE to discover what AX APIs work for Slack
        if !Self.hasRunDiagnostic {
            Self.hasRunDiagnostic = true
            Self.diagnosticResult = AccessibilityBridge.runNotionDiagnostic(element)

            if let result = Self.diagnosticResult {
                Logger.info("SLACK DIAGNOSTIC SUMMARY:")
                Logger.info("  Best method: \(result.bestMethodDescription)")
                Logger.info("  Has working method: \(result.hasWorkingMethod)")
                Logger.info("  Supported param attrs: \(result.supportedParamAttributes.joined(separator: ", "))")
            }
        }

        // Delegate to the PositionResolver which tries strategies in order:
        // 1. TextMarkerStrategy (opaque markers - works for Chromium)
        // 2. RangeBoundsStrategy (CFRange bounds)
        // 3. ElementTreeStrategy (child element traversal)
        // 4. LineIndexStrategy, OriginStrategy, AnchorSearchStrategy
        // 5. FontMetricsStrategy (app-specific font estimation)
        // 6. SelectionBoundsStrategy, NavigationStrategy (last resort)
        return PositionResolver.shared.resolvePosition(
            for: errorRange,
            in: element,
            text: text,
            parser: self,
            bundleID: bundleIdentifier
        )
    }

    /// Bounds adjustment - delegates to PositionResolver for consistent multi-strategy approach
    /// This is called by ErrorOverlayWindow.estimateErrorBounds() for legacy compatibility
    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        let context = detectUIContext(element: element)
        let fontSize = estimatedFontSize(context: context)

        // Try cursor-anchored positioning first (like Notion)
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
        if let axBounds = getValidAXBounds(element: element, range: errorRange) {
            return AdjustedBounds(
                position: NSPoint(x: axBounds.origin.x, y: axBounds.origin.y),
                errorWidth: axBounds.width,
                confidence: 0.9,
                uiContext: context,
                debugInfo: "Slack AX bounds (direct)"
            )
        }

        // Fall back to text measurement with graceful degradation
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

    /// Get cursor position and use it as anchor for more reliable positioning
    private func getCursorAnchoredPosition(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String,
        context: String?,
        fontSize: CGFloat
    ) -> AdjustedBounds? {
        // Get cursor position
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success else {
            return nil
        }

        var selectedRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &selectedRange) else {
            return nil
        }

        let cursorPosition = selectedRange.location

        // Try to get bounds at cursor position
        var cursorBounds: CGRect?

        // Method 1: AXInsertionPointFrame
        var insertionPointValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointFrame" as CFString, &insertionPointValue) == .success,
           let axValue = insertionPointValue {
            var frame = CGRect.zero
            if AXValueGetValue(axValue as! AXValue, .cgRect, &frame) {
                if frame.width >= 0 && frame.height > 5 && frame.height < 100 {
                    cursorBounds = frame
                    Logger.debug("Slack: Got cursor bounds from AXInsertionPointFrame: \(frame)", category: Logger.ui)
                }
            }
        }

        // Method 2: Bounds for character at cursor
        if cursorBounds == nil {
            if let bounds = getValidAXBounds(element: element, range: NSRange(location: cursorPosition, length: 1)) {
                cursorBounds = bounds
                Logger.debug("Slack: Got cursor bounds from single char: \(bounds)", category: Logger.ui)
            }
        }

        // Method 3: Bounds for character before cursor
        if cursorBounds == nil && cursorPosition > 0 {
            if let bounds = getValidAXBounds(element: element, range: NSRange(location: cursorPosition - 1, length: 1)) {
                cursorBounds = CGRect(
                    x: bounds.origin.x + bounds.width,
                    y: bounds.origin.y,
                    width: 1,
                    height: bounds.height
                )
                Logger.debug("Slack: Got cursor bounds from prev char: \(cursorBounds!)", category: Logger.ui)
            }
        }

        guard let cursor = cursorBounds else {
            return nil
        }

        // Calculate error position relative to cursor
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let multiplier = spacingMultiplier(context: context)

        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width * multiplier, 20.0)

        // Calculate X offset from cursor to error
        let charsBetween = errorRange.location - cursorPosition
        var xPosition: CGFloat

        if charsBetween >= 0 {
            // Error is after cursor
            let textBetween = String(fullText.dropFirst(cursorPosition).prefix(charsBetween))
            let offsetWidth = (textBetween as NSString).size(withAttributes: attributes).width * multiplier
            xPosition = cursor.origin.x + offsetWidth
        } else {
            // Error is before cursor
            let textBetween = String(fullText.dropFirst(errorRange.location).prefix(-charsBetween))
            let offsetWidth = (textBetween as NSString).size(withAttributes: attributes).width * multiplier
            xPosition = cursor.origin.x - offsetWidth
        }

        Logger.debug("Slack: Cursor-anchored position - cursor=\(cursorPosition), error=\(errorRange.location), x=\(xPosition)", category: Logger.ui)

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: cursor.origin.y),
            errorWidth: errorWidth,
            confidence: 0.80,
            uiContext: context,
            debugInfo: "Slack cursor-anchored (cursorPos: \(cursorPosition), charsBetween: \(charsBetween))"
        )
    }

    // MARK: - AX Bounds Helpers

    private func getValidAXBounds(element: AXUIElement, range: NSRange) -> NSRect? {
        var boundsValue: CFTypeRef?
        var axRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &axRange) else {
            return nil
        }

        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success, let bv = boundsValue else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &bounds) else {
            return nil
        }

        // Validate bounds - reject Chromium bugs (0,0,0,0) or (0, screenHeight, 0, 0)
        guard bounds.width > 5 && bounds.height > 5 && bounds.height < 100 else {
            return nil
        }

        // Also reject if origin is clearly wrong (negative or at screen edge)
        guard bounds.origin.x > 0 && bounds.origin.y > 0 else {
            return nil
        }

        return bounds
    }

    // MARK: - Text Measurement Fallback

    private func getTextMeasurementFallback(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        context: String?,
        fontSize: CGFloat
    ) -> AdjustedBounds? {
        guard let elementFrame = getElementFrame(element: element) else {
            Logger.warning("Slack: Failed to get element frame for text measurement fallback")
            return nil
        }

        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let multiplier = spacingMultiplier(context: context)
        let padding = horizontalPadding(context: context)

        // Calculate line height for Slack's message input
        let lineHeight: CGFloat = fontSize * 1.4  // ~21px for 15pt font

        // Estimate text width per line to determine wrapping
        // Slack's message input has internal padding on both sides
        let availableWidth = elementFrame.width - (padding * 2) - 20  // Extra margin for safety

        // Calculate which line the error starts on by simulating text wrapping
        let textBeforeWidth = (textBeforeError as NSString).size(withAttributes: attributes).width * multiplier
        let errorLine = Int(textBeforeWidth / availableWidth)

        // Calculate X position on that line (accounting for wrapping)
        let xOffsetOnLine = textBeforeWidth.truncatingRemainder(dividingBy: availableWidth)
        let xPosition = elementFrame.origin.x + padding + xOffsetOnLine

        // Calculate error width (may wrap to next line, but we'll underline just the visible part)
        let baseErrorWidth = (errorText as NSString).size(withAttributes: attributes).width
        let adjustedErrorWidth = max(baseErrorWidth * multiplier, 20.0)

        // Y position: In Quartz coordinates, Y increases downward from top of screen
        // Element's origin.y is the TOP of the element in Quartz
        // First line of text starts after some top padding (~8px), then each subsequent line is lineHeight lower
        let topPadding: CGFloat = 8.0
        let yPosition = elementFrame.origin.y + topPadding + (CGFloat(errorLine) * lineHeight) + (lineHeight * 0.85)

        // GRACEFUL DEGRADATION: Text measurement is less reliable
        let confidence: Double = 0.60

        Logger.debug("Slack: Text measurement - line=\(errorLine), xOffset=\(xOffsetOnLine), x=\(xPosition), y=\(yPosition), availableWidth=\(availableWidth)", category: Logger.ui)

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: yPosition),
            errorWidth: adjustedErrorWidth,
            confidence: confidence,
            uiContext: context,
            debugInfo: "Slack text measurement (line: \(errorLine), multiplier: \(multiplier))"
        )
    }

    // MARK: - Element Frame

    private func getElementFrame(element: AXUIElement) -> NSRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        var frame = NSRect(origin: position, size: size)

        // Slack's Electron-based AX implementation sometimes returns negative X values
        if position.x < 0 {
            if let windowFrame = getSlackWindowFrame(element: element, elementPosition: position) {
                let leftPadding: CGFloat = 20.0
                frame.origin.x = windowFrame.origin.x + leftPadding
                frame.origin.y = position.y
                frame.size = size
            }
        }

        return frame
    }

    private func getSlackWindowFrame(element: AXUIElement, elementPosition: NSPoint) -> NSRect? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let elementY = elementPosition.y
        var candidateWindows: [(NSRect, String)] = []

        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  windowPID == pid,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }

            let windowFrame = NSRect(x: x, y: y, width: width, height: height)
            let windowName = (windowInfo[kCGWindowName as String] as? String) ?? "Unknown"

            candidateWindows.append((windowFrame, windowName))

            let windowTop = y
            let windowBottom = y + height

            if elementY >= windowTop && elementY <= windowBottom {
                return windowFrame
            }
        }

        // Return largest window if no exact match
        if let largest = candidateWindows.max(by: { $0.0.width * $0.0.height < $1.0.width * $1.0.height }) {
            return largest.0
        }

        return nil
    }
}
