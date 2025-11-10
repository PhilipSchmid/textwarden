// FFI Bridge - Swift-Rust interop using swift-bridge
//
// Defines FFI-safe structs and functions for Swift integration.

use crate::analyzer;

#[swift_bridge::bridge]
mod ffi {
    pub enum ErrorSeverity {
        Error,
        Warning,
        Info,
    }

    // Opaque type for GrammarError to support Vec<GrammarError>
    extern "Rust" {
        type GrammarError;

        fn start(&self) -> usize;
        fn end(&self) -> usize;
        fn message(&self) -> String;
        fn severity(&self) -> ErrorSeverity;
        fn category(&self) -> String;
        fn lint_id(&self) -> String;
        fn suggestions(&self) -> Vec<String>;
    }

    // Opaque type for AnalysisResult
    extern "Rust" {
        type AnalysisResult;

        fn errors(&self) -> Vec<GrammarError>;
        fn word_count(&self) -> usize;
        fn analysis_time_ms(&self) -> u64;
    }

    extern "Rust" {
        fn analyze_text(text: String, dialect: String) -> AnalysisResult;
    }
}

// FFI type implementations
#[derive(Clone)]
pub struct GrammarError {
    start: usize,
    end: usize,
    message: String,
    severity: analyzer::ErrorSeverity,
    category: String,
    lint_id: String,
    suggestions: Vec<String>,
}

impl GrammarError {
    fn start(&self) -> usize {
        self.start
    }

    fn end(&self) -> usize {
        self.end
    }

    fn message(&self) -> String {
        self.message.clone()
    }

    fn severity(&self) -> ffi::ErrorSeverity {
        match self.severity {
            analyzer::ErrorSeverity::Error => ffi::ErrorSeverity::Error,
            analyzer::ErrorSeverity::Warning => ffi::ErrorSeverity::Warning,
            analyzer::ErrorSeverity::Info => ffi::ErrorSeverity::Info,
        }
    }

    fn category(&self) -> String {
        self.category.clone()
    }

    fn lint_id(&self) -> String {
        self.lint_id.clone()
    }

    fn suggestions(&self) -> Vec<String> {
        self.suggestions.clone()
    }
}

pub struct AnalysisResult {
    errors: Vec<GrammarError>,
    word_count: usize,
    analysis_time_ms: u64,
}

impl AnalysisResult {
    fn errors(&self) -> Vec<GrammarError> {
        self.errors.clone()
    }

    fn word_count(&self) -> usize {
        self.word_count
    }

    fn analysis_time_ms(&self) -> u64 {
        self.analysis_time_ms
    }
}

// FFI wrapper that calls the analyzer and converts types
fn analyze_text(text: String, dialect: String) -> AnalysisResult {
    let result = analyzer::analyze_text(&text, &dialect);

    // Convert analyzer types to FFI types
    let errors = result.errors
        .into_iter()
        .map(|err| GrammarError {
            start: err.start,
            end: err.end,
            message: err.message,
            severity: err.severity,
            category: err.category,
            lint_id: err.lint_id,
            suggestions: err.suggestions,
        })
        .collect();

    AnalysisResult {
        errors,
        word_count: result.word_count,
        analysis_time_ms: result.analysis_time_ms,
    }
}
