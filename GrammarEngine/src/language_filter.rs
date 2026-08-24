// Language Filter - semantic-segment language detection
//
// Splits text into semantic segments, detects each segment once, and reuses that
// summary for the early Harper bailout, readability, and error filtering.

use crate::analyzer::GrammarError;
use std::collections::HashSet;
use std::sync::LazyLock;
use whatlang::{Detector, Lang};

/// Threshold for treating a document as primarily written in selected languages.
const NON_ENGLISH_THRESHOLD: f64 = 0.6;

/// Whatlang must consider its complete language catalog. Restricting candidates to
/// selected languages can force unrelated text into a selected language.
static LANGUAGE_DETECTOR: LazyLock<Detector> = LazyLock::new(Detector::new);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct SegmentRange {
    byte_start: usize,
    byte_end: usize,
    scalar_start: usize,
    scalar_end: usize,
}

#[derive(Clone, Copy, Debug)]
struct DetectedSegment {
    range: SegmentRange,
    language: Option<Lang>,
    confidence: f64,
    reliable: bool,
}

/// Reusable language detections for one document.
#[derive(Clone, Debug, Default)]
pub struct LanguageDetectionSummary {
    segments: Vec<DetectedSegment>,
}

impl LanguageDetectionSummary {
    fn detect(text: &str) -> Self {
        let segments = split_into_segments(text)
            .into_iter()
            .map(|range| {
                let info = text
                    .get(range.byte_start..range.byte_end)
                    .and_then(|segment| LANGUAGE_DETECTOR.detect(segment));

                DetectedSegment {
                    range,
                    language: info.as_ref().map(|detected| detected.lang()),
                    confidence: info.as_ref().map_or(0.0, |detected| detected.confidence()),
                    reliable: info.as_ref().is_some_and(|detected| detected.is_reliable()),
                }
            })
            .collect();

        Self { segments }
    }

    fn selected_ratio(&self, selected_languages: &HashSet<Lang>) -> f64 {
        if self.segments.is_empty() {
            return 0.0;
        }

        let selected_count = self
            .segments
            .iter()
            .filter(|segment| {
                segment.reliable
                    && segment
                        .language
                        .is_some_and(|language| selected_languages.contains(&language))
            })
            .count();

        selected_count as f64 / self.segments.len() as f64
    }

    fn is_primarily_selected(&self, selected_languages: &HashSet<Lang>) -> bool {
        self.selected_ratio(selected_languages) > NON_ENGLISH_THRESHOLD
    }
}

/// Language filter configuration.
pub struct LanguageFilter {
    enabled: bool,
    excluded_languages: HashSet<Lang>,
}

impl LanguageFilter {
    /// Create a language filter from ISO 639-3 language codes.
    pub fn new(enabled: bool, excluded_languages: Vec<String>) -> Self {
        let excluded_languages = excluded_languages
            .into_iter()
            .filter_map(|value| {
                Lang::from_code(value.clone())
                    .or_else(|| legacy_language_code(&value).and_then(Lang::from_code))
            })
            .filter(|language| *language != Lang::Eng)
            .collect();

        Self {
            enabled,
            excluded_languages,
        }
    }

    pub fn excluded_language_count(&self) -> usize {
        self.excluded_languages.len()
    }

    /// Detect every substantive semantic segment once.
    pub fn analyze(&self, text: &str) -> Option<LanguageDetectionSummary> {
        if !self.enabled || self.excluded_languages.is_empty() {
            return None;
        }

        Some(LanguageDetectionSummary::detect(text))
    }

    pub fn should_skip_harper(&self, summary: &LanguageDetectionSummary) -> bool {
        summary.is_primarily_selected(&self.excluded_languages)
    }

