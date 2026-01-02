//
//  ElementTreeStrategy.swift
//  TextWarden
//
//  Element tree traversal positioning strategy
//  Traverses AX hierarchy to find child elements containing error text.
//  Used for Notion and other apps where paragraph bounds are unreliable.
//

import AppKit
import ApplicationServices
import Foundation

// MARK: - Element Scoring

/// Scoring criteria for selecting the best element
struct ElementScore {
    var sizeScore: Int // Based on reasonable text height
    var roleScore: Int // Prefer AXStaticText
    var widthScore: Int // Prefer reasonable widths

    var total: Int { sizeScore + roleScore + widthScore }

    static func calculate(height: CGFloat, width: CGFloat, role: String) -> ElementScore {
        var score = ElementScore(sizeScore: 0, roleScore: 0, widthScore: 0)

        // Height scoring: prefer elements with typical text line height (15-50px)
        if height > 0, height < GeometryConstants.typicalLineHeightRange.upperBound {
            score.sizeScore = 100
        } else if height >= GeometryConstants.typicalLineHeightRange.upperBound, height < GeometryConstants.conservativeMaxLineHeight {
            score.sizeScore = 50
        } else if height >= GeometryConstants.conservativeMaxLineHeight, height < GeometryConstants.maximumLineHeight {
            score.sizeScore = 10
        }
        // Height >= maximumLineHeight gets 0 (container elements)

        // Width scoring
        if width > 20, width < GeometryConstants.maximumTextWidth {
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
    // MARK: - Properties

    var strategyName: String { "ElementTree" }
    var strategyType: StrategyType { .elementTree }
    var tier: StrategyTier { .reliable }
    var tierPriority: Int { 5 }

    // Maximum depth for recursive traversal
    private let maxTraversalDepth = 10

    // Maximum number of children to process
    private let maxChildrenToProcess = 100

    func canHandle(element _: AXUIElement, bundleID: String) -> Bool {
        // Designed for Chromium-based apps where other strategies fail
        // Note: Teams is NOT included here - its child elements have broken frame data
        // (child element frames don't match their visual position)
        let targetApps: Set<String> = [
            "notion.id",
            "com.notion.id",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "org.chromium.Chromium",
        ]
        return targetApps.contains(bundleID)
    }

    // MARK: - Geometry Calculation

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
            Logger.debug("ElementTreeStrategy: Invalid range after offset adjustment", category: Logger.accessibility)
            return nil
        }

        // Safe string slicing to handle UTF-16/character count mismatches
        guard let startIndex = text.index(text.startIndex, offsetBy: errorStart, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: errorEnd, limitedBy: text.endIndex),
              startIndex <= endIndex
        else {
            Logger.debug("ElementTreeStrategy: String index out of bounds for error text", category: Logger.accessibility)
            return nil
        }
        let errorText = String(text[startIndex ..< endIndex])

        Logger.debug("ElementTreeStrategy: Looking for error text (\(errorText.count) chars)", category: Logger.ui)

        // Find the best child element containing the error text
        guard let targetElement = findBestElementContainingText(
            errorText,
            in: element
        ) else {
            Logger.debug("ElementTreeStrategy: Could not find element containing error text", category: Logger.accessibility)
            return nil
        }

        // Get the element's frame and role
        guard let elementFrame = AccessibilityBridge.getElementFrame(targetElement) else {
            Logger.debug("ElementTreeStrategy: Could not get element frame", category: Logger.accessibility)
            return nil
        }

        let role = getElementRole(targetElement)
        Logger.debug("ElementTreeStrategy: Found \(role) with frame \(elementFrame)", category: Logger.ui)

        // Get the element's text
        let elementText = getElementText(targetElement) ?? ""

        Logger.debug("ElementTreeStrategy: Element text length: \(elementText.count) chars", category: Logger.ui)

        // Calculate position within the element's text
        guard let range = elementText.range(of: errorText) else {
            Logger.debug("ElementTreeStrategy: Error text not found in element text", category: Logger.accessibility)
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
                                "line_count": validLineBounds.count,
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
                        "child_range": "\(childErrorRange)",
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
            var currentLine = 0
            let charsBeforeError = textBeforeError.count

            let words = elementText.components(separatedBy: " ")
            var charIndex = 0

            for word in words {
                let wordWidth = (word as NSString).size(withAttributes: attributes).width
                let spaceWidth: CGFloat = 5.0

                if currentX + wordWidth > elementWidth, currentX > 0 {
                    currentLine += 1
                    currentX = 0
                }

                let wordEnd = charIndex + word.count
                if charIndex <= charsBeforeError, wordEnd >= charsBeforeError {
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

        guard cocoaBounds.width > 0, cocoaBounds.height > 0 else {
            Logger.debug("ElementTreeStrategy: Invalid bounds dimensions", category: Logger.accessibility)
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
                "text_offset": offsetInElement,
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
        let frame = AccessibilityBridge.getElementFrame(element)

        if let elementText = getElementText(element), elementText.contains(targetText) {
            if let f = frame {
                let score = ElementScore.calculate(height: f.height, width: f.width, role: role)

                if score.total > 0 {
                    candidates.append((element: element, score: score, frame: f))
                    Logger.debug("ElementTreeStrategy: Candidate \(role) score=\(score.total) frame=\(f) textLen=\(elementText.count)", category: Logger.ui)
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

        guard height > 0, width > 0 else {
            return GeometryConstants.normalLineHeight
        }

        if height < GeometryConstants.multiLineThresholdHeight {
            let estimatedSize = height / 1.35
            return max(12.0, min(22.0, estimatedSize))
        }

        let avgCharWidth: CGFloat = 8.0
        let expectedSingleLineWidth = CGFloat(text.count) * avgCharWidth

        if expectedSingleLineWidth < width * 0.7, height > GeometryConstants.multiLineThresholdHeight, height < 55.0 {
            return 30.0
        }

        let titleLineHeight: CGFloat = 42.0
        let bodyLineHeight: CGFloat = 22.0

        let titleLines = round(height / titleLineHeight)
        let bodyLines = round(height / bodyLineHeight)

        if titleLines >= 1, titleLines <= 3 {
            let titleRemainder = abs(height - (titleLines * titleLineHeight))
            let bodyRemainder = abs(height - (bodyLines * bodyLineHeight))

            if titleRemainder < bodyRemainder, titleRemainder < 15.0 {
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
           let role = value as? String
        {
            return role
        }
        return "unknown"
    }

    private func getElementText(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?

        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty
        {
            return text
        }

        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty
        {
            return text
        }

        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty
        {
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
              let children = value as? [AXUIElement]
        else {
            return nil
        }

        return children
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

        guard result == .success,
              let bv = boundsValue,
              let bounds = safeAXValueGetRect(bv)
        else {
            return nil
        }

        guard bounds.width > 0, bounds.height > 0, bounds.height < GeometryConstants.maximumLineHeight else {
            return nil
        }

        return bounds
    }

    /// Get the line number for a character index using AXLineForIndex
    private func getLineForIndex(_ index: Int, in element: AXUIElement) -> Int? {
        var lineValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXLineForIndex" as CFString,
            index as CFTypeRef,
            &lineValue
        )

        guard result == .success, let lineNum = lineValue as? Int else {
            return nil
        }

        return lineNum
    }

    /// Get the character range for a specific line number using AXRangeForLine
    private func getRangeForLine(_ lineNumber: Int, in element: AXUIElement) -> NSRange? {
        var rangeValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXRangeForLine" as CFString,
            lineNumber as CFTypeRef,
            &rangeValue
        )

        guard result == .success,
              let rv = rangeValue,
              let cfRange = safeAXValueGetRange(rv)
        else {
            return nil
        }

        return NSRange(location: cfRange.location, length: cfRange.length)
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

        guard cocoaBounds.width > 0, cocoaBounds.height > 0 else {
            return nil
        }

        Logger.debug("ElementTreeStrategy: Fallback with element frame: \(cocoaBounds)", category: Logger.accessibility)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: 0.70,
            strategy: strategyName,
            metadata: [
                "api": "element-tree-frame-fallback",
                "element_frame": NSStringFromRect(frame),
            ]
        )
    }

    // MARK: - Multi-Line Resolution

    /// Resolve per-line bounds for a child element's text range
    /// Uses AXRangeForLine API to get system-defined line ranges, then computes bounds for
    /// the intersection of our target range with each line
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

        Logger.debug("ElementTreeStrategy: Multi-line check - height: \(overallBounds.height), lineHeight: \(typicalLineHeight), estimatedLines: \(estimatedLineCount), likely: \(likelyMultiLine)", category: Logger.accessibility)

        guard likelyMultiLine, estimatedLineCount > 1 else {
            return nil // Single line, no need for multi-line bounds
        }

        // Method 0: Try AXRangeForLine API first - this is the most reliable approach
        // Get line number for start and end of our range
        if let startLine = getLineForIndex(range.location, in: element),
           let endLine = getLineForIndex(range.location + range.length - 1, in: element),
           startLine != endLine
        {
            Logger.debug("ElementTreeStrategy: Using AXRangeForLine - range spans lines \(startLine) to \(endLine)", category: Logger.accessibility)

            var lineBounds: [CGRect] = []

            for lineNum in startLine ... endLine {
                guard let fullLineRange = getRangeForLine(lineNum, in: element) else {
                    Logger.debug("ElementTreeStrategy: AXRangeForLine failed for line \(lineNum)", category: Logger.accessibility)
                    continue
                }

                // Compute intersection of our target range with this line's range
                let intersectStart = max(range.location, fullLineRange.location)
                let intersectEnd = min(range.location + range.length, fullLineRange.location + fullLineRange.length)

                guard intersectEnd > intersectStart else { continue }

                let intersectionRange = NSRange(location: intersectStart, length: intersectEnd - intersectStart)

                // Get bounds for the first and last character of this line segment
                let firstCharRange = NSRange(location: intersectStart, length: 1)
                let lastCharRange = NSRange(location: intersectEnd - 1, length: 1)

                if let firstBounds = getBoundsForRange(firstCharRange, in: element),
                   let lastBounds = getBoundsForRange(lastCharRange, in: element)
                {
                    // Construct line bounds from first to last character
                    let lineX = firstBounds.origin.x
                    let lineY = firstBounds.origin.y
                    let lineWidth = lastBounds.maxX - firstBounds.origin.x
                    let lineHeight = max(firstBounds.height, typicalLineHeight)

                    let lineRect = CGRect(x: lineX, y: lineY, width: lineWidth, height: lineHeight)
                    lineBounds.append(lineRect)
                    Logger.debug("ElementTreeStrategy: Line \(lineNum) bounds via AXRangeForLine: \(lineRect), chars \(intersectionRange.location)-\(intersectionRange.location + intersectionRange.length)", category: Logger.accessibility)
                }
            }

            if lineBounds.count > 1 {
                return lineBounds
            }
            // Fall through to other methods if AXRangeForLine didn't work well
        }

        // Method 1: Sample each character's Y coordinate to build line segments
        // This is more accurate than using break indices because we directly identify
        // which characters belong to each visual line
        var lineBounds: [CGRect] = []

        // Build a map of character index -> Y coordinate for the entire range
        // Then group consecutive characters with similar Y into lines
        var charYCoords: [(index: Int, y: CGFloat, bounds: CGRect)] = []

        // Sample every character (or with small step for very long ranges)
        let sampleStep = max(1, range.length > 500 ? 2 : 1)
        for i in stride(from: range.location, to: range.location + range.length, by: sampleStep) {
            let charRange = NSRange(location: i, length: 1)
            if let charBounds = getBoundsForRange(charRange, in: element) {
                charYCoords.append((index: i, y: charBounds.origin.y, bounds: charBounds))
            }
        }

        guard charYCoords.count > 1 else {
            return nil // Not enough data
        }

        // Group characters into lines based on Y coordinate
        // A new line starts when Y changes significantly
        var lines: [(startIndex: Int, endIndex: Int, y: CGFloat, firstBounds: CGRect)] = []
        var currentLineStart = charYCoords[0].index
        var currentLineY = charYCoords[0].y
        var currentFirstBounds = charYCoords[0].bounds

        for i in 1 ..< charYCoords.count {
            let (index, y, bounds) = charYCoords[i]
            let yDiff = abs(y - currentLineY)

            if yDiff > typicalLineHeight * 0.5 {
                // This character starts a new line
                // End the previous line at the character BEFORE this one
                let prevIndex = charYCoords[i - 1].index
                lines.append((startIndex: currentLineStart, endIndex: prevIndex, y: currentLineY, firstBounds: currentFirstBounds))
                Logger.debug("ElementTreeStrategy: Line ended at index \(prevIndex), Y=\(currentLineY)", category: Logger.accessibility)

                // Start new line
                currentLineStart = index
                currentLineY = y
                currentFirstBounds = bounds
            }
        }

        // Don't forget the last line
        let lastIndex = charYCoords[charYCoords.count - 1].index
        lines.append((startIndex: currentLineStart, endIndex: lastIndex, y: currentLineY, firstBounds: currentFirstBounds))

        Logger.debug("ElementTreeStrategy: Found \(lines.count) lines via Y-coordinate grouping", category: Logger.accessibility)

        // Build bounds for each line
        if lines.count > 1 {
            for (i, line) in lines.enumerated() {
                // Get bounds for the last character of this line
                let lastCharRange = NSRange(location: line.endIndex, length: 1)
                if let lastBounds = getBoundsForRange(lastCharRange, in: element) {
                    // Calculate line bounds from first to last character
                    let lineX = line.firstBounds.origin.x
                    let lineY = line.firstBounds.origin.y
                    let lineWidth = max(lastBounds.maxX - line.firstBounds.origin.x, typicalLineHeight)
                    let lineHeight = max(line.firstBounds.height, typicalLineHeight)

                    let lineRect = CGRect(x: lineX, y: lineY, width: lineWidth, height: lineHeight)
                    lineBounds.append(lineRect)
                    Logger.debug("ElementTreeStrategy: Line \(i) bounds: \(lineRect), indices \(line.startIndex)-\(line.endIndex)", category: Logger.accessibility)
                }
            }

            if lineBounds.count > 1 {
                return lineBounds
            }
        }

        // Method 2: Geometric fallback - split overall bounds into estimated line segments
        Logger.debug("ElementTreeStrategy: Using geometric fallback to split into \(estimatedLineCount) lines", category: Logger.accessibility)
        lineBounds = []

        for lineIndex in 0 ..< estimatedLineCount {
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
            Logger.debug("ElementTreeStrategy: Geometric line \(lineIndex): \(lineRect)", category: Logger.accessibility)
        }

        return lineBounds.isEmpty ? nil : lineBounds
    }
}
