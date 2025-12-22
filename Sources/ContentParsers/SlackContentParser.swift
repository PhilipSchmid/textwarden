//
//  SlackContentParser.swift
//  TextWarden
//
//  Slack-specific content parser using multi-strategy positioning
//  Leverages TextMarkerStrategy for Chromium/Electron apps
//

import Foundation
import AppKit

/// Slack-specific content parser
/// Uses graceful degradation: error indicator shown but underlines hidden
/// due to Slack's AX APIs returning invalid bounds (Chromium bug)
class SlackContentParser: ContentParser {
    let bundleIdentifier = "com.tinyspeck.slackmacgap"
    let parserName = "Slack"

    /// Cached exclusion ranges from AX-based detection
    private var cachedExclusions: [ExclusionRange] = []

    /// Text hash for which exclusions were extracted
    private var exclusionTextHash: Int = 0

    /// Cached configuration from AppRegistry
    private var config: AppConfiguration {
        AppRegistry.shared.configuration(for: bundleIdentifier)
    }

    /// Track if we've dumped the element tree (do it once per session for debugging)
    private var hasDumpedElementTree = false

    /// Track if we've done Quill Delta extraction (do it once, not on every keystroke)
    private var hasExtractedQuillDelta = false

    /// Cached Quill Delta exclusions
    private var quillDeltaExclusions: [ExclusionRange] = []

    /// Last seen clipboard change count (for monitoring clipboard changes)
    private var lastClipboardChangeCount: Int = 0

    /// Clipboard monitoring timer
    private var clipboardMonitorTimer: Timer?

    /// Quill Delta pasteboard type identifier (Chromium's custom data format)
    private static let chromiumWebCustomDataType = NSPasteboard.PasteboardType("org.chromium.web-custom-data")

    // MARK: - Accessibility-Based Exclusion Detection

    /// Extract exclusion ranges using Accessibility APIs
    /// Primary method: AXAttributedStringForTextMarkerRange for formatting attributes
    /// Fallback: Element tree traversal for AXCodeStyleGroup, AXBlockQuoteLevel, AXLink
    func extractExclusions(from element: AXUIElement, text: String) -> [ExclusionRange] {
        let textHash = text.hashValue

        // Return cached exclusions if text hasn't changed
        if textHash == exclusionTextHash && !cachedExclusions.isEmpty {
            Logger.debug("SlackContentParser: Using cached exclusions (\(cachedExclusions.count) ranges)", category: Logger.analysis)
            return cachedExclusions
        }

        Logger.info("SlackContentParser: Extracting exclusions via Accessibility APIs", category: Logger.analysis)

        var exclusions: [ExclusionRange] = []

        // Method 1: Try AXLinkUIElements for direct link access (doesn't work in Chromium but try anyway)
        let linkExclusions = detectLinksViaAXLinkUIElements(element: element, text: text)
        exclusions.append(contentsOf: linkExclusions)

        // Method 2: Try AXAttributedStringForTextMarkerRange for formatting attributes
        let attributedExclusions = extractFromAttributedString(element: element, text: text)
        exclusions.append(contentsOf: attributedExclusions)

        // Method 3: Check if clipboard already has Quill Delta (from user's previous copy)
        // This is non-intrusive - just reads existing clipboard without modifying it
        if !hasExtractedQuillDelta {
            hasExtractedQuillDelta = true
            // First try passive reading (if user already copied from Slack)
            quillDeltaExclusions = parseQuillDeltaFromClipboard(text: text)
            if quillDeltaExclusions.isEmpty {
                Logger.debug("SlackContentParser: No existing Quill Delta on clipboard", category: Logger.analysis)
            }
        }
        exclusions.append(contentsOf: quillDeltaExclusions)

        // Method 4: Element tree traversal for additional detection
        if exclusions.isEmpty {
            // Dump element tree once for debugging
            if !hasDumpedElementTree {
                hasDumpedElementTree = true
                Logger.info("SlackContentParser: === Element Tree Dump ===", category: Logger.analysis)
                dumpElementTree(element, text: text, depth: 0)
                Logger.info("SlackContentParser: === End Element Tree ===", category: Logger.analysis)
            }

            // Check for AXCodeStyleGroup subrole (inline code)
            exclusions.append(contentsOf: detectCodeStyleGroups(in: element, text: text))

            // Check for AXBlockQuoteLevel attribute (blockquotes)
            exclusions.append(contentsOf: detectBlockQuotes(in: element, text: text))

            // Check for AXLink role (mentions, channels, URLs)
            exclusions.append(contentsOf: detectLinks(in: element, text: text))
        }

        // Cache and return
        cachedExclusions = exclusions
        exclusionTextHash = textHash

        if !exclusions.isEmpty {
            Logger.info("SlackContentParser: Detected \(exclusions.count) total exclusion ranges", category: Logger.analysis)
        }

        return exclusions
    }

    // MARK: - Attributed String Extraction (Primary Method)

    /// Extract exclusions from AXAttributedStringForTextMarkerRange
    /// This returns an NSAttributedString with formatting attributes like links, fonts, etc.
    private func extractFromAttributedString(element: AXUIElement, text: String) -> [ExclusionRange] {
        var exclusions: [ExclusionRange] = []

        // Get the full text range as a marker range
        guard let markerRange = getFullTextMarkerRange(element: element) else {
            Logger.debug("SlackContentParser: Could not get text marker range", category: Logger.analysis)
            return exclusions
        }

        // Get attributed string for the range
        var attrStringRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForTextMarkerRange" as CFString,
            markerRange,
            &attrStringRef
        )

        guard result == .success, let attrString = attrStringRef as? NSAttributedString else {
            Logger.debug("SlackContentParser: AXAttributedStringForTextMarkerRange failed (error: \(result.rawValue))", category: Logger.analysis)
            return exclusions
        }

        Logger.info("SlackContentParser: Got attributed string (\(attrString.length) chars), analyzing attributes...", category: Logger.analysis)

        // First pass: log all unique attribute keys found
        var allAttributeKeys: Set<String> = []
        attrString.enumerateAttributes(in: NSRange(location: 0, length: attrString.length), options: []) { attrs, _, _ in
            for key in attrs.keys {
                allAttributeKeys.insert(key.rawValue)
            }
        }
        Logger.info("SlackContentParser: Attribute keys found: \(allAttributeKeys.sorted().joined(separator: ", "))", category: Logger.analysis)

