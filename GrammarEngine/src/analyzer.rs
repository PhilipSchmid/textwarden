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

            // Create a unique lint_id by combining category with normalized message
            // This ensures each specific rule gets its own identifier
            // Example: "Formatting::horizontal_ellipsis_must_have_3_dots"
            let message_key = message
                .to_lowercase()
                .chars()
                .map(|c| if c.is_alphanumeric() { c } else { '_' })
                .collect::<String>()
                .split('_')
                .filter(|s| !s.is_empty())
                .take(8) // Limit to first 8 words to avoid very long IDs
                .collect::<Vec<&str>>()
                .join("_");
            let lint_id = format!("{}::{}", category, message_key);

            // Extract suggestions from Harper's lint
            // Harper provides suggestions as Suggestion enum with ReplaceWith variant
            let suggestions: Vec<String> = lint.suggestions
                .iter()
                .filter_map(|suggestion| {
                    // Extract text from ReplaceWith variant
                    // Each suggestion contains a Vec<char> with the replacement text
                    match suggestion {
                        harper_core::linting::Suggestion::ReplaceWith(chars) => {
                            Some(chars.iter().collect())
                        }
                        _ => None
                    }
                })
                .collect();

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
    fn test_harper_suggestions_debug() {
        use harper_core::{Document, linting::{Linter, LintGroup}, Dialect};
        use harper_core::spell::MutableDictionary;
        use std::sync::Arc;

        // Create a dictionary
        let dictionary = Arc::new(MutableDictionary::curated());

        // Initialize linter
        let mut linter = LintGroup::new_curated(dictionary, Dialect::American);

        // Test text with obvious errors that should generate suggestions
        let test_text = "Teh quick brown fox jumps over teh lazy dog. I can has cheezburger?";
        let document = Document::new_plain_english_curated(test_text);

        // Get lints
        let lints = linter.lint(&document);

        println!("\n=== HARPER SUGGESTIONS DEBUG ===");
        println!("Found {} lints", lints.len());

        for (i, lint) in lints.iter().enumerate() {
            println!("\n--- Lint {} ---", i + 1);
            println!("Message: {}", lint.message);
            println!("Span: {:?}", lint.span);
            println!("Priority: {}", lint.priority);
            println!("Lint Kind: {:?}", lint.lint_kind);
            println!("Suggestions count: {}", lint.suggestions.len());

            for (j, suggestion) in lint.suggestions.iter().enumerate() {
                println!("  Suggestion {}: {:?}", j + 1, suggestion);
            }
        }
        println!("=== END DEBUG ===\n");
    }

    #[test]
    fn test_suggestions_extraction() {
        // Test that suggestions are properly extracted from Harper
        let result = analyze_text("Teh quick brown fox.", "American");

        // Should find at least one error for "Teh"
        assert!(!result.errors.is_empty(), "Should detect 'Teh' as an error");

        // Find the error for "Teh"
        let teh_error = result.errors.iter()
            .find(|e| e.start == 0 && e.end == 3)
            .expect("Should find error for 'Teh'");

        // Should have suggestions
        assert!(!teh_error.suggestions.is_empty(),
                "Error for 'Teh' should have suggestions");

        println!("\n=== SUGGESTIONS EXTRACTION TEST ===");
        println!("Error: {}", teh_error.message);
        println!("Suggestions ({}): {:?}",
                 teh_error.suggestions.len(),
                 teh_error.suggestions);

        // Verify suggestions are strings, not empty
        for suggestion in &teh_error.suggestions {
            assert!(!suggestion.is_empty(), "Suggestion should not be empty");
            assert!(suggestion.chars().all(|c| c.is_alphabetic()),
                    "Suggestion should contain only letters");
        }
        println!("=== END TEST ===\n");
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
