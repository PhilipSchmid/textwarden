//
//  NotionContentParser.swift
//  TextWarden
//
//  Content parser for Notion (Electron-based app)
//  Uses cursor position as anchor for reliable error positioning in Electron apps.
//
//  Positioning Strategy:
//  - Use AXSelectedTextRange to get cursor position
//  - Get bounds for cursor/selection as reliable anchor
//  - Calculate error positions relative to cursor
//  - Fall back to element frame + text measurement when AX APIs fail
//  - Filter out Notion UI elements from text before analysis
//

import Foundation
import AppKit

/// Notion-specific content parser using cursor-anchored positioning
class NotionContentParser: ContentParser {

    // MARK: - Properties

    let bundleIdentifier: String
    let parserName = "Notion"

    /// DEVELOPMENT FLAG: Force showing underlines even with unreliable positioning
    /// Best practice: Hide underlines rather than show them at wrong positions
    static var forceShowUnderlines = true

    /// Diagnostic result from probing Notion's AX capabilities
    /// Populated on first positioning attempt
    private static var diagnosticResult: NotionDiagnosticResult?
    private static var hasRunDiagnostic = false

    /// UI elements that Notion includes in AX text but should be filtered
    /// These are detected via exact match or prefix matching
    private static let notionUIElements: [String] = [
        "Add icon",
        "Add cover",
        "Add comment",
        "Type '/' for commands",
        "Write, press 'space' for AI, '/' for commands",  // AI placeholder
        "Write, press 'space' for AI",  // Shorter variant
        "Press Enter to continue with an empty page",
        "Untitled",
    ]

    /// Notion block types detected via AXRoleDescription
    /// These identify actual content blocks vs UI chrome
    private static let notionContentBlockTypes: Set<String> = [
        "notion-text-block",
        "notion-header-block",
        "notion-sub_header-block",
        "notion-sub_sub_header-block",
        "notion-page-block",
        "notion-callout-block",
        "notion-toggle-block",
    ]

    /// Offset of actual content within the full AX text
    /// Used to map error positions from preprocessed text back to original
    private(set) var uiElementOffset: Int = 0

    /// Cache for cursor position to avoid repeated AX calls
    private var cachedCursorInfo: (position: Int, frame: NSRect, timestamp: Date)?
    private let cursorCacheTimeout: TimeInterval = TimingConstants.cursorCacheTimeout

    // MARK: - Initialization

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    /// Offset to add when mapping preprocessed error positions to original text
    var textReplacementOffset: Int {
        return uiElementOffset
    }

    // MARK: - Text Preprocessing

    /// Preprocess Notion text to filter out UI elements
    func preprocessText(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }

        var lines = text.components(separatedBy: "\n")
        var removedChars = 0

        // Remove leading empty lines and UI elements
        while let firstLine = lines.first {
            let line = firstLine.trimmingCharacters(in: .whitespaces)

            // Check if this line is a known UI element
            let isUIElement = line.isEmpty ||
                Self.notionUIElements.contains { uiElement in
                    line == uiElement || line.hasPrefix(uiElement)
                }

            if isUIElement {
                // Count characters being removed (line + newline)
                removedChars += firstLine.count + 1
                lines.removeFirst()
            } else {
                break
            }
        }

        // Store offset for position mapping
        self.uiElementOffset = removedChars

        // Also remove trailing UI elements (like placeholders at the end)
        while let lastLine = lines.last {
            let line = lastLine.trimmingCharacters(in: .whitespaces)

            // Check if this line is a known UI element
            let isUIElement = line.isEmpty ||
                Self.notionUIElements.contains { uiElement in
                    line == uiElement || line.hasPrefix(uiElement)
                }

            if isUIElement {
                lines.removeLast()
            } else {
                break
            }
        }

