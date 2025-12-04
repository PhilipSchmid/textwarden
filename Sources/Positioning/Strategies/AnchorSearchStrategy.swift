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

        // Convert filtered coordinates to original coordinates
        let textOffset = parser.textReplacementOffset
        let originalLocation = errorRange.location + textOffset

        // Step 1: Probe to find a character with valid bounds near the error
        guard let anchor = findValidAnchor(near: originalLocation, in: element, textLength: text.count) else {
            Logger.debug("AnchorSearchStrategy: Could not find valid anchor")
            return nil
        }

        Logger.debug("AnchorSearchStrategy: Found anchor at index \(anchor.index) with bounds \(anchor.bounds)", category: Logger.ui)

        // Step 2: Calculate offset from anchor to error (using original coordinates)
        let offset = originalLocation - anchor.index

        Logger.debug("AnchorSearchStrategy: Offset from anchor: \(offset) characters", category: Logger.ui)

        // Step 3: Measure text between anchor and error
        let context = parser.detectUIContext(element: element)
        let fontSize = parser.estimatedFontSize(context: context)
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Get text from anchor to error (or error to anchor if error is before)
        // Use safe string indexing to handle UTF-16/character count mismatches
        let textBetween: String
        if offset >= 0 {
            guard let startIdx = text.index(text.startIndex, offsetBy: anchor.index, limitedBy: text.endIndex),
                  let endIdx = text.index(text.startIndex, offsetBy: min(originalLocation, text.count), limitedBy: text.endIndex),
                  startIdx <= endIdx else {
                Logger.debug("AnchorSearchStrategy: String index out of bounds (positive offset)")
                return nil
            }
            textBetween = String(text[startIdx..<endIdx])
        } else {
            guard let startIdx = text.index(text.startIndex, offsetBy: originalLocation, limitedBy: text.endIndex),
                  let endIdx = text.index(text.startIndex, offsetBy: min(anchor.index, text.count), limitedBy: text.endIndex),
                  startIdx <= endIdx else {
                Logger.debug("AnchorSearchStrategy: String index out of bounds (negative offset)")
                return nil
            }
            textBetween = String(text[startIdx..<endIdx])
        }

        let textBetweenWidth = (textBetween as NSString).size(withAttributes: attributes).width

        // Get error text (using original coordinates)
        // Safe string slicing to handle UTF-16/character count mismatches
        let errorEndIndex = min(originalLocation + errorRange.length, text.count)
        guard let errorStartIdx = text.index(text.startIndex, offsetBy: originalLocation, limitedBy: text.endIndex),
              let errorEndIdx = text.index(text.startIndex, offsetBy: errorEndIndex, limitedBy: text.endIndex),
              errorStartIdx <= errorEndIdx else {
            Logger.debug("AnchorSearchStrategy: String index out of bounds for error text")
            return nil
        }
        let errorText = String(text[errorStartIdx..<errorEndIdx])
        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 20.0)

        Logger.debug("AnchorSearchStrategy: textBetweenWidth=\(textBetweenWidth), errorWidth=\(errorWidth)", category: Logger.ui)

        // Step 4: Calculate error position from anchor
        var errorX: CGFloat
        if offset >= 0 {
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
            if offset >= 0 {
                errorY = anchor.bounds.origin.y + (CGFloat(newlineCount) * lineHeight)
            } else {
                errorY = anchor.bounds.origin.y - (CGFloat(newlineCount) * lineHeight)
            }
            let textAfterLastNewline = textBetween.components(separatedBy: "\n").last ?? ""
            let textAfterWidth = (textAfterLastNewline as NSString).size(withAttributes: attributes).width
            if let elementFrame = getElementFrame(element) {
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
            Logger.debug("AnchorSearchStrategy: Final bounds validation failed")
            return nil
        }

        // Confidence depends on distance from anchor and whether same line
        let confidence: Double
        if newlineCount == 0 && abs(offset) < 20 {
            confidence = 0.85
        } else if newlineCount == 0 {
            confidence = 0.75
        } else {
            confidence = 0.60
        }

        Logger.debug("AnchorSearchStrategy: SUCCESS - bounds: \(cocoaBounds), confidence: \(confidence)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: confidence,
            strategy: strategyName,
            metadata: [
                "api": "anchor-search",
                "anchor_index": anchor.index,
                "offset": offset,
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
                if bounds.width > 0 && bounds.height > 0 && bounds.height < 200 && bounds.width < 100 {
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

        guard result == .success, let bv = boundsValue else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &bounds) else {
            return nil
        }

        return bounds
    }

    private func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let positionResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )

        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard positionResult == .success,
              sizeResult == .success,
              let position = positionValue,
              let size = sizeValue else {
            return nil
        }

        var origin = CGPoint.zero
        var rectSize = CGSize.zero

        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &rectSize) else {
            return nil
        }

        return CGRect(origin: origin, size: rectSize)
    }
}
