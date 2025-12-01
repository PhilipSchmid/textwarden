//
//  ElementTreeStrategy.swift
//  TextWarden
//
//  Element tree traversal positioning strategy
//  Traverses AX hierarchy to find child elements containing error text.
//  Used for Notion and other apps where paragraph bounds are unreliable.
//

import Foundation
import AppKit
import ApplicationServices

// MARK: - Element Scoring

/// Scoring criteria for selecting the best element
struct ElementScore {
    var sizeScore: Int      // Based on reasonable text height
    var roleScore: Int      // Prefer AXStaticText
    var widthScore: Int     // Prefer reasonable widths

    var total: Int { sizeScore + roleScore + widthScore }

    static func calculate(height: CGFloat, width: CGFloat, role: String) -> ElementScore {
        var score = ElementScore(sizeScore: 0, roleScore: 0, widthScore: 0)

        // Height scoring: prefer elements with typical text line height (15-50px)
        if height > 0 && height < 50 {
            score.sizeScore = 100
        } else if height >= 50 && height < 100 {
            score.sizeScore = 50
        } else if height >= 100 && height < 200 {
            score.sizeScore = 10
        }
        // Height >= 200 gets 0 (container elements)

        // Width scoring
        if width > 20 && width < 800 {
            score.widthScore = 20
        }

        // Role scoring
        switch role {
        case "AXStaticText":
            score.roleScore = 50
        case "AXTextField", "AXTextArea":
            score.roleScore = 30
        default:
            score.roleScore = 0
        }

        return score
    }

    static let minimumAcceptable = 50
}

/// Element tree traversal strategy for element-based positioning
/// Traverses AX hierarchy to find AXStaticText children containing the error text
class ElementTreeStrategy: GeometryProvider {

    var strategyName: String { "ElementTree" }
    var tier: StrategyTier { .reliable }
    var tierPriority: Int { 5 }

    // Maximum depth for recursive traversal
    private let maxTraversalDepth = 10

    // Maximum number of children to process
    private let maxChildrenToProcess = 100

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Designed for Chromium-based apps where other strategies fail
        let targetApps: Set<String> = [
            "notion.id",
            "com.notion.id",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "org.chromium.Chromium"
        ]
        return targetApps.contains(bundleID)
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("ElementTreeStrategy: Starting for range \(errorRange)", category: Logger.ui)

        // Convert filtered coordinates to original coordinates
        let offset = parser.textReplacementOffset
        let originalStart = errorRange.location + offset
        let originalEnd = originalStart + errorRange.length

        Logger.debug("ElementTreeStrategy: Applying offset \(offset): filtered \(errorRange.location) -> original \(originalStart)", category: Logger.ui)

        // Extract the error text using original coordinates
        let errorStart = min(originalStart, text.count)
        let errorEnd = min(originalEnd, text.count)

        guard errorStart < errorEnd else {
            Logger.debug("ElementTreeStrategy: Invalid range after offset adjustment")
            return nil
        }

        // Safe string slicing to handle UTF-16/character count mismatches
        guard let startIndex = text.index(text.startIndex, offsetBy: errorStart, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: errorEnd, limitedBy: text.endIndex),
              startIndex <= endIndex else {
            Logger.debug("ElementTreeStrategy: String index out of bounds for error text")
            return nil
        }
        let errorText = String(text[startIndex..<endIndex])

        Logger.debug("ElementTreeStrategy: Looking for error text: '\(errorText)'", category: Logger.ui)

        // Find the best child element containing the error text
        guard let targetElement = findBestElementContainingText(
            errorText,
            in: element
        ) else {
            Logger.debug("ElementTreeStrategy: Could not find element containing error text")
            return nil
        }

        // Get the element's frame and role
        guard let elementFrame = getElementFrame(targetElement) else {
            Logger.debug("ElementTreeStrategy: Could not get element frame")
            return nil
        }

        let role = getElementRole(targetElement)
        Logger.debug("ElementTreeStrategy: Found \(role) with frame \(elementFrame)", category: Logger.ui)

        // Get the element's text
        let elementText = getElementText(targetElement) ?? ""

        Logger.debug("ElementTreeStrategy: Element text: '\(elementText.prefix(50))'", category: Logger.ui)

