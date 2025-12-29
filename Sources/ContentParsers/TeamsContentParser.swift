//
//  TeamsContentParser.swift
//  TextWarden
//
//  Microsoft Teams-specific content parser.
//  Teams is a Chromium-based app (like Slack) with similar AX tree structure.
//  Child AXStaticText elements support AXBoundsForRange for positioning.
//
//  FORMATTED CONTENT HANDLING:
//  Teams supports message formatting similar to Slack. We exclude certain content
//  from grammar checking using AX attribute detection:
//  - EXCLUDED: Code blocks, blockquotes, links, mentions (@user), channels (#channel)
//  - CHECKED: Bold, italic, underline, strikethrough (grammar errors should be flagged)
//

import Foundation
import AppKit

/// Microsoft Teams-specific content parser
/// Uses TeamsStrategy for positioning via child element AXBoundsForRange.
/// Detects formatted content (code blocks, links, mentions) for exclusion.
class TeamsContentParser: ContentParser {
    let bundleIdentifier = "com.microsoft.teams2"
    let parserName = "Teams"

    /// Cached exclusion ranges from AX-based detection
    private var cachedExclusions: [ExclusionRange] = []

    /// Text hash for which exclusions were extracted
    private var exclusionTextHash: Int = 0

    /// Cached configuration from AppRegistry
    private var config: AppConfiguration {
        AppRegistry.shared.configuration(for: bundleIdentifier)
    }

    /// Visual underlines status from config
    var disablesVisualUnderlines: Bool {
        return !config.features.visualUnderlinesEnabled
    }

