//
//  AnchorSearchStrategy.swift
//  TextWarden
//
//  Anchor-based positioning strategy
//  Finds a valid reference point by probing individual characters,
//  then calculates error position relative to that reference.
//

import Foundation
import AppKit
import ApplicationServices

/// Anchor search strategy
/// Probes characters near the error to find one with valid bounds,
/// then calculates the error position relative to that anchor.
class AnchorSearchStrategy: GeometryProvider {

    var strategyName: String { "AnchorSearch" }
    var strategyType: StrategyType { .anchorSearch }
    var tier: StrategyTier { .reliable }
    var tierPriority: Int { 30 }

    // Maximum distance to probe from error position
    private let maxProbeDistance = 50

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Universal strategy
        return true
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("AnchorSearchStrategy: Starting for range \(errorRange)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates (still in grapheme clusters)
        let textOffset = parser.textReplacementOffset
        let originalLocationGrapheme = errorRange.location + textOffset

        // Convert grapheme cluster index to UTF-16 code units for accessibility API
        // macOS AXBoundsForRange uses UTF-16 indices, not grapheme clusters
        let originalLocationUTF16 = graphemeToUTF16(originalLocationGrapheme, in: text)
        let textLengthUTF16 = (text as NSString).length

        Logger.debug("AnchorSearchStrategy: Grapheme location \(originalLocationGrapheme) -> UTF-16 location \(originalLocationUTF16)", category: Logger.ui)

        // Step 1: Probe to find a character with valid bounds near the error (using UTF-16 indices)
        guard let anchor = findValidAnchor(near: originalLocationUTF16, in: element, textLength: textLengthUTF16) else {
            Logger.debug("AnchorSearchStrategy: Could not find valid anchor", category: Logger.accessibility)
            return nil
        }

        Logger.debug("AnchorSearchStrategy: Found anchor at UTF-16 index \(anchor.index) with bounds \(anchor.bounds)", category: Logger.ui)

        // Step 2: Calculate offset from anchor to error (using UTF-16 coordinates)
        let offsetUTF16 = originalLocationUTF16 - anchor.index

        Logger.debug("AnchorSearchStrategy: UTF-16 offset from anchor: \(offsetUTF16)", category: Logger.ui)

        // Step 3: Measure text between anchor and error
        let context = parser.detectUIContext(element: element)
        let fontSize = parser.estimatedFontSize(context: context)
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Get text from anchor to error (or error to anchor if error is before)
        // Convert UTF-16 indices back to String indices for proper text extraction
        let nsText = text as NSString
        let textBetween: String
        if offsetUTF16 >= 0 {
            // Anchor is before error - get text from anchor to error
            let startUTF16 = anchor.index
            let endUTF16 = min(originalLocationUTF16, textLengthUTF16)
            guard startUTF16 <= endUTF16, endUTF16 <= textLengthUTF16 else {
                Logger.debug("AnchorSearchStrategy: UTF-16 range out of bounds (positive offset)", category: Logger.accessibility)
                return nil
            }
            textBetween = nsText.substring(with: NSRange(location: startUTF16, length: endUTF16 - startUTF16))
        } else {
            // Anchor is after error - get text from error to anchor
            let startUTF16 = originalLocationUTF16
            let endUTF16 = min(anchor.index, textLengthUTF16)
            guard startUTF16 <= endUTF16, endUTF16 <= textLengthUTF16 else {
                Logger.debug("AnchorSearchStrategy: UTF-16 range out of bounds (negative offset)", category: Logger.accessibility)
                return nil
            }
            textBetween = nsText.substring(with: NSRange(location: startUTF16, length: endUTF16 - startUTF16))
        }

        let textBetweenWidth = (textBetween as NSString).size(withAttributes: attributes).width

        // Get error text (using UTF-16 coordinates)
        let errorLengthUTF16 = graphemeToUTF16(originalLocationGrapheme + errorRange.length, in: text) - originalLocationUTF16
        let errorEndUTF16 = min(originalLocationUTF16 + errorLengthUTF16, textLengthUTF16)
        guard originalLocationUTF16 <= errorEndUTF16, errorEndUTF16 <= textLengthUTF16 else {
            Logger.debug("AnchorSearchStrategy: UTF-16 range out of bounds for error text", category: Logger.accessibility)
            return nil
        }
        let errorText = nsText.substring(with: NSRange(location: originalLocationUTF16, length: errorEndUTF16 - originalLocationUTF16))
        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 20.0)

