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
    /// - Returns: Result containing analysis result or error
    @objc public func analyzeText(_ text: String, dialect: String) -> GrammarAnalysisResult {
        // Call FFI function with dialect
        let ffiResult = analyze_text(text, dialect)

        // Convert FFI result to Swift model
        return GrammarAnalysisResult(ffiResult: ffiResult)
    }

    /// Async wrapper for text analysis (non-blocking)
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - dialect: English dialect (American, British, Canadian, Australian)
    /// - Returns: Analysis result
    @available(macOS 10.15, *)
    public func analyzeText(_ text: String, dialect: String) async -> GrammarAnalysisResult {
        await Task.detached(priority: .userInitiated) { [text, dialect] in
            // Call FFI function directly in detached task
            let ffiResult = analyze_text(text, dialect)
            return GrammarAnalysisResult(ffiResult: ffiResult)
        }.value
    }
}
