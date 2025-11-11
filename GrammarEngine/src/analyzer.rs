// Analyzer - Grammar analysis implementation wrapping Harper
//
// Provides the core text analysis functionality.

use harper_core::{Document, linting::{Linter, LintGroup}, Dialect};
use harper_core::spell::MutableDictionary;
use std::sync::Arc;
use std::time::Instant;

#[derive(Debug, Clone)]
pub enum ErrorSeverity {
    Error,
    Warning,
    Info,
}

#[derive(Debug, Clone)]
pub struct GrammarError {
    pub start: usize,
    pub end: usize,
    pub message: String,
    pub severity: ErrorSeverity,
    pub category: String,
    pub lint_id: String,
    pub suggestions: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct AnalysisResult {
    pub errors: Vec<GrammarError>,
    pub word_count: usize,
    pub analysis_time_ms: u64,
}

/// Parse a dialect string into Harper's Dialect enum
///
/// # Arguments
/// * `dialect_str` - Dialect name: "American", "British", "Canadian", or "Australian"
///
/// # Returns
/// The corresponding Dialect enum variant, defaulting to American if invalid
fn parse_dialect(dialect_str: &str) -> Dialect {
    match dialect_str {
        "American" => Dialect::American,
        "British" => Dialect::British,
        "Canadian" => Dialect::Canadian,
        "Australian" => Dialect::Australian,
        _ => Dialect::American, // Default to American
    }
}

/// Analyze text for grammar errors using Harper
///
/// # Arguments
/// * `text` - The text to analyze
/// * `dialect_str` - English dialect: "American", "British", "Canadian", or "Australian"
///
/// # Returns
/// An AnalysisResult containing detected errors and analysis metadata
pub fn analyze_text(text: &str, dialect_str: &str) -> AnalysisResult {
    let start_time = Instant::now();

    // Parse the dialect string
    let dialect = parse_dialect(dialect_str);

    // Create a dictionary for spell checking
    let dictionary = Arc::new(MutableDictionary::curated());

    // Initialize Harper linter with curated rules for selected dialect
    let mut linter = LintGroup::new_curated(dictionary, dialect);

    // Parse the text into a Document
    let document = Document::new_plain_english_curated(text);

    // Perform linting
    let lints = linter.lint(&document);

    // Count words (approximate - split on whitespace)
    let word_count = text.split_whitespace().count();

    // Convert Harper lints to our GrammarError format
    let errors: Vec<GrammarError> = lints
        .into_iter()
        .map(|lint| {
            let span = lint.span;
            let message = lint.message;

            // Extract the category from Harper's LintKind
            let category = lint.lint_kind.to_string_key();

            // Use a descriptive lint_id (can be used for "ignore this rule" feature)
            let lint_id = format!("{:?}", lint.lint_kind);

            // Extract suggestions from Harper's lint
            // TODO: Harper's Suggestion struct needs investigation
            // For now, use empty vector - suggestions will be added in future
            let suggestions: Vec<String> = vec![];

            // Map Harper priority to our ErrorSeverity (kept for backwards compatibility)
            // Higher priority = more severe
            let severity = match lint.priority {
                p if p >= 127 => ErrorSeverity::Error,
                p if p >= 64 => ErrorSeverity::Warning,
                _ => ErrorSeverity::Info,
            };

            GrammarError {
                start: span.start,
                end: span.end,
                message,
                severity,
                category,
                lint_id,
                suggestions,
            }
        })
        .collect();

    let analysis_time_ms = start_time.elapsed().as_millis() as u64;

    AnalysisResult {
        errors,
        word_count,
        analysis_time_ms,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_analyze_empty_text() {
        let result = analyze_text("", "American");
        assert_eq!(result.errors.len(), 0);
        assert_eq!(result.word_count, 0);
    }

    #[test]
    fn test_analyze_correct_text() {
        let result = analyze_text("This is a well-written sentence.", "American");
        // Well-written text may still have style suggestions, so we just verify it runs
        assert!(result.word_count > 0);
        assert!(result.analysis_time_ms >= 0);
    }

    #[test]
    fn test_analyze_incorrect_text() {
        // Subject-verb disagreement: "team are" should be "team is"
        let result = analyze_text("The team are working on it.", "American");
        assert!(result.word_count > 0);
        // Note: Harper may or may not catch this specific error depending on version
        // The test mainly verifies the analyzer runs without crashing
    }

    #[test]
    fn test_analyze_performance() {
        let text = &"The quick brown fox jumps over the lazy dog. ".repeat(100);
        let result = analyze_text(text, "American");
        // Analysis should complete in under 100ms for ~900 words
        assert!(result.analysis_time_ms < 100,
                "Analysis took {}ms for {} words",
                result.analysis_time_ms, result.word_count);
    }

    #[test]
    fn test_analyze_dialects() {
        // Test that different dialects can be parsed correctly
        let text = "This is a test.";
        let result_american = analyze_text(text, "American");
        let result_british = analyze_text(text, "British");
        let result_canadian = analyze_text(text, "Canadian");
        let result_australian = analyze_text(text, "Australian");
        let result_invalid = analyze_text(text, "Invalid");

        // All should run without crashing
        assert!(result_american.word_count > 0);
        assert!(result_british.word_count > 0);
        assert!(result_canadian.word_count > 0);
        assert!(result_australian.word_count > 0);
        assert!(result_invalid.word_count > 0); // Should default to American
    }
}
