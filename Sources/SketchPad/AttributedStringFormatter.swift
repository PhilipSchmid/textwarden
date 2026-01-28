//
//  AttributedStringFormatter.swift
//  TextWarden
//
//  Helper for formatting operations using macOS 26 APIs
//  Works with NSAttributedString internally, converts to AttributedString for SwiftUI TextEditor
//

import AppKit
import SwiftUI

/// Formatting operations for NSAttributedString with conversion support for SwiftUI TextEditor
/// Uses NSAttributedString internally for reliable font manipulation, converts for SwiftUI
enum AttributedStringFormatter {
    // MARK: - Font Configuration

    static let bodyFontSize: CGFloat = 16
    static let h1FontSize: CGFloat = 28
    static let h2FontSize: CGFloat = 22
    static let h3FontSize: CGFloat = 18
    static let codeFontSize: CGFloat = 14

    /// Bullet prefix for lists
    static let bulletPrefix = "\u{2022}  " // Bullet + 2 spaces

    /// Block quote indent value
    static let blockQuoteIndent: CGFloat = 30

    // MARK: - Conversion Helpers

    /// Convert AttributedString to NSAttributedString
    static func toNSAttributedString(_ attributedString: AttributedString) -> NSAttributedString {
        NSAttributedString(attributedString)
    }

    /// Convert NSAttributedString to AttributedString
    static func toAttributedString(_ nsAttributedString: NSAttributedString) -> AttributedString {
        AttributedString(nsAttributedString)
    }

    // MARK: - Bold

    /// Toggle bold formatting on the selected range
    static func toggleBold(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        // Check if already bold
        var isBold = false
        string.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            if let font = value as? NSFont {
                isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                stop.pointee = true
            }
        }

