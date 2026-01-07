//
//  NotionContentParser.swift
//  TextWarden
//
//  Content parser for Notion (Electron-based app).
//  Handles text preprocessing to filter out UI elements before analysis.
//
//  Positioning is handled by NotionStrategy, which traverses the AX tree
//  to find AXStaticText children with working AXBoundsForRange queries
//  (same approach as Slack and Teams).
//

import AppKit
import Foundation

/// Notion-specific content parser for text preprocessing
class NotionContentParser: ContentParser {
    // MARK: - Properties

    let bundleIdentifier: String
    let parserName = "Notion"

    /// UI elements that Notion includes in AX text but should be filtered
    /// These are detected via exact match or prefix matching
    /// Note: Notion uses curly quotes (U+2018 left, U+2019 right) in some UI text
    private static let notionUIElements: [String] = [
        "Add icon",
        "Add cover",
        "Add comment",
        "Type '/' for commands",
        "Type \u{2018}/\u{2019} for commands", // Curly quotes variant (U+2018/U+2019)
        "Write, press 'space' for AI, '/' for commands", // AI placeholder (straight quotes)
        "Write, press \u{2018}space\u{2019} for AI, \u{2018}/\u{2019} for commands", // Curly quotes variant
        "Write, press 'space' for AI", // Shorter variant (straight quotes)
        "Write, press \u{2018}space\u{2019} for AI", // Curly quotes shorter variant
        "Write, press \u{2018}space\u{2019}", // Even shorter (what Notion actually sends)
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

    /// Role descriptions that ARE allowed (include list approach)
    /// Only text inside these container types will be analyzed for grammar errors.
    /// This is more robust than an exclude list because unknown block types
    /// (lists, tables, code blocks with AX elements, etc.) are automatically excluded.
    ///
    /// NOTE: Code blocks are virtualized (no AX element) so they're handled separately
    /// via the U+200B marker detection in preprocessText().
    private static let allowedContainerRoleDescriptions: Set<String> = [
        "", // Empty - some elements don't have roleDesc
        "group", // Generic containers
        "text entry area", // Text blocks
        "heading", // Headers (H1, H2, H3)
        "text", // AXStaticText elements
    ]

    /// Bullet characters used in Notion lists
    /// These appear as separate lines/characters in the fullText
    private static let bulletCharacters: Set<Character> = [
        "\u{2022}", // • Bullet
        "\u{25AA}", // ▪ Black Small Square
        "\u{25E6}", // ◦ White Bullet
        "\u{2023}", // ‣ Triangular Bullet
        "\u{2043}", // ⁃ Hyphen Bullet
    ]

    /// Offset of actual content within the full AX text
    /// Used to map error positions from preprocessed text back to original
    private(set) var uiElementOffset: Int = 0

    /// Ranges of text to skip (from blockquotes, etc.) - detected from AX tree
    private var skipRanges: [NSRange] = []

    /// Text content to skip - stored as strings so we can re-find them after preprocessing
    private var skipTexts: [String] = []

    // MARK: - Initialization

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    /// Offset to add when mapping preprocessed error positions to original text
    var textReplacementOffset: Int {
        uiElementOffset
    }

    // MARK: - Text Preprocessing

    /// Check if a string is emoji-only (page icons, decorative elements)
    /// Notion page icons are typically single grapheme clusters that aren't alphanumeric
    /// NOTE: U+200B (zero-width space) is NOT considered emoji - it's used as a code block marker
    private func isEmojiOnlyLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }

        // Check if line is very short (1-3 grapheme clusters) and contains no letters/digits
        // This catches emoji, symbols, and other non-text UI elements
        let graphemeCount = line.count
        guard graphemeCount <= 3 else { return false }

