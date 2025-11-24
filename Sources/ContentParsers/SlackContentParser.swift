//
//  SlackContentParser.swift
//  TextWarden
//
//  Slack-specific content parser with UI context detection
//  Handles different text rendering in message input vs search bar vs thread replies
//  Based on empirical calibration data from Scripts/analyze-slack-spacing.swift
//

import Foundation
import AppKit

// MARK: - Debug Border Window
class DebugBorderWindow: NSPanel {
    static var debugWindows: [DebugBorderWindow] = []

    init(frame: NSRect, color: NSColor, label: String) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver  // HIGHER than .floating to be on top
        self.ignoresMouseEvents = true
        self.hasShadow = false

        let borderView = DebugBorderView(color: color, label: label)
        self.contentView = borderView

        self.orderFront(nil)
        DebugBorderWindow.debugWindows.append(self)
    }

    static func clearAll() {
        for window in debugWindows {
            window.close()
        }
        debugWindows.removeAll()
    }
}

class DebugBorderView: NSView {
    let borderColor: NSColor
    let label: String

    init(color: NSColor, label: String) {
        self.borderColor = color
        self.label = label
        super.init(frame: .zero)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw THICK border only (no fill)
        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(5.0)  // Thicker!
        context.stroke(bounds.insetBy(dx: 2.5, dy: 2.5))

        // Draw label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),  // Bigger!
            .foregroundColor: borderColor
        ]
        let labelStr = label as NSString
        let textSize = labelStr.size(withAttributes: attrs)

        // Position blue box label (CGWindow coords) in top right, others in top left
        let xPosition: CGFloat
        if label.contains("CGWindow") {
            xPosition = bounds.width - textSize.width - 10  // Top right
        } else {
            xPosition = 10  // Top left
        }