        // Apply or remove bold
        string.beginEditing()
        string.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            if let font = value as? NSFont {
                let newFont: NSFont = if isBold {
                    NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                } else {
                    NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                string.addAttribute(.font, value: newFont, range: attrRange)
            }
        }
        string.endEditing()
    }

    // MARK: - Italic

    /// Toggle italic formatting on the selected range
    static func toggleItalic(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        // Check if already italic
        var isItalic = false
        string.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            if let font = value as? NSFont {
                isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                stop.pointee = true
            }
        }

        // Apply or remove italic
        string.beginEditing()
        string.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            if let font = value as? NSFont {
                let newFont: NSFont = if isItalic {
                    NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                } else {
                    NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                string.addAttribute(.font, value: newFont, range: attrRange)
            }
        }
        string.endEditing()
    }

    // MARK: - Underline

    /// Toggle underline formatting on the selected range
    static func toggleUnderline(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        // Check if already underlined
        var isUnderlined = false
        string.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
            if let style = value as? Int, style != 0 {
                isUnderlined = true
                stop.pointee = true
            }
        }

        // Apply or remove underline
        string.beginEditing()
        if isUnderlined {
            string.removeAttribute(.underlineStyle, range: range)
        } else {
            string.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        string.endEditing()
    }

    // MARK: - Strikethrough

    /// Toggle strikethrough formatting on the selected range
    static func toggleStrikethrough(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        // Check if already has strikethrough
        var hasStrikethrough = false
        string.enumerateAttribute(.strikethroughStyle, in: range, options: []) { value, _, stop in
            if let style = value as? Int, style != 0 {
                hasStrikethrough = true
                stop.pointee = true
            }
        }

        // Apply or remove strikethrough
        string.beginEditing()
        if hasStrikethrough {
            string.removeAttribute(.strikethroughStyle, range: range)
        } else {
            string.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        string.endEditing()
    }

    // MARK: - Headings

    /// Apply or remove heading formatting on a line range
    static func toggleHeading(level: Int, in string: inout NSMutableAttributedString, lineRange: NSRange) {
        guard lineRange.length > 0 else { return }

        let targetSize: CGFloat = switch level {
        case 1: h1FontSize
        case 2: h2FontSize
        case 3: h3FontSize
        default: bodyFontSize
        }

        // Check if already this heading level
        var isAlreadyHeading = false
        if lineRange.location < string.length {
            let attrs = string.attributes(at: lineRange.location, effectiveRange: nil)
            if let font = attrs[.font] as? NSFont {
                let size = font.pointSize
                switch level {
                case 1: isAlreadyHeading = size >= 27 && size <= 29
                case 2: isAlreadyHeading = size >= 21 && size <= 23
                case 3: isAlreadyHeading = size >= 17 && size <= 19
                default: break
                }
            }
        }

        string.beginEditing()
        if isAlreadyHeading {
            // Remove heading - reset to body font
            string.addAttribute(.font, value: NSFont.systemFont(ofSize: bodyFontSize), range: lineRange)
        } else {
            // Apply heading
            string.addAttribute(.font, value: NSFont.systemFont(ofSize: targetSize, weight: .bold), range: lineRange)
        }
        string.endEditing()
    }

    // MARK: - Lists

    /// Toggle bullet list for a line
    static func toggleBulletList(in string: inout NSMutableAttributedString, lineRange: NSRange) -> Bool {
        let lineText = (string.string as NSString).substring(with: lineRange)

        string.beginEditing()

        if lineText.hasPrefix(bulletPrefix) {
            // Remove bullet
            let bulletRange = NSRange(location: lineRange.location, length: bulletPrefix.count)
            string.replaceCharacters(in: bulletRange, with: "")
            string.endEditing()
            return false
        } else {
            // Add bullet
            let bulletString = NSAttributedString(string: bulletPrefix, attributes: [
                .font: NSFont.systemFont(ofSize: bodyFontSize),
            ])
            string.insert(bulletString, at: lineRange.location)
            string.endEditing()
            return true
        }
    }

    /// Toggle numbered list for a line
    static func toggleNumberedList(in string: inout NSMutableAttributedString, lineRange: NSRange, number: Int = 1) -> Bool {
        let lineText = (string.string as NSString).substring(with: lineRange)

        // Check if already numbered (pattern: ^\d+\.\s)
        let numberPattern = try? NSRegularExpression(pattern: "^\\d+\\.\\s")

        string.beginEditing()

        if let pattern = numberPattern,
           let match = pattern.firstMatch(in: lineText, range: NSRange(location: 0, length: lineText.count))
        {
            // Remove number prefix
            let removeRange = NSRange(location: lineRange.location, length: match.range.length)
            string.replaceCharacters(in: removeRange, with: "")
            string.endEditing()
            return false
        } else {
            // Add number
            let numberPrefix = "\(number). "
            let numberString = NSAttributedString(string: numberPrefix, attributes: [
                .font: NSFont.systemFont(ofSize: bodyFontSize),
            ])
            string.insert(numberString, at: lineRange.location)
            string.endEditing()
            return true
        }
    }

    // MARK: - Code

    /// Toggle inline code formatting on the selected range
    static func toggleInlineCode(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        // Check if already inline code (monospace + background)
        var isInlineCode = false
        if range.location < string.length {
            let attrs = string.attributes(at: range.location, effectiveRange: nil)
            if let font = attrs[.font] as? NSFont,
               font.fontDescriptor.symbolicTraits.contains(.monoSpace),
               attrs[.backgroundColor] != nil
            {
                isInlineCode = true
            }
        }

        string.beginEditing()
        if isInlineCode {
            // Remove inline code
            string.addAttribute(.font, value: NSFont.systemFont(ofSize: bodyFontSize), range: range)
            string.removeAttribute(.backgroundColor, range: range)
        } else {
            // Apply inline code
            string.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular), range: range)
            string.addAttribute(.backgroundColor, value: codeBackgroundColor, range: range)
        }
        string.endEditing()
    }

    /// Toggle code block formatting on a paragraph range
    static func toggleCodeBlock(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        // Check if already code block
        var isCodeBlock = false
        if range.location < string.length {
            let attrs = string.attributes(at: range.location, effectiveRange: nil)
            if let font = attrs[.font] as? NSFont,
               font.fontDescriptor.symbolicTraits.contains(.monoSpace),
               attrs[.backgroundColor] != nil
            {
                isCodeBlock = true
            }
        }

        string.beginEditing()
        if isCodeBlock {
            // Remove code block
            string.addAttribute(.font, value: NSFont.systemFont(ofSize: bodyFontSize), range: range)
            string.removeAttribute(.backgroundColor, range: range)
            string.removeAttribute(.paragraphStyle, range: range)
        } else {
            // Apply code block
            string.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular), range: range)
            string.addAttribute(.backgroundColor, value: codeBlockBackgroundColor, range: range)

            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = 12
            paragraph.firstLineHeadIndent = 12
            paragraph.tailIndent = -12
            string.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
        string.endEditing()
    }

    // MARK: - Block Quote

    /// Toggle block quote formatting on a paragraph range
    static func toggleBlockQuote(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        // Check if already a quote
        var isQuote = false
        if range.location < string.length {
            let attrs = string.attributes(at: range.location, effectiveRange: nil)
            if let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle {
                isQuote = paragraph.headIndent == blockQuoteIndent
            }
        }

        string.beginEditing()
        if isQuote {
            // Remove quote
            string.removeAttribute(.paragraphStyle, range: range)
            string.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        } else {
            // Apply quote
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = blockQuoteIndent
            paragraph.firstLineHeadIndent = blockQuoteIndent
            paragraph.paragraphSpacing = 8
            string.addAttribute(.paragraphStyle, value: paragraph, range: range)
            string.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        string.endEditing()
    }

    // MARK: - Clear Formatting

    /// Clear all formatting from a range
    static func clearFormatting(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        string.beginEditing()
        string.addAttribute(.font, value: NSFont.systemFont(ofSize: bodyFontSize), range: range)
        string.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        string.removeAttribute(.backgroundColor, range: range)
        string.removeAttribute(.underlineStyle, range: range)
        string.removeAttribute(.strikethroughStyle, range: range)
        string.removeAttribute(.paragraphStyle, range: range)
        string.endEditing()
    }

    // MARK: - Indentation

    /// Increase indent for a line
    static func increaseIndent(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }

        string.beginEditing()

        let attrs = string.attributes(at: range.location, effectiveRange: nil)
        let currentParagraph = (attrs[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
        let newParagraph = currentParagraph.mutableCopy() as! NSMutableParagraphStyle

        newParagraph.headIndent = min(currentParagraph.headIndent + 20, 100)
        newParagraph.firstLineHeadIndent = newParagraph.headIndent
        string.addAttribute(.paragraphStyle, value: newParagraph, range: range)

        string.endEditing()
    }

    /// Decrease indent for a line
    static func decreaseIndent(in string: inout NSMutableAttributedString, range: NSRange) {
        guard range.length > 0, range.location < string.length else { return }

        string.beginEditing()

        let attrs = string.attributes(at: range.location, effectiveRange: nil)
        guard let currentParagraph = attrs[.paragraphStyle] as? NSParagraphStyle else {
            string.endEditing()
            return
        }

        let newParagraph = currentParagraph.mutableCopy() as! NSMutableParagraphStyle
        newParagraph.headIndent = max(currentParagraph.headIndent - 20, 0)
        newParagraph.firstLineHeadIndent = newParagraph.headIndent
        string.addAttribute(.paragraphStyle, value: newParagraph, range: range)

        string.endEditing()
    }

    // MARK: - Private Helpers

    /// Theme-aware code background color (inline)
    private static var codeBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.25, alpha: 1.0)
                : NSColor(white: 0.92, alpha: 1.0)
        }
    }

    /// Theme-aware code block background color
    private static var codeBlockBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.18, alpha: 1.0)
                : NSColor(white: 0.95, alpha: 1.0)
        }
    }
}