        // Enumerate attributes to find formatting
        attrString.enumerateAttributes(in: NSRange(location: 0, length: attrString.length), options: []) { attrs, range, _ in
            let rangeText = attrString.attributedSubstring(from: range).string
            // Log non-trivial attributes (skip if just font/paragraph style)
            let interestingAttrs = attrs.filter { $0.key != .font && $0.key != .paragraphStyle && $0.key != .foregroundColor }
            if !interestingAttrs.isEmpty {
                Logger.debug("SlackContentParser: Range \(range.location)-\(range.location + range.length) '\(rangeText.prefix(20))' has: \(interestingAttrs.keys.map { $0.rawValue }.joined(separator: ", "))", category: Logger.analysis)
            }

            // Check for links (mentions, channels, URLs)
            if let link = attrs[.link] {
                let linkText = attrString.attributedSubstring(from: range).string
                var linkType = "link"

                if let url = link as? URL {
                    let urlString = url.absoluteString
                    if urlString.contains("slack://user") || urlString.hasPrefix("@") {
                        linkType = "mention"
                    } else if urlString.contains("slack://channel") || urlString.hasPrefix("#") {
                        linkType = "channel"
                    }
                } else if let urlString = link as? String {
                    if urlString.contains("slack://user") || urlString.hasPrefix("@") {
                        linkType = "mention"
                    } else if urlString.contains("slack://channel") || urlString.hasPrefix("#") {
                        linkType = "channel"
                    }
                }

                Logger.info("SlackContentParser: Found \(linkType) at \(range.location)-\(range.location + range.length), text: '\(linkText)'", category: Logger.analysis)
                exclusions.append(ExclusionRange(location: range.location, length: range.length))
            }

            // Check for code font (monospace indicates code)
            if let font = attrs[.font] as? NSFont {
                let fontName = font.fontName.lowercased()
                if fontName.contains("mono") || fontName.contains("courier") || fontName.contains("menlo") ||
                   fontName.contains("consolas") || fontName.contains("source code") {
                    let codeText = attrString.attributedSubstring(from: range).string
                    Logger.info("SlackContentParser: Found code (font: \(font.fontName)) at \(range.location)-\(range.location + range.length), text: '\(codeText.prefix(30))'", category: Logger.analysis)
                    exclusions.append(ExclusionRange(location: range.location, length: range.length))
                }
            }

            // Check for custom Slack attributes (if any)
            for (key, _) in attrs {
                let keyName = key.rawValue.lowercased()
                if keyName.contains("code") || keyName.contains("quote") || keyName.contains("mention") {
                    let attrText = attrString.attributedSubstring(from: range).string
                    Logger.info("SlackContentParser: Found custom attr '\(key.rawValue)' at \(range.location)-\(range.location + range.length), text: '\(attrText.prefix(30))'", category: Logger.analysis)
                    exclusions.append(ExclusionRange(location: range.location, length: range.length))
                }
            }
        }

