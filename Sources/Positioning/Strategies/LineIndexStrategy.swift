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

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let originalLocation = errorRange.location + offset

        // Step 1: Get the line number for the error position
        guard let lineNumber = getLineForIndex(originalLocation, in: element) else {
            Logger.debug("LineIndexStrategy: AXLineForIndex failed for index \(errorRange.location)")
            return nil
        }

        Logger.debug("LineIndexStrategy: Error at index \(originalLocation) is on line \(lineNumber)", category: Logger.ui)

        // Step 2: Get the character range for this line
        guard let lineRange = getRangeForLine(lineNumber, in: element) else {
            Logger.debug("LineIndexStrategy: AXRangeForLine failed for line \(lineNumber)")
            return nil
        }

        Logger.debug("LineIndexStrategy: Line \(lineNumber) has range \(lineRange)", category: Logger.ui)

        // Step 3: Get bounds for the entire line
        guard let lineBounds = getBoundsForRange(lineRange, in: element) else {
            Logger.debug("LineIndexStrategy: AXBoundsForRange failed for line range \(lineRange)")
            return nil
        }

        Logger.debug("LineIndexStrategy: Line bounds (Quartz): \(lineBounds)", category: Logger.ui)

        // Validate line bounds
        guard lineBounds.width > 0 && lineBounds.height > 0 && lineBounds.height < 200 else {
            Logger.debug("LineIndexStrategy: Invalid line bounds: \(lineBounds)")
            return nil
        }

        // Step 4: Calculate X offset within the line
        let lineStartIndex = lineRange.location
        let offsetInLine = originalLocation - lineStartIndex

        // Extract line text for measurement
        // Use safe string indexing to handle UTF-16/character count mismatches
        let lineEndIndex = min(lineRange.location + lineRange.length, text.count)
        guard lineStartIndex < lineEndIndex && lineStartIndex >= 0 && lineEndIndex <= text.count else {
            Logger.debug("LineIndexStrategy: Invalid line indices (start=\(lineStartIndex), end=\(lineEndIndex), textCount=\(text.count))")
            return nil
        }

        // Safe string slicing using index(limited:) approach
        guard let startIdx = text.index(text.startIndex, offsetBy: lineStartIndex, limitedBy: text.endIndex),
              let endIdx = text.index(text.startIndex, offsetBy: lineEndIndex, limitedBy: text.endIndex),
              startIdx <= endIdx else {
            Logger.debug("LineIndexStrategy: String index out of bounds for line text")
            return nil
        }
        let lineText = String(text[startIdx..<endIdx])

        // Get text before error within the line
        let textBeforeErrorInLine: String
        if offsetInLine > 0 && offsetInLine <= lineText.count {
            textBeforeErrorInLine = String(lineText.prefix(offsetInLine))
        } else {
            textBeforeErrorInLine = ""
        }

        // Get error text (using original coordinates)
        // Safe string slicing to handle UTF-16/character count mismatches
        let errorEndIndex = min(originalLocation + errorRange.length, text.count)
        let errorText: String
        if let errorStartIdx = text.index(text.startIndex, offsetBy: originalLocation, limitedBy: text.endIndex),
           let errorEndIdx = text.index(text.startIndex, offsetBy: errorEndIndex, limitedBy: text.endIndex),
           errorStartIdx <= errorEndIdx {
            errorText = String(text[errorStartIdx..<errorEndIdx])
        } else {
            Logger.debug("LineIndexStrategy: String index out of bounds for error text")
            return nil
        }

        Logger.debug("LineIndexStrategy: textBeforeErrorInLine='\(textBeforeErrorInLine)', errorText='\(errorText)'", category: Logger.ui)

        // Calculate widths using font measurement
        let context = parser.detectUIContext(element: element)
        let fontSize = parser.estimatedFontSize(context: context)
        let font = NSFont.systemFont(ofSize: fontSize)
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
            confidence: 0.90,
            strategy: strategyName,
            metadata: [
                "api": "line-index",
                "line_number": lineNumber,
                "line_range": "\(lineRange)",
                "offset_in_line": offsetInLine
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
}
