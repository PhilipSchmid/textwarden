//
//  ReplacementTextMatcher.swift
//  TextWarden
//

import Foundation

/// Matches the live error span with the exact text that was analyzed.
enum ReplacementTextMatcher {
    enum Resolution: Equatable {
        case matched(Range<Int>)
        case ambiguous([Range<Int>])
        case notFound
        case unavailable
    }

    /// Resolve the live source range without guessing between repeated nearby tokens.
    static func resolveRange(
        in sourceText: String,
        analyzedText: String,
        for error: GrammarErrorModel,
        searchRadius: Int = 5
    ) -> Resolution {
        guard let expected = TextIndexConverter.extractErrorText(
            start: error.start,
            end: error.end,
            from: analyzedText
        ) else {
            return .unavailable
        }

        let scalarCount = sourceText.unicodeScalars.count
        let errorLength = error.end - error.start
        guard error.start >= 0,
              errorLength > 0,
              error.end <= scalarCount
        else {
            return .notFound
        }

        let originalRange = error.start ..< error.end
        if let actual = text(in: originalRange, from: sourceText),
           actual == expected
        {
            return .matched(originalRange)
        }

        let radius = max(0, searchRadius)
        var matches: [Range<Int>] = []

        for offset in -radius ... radius where offset != 0 {
            let start = error.start + offset
            let end = start + errorLength
            guard start >= 0, end <= scalarCount else { continue }

            let range = start ..< end
            guard let candidate = text(in: range, from: sourceText) else { continue }
            if candidate == expected {
                matches.append(range)
            }
        }

        if matches.count == 1, let match = matches.first {
            return .matched(match)
        }
        if matches.count > 1 {
            return .ambiguous(matches)
        }
        return .notFound
    }

    private static func text(in range: Range<Int>, from sourceText: String) -> String? {
        guard let start = TextIndexConverter.scalarIndexToStringIndex(range.lowerBound, in: sourceText),
              let end = TextIndexConverter.scalarIndexToStringIndex(range.upperBound, in: sourceText)
        else {
            return nil
        }
        return String(sourceText[start ..< end])
    }
}

/// Keeps each canonical error tied to the exact text that produced it.
struct GrammarErrorSourceStore {
    private struct Entry {
        let error: GrammarErrorModel
        let sourceText: String
    }

    private var entriesByError: [ObjectIdentifier: Entry] = [:]

    mutating func replace(errors: [GrammarErrorModel], sourceText: String) {
        let previousEntries = entriesByError
        entriesByError.removeAll(keepingCapacity: true)
        for error in errors {
            let identifier = ObjectIdentifier(error)
            let existingSource = previousEntries[identifier].flatMap { entry in
                entry.error === error ? entry.sourceText : nil
            }
            entriesByError[identifier] = Entry(
                error: error,
                sourceText: existingSource ?? sourceText
            )
        }
    }

    func sourceText(for error: GrammarErrorModel, among currentErrors: [GrammarErrorModel]) -> String? {
        guard currentErrors.contains(where: { $0 === error }) else {
            return nil
        }
        guard let entry = entriesByError[ObjectIdentifier(error)], entry.error === error else {
            return nil
        }
        return entry.sourceText
    }
}