        labelStr.draw(at: NSPoint(x: xPosition, y: bounds.height - 30), withAttributes: attrs)
    }
}

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

        let calibration = UserPreferences.shared.getCalibration(for: bundleIdentifier)

        // STRATEGY: Use AX API to get bounds for FULL TEXT, then calculate average char width
        // This adapts automatically to zoom levels, font sizes, DPI, etc.
        let fullTextRange = NSRange(location: 0, length: fullText.count)
        if let fullTextBounds = tryGetAXBounds(element: element, range: fullTextRange),
           fullText.count > 0 {
            // Calculate average character width from actual rendered text
            let averageCharWidth = fullTextBounds.width / CGFloat(fullText.count)

            // Position error based on character index
            let baseXPosition = fullTextBounds.origin.x + (CGFloat(errorRange.location) * averageCharWidth)
            let baseErrorWidth = CGFloat(errorRange.length) * averageCharWidth

            // Apply calibration
            let xPosition = baseXPosition + calibration.horizontalOffset
            let errorWidth = baseErrorWidth * calibration.widthMultiplier

            let debugInfo = "Slack: Using full text AX bounds. chars=\(fullText.count), avgWidth=\(String(format: "%.2f", averageCharWidth))px, textBounds=\(fullTextBounds), calibration=(offset=\(calibration.horizontalOffset), width=\(calibration.widthMultiplier)x)"
            Logger.info(debugInfo)

            return AdjustedBounds(
                position: NSPoint(x: xPosition, y: fullTextBounds.origin.y + fullTextBounds.height - 2),
                errorWidth: errorWidth,
                confidence: 1.0,
                uiContext: context,
                debugInfo: debugInfo
            )
        }

        // Try AX bounds for error range directly (fallback)
        if let axBounds = tryGetAXBounds(element: element, range: errorRange) {
            // Apply calibration
            let xPosition = axBounds.origin.x + calibration.horizontalOffset
            let errorWidth = axBounds.width * calibration.widthMultiplier

            let debugInfo = "AX API (direct error bounds), calibration=(offset=\(calibration.horizontalOffset), width=\(calibration.widthMultiplier)x)"
            Logger.debug("Slack: AX API returned valid bounds for error range! context=\(context ?? "unknown"), bounds=\(axBounds), \(debugInfo)")
            return AdjustedBounds(
                position: NSPoint(x: xPosition, y: axBounds.origin.y),
                errorWidth: errorWidth,
                confidence: 1.0,
                uiContext: context,
                debugInfo: debugInfo
            )
        }

        // Try character-by-character AX bounds first
        // This approach:
        // 1. Calls AXBoundsForRange for EACH character
        // 2. Uses the X coordinates DIRECTLY (no multiplication!)
        // 3. Falls back to measurement only if AX fails
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
            let baseXPosition = lastCharBounds.origin.x + lastCharBounds.width

            // Total width calculation for debugging
            let startX = firstCharBounds.origin.x
            let totalWidth = baseXPosition - startX

            let errorBounds = tryGetAXBounds(element: element, range: errorRange)
            let baseErrorWidth = errorBounds?.width ?? measureErrorWidth(errorText, fontSize: fontSize)

            // Apply calibration
            let xPosition = baseXPosition + calibration.horizontalOffset
            let errorWidth = baseErrorWidth * calibration.widthMultiplier

            let debugInfo = """
                Slack AX bounds (char-by-char): \
                charCount=\(textBeforeError.count), \
                xPosition=\(String(format: "%.2f", xPosition))px, \
                totalWidth=\(String(format: "%.2f", totalWidth))px, \
                firstChar=\(firstCharBounds), lastChar=\(lastCharBounds), \
                calibration=(offset=\(calibration.horizontalOffset), width=\(calibration.widthMultiplier)x)
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

        // Apply spacing multiplier to match Slack's Chromium rendering
        // Slack renders text ~6% narrower than NSFont measures (0.94x)
        // Using multiplier instead of per-character correction avoids cumulative drift
        let adjustedTextBeforeWidth = baseTextBeforeWidth * multiplier
        let adjustedErrorWidth = baseErrorWidth * multiplier

        guard let elementFrame = getElementFrame(element: element) else {
            Logger.error("Slack: Failed to get element frame")
            return nil
        }

        let baseXPosition = elementFrame.origin.x + adjustedTextBeforeWidth
        let xPosition = baseXPosition + calibration.horizontalOffset
        let errorWidth = adjustedErrorWidth * calibration.widthMultiplier

        // Position at text baseline (0.82 from bottom accounts for text rendering offset)
        let yPosition = elementFrame.origin.y + (elementFrame.height * 0.82)

        let debugInfo = """
            Slack text measurement fallback: context=\(context ?? "unknown"), \
            fontSize=\(fontSize)pt, multiplier=\(multiplier)x, padding=\(padding)px, \
            baseWidth=\(String(format: "%.2f", baseTextBeforeWidth))px, \
            adjusted=\(String(format: "%.2f", adjustedTextBeforeWidth))px, \
            calibration=(offset=\(calibration.horizontalOffset), width=\(calibration.widthMultiplier)x)
            """

        Logger.debug(debugInfo)

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: yPosition),
            errorWidth: errorWidth,
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
        // The element parameter is the actual text field, so we want ITS bounds
        return getElementFrameFromAX(element: element)
    }

    private func getElementFrameFromAX(element: AXUIElement) -> NSRect? {
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

        // Slack's Electron-based AX implementation returns negative X values as sentinel values
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

        // Find Slack's window that contains the text input element
        // Element position Y is reliable even though X is broken
        let elementY = elementPosition.y  // This is in Quartz coordinates

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
            let windowLayer = windowInfo[kCGWindowLayer as String] as? Int ?? -1

            candidateWindows.append((windowFrame, windowName))

            Logger.debug("SLACK: Found window: \(windowName), Frame: \(windowFrame), Layer: \(windowLayer)", category: Logger.ui)

            // Check if element Y position is within this window's Y range
            let windowTop = y
            let windowBottom = y + height

            if elementY >= windowTop && elementY <= windowBottom {
                Logger.debug("SLACK: Window '\(windowName)' contains element (Y=\(elementY) in range \(windowTop)-\(windowBottom))", category: Logger.ui)

                return windowFrame
            }
        }

        // If no window contains the element, log all candidates and return the largest
        if !candidateWindows.isEmpty {
            Logger.debug("SLACK: No window contains element Y=\(elementY). Found \(candidateWindows.count) windows. Using largest.", category: Logger.ui)

            let largest = candidateWindows.max(by: { $0.0.width * $0.0.height < $1.0.width * $1.0.height })
            return largest?.0
        }

        return nil
    }

    private func measureErrorWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }
}