        return exclusions
    }

    /// Get full text marker range for the element
    private func getFullTextMarkerRange(element: AXUIElement) -> CFTypeRef? {
        // Method 1: Try AXTextMarkerRangeForUIElement
        var rangeRef: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerRangeForUIElement" as CFString,
            element,
            &rangeRef
        ) == .success {
            return rangeRef
        }

        // Method 2: Try to construct from start/end markers
        var startMarkerRef: CFTypeRef?
        var endMarkerRef: CFTypeRef?

        if AXUIElementCopyAttributeValue(element, "AXStartTextMarker" as CFString, &startMarkerRef) == .success,
           AXUIElementCopyAttributeValue(element, "AXEndTextMarker" as CFString, &endMarkerRef) == .success,
           let startMarker = startMarkerRef,
           let endMarker = endMarkerRef {

            // Create range from start to end markers
            let markers = [startMarker, endMarker] as CFArray
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                "AXTextMarkerRangeForMarkers" as CFString,
                markers,
                &rangeRef
            ) == .success {
                return rangeRef
            }
        }

        // Method 3: Try using number of characters
        var charCountRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &charCountRef) == .success,
           let charCount = charCountRef as? Int {

            // Get marker for index 0
            var startIndexMarker: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                "AXTextMarkerForIndex" as CFString,
                0 as CFNumber,
                &startIndexMarker
            ) == .success {

                // Get marker for last index
                var endIndexMarker: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    "AXTextMarkerForIndex" as CFString,
                    charCount as CFNumber,
                    &endIndexMarker
                ) == .success {

                    // Create range from markers
                    let markers = [startIndexMarker!, endIndexMarker!] as CFArray
                    if AXUIElementCopyParameterizedAttributeValue(
                        element,
                        "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
                        markers,
                        &rangeRef
                    ) == .success {
                        return rangeRef
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Quill Delta Extraction (Fast, Imperceptible)

    /// Check if an exclusion is a link (mention/channel)
    private func isLinkExclusion(_ exclusion: ExclusionRange, text: String) -> Bool {
        guard exclusion.location >= 0,
              exclusion.location + exclusion.length <= text.count,
              let start = text.index(text.startIndex, offsetBy: exclusion.location, limitedBy: text.endIndex),
              let end = text.index(start, offsetBy: exclusion.length, limitedBy: text.endIndex) else {
            return false
        }
        let exclusionText = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
        return exclusionText.hasPrefix("@") || exclusionText.hasPrefix("#") || exclusionText.hasPrefix("http")
    }

    /// Extract exclusions from Quill Delta via fast clipboard operation
    /// This is imperceptible to user (<50ms total) with full clipboard/selection restoration
    private func extractQuillDeltaExclusions(element: AXUIElement, text: String) -> [ExclusionRange] {
        var exclusions: [ExclusionRange] = []

        let startTime = DispatchTime.now()

        // Step 1: Save current state
        let savedClipboard = saveClipboardState()
        let savedSelection = saveSelectionState(element: element)

        defer {
            // Step 4: Restore state
            restoreSelectionState(element: element, state: savedSelection)
            restoreClipboardState(savedClipboard)

            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            Logger.debug("SlackContentParser: Quill Delta extraction took \(String(format: "%.1f", elapsed))ms", category: Logger.analysis)
        }

        // Step 2: Clear clipboard and trigger copy
        NSPasteboard.general.clearContents()
        let initialChangeCount = NSPasteboard.general.changeCount

        // Select all using AX action or key event
        let selectAllResult = performSelectAll(element: element)
        Logger.debug("SlackContentParser: Select all result: \(selectAllResult)", category: Logger.analysis)

        // Brief delay for selection to register
        usleep(30_000) // 30ms

        // Copy using AX action or key event
        let copyResult = performCopy(element: element)
        Logger.debug("SlackContentParser: Copy result: \(copyResult)", category: Logger.analysis)

        // Brief delay for clipboard to populate
        usleep(50_000) // 50ms

        // Check if clipboard changed
        let newChangeCount = NSPasteboard.general.changeCount
        Logger.debug("SlackContentParser: Clipboard change count: \(initialChangeCount) -> \(newChangeCount)", category: Logger.analysis)

        // Log what's on clipboard
        if let types = NSPasteboard.general.types {
            Logger.debug("SlackContentParser: Clipboard types: \(types.map { $0.rawValue }.joined(separator: ", "))", category: Logger.analysis)
        }

        // Step 3: Parse Quill Delta from clipboard
        exclusions = parseQuillDeltaFromClipboard(text: text)

        return exclusions
    }

    /// Save current clipboard state for restoration
    private func saveClipboardState() -> [(NSPasteboard.PasteboardType, Data)] {
        let pasteboard = NSPasteboard.general
        var saved: [(NSPasteboard.PasteboardType, Data)] = []

        if let types = pasteboard.types {
            for type in types {
                if let data = pasteboard.data(forType: type) {
                    saved.append((type, data))
                }
            }
        }
        return saved
    }

    /// Restore clipboard state
    private func restoreClipboardState(_ state: [(NSPasteboard.PasteboardType, Data)]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for (type, data) in state {
            pasteboard.setData(data, forType: type)
        }
    }

    /// Save current selection state
    private func saveSelectionState(element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let range = safeAXValueGetRange(rangeRef!) else {
            return nil
        }
        return range
    }

    /// Restore selection state
    private func restoreSelectionState(element: AXUIElement, state: CFRange?) {
        guard let range = state else { return }

        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
    }

    /// Perform Select All action
    private func performSelectAll(element: AXUIElement) -> Bool {
        // Try AX action first
        if AXUIElementPerformAction(element, "AXSelectAll" as CFString) == .success {
            return true
        }

        // Fall back to Cmd+A key event
        return simulateKeyCombo(keyCode: 0, command: true) // 'A' key
    }

    /// Perform Copy action
    private func performCopy(element: AXUIElement) -> Bool {
        // Try AX action first
        if AXUIElementPerformAction(element, "AXCopy" as CFString) == .success {
            return true
        }

        // Fall back to Cmd+C key event
        return simulateKeyCombo(keyCode: 8, command: true) // 'C' key
    }

    /// Simulate a keyboard shortcut
    private func simulateKeyCombo(keyCode: CGKeyCode, command: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        if command {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    /// Parse Quill Delta JSON from clipboard and extract exclusion ranges
    /// Handles Slack-specific embedded objects: user, channel, broadcast, emoji, date, link
    private func parseQuillDeltaFromClipboard(text: String) -> [ExclusionRange] {
        let emptyResult: [ExclusionRange] = []

        let pasteboard = NSPasteboard.general

        // Log all available clipboard types for debugging
        if let types = pasteboard.types {
            let typeList = types.map { $0.rawValue }.joined(separator: ", ")
            Logger.debug("SlackContentParser: Clipboard types available: \(typeList)", category: Logger.analysis)

            // Check for interesting types
            for type in types {
                if type.rawValue.contains("slack") || type.rawValue.contains("chromium") || type.rawValue.contains("tinyspeck") {
                    Logger.info("SlackContentParser: Found interesting clipboard type: \(type.rawValue)", category: Logger.analysis)
                }
            }
        }

        // Look for Quill Delta in org.chromium.web-custom-data
        guard let data = pasteboard.data(forType: Self.chromiumWebCustomDataType) else {
            Logger.debug("SlackContentParser: No org.chromium.web-custom-data on clipboard", category: Logger.analysis)
            return emptyResult
        }

        Logger.info("SlackContentParser: Found org.chromium.web-custom-data (\(data.count) bytes)", category: Logger.analysis)

        // Decode as UTF-16LE (Chromium format)
        guard let content = String(data: data, encoding: .utf16LittleEndian) else {
            // Try other encodings
            if let utf8Content = String(data: data, encoding: .utf8) {
                Logger.debug("SlackContentParser: Decoded as UTF-8 instead of UTF-16LE", category: Logger.analysis)
                return parseQuillDeltaContent(utf8Content, text: text)
            }
            Logger.debug("SlackContentParser: Failed to decode clipboard data", category: Logger.analysis)
            return emptyResult
        }

        Logger.debug("SlackContentParser: Decoded Chromium data (\(content.count) chars)", category: Logger.analysis)

        return parseQuillDeltaContent(content, text: text)
    }

    /// Parse the Quill Delta content string and extract exclusions
    private func parseQuillDeltaContent(_ content: String, text: String) -> [ExclusionRange] {
        var exclusions: [ExclusionRange] = []

        // Extract JSON from the content
        guard let jsonString = extractQuillDeltaJSON(from: content) else {
            Logger.debug("SlackContentParser: No Quill Delta JSON found in content", category: Logger.analysis)

            // Log what we found instead
            if content.contains("ops") {
                Logger.debug("SlackContentParser: Content contains 'ops' but couldn't extract JSON", category: Logger.analysis)
            }
            return exclusions
        }

        Logger.debug("SlackContentParser: Extracted Quill Delta JSON (\(jsonString.count) chars)", category: Logger.analysis)

        guard let jsonData = jsonString.data(using: .utf8) else {
            Logger.debug("SlackContentParser: Failed to convert JSON string to data", category: Logger.analysis)
            return exclusions
        }

        // Parse JSON
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let ops = json["ops"] as? [[String: Any]] else {
                Logger.debug("SlackContentParser: JSON doesn't have expected 'ops' structure", category: Logger.analysis)
                return exclusions
            }

            Logger.info("SlackContentParser: Parsing Quill Delta with \(ops.count) operations", category: Logger.analysis)

            var position = 0
            for (index, op) in ops.enumerated() {
                // Handle embedded objects (user, channel, emoji, date, etc.)
                // In Slack's Quill Delta, embedded objects have insert as a dictionary, not a string
                if let insertObject = op["insert"] as? [String: Any] {
                    let objectType = parseEmbeddedObject(insertObject, at: position, operationIndex: index)
                    if let type = objectType {
                        // Embedded objects typically represent 1 character position (rendered as a span)
                        // But we need to find the actual text representation
                        let embeddedLength = getEmbeddedObjectLength(type: type, object: insertObject, in: text, at: position)
                        Logger.info("SlackContentParser: Quill Delta: Found embedded '\(type)' at \(position), length: \(embeddedLength)", category: Logger.analysis)
                        if embeddedLength > 0 {
                            exclusions.append(ExclusionRange(location: position, length: embeddedLength))
                        }
                        position += embeddedLength
                    } else {
                        // Unknown embedded object, skip 1 position
                        position += 1
                    }
                    continue
                }

                // Handle regular text insert
                guard let insert = op["insert"] as? String else {
                    Logger.debug("SlackContentParser: Op \(index) has no string insert: \(op)", category: Logger.analysis)
                    continue
                }

                let insertLength = insert.count

                // Check for attributes
                if let attrs = op["attributes"] as? [String: Any] {
                    // Log all attributes for debugging
                    let attrKeys = attrs.keys.joined(separator: ", ")
                    Logger.debug("SlackContentParser: Op \(index) attributes: \(attrKeys)", category: Logger.analysis)

                    // Check for slackmention attribute (Slack's format for @mentions and #channels)
                    // Format: {"slackmention": {"id": "U123...", "label": "@username", "mention": false, "unverified": false}}
                    if let slackmention = attrs["slackmention"] as? [String: Any] {
                        let mentionId = slackmention["id"] as? String ?? ""
                        let label = slackmention["label"] as? String ?? ""
                        var mentionType = "mention"

                        // Determine type based on ID prefix: U=user, C=channel, S=usergroup
                        if mentionId.hasPrefix("C") {
                            mentionType = "channel"
                        } else if mentionId.hasPrefix("S") {
                            mentionType = "usergroup"
                        } else if label == "@here" || label == "@channel" || label == "@everyone" {
                            mentionType = "broadcast"
                        }

                        Logger.info("SlackContentParser: Quill Delta: Found \(mentionType) at \(position)-\(position + insertLength), length: \(insertLength), id: '\(mentionId)'", category: Logger.analysis)
                        exclusions.append(ExclusionRange(location: position, length: insertLength))
                    }

                    // Check for link attribute (URLs)
                    if attrs["link"] is String {
                        Logger.info("SlackContentParser: Quill Delta: Found link at \(position)-\(position + insertLength), length: \(insertLength)", category: Logger.analysis)
                        exclusions.append(ExclusionRange(location: position, length: insertLength))
                    }

                    // Check for code attribute (inline code)
                    if let code = attrs["code"] as? Bool, code {
                        Logger.info("SlackContentParser: Quill Delta: Found inline code at \(position)-\(position + insertLength), length: \(insertLength)", category: Logger.analysis)
                        exclusions.append(ExclusionRange(location: position, length: insertLength))
                    }

                    // Check for code-block attribute
                    if attrs["code-block"] != nil {
                        Logger.info("SlackContentParser: Quill Delta: Found code block at \(position)-\(position + insertLength)", category: Logger.analysis)
                        exclusions.append(ExclusionRange(location: position, length: insertLength))
                    }

                    // Check for blockquote attribute
                    if attrs["blockquote"] != nil {
                        Logger.info("SlackContentParser: Quill Delta: Found blockquote at \(position)-\(position + insertLength)", category: Logger.analysis)
                        exclusions.append(ExclusionRange(location: position, length: insertLength))
                    }

                    // Detect text styling (bold, italic, underline, strikethrough)
                    // These are logged for completeness but NOT excluded - grammar errors should still be flagged
                    if let bold = attrs["bold"] as? Bool, bold {
                        Logger.info("SlackContentParser: Quill Delta: Found bold at \(position)-\(position + insertLength), length: \(insertLength)", category: Logger.analysis)
                    }
                    if let italic = attrs["italic"] as? Bool, italic {
                        Logger.info("SlackContentParser: Quill Delta: Found italic at \(position)-\(position + insertLength), length: \(insertLength)", category: Logger.analysis)
                    }
                    if let underline = attrs["underline"] as? Bool, underline {
                        Logger.info("SlackContentParser: Quill Delta: Found underline at \(position)-\(position + insertLength), length: \(insertLength)", category: Logger.analysis)
                    }
                    if let strike = attrs["strike"] as? Bool, strike {
                        Logger.info("SlackContentParser: Quill Delta: Found strikethrough at \(position)-\(position + insertLength), length: \(insertLength)", category: Logger.analysis)
                    }

                    // Detect list formatting (bullet, ordered)
                    // Logged for completeness but NOT excluded
                    if let list = attrs["list"] as? String {
                        Logger.info("SlackContentParser: Quill Delta: Found list (\(list)) at \(position)-\(position + insertLength)", category: Logger.analysis)
                    }
                }

                position += insertLength
            }

            Logger.info("SlackContentParser: Quill Delta parsing complete. Found \(exclusions.count) exclusions", category: Logger.analysis)

        } catch {
            Logger.debug("SlackContentParser: Failed to parse Quill Delta JSON: \(error)", category: Logger.analysis)
        }

        return exclusions
    }

    /// Parse a Slack embedded object (user mention, channel, emoji, date, etc.)
    /// Returns the type of object if recognized
    private func parseEmbeddedObject(_ object: [String: Any], at position: Int, operationIndex: Int) -> String? {
        // Log the embedded object for debugging
        Logger.debug("SlackContentParser: Op \(operationIndex) embedded object: \(object)", category: Logger.analysis)

        // Check for user mention: {"insert": {"user": "U12345"}}
        if let userId = object["user"] as? String {
            Logger.info("SlackContentParser: Found user mention embed: \(userId)", category: Logger.analysis)
            return "user"
        }

        // Check for channel reference: {"insert": {"channel": "C12345"}}
        if let channelId = object["channel"] as? String {
            Logger.info("SlackContentParser: Found channel embed: \(channelId)", category: Logger.analysis)
            return "channel"
        }

        // Check for broadcast: {"insert": {"broadcast": "here"}} or "channel" or "everyone"
        if let broadcast = object["broadcast"] as? String {
            Logger.info("SlackContentParser: Found broadcast embed: @\(broadcast)", category: Logger.analysis)
            return "broadcast"
        }

        // Check for emoji: {"insert": {"emoji": "smile"}}
        if let emoji = object["emoji"] as? String {
            Logger.debug("SlackContentParser: Found emoji embed: :\(emoji):", category: Logger.analysis)
            return "emoji"
        }

        // Check for Slack emoji: {"insert": {"slackemoji": {"text": ":smile:"}}}
        if let slackemoji = object["slackemoji"] as? [String: Any] {
            let text = slackemoji["text"] as? String ?? ""
            Logger.debug("SlackContentParser: Found slackemoji embed: \(text)", category: Logger.analysis)
            return "emoji"
        }

        // Check for date: {"insert": {"date": 1234567890}}
        if object["date"] != nil {
            Logger.debug("SlackContentParser: Found date embed", category: Logger.analysis)
            return "date"
        }

        // Check for link (URL card): {"insert": {"link": "https://..."}}
        if let link = object["link"] as? String {
            Logger.info("SlackContentParser: Found link embed: \(link)", category: Logger.analysis)
            return "link"
        }

        // Check for usergroup: {"insert": {"usergroup": "S12345"}}
        if let usergroup = object["usergroup"] as? String {
            Logger.info("SlackContentParser: Found usergroup embed: \(usergroup)", category: Logger.analysis)
            return "usergroup"
        }

        // Unknown embedded object type
        let keys = object.keys.joined(separator: ", ")
        Logger.debug("SlackContentParser: Unknown embedded object type. Keys: \(keys)", category: Logger.analysis)
        return nil
    }

    /// Get the length of an embedded object's text representation
    /// This tries to find the matching text in the source text
    private func getEmbeddedObjectLength(type: String, object: [String: Any], in text: String, at position: Int) -> Int {
        // Default to 1 if we can't determine the length
        // Slack typically renders embedded objects as short strings
        switch type {
        case "user":
            // User mentions are rendered as @username - find by looking for @
            if let matchRange = findMentionAt(position: position, in: text, prefix: "@") {
                return matchRange.length
            }
            return 1

        case "channel":
            // Channels are rendered as #channel-name - find by looking for #
            if let matchRange = findMentionAt(position: position, in: text, prefix: "#") {
                return matchRange.length
            }
            return 1

        case "broadcast":
            // Broadcasts are @here, @channel, @everyone
            if let broadcast = object["broadcast"] as? String {
                return broadcast.count + 1 // +1 for @
            }
            return 1

        case "emoji":
            // Emojis are typically 1-2 characters (unicode emoji or custom emoji rendered as :name:)
            return 1

        case "date":
            // Dates can vary in length depending on format
            return 10 // Reasonable default

        case "link", "usergroup":
            // Links and usergroups vary in length
            return 1

        default:
            return 1
        }
    }

    /// Find a mention (@user or #channel) starting near the given position
    private func findMentionAt(position: Int, in text: String, prefix: String) -> ExclusionRange? {
        // Look in a window around the position for the prefix
        let searchStart = max(0, position - 5)
        let searchEnd = min(text.count, position + 50)

        guard searchStart < searchEnd,
              let startIndex = text.index(text.startIndex, offsetBy: searchStart, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: searchEnd, limitedBy: text.endIndex) else {
            return nil
        }

        let searchWindow = String(text[startIndex..<endIndex])

        // Find the prefix in the window
        guard let prefixRange = searchWindow.range(of: prefix) else {
            return nil
        }

        // Find the end of the mention (space, newline, or punctuation)
        let afterPrefix = searchWindow[prefixRange.upperBound...]
        var mentionEnd = afterPrefix.startIndex

        for char in afterPrefix {
            if char.isWhitespace || char.isPunctuation && char != "_" && char != "-" {
                break
            }
            mentionEnd = afterPrefix.index(after: mentionEnd)
        }

        let mention = String(searchWindow[prefixRange.lowerBound..<mentionEnd])
        let mentionStartInText = searchStart + searchWindow.distance(from: searchWindow.startIndex, to: prefixRange.lowerBound)

        return ExclusionRange(location: mentionStartInText, length: mention.count)
    }

    /// Extract Quill Delta JSON from Chromium web-custom-data content
    private func extractQuillDeltaJSON(from content: String) -> String? {
        // Look for JSON object containing ops array
        guard let opsRange = content.range(of: "{\"ops\"") else {
            // Also try with spaces
            guard let opsRange2 = content.range(of: "{ \"ops\"") else {
                return nil
            }
            return extractJSONObject(from: content, startingAt: opsRange2.lowerBound)
        }
        return extractJSONObject(from: content, startingAt: opsRange.lowerBound)
    }

    /// Extract a complete JSON object from a string
    private func extractJSONObject(from text: String, startingAt start: String.Index) -> String? {
        var depth = 0
        var endIndex = start

        for (i, char) in text[start...].enumerated() {
            if char == "{" { depth += 1 }
            else if char == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = text.index(start, offsetBy: i + 1)
                    break
                }
            }
        }

        guard depth == 0 else { return nil }
        return String(text[start..<endIndex])
    }

    /// Check for AXLinkUIElements attribute (list of link elements)
    private func detectLinksViaAXLinkUIElements(element: AXUIElement, text: String) -> [ExclusionRange] {
        var exclusions: [ExclusionRange] = []

        // Try to get link elements directly
        var linksRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXLinkUIElements" as CFString, &linksRef) == .success,
           let links = linksRef as? [AXUIElement] {
            Logger.info("SlackContentParser: Found \(links.count) link elements via AXLinkUIElements", category: Logger.analysis)

            for link in links {
                // Get link text
                var valueRef: CFTypeRef?
                let linkText: String
                if AXUIElementCopyAttributeValue(link, kAXValueAttribute as CFString, &valueRef) == .success,
                   let v = valueRef as? String {
                    linkText = v
                } else if AXUIElementCopyAttributeValue(link, kAXTitleAttribute as CFString, &valueRef) == .success,
                          let t = valueRef as? String {
                    linkText = t
                } else {
                    linkText = ""
                }

                // Get URL
                var urlRef: CFTypeRef?
                var linkType = "link"
                if AXUIElementCopyAttributeValue(link, kAXURLAttribute as CFString, &urlRef) == .success {
                    let urlString: String
                    if let u = urlRef as? URL { urlString = u.absoluteString }
                    else if let u = urlRef as? String { urlString = u }
                    else { urlString = "" }

                    if urlString.contains("slack://user") {
                        linkType = "mention"
                    } else if urlString.contains("slack://channel") {
                        linkType = "channel"
                    }
                }

                if !linkText.isEmpty, let range = text.range(of: linkText) {
                    let location = text.distance(from: text.startIndex, to: range.lowerBound)
                    Logger.info("SlackContentParser: AXLinkUIElements: Found \(linkType) '\(linkText)' at \(location)", category: Logger.analysis)
                    exclusions.append(ExclusionRange(location: location, length: linkText.count))
                }
            }
        } else {
            Logger.debug("SlackContentParser: AXLinkUIElements not available", category: Logger.analysis)
        }

        // Also try AXTextLinks
        var textLinksRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXTextLinks" as CFString, &textLinksRef) == .success,
           let textLinks = textLinksRef as? [AXUIElement] {
            Logger.info("SlackContentParser: Found \(textLinks.count) text links via AXTextLinks", category: Logger.analysis)
        }

        return exclusions
    }

    /// Dump element tree for debugging - shows what AX attributes Slack exposes
    private func dumpElementTree(_ element: AXUIElement, text: String, depth: Int) {
        guard depth < 5 else { return } // Limit depth

        let indent = String(repeating: "  ", count: depth)

        // Get role
        var roleRef: CFTypeRef?
        let role = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success
            ? (roleRef as? String ?? "?") : "?"

        // Get subrole
        var subroleRef: CFTypeRef?
        let subrole = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success
            ? (subroleRef as? String ?? "") : ""

        // Get value (text content)
        var valueRef: CFTypeRef?
        let value = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success
            ? String((valueRef as? String ?? "").prefix(40)).replacingOccurrences(of: "\n", with: "\\n") : ""

        // Get URL (for links, mentions, channels)
        var urlRef: CFTypeRef?
        var url = ""
        if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef) == .success {
            if let u = urlRef as? URL { url = u.absoluteString }
            else if let u = urlRef as? String { url = u }
        }

        // Get description
        var descRef: CFTypeRef?
        let desc = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success
            ? (descRef as? String ?? "") : ""

        // Get AXBlockQuoteLevel
        var levelRef: CFTypeRef?
        let quoteLevel = AXUIElementCopyAttributeValue(element, "AXBlockQuoteLevel" as CFString, &levelRef) == .success
            ? (levelRef as? Int ?? 0) : 0

        // Build log line
        var info = "\(indent)[\(role)"
        if !subrole.isEmpty { info += "/\(subrole)" }
        info += "]"
        if !value.isEmpty { info += " val='\(value)'" }
        if !url.isEmpty { info += " url='\(url)'" }
        if !desc.isEmpty { info += " desc='\(desc)'" }
        if quoteLevel > 0 { info += " quoteLevel=\(quoteLevel)" }

        Logger.debug("SlackContentParser: \(info)", category: Logger.analysis)

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children.prefix(15) { // Limit children per level
                dumpElementTree(child, text: text, depth: depth + 1)
            }
        }
    }

    /// Detect links (mentions, channels, URLs) via AXLink role or URL attributes
    private func detectLinks(in element: AXUIElement, text: String) -> [ExclusionRange] {
        var linkRanges: [ExclusionRange] = []

        // Check if this element is a link
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           role == "AXLink" {

            // Get link text
            var valueRef: CFTypeRef?
            let linkText: String
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let v = valueRef as? String {
                linkText = v
            } else {
                // Try AXTitle for links
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let t = titleRef as? String {
                    linkText = t
                } else {
                    linkText = ""
                }
            }

            // Get URL to determine type
            var urlRef: CFTypeRef?
            var linkType = "link"
            if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef) == .success {
                let urlString: String
                if let u = urlRef as? URL { urlString = u.absoluteString }
                else if let u = urlRef as? String { urlString = u }
                else { urlString = "" }

                if urlString.contains("slack://user") || urlString.contains("@") {
                    linkType = "mention"
                } else if urlString.contains("slack://channel") || urlString.contains("#") {
                    linkType = "channel"
                }
            }

            if !linkText.isEmpty {
                // Find position of link text in parent text
                if let range = text.range(of: linkText) {
                    let location = text.distance(from: text.startIndex, to: range.lowerBound)
                    let length = linkText.count
                    Logger.info("SlackContentParser: Found \(linkType) at \(location)-\(location + length), text: '\(linkText)'", category: Logger.analysis)
                    linkRanges.append(ExclusionRange(location: location, length: length))
                }
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                linkRanges.append(contentsOf: detectLinks(in: child, text: text))
            }
        }

        return linkRanges
    }

    /// Detect inline code using AXCodeStyleGroup subrole
    private func detectCodeStyleGroups(in element: AXUIElement, text: String) -> [ExclusionRange] {
        var codeRanges: [ExclusionRange] = []

        // Get child elements and check their subroles
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return codeRanges
        }

        for child in children {
            // Check subrole for code style
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String,
               subrole == "AXCodeStyleGroup" {

                // Get the text content - may be in child AXStaticText elements
                let codeText = getTextFromElement(child)

                if !codeText.isEmpty {
                    // Find position of code text in parent text
                    if let range = text.range(of: codeText) {
                        let location = text.distance(from: text.startIndex, to: range.lowerBound)
                        let length = codeText.count
                        Logger.info("SlackContentParser: Found inline code at \(location)-\(location + length), text: '\(codeText.prefix(50))'", category: Logger.analysis)
                        codeRanges.append(ExclusionRange(location: location, length: length))
                    } else {
                        Logger.debug("SlackContentParser: Found inline code but text not found in parent: '\(codeText.prefix(50))'", category: Logger.analysis)
                    }
                } else {
                    Logger.debug("SlackContentParser: Found AXCodeStyleGroup but no text content", category: Logger.analysis)
                }
            }

            // Recursively check child's children
            codeRanges.append(contentsOf: detectCodeStyleGroups(in: child, text: text))
        }

        return codeRanges
    }

    /// Get text from an element, checking both AXValue and child AXStaticText elements
    private func getTextFromElement(_ element: AXUIElement) -> String {
        // First try AXValue on the element itself
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String,
           !value.isEmpty {
            return value
        }

        // Then try to concatenate text from child AXStaticText elements
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return ""
        }

        var combinedText = ""
        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String,
               role == "AXStaticText" {
                var childValueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &childValueRef) == .success,
                   let childValue = childValueRef as? String {
                    combinedText += childValue
                }
            }
        }

        return combinedText
    }

    /// Detect block quotes using AXBlockQuoteLevel attribute
    private func detectBlockQuotes(in element: AXUIElement, text: String) -> [ExclusionRange] {
        var quoteRanges: [ExclusionRange] = []

        // Check for block quote level attribute
        var levelRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXBlockQuoteLevel" as CFString, &levelRef) == .success,
           let level = levelRef as? Int,
           level > 0 {
            // This element is a block quote - get its text content
            var valueRef: CFTypeRef?
            let quoteText: String
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String {
                quoteText = value
            } else {
                quoteText = "(no text)"
            }

            if let range = getTextRange(for: element, in: element) {
                Logger.info("SlackContentParser: Found block quote at level \(level), range \(range.location)-\(range.location + range.length), text: '\(quoteText.prefix(50))'", category: Logger.analysis)
                quoteRanges.append(range)
            } else {
                // Still log even if we couldn't get the range
                Logger.debug("SlackContentParser: Found block quote at level \(level) but couldn't determine range, text: '\(quoteText.prefix(50))'", category: Logger.analysis)
            }
        }

        // Check children for block quotes
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return quoteRanges
        }

        for child in children {
            quoteRanges.append(contentsOf: detectBlockQuotes(in: child, text: text))
        }

        return quoteRanges
    }

    /// Get text range for a child element within the parent
    private func getTextRange(for child: AXUIElement, in parent: AXUIElement) -> ExclusionRange? {
        // Try to get the text content and position
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef) == .success,
              let childText = valueRef as? String else {
            return nil
        }

        // Get parent text for position lookup
        var parentValueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXValueAttribute as CFString, &parentValueRef) == .success,
              let parentText = parentValueRef as? String else {
            return nil
        }

        // Find position of child text in parent
        if let range = parentText.range(of: childText) {
            let location = parentText.distance(from: parentText.startIndex, to: range.lowerBound)
            let length = childText.count
            return ExclusionRange(location: location, length: length)
        }

        return nil
    }

    /// Clear cached exclusions (call when text changes significantly)
    func clearExclusionCache() {
        cachedExclusions = []
        exclusionTextHash = 0
        // Don't reset Quill Delta - it's expensive and should persist
        // hasExtractedQuillDelta = false
        // quillDeltaExclusions = []
    }

    /// Reset all state (call when monitoring a new element)
    func resetState() {
        cachedExclusions = []
        exclusionTextHash = 0
        hasExtractedQuillDelta = false
        quillDeltaExclusions = []
        hasDumpedElementTree = false
        stopClipboardMonitoring()
    }

    // MARK: - Clipboard Monitoring

    /// Start monitoring the clipboard for Quill Delta data
    /// This allows us to capture exclusions when the user copies text from Slack
    func startClipboardMonitoring(for text: String) {
        guard clipboardMonitorTimer == nil else { return }

        lastClipboardChangeCount = NSPasteboard.general.changeCount
        Logger.info("SlackContentParser: Starting clipboard monitoring (initial change count: \(lastClipboardChangeCount))", category: Logger.analysis)

        clipboardMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkClipboardForQuillDelta(text: text)
        }
    }

    /// Stop clipboard monitoring
    func stopClipboardMonitoring() {
        clipboardMonitorTimer?.invalidate()
        clipboardMonitorTimer = nil
    }

    /// Check if clipboard has changed and contains Quill Delta data
    private func checkClipboardForQuillDelta(text: String) {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastClipboardChangeCount else { return }

        lastClipboardChangeCount = currentChangeCount
        Logger.info("SlackContentParser: Clipboard changed (count: \(currentChangeCount))", category: Logger.analysis)

        // Check if org.chromium.web-custom-data is present
        if let types = pasteboard.types {
            let hasQuillDelta = types.contains(Self.chromiumWebCustomDataType)
            Logger.info("SlackContentParser: Has org.chromium.web-custom-data: \(hasQuillDelta)", category: Logger.analysis)

            if hasQuillDelta {
                // Parse the Quill Delta and update exclusions
                let newExclusions = parseQuillDeltaFromClipboard(text: text)
                if !newExclusions.isEmpty {
                    quillDeltaExclusions = newExclusions
                    Logger.info("SlackContentParser: Updated exclusions from clipboard: \(newExclusions.count) ranges", category: Logger.analysis)

                    // Clear cached exclusions to force re-evaluation
                    cachedExclusions = []
                    exclusionTextHash = 0
                }
            }

            // Log all types for debugging
            for type in types {
                if type.rawValue.contains("slack") || type.rawValue.contains("chromium") || type.rawValue.contains("tinyspeck") {
                    if let data = pasteboard.data(forType: type) {
                        Logger.info("SlackContentParser: Clipboard type '\(type.rawValue)': \(data.count) bytes", category: Logger.analysis)
                    }
                }
            }
        }
    }

    /// Log current clipboard state for debugging (without exposing content)
    func logClipboardContents() {
        let pasteboard = NSPasteboard.general

        guard let types = pasteboard.types else {
            Logger.debug("SlackContentParser: Clipboard empty", category: Logger.analysis)
            return
        }

        // Check specifically for Quill Delta
        let hasQuillDelta = types.contains(Self.chromiumWebCustomDataType)
        let slackTypes = types.filter { $0.rawValue.contains("slack") || $0.rawValue.contains("chromium") }

        Logger.info("SlackContentParser: Clipboard has \(types.count) types, \(slackTypes.count) Slack-related, Quill Delta: \(hasQuillDelta)", category: Logger.analysis)
    }

    /// Visual underlines enabled/disabled from AppConfiguration
    var disablesVisualUnderlines: Bool {
        return !config.features.visualUnderlinesEnabled
    }

    /// Slack's selection API treats newlines as zero-width, but AXValue includes them.
    /// This is because Slack replaces emojis with \n\n and adds \n for line breaks.
    /// Each newline needs to be subtracted from position for accurate selection.
    func selectionOffset(at position: Int, in text: String) -> Int {
        guard position > 0 else { return 0 }

        let endIndex = min(position, text.count)
        guard let endStringIndex = text.index(text.startIndex, offsetBy: endIndex, limitedBy: text.endIndex) else {
            return 0
        }

        let prefix = String(text[..<endStringIndex])
        return prefix.filter { $0 == "\n" }.count
    }

    /// Diagnostic result from probing Slack's AX capabilities
    private static var diagnosticResult: NotionDiagnosticResult?
    private static var hasRunDiagnostic = false

    /// UI contexts within Slack with different rendering characteristics
    private enum SlackContext: String {
        case messageInput = "message-input"
        case searchBar = "search-bar"
        case threadReply = "thread-reply"
        case editMessage = "edit-message"
        case unknown = "unknown"
    }

    func detectUIContext(element: AXUIElement) -> String? {
        var descValue: CFTypeRef?
        var identifierValue: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)

        let description = descValue as? String
        let identifier = identifierValue as? String

        if let desc = description?.lowercased() {
            if desc.contains("search") {
                return SlackContext.searchBar.rawValue
            } else if desc.contains("thread") || desc.contains("reply") {
                return SlackContext.threadReply.rawValue
            } else if desc.contains("edit") {
                return SlackContext.editMessage.rawValue
            } else if desc.contains("message") || desc.contains("compose") {
                return SlackContext.messageInput.rawValue
            }
        }

        if let id = identifier?.lowercased() {
            if id.contains("search") {
                return SlackContext.searchBar.rawValue
            } else if id.contains("thread") {
                return SlackContext.threadReply.rawValue
            } else if id.contains("composer") || id.contains("message") {
                return SlackContext.messageInput.rawValue
            }
        }

        return SlackContext.messageInput.rawValue
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Use font size from AppConfiguration
        return config.fontConfig.defaultSize
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // Base multiplier from AppConfiguration, with context-specific adjustments
        let baseMultiplier = config.fontConfig.spacingMultiplier
        guard let ctx = context else {
            return baseMultiplier
        }

        let slackContext = SlackContext(rawValue: ctx) ?? .unknown

        switch slackContext {
        case .messageInput, .threadReply, .editMessage, .unknown:
            return baseMultiplier
        case .searchBar:
            return baseMultiplier + 0.01  // Slightly wider for search bar
        }
    }

    func horizontalPadding(context: String?) -> CGFloat {
        // Base padding from AppConfiguration, with context-specific adjustments
        let basePadding = config.horizontalPadding
        guard let ctx = context else {
            return basePadding
        }

        let slackContext = SlackContext(rawValue: ctx) ?? .unknown

        switch slackContext {
        case .searchBar:
            return basePadding + 4.0  // Extra padding for search bar
        default:
            return basePadding
        }
    }

    /// Use the multi-strategy PositionResolver for positioning
    /// This leverages TextMarkerStrategy which works well for Chromium/Electron apps
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String
    ) -> GeometryResult {
        // Run diagnostic ONCE to discover what AX APIs work for Slack
        if !Self.hasRunDiagnostic {
            Self.hasRunDiagnostic = true
            Self.diagnosticResult = AccessibilityBridge.runNotionDiagnostic(element)

            if let result = Self.diagnosticResult {
                Logger.info("SLACK DIAGNOSTIC SUMMARY:", category: Logger.analysis)
                Logger.info("  Best method: \(result.bestMethodDescription)", category: Logger.analysis)
                Logger.info("  Has working method: \(result.hasWorkingMethod)", category: Logger.analysis)
                Logger.info("  Supported param attrs: \(result.supportedParamAttributes.joined(separator: ", "))")
            }
        }

        // Delegate to the PositionResolver which tries strategies in order:
        // 1. TextMarkerStrategy (opaque markers - works for Chromium)
        // 2. RangeBoundsStrategy (CFRange bounds)
        // 3. ElementTreeStrategy (child element traversal)
        // 4. LineIndexStrategy, OriginStrategy, AnchorSearchStrategy
        // 5. FontMetricsStrategy (app-specific font estimation)
        // 6. SelectionBoundsStrategy, NavigationStrategy (last resort)
        return PositionResolver.shared.resolvePosition(
            for: errorRange,
            in: element,
            text: text,
            parser: self,
            bundleID: bundleIdentifier
        )
    }

    /// Bounds adjustment - delegates to PositionResolver for consistent multi-strategy approach
    /// This is called by ErrorOverlayWindow.estimateErrorBounds() for legacy compatibility
    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        let context = detectUIContext(element: element)
        let fontSize = estimatedFontSize(context: context)

        // Try cursor-anchored positioning first (like Notion)
        if let cursorResult = getCursorAnchoredPosition(
            element: element,
            errorRange: errorRange,
            textBeforeError: textBeforeError,
            errorText: errorText,
            fullText: fullText,
            context: context,
            fontSize: fontSize
        ) {
            return cursorResult
        }

        // Try direct AX bounds for the error range
        if let axBounds = getSlackValidatedBounds(element: element, range: errorRange) {
            return AdjustedBounds(
                position: NSPoint(x: axBounds.origin.x, y: axBounds.origin.y),
                errorWidth: axBounds.width,
                confidence: 0.9,
                uiContext: context,
                debugInfo: "Slack AX bounds (direct)"
            )
        }

        // Fall back to text measurement with graceful degradation
        return getTextMeasurementFallback(
            element: element,
            errorRange: errorRange,
            textBeforeError: textBeforeError,
            errorText: errorText,
            context: context,
            fontSize: fontSize
        )
    }

    // MARK: - Cursor-Anchored Positioning

    /// Get cursor position and use it as anchor for more reliable positioning
    private func getCursorAnchoredPosition(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String,
        context: String?,
        fontSize: CGFloat
    ) -> AdjustedBounds? {
        // Get cursor position
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
              let rangeRef = selectedRangeValue,
              let selectedRange = safeAXValueGetRange(rangeRef) else {
            return nil
        }

        let cursorPosition = selectedRange.location

        // Try to get bounds at cursor position
        var cursorBounds: CGRect?

        // Method 1: AXInsertionPointFrame
        var insertionPointValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointFrame" as CFString, &insertionPointValue) == .success,
           let axValue = insertionPointValue,
           let frame = safeAXValueGetRect(axValue) {
            if frame.width >= 0 && frame.height > GeometryConstants.minimumBoundsSize && frame.height < GeometryConstants.conservativeMaxLineHeight {
                cursorBounds = frame
                Logger.debug("Slack: Got cursor bounds from AXInsertionPointFrame: \(frame)", category: Logger.ui)
            }
        }

        // Method 2: Bounds for character at cursor
        if cursorBounds == nil {
            if let bounds = getSlackValidatedBounds(element: element, range: NSRange(location: cursorPosition, length: 1)) {
                cursorBounds = bounds
                Logger.debug("Slack: Got cursor bounds from single char: \(bounds)", category: Logger.ui)
            }
        }

        // Method 3: Bounds for character before cursor
        if cursorBounds == nil && cursorPosition > 0 {
            if let bounds = getSlackValidatedBounds(element: element, range: NSRange(location: cursorPosition - 1, length: 1)) {
                let cursor = CGRect(
                    x: bounds.origin.x + bounds.width,
                    y: bounds.origin.y,
                    width: 1,
                    height: bounds.height
                )
                cursorBounds = cursor
                Logger.debug("Slack: Got cursor bounds from prev char: \(cursor)", category: Logger.ui)
            }
        }

        guard let cursor = cursorBounds else {
            return nil
        }

        // Calculate error position relative to cursor
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let multiplier = spacingMultiplier(context: context)

        let errorWidth = max((errorText as NSString).size(withAttributes: attributes).width * multiplier, 20.0)

        // Calculate X offset from cursor to error
        let charsBetween = errorRange.location - cursorPosition
        var xPosition: CGFloat

        if charsBetween >= 0 {
            // Error is after cursor
            let textBetween = String(fullText.dropFirst(cursorPosition).prefix(charsBetween))
            let offsetWidth = (textBetween as NSString).size(withAttributes: attributes).width * multiplier
            xPosition = cursor.origin.x + offsetWidth
        } else {
            // Error is before cursor
            let textBetween = String(fullText.dropFirst(errorRange.location).prefix(-charsBetween))
            let offsetWidth = (textBetween as NSString).size(withAttributes: attributes).width * multiplier
            xPosition = cursor.origin.x - offsetWidth
        }

        Logger.debug("Slack: Cursor-anchored position - cursor=\(cursorPosition), error=\(errorRange.location), x=\(xPosition)", category: Logger.ui)

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: cursor.origin.y),
            errorWidth: errorWidth,
            confidence: 0.80,
            uiContext: context,
            debugInfo: "Slack cursor-anchored (cursorPos: \(cursorPosition), charsBetween: \(charsBetween))"
        )
    }

    // MARK: - AX Bounds Helpers

    /// Get validated bounds with Slack-specific origin check
    /// Slack's Electron app sometimes returns negative coordinates
    private func getSlackValidatedBounds(element: AXUIElement, range: NSRange) -> CGRect? {
        guard let bounds = AccessibilityBridge.getBoundsForRange(range, in: element) else {
            return nil
        }

        // Slack-specific: reject negative or zero origin (Electron bug)
        guard bounds.origin.x > 0 && bounds.origin.y > 0 else {
            return nil
        }

        return bounds
    }

    // MARK: - Text Measurement Fallback

    private func getTextMeasurementFallback(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        context: String?,
        fontSize: CGFloat
    ) -> AdjustedBounds? {
        guard let elementFrame = getSlackElementFrame(element: element) else {
            Logger.warning("Slack: Failed to get element frame for text measurement fallback", category: Logger.analysis)
            return nil
        }

        // Use Lato font if available (Slack's actual font), otherwise fall back to system font
        // Apply a multiplier to correct for font rendering differences between macOS and Chromium
        let font: NSFont
        let multiplier: CGFloat

        if let latoFont = NSFont(name: "Lato-Regular", size: fontSize) ??
                          NSFont(name: "Lato", size: fontSize) {
            font = latoFont
            // Lato renders almost identically, minimal correction needed
            multiplier = 0.99
            Logger.debug("Slack: Using Lato font for text measurement", category: Logger.ui)
        } else {
            // Fall back to system font with Chromium rendering correction
            font = NSFont.systemFont(ofSize: fontSize)
            // Chromium's text rendering is narrower than macOS for system font
            multiplier = spacingMultiplier(context: context)
            Logger.debug("Slack: Lato not found, using system font with multiplier \(multiplier)", category: Logger.ui)
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let padding = horizontalPadding(context: context)

        // Calculate line height for Slack's message input
        let lineHeight: CGFloat = fontSize * 1.4  // ~21px for 15pt font

        // Estimate text width per line to determine wrapping
        // Slack's message input has internal padding on both sides
        let availableWidth = elementFrame.width - (padding * 2) - 20  // Extra margin for safety

        // Calculate which line the error starts on by simulating text wrapping
        let textBeforeWidth = (textBeforeError as NSString).size(withAttributes: attributes).width * multiplier
        let errorLine = Int(textBeforeWidth / availableWidth)

        // Calculate X position on that line (accounting for wrapping)
        let xOffsetOnLine = textBeforeWidth.truncatingRemainder(dividingBy: availableWidth)
        let xPosition = elementFrame.origin.x + padding + xOffsetOnLine

        // Calculate error width (may wrap to next line, but we'll underline just the visible part)
        let baseErrorWidth = (errorText as NSString).size(withAttributes: attributes).width
        let adjustedErrorWidth = max(baseErrorWidth * multiplier, 20.0)

        // Y position: In Quartz coordinates, Y increases downward from top of screen
        // Element's origin.y is the TOP of the element in Quartz
        // First line of text starts after some top padding (~8px), then each subsequent line is lineHeight lower
        let topPadding: CGFloat = 8.0
        let yPosition = elementFrame.origin.y + topPadding + (CGFloat(errorLine) * lineHeight) + (lineHeight * 0.85)

        // GRACEFUL DEGRADATION: Text measurement is less reliable
        let confidence: Double = 0.60

        Logger.debug("Slack: Text measurement - line=\(errorLine), xOffset=\(xOffsetOnLine), x=\(xPosition), y=\(yPosition), availableWidth=\(availableWidth)", category: Logger.ui)

        return AdjustedBounds(
            position: NSPoint(x: xPosition, y: yPosition),
            errorWidth: adjustedErrorWidth,
            confidence: confidence,
            uiContext: context,
            debugInfo: "Slack text measurement (line: \(errorLine), multiplier: \(multiplier))"
        )
    }

    // MARK: - Element Frame

    /// Get element frame with Slack-specific workaround for negative X values
    private func getSlackElementFrame(element: AXUIElement) -> CGRect? {
        guard var frame = AccessibilityBridge.getElementFrame(element) else {
            return nil
        }

        // Slack's Electron-based AX implementation sometimes returns negative X values
        if frame.origin.x < 0 {
            if let windowFrame = getSlackWindowFrame(element: element, elementPosition: frame.origin) {
                let leftPadding: CGFloat = 20.0
                frame.origin.x = windowFrame.origin.x + leftPadding
                // Keep original Y and size
            }
        }

        return frame
    }

    private func getSlackWindowFrame(element: AXUIElement, elementPosition: CGPoint) -> CGRect? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let elementY = elementPosition.y
        var candidateWindows: [(CGRect, String)] = []

        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  windowPID == pid,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }

            let windowFrame = CGRect(x: x, y: y, width: width, height: height)
            let windowName = (windowInfo[kCGWindowName as String] as? String) ?? "Unknown"

            candidateWindows.append((windowFrame, windowName))

            let windowTop = y
            let windowBottom = y + height

            if elementY >= windowTop && elementY <= windowBottom {
                return windowFrame
            }
        }

        // Return largest window if no exact match
        if let largest = candidateWindows.max(by: { $0.0.width * $0.0.height < $1.0.width * $1.0.height }) {
            return largest.0
        }

        return nil
    }
}
