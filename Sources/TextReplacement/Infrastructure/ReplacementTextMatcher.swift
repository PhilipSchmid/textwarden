//
//  ReplacementTextMatcher.swift
//  TextWarden
//

import Foundation

/// Matches the live error span with the exact text that was analyzed.
enum ReplacementTextMatcher {
    static func uniqueLiteralRange(of text: String, in source: String) -> Range<String.Index>? {
        guard !text.isEmpty,
              let match = source.range(of: text, options: .literal),
              source.range(of: text, options: .literal, range: source.index(after: match.lowerBound) ..< source.endIndex) == nil
        else { return nil }
        return match
    }

    enum Resolution: Equatable {
        case matched(Range<Int>)
        case ambiguous([Range<Int>])
        case notFound
        case unavailable
    }

    enum SegmentReconciliation: Equatable {
        case updated(String)
        case sourceChanged
        case invalidRange
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

    /// Apply a replacement to cached analysis text only while it still matches the text
    /// that produced the error. AX notifications may deliver the corrected text first.
    static func reconcileSegment(
        currentText: String,
        analyzedText: String?,
        replacing range: Range<Int>,
        with replacement: String
    ) -> SegmentReconciliation {
        if let analyzedText, currentText != analyzedText {
            return .sourceChanged
        }

        guard range.lowerBound >= 0,
              range.lowerBound < range.upperBound,
              range.upperBound <= currentText.unicodeScalars.count,
              let start = TextIndexConverter.scalarIndexToStringIndex(range.lowerBound, in: currentText),
              let end = TextIndexConverter.scalarIndexToStringIndex(range.upperBound, in: currentText)
        else {
            return .invalidRange
        }

        var updatedText = currentText
        updatedText.replaceSubrange(start ..< end, with: replacement)
        return .updated(updatedText)
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

    /// Advance errors that survived a known edit outside their spans.
    mutating func advanceUnchangedErrors(
        _ errors: [GrammarErrorModel],
        replacing range: Range<Int>,
        in source: String,
        with replacement: String,
        matching updatedSource: String
    ) {
        guard !errors.isEmpty,
              case let .updated(expected) = ReplacementTextMatcher.reconcileSegment(
                  currentText: source,
                  analyzedText: nil,
                  replacing: range,
                  with: replacement
              ),
              expected.utf16.elementsEqual(updatedSource.utf16)
        else { return }

        // Errors after a length-changing edit get new objects when their offsets shift.
        let preservesOffsets = replacement.unicodeScalars.count == range.count
        for error in errors where error.end <= range.lowerBound || (preservesOffsets && error.start >= range.upperBound) {
            let identifier = ObjectIdentifier(error)
            guard let entry = entriesByError[identifier],
                  entry.error === error,
                  entry.sourceText.utf16.elementsEqual(source.utf16)
            else { continue }
            entriesByError[identifier] = Entry(error: error, sourceText: updatedSource)
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
