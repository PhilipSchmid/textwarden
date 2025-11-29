// Language Filter - Sentence-level language detection
//
// Splits text into sentences, detects the language of each sentence,
// and filters out grammar errors in non-English sentences.

use whichlang::{detect_language, Lang};
use crate::analyzer::GrammarError;

/// Language filter configuration
pub struct LanguageFilter {
    enabled: bool,
    excluded_languages: Vec<Lang>,
}

impl LanguageFilter {
    /// Create a new language filter
    ///
    /// # Arguments
    /// * `enabled` - Whether language detection is enabled
    /// * `excluded_languages` - List of language codes to exclude (e.g., ["spanish", "german"])
    pub fn new(enabled: bool, excluded_languages: Vec<String>) -> Self {
        let langs = excluded_languages.iter()
            .filter_map(|s| lang_from_string(s))
            .collect();

        Self {
            enabled,
            excluded_languages: langs,
        }
    }

    /// Filter out errors for non-English sentences
    ///
    /// Uses sentence-level language detection: splits text into sentences,
    /// detects the language of each sentence, and filters errors in non-English sentences.
    ///
    /// # Arguments
    /// * `errors` - Errors detected by Harper
    /// * `text` - Original text that was analyzed
    ///
    /// # Returns
    /// Filtered list of errors with errors in non-English sentences removed
    pub fn filter_errors(&self, errors: Vec<GrammarError>, text: &str) -> Vec<GrammarError> {
        if !self.enabled || self.excluded_languages.is_empty() {
            return errors;
        }

        // Split text into sentences
        let sentences = split_into_sentences(text);

        // Detect language for each sentence (cache to avoid redundant detection)
        // Use get() for safe slicing to avoid panics on invalid UTF-8 boundaries
        let sentence_languages: Vec<(usize, usize, Lang)> = sentences.iter()
            .filter_map(|&(start, end)| {
                // Safe slice - returns None if indices are not at valid UTF-8 boundaries
                text.get(start..end).map(|sentence_text| {
                    let lang = detect_language(sentence_text);
                    (start, end, lang)
                })
            })
            .collect();

        // Filter errors based on sentence language
        errors.into_iter()
            .filter(|error| {
                // Find which sentence this error belongs to
                let sentence_lang = sentence_languages.iter()
                    .find(|(start, end, _)| error.start >= *start && error.end <= *end)
                    .map(|(_, _, lang)| lang);

                match sentence_lang {
                    Some(lang) => {
                        // Keep error if sentence is NOT in an excluded language
                        !self.excluded_languages.contains(lang)
                    }
                    None => {
                        // If we can't find the sentence, keep the error (fail-safe)
                        true
                    }
                }
            })
            .collect()
    }
}

/// Split text into sentences
/// Returns a vector of (start, end) byte positions for each sentence
fn split_into_sentences(text: &str) -> Vec<(usize, usize)> {
    let mut sentences = Vec::new();
    let mut start = 0;

    for (i, ch) in text.char_indices() {
        // Sentence terminators
        if ch == '.' || ch == '!' || ch == '?' {
            // Check if there's more text after this
            let rest = &text[i + ch.len_utf8()..];

            // End of sentence if followed by whitespace or end of text
            if rest.is_empty() || rest.starts_with(|c: char| c.is_whitespace()) {
                let end = i + ch.len_utf8();
                if start < end {
                    sentences.push((start, end));
                }
                // Start next sentence after any whitespace
                start = i + ch.len_utf8() + rest.len() - rest.trim_start().len();
                if start >= text.len() {
                    break;
                }
            }
        }
    }

    // Add remaining text as final sentence if there's any
    if start < text.len() {
        sentences.push((start, text.len()));
    }

    // If no sentences were found, treat entire text as one sentence
    if sentences.is_empty() {
        sentences.push((0, text.len()));
    }

    sentences
}

