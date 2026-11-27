//
//  LineIndexStrategy.swift
//  TextWarden
//
//  Line-based positioning strategy
//  Uses AXLineForIndex and AXRangeForLine to get line bounds,
//  then calculates character offset within the line.
//

import AppKit
import ApplicationServices
import Foundation

/// Line-based positioning strategy
/// Gets line bounds then calculates X offset within the line
class LineIndexStrategy: GeometryProvider {
    typealias CopyAttribute = (AXUIElement, CFString, CFTypeRef, UnsafeMutablePointer<CFTypeRef?>) -> AXError
    private let copyAttribute: CopyAttribute

    init(copyAttribute: @escaping CopyAttribute = AXUIElementCopyParameterizedAttributeValue) {
        self.copyAttribute = copyAttribute
    }

    var strategyName: String {
        "LineIndex"
    }

    var strategyType: StrategyType {
        .lineIndex
    }

    var tier: StrategyTier {
        .reliable
    }

    var tierPriority: Int {
        10
    }

    // Uses default canHandle (returns true) - universal approach, fails gracefully

    func calculateGeometry(
        errorRange utf16Range: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {
        let originalLocationUTF16 = utf16Range.location
        guard let errorIndices = Range(utf16Range, in: text), !errorIndices.isEmpty else { return nil }
        let errorText = String(text[errorIndices])

        // Step 1: Get the line number for the error position (using UTF-16 index)
        guard let lineNumber = getLineForIndex(originalLocationUTF16, in: element) else {
            Logger.debug("LineIndexStrategy: AXLineForIndex failed for index \(originalLocationUTF16)", category: Logger.accessibility)
            return nil
        }

        Logger.debug("LineIndexStrategy: Error at UTF-16 index \(originalLocationUTF16) is on line \(lineNumber)", category: Logger.ui)

        // Step 2: Get the character range for this line
        guard let lineRange = getRangeForLine(lineNumber, in: element) else {
            Logger.debug("LineIndexStrategy: AXRangeForLine failed for line \(lineNumber)", category: Logger.accessibility)
            return nil
        }

        Logger.debug("LineIndexStrategy: Line \(lineNumber) has range \(lineRange)", category: Logger.ui)

        // Step 3: Get bounds for the entire line
        // Try AXBoundsForRange first, fall back to font-metrics estimation if unsupported
        let lineBounds: CGRect
        let usingEstimatedBounds: Bool
        if let axLineBounds = getBoundsForRange(lineRange, in: element) {
            lineBounds = axLineBounds
            usingEstimatedBounds = false
            Logger.debug("LineIndexStrategy: Line bounds (Quartz) from AX: \(lineBounds)", category: Logger.ui)
        } else {
            // Fallback: estimate line bounds using element frame and font metrics
            // This handles apps like Telegram where AXBoundsForRange is unsupported
            guard let estimatedBounds = estimateLineBounds(
                lineNumber: lineNumber,
                element: element,
                parser: parser
            ) else {
                Logger.debug("LineIndexStrategy: Both AXBoundsForRange and estimation failed for line \(lineNumber)", category: Logger.accessibility)
                return nil
            }
            lineBounds = estimatedBounds
            usingEstimatedBounds = true
            Logger.debug("LineIndexStrategy: Estimated line bounds (Quartz): \(lineBounds)", category: Logger.ui)
        }

        // Validate line bounds
        guard lineBounds.width > 0, lineBounds.height > 0, lineBounds.height < GeometryConstants.maximumLineHeight else {
            Logger.debug("LineIndexStrategy: Invalid line bounds: \(lineBounds)", category: Logger.accessibility)
            return nil
        }

        // Step 4: Calculate X offset within the line
        // All values here are in UTF-16 code units for consistency with accessibility APIs
        let lineStartUTF16 = lineRange.location
        let offsetInLineUTF16 = originalLocationUTF16 - lineStartUTF16
        guard offsetInLineUTF16 >= 0, offsetInLineUTF16 <= lineRange.length,
              let prefix = Range(NSRange(location: lineStartUTF16, length: offsetInLineUTF16), in: text)
        else { return nil }
        var textBeforeErrorInLine = String(text[prefix])

        // Handle edge case: if textBeforeErrorInLine contains a newline, the error is actually
        // on the next visual line. AXLineForIndex can return the previous line when the error
        // is at a line boundary. In this case, only use text after the last newline for
        // width calculation, and adjust the Y position to the next line.
        var lineOffsetAdjustment = 0
        if textBeforeErrorInLine.contains("\n") {
            let parts = textBeforeErrorInLine.components(separatedBy: "\n")
            lineOffsetAdjustment = parts.count - 1 // Number of newlines crossed
            textBeforeErrorInLine = parts.last ?? ""
            Logger.debug("LineIndexStrategy: Adjusted for newline boundary - \(lineOffsetAdjustment) lines down", category: Logger.ui)
        }

        Logger.debug("LineIndexStrategy: textBeforeErrorInLine=\(textBeforeErrorInLine.count) chars, errorText=\(errorText.count) chars", category: Logger.ui)

        // Calculate widths using font measurement
        // Try to get attributed string for accurate measurement of formatted text
        let textBeforeWidth: CGFloat
        let rawErrorWidth: CGFloat
        let multiplier = parser.spacingMultiplier(context: nil)

        // Try to use attributed string measurement for accuracy with formatted text (bold, italic)
        if let attrMeasurements = Self.measureUsingAttributedString(
            textBefore: textBeforeErrorInLine, errorRange: utf16Range, errorText: errorText,
            attributedString: { self.attributedString(for: $0, in: element) }
        ) {
            textBeforeWidth = attrMeasurements.textBeforeWidth
            rawErrorWidth = attrMeasurements.errorWidth * multiplier
            Logger.debug("LineIndexStrategy: Using attributed string measurement", category: Logger.ui)
        } else {
            // Fallback to basic font measurement
            let font = detectFont(from: element, parser: parser, at: originalLocationUTF16)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            textBeforeWidth = (textBeforeErrorInLine as NSString).size(withAttributes: attributes).width
            rawErrorWidth = (errorText as NSString).size(withAttributes: attributes).width * multiplier
        }
        // Minimum width proportional to character count (roughly 4px per char) to handle narrow chars like "I"
        // Old fixed minimum of 20px was too wide for short narrow-char errors like "I I"
        let minWidth = max(CGFloat(errorText.count) * 4.0, 8.0)
        let errorWidth = max(rawErrorWidth, minWidth)

        Logger.debug("LineIndexStrategy: textBeforeWidth=\(textBeforeWidth), errorWidth=\(errorWidth), multiplier=\(multiplier)", category: Logger.ui)

        // Step 5: Calculate final bounds
        let errorX = lineBounds.origin.x + textBeforeWidth

        // Adjust Y position if the error is on a different visual line than reported by AXLineForIndex
        // This happens when the error is at a line boundary (right after a newline)
        let lineHeight = lineBounds.height
        let errorY: CGFloat
        if lineOffsetAdjustment > 0 {
            // Move down by the number of newlines crossed
            // In Quartz coordinates (top-left origin), increasing Y moves down
            errorY = lineBounds.origin.y + (CGFloat(lineOffsetAdjustment) * lineHeight)
            Logger.debug("LineIndexStrategy: Adjusted Y from \(lineBounds.origin.y) to \(errorY) (\(lineOffsetAdjustment) lines)", category: Logger.ui)
        } else {
            errorY = lineBounds.origin.y
        }
        let errorHeight = lineHeight

        let quartzBounds = CGRect(
            x: errorX,
            y: errorY,
            width: errorWidth,
            height: errorHeight
        )

        Logger.debug("LineIndexStrategy: Quartz bounds: \(quartzBounds)", category: Logger.ui)

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        Logger.debug("LineIndexStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        // Validate final bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("LineIndexStrategy: Final bounds validation failed: \(cocoaBounds)", category: Logger.accessibility)
            return nil
        }

        Logger.debug("LineIndexStrategy: SUCCESS - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: usingEstimatedBounds ? GeometryConstants.mediumConfidence : GeometryConstants.reliableConfidence,
            strategy: strategyName,
            metadata: [
                "api": usingEstimatedBounds ? "line-index-estimated" : "line-index",
                "line_number": lineNumber,
                "line_range": "\(lineRange)",
                "offset_in_line_utf16": offsetInLineUTF16,
                "using_estimated_bounds": usingEstimatedBounds,
            ]
        )
    }

    // MARK: - AX API Helpers

    private func getLineForIndex(_ index: Int, in element: AXUIElement) -> Int? {
        var indexValue = index
        guard let indexRef = CFNumberCreate(kCFAllocatorDefault, .intType, &indexValue) else {
            return nil
        }

        var lineValue: CFTypeRef?
        let result = copyAttribute(
            element,
            "AXLineForIndex" as CFString,
            indexRef,
            &lineValue
        )

        guard result == .success, let line = lineValue as? Int else {
            return nil
        }

        return line
    }

    private func getRangeForLine(_ lineNumber: Int, in element: AXUIElement) -> NSRange? {
        var lineValue = lineNumber
        guard let lineRef = CFNumberCreate(kCFAllocatorDefault, .intType, &lineValue) else {
            return nil
        }

        var rangeValue: CFTypeRef?
        let result = copyAttribute(
            element,
            "AXRangeForLine" as CFString,
            lineRef,
            &rangeValue
        )

        guard result == .success,
              let rv = rangeValue,
              let range = safeAXValueGetRange(rv), range.location >= 0, range.length >= 0
        else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    private func getBoundsForRange(_ range: NSRange, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let result = copyAttribute(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success,
              let bv = boundsValue,
              let bounds = safeAXValueGetRect(bv)
        else {
            return nil
        }

        return bounds
    }

    // MARK: - Attributed String Measurement

    static func measureUsingAttributedString(
        textBefore: String, errorRange: NSRange, errorText: String,
        attributedString: (NSRange) -> NSAttributedString?
    ) -> (textBeforeWidth: CGFloat, errorWidth: CGFloat)? {
        func width(of text: String, in range: NSRange) -> CGFloat? {
            if text.isEmpty { return 0 }
            guard let attributed = attributedString(range),
                  attributed.string.utf16.elementsEqual(text.utf16)
            else { return nil }

            // AXFont is a dictionary. AppKit measures it using the default font unless we supply .font.
            var measured: NSMutableAttributedString?
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, run, _ in
                guard attributes[.font] == nil, let font = font(from: attributes) else { return }
                if measured == nil { measured = NSMutableAttributedString(attributedString: attributed) }
                measured?.addAttribute(.font, value: font, range: run)
            }
            return (measured ?? attributed).size().width
        }

        let length = textBefore.utf16.count
        guard length <= errorRange.location,
              let before = width(of: textBefore, in: NSRange(location: errorRange.location - length, length: length)),
              let error = width(of: errorText, in: errorRange)
        else { return nil }
        return (before, error)
    }

    private func attributedString(for range: NSRange, in element: AXUIElement) -> NSAttributedString? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        guard copyAttribute(
            element, kAXAttributedStringForRangeParameterizedAttribute as CFString, parameter, &value
        ) == .success else { return nil }
        return value as? NSAttributedString
    }

    // MARK: - Font Detection

    /// Detect the font being used in the element for accurate text measurement
    private func detectFont(from element: AXUIElement, parser: ContentParser, at position: Int = 0) -> NSFont {
        // Try to get font info from attributed string at the specified position
        if let attributed = attributedString(for: NSRange(location: position, length: 1), in: element),
           attributed.length > 0, let font = Self.font(from: attributed.attributes(at: 0, effectiveRange: nil))
        {
            Logger.debug("LineIndexStrategy: Detected font '\(font.fontName)' size \(font.pointSize)", category: Logger.ui)
            return font
        }

        // Fallback to parser's estimated font size
        let context = parser.detectUIContext(element: element)
        let fontSize = parser.estimatedFontSize(context: context)

        // Use configured font family if available, otherwise system font
        if let fontFamily = parser.fontFamily(context: context),
           let font = NSFont(name: fontFamily, size: fontSize)
        {
            Logger.debug("LineIndexStrategy: Using configured font '\(fontFamily)' size \(fontSize)", category: Logger.ui)
            return font
        }

        Logger.debug("LineIndexStrategy: Using fallback system font size \(fontSize)", category: Logger.ui)
        return NSFont.systemFont(ofSize: fontSize)
    }

    private static func font(from attributes: [NSAttributedString.Key: Any]) -> NSFont? {
        if let font = attributes[.font] as? NSFont { return font }
        guard let axFont = attributes[NSAttributedString.Key("AXFont")] as? [String: Any],
              let name = axFont["AXFontName"] as? String,
              let size = axFont["AXFontSize"] as? CGFloat
        else { return nil }
        return NSFont(name: name, size: size)
    }

    // MARK: - Bounds Estimation Fallback

    /// Estimate line bounds when AXBoundsForRange is unavailable
    /// Uses element frame and font metrics to calculate approximate line position
    /// This is a fallback for apps like Telegram where AXBoundsForRange returns error
    private func estimateLineBounds(
        lineNumber: Int,
        element: AXUIElement,
        parser: ContentParser
    ) -> CGRect? {
        // Get element frame (position + size)
        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
            Logger.debug("LineIndexStrategy: Failed to get element frame for estimation", category: Logger.accessibility)
            return nil
        }

        // Get font info for line height calculation
        let font = detectFont(from: element, parser: parser)
        let lineHeight = font.pointSize * GeometryConstants.lineHeightMultiplier

        // Calculate Y position for this line
        // In Quartz coordinates, Y increases downward from top-left
        // Line 0 is at the top of the element
        let lineY = elementFrame.origin.y + (CGFloat(lineNumber) * lineHeight) + 4 // 4pt top padding estimate

        // Use element X for line start and full width
        let lineX = elementFrame.origin.x
        let lineWidth = elementFrame.size.width

        Logger.debug("LineIndexStrategy: Estimated line \(lineNumber) at Y=\(lineY), lineHeight=\(lineHeight)", category: Logger.accessibility)

        return CGRect(
            x: lineX,
            y: lineY,
            width: lineWidth,
            height: lineHeight
        )
    }
}