        // Calculate position within the element's text
        guard let range = elementText.range(of: errorText) else {
            Logger.debug("ElementTreeStrategy: Error text not found in element text")
            return createResultFromFrame(elementFrame, errorText: errorText, parser: parser)
        }

        let offsetInElement = elementText.distance(from: elementText.startIndex, to: range.lowerBound)
        let textBeforeError = String(elementText.prefix(offsetInElement))

        Logger.debug("ElementTreeStrategy: Error at offset \(offsetInElement) in element", category: Logger.ui)

        // Try AXBoundsForRange on the child element itself
        let childErrorRange = NSRange(location: offsetInElement, length: errorText.count)
        if let childBounds = getBoundsForRange(childErrorRange, in: targetElement) {
            Logger.debug("ElementTreeStrategy: Got bounds from child element's AXBoundsForRange: \(childBounds)", category: Logger.ui)

            let cocoaBounds = CoordinateMapper.toCocoaCoordinates(childBounds)
            if CoordinateMapper.validateBounds(cocoaBounds) {
                // Check for multi-line: If bounds height suggests multiple lines, try to get per-line bounds
                let multiLineResult = resolveMultiLineBoundsForChild(
                    childErrorRange,
                    in: targetElement,
                    overallBounds: childBounds
                )

                if let lineBounds = multiLineResult, lineBounds.count > 1 {
                    // Convert all line bounds to Cocoa coordinates
                    let cocoaLineBounds = lineBounds.map { CoordinateMapper.toCocoaCoordinates($0) }
                    let validLineBounds = cocoaLineBounds.filter { CoordinateMapper.validateBounds($0) }

                    if validLineBounds.count > 1 {
                        Logger.debug("ElementTreeStrategy: SUCCESS multi-line with \(validLineBounds.count) lines: \(cocoaBounds)", category: Logger.ui)
                        return GeometryResult(
                            bounds: cocoaBounds,
                            lineBounds: validLineBounds,
                            confidence: 0.95,
                            strategy: strategyName,
                            metadata: [
                                "api": "element-tree-range-bounds-multiline",
                                "element_role": role,
                                "child_range": "\(childErrorRange)",
                                "line_count": validLineBounds.count
                            ]
                        )
                    }
                }

                Logger.debug("ElementTreeStrategy: SUCCESS using child AXBoundsForRange: \(cocoaBounds)", category: Logger.ui)
                return GeometryResult(
                    bounds: cocoaBounds,
                    confidence: 0.95,
                    strategy: strategyName,
                    metadata: [
                        "api": "element-tree-range-bounds",
                        "element_role": role,
                        "child_range": "\(childErrorRange)"
                    ]
                )
            }
        }