        Logger.debug("AnchorSearchStrategy: textBetweenWidth=\(textBetweenWidth), errorWidth=\(errorWidth)", category: Logger.ui)

        // Step 4: Calculate error position from anchor
        var errorX: CGFloat
        if offsetUTF16 >= 0 {
            errorX = anchor.bounds.origin.x + textBetweenWidth
        } else {
            errorX = anchor.bounds.origin.x - textBetweenWidth
        }

        // Check if we're on the same line by looking at newlines in textBetween
        let newlineCount = textBetween.filter { $0 == "\n" }.count

        // Estimate Y position
        var errorY = anchor.bounds.origin.y
        if newlineCount > 0 {
            let lineHeight = anchor.bounds.height * 1.2
            if offsetUTF16 >= 0 {
                errorY = anchor.bounds.origin.y + (CGFloat(newlineCount) * lineHeight)
            } else {
                errorY = anchor.bounds.origin.y - (CGFloat(newlineCount) * lineHeight)
            }
            let textAfterLastNewline = textBetween.components(separatedBy: "\n").last ?? ""
            let textAfterWidth = (textAfterLastNewline as NSString).size(withAttributes: attributes).width
            if let elementFrame = AccessibilityBridge.getElementFrame(element) {
                errorX = elementFrame.origin.x + textAfterWidth
            }
        }

        let quartzBounds = CGRect(
            x: errorX,
            y: errorY,
            width: errorWidth,
            height: anchor.bounds.height
        )

        Logger.debug("AnchorSearchStrategy: Quartz bounds: \(quartzBounds)", category: Logger.ui)

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        Logger.debug("AnchorSearchStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        // Validate
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("AnchorSearchStrategy: Final bounds validation failed", category: Logger.accessibility)
            return nil
        }

        // Confidence depends on distance from anchor and whether same line
        let confidence: Double
        if newlineCount == 0 && abs(offsetUTF16) < 20 {
            confidence = GeometryConstants.goodConfidence
        } else if newlineCount == 0 {
            confidence = GeometryConstants.mediumConfidence
        } else {
            confidence = GeometryConstants.lowConfidence
        }

        Logger.debug("AnchorSearchStrategy: SUCCESS - bounds: \(cocoaBounds), confidence: \(confidence)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: confidence,
            strategy: strategyName,
            metadata: [
                "api": "anchor-search",
                "anchor_index": anchor.index,
                "offset_utf16": offsetUTF16,
                "newlines_crossed": newlineCount
            ]
        )
    }

    // MARK: - Anchor Finding

    private struct Anchor {
        let index: Int
        let bounds: CGRect
    }

    private func findValidAnchor(near targetIndex: Int, in element: AXUIElement, textLength: Int) -> Anchor? {
        var offsets: [Int] = [0]
        for i in 1...maxProbeDistance {
            offsets.append(i)
            offsets.append(-i)
        }

        for offset in offsets {
            let probeIndex = targetIndex + offset
            guard probeIndex >= 0 && probeIndex < textLength else { continue }

            if let bounds = getBoundsForSingleChar(at: probeIndex, in: element) {
                if bounds.width > 0 && bounds.height > 0 && bounds.height < GeometryConstants.maximumLineHeight && bounds.width < GeometryConstants.maximumCharacterWidth {
                    return Anchor(index: probeIndex, bounds: bounds)
                }
            }
        }

        return nil
    }

    private func getBoundsForSingleChar(at index: Int, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: index, length: 1)
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

        guard result == .success,
              let bv = boundsValue,
              let bounds = safeAXValueGetRect(bv) else {
            return nil
        }

        return bounds
    }

    // MARK: - UTF-16 Index Conversion

    /// Convert a grapheme cluster index to UTF-16 code unit offset.
    /// Harper provides error positions in grapheme clusters, but macOS accessibility APIs
    /// (AXBoundsForRange) use UTF-16 code units.
    /// This matters for text with emojis: 😊 = 1 grapheme but 2 UTF-16 code units.
    private func graphemeToUTF16(_ graphemeIndex: Int, in string: String) -> Int {
        let safeIndex = min(graphemeIndex, string.count)
        guard let stringIndex = string.index(string.startIndex, offsetBy: safeIndex, limitedBy: string.endIndex) else {
            return graphemeIndex  // Fallback to original if conversion fails
        }
        let prefix = String(string[..<stringIndex])
        return (prefix as NSString).length
    }
}