        // Must not contain any letter or digit characters
        // Use explicit check for letters and digits, ignoring variation selectors and other modifiers
        for scalar in line.unicodeScalars {
            // Skip variation selectors and other invisible modifiers
            if scalar.value >= 0xFE00 && scalar.value <= 0xFE0F { continue }
            if scalar.value >= 0xE0100 && scalar.value <= 0xE01EF { continue }

            // U+200B (zero-width space) is used as a code block boundary marker
            // Don't treat it as emoji/UI element - let code block detection handle it
            if scalar.value == 0x200B { return false }

            // Check if this is a letter or digit
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                return false
            }
        }

        return true
    }

    /// Strip leading non-alphanumeric characters (emoji, symbols) from a string
    private func stripLeadingNonAlphanumeric(_ text: String) -> String {
        var result = text
        while let first = result.first {
            let isAlphanumeric = first.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            if isAlphanumeric {
                break
            }
            result.removeFirst()
        }
        return result
    }

    /// Check if a line should be filtered as a UI element
    private func isUIElementLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Empty lines
        if trimmed.isEmpty { return true }

        // Emoji-only lines (page icons)
        if isEmojiOnlyLine(trimmed) { return true }

        // Strip leading emoji/symbols and check for known UI elements
        // This handles cases like "page icon+Add icon" where emoji prefixes the UI text
        let strippedLine = stripLeadingNonAlphanumeric(trimmed)

        // Check both original trimmed and stripped versions against UI elements
        return Self.notionUIElements.contains { uiElement in
            trimmed == uiElement ||
                trimmed.hasPrefix(uiElement) ||
                strippedLine == uiElement ||
                strippedLine.hasPrefix(uiElement)
        }
    }

    /// Check if a line is a code block boundary marker (zero-width space)
    /// Notion uses U+200B after code blocks
    /// NOTE: U+200B is in CharacterSet.whitespaces, so we can't use trimmingCharacters
    private func isCodeBlockBoundary(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }

        // Check if line contains at least one U+200B and ONLY whitespace/U+200B characters
        var hasZeroWidthSpace = false
        for scalar in line.unicodeScalars {
            if scalar.value == 0x200B {
                hasZeroWidthSpace = true
            } else if !CharacterSet.whitespaces.contains(scalar) {
                // Found a non-whitespace, non-U+200B character
                return false
            }
        }
        return hasZeroWidthSpace
    }

    /// Check if a line is a bullet character (used in bulleted lists)
    /// Notion uses various bullet characters that appear as separate lines in fullText
    private func isBulletLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 1, let char = trimmed.first else { return false }
        return Self.bulletCharacters.contains(char)
    }

    /// Check if a line is a numbered list marker (e.g., "1.", "2.", "10.")
    /// Notion uses numbers followed by period for numbered lists
    private func isNumberedListMarker(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Check if it matches pattern: one or more digits followed by a period
        // e.g., "1.", "2.", "10.", "123."
        guard trimmed.last == "." else { return false }
        let withoutPeriod = trimmed.dropLast()
        return !withoutPeriod.isEmpty && withoutPeriod.allSatisfy(\.isNumber)
    }

    /// Preprocess Notion text to filter out UI elements and code blocks
    /// IMPORTANT: Only filter LEADING and TRAILING UI elements, not middle ones.
    /// Middle filtering causes position drift because textReplacementOffset only
    /// tracks leading removed characters. TextPart-based positioning needs
    /// consistent character offsets between filtered and full text.
    ///
    /// Code blocks are identified by the pattern: content line followed by U+200B line.
    /// We replace code block content with empty lines (preserving positions) so errors
    /// in code blocks don't get reported.
    func preprocessText(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }

        var lines = text.components(separatedBy: "\n")
        var removedChars = 0

        // Remove leading empty lines, UI elements, and emoji-only lines (page icons)
        // IMPORTANT: Use unicodeScalars.count for position tracking because Harper
        // reports error positions in Unicode scalar offsets, not grapheme clusters.
        // Emojis with skin tones (e.g., 💪🏼) are 1 grapheme but 2+ scalars.
        while let firstLine = lines.first {
            if isUIElementLine(firstLine) {
                // Count Unicode scalars in this line plus the newline after it
                removedChars += firstLine.unicodeScalars.count + 1
                lines.removeFirst()
            } else {
                break
            }
        }

        // Store offset for position mapping
        uiElementOffset = removedChars

        // Debug: Log what was removed
        if removedChars > 0 {
            Logger.debug("NotionContentParser: Removed \(removedChars) scalars from leading UI elements", category: Logger.ui)
        }

        // Also remove trailing UI elements (like placeholders at the end)
        // Trailing removal doesn't affect position mapping since errors come before
        while let lastLine = lines.last {
            if isUIElementLine(lastLine) {
                lines.removeLast()
            } else {
                break
            }
        }

        // Filter code blocks: lines followed by U+200B are code block content
        // Replace with newlines to preserve character positions while preventing
        // grammar checking of code content (newlines avoid Harper "multiple spaces" warnings)
        // Use unicodeScalars.count to match Harper's position system
        var codeBlocksFiltered = 0
        for i in 0 ..< lines.count {
            // Check if next line is a code block boundary (U+200B)
            if i + 1 < lines.count {
                let nextLine = lines[i + 1]
                if isCodeBlockBoundary(nextLine) {
                    Logger.trace("NotionContentParser: Code block at line \(i), U+200B boundary at line \(i + 1)", category: Logger.ui)
                    // This line is code block content - replace with newlines to preserve scalar length
                    let originalLength = lines[i].unicodeScalars.count
                    lines[i] = String(repeating: "\n", count: originalLength)
                    codeBlocksFiltered += 1
                }
            }
        }

        // Filter bulleted list items: bullet character followed by list item content
        // Structure: line N is "•" (bullet), line N+1 is the list item text
        // Use unicodeScalars.count to match Harper's position system
        var bulletListsFiltered = 0
        for i in 0 ..< lines.count {
            if isBulletLine(lines[i]) {
                // Replace bullet line with newlines (scalar count)
                lines[i] = String(repeating: "\n", count: lines[i].unicodeScalars.count)
                // Replace the following line (list item content) with newlines
                if i + 1 < lines.count {
                    let originalLength = lines[i + 1].unicodeScalars.count
                    lines[i + 1] = String(repeating: "\n", count: originalLength)
                    Logger.trace("NotionContentParser: Filtered bullet list item at line \(i + 1)", category: Logger.ui)
                }
                bulletListsFiltered += 1
            }
        }

        // Filter numbered list items: number marker (e.g., "1.") followed by list item content
        // Structure: line N is "1." (number), line N+1 is the list item text
        // Use unicodeScalars.count to match Harper's position system
        var numberedListsFiltered = 0
        for i in 0 ..< lines.count {
            if isNumberedListMarker(lines[i]) {
                // Replace number marker line with newlines (scalar count)
                lines[i] = String(repeating: "\n", count: lines[i].unicodeScalars.count)
                // Replace the following line (list item content) with newlines
                if i + 1 < lines.count {
                    let originalLength = lines[i + 1].unicodeScalars.count
                    lines[i + 1] = String(repeating: "\n", count: originalLength)
                    Logger.trace("NotionContentParser: Filtered numbered list item at line \(i + 1)", category: Logger.ui)
                }
                numberedListsFiltered += 1
            }
        }

        // Also replace the U+200B boundary lines with same-length newlines
        // IMPORTANT: Must preserve scalar count to avoid position drift
        lines = lines.map { line in
            if isCodeBlockBoundary(line) {
                // Replace U+200B chars with newlines (scalar count) to preserve positions
                return String(repeating: "\n", count: line.unicodeScalars.count)
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "" : line
        }

        var filteredText = lines.joined(separator: "\n")

        // Apply skip texts by searching for them in the filtered text
        // This avoids position alignment issues - we find the actual text content and replace it
        var skipTextsApplied = 0
        for skipText in skipTexts {
            // Search for the skip text in the filtered content
            if let range = filteredText.range(of: skipText) {
                // Replace with newlines to preserve scalar positions for Harper
                let scalarCount = skipText.unicodeScalars.count
                let replacement = String(repeating: "\n", count: scalarCount)
                filteredText.replaceSubrange(range, with: replacement)
                skipTextsApplied += 1
            }
        }

        // Filter UI element patterns anywhere in the text (not just leading/trailing)
        // These are Notion's placeholder texts like "Write, press 'space' for AI..."
        // Replace with newlines to preserve scalar positions for Harper
        var uiPatternsFiltered = 0
        for uiElement in Self.notionUIElements {
            // Search for the UI element text anywhere in the filtered content
            // Use a while loop to handle multiple occurrences
            while let range = filteredText.range(of: uiElement) {
                let scalarCount = uiElement.unicodeScalars.count
                let replacement = String(repeating: "\n", count: scalarCount)
                filteredText.replaceSubrange(range, with: replacement)
                uiPatternsFiltered += 1
                Logger.trace("NotionContentParser: Filtered UI pattern '\(uiElement.prefix(30))...'", category: Logger.ui)
            }
        }

        if removedChars > 0 || codeBlocksFiltered > 0 || bulletListsFiltered > 0 || numberedListsFiltered > 0 || skipTextsApplied > 0 || uiPatternsFiltered > 0 {
            Logger.debug("NotionContentParser: Filtered leading UI: \(removedChars), code blocks: \(codeBlocksFiltered), bullet lists: \(bulletListsFiltered), numbered lists: \(numberedListsFiltered), skip texts: \(skipTextsApplied)/\(skipTexts.count), UI patterns: \(uiPatternsFiltered), remaining: \(filteredText.unicodeScalars.count) scalars", category: Logger.ui)
            // Debug: Show what text remains for analysis (truncated)
            let cleanedPreview = filteredText.replacingOccurrences(of: "\n", with: "↵").prefix(100)
            Logger.debug("NotionContentParser: Filtered text preview: '\(cleanedPreview)'", category: Logger.ui)
        }

        // Return nil if nothing left after filtering
        return filteredText.isEmpty ? nil : filteredText
    }

    // MARK: - UI Context Detection

    func detectUIContext(element: AXUIElement) -> String? {
        // Try to get role description to identify Notion block type
        var roleDescValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescValue) == .success,
           let roleDesc = roleDescValue as? String
        {
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
           CFGetTypeID(pv) == AXUIElementGetTypeID()
        {
            // Safe: type verified by CFGetTypeID check above
            let parent = unsafeBitCast(pv, to: AXUIElement.self)
            var parentRoleDesc: CFTypeRef?
            if AXUIElementCopyAttributeValue(parent, kAXRoleDescriptionAttribute as CFString, &parentRoleDesc) == .success,
               let roleDesc = parentRoleDesc as? String
            {
                for blockType in Self.notionContentBlockTypes {
                    if roleDesc.contains(blockType) {
                        return String(blockType.dropFirst("notion-".count))
                    }
                }
            }
        }

        return "page-content"
    }

    // MARK: - Font Configuration

    func estimatedFontSize(context: String?) -> CGFloat {
        // Font sizes based on Notion's actual rendering
        switch context {
        case "header-block": 30.0 // H1 - large header
        case "sub_header-block": 24.0 // H2 - medium header
        case "sub_sub_header-block": 20.0 // H3 - small header
        case "callout-block": 15.0 // Callout blocks
        case "toggle-block": 16.0 // Toggle content
        case "text-block", "page-block": 16.0 // Body text
        default: 16.0 // Default Notion body text
        }
    }

    func spacingMultiplier(context _: String?) -> CGFloat {
        1.0 // Notion's Electron/React rendering
    }

    func horizontalPadding(context _: String?) -> CGFloat {
        0.0 // Padding handled by strategy
    }

    var disablesVisualUnderlines: Bool {
        false // Underlines enabled - NotionStrategy handles positioning
    }

    /// Notion's extractText returns preprocessed text (UI elements already filtered)
    var extractTextReturnsPreprocessed: Bool {
        true
    }

    // MARK: - Text Extraction

    /// Custom text extraction that returns preprocessed text
    /// CRITICAL: This ensures text validation compares the same text that was analyzed.
    /// Without this, extractTextSynchronously() would return raw AX text (with UI elements),
    /// while lastAnalyzedText has preprocessed text (UI elements filtered), causing mismatches.
    func extractText(from element: AXUIElement) -> String? {
        // Get raw text from AXValue
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard error == .success, let text = value as? String else {
            return nil
        }

        // Detect skip ranges from AX tree (blockquotes, etc.)
        skipTexts = [] // Reset before detection
        skipRanges = detectSkipRanges(element: element, fullText: text)

        // Return preprocessed text (with UI elements and skip ranges filtered)
        return preprocessText(text)
    }

    // MARK: - AX Tree Traversal for Skip Ranges

    /// Detect text ranges that should be skipped (blockquotes, etc.) by traversing AX tree
    private func detectSkipRanges(element: AXUIElement, fullText: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var searchStart = 0

        collectSkipRanges(
            from: element,
            fullText: fullText,
            searchStart: &searchStart,
            into: &ranges,
            insideDisallowedBlock: false,
            depth: 0
        )

        if !ranges.isEmpty {
            Logger.debug("NotionContentParser: Detected \(ranges.count) skip ranges from AX tree", category: Logger.ui)
        }

        return ranges
    }

    /// Check if an element has a "Tick box" in nearby ancestor siblings or their children.
    /// Notion's AX structure places "Tick box" inside a sibling group:
    ///   AXGroup (todo row container)
    ///   ├── AXGroup (checkbox container)
    ///   │   └── Tick box  <-- need to find this
    ///   ├── AXTextArea
    ///   │   └── AXStaticText (text content) <-- we're here
    /// So we need to check siblings AND their immediate children.
    private func hasTodoSibling(_ element: AXUIElement) -> Bool {
        var current = element

        // Check up to 3 levels of ancestors
        for _ in 0 ..< 3 {
            // Get parent of current
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let pRef = parentRef,
                  CFGetTypeID(pRef) == AXUIElementGetTypeID()
            else {
                return false
            }
            // Safe: type verified above
            let parent = unsafeBitCast(pRef, to: AXUIElement.self)

            // Get siblings at this level (parent's children)
            if let siblings = getChildren(parent) {
                for sibling in siblings {
                    // Check if sibling is a Tick box
                    let siblingRoleDesc = getRoleDescription(sibling)
                    if siblingRoleDesc == "Tick box" {
                        return true
                    }

                    // Check sibling's children (Tick box might be nested one level)
                    if let siblingChildren = getChildren(sibling) {
                        for child in siblingChildren {
                            let childRoleDesc = getRoleDescription(child)
                            if childRoleDesc == "Tick box" {
                                return true
                            }
                        }
                    }
                }
            }

            // Move up to check next level
            current = parent
        }
        return false
    }

    /// Recursively traverse AX tree to find skip ranges (using allow-list approach)
    /// Text is only analyzed if ALL ancestors have allowed roleDescriptions.
    /// Once we hit a non-allowed container, everything below it is skipped.
    /// Also detects todo items via sibling "Tick box" relationship.
    private func collectSkipRanges(
        from element: AXUIElement,
        fullText: String,
        searchStart: inout Int,
        into ranges: inout [NSRange],
        insideDisallowedBlock: Bool,
        depth: Int
    ) {
        // Prevent infinite recursion
        guard depth < 15 else { return }

        let roleDesc = getRoleDescription(element)

        // Check if this element's roleDescription is in our allow list
        // If not, everything below it should be skipped
        let isDisallowed = !Self.allowedContainerRoleDescriptions.contains(roleDesc)
        var shouldSkip = insideDisallowedBlock || isDisallowed

        if isDisallowed, !insideDisallowedBlock {
            Logger.trace("NotionContentParser: Found disallowed container roleDesc='\(roleDesc)'", category: Logger.ui)
        }

        // Get text content if this is a text element
        let text = getText(element)

        // Check for todo item context: if this text element has a "Tick box" sibling
        // This handles Notion's structure where Tick box is sibling, not parent
        if !shouldSkip, !text.isEmpty, hasTodoSibling(element) {
            shouldSkip = true
        }

        // Debug: log when we're inside a disallowed block and have text
        if insideDisallowedBlock, !text.isEmpty, text.count < 100 {
            Logger.trace("NotionContentParser: Inside disallowed block, found text '\(text.prefix(30))...' roleDesc='\(roleDesc)'", category: Logger.ui)
        }

        if shouldSkip, !text.isEmpty {
            // Store the text content to skip - will be searched in filtered text later
            // This avoids position alignment issues between original and filtered text
            if !skipTexts.contains(text) {
                skipTexts.append(text)
                Logger.trace("NotionContentParser: Will skip text '\(text.prefix(30))...' (roleDesc='\(roleDesc)')", category: Logger.ui)
            }

            // Also store range for backward compatibility (though we'll primarily use skipTexts)
            if let range = findTextRange(text, in: fullText, startingAt: searchStart) {
                ranges.append(range)
                searchStart = range.location + range.length
            } else if let range = findTextRange(text, in: fullText, startingAt: 0) {
                let alreadyCovered = ranges.contains { $0.location == range.location }
                if !alreadyCovered {
                    ranges.append(range)
                }
            }
        }

        // Recurse into children
        guard let children = getChildren(element) else { return }

        for child in children {
            collectSkipRanges(
                from: child,
                fullText: fullText,
                searchStart: &searchStart,
                into: &ranges,
                insideDisallowedBlock: shouldSkip,
                depth: depth + 1
            )
        }
    }

    /// Find text range in full text, returning Unicode scalar positions
    /// IMPORTANT: Returns positions in Unicode scalars to match Harper's position system
    private func findTextRange(_ substring: String, in text: String, startingAt: Int) -> NSRange? {
        let scalars = text.unicodeScalars
        guard startingAt < scalars.count,
              let searchStartIdx = scalars.index(scalars.startIndex, offsetBy: startingAt, limitedBy: scalars.endIndex)
        else {
            return nil
        }

        // Convert scalar index to String.Index for searching
        guard let stringStartIdx = String.Index(searchStartIdx, within: text) else {
            return nil
        }

        let searchRange = stringStartIdx ..< text.endIndex
        if let foundRange = text.range(of: substring, range: searchRange) {
            // Calculate position in Unicode scalars (not grapheme clusters)
            let foundScalarIdx = foundRange.lowerBound.samePosition(in: scalars) ?? scalars.startIndex
            let location = scalars.distance(from: scalars.startIndex, to: foundScalarIdx)
            let length = substring.unicodeScalars.count
            return NSRange(location: location, length: length)
        }
        return nil
    }

    // MARK: - AX Helpers

    private func getText(_ element: AXUIElement) -> String {
        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef) == .success,
              let text = textRef as? String
        else {
            return ""
        }
        return text
    }

    private func getRoleDescription(_ element: AXUIElement) -> String {
        var roleDescRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescRef) == .success,
              let roleDesc = roleDescRef as? String
        else {
            return ""
        }
        return roleDesc
    }

    private func getChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }
        return children
    }
}
