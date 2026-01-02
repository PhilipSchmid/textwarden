//
//  TextIndexConverter.swift
//  TextWarden
//
//  Utility for converting between different text indexing systems:
//  - Unicode scalars (Harper/Rust char indices)
//  - Grapheme clusters (Swift String indices)
//  - UTF-16 code units (macOS Accessibility APIs, NSString)
//
//  This matters for text with emojis and complex characters:
//  - 😊 = 1 grapheme cluster, 2 UTF-16 code units, 1 Unicode scalar
//  - ❗️ = 1 grapheme cluster, 2 UTF-16 code units, 2 Unicode scalars (U+2757 + U+FE0F)
//  - 👨‍👩‍👧 = 1 grapheme cluster, 11 UTF-16 code units, 7 Unicode scalars
//

import Foundation

/// Centralized utility for converting between different text indexing systems
enum TextIndexConverter {
    // MARK: - Unicode Scalar ↔ String.Index (Grapheme Cluster)

    /// Convert Unicode scalar index to String.Index (grapheme cluster based).
    /// Harper uses Rust's char indices (Unicode scalar values), but Swift uses grapheme clusters.
    /// - Parameters:
    ///   - scalarIndex: The Unicode scalar index from Harper
    ///   - string: The string to convert within
    /// - Returns: The corresponding String.Index, or nil if out of bounds
    static func scalarIndexToStringIndex(_ scalarIndex: Int, in string: String) -> String.Index? {
        let scalars = string.unicodeScalars
        var scalarCount = 0
        var currentIndex = string.startIndex

        while currentIndex < string.endIndex {
            if scalarCount == scalarIndex {
                return currentIndex
            }
            // Count how many scalars are in this grapheme cluster
            let nextIndex = string.index(after: currentIndex)
            let scalarStart = currentIndex.samePosition(in: scalars) ?? scalars.startIndex
            let scalarEnd = nextIndex.samePosition(in: scalars) ?? scalars.endIndex
            let scalarsInCluster = scalars.distance(from: scalarStart, to: scalarEnd)
            scalarCount += scalarsInCluster
            currentIndex = nextIndex
        }

        // If scalarIndex equals total scalar count, return endIndex
        if scalarCount == scalarIndex {
            return string.endIndex
        }

        return nil
    }

    /// Get the number of Unicode scalars up to a String.Index.
    /// - Parameters:
    ///   - stringIndex: The String.Index to convert
    ///   - string: The string to convert within
    /// - Returns: The Unicode scalar count up to that index
    static func stringIndexToScalarIndex(_ stringIndex: String.Index, in string: String) -> Int {
        let scalars = string.unicodeScalars
        let scalarStart = string.startIndex.samePosition(in: scalars) ?? scalars.startIndex
        let scalarEnd = stringIndex.samePosition(in: scalars) ?? scalars.endIndex
        return scalars.distance(from: scalarStart, to: scalarEnd)
    }

    // MARK: - Grapheme Cluster ↔ UTF-16

    /// Convert grapheme cluster indices to UTF-16 code unit indices.
    /// macOS accessibility APIs use UTF-16 code units, not grapheme clusters.
    /// - Parameters:
    ///   - range: NSRange in grapheme cluster indices
    ///   - text: The text to convert within
    /// - Returns: NSRange in UTF-16 code unit indices
    static func graphemeToUTF16Range(_ range: NSRange, in text: String) -> NSRange {
        let endPosition = range.location + range.length
        // Use safe index operations to prevent crashes on out-of-bounds access
        guard range.location >= 0, range.location <= endPosition,
              let startIndex = text.index(text.startIndex, offsetBy: range.location, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: endPosition, limitedBy: text.endIndex)
        else {
            return range // Out of bounds, return original
        }

        // Use prefix strings and NSString.length for UTF-16 conversion
        let prefixToStart = String(text[..<startIndex])
        let prefixToEnd = String(text[..<endIndex])

        let utf16Location = (prefixToStart as NSString).length
        let utf16EndLocation = (prefixToEnd as NSString).length
        let utf16Length = max(1, utf16EndLocation - utf16Location)

        return NSRange(location: utf16Location, length: utf16Length)
    }

