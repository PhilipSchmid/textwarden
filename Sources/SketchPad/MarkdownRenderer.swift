//
//  MarkdownRenderer.swift
//  TextWarden
//
//  Renders Markdown to NSAttributedString using Apple's swift-markdown MarkupVisitor pattern
//

import AppKit
import Markdown

/// Renders Markdown AST to NSAttributedString for display in NSTextView
struct MarkdownRenderer: MarkupVisitor {
    typealias Result = NSAttributedString

    // MARK: - Font Configuration

    private let bodyFont = NSFont.systemFont(ofSize: 16)
    private let h1Font = NSFont.systemFont(ofSize: 28, weight: .bold)
    private let h2Font = NSFont.systemFont(ofSize: 22, weight: .bold)
    private let h3Font = NSFont.systemFont(ofSize: 18, weight: .bold)
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    // MARK: - Color Configuration

    private var codeBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.25, alpha: 1.0) // Dark mode: subtle dark gray
                : NSColor(white: 0.92, alpha: 1.0) // Light mode: light gray
        }
    }

    private var codeBlockBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.18, alpha: 1.0) // Dark mode: darker background
                : NSColor(white: 0.95, alpha: 1.0) // Light mode: light gray
        }
    }

    // MARK: - MarkupVisitor Implementation

    mutating func defaultVisit(_ markup: any Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in document.children {
            result.append(visit(child))
        }
        // Trim trailing newlines
        while result.string.hasSuffix("\n\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
        return result
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let font: NSFont = switch heading.level {
        case 1: h1Font
        case 2: h2Font
        default: h3Font
        }

        let result = NSMutableAttributedString()
        for child in heading.children {
            result.append(visit(child))
        }

        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.font, value: font, range: range)
        result.append(NSAttributedString(string: "\n"))
        return result
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in paragraph.children {
            result.append(visit(child))
        }

        let range = NSRange(location: 0, length: result.length)
        // Only apply body font where no font is set
        result.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            if value == nil {
                result.addAttribute(.font, value: bodyFont, range: subrange)
            }
        }

        result.append(NSAttributedString(string: "\n\n"))
        return result
    }

    mutating func visitText(_ text: Text) -> NSAttributedString {
        NSAttributedString(string: text.string, attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.textColor,
        ])
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in strong.children {
            result.append(visit(child))
        }

        // Apply bold to all text
        let range = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let existingFont = (value as? NSFont) ?? bodyFont
            let boldFont = NSFontManager.shared.convert(existingFont, toHaveTrait: .boldFontMask)
            result.addAttribute(.font, value: boldFont, range: subrange)
        }
        return result
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in emphasis.children {
            result.append(visit(child))
        }

        // Apply italic to all text
        let range = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let existingFont = (value as? NSFont) ?? bodyFont
            let italicFont = NSFontManager.shared.convert(existingFont, toHaveTrait: .italicFontMask)
            result.addAttribute(.font, value: italicFont, range: subrange)
        }
        return result
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in strikethrough.children {
            result.append(visit(child))
        }

        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        return result
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSAttributedString {
        NSAttributedString(string: inlineCode.code, attributes: [
            .font: codeFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: codeBackgroundColor,
        ])
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        let code = codeBlock.code.trimmingCharacters(in: .newlines)

        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 12
        paragraph.firstLineHeadIndent = 12
        paragraph.tailIndent = -12

        return NSAttributedString(string: code + "\n\n", attributes: [
            .font: codeFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: codeBlockBackgroundColor,
            .paragraphStyle: paragraph,
        ])
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for item in list.listItems {
            let bullet = NSAttributedString(string: "•  ", attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.textColor,
            ])
            result.append(bullet)

            let itemContent = visitListItem(item)
            result.append(itemContent)
        }
        return result
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in list.listItems.enumerated() {
            let number = NSAttributedString(string: "\(index + 1). ", attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.textColor,
            ])
            result.append(number)

            let itemContent = visitListItem(item)
            result.append(itemContent)
        }
        return result
    }

    mutating func visitListItem(_ item: ListItem) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Visit children but handle paragraph differently
        for child in item.children {
            if child is Paragraph {
                // Don't add double newlines for list item paragraphs
                let paragraphResult = NSMutableAttributedString()
                for grandchild in child.children {
                    paragraphResult.append(visit(grandchild))
                }
                result.append(paragraphResult)
            } else {
                result.append(visit(child))
            }
        }

        // Ensure single newline at end
        if !result.string.hasSuffix("\n") {
            result.append(NSAttributedString(string: "\n"))
        }

        // Apply list paragraph style with indent
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 20
        paragraph.firstLineHeadIndent = 0

        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.paragraphStyle, value: paragraph, range: range)

        return result
    }

    mutating func visitBlockQuote(_ quote: BlockQuote) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in quote.children {
            result.append(visit(child))
        }

        // Apply quote styling
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 30
        paragraph.firstLineHeadIndent = 30
        paragraph.paragraphSpacing = 8

        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.paragraphStyle, value: paragraph, range: range)
        result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)

        return result
    }

    mutating func visitLink(_ link: Markdown.Link) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in link.children {
            result.append(visit(child))
        }

        if let destination = link.destination, let url = URL(string: destination) {
            let range = NSRange(location: 0, length: result.length)
            result.addAttribute(.link, value: url, range: range)
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }

        return result
    }

    mutating func visitSoftBreak(_: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ")
    }

    mutating func visitLineBreak(_: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n")
    }

    mutating func visitThematicBreak(_: ThematicBreak) -> NSAttributedString {
        NSAttributedString(string: "\n---\n\n", attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.separatorColor,
        ])
    }

    // MARK: - Public API

    /// Render Markdown string to NSAttributedString
    static func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives, .parseSymbolLinks])
        var renderer = MarkdownRenderer()
        return renderer.visit(document)
    }
}
