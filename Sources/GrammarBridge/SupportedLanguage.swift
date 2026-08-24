// SupportedLanguage.swift
// Detector-backed language metadata shared by preferences and onboarding.

import Foundation

struct SupportedLanguage: Hashable, Identifiable, Sendable {
    let code: String
    let englishName: String
    let nativeName: String

    var id: String {
        code
    }

    var secondaryName: String? {
        nativeName.compare(englishName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            ? nil
            : nativeName
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else { return true }

        return [code, englishName, nativeName]
            .map(Self.normalized)
            .contains { $0.contains(normalizedQuery) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension GrammarEngine {
    static let supportedLanguages: [SupportedLanguage] = supported_languages().map { language in
        SupportedLanguage(
            code: language.code().toString(),
            englishName: language.english_name().toString(),
            nativeName: language.native_name().toString()
        )
    }
}
