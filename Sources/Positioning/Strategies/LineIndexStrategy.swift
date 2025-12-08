//
//  LineIndexStrategy.swift
//  TextWarden
//
//  Line-based positioning strategy
//  Uses AXLineForIndex and AXRangeForLine to get line bounds,
//  then calculates character offset within the line.
//

import Foundation
import AppKit
import ApplicationServices

/// Line-based positioning strategy
/// Gets line bounds then calculates X offset within the line
class LineIndexStrategy: GeometryProvider {

    var strategyName: String { "LineIndex" }
    var strategyType: StrategyType { .lineIndex }
    var tier: StrategyTier { .reliable }
    var tierPriority: Int { 10 }

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Universal approach - fails gracefully if APIs aren't supported
        return true
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("LineIndexStrategy: Starting for range \(errorRange)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates (still in grapheme clusters)
        let offset = parser.textReplacementOffset
        let originalLocationGrapheme = errorRange.location + offset

        // Convert grapheme cluster index to UTF-16 for accessibility APIs
        // macOS accessibility APIs (AXLineForIndex, AXRangeForLine, AXBoundsForRange) use UTF-16 code units
        let originalLocationUTF16 = graphemeToUTF16(originalLocationGrapheme, in: text)
        let errorLengthUTF16 = graphemeToUTF16(originalLocationGrapheme + errorRange.length, in: text) - originalLocationUTF16

        Logger.debug("LineIndexStrategy: Grapheme location \(originalLocationGrapheme) -> UTF-16 location \(originalLocationUTF16)", category: Logger.ui)

        // Step 1: Get the line number for the error position (using UTF-16 index)
        guard let lineNumber = getLineForIndex(originalLocationUTF16, in: element) else {
            Logger.debug("LineIndexStrategy: AXLineForIndex failed for index \(originalLocationUTF16)")
            return nil
        }

        Logger.debug("LineIndexStrategy: Error at UTF-16 index \(originalLocationUTF16) is on line \(lineNumber)", category: Logger.ui)

        // Step 2: Get the character range for this line
        guard let lineRange = getRangeForLine(lineNumber, in: element) else {
            Logger.debug("LineIndexStrategy: AXRangeForLine failed for line \(lineNumber)")
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
                Logger.debug("LineIndexStrategy: Both AXBoundsForRange and estimation failed for line \(lineNumber)")
                return nil
            }
            lineBounds = estimatedBounds
            usingEstimatedBounds = true
            Logger.debug("LineIndexStrategy: Estimated line bounds (Quartz): \(lineBounds)", category: Logger.ui)
        }

        // Validate line bounds
        guard lineBounds.width > 0 && lineBounds.height > 0 && lineBounds.height < 200 else {
            Logger.debug("LineIndexStrategy: Invalid line bounds: \(lineBounds)")
            return nil
        }

        // Step 4: Calculate X offset within the line
        // All values here are in UTF-16 code units for consistency with accessibility APIs
        let lineStartUTF16 = lineRange.location
        let lineEndUTF16 = lineRange.location + lineRange.length
        let offsetInLineUTF16 = originalLocationUTF16 - lineStartUTF16

        // Convert UTF-16 indices to String.Index for correct text extraction
        guard let lineStartIdx = stringIndex(forUTF16Offset: lineStartUTF16, in: text),
              let lineEndIdx = stringIndex(forUTF16Offset: lineEndUTF16, in: text),
              lineStartIdx <= lineEndIdx else {
            Logger.debug("LineIndexStrategy: Failed to convert UTF-16 indices to string indices")
            return nil
        }
        let lineText = String(text[lineStartIdx..<lineEndIdx])

        // Get text before error within the line
        // offsetInLineUTF16 is the UTF-16 offset within the line, need to convert to grapheme count
        let textBeforeErrorInLine: String
        if offsetInLineUTF16 > 0 {
            // Convert the error position to a string index within the line text
            if let errorPosInLine = stringIndex(forUTF16Offset: offsetInLineUTF16, in: lineText) {
                textBeforeErrorInLine = String(lineText[..<errorPosInLine])
            } else {
                textBeforeErrorInLine = ""
            }
        } else {
            textBeforeErrorInLine = ""
        }

        // Get error text (using UTF-16 coordinates)
        let errorEndUTF16 = originalLocationUTF16 + errorLengthUTF16
        let errorText: String
        if let errorStartIdx = stringIndex(forUTF16Offset: originalLocationUTF16, in: text),
           let errorEndIdx = stringIndex(forUTF16Offset: errorEndUTF16, in: text),
           errorStartIdx <= errorEndIdx {
            errorText = String(text[errorStartIdx..<errorEndIdx])
        } else {
            Logger.debug("LineIndexStrategy: String index out of bounds for error text")
            return nil
        }

        Logger.debug("LineIndexStrategy: textBeforeErrorInLine='\(textBeforeErrorInLine)', errorText='\(errorText)'", category: Logger.ui)