    /// UI contexts within Teams
    private enum TeamsContext: String {
        case messageInput = "message-input"
        case searchBar = "search-bar"
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
                return TeamsContext.searchBar.rawValue
            } else if desc.contains("message") || desc.contains("compose") || desc.contains("chat") {
                return TeamsContext.messageInput.rawValue
            }
        }

        if let id = identifier?.lowercased() {
            if id.contains("search") {
                return TeamsContext.searchBar.rawValue
            } else if id.contains("composer") || id.contains("message") || id.contains("chat") {
                return TeamsContext.messageInput.rawValue
            }
        }

        return TeamsContext.messageInput.rawValue
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        return config.fontConfig.defaultSize
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        return config.fontConfig.spacingMultiplier
    }

    func horizontalPadding(context: String?) -> CGFloat {
        return config.horizontalPadding
    }

    // MARK: - Exclusion Detection

    /// Extract exclusion ranges using Accessibility APIs
    /// Detects: code blocks, blockquotes, links, mentions, channels
    /// Does NOT exclude: bold, italic, underline, strikethrough (grammar should be checked)
    func extractExclusions(from element: AXUIElement, text: String) -> [ExclusionRange] {
        let textHash = text.hashValue

        // Return cached exclusions if text hasn't changed
        if textHash == exclusionTextHash && !cachedExclusions.isEmpty {
            Logger.debug("TeamsContentParser: Using cached exclusions (\(cachedExclusions.count) ranges)", category: Logger.analysis)
            return cachedExclusions
        }

        Logger.debug("TeamsContentParser: Extracting exclusions via Accessibility APIs", category: Logger.analysis)

        var exclusions: [ExclusionRange] = []

        // Method 1: AXAttributedStringForRange for AXBackgroundColor
        // Teams applies background color to: mentions, channels, code blocks
        let attributedExclusions = extractFromAttributedString(element: element, text: text)
        exclusions.append(contentsOf: attributedExclusions)

        // Method 2: Detect links via AXLink child elements
        let linkExclusions = detectLinks(in: element, text: text)
        exclusions.append(contentsOf: linkExclusions)

        // Method 3: Element tree traversal for additional detection
        // Check for inline code (AXCodeStyleGroup subrole)
        exclusions.append(contentsOf: detectCodeStyleGroups(in: element, text: text))

        // Check for blockquotes (AXBlockQuoteLevel attribute)
        exclusions.append(contentsOf: detectBlockQuotes(in: element, text: text))

        // Check for mentions (@user) and channels (#channel) in element tree
        exclusions.append(contentsOf: detectMentionsAndChannels(in: element, text: text))

        // Cache and return
        cachedExclusions = exclusions
        exclusionTextHash = textHash

        if !exclusions.isEmpty {
            Logger.info("TeamsContentParser: Detected \(exclusions.count) total exclusion ranges", category: Logger.analysis)
        }

        return exclusions
    }

    // MARK: - Attributed String Extraction

    /// Extract exclusions from attributed string using AXBackgroundColor
    /// Teams applies background color to mentions, channels, code blocks
    private func extractFromAttributedString(element: AXUIElement, text: String) -> [ExclusionRange] {
        var exclusions: [ExclusionRange] = []

        // Get character count
        var charCountRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &charCountRef) == .success,
              let charCount = charCountRef as? Int, charCount > 0 else {
            Logger.debug("TeamsContentParser: Could not get AXNumberOfCharacters", category: Logger.analysis)
            return exclusions
        }

        // Process text in adaptive chunks
        var offset = 0
        while offset < charCount {
            let remaining = charCount - offset
            guard let attrString = getAttributedStringAdaptive(element: element, offset: offset, maxLength: remaining) else {
                offset += 1
                continue
            }

            extractExclusionAttributes(from: attrString, globalOffset: offset, into: &exclusions)
            offset += attrString.length
        }

        // Merge adjacent exclusions
        let merged = mergeAdjacentExclusions(exclusions)

        if !merged.isEmpty {
            Logger.debug("TeamsContentParser: AXBackgroundColor found \(merged.count) exclusions", category: Logger.analysis)
        }

        return merged
    }

    /// Extract exclusion ranges based on AXBackgroundColor attribute
    private func extractExclusionAttributes(
        from attrString: NSAttributedString,
        globalOffset: Int,
        into exclusions: inout [ExclusionRange]
    ) {
        let backgroundColorKey = NSAttributedString.Key(rawValue: "AXBackgroundColor")
        let fullRange = NSRange(location: 0, length: attrString.length)

        attrString.enumerateAttribute(backgroundColorKey, in: fullRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let globalLocation = globalOffset + range.location
            exclusions.append(ExclusionRange(location: globalLocation, length: range.length))
        }
    }

    /// Adaptive chunk sizes for API robustness
    private static let adaptiveChunkSizes = [200, 100, 50, 25, 10, 5, 1]

    /// Get attributed string with adaptive chunk sizing
    private func getAttributedStringAdaptive(element: AXUIElement, offset: Int, maxLength: Int) -> NSAttributedString? {
        for chunkSize in Self.adaptiveChunkSizes {
            let length = min(chunkSize, maxLength)
            guard length > 0 else { continue }

            var cfRange = CFRange(location: offset, length: length)
            guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { continue }

            var attrStringRef: CFTypeRef?
            let result = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXAttributedStringForRangeParameterizedAttribute as CFString,
                rangeValue,
                &attrStringRef
            )

            if result == .success, let attrString = attrStringRef as? NSAttributedString {
                return attrString
            }
        }
        return nil
    }

    /// Merge adjacent or overlapping exclusion ranges
    private func mergeAdjacentExclusions(_ exclusions: [ExclusionRange]) -> [ExclusionRange] {
        guard !exclusions.isEmpty else { return [] }

        let sorted = exclusions.sorted { $0.location < $1.location }
        var merged: [ExclusionRange] = []
        var current = sorted[0]

        for next in sorted.dropFirst() {
            let currentEnd = current.location + current.length
            if next.location <= currentEnd {
                let newEnd = max(currentEnd, next.location + next.length)
                current = ExclusionRange(location: current.location, length: newEnd - current.location)
            } else {
                merged.append(current)
                current = next
            }
        }

        merged.append(current)
        return merged
    }

    // MARK: - Link Detection

    /// Maximum depth for link detection tree traversal
    private static let maxLinkDetectionDepth = 5

    private func detectLinks(in element: AXUIElement, text: String) -> [ExclusionRange] {
        return detectLinksRecursive(in: element, text: text, depth: 0)
    }

    private func detectLinksRecursive(in element: AXUIElement, text: String, depth: Int) -> [ExclusionRange] {
        guard depth < Self.maxLinkDetectionDepth else { return [] }

        var linkRanges: [ExclusionRange] = []

        var roleRef: CFTypeRef?
        let role: String? = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success
            ? roleRef as? String : nil

        if role == "AXLink" {
            var valueRef: CFTypeRef?
            var linkText: String = ""

            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let v = valueRef as? String, !v.isEmpty {
                linkText = v
            } else {
                linkText = getLinkTextFromChildren(element)
            }

            // Only detect actual URLs, not mentions/channels
            if !linkText.isEmpty && (linkText.hasPrefix("http://") || linkText.hasPrefix("https://")) {
                if let range = text.range(of: linkText) {
                    let location = text.distance(from: text.startIndex, to: range.lowerBound)
                    linkRanges.append(ExclusionRange(location: location, length: linkText.count))
                }
            }
            return linkRanges
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                linkRanges.append(contentsOf: detectLinksRecursive(in: child, text: text, depth: depth + 1))
            }
        }

        return linkRanges
    }

    private func getLinkTextFromChildren(_ element: AXUIElement) -> String {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return ""
        }

        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXStaticText" {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String, !value.isEmpty {
                    return value
                }
            }
            let nestedText = getLinkTextFromChildren(child)
            if !nestedText.isEmpty {
                return nestedText
            }
        }
        return ""
    }

    // MARK: - Code Style Detection

    /// Detect inline code using AXCodeStyleGroup subrole
    private func detectCodeStyleGroups(in element: AXUIElement, text: String) -> [ExclusionRange] {
        var codeRanges: [ExclusionRange] = []

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return codeRanges
        }

        for child in children {
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String, subrole == "AXCodeStyleGroup" {
                let codeText = getTextFromElement(child)
                if !codeText.isEmpty, let range = text.range(of: codeText) {
                    let location = text.distance(from: text.startIndex, to: range.lowerBound)
                    Logger.debug("TeamsContentParser: Found code block at \(location)-\(location + codeText.count)", category: Logger.analysis)
                    codeRanges.append(ExclusionRange(location: location, length: codeText.count))
                }
            }
            // Recurse
            codeRanges.append(contentsOf: detectCodeStyleGroups(in: child, text: text))
        }

        return codeRanges
    }

    private func getTextFromElement(_ element: AXUIElement) -> String {
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String, !value.isEmpty {
            return value
        }

        // Concatenate child AXStaticText
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return ""
        }

        var combined = ""
        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXStaticText" {
                var childValueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &childValueRef) == .success,
                   let childValue = childValueRef as? String {
                    combined += childValue
                }
            }
        }
        return combined
    }

    // MARK: - Block Quote Detection

    /// Detect block quotes using AXBlockQuoteLevel attribute
    private func detectBlockQuotes(in element: AXUIElement, text: String) -> [ExclusionRange] {
        var quoteRanges: [ExclusionRange] = []

        var levelRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXBlockQuoteLevel" as CFString, &levelRef) == .success,
           let level = levelRef as? Int, level > 0 {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let quoteText = valueRef as? String, !quoteText.isEmpty,
               let range = text.range(of: quoteText) {
                let location = text.distance(from: text.startIndex, to: range.lowerBound)
                Logger.debug("TeamsContentParser: Found blockquote at level \(level), \(location)-\(location + quoteText.count)", category: Logger.analysis)
                quoteRanges.append(ExclusionRange(location: location, length: quoteText.count))
            }
        }

        // Check children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                quoteRanges.append(contentsOf: detectBlockQuotes(in: child, text: text))
            }
        }

        return quoteRanges
    }

    // MARK: - Mentions and Channels Detection

    /// Detect mentions (@user) and channels (#channel) in element tree
    private func detectMentionsAndChannels(in element: AXUIElement, text: String) -> [ExclusionRange] {
        var exclusions: [ExclusionRange] = []

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return exclusions
        }

        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXStaticText" {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String, !value.isEmpty {
                    // Check for mention or channel prefix
                    let isMention = value.hasPrefix("@") && value.count > 1 && !value.contains("@.")
                    let isChannel = value.hasPrefix("#") && value.count > 1

                    if isMention || isChannel {
                        if let range = text.range(of: value) {
                            let location = text.distance(from: text.startIndex, to: range.lowerBound)
                            exclusions.append(ExclusionRange(location: location, length: value.count))
                        }
                    }
                }
            }
            // Recurse
            exclusions.append(contentsOf: detectMentionsAndChannels(in: child, text: text))
        }

        return exclusions
    }

    // MARK: - Cache Management

    /// Clear cached exclusions
    func clearExclusionCache() {
        cachedExclusions = []
        exclusionTextHash = 0
    }

    /// Reset all state
    func resetState() {
        cachedExclusions = []
        exclusionTextHash = 0
    }
}
