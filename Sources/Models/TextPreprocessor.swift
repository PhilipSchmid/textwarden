//
//  TextPreprocessor.swift
//  TextWarden
//
//  Text preprocessing for code editors and terminals
//

import Foundation

/// Preprocesses text to exclude patterns that shouldn't be grammar checked
enum TextPreprocessor {
    // MARK: - Code Block Exclusion

    /// Exclude code blocks from grammar checking
    static func excludeCodeBlocks(from text: String) -> String {
        var result = text

        let fencedPattern = "```[\\s\\S]*?```"
        result = replacePattern(fencedPattern, in: result, with: "")

        let indentedPattern = "^    .*$"
        result = replacePattern(indentedPattern, in: result, with: "", options: [.anchorsMatchLines])

        return result
    }

    /// Exclude inline code from grammar checking
    static func excludeInlineCode(from text: String) -> String {
        let pattern = "`[^`]+`"
        return replacePattern(pattern, in: text, with: "")
    }

    // MARK: - URL Exclusion

    /// Exclude URLs from grammar checking
    static func excludeURLs(from text: String) -> [ExclusionRange] {
        var ranges: [ExclusionRange] = []

        // Match URLs: http://, https://, ftp://, www.
        let patterns = [
            "https?://[^\\s]+",
            "ftp://[^\\s]+",
            "www\\.[^\\s]+",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: nsRange)

                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let location = text.distance(from: text.startIndex, to: range.lowerBound)
                        let length = text.distance(from: range.lowerBound, to: range.upperBound)
                        ranges.append(ExclusionRange(location: location, length: length))
                    }
                }
            }
        }

        return ranges
    }

    // MARK: - List Marker Exclusion

    /// Exclude list markers and their alignment spacing from grammar checking.
    ///
    /// Handles various list formats found in chat apps and text editors:
    /// - Bullet markers: •, ◦, ▪, ▸, -, *, +
    /// - Numbered lists: 1. 2. 10. or 1) 2) or (1) (2)
    /// - Letter lists: a. b. A. B. or a) b) or (a) (b)
    /// - Roman numerals: i. ii. iii. I. II. III.
    /// - Checkboxes: [ ] [x] [X]
    ///
    /// Matches markers at line start (with optional leading whitespace for indented lists)
    /// followed by whitespace (space or tab) used for alignment.
    static func excludeListMarkers(from text: String) -> [ExclusionRange] {
        var ranges: [ExclusionRange] = []

        // Unicode bullet characters - synced with GrammarEngine/src/language_filter.rs is_bullet_char()
        // U+2022 • BULLET, U+25E6 ◦ WHITE BULLET, U+25AA ▪ BLACK SMALL SQUARE
        // U+25B8 ▸ BLACK RIGHT-POINTING SMALL TRIANGLE, U+25BA ► BLACK RIGHT-POINTING POINTER
        // U+2023 ‣ TRIANGULAR BULLET, U+2043 ⁃ HYPHEN BULLET
        // U+2013 – EN DASH, U+2014 — EM DASH (used as bullets in some apps)
        // U+25CB ○ WHITE CIRCLE, U+25CF ● BLACK CIRCLE
        let bulletChars = "•◦▪▸►‣⁃○●–—\\-\\*\\+"

        let patterns = [
            // Bullet markers: bullet char + whitespace (space or tab)
            // Matches: "• item", "- item", "* item", "	• item" (indented)
            "^[ \\t]*[\(bulletChars)][ \\t]+",

            // Numbered lists: digits + period/paren + whitespace
            // Matches: "1. item", "10. item", "1) item", "(1) item"
            "^[ \\t]*\\(?\\d{1,3}[.)][ \\t]+",

            // Letter lists: single letter + period/paren + whitespace
            // Matches: "a. item", "A. item", "a) item", "(a) item"
            "^[ \\t]*\\(?[a-zA-Z][.)][ \\t]+",

            // Roman numerals (lowercase): i, ii, iii, iv, v, vi, vii, viii, ix, x, xi, xii
            // Matches: "i. item", "iv. item", "xii. item"
            "^[ \\t]*(?:x{0,1}i{1,3}|i?v|vi{0,3}|ix|x{1,2}i{0,2})[.)\\t][ \\t]+",

            // Roman numerals (uppercase): I, II, III, IV, V, VI, VII, VIII, IX, X, XI, XII
            "^[ \\t]*(?:X{0,1}I{1,3}|I?V|VI{0,3}|IX|X{1,2}I{0,2})[.)\\t][ \\t]+",

            // Checkbox markers: [ ] or [x] or [X] followed by space
            // Matches: "[ ] todo", "[x] done", "[X] done"
            "^[ \\t]*\\[[xX ]\\][ \\t]+",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                continue
            }

            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)

            for match in matches {
                if let range = Range(match.range, in: text) {
                    let location = text.distance(from: text.startIndex, to: range.lowerBound)
                    let length = text.distance(from: range.lowerBound, to: range.upperBound)
                    ranges.append(ExclusionRange(location: location, length: length))
                }
            }
        }

        return ranges
    }

    // MARK: - File Path Exclusion

    /// Exclude file paths from grammar checking
    static func excludeFilePaths(from text: String) -> [ExclusionRange] {
        var ranges: [ExclusionRange] = []

        // Match common file path patterns
        let patterns = [
            "/[\\w/.]+", // Unix paths
            "[A-Z]:[\\\\\\w.]+", // Windows paths
            "~/[\\w/.]+", // Home directory paths
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: nsRange)

                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let location = text.distance(from: text.startIndex, to: range.lowerBound)
                        let length = text.distance(from: range.lowerBound, to: range.upperBound)
                        ranges.append(ExclusionRange(location: location, length: length))
                    }
                }
            }
        }

        return ranges
    }

    // MARK: - Combined Preprocessing

    /// Preprocess text for code editors
    static func preprocessForCodeEditor(_ text: String) -> PreprocessedText {
        var cleanedText = text

        cleanedText = excludeCodeBlocks(from: cleanedText)

        cleanedText = excludeInlineCode(from: cleanedText)

        // Track ranges to exclude from error reporting (don't remove, just mark)
        let urlRanges = excludeURLs(from: text)
        let filePathRanges = excludeFilePaths(from: text)
        let listMarkerRanges = excludeListMarkers(from: text)

        return PreprocessedText(
            original: text,
            cleaned: cleanedText,
            exclusionRanges: urlRanges + filePathRanges + listMarkerRanges
        )
    }

    // MARK: - Helper Methods

    private static func replacePattern(
        _ pattern: String,
        in text: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: nsRange,
            withTemplate: replacement
        )
    }
}

// MARK: - Data Types

/// Result of text preprocessing
struct PreprocessedText {
    /// Original text before preprocessing
    let original: String

    /// Cleaned text with code/URLs removed
    let cleaned: String

    /// Ranges to exclude from error reporting
    let exclusionRanges: [ExclusionRange]
}

/// A range to exclude from grammar checking
struct ExclusionRange {
    let location: Int
    let length: Int

    var range: Range<Int> {
        location ..< (location + length)
    }

    func overlaps(_ errorRange: Range<Int>) -> Bool {
        range.overlaps(errorRange)
    }
}