        // Fallback: Estimate position using text measurement
        let fontSize = estimateFontSizeFromElement(frame: elementFrame, text: elementText)
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        Logger.debug("ElementTreeStrategy: Estimated font size \(fontSize)pt for element height \(elementFrame.height)", category: Logger.ui)

        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 20.0)

        // Handle multi-line elements
        let lineHeight: CGFloat = fontSize * 1.4
        let isMultiLine = elementFrame.height > lineHeight * 1.5

        var errorX: CGFloat = elementFrame.origin.x
        var errorY: CGFloat = elementFrame.origin.y
        let errorHeight: CGFloat = min(elementFrame.height, lineHeight)

        if isMultiLine {
            let elementWidth = elementFrame.width

            var currentX: CGFloat = 0
            var currentLine: Int = 0
            let charsBeforeError = textBeforeError.count

            let words = elementText.components(separatedBy: " ")
            var charIndex = 0

            for word in words {
                let wordWidth = (word as NSString).size(withAttributes: attributes).width
                let spaceWidth: CGFloat = 5.0

                if currentX + wordWidth > elementWidth && currentX > 0 {
                    currentLine += 1
                    currentX = 0
                }

                let wordEnd = charIndex + word.count
                if charIndex <= charsBeforeError && wordEnd >= charsBeforeError {
                    let offsetInWord = max(0, charsBeforeError - charIndex)
                    let textInWordBeforeError = String(word.prefix(offsetInWord))
                    errorX = elementFrame.origin.x + currentX + (textInWordBeforeError as NSString).size(withAttributes: attributes).width
                    errorY = elementFrame.origin.y + (CGFloat(currentLine) * lineHeight)

                    Logger.debug("ElementTreeStrategy: Multi-line - line \(currentLine), X=\(errorX), Y=\(errorY)", category: Logger.ui)
                    break
                }

                currentX += wordWidth + spaceWidth
                charIndex += word.count + 1
            }

            if errorX == 0 {
                let textBeforeWidth = (textBeforeError as NSString).size(withAttributes: attributes).width
                errorX = elementFrame.origin.x + textBeforeWidth.truncatingRemainder(dividingBy: elementWidth)
                let estimatedLine = Int(textBeforeWidth / elementWidth)
                errorY = elementFrame.origin.y + (CGFloat(estimatedLine) * lineHeight)
            }
        } else {
            let textBeforeWidth = (textBeforeError as NSString).size(withAttributes: attributes).width
            errorX = elementFrame.origin.x + textBeforeWidth
            errorY = elementFrame.origin.y
        }

        let quartzBounds = CGRect(
            x: errorX,
            y: errorY,
            width: errorWidth,
            height: errorHeight
        )

        Logger.debug("ElementTreeStrategy: Quartz bounds: \(quartzBounds)", category: Logger.ui)

        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        Logger.debug("ElementTreeStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        guard cocoaBounds.width > 0 && cocoaBounds.height > 0 else {
            Logger.debug("ElementTreeStrategy: Invalid bounds dimensions")
            return nil
        }

        Logger.debug("ElementTreeStrategy: SUCCESS with bounds: \(cocoaBounds)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.88,
            strategy: strategyName,
            metadata: [
                "api": "element-tree-statictext",
                "element_role": role,
                "element_frame": NSStringFromRect(elementFrame),
                "text_offset": offsetInElement
            ]
        )
    }

    // MARK: - Element Traversal

    private func findBestElementContainingText(
        _ targetText: String,
        in element: AXUIElement
    ) -> AXUIElement? {

        var candidates: [(element: AXUIElement, score: ElementScore, frame: CGRect)] = []
        collectCandidates(targetText, in: element, depth: 0, candidates: &candidates)

        Logger.debug("ElementTreeStrategy: Found \(candidates.count) candidates", category: Logger.ui)

        // Sort by total score (higher is better)
        candidates.sort { $0.score.total > $1.score.total }

        if let best = candidates.first, best.score.total >= ElementScore.minimumAcceptable {
            let role = getElementRole(best.element)
            Logger.debug("ElementTreeStrategy: Best candidate is \(role) with score \(best.score.total), frame \(best.frame)", category: Logger.ui)
            return best.element
        }

        if let best = candidates.first {
            Logger.debug("ElementTreeStrategy: Best candidate score \(best.score.total) below minimum \(ElementScore.minimumAcceptable) - rejecting", category: Logger.ui)
        }

        return nil
    }

    private func collectCandidates(
        _ targetText: String,
        in element: AXUIElement,
        depth: Int,
        candidates: inout [(element: AXUIElement, score: ElementScore, frame: CGRect)]
    ) {
        guard depth < maxTraversalDepth else { return }

        let role = getElementRole(element)
        let frame = getElementFrame(element)

        if let elementText = getElementText(element), elementText.contains(targetText) {
            if let f = frame {
                let score = ElementScore.calculate(height: f.height, width: f.width, role: role)

                if score.total > 0 {
                    candidates.append((element: element, score: score, frame: f))
                    Logger.debug("ElementTreeStrategy: Candidate \(role) score=\(score.total) frame=\(f) text='\(elementText.prefix(30))'", category: Logger.ui)
                }
            }
        }

        if let children = getChildren(element) {
            for child in children.prefix(maxChildrenToProcess) {
                collectCandidates(targetText, in: child, depth: depth + 1, candidates: &candidates)
            }
        }
    }

    // MARK: - Font Size Estimation

    private func estimateFontSizeFromElement(frame: CGRect, text: String) -> CGFloat {
        let height = frame.height
        let width = frame.width

        guard height > 0 && width > 0 else {
            return 16.0
        }

        if height < 35.0 {
            let estimatedSize = height / 1.35
            return max(12.0, min(22.0, estimatedSize))
        }

        let avgCharWidth: CGFloat = 8.0
        let expectedSingleLineWidth = CGFloat(text.count) * avgCharWidth

        if expectedSingleLineWidth < width * 0.7 && height > 35.0 && height < 55.0 {
            return 30.0
        }

        let titleLineHeight: CGFloat = 42.0
        let bodyLineHeight: CGFloat = 22.0

        let titleLines = round(height / titleLineHeight)
        let bodyLines = round(height / bodyLineHeight)

        if titleLines >= 1 && titleLines <= 3 {
            let titleRemainder = abs(height - (titleLines * titleLineHeight))
            let bodyRemainder = abs(height - (bodyLines * bodyLineHeight))

            if titleRemainder < bodyRemainder && titleRemainder < 15.0 {
                Logger.debug("ElementTreeStrategy: Detected title element (height=\(height), ~\(Int(titleLines)) lines)", category: Logger.ui)
                return 30.0
            }
        }

        return 16.0
    }

    // MARK: - AX Helpers

    private func getElementRole(_ element: AXUIElement) -> String {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
           let role = value as? String {
            return role
        }
        return "unknown"
    }

    private func getElementText(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?

        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }

        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }

        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }

        return nil
    }

    private func getChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        )

        guard result == .success,
              let children = value as? [AXUIElement] else {
            return nil
        }

        return children
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

        guard bounds.width > 0 && bounds.height > 0 && bounds.height < 200 else {
            return nil
        }

        return bounds
    }

    private func createResultFromFrame(_ frame: CGRect, errorText: String, parser: ContentParser? = nil) -> GeometryResult? {
        let fontSize: CGFloat = parser?.estimatedFontSize(context: nil) ?? 14.0
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 20.0)

        let quartzBounds = CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: min(errorWidth, frame.width),
            height: frame.height
        )

        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        guard cocoaBounds.width > 0 && cocoaBounds.height > 0 else {
            return nil
        }

        Logger.debug("ElementTreeStrategy: Fallback with element frame: \(cocoaBounds)")

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.70,
            strategy: strategyName,
            metadata: [
                "api": "element-tree-frame-fallback",
                "element_frame": NSStringFromRect(frame)
            ]
        )
    }

    // MARK: - Multi-Line Resolution

    /// Resolve per-line bounds for a child element's text range
    /// Specifically designed for Electron/Chromium apps where parent element AX APIs fail
    /// but child element AXBoundsForRange works
    private func resolveMultiLineBoundsForChild(
        _ range: NSRange,
        in element: AXUIElement,
        overallBounds: CGRect
    ) -> [CGRect]? {
        // Get typical line height from a single character
        var typicalLineHeight: CGFloat = 20.0
        let singleCharRange = NSRange(location: range.location, length: 1)
        if let charBounds = getBoundsForRange(singleCharRange, in: element) {
            typicalLineHeight = max(charBounds.height, 12.0)
        }

        // Check if bounds height suggests multi-line
        let estimatedLineCount = Int(ceil(overallBounds.height / typicalLineHeight))
        let likelyMultiLine = overallBounds.height > typicalLineHeight * 1.5

        Logger.debug("ElementTreeStrategy: Multi-line check - height: \(overallBounds.height), lineHeight: \(typicalLineHeight), estimatedLines: \(estimatedLineCount), likely: \(likelyMultiLine)")

        guard likelyMultiLine && estimatedLineCount > 1 else {
            return nil // Single line, no need for multi-line bounds
        }

        // Method 1: Sample Y-coordinates to detect line breaks
        var lineBounds: [CGRect] = []
        var lineBreakIndices: [Int] = [range.location]
        var lastY: CGFloat?

        // Sample every ~5 characters to find line breaks
        let sampleStep = max(1, min(5, range.length / (estimatedLineCount * 3)))
        var sampleIndex = range.location

        while sampleIndex < range.location + range.length {
            let charRange = NSRange(location: sampleIndex, length: 1)
            if let charBounds = getBoundsForRange(charRange, in: element) {
                if let prevY = lastY {
                    let yDiff = abs(charBounds.origin.y - prevY)
                    if yDiff > charBounds.height * 0.5 {
                        // Line break detected
                        lineBreakIndices.append(sampleIndex)
                        Logger.debug("ElementTreeStrategy: Line break at index \(sampleIndex), Y jumped from \(prevY) to \(charBounds.origin.y)")
                    }
                }
                lastY = charBounds.origin.y
            }
            sampleIndex += sampleStep
        }

        lineBreakIndices.append(range.location + range.length)

        // Convert line break indices to bounds
        // We need to get bounds for just the FIRST character of each line to get correct Y position
        // Then construct proper per-line bounds
        var lineYPositions: [CGFloat] = []
        for i in 0..<(lineBreakIndices.count - 1) {
            let lineStart = lineBreakIndices[i]
            // Get bounds for just the first character to get the correct Y position
            let firstCharRange = NSRange(location: lineStart, length: 1)
            if let firstCharBounds = getBoundsForRange(firstCharRange, in: element) {
                lineYPositions.append(firstCharBounds.origin.y)
                Logger.debug("ElementTreeStrategy: Line \(i) starts at Y=\(firstCharBounds.origin.y)")
            }
        }

        // If we found line Y positions, construct geometric bounds for each line
        if lineYPositions.count > 1 {
            Logger.debug("ElementTreeStrategy: Found \(lineYPositions.count) lines via Y-sampling, constructing geometric bounds")

            // Get the left margin X from the first line (line 0)
            // All continuation lines should start at this left margin
            var leftMarginX = overallBounds.origin.x
            let firstLineCharRange = NSRange(location: lineBreakIndices[0], length: 1)
            if let firstLineCharBounds = getBoundsForRange(firstLineCharRange, in: element) {
                leftMarginX = firstLineCharBounds.origin.x
            }

            for i in 0..<lineYPositions.count {
                let lineY = lineYPositions[i]
                let lineStart = lineBreakIndices[i]
                let lineEnd = lineBreakIndices[i + 1]

                let isFirstLine = i == 0
                let isLastLine = i == lineYPositions.count - 1

                // X position logic:
                // - First line: Use actual X of first character (error might not start at left margin)
                // - Middle/last lines: Use left margin X (text wraps to left edge)
                var lineX: CGFloat
                if isFirstLine {
                    let firstCharRange = NSRange(location: lineStart, length: 1)
                    if let firstCharBounds = getBoundsForRange(firstCharRange, in: element) {
                        lineX = firstCharBounds.origin.x
                    } else {
                        lineX = leftMarginX
                    }
                } else {
                    // Continuation lines start at left margin
                    lineX = leftMarginX
                }

                // Width logic:
                // - Last line: Get actual width from bounds
                // - Other lines: Extend to right edge of overall bounds
                var lineWidth: CGFloat
                if isLastLine {
                    // Calculate actual width by getting bounds for last line
                    let lastLineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                    if let lastLineBounds = getBoundsForRange(lastLineRange, in: element) {
                        lineWidth = lastLineBounds.width
                    } else {
                        lineWidth = overallBounds.width * 0.5
                    }
                } else {
                    // Extend to right edge
                    lineWidth = overallBounds.maxX - lineX
                }

                let lineRect = CGRect(
                    x: lineX,
                    y: lineY,
                    width: lineWidth,
                    height: typicalLineHeight
                )
                lineBounds.append(lineRect)
                Logger.debug("ElementTreeStrategy: Constructed line \(i) bounds: \(lineRect) (isFirst=\(isFirstLine), isLast=\(isLastLine))")
            }

            return lineBounds
        }

        // Method 2: Geometric fallback - split overall bounds into estimated line segments
        Logger.debug("ElementTreeStrategy: Using geometric fallback to split into \(estimatedLineCount) lines")
        lineBounds = []

        for lineIndex in 0..<estimatedLineCount {
            let lineY = overallBounds.origin.y + (CGFloat(lineIndex) * typicalLineHeight)

            let lineRect: CGRect
            if lineIndex == 0 {
                // First line - use original X position
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: overallBounds.width,
                    height: typicalLineHeight
                )
            } else if lineIndex == estimatedLineCount - 1 {
                // Last line - may not span full width
                let lastLineWidth = min(overallBounds.width, overallBounds.width * 0.7)
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: lastLineWidth,
                    height: typicalLineHeight
                )
            } else {
                // Middle lines - span full width
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: overallBounds.width,
                    height: typicalLineHeight
                )
            }

            lineBounds.append(lineRect)
            Logger.debug("ElementTreeStrategy: Geometric line \(lineIndex): \(lineRect)")
        }

        return lineBounds.isEmpty ? nil : lineBounds
    }
}