        // Calculate widths using font measurement
        // Try to detect the actual font from the element for accurate measurement
        let font = detectFont(from: element, parser: parser)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let textBeforeWidth = (textBeforeErrorInLine as NSString).size(withAttributes: attributes).width
        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 20.0)

        Logger.debug("LineIndexStrategy: textBeforeWidth=\(textBeforeWidth), errorWidth=\(errorWidth)", category: Logger.ui)

        // Step 5: Calculate final bounds
        let errorX = lineBounds.origin.x + textBeforeWidth
        let errorY = lineBounds.origin.y
        let errorHeight = lineBounds.height

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
            Logger.debug("LineIndexStrategy: Final bounds validation failed: \(cocoaBounds)")
            return nil
        }

        Logger.debug("LineIndexStrategy: SUCCESS - bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: usingEstimatedBounds ? 0.75 : 0.90,
            strategy: strategyName,
            metadata: [
                "api": usingEstimatedBounds ? "line-index-estimated" : "line-index",
                "line_number": lineNumber,
                "line_range": "\(lineRange)",
                "offset_in_line_utf16": offsetInLineUTF16,
                "using_estimated_bounds": usingEstimatedBounds
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
        let result = AXUIElementCopyParameterizedAttributeValue(
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
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXRangeForLine" as CFString,
            lineRef,
            &rangeValue
        )

        guard result == .success, let rv = rangeValue else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rv as! AXValue, .cfRange, &range) else {
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

        return bounds
    }

    // MARK: - Font Detection

    /// Detect the font being used in the element for accurate text measurement
    private func detectFont(from element: AXUIElement, parser: ContentParser) -> NSFont {
        // Try to get font info from attributed string at position 0
        if let font = getAttributedStringFontInfo(from: element, at: 0) {
            Logger.debug("LineIndexStrategy: Detected font '\(font.fontName)' size \(font.pointSize)", category: Logger.ui)
            return font
        }

        // Fallback to parser's estimated font size with system font
        let context = parser.detectUIContext(element: element)
        let fontSize = parser.estimatedFontSize(context: context)

        Logger.debug("LineIndexStrategy: Using fallback system font size \(fontSize)", category: Logger.ui)
        return NSFont.systemFont(ofSize: fontSize)
    }

    /// Get font info from attributed string at a specific position
    private func getAttributedStringFontInfo(from element: AXUIElement, at position: Int) -> NSFont? {
        // Try AXAttributedStringForRange with a small range at the given position
        var cfRange = CFRange(location: position, length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var attrStringValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForRange" as CFString,
            rangeValue,
            &attrStringValue
        )

        guard result == .success,
              let attrString = attrStringValue as? NSAttributedString,
              attrString.length > 0 else {
            return nil
        }

        // Extract font from attributes
        let attrs = attrString.attributes(at: 0, effectiveRange: nil)
        if let font = attrs[.font] as? NSFont {
            return font
        }

        // Try looking for AXFont key in attributed string
        if let fontDict = attrs[NSAttributedString.Key(rawValue: "AXFont")] as? [String: Any] {
            if let fontName = fontDict["AXFontName"] as? String,
               let fontSize = fontDict["AXFontSize"] as? CGFloat {
                if let font = NSFont(name: fontName, size: fontSize) {
                    return font
                }
            }
        }

        return nil
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
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            Logger.debug("LineIndexStrategy: Failed to get element position/size for estimation")
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        // Get font info for line height calculation
        let font = detectFont(from: element, parser: parser)
        let lineHeight = font.pointSize * 1.3  // Approximate line height (font size * 1.3)

        // Calculate Y position for this line
        // In Quartz coordinates, Y increases downward from top-left
        // Line 0 is at the top of the element
        let lineY = position.y + (CGFloat(lineNumber) * lineHeight) + 4  // 4pt top padding estimate

        // Use element X for line start and full width
        let lineX = position.x
        let lineWidth = size.width

        Logger.debug("LineIndexStrategy: Estimated line \(lineNumber) at Y=\(lineY), lineHeight=\(lineHeight)")

        return CGRect(
            x: lineX,
            y: lineY,
            width: lineWidth,
            height: lineHeight
        )
    }

    // MARK: - UTF-16 Index Conversion

    /// Convert a grapheme cluster index to UTF-16 code unit offset.
    /// Harper provides error positions in grapheme clusters, but macOS accessibility APIs
    /// (AXLineForIndex, AXRangeForLine, AXBoundsForRange) use UTF-16 code units.
    /// This matters for text with emojis: 😉 = 1 grapheme but 2 UTF-16 code units.
    private func graphemeToUTF16(_ graphemeIndex: Int, in string: String) -> Int {
        let safeIndex = min(graphemeIndex, string.count)
        guard let stringIndex = string.index(string.startIndex, offsetBy: safeIndex, limitedBy: string.endIndex) else {
            return graphemeIndex  // Fallback to original if conversion fails
        }
        let prefix = String(string[..<stringIndex])
        return (prefix as NSString).length
    }

    /// Convert a UTF-16 code unit offset to a String.Index (grapheme cluster based)
    /// macOS accessibility APIs use UTF-16 indices, but Swift String uses grapheme clusters
    /// This is necessary for correct string slicing when text contains emojis or other
    /// multi-codepoint characters (e.g., 😉 = 1 grapheme but 2 UTF-16 code units)
    private func stringIndex(forUTF16Offset utf16Offset: Int, in string: String) -> String.Index? {
        guard utf16Offset >= 0 else { return nil }

        let nsString = string as NSString
        guard utf16Offset <= nsString.length else { return nil }

        // NSString range with length 0 at the UTF-16 offset
        let utf16Range = NSRange(location: utf16Offset, length: 0)

        // Convert to Range<String.Index>
        guard let range = Range(utf16Range, in: string) else { return nil }

        return range.lowerBound
    }
}
