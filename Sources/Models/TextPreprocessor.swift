//
//  TextPreprocessor.swift
//  TextWarden
//
//  Text preprocessing for code editors and terminals
//

import Foundation

/// Preprocesses text to exclude patterns that shouldn't be grammar checked
struct TextPreprocessor {

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
            "www\\.[^\\s]+"
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

        // Track URL ranges (don't remove, just mark for exclusion)
        let urlRanges = excludeURLs(from: text)
        let filePathRanges = excludeFilePaths(from: text)

        return PreprocessedText(
            original: text,
            cleaned: cleanedText,
            exclusionRanges: urlRanges + filePathRanges
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
        return location..<(location + length)
    }

    func overlaps(_ errorRange: Range<Int>) -> Bool {
        return range.overlaps(errorRange)
    }
}
