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
    /// - Returns: Result containing analysis result or error
    @objc public func analyzeText(_ text: String, dialect: String, enableInternetAbbrev: Bool, enableGenZSlang: Bool) -> GrammarAnalysisResult {
        // Call FFI function with dialect and slang options
        let ffiResult = analyze_text(text, dialect, enableInternetAbbrev, enableGenZSlang)

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
    /// - Returns: Analysis result
    @available(macOS 10.15, *)
    public func analyzeText(_ text: String, dialect: String, enableInternetAbbrev: Bool, enableGenZSlang: Bool) async -> GrammarAnalysisResult {
        await Task.detached(priority: .userInitiated) { [text, dialect, enableInternetAbbrev, enableGenZSlang] in
            // Call FFI function directly in detached task
            let ffiResult = analyze_text(text, dialect, enableInternetAbbrev, enableGenZSlang)
            return GrammarAnalysisResult(ffiResult: ffiResult)
        }.value
    }

    // MARK: - Convenience Methods

    /// Convenience method for analyzing text with default parameters
    ///
    /// - Parameter text: The text to analyze
    /// - Returns: Result containing analysis result or error
    @objc public func analyzeText(_ text: String) -> GrammarAnalysisResult {
        analyzeText(text, dialect: "American", enableInternetAbbrev: true, enableGenZSlang: true)
    }

    /// Convenience method for analyzing text with specified dialect
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - dialect: English dialect (American, British, Canadian, Australian)
    /// - Returns: Result containing analysis result or error
    @objc public func analyzeText(_ text: String, dialect: String) -> GrammarAnalysisResult {
        analyzeText(text, dialect: dialect, enableInternetAbbrev: true, enableGenZSlang: true)
    }

    /// Async convenience method for analyzing text with default parameters
    ///
    /// - Parameter text: The text to analyze
    /// - Returns: Analysis result
    @available(macOS 10.15, *)
    public func analyzeText(_ text: String) async -> GrammarAnalysisResult {
        await analyzeText(text, dialect: "American", enableInternetAbbrev: true, enableGenZSlang: true)
    }

    /// Async convenience method for analyzing text with specified dialect
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - dialect: English dialect (American, British, Canadian, Australian)
    /// - Returns: Analysis result
    @available(macOS 10.15, *)
    public func analyzeText(_ text: String, dialect: String) async -> GrammarAnalysisResult {
        await analyzeText(text, dialect: dialect, enableInternetAbbrev: true, enableGenZSlang: true)
    }
}
