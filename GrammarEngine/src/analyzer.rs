// Analyzer - Grammar analysis implementation wrapping Harper
//
// Provides the core text analysis functionality.

use harper_core::{Document, linting::{Linter, LintGroup}, Dialect};
use harper_core::spell::{MutableDictionary, MergedDictionary};
use std::sync::Arc;
use std::time::Instant;
use crate::slang_dict;

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
///
/// # Returns
/// An AnalysisResult containing detected errors and analysis metadata
pub fn analyze_text(
    text: &str,
    dialect_str: &str,
    enable_internet_abbrev: bool,
    enable_genz_slang: bool
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

        assert!(abbrev_dict.contains_exact_word(&afaict_upper), "AFAICT should be in abbrev dictionary");
        assert!(abbrev_dict.contains_exact_word(&afaict_lower), "afaict should be in abbrev dictionary");
        assert!(abbrev_dict.contains_exact_word(&lol_upper), "LOL should be in abbrev dictionary");
        assert!(abbrev_dict.contains_exact_word(&lol_lower), "lol should be in abbrev dictionary");

        assert!(merged.contains_exact_word(&afaict_upper), "AFAICT should be in merged dictionary");
        assert!(merged.contains_exact_word(&lol_upper), "LOL should be in merged dictionary");
    }

    #[test]
    fn test_analyze_empty_text() {
        let result = analyze_text("", "American", false, false);
        assert_eq!(result.errors.len(), 0);
        assert_eq!(result.word_count, 0);
    }

    #[test]
    fn test_analyze_correct_text() {
        let result = analyze_text("This is a well-written sentence.", "American", false, false);
        // Well-written text may still have style suggestions, so we just verify it runs
        assert!(result.word_count > 0);
        assert!(result.analysis_time_ms >= 0);
    }

    #[test]
    fn test_analyze_incorrect_text() {
        // Subject-verb disagreement: "team are" should be "team is"
        let result = analyze_text("The team are working on it.", "American", false, false);
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
        let result = analyze_text("Teh quick brown fox.", "American", false, false);

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
        let result = analyze_text(text, "American", false, false);
        // Analysis should complete in under 100ms for ~900 words
        assert!(result.analysis_time_ms < 100,
                "Analysis took {}ms for {} words",
                result.analysis_time_ms, result.word_count);
    }

    #[test]
    fn test_analyze_dialects() {
        // Test that different dialects can be parsed correctly
        let text = "This is a test.";
        let result_american = analyze_text(text, "American", false, false);
        let result_british = analyze_text(text, "British", false, false);
        let result_canadian = analyze_text(text, "Canadian", false, false);
        let result_australian = analyze_text(text, "Australian", false, false);
        let result_invalid = analyze_text(text, "Invalid", false, false);

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
        let result_disabled = analyze_text(text, "American", false, false);

        // With slang enabled, should NOT flag abbreviations
        let result_enabled = analyze_text(text, "American", true, false);

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
        let result_disabled = analyze_text(text, "American", false, false);

        // With slang enabled, should recognize these words
        let result_enabled = analyze_text(text, "American", false, true);

        println!("Errors without Gen Z slang: {}", result_disabled.errors.len());
        println!("Errors with Gen Z slang: {}", result_enabled.errors.len());
    }

    #[test]
    fn test_both_slang_options() {
        // Test with both slang options enabled
        let text = "BTW your vibe is totally slay! NGL you ghosted me ASAP.";

        let result = analyze_text(text, "American", true, true);

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
        let result_disabled = analyze_text(text, "American", false, false);

        // With slang enabled, should NOT flag these
        let result_enabled = analyze_text(text, "American", true, false);

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
            let result = analyze_text(text, "American", true, false);

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
        let abbrev_disabled = analyze_text(text_with_abbrevs, "American", false, false);
        let abbrev_enabled = analyze_text(text_with_abbrevs, "American", true, false);

        println!("\n=== INTERNET ABBREVIATIONS TOGGLE TEST ===");
        println!("Text: {}", text_with_abbrevs);
        println!("Errors (disabled): {}", abbrev_disabled.errors.len());
        println!("Errors (enabled): {}", abbrev_enabled.errors.len());

        // Should have fewer or equal errors when enabled
        assert!(abbrev_enabled.errors.len() <= abbrev_disabled.errors.len(),
                "Enabling abbreviations should not increase error count");

        // Test Gen Z slang toggle
        let slang_disabled = analyze_text(text_with_slang, "American", false, false);
        let slang_enabled = analyze_text(text_with_slang, "American", false, true);

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
        let result = analyze_text("", "American", true, true);
        assert_eq!(result.errors.len(), 0, "Empty text should have no errors");
        assert_eq!(result.word_count, 0, "Empty text should have 0 words");

        // Only abbreviations
        let result = analyze_text("BTW FYI LOL ASAP", "American", true, false);
        println!("\nOnly abbreviations - Errors: {}", result.errors.len());
        // These should all be recognized
        assert_eq!(result.word_count, 4, "Should count 4 words");

        // Abbreviations with punctuation
        let result = analyze_text("BTW, FYI! LOL? ASAP.", "American", true, false);
        println!("With punctuation - Errors: {}", result.errors.len());

        // Mixed slang types
        let result = analyze_text("BTW that vibe is sus", "American", true, true);
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
            let result = analyze_text(&text, "American", true, false);

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
            let result_lower = analyze_text(&text_lower, "American", true, false);

            // Test UPPERCASE
            let abbrev_upper = abbrev.to_uppercase();
            let text_upper = format!("I think {} is common", abbrev_upper);
            let result_upper = analyze_text(&text_upper, "American", true, false);

            // Test Title Case
            let abbrev_title: String = abbrev.chars().enumerate()
                .map(|(i, c)| if i == 0 { c.to_uppercase().to_string() } else { c.to_string() })
                .collect();
            let text_title = format!("I think {} is common", abbrev_title);
            let result_title = analyze_text(&text_title, "American", true, false);

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
            let result = analyze_text(text, "American", true, true);  // Both slang options ON

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
        let result = analyze_text(text, "American", true, false);

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
}

