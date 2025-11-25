// GrammarError.swift
// Swift model for grammar errors

import Foundation

/// Severity level of a grammar error
@objc public enum GrammarErrorSeverity: Int, CustomStringConvertible {
    case error
    case warning
    case info

    public var description: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        }
    }

    /// Convert from FFI ErrorSeverity enum
    init(ffiSeverity: ErrorSeverity) {
        switch ffiSeverity {
        case .Error: self = .error
        case .Warning: self = .warning
        case .Info: self = .info
        }
    }
}

/// A grammar error detected in text
@objc public class GrammarErrorModel: NSObject {
    /// Zero-based character offset where error starts
    @objc public let start: Int

    /// Zero-based character offset where error ends
    @objc public let end: Int

    /// Human-readable error message
    @objc public let message: String

    /// Error severity level (kept for backwards compatibility)
    @objc public let severity: GrammarErrorSeverity

    /// Grammar check category (e.g., "Spelling", "Grammar", "Style")
    @objc public let category: String

    /// Unique identifier for the lint rule
    @objc public let lintId: String

    /// Suggested replacements for the error
    @objc public let suggestions: [String]

    /// Initialize from FFI GrammarError (opaque type)
    init(ffiError: GrammarErrorRef) {
        self.start = Int(ffiError.start())
        self.end = Int(ffiError.end())
        self.message = ffiError.message().toString()
        self.severity = GrammarErrorSeverity(ffiSeverity: ffiError.severity())
        self.category = ffiError.category().toString()
        self.lintId = ffiError.lint_id().toString()

        // Convert RustVec<RustString> to [String]
        let rustSuggestions = ffiError.suggestions()
        self.suggestions = rustSuggestions.map { rustStrRef in
            rustStrRef.as_str().toString()
        }

        super.init()
    }

    /// Convenience initializer for testing
    @objc public init(start: Int, end: Int, message: String, severity: GrammarErrorSeverity, category: String, lintId: String, suggestions: [String] = []) {
        self.start = start
        self.end = end
        self.message = message
        self.severity = severity
        self.category = category
        self.lintId = lintId
        self.suggestions = suggestions
        super.init()
    }

    public override var description: String {
        let suggestionsStr = suggestions.isEmpty ? "" : " -> [\(suggestions.joined(separator: ", "))]"
        return "[\(severity)] \(message) (\(lintId)) at \(start):\(end)\(suggestionsStr)"
    }
}

/// Result of analyzing text for grammar errors
@objc public class GrammarAnalysisResult: NSObject {
    /// List of detected grammar errors
    @objc public let errors: [GrammarErrorModel]

    /// Total number of words analyzed
    @objc public let wordCount: Int

    /// Analysis time in milliseconds
    @objc public let analysisTimeMs: UInt64

    /// Memory usage before analysis (bytes)
    @objc public let memoryBeforeBytes: UInt64

    /// Memory usage after analysis (bytes)
    @objc public let memoryAfterBytes: UInt64

    /// Memory delta (after - before) in bytes
    @objc public let memoryDeltaBytes: Int64

    /// Initialize from FFI AnalysisResult (opaque type)
    init(ffiResult: AnalysisResultRef) {
        let ffiErrors = ffiResult.errors()
        self.errors = ffiErrors.map { GrammarErrorModel(ffiError: $0) }
        self.wordCount = Int(ffiResult.word_count())
        self.analysisTimeMs = ffiResult.analysis_time_ms()
        self.memoryBeforeBytes = ffiResult.memory_before_bytes()
        self.memoryAfterBytes = ffiResult.memory_after_bytes()
        self.memoryDeltaBytes = ffiResult.memory_delta_bytes()
        super.init()
    }

    /// Convenience initializer for testing
    @objc public init(errors: [GrammarErrorModel], wordCount: Int, analysisTimeMs: UInt64, memoryBeforeBytes: UInt64 = 0, memoryAfterBytes: UInt64 = 0, memoryDeltaBytes: Int64 = 0) {
        self.errors = errors
        self.wordCount = wordCount
        self.analysisTimeMs = analysisTimeMs
        self.memoryBeforeBytes = memoryBeforeBytes
        self.memoryAfterBytes = memoryAfterBytes
        self.memoryDeltaBytes = memoryDeltaBytes
        super.init()
    }

    public override var description: String {
        "Analysis: \(errors.count) errors found in \(wordCount) words (\(analysisTimeMs)ms, mem: \(memoryAfterBytes / 1024)KB)"
    }
}
