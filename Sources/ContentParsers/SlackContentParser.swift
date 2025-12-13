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
/// Uses graceful degradation: error indicator shown but underlines hidden
/// due to Slack's AX APIs returning invalid bounds (Chromium bug)
class SlackContentParser: ContentParser {
    let bundleIdentifier = "com.tinyspeck.slackmacgap"
    let parserName = "Slack"

    /// Cached configuration from AppRegistry
    private var config: AppConfiguration {
        AppRegistry.shared.configuration(for: bundleIdentifier)
    }

    /// Visual underlines enabled/disabled from AppConfiguration
    var disablesVisualUnderlines: Bool {
        return !config.features.visualUnderlinesEnabled
    }

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
        // Use font size from AppConfiguration
        return config.fontConfig.defaultSize
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // Base multiplier from AppConfiguration, with context-specific adjustments
        let baseMultiplier = config.fontConfig.spacingMultiplier
        guard let ctx = context else {
            return baseMultiplier
        }

        let slackContext = SlackContext(rawValue: ctx) ?? .unknown

        switch slackContext {
        case .messageInput, .threadReply, .editMessage, .unknown:
            return baseMultiplier
        case .searchBar:
            return baseMultiplier + 0.01  // Slightly wider for search bar
        }
    }

    func horizontalPadding(context: String?) -> CGFloat {
        // Base padding from AppConfiguration, with context-specific adjustments
        let basePadding = config.horizontalPadding
        guard let ctx = context else {
            return basePadding
        }

        let slackContext = SlackContext(rawValue: ctx) ?? .unknown

        switch slackContext {
        case .searchBar:
            return basePadding + 4.0  // Extra padding for search bar
        default:
            return basePadding
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
        if let axBounds = getSlackValidatedBounds(element: element, range: errorRange) {
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
        ) == .success,
              let rangeRef = selectedRangeValue,
              let selectedRange = safeAXValueGetRange(rangeRef) else {
            return nil
        }

        let cursorPosition = selectedRange.location

        // Try to get bounds at cursor position
        var cursorBounds: CGRect?

        // Method 1: AXInsertionPointFrame
        var insertionPointValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointFrame" as CFString, &insertionPointValue) == .success,
           let axValue = insertionPointValue,
           let frame = safeAXValueGetRect(axValue) {
            if frame.width >= 0 && frame.height > GeometryConstants.minimumBoundsSize && frame.height < GeometryConstants.conservativeMaxLineHeight {
                cursorBounds = frame
                Logger.debug("Slack: Got cursor bounds from AXInsertionPointFrame: \(frame)", category: Logger.ui)
            }
        }

        // Method 2: Bounds for character at cursor
        if cursorBounds == nil {
            if let bounds = getSlackValidatedBounds(element: element, range: NSRange(location: cursorPosition, length: 1)) {
                cursorBounds = bounds
                Logger.debug("Slack: Got cursor bounds from single char: \(bounds)", category: Logger.ui)
            }
        }

        // Method 3: Bounds for character before cursor
        if cursorBounds == nil && cursorPosition > 0 {
            if let bounds = getSlackValidatedBounds(element: element, range: NSRange(location: cursorPosition - 1, length: 1)) {
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

    /// Get validated bounds with Slack-specific origin check
    /// Slack's Electron app sometimes returns negative coordinates
    private func getSlackValidatedBounds(element: AXUIElement, range: NSRange) -> CGRect? {
        guard let bounds = AccessibilityBridge.getBoundsForRange(range, in: element) else {
            return nil
        }

        // Slack-specific: reject negative or zero origin (Electron bug)
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
        guard let elementFrame = getSlackElementFrame(element: element) else {
            Logger.warning("Slack: Failed to get element frame for text measurement fallback")
            return nil
        }

        // Use Lato font if available (Slack's actual font), otherwise fall back to system font
        // Apply a multiplier to correct for font rendering differences between macOS and Chromium
        let font: NSFont
        let multiplier: CGFloat

        if let latoFont = NSFont(name: "Lato-Regular", size: fontSize) ??
                          NSFont(name: "Lato", size: fontSize) {
            font = latoFont
            // Lato renders almost identically, minimal correction needed
            multiplier = 0.99
            Logger.debug("Slack: Using Lato font for text measurement", category: Logger.ui)
        } else {
            // Fall back to system font with Chromium rendering correction
            font = NSFont.systemFont(ofSize: fontSize)
            // Chromium's text rendering is narrower than macOS for system font
            multiplier = spacingMultiplier(context: context)
            Logger.debug("Slack: Lato not found, using system font with multiplier \(multiplier)", category: Logger.ui)
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
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

    /// Get element frame with Slack-specific workaround for negative X values
    private func getSlackElementFrame(element: AXUIElement) -> CGRect? {
        guard var frame = AccessibilityBridge.getElementFrame(element) else {
            return nil
        }

        // Slack's Electron-based AX implementation sometimes returns negative X values
        if frame.origin.x < 0 {
            if let windowFrame = getSlackWindowFrame(element: element, elementPosition: frame.origin) {
                let leftPadding: CGFloat = 20.0
                frame.origin.x = windowFrame.origin.x + leftPadding
                // Keep original Y and size
            }
        }

        return frame
    }

    private func getSlackWindowFrame(element: AXUIElement, elementPosition: CGPoint) -> CGRect? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let elementY = elementPosition.y
        var candidateWindows: [(CGRect, String)] = []

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

            let windowFrame = CGRect(x: x, y: y, width: width, height: height)
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
