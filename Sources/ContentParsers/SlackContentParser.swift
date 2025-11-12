//
//  SlackContentParser.swift
//  Gnau
//
//  Slack-specific content parser with UI context detection
//  Handles different text rendering in message input vs search bar vs thread replies
//
//  Based on reverse-engineering LanguageTool's AXContentParserSlack implementation
//  and empirical calibration data from Scripts/analyze-slack-spacing.swift
//

import Foundation
import AppKit

/// Slack-specific content parser
/// Handles Electron/React rendering quirks and multiple UI contexts
class SlackContentParser: ContentParser {
    let bundleIdentifier = "com.tinyspeck.slackmacgap"
    let parserName = "Slack"

    /// UI contexts within Slack with different rendering characteristics
    private enum SlackContext: String {
        case messageInput = "message-input"     // Main message composition
        case searchBar = "search-bar"           // Global search
        case threadReply = "thread-reply"       // Thread reply input
        case editMessage = "edit-message"       // Editing existing message
        case unknown = "unknown"
    }

    func detectUIContext(element: AXUIElement) -> String? {
        // Try to get AXRole and AXDescription for context detection
        var roleValue: CFTypeRef?
        var descValue: CFTypeRef?
        var identifierValue: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)

        let role = roleValue as? String
        let description = descValue as? String
        let identifier = identifierValue as? String

        // Heuristics based on AX attributes
        // Note: Slack's Electron app has limited AX support, so this may be unreliable

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

        // Default to message input if we can't determine
        return SlackContext.messageInput.rawValue
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Slack uses consistent 15pt font across all UI contexts
        return 15.0
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // DATA-DRIVEN CALIBRATION (see Scripts/analyze-slack-spacing.swift)
        //
        // Root cause: Slack's Chromium renderer displays text ~6% narrower than NSFont measures
        // Likely due to: letter-spacing CSS, font substitution, or Chromium text shaping vs CoreText
        //
        // Empirical testing with "Blub. This is a test Message" (28 chars):
        //   NSFont measures: 190.54px
        //   0.95x: 181.01px - Close, but slightly too far RIGHT
        //   0.94x: 179.11px - Optimal (saves 0.41px per char)
        //   0.93x: 177.20px - Too far LEFT (saves 0.48px per char)
        //
        // Different UI contexts within Slack may have different rendering:
        guard let ctx = context else {
            return 0.94 // Default for message input
        }

        let slackContext = SlackContext(rawValue: ctx) ?? .unknown