    /// Convert a single grapheme cluster index to UTF-16 code unit offset.
    /// - Parameters:
    ///   - graphemeIndex: The grapheme cluster index
    ///   - string: The string to convert within
    /// - Returns: The UTF-16 code unit offset
    static func graphemeToUTF16(_ graphemeIndex: Int, in string: String) -> Int {
        let safeIndex = min(graphemeIndex, string.count)
        guard let stringIndex = string.index(string.startIndex, offsetBy: safeIndex, limitedBy: string.endIndex) else {
            return graphemeIndex // Fallback to original if conversion fails
        }
        let prefix = String(string[..<stringIndex])
        return (prefix as NSString).length
    }

    /// Convert UTF-16 code unit offset to grapheme cluster count.
    /// - Parameters:
    ///   - utf16Offset: The UTF-16 offset
    ///   - string: The string to convert within
    /// - Returns: The grapheme cluster count, or nil if out of bounds
    static func utf16ToGraphemeIndex(_ utf16Offset: Int, in string: String) -> Int? {
        guard utf16Offset >= 0 else { return nil }

        let nsString = string as NSString
        guard utf16Offset <= nsString.length else { return nil }

        // Use Range(NSRange, in:) to convert UTF-16 position to String.Index
        let utf16Range = NSRange(location: utf16Offset, length: 0)
        guard let range = Range(utf16Range, in: string) else { return nil }

        // Count grapheme clusters from start to this position
        return string.distance(from: string.startIndex, to: range.lowerBound)
    }

    // MARK: - String.Index ↔ UTF-16

    /// Get UTF-16 offset for a String.Index.
    /// - Parameters:
    ///   - index: The String.Index to convert
    ///   - string: The string to convert within
    /// - Returns: The UTF-16 code unit offset
    static func utf16Offset(of index: String.Index, in string: String) -> Int {
        string.utf16.distance(from: string.utf16.startIndex, to: index)
    }

    /// Convert UTF-16 code unit offset to String.Index.
    /// - Parameters:
    ///   - utf16Offset: The UTF-16 offset
    ///   - string: The string to convert within
    /// - Returns: The corresponding String.Index, or nil if out of bounds
    static func stringIndex(forUTF16Offset utf16Offset: Int, in string: String) -> String.Index? {
        guard utf16Offset >= 0 else { return nil }

        let nsString = string as NSString
        guard utf16Offset <= nsString.length else { return nil }

        let utf16Range = NSRange(location: utf16Offset, length: 0)
        guard let range = Range(utf16Range, in: string) else { return nil }

        return range.lowerBound
    }

    // MARK: - Convenience Methods

    /// Extract error text using Harper's scalar indices.
    /// - Parameters:
    ///   - start: Start scalar index from Harper
    ///   - end: End scalar index from Harper
    ///   - text: The source text
    /// - Returns: The extracted substring, or nil if indices are invalid
    static func extractErrorText(start: Int, end: Int, from text: String) -> String? {
        guard let startIndex = scalarIndexToStringIndex(start, in: text),
              let endIndex = scalarIndexToStringIndex(end, in: text),
              startIndex < endIndex
        else {
            return nil
        }
        return String(text[startIndex ..< endIndex])
    }

    /// Convert Harper's scalar range to CFRange for accessibility APIs.
    /// Combines scalar→grapheme→UTF-16 conversions.
    /// - Parameters:
    ///   - start: Start scalar index from Harper
    ///   - end: End scalar index from Harper
    ///   - text: The source text
    /// - Returns: CFRange in UTF-16 code units for accessibility APIs
    static func scalarRangeToUTF16CFRange(start: Int, end: Int, in text: String) -> CFRange? {
        guard let startIndex = scalarIndexToStringIndex(start, in: text),
              let endIndex = scalarIndexToStringIndex(end, in: text)
        else {
            return nil
        }

        let utf16Start = utf16Offset(of: startIndex, in: text)
        let utf16End = utf16Offset(of: endIndex, in: text)
        return CFRange(location: utf16Start, length: max(1, utf16End - utf16Start))
    }
}