    /// Filter errors using a summary already calculated before Harper ran.
    pub fn filter_errors_with_summary(
        &self,
        errors: Vec<GrammarError>,
        summary: &LanguageDetectionSummary,
    ) -> Vec<GrammarError> {
        if !self.enabled || self.excluded_languages.is_empty() {
            return errors;
        }

        if self.should_skip_harper(summary) {
            tracing::info!(
                "LanguageFilter: selected languages cover {:.0}% of segments; filtering all {} errors",
                summary.selected_ratio(&self.excluded_languages) * 100.0,
                errors.len()
            );
            return vec![];
        }

        errors
            .into_iter()
            .filter(|error| {
                let detected_segment = summary.segments.iter().find(|segment| {
                    error.start >= segment.range.scalar_start
                        && error.end <= segment.range.scalar_end
                });

                match detected_segment {
                    Some(segment) => {
                        let should_ignore = segment.reliable
                            && segment.language.is_some_and(|language| {
                                self.excluded_languages.contains(&language)
                            });

                        if should_ignore {
                            tracing::debug!(
                                "LanguageFilter: filtering error in language={:?}, confidence={:.2}",
                                segment.language,
                                segment.confidence
                            );
                        }

                        !should_ignore
                    }
                    // If an error cannot be mapped to a segment, preserve it.
                    None => true,
                }
            })
            .collect()
    }

    /// Convenience path for focused tests and callers without a cached summary.
    pub fn filter_errors(&self, errors: Vec<GrammarError>, text: &str) -> Vec<GrammarError> {
        match self.analyze(text) {
            Some(summary) => self.filter_errors_with_summary(errors, &summary),
            None => errors,
        }
    }

    /// Whether selected, reliable segments account for more than 60% of the document.
    pub fn is_document_primarily_non_english(&self, text: &str) -> bool {
        self.analyze(text)
            .is_some_and(|summary| self.should_skip_harper(&summary))
    }
}

/// Accept the display names persisted by TextWarden versions before ISO-code storage.
/// Swift migrates these values eagerly; this fallback keeps the FFI boundary safe
/// during upgrades where an analysis request may race preference initialization.
fn legacy_language_code(value: &str) -> Option<&'static str> {
    match value.to_lowercase().as_str() {
        "arabic" => Some("ara"),
        "dutch" => Some("nld"),
        "french" => Some("fra"),
        "german" => Some("deu"),
        "hindi" => Some("hin"),
        "italian" => Some("ita"),
        "japanese" => Some("jpn"),
        "korean" => Some("kor"),
        "mandarin" | "chinese" => Some("cmn"),
        "portuguese" => Some("por"),
        "russian" => Some("rus"),
        "spanish" => Some("spa"),
        "swedish" => Some("swe"),
        "turkish" => Some("tur"),
        "vietnamese" => Some("vie"),
        _ => None,
    }
}

/// Split text into sentences/segments for language detection
/// Handles: punctuation (.!?), paragraph breaks, bullet points, numbered lists
/// Returns a vector of (start, end) byte positions for each segment
pub fn split_into_sentences(text: &str) -> Vec<(usize, usize)> {
    split_into_byte_ranges(text)
}

fn split_into_segments(text: &str) -> Vec<SegmentRange> {
    let scalar_boundaries: Vec<usize> = text
        .char_indices()
        .map(|(byte_index, _)| byte_index)
        .chain(std::iter::once(text.len()))
        .collect();

    split_into_byte_ranges(text)
        .into_iter()
        .filter(|(byte_start, byte_end)| {
            text.get(*byte_start..*byte_end)
                .is_some_and(|segment| !segment.trim().is_empty())
        })
        .filter_map(|(byte_start, byte_end)| {
            let scalar_start = scalar_boundaries.binary_search(&byte_start).ok()?;
            let scalar_end = scalar_boundaries.binary_search(&byte_end).ok()?;
            Some(SegmentRange {
                byte_start,
                byte_end,
                scalar_start,
                scalar_end,
            })
        })
        .collect()
}

