//
//  ContentParser.swift
//  Gnau
//
//  Protocol for app-specific content parsing and bounds adjustment
//  Inspired by LanguageTool's architecture with dedicated parsers per application
//

import Foundation
import AppKit

/// Result of bounds adjustment containing position and metadata
struct AdjustedBounds {
    /// The calculated screen position for the underline
    let position: NSPoint

    /// Width of the error text for underline rendering
    let errorWidth: CGFloat

    /// Confidence level of the bounds calculation (0.0 to 1.0)
    /// 1.0 = AX API returned valid bounds
    /// 0.5-0.9 = Estimation based on text measurement
    /// < 0.5 = Fallback/unreliable
    let confidence: Double

    /// UI context detected (e.g., "message-input", "search-bar", "editor")
    let uiContext: String?

    /// Debug information about how bounds were calculated
    let debugInfo: String
}

/// Protocol for app-specific content parsing and bounds adjustment
/// Each supported application should have a dedicated parser implementation
protocol ContentParser {
    /// Bundle identifier this parser supports
    var bundleIdentifier: String { get }

    /// Human-readable name for this parser
    var parserName: String { get }

    /// Adjust bounds for error positioning based on app-specific rendering
    /// - Parameters:
    ///   - element: The AXUIElement containing the text
    ///   - errorRange: Range of the error within the text
    ///   - textBeforeError: Text before the error position
    ///   - errorText: The error text itself
    ///   - fullText: Complete text content
    /// - Returns: Adjusted bounds with position and metadata
    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds?

    /// Detect UI context from the AXUIElement
    /// Used to differentiate between different input fields within the same app
    /// - Parameter element: The AXUIElement to inspect
    /// - Returns: Context identifier (e.g., "message-input", "search-bar")
    func detectUIContext(element: AXUIElement) -> String?

    /// Get estimated font size for this app's text rendering
    /// - Parameter context: UI context if available
    /// - Returns: Font size in points
    func estimatedFontSize(context: String?) -> CGFloat

    /// Get spacing multiplier for text measurement correction
    /// Different UI contexts may have different rendering characteristics
    /// - Parameter context: UI context if available
    /// - Returns: Multiplier to apply to NSFont measurements (1.0 = no adjustment)
    func spacingMultiplier(context: String?) -> CGFloat

    /// Get horizontal padding for text input elements
    /// - Parameter context: UI context if available
    /// - Returns: Left padding in points
    func horizontalPadding(context: String?) -> CGFloat

    /// Check if this parser supports the given bundle identifier
    /// - Parameter bundleID: Bundle identifier to check
    /// - Returns: True if this parser can handle the app
    func supports(bundleID: String) -> Bool
}

// MARK: - Default Implementations

extension ContentParser {
    func supports(bundleID: String) -> Bool {
        return bundleID == bundleIdentifier
    }

    /// Default bounds adjustment using generic text measurement
    /// Subclasses should override for app-specific behavior
    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        // Try to get AX bounds first
        if let axBounds = getAXBounds(element: element, range: errorRange) {
            return AdjustedBounds(
                position: NSPoint(x: axBounds.origin.x, y: axBounds.origin.y),
                errorWidth: axBounds.width,
                confidence: 1.0,
                uiContext: detectUIContext(element: element),
                debugInfo: "AX API bounds (generic parser)"
            )
        }

        // Fall back to text measurement
        let context = detectUIContext(element: element)
        let fontSize = estimatedFontSize(context: context)
        let multiplier = spacingMultiplier(context: context)
        let padding = horizontalPadding(context: context)

        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let textBeforeWidth = (textBeforeError as NSString).size(withAttributes: attributes).width
        let errorWidth = (errorText as NSString).size(withAttributes: attributes).width

        // Apply spacing correction
        let adjustedTextBeforeWidth = textBeforeWidth * multiplier

        // Get element frame for positioning
        guard let elementFrame = getElementFrame(element: element) else {
            return nil
        }

        let xPosition = elementFrame.origin.x + padding + adjustedTextBeforeWidth
        let yPosition = elementFrame.origin.y + elementFrame.height - 2 // 2pt above bottom

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: yPosition),
            errorWidth: errorWidth,
            confidence: 0.6,
            uiContext: context,
            debugInfo: "Text measurement fallback (fontSize: \(fontSize), multiplier: \(multiplier), padding: \(padding))"
        )
    }

    /// Get AX bounds for a range if available
    private func getAXBounds(element: AXUIElement, range: NSRange) -> NSRect? {
        var boundsValue: CFTypeRef?
        let location = range.location
        let length = range.length

        // Create AXValue for the range
        var axRange = CFRange(location: location, length: length)
        let rangeValue = AXValueCreate(.cfRange, &axRange)

        // Try to get bounds for range
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

        // Validate bounds (check for Electron/Chromium bugs)
        guard bounds.origin.x > 0 && bounds.origin.y > 0 &&
              bounds.width > 0 && bounds.height > 0 else {
            return nil
        }

        return bounds
    }

    /// Get element frame from AX API
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
}
