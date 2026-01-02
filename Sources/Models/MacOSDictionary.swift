//
//  MacOSDictionary.swift
//  TextWarden
//
//  Checks words against macOS system spell checker (words added via "Learn Spelling")
//

import AppKit
import Foundation

/// Checks words against the macOS system spell checker
/// Uses NSSpellChecker API to check if words have been learned via "Learn Spelling" in other apps
@MainActor
class MacOSDictionary {
    static let shared = MacOSDictionary()

    private let spellChecker = NSSpellChecker.shared

    private init() {}

    // MARK: - Public Methods

    /// Check if a word has been learned by macOS spell checker (case-sensitive)
    func contains(_ word: String) -> Bool {
        spellChecker.hasLearnedWord(word)
    }

    /// Check if any word in the text has been learned by macOS spell checker
    func containsAnyWord(in text: String) -> Bool {
        let textWords = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        return textWords.contains { textWord in
            spellChecker.hasLearnedWord(textWord)
        }
    }
}
