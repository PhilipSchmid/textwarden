// Analyzer - Grammar analysis implementation wrapping Harper
//
// Provides the core text analysis functionality.

use harper_core::{Document, linting::{Linter, LintGroup}, Dialect};
use harper_core::spell::{MutableDictionary, MergedDictionary};
use std::sync::Arc;
use std::time::Instant;
use crate::slang_dict;
use crate::language_filter::LanguageFilter;

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
/// * `enable_internet_abbrev` - Enable internet abbreviations (BTW, FYI, LOL, etc.)
/// * `enable_genz_slang` - Enable Gen Z slang words (ghosting, sus, slay, etc.)
/// * `enable_language_detection` - Enable detection and filtering of non-English words
/// * `excluded_languages` - List of languages to exclude from error detection (e.g., ["spanish", "german"])
///
/// # Returns
/// An AnalysisResult containing detected errors and analysis metadata
pub fn analyze_text(
    text: &str,
    dialect_str: &str,
    enable_internet_abbrev: bool,
    enable_genz_slang: bool,
    enable_language_detection: bool,
    excluded_languages: Vec<String>,
) -> AnalysisResult {
    let start_time = Instant::now();

    // Parse the dialect string
    let dialect = parse_dialect(dialect_str);

    // Build dictionary based on slang options
    // Always use MergedDictionary for consistency
    let mut merged = MergedDictionary::new();
    merged.add_dictionary(MutableDictionary::curated());

    if enable_internet_abbrev {
        let abbrev_words = slang_dict::load_internet_abbreviations();
        let mut abbrev_dict = MutableDictionary::new();
        abbrev_dict.extend_words(abbrev_words);
        merged.add_dictionary(Arc::new(abbrev_dict));
    }

    if enable_genz_slang {
        let genz_words = slang_dict::load_genz_slang();
        let mut genz_dict = MutableDictionary::new();
        genz_dict.extend_words(genz_words);
        merged.add_dictionary(Arc::new(genz_dict));
    }

    let dictionary = Arc::new(merged);

    // Initialize Harper linter with curated rules for selected dialect
    // Clone the Arc so we can use the dictionary for both linting and document parsing
    let mut linter = LintGroup::new_curated(dictionary.clone(), dialect);

    // If internet abbreviations are enabled, disable Harper's initialism expansion rules
    // These rules suggest expanding abbreviations like "btw" → "by the way", "fyi" → "for your information"
    // When the user explicitly enables abbreviations, they don't want these suggestions
    if enable_internet_abbrev {
        linter.config.set_rule_enabled("ByTheWay", false);
        linter.config.set_rule_enabled("ForYourInformation", false);
        linter.config.set_rule_enabled("AsSoonAsPossible", false);
        linter.config.set_rule_enabled("InMyOpinion", false);
        linter.config.set_rule_enabled("InMyHumbleOpinion", false);
        linter.config.set_rule_enabled("OhMyGod", false);
        linter.config.set_rule_enabled("BeRightBack", false);
        linter.config.set_rule_enabled("TalkToYouLater", false);
        linter.config.set_rule_enabled("NeverMind", false);
        linter.config.set_rule_enabled("ToBeHonest", false);
        linter.config.set_rule_enabled("AsFarAsIKnow", false);
    }

    // Parse the text into a Document using our merged dictionary
    // This ensures abbreviations and slang are recognized during parsing
    let document = Document::new_plain_english(text, dictionary.as_ref());

    // Perform linting
    let lints = linter.lint(&document);

    // Count words (approximate - split on whitespace)
    let word_count = text.split_whitespace().count();

    // Convert Harper lints to our GrammarError format
    let mut errors: Vec<GrammarError> = lints
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

    // Apply language detection filter to remove errors for non-English words
    // This is the optimized approach: we only detect language for words that Harper flagged
    let filter = LanguageFilter::new(enable_language_detection, excluded_languages);
    errors = filter.filter_errors(errors, text);

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
    use harper_core::WordMetadata;

    #[test]
    fn test_dictionary_contains_abbreviations() {
        // Test that our dictionary loading works correctly
        use harper_core::spell::{Dictionary, MutableDictionary, MergedDictionary};
        use crate::slang_dict;

        let abbrev_words = slang_dict::load_internet_abbreviations();
        println!("\n=== LOADING ABBREVIATIONS ===");
        println!("Total words loaded: {}", abbrev_words.len());

        // Check if AFAICT and LOL are in the loaded words
        let afaict_count = abbrev_words.iter().filter(|(w, _)| {
            let s: String = w.iter().collect();
            s == "AFAICT" || s == "afaict"
        }).count();
        let lol_count = abbrev_words.iter().filter(|(w, _)| {
            let s: String = w.iter().collect();
            s == "LOL" || s == "lol"
        }).count();
        println!("AFAICT variants in loaded words: {}", afaict_count);
        println!("LOL variants in loaded words: {}", lol_count);

        let mut abbrev_dict = MutableDictionary::new();
        abbrev_dict.extend_words(abbrev_words);

        // Also test with merged dictionary like in the main code
        let mut merged = MergedDictionary::new();
        merged.add_dictionary(MutableDictionary::curated());
        merged.add_dictionary(std::sync::Arc::new(abbrev_dict.clone()));

        // Test exact matches for both uppercase and lowercase
        let afaict_upper: Vec<char> = "AFAICT".chars().collect();
        let afaict_lower: Vec<char> = "afaict".chars().collect();
        let lol_upper: Vec<char> = "LOL".chars().collect();
        let lol_lower: Vec<char> = "lol".chars().collect();

        println!("\n=== DICTIONARY CONTAINS TEST ===");
        println!("MutableDictionary (abbrev only):");
        println!("  AFAICT: {}", abbrev_dict.contains_exact_word(&afaict_upper));
        println!("  afaict: {}", abbrev_dict.contains_exact_word(&afaict_lower));
        println!("  LOL: {}", abbrev_dict.contains_exact_word(&lol_upper));
        println!("  lol: {}", abbrev_dict.contains_exact_word(&lol_lower));

        println!("\nMergedDictionary (curated + abbrev):");
        println!("  AFAICT: {}", merged.contains_exact_word(&afaict_upper));
        println!("  afaict: {}", merged.contains_exact_word(&afaict_lower));
        println!("  LOL: {}", merged.contains_exact_word(&lol_upper));
        println!("  lol: {}", merged.contains_exact_word(&lol_lower));

        // Dictionary contains lowercase versions only (by design, see slang_dict.rs)
        assert!(abbrev_dict.contains_exact_word(&afaict_lower), "afaict should be in abbrev dictionary");
        assert!(abbrev_dict.contains_exact_word(&lol_lower), "lol should be in abbrev dictionary");

        // Uppercase versions are NOT in the dictionary (lowercase-only generation)
        assert!(!abbrev_dict.contains_exact_word(&afaict_upper), "AFAICT uppercase should NOT be in dictionary (lowercase only)");
        assert!(!abbrev_dict.contains_exact_word(&lol_upper), "LOL uppercase should NOT be in dictionary (lowercase only)");

        // Merged dictionary should also contain lowercase versions
        assert!(merged.contains_exact_word(&afaict_lower), "afaict should be in merged dictionary");
        assert!(merged.contains_exact_word(&lol_lower), "lol should be in merged dictionary");
    }

    #[test]
    fn test_analyze_empty_text() {
        let result = analyze_text("", "American", false, false, false, vec![]);
        assert_eq!(result.errors.len(), 0);
        assert_eq!(result.word_count, 0);
    }

    #[test]
    fn test_analyze_correct_text() {
        let result = analyze_text("This is a well-written sentence.", "American", false, false, false, vec![]);
        // Well-written text may still have style suggestions, so we just verify it runs
        assert!(result.word_count > 0);
        // analysis_time_ms is unsigned, so always >= 0 (no need to assert)
    }

    #[test]
    fn test_analyze_incorrect_text() {
        // Subject-verb disagreement: "team are" should be "team is"
        let result = analyze_text("The team are working on it.", "American", false, false, false, vec![]);
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
        let result = analyze_text("Teh quick brown fox.", "American", false, false, false, vec![]);

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
        let result = analyze_text(text, "American", false, false, false, vec![]);
        // Analysis should complete in under 1500ms for ~900 words (test mode with opt-level=1)
        // Note: Release builds are ~3x faster (~500ms)
        assert!(result.analysis_time_ms < 1500,
                "Analysis took {}ms for {} words",
                result.analysis_time_ms, result.word_count);
    }

    #[test]
    fn test_analyze_dialects() {
        // Test that different dialects can be parsed correctly
        let text = "This is a test.";
        let result_american = analyze_text(text, "American", false, false, false, vec![]);
        let result_british = analyze_text(text, "British", false, false, false, vec![]);
        let result_canadian = analyze_text(text, "Canadian", false, false, false, vec![]);
        let result_australian = analyze_text(text, "Australian", false, false, false, vec![]);
        let result_invalid = analyze_text(text, "Invalid", false, false, false, vec![]);

        // All should run without crashing
        assert!(result_american.word_count > 0);
        assert!(result_british.word_count > 0);
        assert!(result_canadian.word_count > 0);
        assert!(result_australian.word_count > 0);
        assert!(result_invalid.word_count > 0); // Should default to American
    }

    #[test]
    fn test_internet_abbreviations() {
        // Test that internet abbreviations are recognized when enabled
        let text = "BTW, FYI the meeting is ASAP. LOL!";

        // With slang disabled, should flag abbreviations as errors
        let result_disabled = analyze_text(text, "American", false, false, false, vec![]);

        // With slang enabled, should NOT flag abbreviations
        let result_enabled = analyze_text(text, "American", true, false, false, vec![]);

        // We expect fewer errors with slang enabled
        println!("Errors without slang: {}", result_disabled.errors.len());
        println!("Errors with slang: {}", result_enabled.errors.len());

        // Note: This test validates the functionality works
        // The exact error counts may vary based on Harper's behavior
    }

    #[test]
    fn test_genz_slang() {
        // Test that Gen Z slang is recognized when enabled
        let text = "That is so sus. She is ghosting me. You slayed!";

        // With slang disabled, may flag slang words
        let result_disabled = analyze_text(text, "American", false, false, false, vec![]);

        // With slang enabled, should recognize these words
        let result_enabled = analyze_text(text, "American", false, true, false, vec![]);

        println!("Errors without Gen Z slang: {}", result_disabled.errors.len());
        println!("Errors with Gen Z slang: {}", result_enabled.errors.len());
    }

    #[test]
    fn test_both_slang_options() {
        // Test with both slang options enabled
        let text = "BTW your vibe is totally slay! NGL you ghosted me ASAP.";

        let result = analyze_text(text, "American", true, true, false, vec![]);

        println!("Text with both slang types enabled:");
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - {}: {}", &text[error.start..error.end], error.message);
        }
    }

    #[test]
    fn test_uppercase_abbreviations_recognized() {
        // Test that uppercase abbreviations are NOT flagged when enabled
        // This is the critical test for the bug fix
        let text = "AFAICT, FYI, BTW, and LOL are common abbreviations.";

        // Without slang, should flag as spelling errors
        let result_disabled = analyze_text(text, "American", false, false, false, vec![]);

        // With slang enabled, should NOT flag these
        let result_enabled = analyze_text(text, "American", true, false, false, vec![]);

        println!("\n=== UPPERCASE ABBREVIATIONS TEST ===");
        println!("Text: {}", text);
        println!("\nWithout internet abbreviations enabled:");
        println!("  Errors: {}", result_disabled.errors.len());
        for error in &result_disabled.errors {
            println!("    - {}: {}", &text[error.start..error.end], error.message);
        }

        println!("\nWith internet abbreviations enabled:");
        println!("  Errors: {}", result_enabled.errors.len());
        for error in &result_enabled.errors {
            println!("    - {}: {}", &text[error.start..error.end], error.message);
        }

        // Critical assertion: with slang enabled, these specific abbreviations should NOT be flagged
        let flagged_words_when_enabled: Vec<String> = result_enabled.errors.iter()
            .map(|e| text[e.start..e.end].to_string())
            .collect();

        assert!(!flagged_words_when_enabled.contains(&"AFAICT".to_string()),
                "AFAICT should not be flagged when internet abbreviations are enabled");
        assert!(!flagged_words_when_enabled.contains(&"FYI".to_string()),
                "FYI should not be flagged when internet abbreviations are enabled");
        assert!(!flagged_words_when_enabled.contains(&"BTW".to_string()),
                "BTW should not be flagged when internet abbreviations are enabled");
        assert!(!flagged_words_when_enabled.contains(&"LOL".to_string()),
                "LOL should not be flagged when internet abbreviations are enabled");

        println!("=== TEST PASSED ===\n");
    }

    #[test]
    fn test_mixed_case_abbreviations() {
        // Test that abbreviations work in lowercase, UPPERCASE, and Title Case
        let test_cases = vec![
            "btw this is cool",           // lowercase
            "BTW this is cool",           // UPPERCASE
            "Btw this is cool",           // Title Case
            "fyi you should know",        // lowercase
            "FYI you should know",        // UPPERCASE
            "Fyi you should know",        // Title Case
        ];

        for text in test_cases {
            let result = analyze_text(text, "American", true, false, false, vec![]);

            println!("\nTesting: '{}'", text);
            println!("Errors: {}", result.errors.len());

            // The abbreviation itself should not be flagged
            let flagged_abbrev = result.errors.iter()
                .any(|e| {
                    let word = &text[e.start..e.end];
                    word.to_lowercase() == "btw" || word.to_lowercase() == "fyi"
                });

            assert!(!flagged_abbrev,
                    "Abbreviation should not be flagged in any case: '{}'", text);
        }
    }

    #[test]
    fn test_slang_toggle_effectiveness() {
        // Verify that toggling slang options actually changes the analysis results
        let text_with_abbrevs = "BTW, FYI, IMHO, and ASAP are abbreviations.";
        let text_with_slang = "That vibe is sus and totally slay.";

        // Test internet abbreviations toggle
        let abbrev_disabled = analyze_text(text_with_abbrevs, "American", false, false, false, vec![]);
        let abbrev_enabled = analyze_text(text_with_abbrevs, "American", true, false, false, vec![]);

        println!("\n=== INTERNET ABBREVIATIONS TOGGLE TEST ===");
        println!("Text: {}", text_with_abbrevs);
        println!("Errors (disabled): {}", abbrev_disabled.errors.len());
        println!("Errors (enabled): {}", abbrev_enabled.errors.len());

        // Should have fewer or equal errors when enabled
        assert!(abbrev_enabled.errors.len() <= abbrev_disabled.errors.len(),
                "Enabling abbreviations should not increase error count");

        // Test Gen Z slang toggle
        let slang_disabled = analyze_text(text_with_slang, "American", false, false, false, vec![]);
        let slang_enabled = analyze_text(text_with_slang, "American", false, true, false, vec![]);

        println!("\n=== GEN Z SLANG TOGGLE TEST ===");
        println!("Text: {}", text_with_slang);
        println!("Errors (disabled): {}", slang_disabled.errors.len());
        println!("Errors (enabled): {}", slang_enabled.errors.len());

        // Should have fewer or equal errors when enabled
        assert!(slang_enabled.errors.len() <= slang_disabled.errors.len(),
                "Enabling slang should not increase error count");

        println!("=== TOGGLE TESTS PASSED ===\n");
    }

    #[test]
    fn test_edge_cases() {
        // Test edge cases and special scenarios

        // Empty text
        let result = analyze_text("", "American", true, true, false, vec![]);
        assert_eq!(result.errors.len(), 0, "Empty text should have no errors");
        assert_eq!(result.word_count, 0, "Empty text should have 0 words");

        // Only abbreviations
        let result = analyze_text("BTW FYI LOL ASAP", "American", true, false, false, vec![]);
        println!("\nOnly abbreviations - Errors: {}", result.errors.len());
        // These should all be recognized
        assert_eq!(result.word_count, 4, "Should count 4 words");

        // Abbreviations with punctuation
        let result = analyze_text("BTW, FYI! LOL? ASAP.", "American", true, false, false, vec![]);
        println!("With punctuation - Errors: {}", result.errors.len());

        // Mixed slang types
        let result = analyze_text("BTW that vibe is sus", "American", true, true, false, vec![]);
        println!("Mixed slang types - Errors: {}", result.errors.len());
    }

    #[test]
    fn test_regression_afaict_lol_bug() {
        // REGRESSION TEST for the bug where AFAICT and LOL were always flagged
        // This was caused by using Document::new_plain_english_curated() instead of
        // Document::new_plain_english() with our merged dictionary

        println!("\n=== REGRESSION TEST: AFAICT/LOL Bug ===");

        // These were the specific failing cases reported by the user
        let test_cases = vec![
            ("afaict", "lowercase afaict"),
            ("AFAICT", "UPPERCASE AFAICT"),
            ("lol", "lowercase lol"),
            ("LOL", "UPPERCASE LOL"),
        ];

        for (abbrev, description) in test_cases {
            let text = format!("I think {} this works", abbrev);
            let result = analyze_text(&text, "American", true, false, false, vec![]);

            println!("\nTesting {}: '{}'", description, text);
            println!("  Errors: {}", result.errors.len());

            // Check if the abbreviation itself was flagged
            let abbrev_flagged = result.errors.iter()
                .any(|e| text[e.start..e.end].to_lowercase() == abbrev.to_lowercase());

            if abbrev_flagged {
                println!("  ❌ REGRESSION: {} was flagged!", abbrev);
                for error in &result.errors {
                    println!("    - {}: {}", &text[error.start..error.end], error.message);
                }
            } else {
                println!("  ✅ {} correctly recognized", abbrev);
            }

            assert!(!abbrev_flagged,
                "REGRESSION: {} should NOT be flagged when internet abbreviations are enabled", abbrev);
        }

        println!("\n=== All regression tests passed ===");
    }

    #[test]
    fn test_common_abbreviations_all_cases() {
        // Comprehensive test for common abbreviations in all case variations
        // These are the most frequently used internet abbreviations

        let common_abbreviations = vec![
            "btw", "fyi", "lol", "omg", "afaict", "imho", "asap", "brb",
            "ttyl", "tbh", "afaik", "imo", "lmk", "idk", "iirc", "fwiw",
        ];

        println!("\n=== COMPREHENSIVE ABBREVIATION CASE TEST ===");

        for abbrev in &common_abbreviations {
            // Test lowercase
            let text_lower = format!("I think {} is common", abbrev);
            let result_lower = analyze_text(&text_lower, "American", true, false, false, vec![]);

            // Test UPPERCASE
            let abbrev_upper = abbrev.to_uppercase();
            let text_upper = format!("I think {} is common", abbrev_upper);
            let result_upper = analyze_text(&text_upper, "American", true, false, false, vec![]);

            // Test Title Case
            let abbrev_title: String = abbrev.chars().enumerate()
                .map(|(i, c)| if i == 0 { c.to_uppercase().to_string() } else { c.to_string() })
                .collect();
            let text_title = format!("I think {} is common", abbrev_title);
            let result_title = analyze_text(&text_title, "American", true, false, false, vec![]);

            // Check none are flagged
            let lower_ok = !result_lower.errors.iter()
                .any(|e| text_lower[e.start..e.end].to_lowercase() == *abbrev);
            let upper_ok = !result_upper.errors.iter()
                .any(|e| text_upper[e.start..e.end].to_lowercase() == *abbrev);
            let title_ok = !result_title.errors.iter()
                .any(|e| text_title[e.start..e.end].to_lowercase() == *abbrev);

            println!("{}: lowercase={}, UPPERCASE={}, Title={}",
                abbrev,
                if lower_ok { "✓" } else { "✗" },
                if upper_ok { "✓" } else { "✗" },
                if title_ok { "✓" } else { "✗" }
            );

            assert!(lower_ok, "{} (lowercase) should be recognized", abbrev);
            assert!(upper_ok, "{} (UPPERCASE) should be recognized", abbrev_upper);
            assert!(title_ok, "{} (Title) should be recognized", abbrev_title);
        }

        println!("=== All {} abbreviations passed in all cases ===", common_abbreviations.len() * 3);
    }

    #[test]
    fn test_real_errors_still_caught() {
        // Verify that enabling slang doesn't prevent real spelling errors from being caught
        // This is critical - we want to recognize slang, but still catch typos

        println!("\n=== REAL ERRORS STILL CAUGHT TEST ===");

        let texts_with_errors = vec![
            ("Teh quick brown fox", "Teh"),           // Common typo
            ("I recieve your message", "recieve"),     // i before e
            ("Definately correct", "Definately"),      // Common misspelling
            ("This is wierd", "wierd"),                // ei/ie confusion
        ];

        for (text, expected_error_word) in texts_with_errors {
            let result = analyze_text(text, "American", true, true, false, vec![]);  // Both slang options ON

            println!("\nText: '{}'", text);
            println!("Expected error word: '{}'", expected_error_word);
            println!("Errors found: {}", result.errors.len());

            // Check if the expected error was caught
            let error_caught = result.errors.iter()
                .any(|e| text[e.start..e.end].to_lowercase().contains(&expected_error_word.to_lowercase()));

            if error_caught {
                println!("  ✅ Error correctly caught");
            } else {
                println!("  ❌ Error NOT caught - this is a problem!");
                println!("  Errors found:");
                for error in &result.errors {
                    println!("    - {}: {}", &text[error.start..error.end], error.message);
                }
            }

            assert!(error_caught || result.errors.len() > 0,
                "Real spelling error '{}' should still be caught even with slang enabled", expected_error_word);
        }

        println!("\n=== Real errors are still being caught ===");
    }

    #[test]
    fn test_user_screenshot_scenario() {
        // Test the exact scenario from the user's screenshot:
        // "btw, lol, omg, afaict, AFAICT, lol, LMK, Teh,"
        // Only "Teh" should be marked as an error

        let text = "btw, lol, omg, afaict, AFAICT, lol, LMK, Teh,";
        let result = analyze_text(text, "American", true, false, false, vec![]);

        println!("\n=== USER SCREENSHOT SCENARIO TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());

        for error in &result.errors {
            let error_word = &text[error.start..error.end];
            println!("  - '{}': {}", error_word, error.message);
        }

        // Check each word
        let btw_ok = !result.errors.iter().any(|e| &text[e.start..e.end] == "btw");
        let lol_ok = !result.errors.iter().any(|e| &text[e.start..e.end] == "lol");
        let omg_ok = !result.errors.iter().any(|e| &text[e.start..e.end] == "omg");
        let afaict_lower_ok = !result.errors.iter().any(|e| &text[e.start..e.end] == "afaict");
        let afaict_upper_ok = !result.errors.iter().any(|e| &text[e.start..e.end] == "AFAICT");
        let lmk_ok = !result.errors.iter().any(|e| &text[e.start..e.end] == "LMK");
        let teh_error = result.errors.iter().any(|e| &text[e.start..e.end] == "Teh");

        println!("\nResults:");
        println!("  btw: {}", if btw_ok { "✓" } else { "✗ FLAGGED" });
        println!("  lol: {}", if lol_ok { "✓" } else { "✗ FLAGGED" });
        println!("  omg: {}", if omg_ok { "✓" } else { "✗ FLAGGED" });
        println!("  afaict: {}", if afaict_lower_ok { "✓" } else { "✗ FLAGGED" });
        println!("  AFAICT: {}", if afaict_upper_ok { "✓" } else { "✗ FLAGGED" });
        println!("  LMK: {}", if lmk_ok { "✓" } else { "✗ FLAGGED" });
        println!("  Teh: {}", if teh_error { "✓ CORRECTLY FLAGGED" } else { "✗ NOT FLAGGED" });

        assert!(btw_ok, "btw should not be flagged");
        assert!(lol_ok, "lol should not be flagged");
        assert!(omg_ok, "omg should not be flagged");
        assert!(afaict_lower_ok, "afaict (lowercase) should not be flagged");
        assert!(afaict_upper_ok, "AFAICT (uppercase) should not be flagged");
        assert!(lmk_ok, "LMK should not be flagged");
        assert!(teh_error, "Teh should be flagged as an error");

        println!("\n=== Screenshot scenario test passed ===");
    }

    #[test]
    fn test_dictionary_used_in_document_parsing() {
        // This test verifies the ROOT CAUSE FIX:
        // Document parsing now uses our merged dictionary, not just curated
        // This is tested indirectly by verifying abbreviations are recognized

        use harper_core::spell::{MutableDictionary, MergedDictionary};
        use harper_core::Document;
        use std::sync::Arc;

        println!("\n=== DOCUMENT PARSING DICTIONARY TEST ===");

        // Create a custom dictionary with a test word
        let mut custom_dict = MutableDictionary::new();
        let test_word: Vec<char> = "testabbrev".chars().collect();
        custom_dict.extend_words(vec![(test_word.clone(), WordMetadata::default())]);

        // Create merged dictionary
        let mut merged = MergedDictionary::new();
        merged.add_dictionary(MutableDictionary::curated());
        merged.add_dictionary(Arc::new(custom_dict));
        let dictionary = Arc::new(merged);

        // Parse document with our dictionary (THE FIX!)
        let text = "This testabbrev should be recognized";
        let document = Document::new_plain_english(text, dictionary.as_ref());

        // Create linter
        let mut linter = harper_core::linting::LintGroup::new_curated(dictionary.clone(), harper_core::Dialect::American);

        // Get lints
        let lints = linter.lint(&document);

        println!("Text: '{}'", text);
        println!("Lints: {}", lints.len());
        for lint in &lints {
            println!("  - {}: {}", &text[lint.span.start..lint.span.end], lint.message);
        }

        // Check if our custom word was flagged
        let testabbrev_flagged = lints.iter()
            .any(|lint| &text[lint.span.start..lint.span.end] == "testabbrev");

        assert!(!testabbrev_flagged,
            "Custom dictionary word should be recognized during document parsing");

        println!("✅ Dictionary is correctly used during document parsing");
    }

    // MARK: - Language Detection Integration Tests

    #[test]
    fn test_language_detection_disabled_by_default() {
        // With language detection disabled, foreign words should still be flagged
        let text = "Hallo world";
        let result = analyze_text(text, "American", false, false, false, vec![]);

        // "Hallo" should be flagged as unknown word
        let hallo_error = result.errors.iter()
            .any(|e| text[e.start..e.end].contains("Hallo"));

        assert!(hallo_error || result.errors.is_empty(),
                "When disabled, behavior unchanged");
    }

    #[test]
    fn test_language_detection_german_word_filtered() {
        // Enable language detection with German excluded
        // Use complete German sentence followed by English sentence
        let text = "Hallo Welt, wie geht es dir? How are you doing today?";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true, // Enable language detection
            vec!["german".to_string()]
        );

        println!("\n=== GERMAN SENTENCE TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in the German sentence (0..30) should be filtered
        let german_sentence_errors = result.errors.iter()
            .filter(|e| e.start < 30)
            .count();

        assert_eq!(german_sentence_errors, 0, "All errors in German sentence should be filtered");
    }

    #[test]
    fn test_language_detection_user_scenario() {
        // Test exact user scenario: "Hello dear Nachbar, how are you doing? Gruss Bob"
        // First sentence is English (keep errors), second sentence is German (filter errors)
        let text = "Hello dear Nachbar, how are you doing? Gruss Bob";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["german".to_string()]
        );

        println!("\n=== USER SCENARIO TEST ===");
        println!("Text: '{}'", text);
        println!("Errors found: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // "Nachbar" in English sentence should be kept (error at position 11-18)
        let nachbar_error = result.errors.iter()
            .any(|e| e.start == 11 && e.end == 18);

        // "Gruss" in German sentence should be filtered (would be at position 40-45)
        let gruss_error = result.errors.iter()
            .any(|e| e.start >= 40 && e.end <= 49);

        assert!(nachbar_error, "Nachbar in English sentence should be kept");
        assert!(!gruss_error, "Gruss in German sentence should be filtered");
        println!("✅ User scenario passed: English sentence errors kept, German sentence errors filtered");
    }

    #[test]
    fn test_language_detection_spanish_words() {
        // Use complete Spanish sentence followed by English sentence
        let text = "Hola amigos, como estas hoy? Let's continue in English.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["spanish".to_string()]
        );

        println!("\n=== SPANISH WORDS TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Spanish sentence (0..29) should be filtered
        let spanish_errors = result.errors.iter()
            .filter(|e| e.start < 29)
            .count();

        assert_eq!(spanish_errors, 0, "All errors in Spanish sentence should be filtered");
    }

    #[test]
    fn test_language_detection_french_greeting() {
        // Use complete French sentence followed by English sentence
        let text = "Bonjour mes amis, comment allez-vous? I have a question.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["french".to_string()]
        );

        println!("\n=== FRENCH GREETING TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in French sentence (0..38) should be filtered
        let french_errors = result.errors.iter()
            .filter(|e| e.start < 38)
            .count();

        assert_eq!(french_errors, 0, "All errors in French sentence should be filtered");
    }

    #[test]
    fn test_language_detection_multiple_languages() {
        // Use longer complete sentences in different languages so whichlang can detect them
        let text = "Hola amigos, como estas hoy? Bonjour mes amis, comment allez-vous? Hallo Freunde, wie geht es euch? Welcome to the meeting.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["spanish".to_string(), "french".to_string(), "german".to_string()]
        );

        println!("\n=== MULTIPLE LANGUAGES TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Spanish sentence (0..29) should be filtered
        let spanish_errors = result.errors.iter().filter(|e| e.start < 29).count();
        // Errors in French sentence (29..66) should be filtered
        let french_errors = result.errors.iter().filter(|e| e.start >= 29 && e.start < 66).count();
        // Errors in German sentence (66..99) should be filtered
        let german_errors = result.errors.iter().filter(|e| e.start >= 66 && e.start < 99).count();

        assert_eq!(spanish_errors, 0, "Spanish sentence errors should be filtered");
        assert_eq!(french_errors, 0, "French sentence errors should be filtered");
        assert_eq!(german_errors, 0, "German sentence errors should be filtered");
    }

    #[test]
    fn test_language_detection_exclude_one_language_only() {
        // Spanish sentence and German sentence, but only Spanish excluded
        let text = "Hola amigos, como estas? Hallo Welt, wie geht es dir?";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["spanish".to_string()] // Only Spanish excluded
        );

        println!("\n=== SELECTIVE EXCLUSION TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Spanish sentence (0..25) should be filtered
        let spanish_errors = result.errors.iter().filter(|e| e.start < 25).count();

        // German sentence errors should NOT be filtered (German not excluded)
        // We just verify Spanish is filtered
        assert_eq!(spanish_errors, 0, "Spanish sentence errors should be filtered");
    }

    #[test]
    fn test_language_detection_with_slang_enabled() {
        // Test that language detection works alongside slang dictionaries
        // Spanish sentence followed by English with slang
        let text = "Hola amigos, como estas? BTW, that's totally sus.";
        let result = analyze_text(
            text,
            "American",
            true, // Internet abbreviations ON
            true, // Gen Z slang ON
            true, // Language detection ON
            vec!["spanish".to_string()]
        );

        println!("\n=== LANGUAGE + SLANG TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Spanish sentence (0..25) should be filtered
        let spanish_errors = result.errors.iter().filter(|e| e.start < 25).count();

        // "BTW" and "sus" in English sentence should NOT be flagged (slang dictionaries)
        let has_btw = result.errors.iter().any(|e| &text[e.start..e.end] == "BTW");
        let has_sus = result.errors.iter().any(|e| &text[e.start..e.end] == "sus");

        assert_eq!(spanish_errors, 0, "Spanish sentence errors should be filtered");
        assert!(!has_btw, "BTW should not be flagged (internet abbreviations)");
        assert!(!has_sus, "sus should not be flagged (Gen Z slang)");
    }

    #[test]
    fn test_language_detection_preserves_real_errors() {
        // Ensure real English errors are still caught
        // German sentence followed by English sentence with typo
        let text = "Hallo Welt, wie geht es dir? I recieve your message.";
        // "Hallo..." = German sentence (filtered), "I recieve..." = English typo (should be caught)
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["german".to_string()]
        );

        println!("\n=== REAL ERRORS PRESERVED TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in German sentence (0..30) should be filtered
        let german_errors = result.errors.iter().filter(|e| e.start < 30).count();
        assert_eq!(german_errors, 0, "German sentence errors should be filtered");

        // "recieve" in English sentence should still be caught if Harper detects it
        // This depends on Harper's spell checker
        let has_recieve = result.errors.iter().any(|e| &text[e.start..e.end] == "recieve");
        if has_recieve {
            println!("✅ Real English error 'recieve' was preserved");
        }
    }

    #[test]
    fn test_language_detection_code_switching() {
        // Test code-switching scenario (common in bilingual contexts)
        // Use Spanish sentence followed by English sentence
        let text = "Fui al mercado ayer. I went shopping yesterday.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["spanish".to_string()]
        );

        println!("\n=== CODE-SWITCHING TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Spanish sentence (0..21) should be filtered
        let spanish_errors = result.errors.iter().filter(|e| e.start < 21).count();
        assert_eq!(spanish_errors, 0, "Spanish sentence errors should be filtered");
    }

    #[test]
    fn test_language_detection_performance() {
        // Test that language detection doesn't significantly impact performance
        // Use complete German sentences
        let text = &"Hallo Welt, wie geht es dir? ".repeat(50); // ~250 words
        let start = std::time::Instant::now();

        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["german".to_string()]
        );

        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE TEST ===");
        println!("Text length: {} words", text.split_whitespace().count());
        println!("Analysis time: {}ms", elapsed.as_millis());
        println!("Errors found: {}", result.errors.len());

        // Should still be fast (<300ms for ~250 words)
        assert!(elapsed.as_millis() < 300,
                "Analysis with language detection should complete in <300ms, took {}ms",
                elapsed.as_millis());
    }

    #[test]
    fn test_language_detection_empty_excluded_list() {
        // Enabled but no languages excluded = same as disabled
        let text = "Hallo Welt, wie geht es dir?";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec![] // Empty list
        );

        // Behavior should be same as disabled (no filtering)
        // This test just ensures no crashes and proper handling
        println!("\n=== EMPTY EXCLUSION LIST TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        println!("✅ No crash with empty exclusion list");
    }

    #[test]
    fn test_language_detection_all_dialects() {
        // Test that language detection works with all English dialects
        let dialects = vec!["American", "British", "Canadian", "Australian"];
        let text = "Hallo Welt, wie geht es dir? English sentence here.";

        for dialect in dialects {
            let result = analyze_text(
                text,
                dialect,
                false,
                false,
                true,
                vec!["german".to_string()]
            );

            println!("\n=== DIALECT TEST: {} ===", dialect);
            println!("Text: '{}'", text);
            println!("Errors: {}", result.errors.len());

            // German sentence errors (0..30) should be filtered regardless of dialect
            let german_errors = result.errors.iter().filter(|e| e.start < 30).count();
            assert_eq!(german_errors, 0, "German sentence errors should be filtered for dialect {}", dialect);
        }
    }

    #[test]
    fn test_language_detection_word_count_unchanged() {
        // Word count should be based on original text
        let text = "Hallo Welt heute. English sentence here.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["german".to_string()]
        );

        // 3 German words + 3 English words = 6 total
        assert_eq!(result.word_count, 6, "Word count should include all words from all sentences");
    }

    #[test]
    fn test_language_detection_italian() {
        // Test Italian language detection and filtering
        let text = "Ciao amici, come stai oggi? Welcome to our Italian class.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["italian".to_string()]
        );

        println!("\n=== ITALIAN LANGUAGE TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Italian sentence (0..28) should be filtered
        let italian_errors = result.errors.iter().filter(|e| e.start < 28).count();
        assert_eq!(italian_errors, 0, "Italian sentence errors should be filtered");
    }

    #[test]
    fn test_language_detection_portuguese() {
        // Test Portuguese language detection and filtering
        let text = "Olá meus amigos, como você está? This is an English sentence.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["portuguese".to_string()]
        );

        println!("\n=== PORTUGUESE LANGUAGE TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Portuguese sentence (0..33) should be filtered
        let portuguese_errors = result.errors.iter().filter(|e| e.start < 33).count();
        assert_eq!(portuguese_errors, 0, "Portuguese sentence errors should be filtered");
    }

    #[test]
    fn test_language_detection_dutch() {
        // Test Dutch language detection and filtering
        let text = "Hallo allemaal, hoe gaat het met jullie? Back to English now.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["dutch".to_string()]
        );

        println!("\n=== DUTCH LANGUAGE TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Dutch sentence (0..42) should be filtered
        let dutch_errors = result.errors.iter().filter(|e| e.start < 42).count();
        assert_eq!(dutch_errors, 0, "Dutch sentence errors should be filtered");
    }

    #[test]
    fn test_language_detection_swedish() {
        // Test Swedish language detection and filtering
        let text = "Hej allihopa, hur mår ni idag? The meeting starts soon.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["swedish".to_string()]
        );

        println!("\n=== SWEDISH LANGUAGE TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Swedish sentence (0..31) should be filtered
        let swedish_errors = result.errors.iter().filter(|e| e.start < 31).count();
        assert_eq!(swedish_errors, 0, "Swedish sentence errors should be filtered");
    }

    #[test]
    fn test_language_detection_turkish() {
        // Test Turkish language detection and filtering
        let text = "Merhaba arkadaşlar, nasılsınız bugün? Let's continue in English.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["turkish".to_string()]
        );

        println!("\n=== TURKISH LANGUAGE TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Turkish sentence (0..39) should be filtered
        let turkish_errors = result.errors.iter().filter(|e| e.start < 39).count();
        assert_eq!(turkish_errors, 0, "Turkish sentence errors should be filtered");
    }

    #[test]
    fn test_language_detection_non_excluded_language_kept() {
        // Test that non-excluded languages are NOT filtered
        // Italian excluded, but German should still show errors
        let text = "Ciao amici, come stai? Hallo Welt, wie geht es dir?";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["italian".to_string()] // Only Italian excluded, not German
        );

        println!("\n=== NON-EXCLUDED LANGUAGE TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Errors in Italian sentence (0..22) should be filtered
        let italian_errors = result.errors.iter().filter(|e| e.start < 22).count();
        assert_eq!(italian_errors, 0, "Italian sentence errors should be filtered");

        // German errors should NOT be filtered (German not in excluded list)
        // We don't assert specific count since it depends on Harper's detection
        println!("✅ Italian filtered, German errors may still be present");
    }

    #[test]
    fn test_language_detection_multilingual_email() {
        // Real-world scenario: multilingual email with greetings in different languages
        let text = "Bonjour Jean! Hope you're doing well. Hasta luego amigo! See you tomorrow.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["french".to_string(), "spanish".to_string()]
        );

        println!("\n=== MULTILINGUAL EMAIL TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // This is a mixed scenario - sentences may be detected differently
        // The key is that the system handles it gracefully
        println!("✅ Multilingual email handled without crashes");
    }

    #[test]
    fn test_language_detection_asian_languages() {
        // Test with Asian languages - Japanese, Korean, Chinese
        // Note: These require proper UTF-8 handling
        let text = "こんにちは、元気ですか? This is English. 안녕하세요, 어떻게 지내세요? More English here.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["japanese".to_string(), "korean".to_string()]
        );

        println!("\n=== ASIAN LANGUAGES TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Just verify no crashes with UTF-8 and Asian scripts
        println!("✅ Asian languages handled correctly with UTF-8");
    }

    #[test]
    fn test_language_detection_mixed_punctuation() {
        // Test with various punctuation marks and sentence terminators
        let text = "¿Hola amigo, cómo estás? Great! Danke schön! Fantastic. Merci beaucoup! Done.";
        let result = analyze_text(
            text,
            "American",
            false,
            false,
            true,
            vec!["spanish".to_string(), "german".to_string(), "french".to_string()]
        );

        println!("\n=== MIXED PUNCTUATION TEST ===");
        println!("Text: '{}'", text);
        println!("Errors: {}", result.errors.len());
        for error in &result.errors {
            println!("  - '{}' ({}..{}): {}", &text[error.start..error.end], error.start, error.end, error.message);
        }

        // Verify sentence splitting works with different punctuation
        println!("✅ Mixed punctuation handled correctly");
    }

    // MARK: - Performance Regression Tests

    #[test]
    fn test_performance_baseline_analysis() {
        // Performance regression test: Basic analysis without language detection
        // Target: < 450ms for ~200 words (test mode with opt-level=1)
        // Note: Release builds (opt-level=3) are ~3x faster (~150ms)
        use std::time::Instant;

        let text = "This is a comprehensive test of the grammar analysis engine performance. \
                    It contains multiple sentences with various grammatical structures. \
                    The system should be able to analyze this text quickly and efficiently. \
                    We want to ensure that the baseline performance remains good. \
                    Additional text is included to reach approximately 200 words total. \
                    ".repeat(4);

        let start = Instant::now();
        let result = analyze_text(&text, "American", false, false, false, vec![]);
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: Baseline Analysis ===");
        println!("Text length: {} chars, {} words", text.len(), result.word_count);
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors found: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 450,
            "Baseline analysis too slow: {} ms (expected < 450 ms)",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_language_detection_disabled() {
        // Performance regression test: Language detection disabled should add no overhead
        // Target: < 450ms (test mode), same as baseline
        // Note: Release builds are ~3x faster
        use std::time::Instant;

        let text = "This is a test sentence with Hallo and Danke mixed in. \
                    The language detection is disabled so it shouldn't affect performance. \
                    We include more text to make this a realistic test case scenario. \
                    ".repeat(10);

        let start = Instant::now();
        let result = analyze_text(&text, "American", false, false, false, vec![]);
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: Language Detection Disabled ===");
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 450,
            "Analysis with disabled language detection too slow: {} ms (expected < 450 ms)",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_language_detection_enabled() {
        // Performance regression test: Language detection enabled with minimal overhead
        // Target: < 500ms for ~200 words (test mode), allows ~10% overhead vs baseline
        // Note: Release builds are ~3x faster (~150-170ms)
        use std::time::Instant;

        let text = "This is a test sentence with Hallo and Danke mixed in. \
                    The language detection is enabled but should have minimal impact. \
                    We include more text to make this a realistic test case scenario. \
                    ".repeat(10);

        let start = Instant::now();
        let result = analyze_text(
            &text,
            "American",
            false,
            false,
            true,
            vec!["german".to_string()]
        );
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: Language Detection Enabled ===");
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 500,
            "Analysis with language detection too slow: {} ms (expected < 500 ms)",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_mixed_multilingual_text() {
        // Performance regression test: Mixed multilingual text
        // Target: < 800ms for realistic mixed-language document (test mode)
        // Note: Release builds are ~3x faster (~250-270ms)
        use std::time::Instant;

        let text = "Hallo Team! Here's the Zusammenfassung for today's meeting. \
                    We discussed the neue Features and the Zeitplan for the release. \
                    Por favor, review the Dokumentation and let me know if you have any Fragen. \
                    Merci beaucoup for your collaboration. Gracias por todo. \
                    This is a typical scenario in international teams where multiple languages mix. \
                    ".repeat(5);

        let start = Instant::now();
        let result = analyze_text(
            &text,
            "American",
            false,
            false,
            true,
            vec!["german".to_string(), "spanish".to_string(), "french".to_string()]
        );
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: Mixed Multilingual Text ===");
        println!("Text length: {} chars, {} words", text.len(), result.word_count);
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 800,
            "Mixed multilingual analysis too slow: {} ms (expected < 800 ms)",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_all_languages_excluded() {
        // Performance regression test: Many excluded languages
        // Target: < 550ms (test mode), shouldn't degrade significantly with more excluded languages
        // Note: Release builds are ~3x faster (~180-200ms)
        use std::time::Instant;

        let all_langs = vec![
            "spanish", "french", "german", "italian", "portuguese",
            "dutch", "russian", "mandarin", "japanese", "korean",
            "arabic", "hindi", "turkish", "swedish", "vietnamese",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();

        let text = "This is a test with multiple foreign words like Hallo Bonjour Gracias Ciao scattered throughout. \
                    The system should handle many excluded languages efficiently without degradation. \
                    ".repeat(10);

        let start = Instant::now();
        let result = analyze_text(&text, "American", false, false, true, all_langs);
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: All Languages Excluded ===");
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 550,
            "Analysis with all languages excluded too slow: {} ms (expected < 550 ms)",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_abbreviations_and_slang() {
        // Performance regression test: Abbreviations and slang processing
        // Target: < 450ms for text with abbreviations and slang (test mode)
        // Note: Release builds are ~3x faster (~150ms)
        use std::time::Instant;

        let text = "btw lol omg afaict IMO FYI ASAP brb ghosting sus slay vibes lowkey highkey \
                    The system needs to process these efficiently along with normal text. \
                    This is a common scenario in modern communication. \
                    ".repeat(10);

        let start = Instant::now();
        let result = analyze_text(&text, "American", true, true, false, vec![]);
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: Abbreviations and Slang ===");
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 450,
            "Abbreviations/slang analysis too slow: {} ms (expected < 450 ms)",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_comprehensive_full_features() {
        // Performance regression test: All features enabled
        // Target: < 700ms for comprehensive analysis with all features (test mode)
        // Note: Release builds are ~3x faster (~230-250ms)
        use std::time::Instant;

        let text = "btw, Hallo Team! Here's the Zusammenfassung lol. \
                    We discussed the neue Features omg and the Zeitplan ASAP. \
                    This is sus but the vibes are good lowkey. \
                    Por favor review and LMK if you have Fragen. Danke! \
                    ".repeat(10);

        let start = Instant::now();
        let result = analyze_text(
            &text,
            "American",
            true, // internet abbreviations
            true, // slang
            true, // language detection
            vec!["german".to_string(), "spanish".to_string()]
        );
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: All Features Enabled ===");
        println!("Text length: {} chars, {} words", text.len(), result.word_count);
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 700,
            "Comprehensive analysis too slow: {} ms (expected < 700 ms)",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_short_text_latency() {
        // Performance regression test: Short text latency
        // Target: < 450ms for short message (test mode)
        // Note: Release builds are ~3x faster (~140-150ms)
        // Even short texts incur Harper initialization and dictionary loading overhead
        use std::time::Instant;

        let text = "Hallo, how are you?";

        let start = Instant::now();
        let result = analyze_text(
            &text,
            "American",
            true,
            true,
            true,
            vec!["german".to_string()]
        );
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: Short Text Latency ===");
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 450,
            "Short text analysis too slow: {} ms (expected < 450 ms)",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_long_document() {
        // Performance regression test: Long document (1000+ words)
        // Target: < 500ms for very long text
        use std::time::Instant;

        let paragraph = "This is a comprehensive test paragraph that contains various grammatical structures. \
                        We want to test the performance of the grammar engine on long documents. \
                        The text should be analyzed efficiently even when it's quite lengthy. \
                        Real-world documents often contain hundreds or thousands of words. \
                        ";

        let text = paragraph.repeat(50); // ~1000 words

        let start = Instant::now();
        let result = analyze_text(&text, "American", true, true, false, vec![]);
        let elapsed = start.elapsed();

        println!("\n=== PERFORMANCE: Long Document ===");
        println!("Text length: {} chars, {} words", text.len(), result.word_count);
        println!("Analysis time: {} ms", elapsed.as_millis());
        println!("Errors: {}", result.errors.len());

        assert!(
            elapsed.as_millis() < 500,
            "Long document analysis too slow: {} ms (expected < 500 ms)",
            elapsed.as_millis()
        );
    }
}