fn split_into_byte_ranges(text: &str) -> Vec<(usize, usize)> {
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
    let filter = LanguageFilter::new(enabled, excluded_languages.to_vec());
    let summary = filter.analyze(text)?;
    Some(filter.should_skip_harper(&summary))
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

    const ENGLISH_SENTENCE: &str = "This is a detailed English sentence with enough characteristic words for automatic language detection to produce a useful and dependable result.";
    const GERMAN_SENTENCE: &str = "Dies ist ein ausführlicher deutscher Satz mit genügend charakteristischen Wörtern, damit die automatische Spracherkennung zuverlässig funktioniert.";
    const SPANISH_SENTENCE: &str = "Esta es una oración española detallada con suficientes palabras características para que la detección automática del idioma funcione de manera fiable.";
    const FRENCH_SENTENCE: &str = "Ceci est une phrase française détaillée qui contient suffisamment de mots caractéristiques pour que la détection automatique de la langue fonctionne correctement.";

    fn error_for(text: &str, needle: &str) -> GrammarError {
        let byte_start = text
            .find(needle)
            .expect("test fixture should contain needle");
        let scalar_start = text[..byte_start].chars().count();
        create_error(
            scalar_start,
            scalar_start + needle.chars().count(),
            "Unknown word",
        )
    }

    fn synthetic_summary(detections: &[(Option<Lang>, bool)]) -> LanguageDetectionSummary {
        LanguageDetectionSummary {
            segments: detections
                .iter()
                .enumerate()
                .map(|(index, (language, reliable))| DetectedSegment {
                    range: SegmentRange {
                        byte_start: index,
                        byte_end: index + 1,
                        scalar_start: index,
                        scalar_end: index + 1,
                    },
                    language: *language,
                    confidence: if *reliable { 1.0 } else { 0.5 },
                    reliable: *reliable,
                })
                .collect(),
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

    #[test]
    fn test_split_crlf_paragraphs_and_list_items() {
        let text = "First paragraph\r\n\r\n- Second item\r\n- Third item";
        let sentences = split_into_sentences(text);

        assert_eq!(sentences.len(), 3);
        assert_eq!(&text[sentences[0].0..sentences[0].1], "First paragraph\r");
        assert_eq!(&text[sentences[1].0..sentences[1].1], "- Second item\r\n");
        assert_eq!(&text[sentences[2].0..sentences[2].1], "- Third item");
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
        let filter = LanguageFilter::new(true, vec!["deu".to_string()]);
        let errors = vec![error_for(GERMAN_SENTENCE, "ausführlicher")];

        let filtered = filter.filter_errors(errors, GERMAN_SENTENCE);
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
        let filter = LanguageFilter::new(true, vec!["spa".to_string()]);
        let errors = vec![error_for(SPANISH_SENTENCE, "española")];

        let filtered = filter.filter_errors(errors, SPANISH_SENTENCE);
        assert_eq!(
            filtered.len(),
            0,
            "Spanish sentence errors should be filtered"
        );
    }

    #[test]
    fn test_single_french_sentence() {
        let filter = LanguageFilter::new(true, vec!["fra".to_string()]);
        let errors = vec![error_for(FRENCH_SENTENCE, "française")];

        let filtered = filter.filter_errors(errors, FRENCH_SENTENCE);
        assert_eq!(
            filtered.len(),
            0,
            "French sentence errors should be filtered"
        );
    }

    // MARK: - Multi-Sentence Tests (User Example!)

    #[test]
    fn test_short_ambiguous_segments_fail_open() {
        let filter = LanguageFilter::new(true, vec!["deu".to_string()]);
        let text = "Hello dear Nachbar, how are you doing? Gruss Bob";
        let errors = vec![
            create_error(11, 18, "Unknown word"), // Nachbar (in English sentence)
            create_error(40, 45, "Unknown word"), // Gruss (in German sentence)
        ];

        let filtered = filter.filter_errors(errors, text);

        assert_eq!(
            filtered.len(),
            2,
            "Short ambiguous segments should remain checked"
        );
    }

    #[test]
    fn test_mixed_english_german_sentences() {
        let filter = LanguageFilter::new(true, vec!["deu".to_string()]);
        let text = format!("{ENGLISH_SENTENCE} {GERMAN_SENTENCE} {ENGLISH_SENTENCE}");
        let errors = vec![
            error_for(&text, "detailed"),
            error_for(&text, "ausführlicher"),
        ];

        let filtered = filter.filter_errors(errors, &text);

        // Should keep errors from English sentences, filter from German
        assert_eq!(filtered.len(), 1, "Should keep the English sentence error");
    }

    #[test]
    fn test_mixed_english_spanish_french() {
        let filter = LanguageFilter::new(true, vec!["spa".to_string(), "fra".to_string()]);
        let text =
            format!("{ENGLISH_SENTENCE} {SPANISH_SENTENCE} {FRENCH_SENTENCE} {ENGLISH_SENTENCE}");
        let errors = vec![
            error_for(&text, "detailed"),
            error_for(&text, "española"),
            error_for(&text, "française"),
        ];

        let filtered = filter.filter_errors(errors, &text);

        assert_eq!(filtered.len(), 1, "Should keep only the English error");
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
        let filter = LanguageFilter::new(true, vec!["spa".to_string()]);
        let text = format!("{SPANISH_SENTENCE} {GERMAN_SENTENCE} {ENGLISH_SENTENCE}");
        let errors = vec![
            error_for(&text, "española"),
            error_for(&text, "ausführlicher"),
            error_for(&text, "detailed"),
        ];

        let filtered = filter.filter_errors(errors, &text);

        // Spanish sentence filtered, German and English kept
        assert_eq!(filtered.len(), 2);
    }

    #[test]
    fn test_multiple_excluded_languages() {
        let filter = LanguageFilter::new(
            true,
            vec!["deu".to_string(), "spa".to_string(), "fra".to_string()],
        );
        // Three of five reliable segments are selected: exactly 60% must not
        // trigger the whole-document bailout.
        let text = format!(
            "{ENGLISH_SENTENCE} {GERMAN_SENTENCE} {SPANISH_SENTENCE} {FRENCH_SENTENCE} {ENGLISH_SENTENCE}"
        );
        let errors = vec![
            error_for(&text, "detailed"),
            error_for(&text, "ausführlicher"),
            error_for(&text, "española"),
            error_for(&text, "française"),
        ];

        let summary = filter.analyze(&text).expect("language detection enabled");
        assert!(!filter.should_skip_harper(&summary));

        let filtered = filter.filter_errors_with_summary(errors, &summary);

        assert_eq!(filtered.len(), 1);
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
        let filter = LanguageFilter::new(true, vec!["deu".to_string()]);
        let english_text = format!("{0} {0} {0}", ENGLISH_SENTENCE);

        assert!(
            !filter.is_document_primarily_non_english(&english_text),
            "English document should not be detected as non-English"
        );
    }

    #[test]
    fn test_is_non_english_german_document() {
        let filter = LanguageFilter::new(true, vec!["deu".to_string()]);
        let german_text = format!("{0} {0} {0}", GERMAN_SENTENCE);

        assert!(
            filter.is_document_primarily_non_english(&german_text),
            "German document should be detected as non-English when German is excluded"
        );
    }

    #[test]
    fn test_is_non_english_german_not_in_excluded() {
        // German document but German is not in excluded list
        let filter = LanguageFilter::new(true, vec!["spa".to_string()]);
        let german_text = format!("{0} {0} {0}", GERMAN_SENTENCE);

        assert!(
            !filter.is_document_primarily_non_english(&german_text),
            "German document should not be flagged when German is not excluded"
        );
    }

    #[test]
    fn test_is_non_english_mixed_document() {
        // Mixed document with <60% German - should not be flagged
        let filter = LanguageFilter::new(true, vec!["deu".to_string()]);
        let mixed_text = format!(
            "{ENGLISH_SENTENCE} {ENGLISH_SENTENCE} {ENGLISH_SENTENCE} {GERMAN_SENTENCE} {GERMAN_SENTENCE}"
        );

        assert!(
            !filter.is_document_primarily_non_english(&mixed_text),
            "Mixed document with <60% German should not be flagged as non-English"
        );
    }

    #[test]
    fn test_is_non_english_spanish_document() {
        let filter = LanguageFilter::new(true, vec!["spa".to_string()]);
        let spanish_text = format!("{0} {0} {0}", SPANISH_SENTENCE);

        assert!(
            filter.is_document_primarily_non_english(&spanish_text),
            "Spanish document should be detected as non-English when Spanish is excluded"
        );
    }

    #[test]
    fn test_is_non_english_french_document() {
        let filter = LanguageFilter::new(true, vec!["fra".to_string()]);
        let french_text = format!("{0} {0} {0}", FRENCH_SENTENCE);

        assert!(
            filter.is_document_primarily_non_english(&french_text),
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
        let german_text = format!("{0} {0} {0}", GERMAN_SENTENCE);
        let result = should_skip_harper_analysis(&german_text, true, &["deu".to_string()]);
        assert_eq!(
            result,
            Some(true),
            "German document should be skipped when German is excluded"
        );
    }

    #[test]
    fn test_should_skip_harper_mixed_document() {
        // Mixed document with <60% German should not be skipped
        let mixed_text = format!(
            "{ENGLISH_SENTENCE} {ENGLISH_SENTENCE} {ENGLISH_SENTENCE} {GERMAN_SENTENCE} {GERMAN_SENTENCE}"
        );
        let result = should_skip_harper_analysis(&mixed_text, true, &["deu".to_string()]);
        assert_eq!(
            result,
            Some(false),
            "Mixed document with <60% German should not be skipped"
        );
    }

    #[test]
    fn test_should_skip_harper_wrong_excluded_language() {
        // German document but only Spanish is excluded - should not skip
        let german_text = format!("{0} {0} {0}", GERMAN_SENTENCE);
        let result = should_skip_harper_analysis(&german_text, true, &["spa".to_string()]);
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

    #[test]
    fn test_latvian_issue_samples_are_reliably_filtered() {
        let filter = LanguageFilter::new(true, vec!["lav".to_string()]);
        let samples = [
            "Šodien ir silta diena un es rakstu vēstuli.",
            "Latviešu valoda ir skaista un bagāta valoda, kurā runā Latvijā.",
        ];

        for text in samples {
            let summary = filter.analyze(text).expect("language detection enabled");
            let segment = summary.segments.first().expect("one Latvian segment");
            assert_eq!(segment.language, Some(Lang::Lav));
            assert!(segment.reliable);

            let errors = vec![error_for(text, text.split_whitespace().next().unwrap())];
            assert!(filter
                .filter_errors_with_summary(errors, &summary)
                .is_empty());
        }
    }

    #[test]
    fn test_existing_language_catalog_samples_are_reliable() {
        let samples = [
            (Lang::Ara, "اللغة العربية لغة جميلة وغنية، ويتحدث بها ملايين الناس في بلدان عديدة حول العالم كل يوم."),
            (Lang::Nld, "Dit is een uitgebreide Nederlandse zin met voldoende kenmerkende woorden om de automatische taalherkenning betrouwbaar te laten werken."),
            (Lang::Eng, ENGLISH_SENTENCE),
            (Lang::Fra, FRENCH_SENTENCE),
            (Lang::Deu, GERMAN_SENTENCE),
            (Lang::Hin, "हिन्दी भारत में व्यापक रूप से बोली जाने वाली एक समृद्ध भाषा है और इसकी साहित्यिक परंपरा बहुत पुरानी है।"),
            (Lang::Ita, "Questa è una frase italiana dettagliata con abbastanza parole caratteristiche perché il rilevamento automatico della lingua funzioni in modo affidabile."),
            (Lang::Jpn, "日本語は日本で広く話されている言語であり、豊かな文学と長い文化的な歴史を持っています。"),
            (Lang::Kor, "한국어는 대한민국에서 널리 사용되는 언어이며 풍부한 문학과 오랜 문화적 역사를 가지고 있습니다."),
            (Lang::Cmn, "中文是一种历史悠久而且内容丰富的语言，世界各地有许多人每天使用中文进行交流和学习。"),
            (Lang::Por, "Esta é uma frase portuguesa detalhada com palavras características suficientes para que a detecção automática do idioma funcione de forma confiável."),
            (Lang::Rus, "Русский язык обладает богатой литературной традицией, и миллионы людей используют его для общения каждый день."),
            (Lang::Spa, SPANISH_SENTENCE),
            (Lang::Swe, "Det här är en detaljerad svensk mening med tillräckligt många karakteristiska ord för att den automatiska språkidentifieringen ska fungera tillförlitligt."),
            (Lang::Tur, "Bu, otomatik dil algılamanın güvenilir bir şekilde çalışması için yeterli karakteristik kelime içeren ayrıntılı bir Türkçe cümledir."),
            (Lang::Vie, "Tiếng Việt là một ngôn ngữ phong phú với lịch sử lâu đời và được hàng triệu người sử dụng để giao tiếp mỗi ngày."),
        ];

        for (expected, text) in samples {
            let summary = LanguageDetectionSummary::detect(text);
            let segment = summary.segments.first().expect("one language segment");
            assert_eq!(
                segment.language,
                Some(expected),
                "unexpected language for {text}"
            );
            assert!(segment.reliable, "unreliable language for {text}");
        }
    }

    #[test]
    fn test_baltic_and_nordic_samples_do_not_confuse_neighboring_languages() {
        let samples = [
            (Lang::Lav, true, "Latviešu valoda ir bagāta un skaista, un Latvijā cilvēki to lieto ikdienas sarunās, skolās un literatūrā."),
            (Lang::Lit, true, "Lietuvių kalba yra turtinga ir graži, o Lietuvoje žmonės ją kasdien vartoja pokalbiuose, mokyklose ir literatūroje."),
            (Lang::Est, true, "Eesti keel on rikkalik ja kaunis ning Eestis kasutatakse seda iga päev vestlustes, koolides ja kirjanduses."),
            (Lang::Fin, true, "Suomen kieli on rikas ja kaunis, ja Suomessa ihmiset käyttävät sitä päivittäin keskusteluissa, kouluissa ja kirjallisuudessa."),
            (Lang::Swe, true, "Svenska språket är rikt och vackert, och i Sverige använder människor det varje dag i samtal, skolor och litteratur."),
            (Lang::Dan, false, "Jeg synes, at det danske sprog er meget smukt, fordi ordene lyder hyggelige, når mennesker taler sammen, og børnene lærer at læse og skrive i skolen, mens familierne bruger sproget derhjemme hver eneste dag."),
            (Lang::Nob, false, "Det norske språket er rikt og vakkert, og i Norge bruker mennesker det hver dag i samtaler, skoler og litteratur."),
        ];

        for (expected, should_be_reliable, text) in samples {
            let summary = LanguageDetectionSummary::detect(text);
            let segment = summary.segments.first().expect("one language segment");
            assert_eq!(
                segment.language,
                Some(expected),
                "unexpected language for {text}"
            );
            assert_eq!(
                segment.reliable, should_be_reliable,
                "unexpected reliability for {text}"
            );
        }
    }

    #[test]
    fn test_unreliable_danish_norwegian_confusion_fails_open() {
        let text = "Jeg synes, at det danske sprog er meget smukt, fordi ordene lyder hyggelige, når mennesker taler sammen, og børnene lærer at læse og skrive i skolen, mens familierne bruger sproget derhjemme hver eneste dag.";
        let filter = LanguageFilter::new(true, vec!["dan".to_string()]);
        let summary = filter.analyze(text).expect("language detection enabled");
        let segment = summary.segments.first().expect("one language segment");

        assert_eq!(segment.language, Some(Lang::Dan));
        assert!(!segment.reliable);
        assert_eq!(
            filter
                .filter_errors_with_summary(vec![error_for(text, "danske")], &summary)
                .len(),
            1
        );
    }

    #[test]
    fn test_unselected_latvian_remains_checked() {
        let text = "Šodien ir silta diena un es rakstu vēstuli.";
        let filter = LanguageFilter::new(true, vec!["lit".to_string()]);
        let errors = vec![error_for(text, "Šodien")];

        assert_eq!(filter.filter_errors(errors, text).len(), 1);
    }

    #[test]
    fn test_multibyte_ranges_map_to_harper_scalar_offsets() {
        let text = format!("👋 Šodien ir silta diena un es rakstu vēstuli. {ENGLISH_SENTENCE}");
        let filter = LanguageFilter::new(true, vec!["lav".to_string()]);
        let latvian_error = error_for(&text, "vēstuli");
        let english_error = error_for(&text, "detailed");
        let expected_english_start = english_error.start;

        let filtered = filter.filter_errors(vec![latvian_error, english_error], &text);

        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].start, expected_english_start);
    }

    #[test]
    fn test_cjk_and_crlf_ranges_map_to_harper_scalar_offsets() {
        let chinese = "中文是一种历史悠久而且内容丰富的语言，许多人每天使用中文进行交流?";
        let text = format!("{chinese}\r\n\r\n{ENGLISH_SENTENCE}");
        let filter = LanguageFilter::new(true, vec!["cmn".to_string()]);
        let chinese_error = error_for(&text, "历史悠久");
        let english_error = error_for(&text, "detailed");
        let expected_english_start = english_error.start;

        let filtered = filter.filter_errors(vec![chinese_error, english_error], &text);

        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].start, expected_english_start);
    }

    #[test]
    fn test_exactly_sixty_percent_selected_does_not_skip() {
        let filter = LanguageFilter::new(true, vec!["lav".to_string()]);
        let summary = synthetic_summary(&[
            (Some(Lang::Lav), true),
            (Some(Lang::Lav), true),
            (Some(Lang::Lav), true),
            (Some(Lang::Eng), true),
            (Some(Lang::Eng), true),
        ]);

        assert_eq!(summary.selected_ratio(&filter.excluded_languages), 0.6);
        assert!(!filter.should_skip_harper(&summary));
    }

    #[test]
    fn test_multiple_selected_languages_can_trigger_document_skip() {
        let filter = LanguageFilter::new(true, vec!["lav".to_string(), "fra".to_string()]);
        let summary = synthetic_summary(&[
            (Some(Lang::Lav), true),
            (Some(Lang::Lav), true),
            (Some(Lang::Fra), true),
            (Some(Lang::Fra), true),
            (Some(Lang::Eng), true),
        ]);

        assert!(filter.should_skip_harper(&summary));
    }

    #[test]
    fn test_unreliable_segments_remain_in_ratio_denominator() {
        let filter = LanguageFilter::new(true, vec!["lav".to_string()]);
        let summary = synthetic_summary(&[
            (Some(Lang::Lav), true),
            (Some(Lang::Lav), true),
            (Some(Lang::Lav), true),
            (Some(Lang::Lav), false),
            (None, false),
        ]);

        assert_eq!(summary.selected_ratio(&filter.excluded_languages), 0.6);
        assert!(!filter.should_skip_harper(&summary));
    }

    #[test]
    fn test_all_non_english_languages_can_be_selected() {
        let codes = Lang::all()
            .iter()
            .filter(|language| **language != Lang::Eng)
            .map(|language| language.code().to_string())
            .collect();
        let filter = LanguageFilter::new(true, codes);

        assert_eq!(filter.excluded_language_count(), 69);
    }

    #[test]
    #[ignore]
    fn test_performance_whatlang_detection_profiles() {
        use std::hint::black_box;
        use std::time::Instant;

        let short = "Šodien ir silta diena un es rakstu vēstuli.";
        let document = ENGLISH_SENTENCE.repeat(34);
        let mixed_segments = (0..100)
            .map(|index| match index % 4 {
                0 => format!("- {ENGLISH_SENTENCE}"),
                1 => format!("- {GERMAN_SENTENCE}"),
                2 => format!("- {SPANISH_SENTENCE}"),
                _ => format!("- {FRENCH_SENTENCE}"),
            })
            .collect::<Vec<_>>()
            .join("\n");

        fn average_micros(text: &str, iterations: u32) -> u128 {
            let start = Instant::now();
            for _ in 0..iterations {
                black_box(LanguageDetectionSummary::detect(black_box(text)));
            }
            start.elapsed().as_micros() / u128::from(iterations)
        }

        black_box(LanguageDetectionSummary::detect(short));
        let short_micros = average_micros(short, 1_000);
        let document_micros = average_micros(&document, 200);
        let mixed_micros = average_micros(&mixed_segments, 100);

        println!("short segment: {short_micros} µs");
        println!(
            "4–5 KB document ({} bytes): {document_micros} µs",
            document.len()
        );
        println!(
            "mixed document ({} segments, {} bytes): {mixed_micros} µs",
            split_into_segments(&mixed_segments).len(),
            mixed_segments.len()
        );

        assert!(short_micros < 1_000);
        assert!(document_micros < 10_000);
        assert!(mixed_micros < 20_000);
    }
}
