// Language Filter - Sentence-level language detection
//
// Splits text into sentences, detects the language of each sentence,
// and filters out grammar errors in non-English sentences.

use crate::analyzer::GrammarError;
use whichlang::{detect_language, Lang};

/// Threshold for considering a document "primarily" in a given language.
/// If more than this ratio of sentences are in an excluded language, the document
/// is treated as non-English for filtering purposes.
const NON_ENGLISH_THRESHOLD: f64 = 0.6;

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
        let langs = excluded_languages
            .iter()
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
        tracing::debug!(
            "LanguageFilter: enabled={}, excluded_languages={:?}",
            self.enabled,
            self.excluded_languages
        );

        if !self.enabled || self.excluded_languages.is_empty() {
            tracing::debug!(
                "LanguageFilter: Skipping (enabled={}, excluded_empty={})",
                self.enabled,
                self.excluded_languages.is_empty()
            );
            return errors;
        }

        // First, check if document is primarily in an excluded language
        // If so, filter ALL errors (no point in sentence-level detection)
        if let Some((lang, ratio)) =
            calculate_excluded_language_ratio(text, &self.excluded_languages)
        {
            tracing::info!(
                "LanguageFilter: Document language {:?} detected ({:.0}% of sentences)",
                lang,
                ratio * 100.0
            );

            if ratio > NON_ENGLISH_THRESHOLD {
                tracing::info!(
                    "LanguageFilter: Document is primarily {:?} (>{:.0}%), filtering ALL {} errors",
                    lang,
                    NON_ENGLISH_THRESHOLD * 100.0,
                    errors.len()
                );
                return vec![];
            }
        }

        // Fall back to sentence-level detection for mixed-language documents
        let sentences = split_into_sentences(text);

        // Detect language for each sentence (cache to avoid redundant detection)
        // Use get() for safe slicing to avoid panics on invalid UTF-8 boundaries
        let sentence_languages: Vec<(usize, usize, Lang)> = sentences
            .iter()
            .filter_map(|&(start, end)| {
                // Safe slice - returns None if indices are not at valid UTF-8 boundaries
                text.get(start..end).map(|sentence_text| {
                    let lang = detect_language(sentence_text);
                    (start, end, lang)
                })
            })
            .collect();

        // Filter errors based on sentence language
        errors
            .into_iter()
            .filter(|error| {
                // Find which sentence this error belongs to
                let sentence_lang = sentence_languages
                    .iter()
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

    /// Check if document is primarily in a non-English language
    ///
    /// Returns true if:
    /// - Language detection is enabled
    /// - At least one language is excluded
    /// - The document's dominant language is in the excluded list
    /// - More than 60% of sentences are in that language
    ///
    /// This is used to skip readability analysis for non-English documents,
    /// since Flesch Reading Ease is calibrated for English only.
    pub fn is_document_primarily_non_english(&self, text: &str) -> bool {
        // If detection is disabled or no excluded languages, assume English
        if !self.enabled || self.excluded_languages.is_empty() {
            return false;
        }

        // Check if document is primarily in an excluded language
        if let Some((lang, ratio)) =
            calculate_excluded_language_ratio(text, &self.excluded_languages)
        {
            tracing::debug!(
                "LanguageFilter: Document language check - {:?} ({:.0}%), is_non_english={}",
                lang,
                ratio * 100.0,
                ratio > NON_ENGLISH_THRESHOLD
            );
            return ratio > NON_ENGLISH_THRESHOLD;
        }

        false
    }
}

/// Calculate the ratio of sentences in an excluded language.
///
/// Returns `Some((lang, ratio))` if the document's dominant language is in the excluded list,
/// where `lang` is the detected language and `ratio` is the proportion of sentences in that language.
/// Returns `None` if the document's dominant language is not in the excluded list.
///
/// This is the core logic shared by `filter_errors`, `is_document_primarily_non_english`,
/// and `should_skip_harper_analysis`.
fn calculate_excluded_language_ratio(
    text: &str,
    excluded_languages: &[Lang],
) -> Option<(Lang, f64)> {
    // Detect the dominant language of the document
    let doc_lang = detect_language(text);

    // If detected language is not in excluded list, return None
    if !excluded_languages.contains(&doc_lang) {
        return None;
    }

    // Split into sentences and calculate ratio
    let sentences = split_into_sentences(text);
    if sentences.is_empty() {
        return Some((doc_lang, 0.0));
    }

    let doc_lang_count = sentences
        .iter()
        .filter(|(s, e)| {
            text.get(*s..*e)
                .map(|t| detect_language(t) == doc_lang)
                .unwrap_or(false)
        })
        .count();

    let ratio = doc_lang_count as f64 / sentences.len() as f64;
    Some((doc_lang, ratio))
}

/// Split text into sentences/segments for language detection
/// Handles: punctuation (.!?), paragraph breaks, bullet points, numbered lists
/// Returns a vector of (start, end) byte positions for each segment
pub fn split_into_sentences(text: &str) -> Vec<(usize, usize)> {
    let mut sentences = Vec::new();
    let mut start = 0;
    let mut i = 0;
    let chars: Vec<(usize, char)> = text.char_indices().collect();

    while i < chars.len() {
        let (byte_pos, ch) = chars[i];

        // Check for paragraph break (2+ consecutive newlines)
        if ch == '\n' {
            if let Some((_, next_ch)) = chars.get(i + 1) {
                if *next_ch == '\n' || *next_ch == '\r' {
                    // End current segment before the paragraph break (only if non-empty content)
                    if start < byte_pos {
                        let segment = &text[start..byte_pos];
                        if !segment.trim().is_empty() {
                            sentences.push((start, byte_pos));
                        }
                    }
                    // Skip all consecutive newlines/carriage returns
                    while i < chars.len() && (chars[i].1 == '\n' || chars[i].1 == '\r') {
                        i += 1;
                    }
                    // Start new segment after paragraph break
                    if i < chars.len() {
                        start = chars[i].0;
                    }
                    continue;
                }
            }
        }

        // Check for bullet points at start of line
        // Matches: - * • ◦ ▪ ▸ ► ‣ ⁃ followed by space
        if is_bullet_char(ch) && is_at_line_start(text, byte_pos) {
            // Look ahead for space after bullet
            if let Some((_, next_ch)) = chars.get(i + 1) {
                if next_ch.is_whitespace() {
                    // End previous segment before bullet
                    if start < byte_pos {
                        sentences.push((start, byte_pos));
                    }
                    // Start new segment at bullet
                    start = byte_pos;
                }
            }
        }

        // Check for numbered list items at start of line (1. 2. a. b. etc.)
        if (ch.is_ascii_digit() || ch.is_ascii_alphabetic()) && is_at_line_start(text, byte_pos) {
            // Look for pattern: digit/letter followed by . or ) and space
            if let Some((_, dot_ch)) = chars.get(i + 1) {
                if *dot_ch == '.' || *dot_ch == ')' {
                    if let Some((_, space_ch)) = chars.get(i + 2) {
                        if space_ch.is_whitespace() {
                            // End previous segment before number
                            if start < byte_pos {
                                sentences.push((start, byte_pos));
                            }
                            // Start new segment at number
                            start = byte_pos;
                        }
                    }
                }
            }
        }

        // Standard sentence terminators (.!?)
        if ch == '.' || ch == '!' || ch == '?' {
            // Skip if this is a list marker (1. or a.) at start of line
            if ch == '.' && i > 0 {
                let prev_char = chars[i - 1].1;
                if (prev_char.is_ascii_digit() || prev_char.is_ascii_alphabetic())
                    && is_at_line_start(text, chars[i - 1].0)
                {
                    // This is a list marker, not a sentence end
                    i += 1;
                    continue;
                }
            }

            let rest = &text[byte_pos + ch.len_utf8()..];

            // End of sentence if followed by whitespace or end of text
            // But not for abbreviations like "Mr." followed by lowercase
            if rest.is_empty() || is_sentence_boundary(rest) {
                let end = byte_pos + ch.len_utf8();
                if start < end {
                    sentences.push((start, end));
                }
                // Start next sentence after any whitespace
                let trimmed_len = rest.len() - rest.trim_start().len();
                start = byte_pos + ch.len_utf8() + trimmed_len;
            }
        }

        i += 1;
    }

    // Add remaining text as final sentence if there's any non-whitespace content
    if start < text.len() {
        let remaining = &text[start..];
        if !remaining.trim().is_empty() {
            sentences.push((start, text.len()));
        }
    }

    // If no sentences were found but there's actual content, treat entire text as one sentence
    if sentences.is_empty() && !text.trim().is_empty() {
        sentences.push((0, text.len()));
    }

    sentences
}

/// Check if character is a common bullet point marker
fn is_bullet_char(ch: char) -> bool {
    matches!(
        ch,
        '-' | '*' | '•' | '◦' | '▪' | '▸' | '►' | '‣' | '⁃' | '–' | '—'
    )
}

/// Check if position is at the start of a line (after newline or at text start)
fn is_at_line_start(text: &str, byte_pos: usize) -> bool {
    if byte_pos == 0 {
        return true;
    }
    // Check if preceded by newline (with optional whitespace)
    let before = &text[..byte_pos];
    let trimmed = before.trim_end_matches([' ', '\t']);
    trimmed.ends_with('\n') || trimmed.ends_with('\r')
}

/// Check if this looks like a sentence boundary (not an abbreviation)
fn is_sentence_boundary(rest: &str) -> bool {
    if rest.is_empty() {
        return true;
    }

    let first_non_ws = rest.trim_start().chars().next();
    match first_non_ws {
        None => true,
        Some(ch) => {
            // Sentence boundary if followed by:
            // - Uppercase letter (new sentence)
            // - Newline (paragraph/list item)
            // - Quote or bracket (quoted sentence)
            // - Bullet point
            ch.is_uppercase()
                || ch == '\n'
                || ch == '\r'
                || ch == '"'  // Straight double quote
                || ch == '\'' // Straight single quote
                || ch == '\u{201C}' // Left double quote "
                || ch == '\u{201D}' // Right double quote "
                || ch == '\u{2018}' // Left single quote '
                || ch == '\u{2019}' // Right single quote '
                || is_bullet_char(ch)
                || ch.is_ascii_digit() // Numbered list
        }
    }
}

/// Quick check if document should skip Harper analysis entirely.
///
/// Returns `Some(true)` if >60% of sentences are in an excluded language,
/// `Some(false)` if document is likely English or a mix that should be analyzed,
/// `None` if language detection is disabled or no languages are excluded.
///
/// This is used as an early bailout before expensive Harper analysis to avoid
/// wasting ~4.5s on documents that will have all errors filtered anyway.
pub fn should_skip_harper_analysis(
    text: &str,
    enabled: bool,
    excluded_languages: &[String],
) -> Option<bool> {
    // Disabled or no exclusions - can't make a determination
    if !enabled || excluded_languages.is_empty() {
        return None;
    }

    // Convert language strings to Lang enums
    let langs: Vec<Lang> = excluded_languages
        .iter()
        .filter_map(|s| lang_from_string(s))
        .collect();

    if langs.is_empty() {
        return None;
    }

    // Use shared logic to calculate excluded language ratio
    match calculate_excluded_language_ratio(text, &langs) {
        Some((_, ratio)) => Some(ratio > NON_ENGLISH_THRESHOLD),
        None => Some(false), // Document language not in excluded list
    }
}

/// Convert language string to whichlang Lang enum
pub fn lang_from_string(s: &str) -> Option<Lang> {
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
        assert_eq!(sentences.len(), 0, "Empty text should have no sentences");
    }

    #[test]
    fn test_split_whitespace_only() {
        let text = "   \n\n  ";
        let sentences = split_into_sentences(text);
        assert_eq!(
            sentences.len(),
            0,
            "Whitespace-only text should have no sentences"
        );
    }

    // MARK: - Bullet Point Tests

    #[test]
    fn test_split_bullet_points() {
        let text = "- First item\n- Second item\n- Third item";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 3, "Should split into 3 bullet items");
    }

    #[test]
    fn test_split_mixed_bullets() {
        let text = "• Bullet one\n* Bullet two\n- Bullet three";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 3, "Should handle different bullet styles");
    }

    #[test]
    fn test_split_numbered_list() {
        let text = "1. First item\n2. Second item\n3. Third item";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 3, "Should split numbered list");
    }

    #[test]
    fn test_split_lettered_list() {
        let text = "a. First item\nb. Second item\nc. Third item";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 3, "Should split lettered list");
    }

    // MARK: - Paragraph Break Tests

    #[test]
    fn test_split_paragraph_breaks() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.";
        let sentences = split_into_sentences(text);
        assert_eq!(sentences.len(), 3, "Should split on paragraph breaks");
    }

    #[test]
    fn test_split_paragraph_without_punctuation() {
        let text = "First paragraph\n\nSecond paragraph\n\nThird paragraph";
        let sentences = split_into_sentences(text);
        assert_eq!(
            sentences.len(),
            3,
            "Should split paragraphs even without punctuation"
        );
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
        assert_eq!(
            filtered.len(),
            errors.len(),
            "No filtering when no languages excluded"
        );
    }

    // MARK: - Single Sentence Tests

    #[test]
    fn test_single_german_sentence_filtered() {
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let text = "Hallo Welt, wie geht es dir?";
        let errors = vec![
            create_error(0, 5, "Unknown word"),   // Hallo
            create_error(11, 14, "Unknown word"), // wie
        ];

        let filtered = filter.filter_errors(errors, text);
        assert_eq!(
            filtered.len(),
            0,
            "All errors in German sentence should be filtered"
        );
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
        assert_eq!(
            filtered.len(),
            errors.len(),
            "Errors in English sentence should be kept"
        );
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
        assert_eq!(
            filtered.len(),
            0,
            "Spanish sentence errors should be filtered"
        );
    }

    #[test]
    fn test_single_french_sentence() {
        let filter = LanguageFilter::new(true, vec!["french".to_string()]);
        let text = "Bonjour mes amis, comment allez-vous?";
        let errors = vec![
            create_error(0, 7, "Unknown word"),   // Bonjour
            create_error(18, 25, "Unknown word"), // comment
        ];

        let filtered = filter.filter_errors(errors, text);
        assert_eq!(
            filtered.len(),
            0,
            "French sentence errors should be filtered"
        );
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
        assert_eq!(
            filtered.len(),
            1,
            "Should keep English sentence error, filter German sentence error"
        );

        // Verify the kept error is from the English sentence
        assert_eq!(filtered[0].start, 11);
        assert_eq!(filtered[0].end, 18);
    }

    #[test]
    fn test_mixed_english_german_sentences() {
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let text = "This is English. Das ist Deutsch. More English here.";
        let errors = vec![
            create_error(5, 7, "Error 1"),   // "is" in English sentence
            create_error(21, 23, "Error 2"), // "ist" in German sentence
            create_error(44, 48, "Error 3"), // "here" in English sentence
        ];

        let filtered = filter.filter_errors(errors, text);

        // Should keep errors from English sentences, filter from German
        assert_eq!(filtered.len(), 2, "Should keep English sentence errors");
        assert_eq!(filtered[0].start, 5); // First English error
        assert_eq!(filtered[1].start, 44); // Second English error
    }

    #[test]
    fn test_mixed_english_spanish_french() {
        let filter = LanguageFilter::new(true, vec!["spanish".to_string(), "french".to_string()]);
        let text = "Hello. Hola amigos. Bonjour. Goodbye.";
        let errors = vec![
            create_error(0, 5, "Error"),   // Hello (English)
            create_error(7, 11, "Error"),  // Hola (Spanish)
            create_error(20, 27, "Error"), // Bonjour (French)
            create_error(29, 36, "Error"), // Goodbye (English)
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
            elapsed.as_millis() < 500,
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
            elapsed.as_millis() < 100,
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
            create_error(0, 4, "Error 1"),   // Hola (Spanish sentence)
            create_error(13, 18, "Error 2"), // Hallo (German sentence)
            create_error(25, 30, "Error 3"), // Hello (English sentence)
        ];

        let filtered = filter.filter_errors(errors, text);

        // Spanish sentence filtered, German and English kept
        assert_eq!(filtered.len(), 2);
    }

    #[test]
    fn test_multiple_excluded_languages() {
        let filter = LanguageFilter::new(
            true,
            vec![
                "german".to_string(),
                "spanish".to_string(),
                "french".to_string(),
            ],
        );
        // Use longer sentences to provide enough context for accurate language detection
        let text =
            "This is English. Das ist Deutsch. Esto es Español. C'est Français. More English here.";
        let errors = vec![
            create_error(0, 7, "E1"),   // "This is" in English sentence
            create_error(21, 24, "E2"), // "ist" in German sentence
            create_error(38, 40, "E3"), // "es" in Spanish sentence
            create_error(58, 64, "E4"), // "C'est" in French sentence
            create_error(71, 75, "E5"), // "More" in English sentence
        ];

        let filtered = filter.filter_errors(errors, text);

        // Should keep only English sentence errors (E1 and E5)
        assert_eq!(filtered.len(), 2);
    }

    // MARK: - Document Language Detection Tests (for readability skip)

    #[test]
    fn test_is_non_english_disabled() {
        // When language detection is disabled, always return false (assume English)
        let filter = LanguageFilter::new(false, vec!["german".to_string()]);
        let german_text =
            "Das ist ein langer deutscher Text. Er enthält mehrere Sätze. Die Sprache ist Deutsch.";

        assert!(
            !filter.is_document_primarily_non_english(german_text),
            "Should return false when detection is disabled"
        );
    }

    #[test]
    fn test_is_non_english_no_excluded_languages() {
        // When no languages are excluded, always return false (assume English)
        let filter = LanguageFilter::new(true, vec![]);
        let german_text =
            "Das ist ein langer deutscher Text. Er enthält mehrere Sätze. Die Sprache ist Deutsch.";

        assert!(
            !filter.is_document_primarily_non_english(german_text),
            "Should return false when no languages excluded"
        );
    }

    #[test]
    fn test_is_non_english_english_document() {
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let english_text = "This is a long English document. It contains several sentences. The language is English. We want to make sure readability works here.";

        assert!(
            !filter.is_document_primarily_non_english(english_text),
            "English document should not be detected as non-English"
        );
    }

    #[test]
    fn test_is_non_english_german_document() {
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let german_text = "Das ist ein langer deutscher Text. Er enthält mehrere Sätze. Die Sprache ist Deutsch. Wir wollen sicherstellen, dass die Erkennung funktioniert.";

        assert!(
            filter.is_document_primarily_non_english(german_text),
            "German document should be detected as non-English when German is excluded"
        );
    }

    #[test]
    fn test_is_non_english_german_not_in_excluded() {
        // German document but German is not in excluded list
        let filter = LanguageFilter::new(true, vec!["spanish".to_string()]);
        let german_text =
            "Das ist ein langer deutscher Text. Er enthält mehrere Sätze. Die Sprache ist Deutsch.";

        assert!(
            !filter.is_document_primarily_non_english(german_text),
            "German document should not be flagged when German is not excluded"
        );
    }

    #[test]
    fn test_is_non_english_mixed_document() {
        // Mixed document with <60% German - should not be flagged
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);
        let mixed_text = "This is English. Hello world. How are you today? Das ist Deutsch. This is more English text.";

        assert!(
            !filter.is_document_primarily_non_english(mixed_text),
            "Mixed document with <60% German should not be flagged as non-English"
        );
    }

    #[test]
    fn test_is_non_english_spanish_document() {
        let filter = LanguageFilter::new(true, vec!["spanish".to_string()]);
        let spanish_text = "Este es un documento en español. Contiene varias oraciones. El idioma es español. Queremos asegurarnos de que la detección funcione correctamente.";

        assert!(
            filter.is_document_primarily_non_english(spanish_text),
            "Spanish document should be detected as non-English when Spanish is excluded"
        );
    }

    #[test]
    fn test_is_non_english_french_document() {
        let filter = LanguageFilter::new(true, vec!["french".to_string()]);
        let french_text = "Ceci est un long document en français. Il contient plusieurs phrases. La langue est le français. Nous voulons nous assurer que la détection fonctionne.";

        assert!(
            filter.is_document_primarily_non_english(french_text),
            "French document should be detected as non-English when French is excluded"
        );
    }

    #[test]
    fn test_is_non_english_empty_text() {
        let filter = LanguageFilter::new(true, vec!["german".to_string()]);

        assert!(
            !filter.is_document_primarily_non_english(""),
            "Empty text should return false"
        );
    }

    // MARK: - Early Language Detection Tests (should_skip_harper_analysis)

    #[test]
    fn test_should_skip_harper_disabled() {
        // When disabled, returns None (no determination)
        let result = should_skip_harper_analysis(
            "Das ist ein deutscher Text.",
            false,
            &["german".to_string()],
        );
        assert!(result.is_none(), "Should return None when disabled");
    }

    #[test]
    fn test_should_skip_harper_no_excluded_languages() {
        // When no languages excluded, returns None
        let result = should_skip_harper_analysis("Das ist ein deutscher Text.", true, &[]);
        assert!(
            result.is_none(),
            "Should return None when no languages excluded"
        );
    }

    #[test]
    fn test_should_skip_harper_english_document() {
        // English document should not be skipped
        let result = should_skip_harper_analysis(
            "This is an English document. It contains several sentences. We want to analyze it.",
            true,
            &["german".to_string()],
        );
        assert_eq!(
            result,
            Some(false),
            "English document should not be skipped"
        );
    }

    #[test]
    fn test_should_skip_harper_german_document() {
        // German document (>60% German) should be skipped
        let result = should_skip_harper_analysis(
            "Das ist ein langer deutscher Text. Er enthält mehrere Sätze. Die Sprache ist Deutsch. Wir wollen sicherstellen, dass die Erkennung funktioniert.",
            true,
            &["german".to_string()],
        );
        assert_eq!(
            result,
            Some(true),
            "German document should be skipped when German is excluded"
        );
    }

    #[test]
    fn test_should_skip_harper_mixed_document() {
        // Mixed document with <60% German should not be skipped
        let result = should_skip_harper_analysis(
            "This is English. Hello world. How are you today? Das ist Deutsch. This is more English text.",
            true,
            &["german".to_string()],
        );
        assert_eq!(
            result,
            Some(false),
            "Mixed document with <60% German should not be skipped"
        );
    }

    #[test]
    fn test_should_skip_harper_wrong_excluded_language() {
        // German document but only Spanish is excluded - should not skip
        let result = should_skip_harper_analysis(
            "Das ist ein langer deutscher Text. Er enthält mehrere Sätze.",
            true,
            &["spanish".to_string()],
        );
        assert_eq!(
            result,
            Some(false),
            "German document should not be skipped when only Spanish is excluded"
        );
    }

    #[test]
    fn test_should_skip_harper_empty_text() {
        let result = should_skip_harper_analysis("", true, &["german".to_string()]);
        assert_eq!(result, Some(false), "Empty text should return Some(false)");
    }
}
