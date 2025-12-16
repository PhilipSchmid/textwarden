//
//  ContentParser.swift
//  TextWarden
//
//  Protocol for app-specific content parsing and bounds adjustment
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

    /// Get configured font family for this app
    /// Used when accessibility APIs don't provide font information
    /// - Parameter context: UI context if available
    /// - Returns: Font family name, or nil to use system font
    func fontFamily(context: String?) -> String?

    /// Get horizontal padding for text input elements
    /// - Parameter context: UI context if available
    /// - Returns: Left padding in points
    func horizontalPadding(context: String?) -> CGFloat

    /// Check if this parser supports the given bundle identifier
    /// - Parameter bundleID: Bundle identifier to check
    /// - Returns: True if this parser can handle the app
    func supports(bundleID: String) -> Bool

    /// Preprocess text before grammar analysis
    /// Allows app-specific filtering of text (e.g., terminal output removal)
    /// - Parameter text: Raw text extracted from UI element
    /// - Returns: Filtered text ready for grammar checking, or nil to skip analysis
    func preprocessText(_ text: String) -> String?

    /// Custom text extraction for apps with non-standard accessibility structures
    /// Override this for apps where standard AXValue doesn't work (e.g., Apple Mail's WebKit)
    /// - Parameter element: The AXUIElement to extract text from
    /// - Returns: Extracted text, or nil to fall back to standard extraction
    func extractText(from element: AXUIElement) -> String?

    /// Whether this parser wants to disable visual underlines
    /// Used for apps where positioning is unreliable (terminals, some Electron apps)
    /// When true, errors will use alternative notification (floating indicator)
    var disablesVisualUnderlines: Bool { get }

    /// Offset to add to error positions when applying text replacements
    /// Used by terminal parsers where error positions are based on preprocessed text
    /// but replacements need to be applied to the full text (including prompt)
    /// Returns 0 for most parsers, only non-zero for terminal parsers
    var textReplacementOffset: Int { get }

    /// Calculate selection offset for a given position in text.
    /// Used by positioning strategies to adjust for app-specific text representation differences.
    /// For example, Slack replaces emojis with newlines in AXValue but selection API ignores them.
    /// - Parameters:
    ///   - position: The grapheme cluster position in the text
    ///   - text: The full text content from the element
    /// - Returns: Number of characters to subtract from position for selection API
    func selectionOffset(at position: Int, in text: String) -> Int

    /// Whether this app requires UTF-16 index conversion for Chromium selection APIs.
    /// When true, ChromiumStrategy converts grapheme cluster indices to UTF-16 code unit indices.
    /// This is needed for apps where emojis/special characters cause position drift.
    /// Default is false to preserve existing behavior for apps like Slack.
    var requiresUTF16Conversion: Bool { get }

    /// Custom bounds calculation for apps with non-standard accessibility APIs.
    /// Override this for apps where standard AXBoundsForRange doesn't work correctly
    /// (e.g., Apple Mail's WebKit which needs single-char queries and coordinate conversion).
    /// - Parameters:
    ///   - range: Character range to get bounds for
    ///   - element: The AXUIElement containing the text
    /// - Returns: Bounds in Quartz screen coordinates, or nil to use standard calculation
    func getBoundsForRange(range: NSRange, in element: AXUIElement) -> CGRect?

    /// Resolve position geometry for error range using multi-strategy engine
    /// - Parameters:
    ///   - errorRange: NSRange of the error within the text
    ///   - element: AXUIElement containing the text
    ///   - text: Full text content from the element
    ///   - actualBundleID: Optional actual bundle ID (use when parser's bundleIdentifier differs from runtime bundle)
    /// - Returns: GeometryResult with bounds and confidence information
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String,
        actualBundleID: String?
    ) -> GeometryResult
}

// MARK: - Default Implementations

extension ContentParser {
    func supports(bundleID: String) -> Bool {
        return bundleID == bundleIdentifier
    }

    /// Default implementation: no preprocessing, return text as-is
    func preprocessText(_ text: String) -> String? {
        return text
    }

    /// Default: no custom extraction, use standard AXValue
    func extractText(from element: AXUIElement) -> String? {
        return nil
    }

    /// Default: allow visual underlines
    var disablesVisualUnderlines: Bool {
        return false
    }

    /// Default: no offset needed for text replacement
    var textReplacementOffset: Int {
        return 0
    }

    /// Default: no selection offset adjustment needed
    func selectionOffset(at position: Int, in text: String) -> Int {
        return 0
    }

    /// Default: no UTF-16 conversion needed (preserves existing behavior for Slack, etc.)
    var requiresUTF16Conversion: Bool {
        return false
    }

    /// Default: no custom bounds calculation, return nil to use standard API
    func getBoundsForRange(range: NSRange, in element: AXUIElement) -> CGRect? {
        return nil
    }

    /// Default: no configured font family, use system font
    func fontFamily(context: String?) -> String? {
        return nil
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

        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
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
    private func getAXBounds(element: AXUIElement, range: NSRange) -> CGRect? {
        var boundsValue: CFTypeRef?
        let location = range.location
        let length = range.length

        var axRange = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &axRange) else {
            return nil
        }

        // Try to get bounds for range
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success, let boundsValue = boundsValue else {
            return nil
        }

        guard let bounds = safeAXValueGetRect(boundsValue) else {
            return nil
        }

        // Validate bounds (check for Electron/Chromium bugs)
        // Only reject truly invalid values: negative dimensions or extreme negative positions
        // X=0 and Y=0 are valid (element at screen edge)
        guard bounds.origin.x >= -1000 && bounds.origin.y >= -1000 &&
              bounds.width > 0 && bounds.height > 0 else {
            return nil
        }

        return bounds
    }

    /// Resolve position geometry for error range using multi-strategy engine
    /// This is the primary entry point for position calculation
    /// Automatically tries multiple strategies in priority order with caching
    ///
    /// - Parameters:
    ///   - errorRange: NSRange of the error within the text
    ///   - element: AXUIElement containing the text
    ///   - text: Full text content from the element
    ///   - actualBundleID: Optional actual bundle ID (use when parser's bundleIdentifier differs from runtime bundle)
    /// - Returns: GeometryResult with bounds and confidence information
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String,
        actualBundleID: String? = nil
    ) -> GeometryResult {
        return PositionResolver.shared.resolvePosition(
            for: errorRange,
            in: element,
            text: text,
            parser: self,
            bundleID: actualBundleID ?? bundleIdentifier
        )
    }
}
