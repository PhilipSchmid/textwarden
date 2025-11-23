//
//  CustomVocabulary.swift
//  TextWarden
//
//  Custom vocabulary management with JSON persistence (T100, T107)
//

import Foundation
import Combine

/// Manages custom vocabulary words with JSON file persistence
class CustomVocabulary: ObservableObject {
    static let shared = CustomVocabulary()

    private let fileURL: URL
    private let maxWords = 1000

    @Published private(set) var words: Set<String> = []

    private init() {
        // Setup file URL in Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let gnauDir = appSupport.appendingPathComponent("TextWarden")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: gnauDir,
            withIntermediateDirectories: true
        )

        fileURL = gnauDir.appendingPathComponent("custom-vocabulary.json")

        // Load existing vocabulary
        load()
    }

    // MARK: - Public Methods

    /// Add a word to the custom vocabulary (T110)
    /// Case-sensitive: "Today" and "today" are treated as different words
    func addWord(_ word: String) throws {
        guard words.count < maxWords else {
            throw VocabularyError.limitExceeded
        }

        let normalized = word.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            throw VocabularyError.invalidWord
        }

        words.insert(normalized)
        try save()
    }

    /// Remove a word from the custom vocabulary (case-sensitive)
    func removeWord(_ word: String) throws {
        let normalized = word.trimmingCharacters(in: .whitespaces)
        words.remove(normalized)
        try save()
    }

    /// Check if a word is in the custom vocabulary (case-sensitive exact match)
    func contains(_ word: String) -> Bool {
        let normalized = word.trimmingCharacters(in: .whitespaces)
        return words.contains(normalized)
    }

    /// Clear all custom vocabulary
    func clearAll() throws {
        words.removeAll()
        try save()
    }

    /// Check if any text contains words from custom vocabulary (T103)
    /// Used to filter out grammar errors that involve custom words
    /// Case-sensitive: only exact matches (including capitalization) are filtered
    func containsAnyWord(in text: String) -> Bool {
        let textWords = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        return textWords.contains { textWord in
            words.contains(textWord)
        }
    }

    // MARK: - Persistence (T107)

    /// Save vocabulary to JSON file
    private func save() throws {
        let file = CustomVocabularyFile(
            version: 1,
            words: Array(words),
            lastModified: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)

        print("📝 CustomVocabulary: Saved \(words.count) words to \(fileURL.path)")
    }

    /// Load vocabulary from JSON file
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("📝 CustomVocabulary: No existing file, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let file = try decoder.decode(CustomVocabularyFile.self, from: data)

            // Validate version
            guard file.version == 1 else {
                print("⚠️ CustomVocabulary: Unsupported version \(file.version)")
                return
            }

            words = Set(file.words.prefix(maxWords))
            print("📝 CustomVocabulary: Loaded \(words.count) words from \(fileURL.path)")

        } catch {
            print("❌ CustomVocabulary: Failed to load: \(error)")
        }
    }
}

// MARK: - Data Types

/// JSON file structure for custom vocabulary
struct CustomVocabularyFile: Codable {
    let version: Int
    let words: [String]
    let lastModified: Date
}

/// Errors for vocabulary operations
enum VocabularyError: Error, LocalizedError {
    case limitExceeded
    case invalidWord

    var errorDescription: String? {
        switch self {
        case .limitExceeded:
            return "Custom vocabulary limit of 1000 words exceeded"
        case .invalidWord:
            return "Invalid word (empty or whitespace only)"
        }
    }
}
