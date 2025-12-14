//
//  InsertionPointStrategy.swift
//  TextWarden
//
//  Insertion point (cursor/caret) based positioning strategy.
//  Uses the cursor position and selected text range as anchors,
//  then calculates error position using font metrics.
//  Designed for Mac Catalyst apps where standard AX bounds APIs fail.
//

import Foundation
import AppKit
import ApplicationServices

/// Insertion point strategy for Mac Catalyst apps
/// Uses cursor position and selection range as anchors since AXBoundsForRange
/// returns invalid values (0 width/height) for Catalyst apps like Apple Messages.
class InsertionPointStrategy: GeometryProvider {

    var strategyName: String { "InsertionPoint" }
    var strategyType: StrategyType { .insertionPoint }
    var tier: StrategyTier { .reliable }
    var tierPriority: Int { 5 }

    func canHandle(element: AXUIElement, bundleID: String) -> Bool {
        // Try to get insertion point info - if available, we can handle it
        return getSelectedTextRange(from: element) != nil || getInsertionPoint(from: element) != nil
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {

        Logger.debug("InsertionPointStrategy: Starting for range \(errorRange)", category: Logger.ui)

        // Get element frame - this is our baseline for positioning
        guard let elementFrame = AccessibilityBridge.getElementFrame(element),
              elementFrame.width > 0, elementFrame.height > 0 else {
            Logger.debug("InsertionPointStrategy: Could not get element frame", category: Logger.accessibility)
            return nil
        }

        Logger.debug("InsertionPointStrategy: Element frame: \(elementFrame)", category: Logger.ui)

        // HYBRID APPROACH: Try to use AXBoundsForRange for Y coordinate
        // Mac Catalyst apps often return valid Y even when width is 0
        // We'll use AX for Y (accurate) and font metrics for X (since width is broken)
        let textOffset = parser.textReplacementOffset
        let originalErrorLocation = errorRange.location + textOffset

        if let hybridResult = tryHybridPositioning(
            errorRange: errorRange,
            originalLocation: originalErrorLocation,
            element: element,
            elementFrame: elementFrame,
            text: text,
            parser: parser
        ) {
            return hybridResult
        }

        Logger.debug("InsertionPointStrategy: Hybrid approach failed, using full font metrics", category: Logger.ui)

        // Get font configuration for this app
        let context = parser.detectUIContext(element: element)
        let fontSize = parser.estimatedFontSize(context: context)
        let padding = parser.horizontalPadding(context: context)

        // Get insertion point (cursor position in text)
        let insertionPoint = getInsertionPoint(from: element)
        let selectedRange = getSelectedTextRange(from: element)

        Logger.debug("InsertionPointStrategy: insertionPoint=\(String(describing: insertionPoint)), selectedRange=\(String(describing: selectedRange))", category: Logger.ui)

        // originalErrorLocation was already calculated above for hybrid approach

        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Get text before error
        guard originalErrorLocation >= 0 && originalErrorLocation <= text.count else {
            Logger.debug("InsertionPointStrategy: Error location \(originalErrorLocation) out of bounds", category: Logger.accessibility)
            return nil
        }

        // Safe string extraction
        guard let errorStartIdx = text.index(text.startIndex, offsetBy: originalErrorLocation, limitedBy: text.endIndex) else {
            Logger.debug("InsertionPointStrategy: Could not get error start index", category: Logger.accessibility)
            return nil
        }

        let textBeforeError = String(text[..<errorStartIdx])

        // Get error text
        let errorEndLocation = min(originalErrorLocation + errorRange.length, text.count)
        guard let errorEndIdx = text.index(text.startIndex, offsetBy: errorEndLocation, limitedBy: text.endIndex),
              errorStartIdx <= errorEndIdx else {
            Logger.debug("InsertionPointStrategy: Could not get error end index", category: Logger.accessibility)
            return nil
        }
        let errorText = String(text[errorStartIdx..<errorEndIdx])

        // === LINE HEIGHT CALCULATION ===
        // Messages uses approximately 20-22pt line height for 13pt font
        // Estimate line height based on font size, then derive line count from element height
        let expectedLineHeight: CGFloat = fontSize * GeometryConstants.cursorLineHeightMultiplier
        let minLineHeight: CGFloat = GeometryConstants.constrainedMinLineHeight
        let maxLineHeight: CGFloat = GeometryConstants.constrainedMaxLineHeight

        // Calculate available width for text (element width minus padding)
        // Messages has minimal internal padding - the element frame is close to the text bounds
        let availableWidth = elementFrame.width - (padding * 2)

        // Estimate line count from element height divided by expected line height
        // This is more reliable than width-based estimation because element height is accurate
        let estimatedLinesFromHeight = max(1, Int(round(elementFrame.height / expectedLineHeight)))

        // Calculate actual line height from element height divided by line count
        var lineHeight: CGFloat
        if estimatedLinesFromHeight > 1 {
            lineHeight = elementFrame.height / CGFloat(estimatedLinesFromHeight)
            // Clamp to reasonable range
            lineHeight = min(max(lineHeight, minLineHeight), maxLineHeight)
        } else {
            lineHeight = fontSize * GeometryConstants.largerLineHeightMultiplier
        }

        // Width estimation multiplier for wrap detection
        // A multiplier < 1.0 means Messages renders narrower than NSFont predicts
        // A value closer to 1.0 means text wraps earlier (less text fits per line)
        // Tuned for Messages to match actual visual line breaks
        let widthEstimationMultiplier: CGFloat = 1.0

        Logger.debug("InsertionPointStrategy: elementHeight=\(elementFrame.height), availableWidth=\(availableWidth), estimatedLines=\(estimatedLinesFromHeight), baseLineHeight=\(lineHeight)", category: Logger.ui)

        // === DETERMINE WHICH LINE THE ERROR IS ON AND TEXT POSITION ON THAT LINE ===
        // Use word-by-word wrapping simulation to find where text actually wraps
        // This is more accurate than simple width division since Messages wraps at word boundaries
        let (visualLineNumber, textOnCurrentLine) = findLineAndPosition(
            textBeforeError: textBeforeError,
            availableWidth: availableWidth,
            attributes: attributes,
            multiplier: widthEstimationMultiplier
        )

        // Calculate TOTAL line count for the entire text (not just up to the error)
        // This is needed to derive accurate line height from element height
        let (totalVisualLines, _) = findLineAndPosition(
            textBeforeError: text,  // Use full text to count all lines
            availableWidth: availableWidth,
            attributes: attributes,
            multiplier: widthEstimationMultiplier
        )
        let totalLineCount = totalVisualLines + 1  // +1 because it's 0-indexed

        // Use the height-based line estimate as ground truth since it matches actual rendering
        // Our word-wrap simulation often overcounts due to font metric differences
        let adjustedLineHeight = elementFrame.height / CGFloat(estimatedLinesFromHeight)

        // Scale visualLineNumber if simulation overcounts
        let adjustedVisualLineNumber: Int
        if totalLineCount > estimatedLinesFromHeight && estimatedLinesFromHeight > 0 {
            let scaleFactor = CGFloat(estimatedLinesFromHeight) / CGFloat(totalLineCount)
            adjustedVisualLineNumber = Int(round(CGFloat(visualLineNumber) * scaleFactor))
            Logger.debug("InsertionPointStrategy: Scaling visualLineNumber from \(visualLineNumber) to \(adjustedVisualLineNumber) (totalLines=\(totalLineCount), estimated=\(estimatedLinesFromHeight))", category: Logger.ui)
        } else {
            adjustedVisualLineNumber = visualLineNumber
        }

        // Calculate Y position - element frame origin is TOP in Quartz coordinates
        // Use proportional positioning based on adjusted line number vs estimated total lines
        // This accounts for non-uniform line heights by distributing space proportionally
        let proportionalY: CGFloat
        if estimatedLinesFromHeight > 0 {
            // Calculate Y as a proportion of element height
            // Leave room for one line at the bottom (don't exceed last line position)
            let maxLineIndex = CGFloat(estimatedLinesFromHeight - 1)
            let clampedLineIndex = min(CGFloat(adjustedVisualLineNumber), maxLineIndex)
            proportionalY = elementFrame.origin.y + (clampedLineIndex / CGFloat(estimatedLinesFromHeight)) * elementFrame.height
        } else {
            proportionalY = elementFrame.origin.y + (CGFloat(adjustedVisualLineNumber) * adjustedLineHeight)
        }

        // Add a small upward offset for lines > 0 to better align with text baseline
        let lineOffset: CGFloat = adjustedVisualLineNumber > 0 ? -2.0 : 0.0
        let errorY = proportionalY + lineOffset

        // Sanity check: line height should be reasonable
        guard adjustedLineHeight >= 14.0 && adjustedLineHeight <= 50.0 else {
            Logger.debug("InsertionPointStrategy: Calculated line height \(adjustedLineHeight) outside reasonable range - failing strategy", category: Logger.ui)
            return nil
        }

        Logger.debug("InsertionPointStrategy: totalLineCount=\(totalLineCount), estimated=\(estimatedLinesFromHeight), adjustedLineHeight=\(adjustedLineHeight)", category: Logger.ui)

        // Measure the text on the current line directly
        // The multiplier (0.78) is used only for wrap detection to match Messages' narrower rendering
        // But for positioning within a line, we use the actual measured width since we already
        // have the correct text on the current line
        let textWidthOnCurrentLine = (textOnCurrentLine as NSString).size(withAttributes: attributes).width

        Logger.debug("InsertionPointStrategy: visualLineNumber=\(visualLineNumber), textOnCurrentLine='\(textOnCurrentLine)', textWidthOnCurrentLine=\(textWidthOnCurrentLine)", category: Logger.ui)

        // === CALCULATE X POSITION ===
        let rawErrorWidth = (errorText as NSString).size(withAttributes: attributes).width
        let errorWidth = max(rawErrorWidth, 20.0)
        let errorX = elementFrame.origin.x + padding + textWidthOnCurrentLine

        // errorY is already calculated above using mixed line heights

        let quartzBounds = CGRect(
            x: errorX,
            y: errorY,
            width: errorWidth,
            height: adjustedLineHeight
        )

        Logger.debug("InsertionPointStrategy: Quartz bounds: \(quartzBounds) (line \(visualLineNumber))", category: Logger.ui)

        // Validate bounds are reasonable
        guard quartzBounds.width > 0 && quartzBounds.height > 0 else {
            Logger.debug("InsertionPointStrategy: Invalid bounds dimensions", category: Logger.accessibility)
            return nil
        }

        // Ensure X position is within element bounds (with some tolerance)
        let maxX = elementFrame.origin.x + elementFrame.width + 50
        guard errorX < maxX else {
            Logger.debug("InsertionPointStrategy: X position \(errorX) exceeds element width", category: Logger.accessibility)
            return nil
        }

        // Ensure Y position is within element bounds
        let maxY = elementFrame.origin.y + elementFrame.height
        guard errorY < maxY else {
            Logger.debug("InsertionPointStrategy: Y position \(errorY) exceeds element height (max \(maxY))", category: Logger.accessibility)
            return nil
        }

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        Logger.debug("InsertionPointStrategy: Cocoa bounds: \(cocoaBounds)", category: Logger.ui)

        // Validate final bounds
        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("InsertionPointStrategy: Final bounds validation failed", category: Logger.accessibility)
            return nil
        }

        // Confidence based on whether we have cursor info
        let confidence: Double
        if insertionPoint != nil || selectedRange != nil {
            confidence = GeometryConstants.mediumConfidence
        } else {
            confidence = GeometryConstants.lowerConfidence
        }

        Logger.debug("InsertionPointStrategy: SUCCESS - bounds: \(cocoaBounds), confidence: \(confidence)", category: Logger.ui)

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: confidence,
            strategy: strategyName,
            metadata: [
                "api": "insertion-point",
                "visual_line_number": visualLineNumber,
                "text_before_width": textWidthOnCurrentLine,
                "line_height": adjustedLineHeight,
                "estimated_lines": estimatedLinesFromHeight,
                "total_lines": totalLineCount,
                "has_cursor_info": insertionPoint != nil || selectedRange != nil
            ]
        )
    }

    // MARK: - Line Position Detection

    /// Result from line position detection including wrap vs newline distinction
    private struct LinePositionResult {
        let visualLineNumber: Int
        let textOnCurrentLine: String
        let hardLineIndex: Int  // Which hard line (newline-separated) we're on
        let wrapsBeforeThisHardLine: Int  // Total soft wraps before this hard line
    }

    /// Find which visual line the error is on and the text on that line before the error
    /// Returns (lineNumber, textOnLineBeforeError)
    /// Handles both manual line breaks (newlines) and soft word wrapping
    private func findLineAndPosition(
        textBeforeError: String,
        availableWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        multiplier: CGFloat
    ) -> (Int, String) {
        let result = findLineAndPositionDetailed(
            textBeforeError: textBeforeError,
            availableWidth: availableWidth,
            attributes: attributes,
            multiplier: multiplier
        )
        return (result.visualLineNumber, result.textOnCurrentLine)
    }

    /// Detailed version that also returns hard line info for non-uniform line height calculation
    private func findLineAndPositionDetailed(
        textBeforeError: String,
        availableWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        multiplier: CGFloat
    ) -> LinePositionResult {
        guard availableWidth > 0 else {
            return LinePositionResult(
                visualLineNumber: 0,
                textOnCurrentLine: textBeforeError,
                hardLineIndex: 0,
                wrapsBeforeThisHardLine: 0
            )
        }

        // Check for no newlines case first (common case)
        if !textBeforeError.contains(where: { $0.isNewline }) {
            // No newlines - just do word wrap simulation
            let (wrappedLines, finalLineText) = simulateWordWrap(
                text: textBeforeError,
                availableWidth: availableWidth,
                attributes: attributes,
                multiplier: multiplier
            )
            return LinePositionResult(
                visualLineNumber: wrappedLines,
                textOnCurrentLine: finalLineText,
                hardLineIndex: 0,
                wrapsBeforeThisHardLine: 0
            )
        }

        // Split by newlines - use a method that preserves empty strings between consecutive newlines
        var hardLines: [String] = []
        var currentSegment = ""
        for char in textBeforeError {
            if char.isNewline {
                hardLines.append(currentSegment)
                currentSegment = ""
            } else {
                currentSegment.append(char)
            }
        }
        // Add the final segment (text after the last newline, or empty if text ends with newline)
        hardLines.append(currentSegment)

        var visualLineNumber = 0
        var currentLineText = ""
        var totalWrapsBeforeCurrentHardLine = 0
        var currentHardLineIndex = 0

        // Process each hard line (separated by newlines)
        for (hardLineIndex, hardLine) in hardLines.enumerated() {
            // For each hard line, simulate word wrapping
            let (wrappedLines, finalLineText) = simulateWordWrap(
                text: hardLine,
                availableWidth: availableWidth,
                attributes: attributes,
                multiplier: multiplier
            )

            // Track wraps before this hard line (for the final result)
            if hardLineIndex < hardLines.count - 1 {
                totalWrapsBeforeCurrentHardLine += wrappedLines
            }

            // Add wrapped line count to visual line number
            // (wrappedLines is the number of times text wrapped within this hard line)
            visualLineNumber += wrappedLines
            currentLineText = finalLineText
            currentHardLineIndex = hardLineIndex

            // If this is not the last hard line, the newline moves us to the next visual line
            if hardLineIndex < hardLines.count - 1 {
                visualLineNumber += 1
                // Reset currentLineText - it will be set by the next iteration
                // (or remain empty if the next line is also empty)
            }
        }

        Logger.debug("InsertionPointStrategy: findLineAndPosition - line=\(visualLineNumber), textOnLineLen=\(currentLineText.count), hardLines=\(hardLines.count), hardLineIndex=\(currentHardLineIndex)", category: Logger.ui)

        return LinePositionResult(
            visualLineNumber: visualLineNumber,
            textOnCurrentLine: currentLineText,
            hardLineIndex: currentHardLineIndex,
            wrapsBeforeThisHardLine: totalWrapsBeforeCurrentHardLine
        )
    }

    /// Simulate word wrapping within a single line (no newlines)
    /// Returns (numberOfWraps, textOnFinalLine)
    private func simulateWordWrap(
        text: String,
        availableWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        multiplier: CGFloat
    ) -> (Int, String) {
        // Empty text = no wraps, empty line
        guard !text.isEmpty else {
            return (0, "")
        }

        // Check if text fits on single line
        let totalWidth = (text as NSString).size(withAttributes: attributes).width * multiplier
        if totalWidth <= availableWidth {
            return (0, text)
        }

        // Simulate word wrapping
        var wrapCount = 0
        var currentLineText = ""
        var currentLineWidth: CGFloat = 0

        let words = text.components(separatedBy: " ")

        for (index, word) in words.enumerated() {
            let wordWithSpace = index == 0 ? word : " " + word
            let wordWidth = (wordWithSpace as NSString).size(withAttributes: attributes).width * multiplier

            if currentLineWidth + wordWidth > availableWidth && !currentLineText.isEmpty {
                // Word doesn't fit - wrap to new line
                wrapCount += 1
                currentLineText = word  // Start new line with this word (no leading space)
                currentLineWidth = (word as NSString).size(withAttributes: attributes).width * multiplier
            } else {
                // Word fits on current line
                currentLineText += wordWithSpace
                currentLineWidth += wordWidth
            }
        }

        return (wrapCount, currentLineText)
    }

    // MARK: - AX API Helpers

    /// Get the insertion point (cursor position) from the element
    private func getInsertionPoint(from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXInsertionPointLineNumber" as CFString,
            &value
        )

        if result == .success, let lineNum = value as? Int {
            return lineNum
        }

        return nil
    }

    /// Get selected text range from the element
    private func getSelectedTextRange(from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success,
              let axValue = value,
              let range = safeAXValueGetRange(axValue) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    // MARK: - Hybrid Positioning (AX Y + Font Metrics X)

    /// Try hybrid positioning: use AXBoundsForRange for Y coordinate, font metrics for X
    /// Mac Catalyst apps often return valid Y even when width is 0
    /// This gives us accurate vertical positioning while still calculating X with font metrics
    private func tryHybridPositioning(
        errorRange: NSRange,
        originalLocation: Int,
        element: AXUIElement,
        elementFrame: CGRect,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {
        // Try to get bounds for the error range using standard AX API
        // We mainly care about the Y coordinate - X/width may be broken
        var cfRange = CFRange(location: originalLocation, length: max(1, errorRange.length))

        // Clamp to text length to avoid out-of-bounds
        let textUTF16Length = (text as NSString).length
        if cfRange.location >= textUTF16Length {
            Logger.debug("InsertionPointStrategy: Hybrid - location \(cfRange.location) >= textLength \(textUTF16Length)", category: Logger.ui)
            return nil
        }
        cfRange.length = min(cfRange.length, textUTF16Length - cfRange.location)

        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.debug("InsertionPointStrategy: Hybrid - failed to create AXValue", category: Logger.ui)
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
            Logger.debug("InsertionPointStrategy: Hybrid - AXBoundsForRange failed with error \(result.rawValue)", category: Logger.ui)
            return nil
        }

        guard let axBounds = safeAXValueGetRect(bv) else {
            Logger.debug("InsertionPointStrategy: Hybrid - failed to extract CGRect", category: Logger.ui)
            return nil
        }

        Logger.debug("InsertionPointStrategy: Hybrid - AXBoundsForRange returned: \(axBounds)", category: Logger.ui)

        // Check if we got a valid Y coordinate
        // The Y should be within the element frame (with some tolerance)
        let minY = elementFrame.origin.y - 50
        let maxY = elementFrame.origin.y + elementFrame.height + 50

        guard axBounds.origin.y >= minY && axBounds.origin.y <= maxY else {
            Logger.debug("InsertionPointStrategy: Hybrid - Y coordinate \(axBounds.origin.y) outside element bounds [\(minY), \(maxY)]", category: Logger.ui)
            return nil
        }

        // Mac Catalyst AX API is broken for X coordinates but Y is usually reliable.
        // EXCEPTION: When AX returns a very large height (> 1.5x normal line height),
        // it means AX returned bogus bounds spanning multiple lines - this happens for
        // text at the start of a line after a hard newline. In this case, calculate Y ourselves.

        let context = parser.detectUIContext(element: element)
        let fontSize = parser.estimatedFontSize(context: context)
        let padding = parser.horizontalPadding(context: context)
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Use grapheme cluster indices for Swift string operations
        guard originalLocation <= text.count,
              let errorStartIdx = text.index(text.startIndex, offsetBy: originalLocation, limitedBy: text.endIndex) else {
            Logger.debug("InsertionPointStrategy: Hybrid - originalLocation \(originalLocation) out of bounds", category: Logger.ui)
            return nil
        }

        let textBeforeError = String(text[..<errorStartIdx])

        // Calculate available width for line wrapping
        let effectiveAvailableWidth = elementFrame.width - (padding * 2)

        // Find how much text is on the current line before the error (for X calculation)
        // We don't use visualLineNumber in hybrid mode since Y comes from AX
        let (_, textOnCurrentLine) = findLineAndPosition(
            textBeforeError: textBeforeError,
            availableWidth: effectiveAvailableWidth,
            attributes: attributes,
            multiplier: 1.0
        )

        // Calculate X position using font metrics
        let textWidthOnLine = (textOnCurrentLine as NSString).size(withAttributes: attributes).width
        let errorX = elementFrame.origin.x + padding + textWidthOnLine

        // Determine Y coordinate
        // If AX returned a suspiciously large height (> 24px for ~16px line height),
        // it means the bounds span multiple lines - this happens for text at the start
        // of a line after a hard newline. The AX bounds span from the wrong line to the
        // correct line. Solution: use the BOTTOM of the AX bounds minus one line height.
        let normalLineHeight = GeometryConstants.normalLineHeight
        let suspiciousHeightThreshold = normalLineHeight * GeometryConstants.suspiciousHeightMultiplier

        let errorY: CGFloat
        if axBounds.height > suspiciousHeightThreshold {
            // AX returned bogus multi-line bounds - the error is at the BOTTOM of these bounds
            // Subtract one line height from the bottom to get the correct Y
            let correctedY = axBounds.origin.y + axBounds.height - normalLineHeight
            Logger.debug("InsertionPointStrategy: Hybrid - AX height \(axBounds.height) > threshold \(suspiciousHeightThreshold), using corrected Y: \(correctedY) (bottom - lineHeight)", category: Logger.ui)
            errorY = correctedY
        } else {
            // AX Y is reliable - use it
            errorY = axBounds.origin.y
        }

        // Calculate width using font metrics
        let errorEndLocation = min(originalLocation + errorRange.length, text.count)
        guard let errorEndIdx = text.index(text.startIndex, offsetBy: errorEndLocation, limitedBy: text.endIndex) else {
            Logger.debug("InsertionPointStrategy: Hybrid - errorEndLocation out of bounds", category: Logger.ui)
            return nil
        }
        let errorText = String(text[errorStartIdx..<errorEndIdx])
        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 10.0)

        // Use AX height if reasonable (single line), otherwise default to normal line height
        // If we detected multi-line bounds earlier, always use normalLineHeight
        let lineHeight: CGFloat
        if axBounds.height > suspiciousHeightThreshold {
            lineHeight = normalLineHeight
        } else if axBounds.height > GeometryConstants.minimumBoundsSize && axBounds.height <= GeometryConstants.maxSingleLineHeight {
            lineHeight = axBounds.height
        } else {
            lineHeight = normalLineHeight
        }

        Logger.debug("InsertionPointStrategy: Hybrid - AX Y + font metrics X: x=\(errorX), y=\(errorY), w=\(errorWidth), lineLen=\(textOnCurrentLine.count)", category: Logger.ui)

        // Construct hybrid bounds
        let quartzBounds = CGRect(
            x: errorX,
            y: errorY,
            width: errorWidth,
            height: lineHeight
        )

        Logger.debug("InsertionPointStrategy: Hybrid SUCCESS - quartzBounds: \(quartzBounds) (y=\(errorY), x=\(errorX))", category: Logger.ui)

        // Validate bounds
        guard quartzBounds.width > 0 && quartzBounds.height > 0 else {
            return nil
        }

        // Convert to Cocoa coordinates
        let cocoaBounds = CoordinateMapper.toCocoaCoordinates(quartzBounds)

        guard CoordinateMapper.validateBounds(cocoaBounds) else {
            Logger.debug("InsertionPointStrategy: Hybrid - final bounds validation failed", category: Logger.ui)
            return nil
        }

        return GeometryResult(
            bounds: cocoaBounds,
            confidence: GeometryConstants.goodConfidence,
            strategy: strategyName,
            metadata: [
                "api": "hybrid-ax-y-font-x",
                "ax_y": errorY,
                "font_x": errorX,
                "ax_height": axBounds.height
            ]
        )
    }

    /// Query AXBoundsForRange for a single character at the given location.
    /// Returns bounds in Quartz screen coordinates, or nil if the query fails.
    private func getCharacterBounds(location: Int, in element: AXUIElement, textLength: Int) -> CGRect? {
        guard location >= 0 && location < textLength else { return nil }

        var cfRange = CFRange(location: location, length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success,
              let bv = boundsValue,
              let bounds = safeAXValueGetRect(bv) else { return nil }

        // Validate we got something reasonable
        guard bounds.width > 0 && bounds.height > 0 else { return nil }

        return bounds
    }
}
