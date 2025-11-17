// GrammarEngine.swift
// High-level Swift wrapper for Rust grammar engine FFI

import Foundation

/// Swift wrapper for the Rust grammar analysis engine
@objc public class GrammarEngine: NSObject {

    /// Shared singleton instance
    @objc public static let shared = GrammarEngine()

    private override init() {
        super.init()
    }

    /// Analyze text for grammar errors
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - dialect: English dialect (American, British, Canadian, Australian)
    ///   - enableInternetAbbrev: Enable recognition of internet abbreviations (BTW, FYI, LOL, etc.)
    ///   - enableGenZSlang: Enable recognition of Gen Z slang (ghosting, sus, slay, etc.)
    ///   - enableITTerminology: Enable recognition of IT terminology (kubernetes, docker, API, etc.)
    ///   - enableLanguageDetection: Enable detection and filtering of non-English words
    ///   - excludedLanguages: Array of language codes to exclude (e.g., ["spanish", "german"])
    ///   - enableSentenceStartCapitalization: Enable capitalization of suggestions at sentence starts
    /// - Returns: Result containing analysis result or error
    @objc public func analyzeText(
        _ text: String,
        dialect: String,
        enableInternetAbbrev: Bool,
        enableGenZSlang: Bool,
        enableITTerminology: Bool,
        enableLanguageDetection: Bool = false,
        excludedLanguages: [String] = [],
        enableSentenceStartCapitalization: Bool = true
    ) -> GrammarAnalysisResult {
        // Call FFI function with all parameters
        // Convert Swift strings to RustString and create RustVec for language list
        let rustText = RustString(text)
        let rustDialect = RustString(dialect)
        var rustVec = RustVec<RustString>()
        for lang in excludedLanguages {
            rustVec.push(value: RustString(lang))
        }

        let ffiResult = analyze_text(
            rustText,
            rustDialect,
            enableInternetAbbrev,
            enableGenZSlang,
            enableITTerminology,
            enableLanguageDetection,
            rustVec,
            enableSentenceStartCapitalization
        )

        // Convert FFI result to Swift model
        return GrammarAnalysisResult(ffiResult: ffiResult)
    }

    /// Async wrapper for text analysis (non-blocking)
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - dialect: English dialect (American, British, Canadian, Australian)
    ///   - enableInternetAbbrev: Enable recognition of internet abbreviations (BTW, FYI, LOL, etc.)
    ///   - enableGenZSlang: Enable recognition of Gen Z slang (ghosting, sus, slay, etc.)
    ///   - enableITTerminology: Enable recognition of IT terminology (kubernetes, docker, API, etc.)
    ///   - enableLanguageDetection: Enable detection and filtering of non-English words
    ///   - excludedLanguages: Array of language codes to exclude (e.g., ["spanish", "german"])
    ///   - enableSentenceStartCapitalization: Enable capitalization of suggestions at sentence starts
    /// - Returns: Analysis result
    @available(macOS 10.15, *)
    public func analyzeText(
        _ text: String,
        dialect: String,
        enableInternetAbbrev: Bool,
        enableGenZSlang: Bool,
        enableITTerminology: Bool,
        enableLanguageDetection: Bool = false,
        excludedLanguages: [String] = [],
        enableSentenceStartCapitalization: Bool = true
    ) async -> GrammarAnalysisResult {
        await Task.detached(priority: .userInitiated) { [text, dialect, enableInternetAbbrev, enableGenZSlang, enableITTerminology, enableLanguageDetection, excludedLanguages, enableSentenceStartCapitalization] in
            // Call FFI function directly in detached task
            // Convert Swift strings to RustString and create RustVec for language list
            let rustText = RustString(text)
            let rustDialect = RustString(dialect)
            var rustVec = RustVec<RustString>()
            for lang in excludedLanguages {
                rustVec.push(value: RustString(lang))
            }

            let ffiResult = analyze_text(
                rustText,
                rustDialect,
                enableInternetAbbrev,
                enableGenZSlang,
                enableITTerminology,
                enableLanguageDetection,
                rustVec,
                enableSentenceStartCapitalization
            )
            return GrammarAnalysisResult(ffiResult: ffiResult)
        }.value
    }

    // MARK: - Convenience Methods

    /// Convenience method for analyzing text with default parameters
    ///
    /// - Parameter text: The text to analyze
    /// - Returns: Result containing analysis result or error
    @objc public func analyzeText(_ text: String) -> GrammarAnalysisResult {
        analyzeText(
            text,
            dialect: "American",
            enableInternetAbbrev: true,
            enableGenZSlang: true,
            enableITTerminology: true,
            enableLanguageDetection: false,
            excludedLanguages: [],
            enableSentenceStartCapitalization: true
        )
    }

    /// Convenience method for analyzing text with specified dialect
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - dialect: English dialect (American, British, Canadian, Australian)
    /// - Returns: Result containing analysis result or error
    @objc public func analyzeText(_ text: String, dialect: String) -> GrammarAnalysisResult {
        analyzeText(
            text,
            dialect: dialect,
            enableInternetAbbrev: true,
            enableGenZSlang: true,
            enableITTerminology: true,
            enableLanguageDetection: false,
            excludedLanguages: [],
            enableSentenceStartCapitalization: true
        )
    }

    /// Async convenience method for analyzing text with default parameters
    ///
    /// - Parameter text: The text to analyze
    /// - Returns: Analysis result
    @available(macOS 10.15, *)
    public func analyzeText(_ text: String) async -> GrammarAnalysisResult {
        await analyzeText(
            text,
            dialect: "American",
            enableInternetAbbrev: true,
            enableGenZSlang: true,
            enableITTerminology: true,
            enableLanguageDetection: false,
            excludedLanguages: [],
            enableSentenceStartCapitalization: true
        )
    }

    /// Async convenience method for analyzing text with specified dialect
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - dialect: English dialect (American, British, Canadian, Australian)
    /// - Returns: Analysis result
    @available(macOS 10.15, *)
    public func analyzeText(_ text: String, dialect: String) async -> GrammarAnalysisResult {
        await analyzeText(
            text,
            dialect: dialect,
            enableInternetAbbrev: true,
            enableGenZSlang: true,
            enableITTerminology: true,
            enableLanguageDetection: false,
            excludedLanguages: [],
            enableSentenceStartCapitalization: true
        )
    }
}
