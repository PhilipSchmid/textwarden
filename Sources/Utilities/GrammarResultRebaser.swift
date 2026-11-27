//
//  GrammarResultRebaser.swift
//  TextWarden
//
//  Decides which results from an earlier revision of a text still describe the
//  text as it now stands.
//

import Foundation

/// Salvages results computed against an earlier revision of the same text.
///
/// An external source answers after a round trip, by which time the user has
/// usually typed more. Throwing the whole reply away discards work that is
/// still correct: adding a sentence to a paragraph says nothing about the
/// paragraph above it. This keeps the part of a reply the edit cannot have
/// invalidated, and nothing else.
enum GrammarResultRebaser {
    /// The subset of `errors` that still describes `currentText`.
    ///
    /// Only results lying entirely before the first difference are kept, so no
    /// offset is ever adjusted and a salvaged underline cannot drift.
    static func surviving(
        _ errors: [GrammarErrorModel],
        computedFor previousText: String,
        stillValidIn currentText: String
    ) -> [GrammarErrorModel] {
        guard !errors.isEmpty else { return [] }
        guard previousText != currentText else { return errors }

        let boundary = unchangedPrefixLength(of: previousText, against: currentText)
        guard boundary > 0 else { return [] }
        return errors.filter { $0.end <= boundary }
    }

    /// Scalar offset up to which `previous` is known to be untouched.
    ///
    /// Where the divergence falls inside a word, the whole word is treated as
    /// changed. The source judged a fragment the user had not finished typing,
    /// and "recei" being a misspelling says nothing about "receive". A word
    /// that merely has text appended *after* it is left alone, because typing
    /// " the" after "receive" does not change "receive".
    static func unchangedPrefixLength(of previous: String, against current: String) -> Int {
        let previousScalars = Array(previous.unicodeScalars)
        let currentScalars = Array(current.unicodeScalars)

        var shared = 0
        let limit = min(previousScalars.count, currentScalars.count)
        while shared < limit, previousScalars[shared] == currentScalars[shared] {
            shared += 1
        }

        var boundary = shared
        let wordContinues = (shared < previousScalars.count && isWordScalar(previousScalars[shared]))
            || (shared < currentScalars.count && isWordScalar(currentScalars[shared]))
        if wordContinues {
            while boundary > 0, isWordScalar(previousScalars[boundary - 1]) {
                boundary -= 1
            }
        }

        // Offsets address characters, so the cut must not fall inside a
        // grapheme cluster even where its scalars are not word scalars.
        let graphemeBoundaries = TextIndexConverter.stringIndicesByScalarOffset(in: previous)
        while boundary > 0, graphemeBoundaries[boundary] == nil {
            boundary -= 1
        }

        return boundary
    }

    /// Scalars that can sit inside a word, including the marks that combine
    /// with one.
    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) {
            return true
        }
        // An apostrophe or hyphen joins a word rather than ending it, so a
        // half-typed "don" and a finished "don't" are not the same span.
        return scalar == "'" || scalar == "\u{2019}" || scalar == "-"
    }
}