        switch slackContext {
        case .messageInput:
            // Main message composition area
            // Calibrated to 0.94x based on user feedback
            return 0.94

        case .searchBar:
            // Global search bar has different rendering than message input
            // User feedback: underline too far right with 1.0x, needs correction
            // Testing shows search bar also needs spacing reduction, but less than message input
            return 0.96 // Less correction than message input (0.94x)

        case .threadReply:
            // Thread replies use same CSS as message input
            return 0.94

        case .editMessage:
            // Editing uses same input styling
            return 0.94

        case .unknown:
            // Conservative fallback
            return 0.94
        }
    }

    func horizontalPadding(context: String?) -> CGFloat {
        // Slack's message input has approximately 12px left padding
        // Search bar has different padding
        guard let ctx = context else {
            return 12.0
        }

        let slackContext = SlackContext(rawValue: ctx) ?? .unknown

        switch slackContext {
        case .messageInput:
            return 12.0
        case .searchBar:
            return 16.0 // Search bar has slightly more padding
        case .threadReply:
            return 12.0
        case .editMessage:
            return 12.0
        case .unknown:
            return 12.0
        }
    }

    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        // STRATEGY:
        // 1. Try AX API (will likely fail for Slack due to Electron bugs)
        // 2. Fall back to context-aware text measurement with PER-CHARACTER correction
        // 3. Log detailed debug info for future calibration

        let context = detectUIContext(element: element)
        let fontSize = estimatedFontSize(context: context)
        let multiplier = spacingMultiplier(context: context)
        let padding = horizontalPadding(context: context)

        // Try AX bounds first (mostly for validation/debugging)
        if let axBounds = tryGetAXBounds(element: element, range: errorRange) {
            Logger.debug("Slack: AX API returned valid bounds! context=\(context ?? "unknown"), bounds=\(axBounds)")
            return AdjustedBounds(
                position: NSPoint(x: axBounds.origin.x, y: axBounds.origin.y),
                errorWidth: axBounds.width,
                confidence: 1.0,
                uiContext: context,
                debugInfo: "AX API (unexpected success in Slack)"
            )
        }

        // LANGUAGETOOL'S ACTUAL APPROACH: Character-by-character AXBoundsForRange
        // According to binary analysis, LanguageTool:
        // 1. Calls AXBoundsForRange for EACH character
        // 2. Uses the X coordinates DIRECTLY (no multiplication!)
        // 3. Falls back to measurement only if AX fails

        // Try character-by-character AX bounds first
        var characterBounds: [CGRect] = []
        var allAXSucceeded = true

        for index in 0..<textBeforeError.count {
            let charRange = NSRange(location: errorRange.location - textBeforeError.count + index, length: 1)

            if let bounds = tryGetAXBounds(element: element, range: charRange) {
                characterBounds.append(bounds)
            } else {
                allAXSucceeded = false
                break
            }
        }

        // If we got AX bounds for all characters, use them DIRECTLY
        if allAXSucceeded && !characterBounds.isEmpty {
            let firstCharBounds = characterBounds[0]
            let lastCharBounds = characterBounds[characterBounds.count - 1]

            // X position where error starts = right edge of last character before error
            let xPosition = lastCharBounds.origin.x + lastCharBounds.width

            // Total width calculation for debugging
            let startX = firstCharBounds.origin.x
            let totalWidth = xPosition - startX

            // Get error width from AX or measurement
            let errorBounds = tryGetAXBounds(element: element, range: errorRange)
            let errorWidth = errorBounds?.width ?? measureErrorWidth(errorText, fontSize: fontSize)

            let debugInfo = """
                Slack AX bounds (LanguageTool method): \
                charCount=\(textBeforeError.count), \
                xPosition=\(String(format: "%.2f", xPosition))px, \
                totalWidth=\(String(format: "%.2f", totalWidth))px, \
                firstChar=\(firstCharBounds), lastChar=\(lastCharBounds)
                """

            Logger.info(debugInfo)

            return AdjustedBounds(
                position: NSPoint(x: xPosition, y: lastCharBounds.origin.y + lastCharBounds.height - 2),
                errorWidth: errorWidth,
                confidence: 1.0, // AX API = highest confidence
                uiContext: context,
                debugInfo: debugInfo
            )
        }

        // FALLBACK: Text measurement (if AX fails)
        Logger.debug("Slack: AX bounds failed, falling back to text measurement")

        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let baseTextBeforeWidth = (textBeforeError as NSString).size(withAttributes: attributes).width
        let baseErrorWidth = (errorText as NSString).size(withAttributes: attributes).width

        // NEW: Per-character pixel correction instead of percentage multiplier
        // This avoids cumulative drift on long lines
        // Slack renders each character ~0.4px narrower than NSFont measures
        let pixelCorrectionPerChar: CGFloat = 0.4
        let adjustedTextBeforeWidth = baseTextBeforeWidth - (CGFloat(textBeforeError.count) * pixelCorrectionPerChar)

        guard let elementFrame = getElementFrame(element: element) else {
            Logger.error("Slack: Failed to get element frame")
            return nil
        }

        let xPosition = elementFrame.origin.x + padding + adjustedTextBeforeWidth
        let yPosition = elementFrame.origin.y + elementFrame.height - 2

        let debugInfo = """
            Slack text measurement fallback: context=\(context ?? "unknown"), \
            fontSize=\(fontSize)pt, multiplier=\(multiplier)x, padding=\(padding)px, \
            baseWidth=\(String(format: "%.2f", baseTextBeforeWidth))px, \
            adjusted=\(String(format: "%.2f", adjustedTextBeforeWidth))px
            """

        Logger.debug(debugInfo)

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: yPosition),
            errorWidth: baseErrorWidth,
            confidence: 0.75,
            uiContext: context,
            debugInfo: debugInfo
        )
    }

    // MARK: - Private Helpers

    private func tryGetAXBounds(element: AXUIElement, range: NSRange) -> NSRect? {
        var boundsValue: CFTypeRef?
        let location = range.location
        let length = range.length

        var axRange = CFRange(location: location, length: length)
        let rangeValue = AXValueCreate(.cfRange, &axRange)

        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue!,
            &boundsValue
        )

        guard result == .success, let boundsValue = boundsValue else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) else {
            return nil
        }

        // Validate bounds (Slack/Electron typically returns XOrigin=0, YOrigin=screen height)
        guard bounds.origin.x > 0 && bounds.origin.y > 0 &&
              bounds.origin.y < NSScreen.main!.frame.height && // Not at screen edge
              bounds.width > 0 && bounds.height > 0 else {
            return nil
        }

        return bounds
    }

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

        return NSRect(origin: position, size: size)
    }

    private func measureErrorWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }
}