/// Convert language string to whichlang Lang enum
fn lang_from_string(s: &str) -> Option<Lang> {
    match s.to_lowercase().as_str() {
        "spanish" | "spa" => Some(Lang::Spa),
        "french" | "fra" | "fre" => Some(Lang::Fra),
        "german" | "deu" | "ger" => Some(Lang::Deu),
        "italian" | "ita" => Some(Lang::Ita),
        "portuguese" | "por" => Some(Lang::Por),
        "dutch" | "nld" | "dut" => Some(Lang::Nld),
        "russian" | "rus" => Some(Lang::Rus),
        "chinese" | "mandarin" | "cmn" => Some(Lang::Cmn),
        "japanese" | "jpn" => Some(Lang::Jpn),
        "korean" | "kor" => Some(Lang::Kor),
        "arabic" | "ara" => Some(Lang::Ara),
        "hindi" | "hin" => Some(Lang::Hin),
        "turkish" | "tur" => Some(Lang::Tur),
        "swedish" | "swe" => Some(Lang::Swe),
        "vietnamese" | "vie" => Some(Lang::Vie),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analyzer::ErrorSeverity;

    fn create_error(start: usize, end: usize, message: &str) -> GrammarError {
        GrammarError {
            start,
            end,
            message: message.to_string(),
            severity: ErrorSeverity::Error,
            category: "Spelling".to_string(),
            lint_id: "test".to_string(),
            suggestions: vec![],
        }
    }

    // MARK: - Sentence Splitting Tests

    #[test]
    fn test_split_single_sentence() {
        let text = "This is a single sentence.";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 1);
        assert_eq!(sentences[0], (0, text.len()));
    }

    #[test]
    fn test_split_multiple_sentences() {
        let text = "First sentence. Second sentence! Third sentence?";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 3);
        assert_eq!(&text[sentences[0].0..sentences[0].1], "First sentence.");
        assert_eq!(&text[sentences[1].0..sentences[1].1], "Second sentence!");
        assert_eq!(&text[sentences[2].0..sentences[2].1], "Third sentence?");
    }

    #[test]
    fn test_split_no_punctuation() {
        let text = "No punctuation here just words";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 1);
        assert_eq!(sentences[0], (0, text.len()));
    }

    #[test]
    fn test_split_empty_text() {
        let text = "";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 1);
        assert_eq!(sentences[0], (0, 0));
    }

    // MARK: - Basic Filtering Tests

    #[test]
    fn test_filter_disabled() {
        let filter = LanguageFilter::new(false, vec!["german".to_string()]);
        let errors = vec![create_error(0, 5, "Unknown word")];
        let text = "Hallo Welt, wie geht es dir?";

        let filtered = filter.filter_errors(errors.clone(), text);
        assert_eq!(filtered.len(), errors.len(), "No filtering when disabled");
    }

    #[test]
    fn test_filter_no_excluded_languages() {
        let filter = LanguageFilter::new(true, vec![]);
        let errors = vec![create_error(0, 5, "Unknown word")];
        let text = "Hallo Welt, wie geht es dir?";

        let filtered = filter.filter_errors(errors.clone(), text);
        assert_eq!(filtered.len(), errors.len(), "No filtering when no languages excluded");
    }

    // MARK: - Single Sentence Tests

    #[test]
    fn test_single_german_sentence_filtered() {
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let text = "Hallo Welt, wie geht es dir?";
        let errors = vec![
            create_error(0, 5, "Unknown word"),   // Hallo
            create_error(11, 14, "Unknown word"),  // wie
        ];

        let filtered = filter.filter_errors(errors, text);
        assert_eq!(filtered.len(), 0, "All errors in German sentence should be filtered");
    }

    #[test]
    fn test_single_english_sentence_kept() {
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let text = "Hello world, how are you?";
        let errors = vec![
            create_error(0, 5, "Grammar error"),
            create_error(17, 20, "Grammar error"),
        ];

        let filtered = filter.filter_errors(errors.clone(), text);
        assert_eq!(filtered.len(), errors.len(), "Errors in English sentence should be kept");
    }

    #[test]
    fn test_single_spanish_sentence() {
        let filter = LanguageFilter::new(true, vec!["spanish".to_string()]);
        let text = "Hola amigos, como estas?";
        let errors = vec![
            create_error(0, 4, "Unknown word"),   // Hola
            create_error(13, 17, "Unknown word"), // como
        ];

        let filtered = filter.filter_errors(errors, text);
        assert_eq!(filtered.len(), 0, "Spanish sentence errors should be filtered");
    }

    #[test]
    fn test_single_french_sentence() {
        let filter = LanguageFilter::new(true, vec!["french".to_string()]);
        let text = "Bonjour mes amis, comment allez-vous?";
        let errors = vec![
            create_error(0, 7, "Unknown word"),    // Bonjour
            create_error(18, 25, "Unknown word"),  // comment
        ];

        let filtered = filter.filter_errors(errors, text);
        assert_eq!(filtered.len(), 0, "French sentence errors should be filtered");
    }

    // MARK: - Multi-Sentence Tests (User Example!)

    #[test]
    fn test_user_example_mixed_sentences() {
        // Your exact example: "Hello dear Nachbar, how are you doing? Gruss Bob"
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let text = "Hello dear Nachbar, how are you doing? Gruss Bob";
        let errors = vec![
            create_error(11, 18, "Unknown word"), // Nachbar (in English sentence)
            create_error(40, 45, "Unknown word"), // Gruss (in German sentence)
        ];

        let filtered = filter.filter_errors(errors, text);

        // First sentence "Hello dear Nachbar, how are you doing?" is English -> keep errors
        // Second sentence "Gruss Bob" is German -> filter errors
        assert_eq!(filtered.len(), 1, "Should keep English sentence error, filter German sentence error");

        // Verify the kept error is from the English sentence
        assert_eq!(filtered[0].start, 11);
        assert_eq!(filtered[0].end, 18);
    }

    #[test]
    fn test_mixed_english_german_sentences() {
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let text = "This is English. Das ist Deutsch. More English here.";
        let errors = vec![
            create_error(5, 7, "Error 1"),  // "is" in English sentence
            create_error(21, 23, "Error 2"), // "ist" in German sentence
            create_error(44, 48, "Error 3"), // "here" in English sentence
        ];

        let filtered = filter.filter_errors(errors, text);

        // Should keep errors from English sentences, filter from German
        assert_eq!(filtered.len(), 2, "Should keep English sentence errors");
        assert_eq!(filtered[0].start, 5);   // First English error
        assert_eq!(filtered[1].start, 44);  // Second English error
    }

    #[test]
    fn test_mixed_english_spanish_french() {
        let filter = LanguageFilter::new(
            true,
            vec!["spanish".to_string(), "french".to_string()]
        );
        let text = "Hello. Hola amigos. Bonjour. Goodbye.";
        let errors = vec![
            create_error(0, 5, "Error"),    // Hello (English)
            create_error(7, 11, "Error"),   // Hola (Spanish)
            create_error(20, 27, "Error"),  // Bonjour (French)
            create_error(29, 36, "Error"),  // Goodbye (English)
        ];

        let filtered = filter.filter_errors(errors, text);

        // Should keep English errors, filter Spanish and French
        assert_eq!(filtered.len(), 2, "Should keep only English errors");
    }

    // MARK: - Performance Tests

    #[test]
    fn test_performance_many_sentences() {
        use std::time::Instant;

        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        // Create text with 100 sentences
        let mut text = String::new();
        let mut errors = Vec::new();

        for i in 0..100 {
            let start = text.len();
            text.push_str(&format!("This is sentence number {}. ", i));
            errors.push(create_error(start, start + 4, "Error"));
        }

        let start_time = Instant::now();
        let _filtered = filter.filter_errors(errors, &text);
        let elapsed = start_time.elapsed();

        assert!(
            elapsed.as_millis() < 100,
            "100 sentences should process quickly: {} ms",
            elapsed.as_millis()
        );
    }

    #[test]
    fn test_performance_long_sentences() {
        use std::time::Instant;

        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        // Create very long sentences (100 words each)
        let sentence = "word ".repeat(100);
        let text = format!("{}. {}. {}.", sentence, sentence, sentence);
        let errors = vec![
            create_error(0, 4, "Error 1"),
            create_error(505, 509, "Error 2"),
            create_error(1010, 1014, "Error 3"),
        ];

        let start_time = Instant::now();
        let _filtered = filter.filter_errors(errors, &text);
        let elapsed = start_time.elapsed();

        assert!(
            elapsed.as_millis() < 20,
            "Long sentences should process quickly: {} ms",
            elapsed.as_millis()
        );
    }

    // MARK: - Selective Language Filtering

    #[test]
    fn test_selective_language_exclusion() {
        // Only Spanish excluded, not German
        let filter = LanguageFilter::new(true, vec!["spanish".to_string()]);
        let text = "Hola amigos. Hallo Welt. Hello world.";
        let errors = vec![
            create_error(0, 4, "Error 1"),    // Hola (Spanish sentence)
            create_error(13, 18, "Error 2"),  // Hallo (German sentence)
            create_error(25, 30, "Error 3"),  // Hello (English sentence)
        ];

        let filtered = filter.filter_errors(errors, text);

        // Spanish sentence filtered, German and English kept
        assert_eq!(filtered.len(), 2);
    }

    #[test]
    fn test_multiple_excluded_languages() {
        let filter = LanguageFilter::new(
            true,
            vec!["german".to_string(), "spanish".to_string(), "french".to_string()]
        );
        // Use longer sentences to provide enough context for accurate language detection
        let text = "This is English. Das ist Deutsch. Esto es Español. C'est Français. More English here.";
        let errors = vec![
            create_error(0, 7, "E1"),    // "This is" in English sentence
            create_error(21, 24, "E2"),  // "ist" in German sentence
            create_error(38, 40, "E3"),  // "es" in Spanish sentence
            create_error(58, 64, "E4"),  // "C'est" in French sentence
            create_error(71, 75, "E5"),  // "More" in English sentence
        ];

        let filtered = filter.filter_errors(errors, text);

        // Should keep only English sentence errors (E1 and E5)
        assert_eq!(filtered.len(), 2);
    }
}
