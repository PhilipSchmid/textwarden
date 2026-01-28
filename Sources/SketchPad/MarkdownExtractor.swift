//
//  MarkdownExtractor.swift
//  TextWarden
//
//  Extracts Markdown from NSAttributedString by analyzing attributes
//

import AppKit

/// Extracts Markdown from NSAttributedString
enum MarkdownExtractor {
    // MARK: - Font Size Thresholds (matching MarkdownRenderer)

    private static let h1SizeRange: ClosedRange<CGFloat> = 27 ... 29
    private static let h2SizeRange: ClosedRange<CGFloat> = 21 ... 23
    private static let h3SizeRange: ClosedRange<CGFloat> = 17 ... 19
    private static let quoteIndent: CGFloat = 30

    // MARK: - Public API

    /// Extract Markdown from NSAttributedString
    static func extract(from attributed: NSAttributedString) -> String {
        var markdown = ""

        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { attrs, range, _ in
            let substring = (attributed.string as NSString).substring(with: range)
            var text = substring
            var isHeading = false
            var isCode = false
            var isQuote = false

            if let font = attrs[.font] as? NSFont {
                let size = font.pointSize
                let traits = font.fontDescriptor.symbolicTraits

                // Check headings by font size FIRST
                if h1SizeRange.contains(size) {
                    text = processHeading(text, prefix: "# ")
                    isHeading = true
                } else if h2SizeRange.contains(size) {
                    text = processHeading(text, prefix: "## ")
                    isHeading = true
                } else if h3SizeRange.contains(size) {
                    text = processHeading(text, prefix: "### ")
                    isHeading = true
                }

                // Check for code (monospace + background)
                if !isHeading, traits.contains(.monoSpace), attrs[.backgroundColor] != nil {
                    isCode = true
                    if text.contains("\n") {
                        // Multi-line code block
                        let trimmed = text.trimmingCharacters(in: .newlines)
                        text = "```\n\(trimmed)\n```\n"
                    } else {
                        // Inline code
                        text = "`\(text)`"
                    }
                }

                // Bold/italic (skip if heading or code)
                if !isHeading, !isCode {
                    // Check for bold
                    if traits.contains(.bold) {
                        text = "**\(text)**"
                    }
                    // Check for italic
                    if traits.contains(.italic) {
                        text = "*\(text)*"
                    }
                }
            }

            // Strikethrough
            if !isHeading, !isCode {
                if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                    text = "~~\(text)~~"
                }
            }

            // Block quote (check paragraph indent)
            if !isHeading, !isCode {
                if let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle,
                   paragraph.headIndent >= quoteIndent
                {
                    isQuote = true
                    text = processBlockQuote(text)
                }
            }

            // Links
            if !isHeading, !isCode, !isQuote {
                if let link = attrs[.link] {
                    let urlString: String = if let url = link as? URL {
                        url.absoluteString
                    } else if let string = link as? String {
                        string
                    } else {
                        ""
                    }
                    if !urlString.isEmpty {
                        text = "[\(text)](\(urlString))"
                    }
                }
            }

            markdown += text
        }

        // Post-process: convert bullet character to markdown dash
        markdown = markdown.replacingOccurrences(of: "•  ", with: "- ")
        markdown = markdown.replacingOccurrences(of: "• ", with: "- ")

        // Clean up excessive newlines
        while markdown.contains("\n\n\n") {
            markdown = markdown.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    private static func processHeading(_ text: String, prefix: String) -> String {
        // Add heading prefix to each non-empty line
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? String(line) : "\(prefix)\(trimmed)"
            }
            .joined(separator: "\n")
    }

    private static func processBlockQuote(_ text: String) -> String {
        // Add > prefix to each line
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
    }
}