        // Also filter UI elements from MIDDLE of content (e.g., placeholder on focused empty line)
        // Replace with empty line to preserve line count for position mapping
        lines = lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isUIElement = Self.notionUIElements.contains { uiElement in
                trimmed == uiElement || trimmed.hasPrefix(uiElement)
            }
            return isUIElement ? "" : line
        }

        let filteredText = lines.joined(separator: "\n")

        if removedChars > 0 || text.count != filteredText.count {
            Logger.debug("NotionContentParser: Filtered UI elements, original: \(text.count) chars, remaining: \(filteredText.count) chars, leading offset: \(removedChars)", category: Logger.ui)
        }

        // Return nil if nothing left after filtering
        return filteredText.isEmpty ? nil : filteredText
    }

    func detectUIContext(element: AXUIElement) -> String? {
        // Try to get role description to identify Notion block type
        var roleDescValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescValue) == .success,
           let roleDesc = roleDescValue as? String {
            // Check for known Notion block types
            for blockType in Self.notionContentBlockTypes {
                if roleDesc.contains(blockType) {
                    // Return normalized block type (remove "notion-" prefix)
                    return String(blockType.dropFirst("notion-".count))
                }
            }
        }

        // Also check parent elements for block type context
        var parentValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success,
           let pv = parentValue,
           CFGetTypeID(pv) == AXUIElementGetTypeID() {
            // Safe: type verified by CFGetTypeID check above
            let parent = unsafeBitCast(pv, to: AXUIElement.self)
            var parentRoleDesc: CFTypeRef?
            if AXUIElementCopyAttributeValue(parent, kAXRoleDescriptionAttribute as CFString, &parentRoleDesc) == .success,
               let roleDesc = parentRoleDesc as? String {
                for blockType in Self.notionContentBlockTypes {
                    if roleDesc.contains(blockType) {
                        return String(blockType.dropFirst("notion-".count))
                    }
                }
            }
        }

        return "page-content"
    }

    // MARK: - Content Detection

    /// Check if an element is a Notion content block (vs UI chrome)
    private func isContentBlock(roleDescription: String?) -> Bool {
        guard let roleDesc = roleDescription else { return false }
        return Self.notionContentBlockTypes.contains { roleDesc.contains($0) }
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Font sizes based on Notion's actual rendering
        switch context {
        case "header-block": return 30.0            // H1 - large header
        case "sub_header-block": return 24.0        // H2 - medium header
        case "sub_sub_header-block": return 20.0    // H3 - small header
        case "callout-block": return 15.0           // Callout blocks
        case "toggle-block": return 16.0            // Toggle content
        case "text-block", "page-block": return 16.0 // Body text
        default: return 16.0  // Default Notion body text
        }
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        return 1.0  // Notion's Electron/React rendering
    }

    func horizontalPadding(context: String?) -> CGFloat {
        return 0.0  // Padding handled in position calculation
    }

    var disablesVisualUnderlines: Bool {
        return false  // Enable underlines - we have cursor-anchored positioning
    }

    // MARK: - Bounds Adjustment

    /// Bounds adjustment using cursor position as anchor
    /// IMPORTANT: errorRange is based on FILTERED text positions.
    /// When calling AX APIs, we must add uiElementOffset to get original text positions.
    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        // Run comprehensive diagnostic ONCE to discover what AX APIs work
        if !Self.hasRunDiagnostic {
            Self.hasRunDiagnostic = true
            Self.diagnosticResult = AccessibilityBridge.runNotionDiagnostic(element)

            if let result = Self.diagnosticResult {
                Logger.info("NOTION DIAGNOSTIC SUMMARY:")
                Logger.info("  Best method: \(result.bestMethodDescription)")
                Logger.info("  Has working method: \(result.hasWorkingMethod)")
                Logger.info("  Working range bounds: \(result.workingRangeBounds.count)")
                Logger.info("  Line bounds: \(result.lineBounds.count)")
                Logger.info("  Children with bounds: \(result.childrenWithBounds.count)")
            }
        }

        // Convert filtered text position to original text position for AX API calls
        let originalRange = NSRange(
            location: errorRange.location + uiElementOffset,
            length: errorRange.length
        )

        // CRITICAL FIX: Extract errorText using ORIGINAL position from RAW text
        // The passed errorText is wrong - it was extracted using preprocessed position from raw text
        // Use safe index operations to prevent crashes on out-of-bounds access
        let correctedErrorText: String
        let originalStart = originalRange.location
        let originalEnd = originalRange.location + originalRange.length
        if originalStart >= 0, originalStart < originalEnd,
           let startIdx = fullText.index(fullText.startIndex, offsetBy: originalStart, limitedBy: fullText.endIndex),
           let endIdx = fullText.index(fullText.startIndex, offsetBy: originalEnd, limitedBy: fullText.endIndex),
           startIdx <= endIdx {
            correctedErrorText = String(fullText[startIdx..<endIdx])
        } else {
            correctedErrorText = errorText // Fallback to passed value
        }

        Logger.debug("NotionContentParser: adjustBounds for range \(errorRange) (original: \(originalRange)), errorText='\(correctedErrorText)', offset=\(uiElementOffset)", category: Logger.ui)

        // Strategy 1: Try to get cursor frame as anchor
        // Cursor position is in original text coordinates
        if let cursorAnchor = getCursorAnchorInfo(element: element) {
            // Adjust cursor position to filtered text coordinates for line calculations
            let adjustedCursorPosition = max(0, cursorAnchor.position - uiElementOffset)
            let adjustedCursorAnchor = CursorAnchorInfo(
                position: adjustedCursorPosition,
                frame: cursorAnchor.frame,
                lineNumber: cursorAnchor.lineNumber,
                columnOffset: cursorAnchor.columnOffset
            )

            if let result = calculatePositionFromCursorAnchor(
                cursorAnchor: adjustedCursorAnchor,
                errorRange: errorRange,
                textBeforeError: textBeforeError,
                errorText: correctedErrorText,  // Use corrected text
                fullText: fullText,
                element: element
            ) {
                return result
            }
        }

        // Strategy 2: Try direct AX bounds for the error range (use original position)
        if let axBounds = AccessibilityBridge.getBoundsForRange(originalRange, in: element) {
            Logger.debug("NotionContentParser: Got valid AX bounds: \(axBounds)", category: Logger.ui)
            return AdjustedBounds(
                position: NSPoint(x: axBounds.origin.x, y: axBounds.origin.y),
                errorWidth: axBounds.width,
                confidence: 0.85,
                uiContext: detectUIContext(element: element),
                debugInfo: "Notion AX bounds (direct)"
            )
        }

        // Strategy 3: Fall back to element frame + text measurement
        // This uses filtered text positions, which is correct for line counting
        return calculatePositionFromElementFrame(
            element: element,
            errorRange: errorRange,
            textBeforeError: textBeforeError,
            errorText: correctedErrorText,  // Use corrected text
            fullText: fullText
        )
    }

    // MARK: - Cursor Anchor Approach

    /// Structure to hold cursor/insertion point information
    private struct CursorAnchorInfo {
        let position: Int           // Character position of cursor
        let frame: NSRect           // Screen frame of cursor (from AXBoundsForRange)
        let lineNumber: Int         // Line number of cursor
        let columnOffset: Int       // Column offset on current line
    }

    /// Get cursor position and frame as anchor point
    private func getCursorAnchorInfo(element: AXUIElement) -> CursorAnchorInfo? {
        // Get selected text range (cursor position)
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
              let rangeRef = selectedRangeValue,
              let selectedRange = safeAXValueGetRange(rangeRef) else {
            Logger.debug("NotionContentParser: Failed to get AXSelectedTextRange", category: Logger.ui)
            return nil
        }

        let cursorPosition = selectedRange.location
        Logger.debug("NotionContentParser: Cursor at position \(cursorPosition)", category: Logger.ui)

        // Try to get insertion point line number
        var insertionLineValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointLineNumber" as CFString, &insertionLineValue) == .success {
            if let lineNum = insertionLineValue {
                Logger.debug("NotionContentParser: AXInsertionPointLineNumber = \(lineNum)", category: Logger.ui)
            }
        }

        // Try to get bounds for cursor position using multiple strategies
        var cursorFrame: NSRect?

        // First try: AXInsertionPointFrame - primary method for cursor position
        var insertionPointValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointFrame" as CFString, &insertionPointValue) == .success,
           let axValue = insertionPointValue,
           let frame = safeAXValueGetRect(axValue) {
            // Validate frame - check for Chromium's invalid (0,0,0,0) or (0, screenHeight, 0, 0) bug
            if frame.width > 0 || (frame.height > 0 && frame.height < GeometryConstants.conservativeMaxLineHeight) {
                cursorFrame = frame
                Logger.debug("NotionContentParser: Got cursor frame from AXInsertionPointFrame: \(frame)", category: Logger.ui)
            } else {
                Logger.debug("NotionContentParser: AXInsertionPointFrame returned invalid frame: \(frame)", category: Logger.ui)
            }
        }

        // Second try: bounds for single character at cursor
        if cursorFrame == nil {
            if let bounds = getBoundsForPosition(element: element, position: cursorPosition, length: 1) {
                cursorFrame = bounds
                Logger.debug("NotionContentParser: Got cursor frame from single char: \(bounds)", category: Logger.ui)
            }
        }

        // Third try: bounds for character before cursor (if cursor is not at start)
        if cursorFrame == nil && cursorPosition > 0 {
            if let bounds = getBoundsForPosition(element: element, position: cursorPosition - 1, length: 1) {
                // Adjust X to be at the end of the character
                let adjustedFrame = NSRect(
                    x: bounds.origin.x + bounds.width,
                    y: bounds.origin.y,
                    width: 1,
                    height: bounds.height
                )
                cursorFrame = adjustedFrame
                Logger.debug("NotionContentParser: Got cursor frame from prev char: \(adjustedFrame)", category: Logger.ui)
            }
        }

        // Log visible character range for debugging
        if cursorFrame == nil {
            var visibleRangeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &visibleRangeValue) == .success,
               let rangeRef = visibleRangeValue,
               let visibleRange = safeAXValueGetRange(rangeRef) {
                Logger.debug("NotionContentParser: Visible character range: \(visibleRange.location)-\(visibleRange.location + visibleRange.length)", category: Logger.ui)
            }
        }

        guard let frame = cursorFrame else {
            Logger.debug("NotionContentParser: Could not get cursor frame from any AX API", category: Logger.ui)
            return nil
        }

        // Calculate line number and column for cursor
        var fullText: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullText)
        let text = (fullText as? String) ?? ""

        let textBeforeCursor = String(text.prefix(cursorPosition))
        let linesBeforeCursor = textBeforeCursor.components(separatedBy: "\n")
        let lineNumber = linesBeforeCursor.count - 1
        let columnOffset = linesBeforeCursor.last?.count ?? 0

        return CursorAnchorInfo(
            position: cursorPosition,
            frame: frame,
            lineNumber: lineNumber,
            columnOffset: columnOffset
        )
    }

    /// Calculate error position relative to cursor anchor
    private func calculatePositionFromCursorAnchor(
        cursorAnchor: CursorAnchorInfo,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String,
        element: AXUIElement
    ) -> AdjustedBounds? {
        let context = detectUIContext(element: element)
        let fontSize = estimatedFontSize(context: context)
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Calculate error position relative to cursor
        let errorLineOffset = calculateLineOffset(
            from: cursorAnchor.position,
            to: errorRange.location,
            in: fullText
        )

        // Calculate X offset from cursor
        let cursorLineText = getLineText(at: cursorAnchor.position, in: fullText)
        _ = getLineText(at: errorRange.location, in: fullText)  // Used for context validation

        let textBeforeErrorOnLine = getTextBeforePositionOnLine(
            position: errorRange.location,
            in: fullText
        )

        // Calculate error width with a small buffer for Chromium rendering differences
        // NSFont measurement can underestimate compared to Chromium's text rendering
        let measuredWidth = (errorText as NSString).size(withAttributes: attributes).width
        let errorWidth = max(measuredWidth * 1.05, 20.0)  // 5% buffer for rendering variance

        // Calculate Y position
        // Each line is approximately lineHeight pixels apart
        let lineHeight: CGFloat = fontSize * 1.5  // Notion uses ~1.5 line height
        let yOffset = CGFloat(errorLineOffset) * lineHeight

        // Calculate X position
        // If on same line as cursor, calculate relative X offset
        // If on different line, calculate from line start
        var xPosition: CGFloat
        var yPosition: CGFloat

        if errorLineOffset == 0 {
            // Same line as cursor - calculate X offset from cursor
            let charsBetween = errorRange.location - cursorAnchor.position
            if charsBetween >= 0 {
                // Error is after cursor
                let textBetween = String(fullText.dropFirst(cursorAnchor.position).prefix(charsBetween))
                let offsetWidth = (textBetween as NSString).size(withAttributes: attributes).width
                xPosition = cursorAnchor.frame.origin.x + offsetWidth
            } else {
                // Error is before cursor
                let textBetween = String(fullText.dropFirst(errorRange.location).prefix(-charsBetween))
                let offsetWidth = (textBetween as NSString).size(withAttributes: attributes).width
                xPosition = cursorAnchor.frame.origin.x - offsetWidth
            }
            yPosition = cursorAnchor.frame.origin.y
        } else {
            // Different line - need to estimate X from line start
            let textBeforeWidth = (textBeforeErrorOnLine as NSString).size(withAttributes: attributes).width

            // Estimate line start X from element frame or cursor
            if let elementFrame = AccessibilityBridge.getElementFrame(element) {
                // Notion content area starts about 96px from left edge typically
                let contentPadding: CGFloat = 96.0
                xPosition = elementFrame.origin.x + contentPadding + textBeforeWidth
            } else {
                // Fall back to cursor X minus its column offset
                let cursorColumnWidth = (cursorLineText.prefix(cursorAnchor.columnOffset) as NSString).size(withAttributes: attributes).width
                let lineStartX = cursorAnchor.frame.origin.x - cursorColumnWidth
                xPosition = lineStartX + textBeforeWidth
            }
            yPosition = cursorAnchor.frame.origin.y + yOffset
        }

        let confidence: Double = errorLineOffset == 0 ? 0.80 : 0.70

        Logger.debug("NotionContentParser: Cursor anchor result - x: \(xPosition), y: \(yPosition), lineOffset: \(errorLineOffset)", category: Logger.ui)

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: yPosition),
            errorWidth: errorWidth,
            confidence: confidence,
            uiContext: context,
            debugInfo: "Notion cursor-anchored (lineOffset: \(errorLineOffset))"
        )
    }

    // MARK: - Helper Methods

    /// Get bounds for a specific position and length
    private func getBoundsForPosition(element: AXUIElement, position: Int, length: Int) -> CGRect? {
        var boundsValue: CFTypeRef?
        var axRange = CFRange(location: position, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &axRange) else {
            return nil
        }

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

        // Basic validation
        guard bounds.width >= 0 && bounds.height > GeometryConstants.minimumBoundsSize && bounds.height < GeometryConstants.conservativeMaxLineHeight else {
            return nil
        }

        return bounds
    }

    /// Calculate line offset between two positions
    private func calculateLineOffset(from: Int, to: Int, in text: String) -> Int {
        let start = min(from, to)
        let end = max(from, to)

        guard end <= text.count else { return 0 }

        // Safe string slicing to handle UTF-16/character count mismatches
        guard let startIndex = text.index(text.startIndex, offsetBy: start, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: end, limitedBy: text.endIndex),
              startIndex <= endIndex else {
            return 0
        }
        let textBetween = String(text[startIndex..<endIndex])

        let newlineCount = textBetween.filter { $0 == "\n" }.count

        return from <= to ? newlineCount : -newlineCount
    }

    /// Get the text of the line containing the given position
    private func getLineText(at position: Int, in text: String) -> String {
        guard position <= text.count else { return "" }

        let textBefore = String(text.prefix(position))
        let lines = textBefore.components(separatedBy: "\n")
        let currentLineStart = lines.dropLast().joined(separator: "\n").count + (lines.count > 1 ? 1 : 0)

        // Find line end
        let remaining = String(text.dropFirst(currentLineStart))
        if let newlineIndex = remaining.firstIndex(of: "\n") {
            return String(remaining[..<newlineIndex])
        }
        return remaining
    }

    /// Get text before position on the current line
    private func getTextBeforePositionOnLine(position: Int, in text: String) -> String {
        guard position <= text.count else { return "" }

        let textBefore = String(text.prefix(position))
        let lines = textBefore.components(separatedBy: "\n")
        return lines.last ?? ""
    }

    // MARK: - Fallback: Element Frame + Text Measurement

    /// Calculate position using element frame and SCROLL-AWARE paragraph positioning
    /// Key insight: correctScrollableFieldBoundingRects
    /// Must account for scroll position using AXVisibleCharacterRange
    /// Note: Returns position in Quartz coordinates (Y from top of screen)
    ///
    /// Calculate offsets relative to visible area for scroll-aware positioning
    /// rather than absolute text position. Notion's content is centered in a
    /// column that's about 60-70% of the element width.
    private func calculatePositionFromElementFrame(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        let context = detectUIContext(element: element)
        let fontSize = estimatedFontSize(context: context)
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width, 20.0)

        guard let elementFrame = AccessibilityBridge.getElementFrame(element) else {
            Logger.debug("NotionContentParser: Element frame fallback - no frame available", category: Logger.ui)
            return nil
        }

        // CRITICAL: Get visible character range for scroll-aware positioning
        // Use AXVisibleCharacterRange to handle scroll position correctly
        var visibleRangeValue: CFTypeRef?
        var visibleRange: CFRange?
        if AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &visibleRangeValue) == .success,
           let rangeRef = visibleRangeValue,
           let range = safeAXValueGetRange(rangeRef) {
            visibleRange = range
            Logger.debug("NotionContentParser: Visible character range: \(range.location)-\(range.location + range.length)", category: Logger.ui)
        }

        // IMPORTANT: errorRange is in PREPROCESSED text coordinates
        // fullText is the ORIGINAL text from AX element
        let originalPosition = errorRange.location + uiElementOffset

        // Check if error is visible (within visible character range)
        // If not visible, we can't accurately position it
        if let visible = visibleRange {
            let visibleEnd = visible.location + visible.length
            if originalPosition < visible.location || originalPosition >= visibleEnd {
                Logger.debug("NotionContentParser: Error at \(originalPosition) is outside visible range \(visible.location)-\(visibleEnd), skipping", category: Logger.ui)
                return nil
            }
        }

        // Extract paragraphs (non-empty, non-UI lines) and count blank lines between them
        let allLines = fullText.components(separatedBy: "\n")
        var paragraphs: [(text: String, startOffset: Int, isTitle: Bool, blankLinesBefore: Int)] = []
        var currentOffset = 0
        var isFirstContent = true
        var consecutiveBlankLines = 0

        for line in allLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isUI = Self.notionUIElements.contains(where: { trimmed.hasPrefix($0) })
            let isBlank = trimmed.isEmpty

            if isBlank && !isFirstContent {
                // Count blank lines between content paragraphs
                consecutiveBlankLines += 1
            } else if !isUI && !isBlank {
                paragraphs.append((text: line, startOffset: currentOffset, isTitle: isFirstContent, blankLinesBefore: consecutiveBlankLines))
                isFirstContent = false
                consecutiveBlankLines = 0
            }
            currentOffset += line.count + 1  // +1 for newline
        }

        Logger.debug("NotionContentParser: Paragraph analysis:", category: Logger.ui)
        for (idx, para) in paragraphs.enumerated() {
            Logger.debug("  Para \(idx): offset=\(para.startOffset), isTitle=\(para.isTitle), blanksBefore=\(para.blankLinesBefore), text='\(String(para.text.prefix(40)))'", category: Logger.ui)
        }

        // Find which paragraph contains the error
        var errorParagraphIndex = 0
        var positionInParagraph = 0
        for (idx, para) in paragraphs.enumerated() {
            let paraEnd = para.startOffset + para.text.count
            if originalPosition >= para.startOffset && originalPosition < paraEnd {
                errorParagraphIndex = idx
                positionInParagraph = originalPosition - para.startOffset
                break
            } else if originalPosition >= paraEnd && idx < paragraphs.count - 1 {
                errorParagraphIndex = idx + 1
            }
        }

        Logger.debug("NotionContentParser: Error at original pos \(originalPosition), in paragraph \(errorParagraphIndex), posInPara=\(positionInParagraph)", category: Logger.ui)

        // SCROLL-AWARE LAYOUT CALCULATION
        // Calculate which paragraph is at the TOP of the visible area
        var firstVisibleParagraphIndex = 0
        var isScrolled = false  // Track if page is scrolled past title

        if let visible = visibleRange {
            for (idx, para) in paragraphs.enumerated() {
                let paraEnd = para.startOffset + para.text.count
                if visible.location < paraEnd {
                    firstVisibleParagraphIndex = idx
                    break
                }
            }
            // If first visible is not the title (index 0), page is scrolled
            isScrolled = firstVisibleParagraphIndex > 0 || (visible.location > 0 && !paragraphs.isEmpty && visible.location > paragraphs[0].startOffset)
        }

        Logger.debug("NotionContentParser: First visible paragraph index: \(firstVisibleParagraphIndex), isScrolled: \(isScrolled)", category: Logger.ui)

        // DYNAMIC LAYOUT CALCULATION
        let elementWidth = elementFrame.size.width

        // Content column is approximately centered with ~708px max width
        let contentColumnWidth: CGFloat = min(708.0, elementWidth * 0.85)
        let contentLeftMargin = (elementWidth - contentColumnWidth) / 2.0

        // Vertical offsets - Notion uses consistent spacing
        // These values are calibrated to match Notion's actual rendering
        // CRITICAL: These must match Notion's actual pixel layout
        //
        // Measured from actual AXStaticText frames:
        // - Title at Y=287, height=95, so bottom at 382
        // - First body at Y=406
        // - Gap between title bottom and first body = 406 - 382 = 24px
        //
        // The underline should appear at the BASELINE of text (just below where letters sit).
        // We calculate position to the baseline, then TextMeasurementStrategy creates bounds
        // from (baseline - textHeight) to baseline, so the underline draws at the bottom.
        let bodyLineHeight: CGFloat = 26.0      // Body line height (~16pt font * 1.625)
        let paragraphSpacing: CGFloat = 4.0     // Spacing between consecutive body paragraphs
        let titleLineHeight: CGFloat = 47.5     // Title line height (95px / 2 lines ≈ 47.5)
        let titleTopOffset: CGFloat = 116.0     // Distance from element top to title TOP (287 - 171 = 116)
        let titleToBodyGap: CGFloat = 24.0      // Gap between title bottom and first body paragraph TOP

        // CRITICAL: Calculate Y offset relative to visible area
        var yOffset: CGFloat = 0.0

        // If not scrolled and title is visible, start with title offset
        let startParagraphIndex: Int
        if !isScrolled && firstVisibleParagraphIndex == 0 {
            // Page is at top - add title top offset
            startParagraphIndex = 0
            yOffset = titleTopOffset
        } else {
            // Page is scrolled - position relative to first visible paragraph
            startParagraphIndex = firstVisibleParagraphIndex
            yOffset = 0.0
        }

        // Calculate offset from start paragraph to error paragraph
        // CRITICAL: In Notion, newlines in AX text don't render as visual blank lines.
        // The gap between paragraphs is CSS spacing, handled by paragraphSpacing.
        // Only titleToBodyGap is special (larger gap after title).
        for i in startParagraphIndex..<errorParagraphIndex {
            if i < paragraphs.count {
                if paragraphs[i].isTitle {
                    let titleText = paragraphs[i].text
                    let titleWidth = (titleText as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 30.0)]).width
                    let wrappedLines = max(1, Int(ceil(titleWidth / contentColumnWidth)))
                    yOffset += CGFloat(wrappedLines) * titleLineHeight + titleToBodyGap
                } else {
                    // Body paragraphs: line height + small CSS spacing between paragraphs
                    yOffset += bodyLineHeight + paragraphSpacing
                }
            }
        }

        // Add small top margin for visible content area when scrolled
        let visibleAreaTopMargin: CGFloat = isScrolled ? 12.0 : 0.0

        Logger.debug("NotionContentParser: Scroll-aware layout - firstVisiblePara=\(firstVisibleParagraphIndex), errorPara=\(errorParagraphIndex), yOffset=\(yOffset)", category: Logger.ui)
        Logger.debug("NotionContentParser: Dynamic layout - elementWidth=\(elementWidth), contentLeftMargin=\(contentLeftMargin), contentColumnWidth=\(contentColumnWidth)", category: Logger.ui)

        // Calculate X position - text before error in current paragraph
        let currentParaText = errorParagraphIndex < paragraphs.count ? paragraphs[errorParagraphIndex].text : ""
        let textBeforeInPara = String(currentParaText.prefix(positionInParagraph))
        let textBeforeWidth = (textBeforeInPara as NSString).size(withAttributes: attributes).width

        // Determine line height for current paragraph (title vs body)
        let isErrorInTitle = errorParagraphIndex < paragraphs.count && paragraphs[errorParagraphIndex].isTitle
        let currentLineHeight = isErrorInTitle ? titleLineHeight : bodyLineHeight

        // Final positions (in Quartz coordinates - Y from screen top)
        // CRITICAL: Return BASELINE position, not TOP or BOTTOM of line
        // TextMeasurementStrategy expects baseline and subtracts errorHeight to get bounds
        // yOffset gives us the TOP of the text row, so add ~80% of lineHeight to get BASELINE
        // The baseline is where the bottom of letters (excluding descenders) sit
        let xPosition = elementFrame.origin.x + contentLeftMargin + textBeforeWidth
        let yPosition = elementFrame.origin.y + visibleAreaTopMargin + yOffset + (currentLineHeight * 0.80)

        Logger.debug("NotionContentParser: Scroll-aware positioning - para=\(errorParagraphIndex), yOffset=\(yOffset), lineHeight=\(currentLineHeight), x=\(xPosition), y=\(yPosition)", category: Logger.ui)

        // GRACEFUL DEGRADATION:
        // Element frame + hardcoded layout is unreliable. Return low confidence unless debug flag is set.
        // Principle: It's better to hide underlines than show them at incorrect positions.
        let confidence: Double = Self.forceShowUnderlines ? 0.65 : 0.30

        if !Self.forceShowUnderlines {
            Logger.debug("NotionContentParser: Using graceful degradation (confidence=0.30) - set NotionContentParser.forceShowUnderlines=true to override", category: Logger.ui)
        }

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: yPosition),
            errorWidth: errorWidth,
            confidence: confidence,
            uiContext: context,
            debugInfo: "Notion scroll-aware (para: \(errorParagraphIndex), firstVisible: \(firstVisibleParagraphIndex), leftMargin: \(Int(contentLeftMargin)), gracefulDegradation: \(!Self.forceShowUnderlines))"
        )
    }

}
