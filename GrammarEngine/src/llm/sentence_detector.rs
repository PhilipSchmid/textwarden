// Sentence Detector - Identifies complete sentences for LLM analysis
//
// Only triggers LLM analysis for complete sentences to avoid
// analyzing partial text while the user is still typing.

/// Minimum number of words required for a sentence to be analyzed
pub const MIN_WORDS_FOR_ANALYSIS: usize = 5;

fn is_sentence_terminator(ch: char) -> bool {
    matches!(
        ch,
        '.' | '!' | '?' | '…' // ASCII punctuation and ellipsis
            | '。' | '！' | '？' // Common CJK sentence endings
    )
}

/// Extract complete sentences from text
///
/// A sentence is considered complete if it:
/// - Ends with `.`, `!`, `?`, or a paragraph break
/// - Has at least MIN_WORDS_FOR_ANALYSIS words
///
/// Returns a vector of (sentence, start_offset, end_offset) tuples.
pub fn extract_complete_sentences(text: &str) -> Vec<SentenceSpan> {
    let mut sentences = Vec::new();
    let mut current_start = 0;
    let mut current = String::new();

    for (i, char) in text.char_indices() {
        current.push(char);

        // Check for sentence terminators (ASCII, ellipsis, and common Unicode marks)
        let is_terminator = is_sentence_terminator(char);
        let is_paragraph_break = char == '\n' && current.trim().len() > 1;

        if is_terminator || is_paragraph_break {
            let trimmed = current.trim();

            // Only include sentences with enough words
            let word_count = trimmed.split_whitespace().count();
            if !trimmed.is_empty() && word_count >= MIN_WORDS_FOR_ANALYSIS {
                sentences.push(SentenceSpan {
                    text: trimmed.to_string(),
                    start: current_start,
                    end: i + char.len_utf8(),
                    word_count,
                });
            }

            // Reset for next sentence
            current_start = i + char.len_utf8();
            current.clear();
        }
    }

    sentences
}

/// A span representing a complete sentence in the text
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SentenceSpan {
    pub text: String,
    pub start: usize,
    pub end: usize,
    pub word_count: usize,
}

/// Check if the text ends with a complete sentence
///
/// This is useful for determining whether to trigger LLM analysis.
pub fn ends_with_complete_sentence(text: &str) -> bool {
    let trimmed = text.trim_end();
    if trimmed.is_empty() {
        return false;
    }

    let last_char = trimmed.chars().last().unwrap_or(' ');
    let is_terminated = is_sentence_terminator(last_char);

    if !is_terminated {
        return false;
    }

    // Find the last sentence and check word count
    let sentences = extract_complete_sentences(text);
    sentences
        .last()
        .map_or(false, |s| s.word_count >= MIN_WORDS_FOR_ANALYSIS)
}

/// Get the last complete sentence if available
pub fn get_last_complete_sentence(text: &str) -> Option<SentenceSpan> {
    extract_complete_sentences(text).pop()
}

/// Extract all text that forms complete sentences
///
/// Returns the portion of text that contains only complete sentences,
/// excluding any trailing incomplete text.
pub fn extract_complete_text(text: &str) -> Option<String> {
    let sentences = extract_complete_sentences(text);
    if sentences.is_empty() {
        return None;
    }

    let last = sentences.last()?;
    Some(text[..last.end].to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_complete_sentences() {
        let text = "This is a complete sentence. This is another one! And a question?";
        let sentences = extract_complete_sentences(text);

        assert_eq!(sentences.len(), 3);
        assert_eq!(sentences[0].text, "This is a complete sentence.");
        assert_eq!(sentences[1].text, "This is another one!");
        assert_eq!(sentences[2].text, "And a question?");
    }

    #[test]
    fn test_incomplete_sentence_ignored() {
        let text = "This is a complete sentence. This is not";
        let sentences = extract_complete_sentences(text);

        assert_eq!(sentences.len(), 1);
        assert_eq!(sentences[0].text, "This is a complete sentence.");
    }

    #[test]
    fn test_short_sentences_ignored() {
        let text = "Hi. Hello there. This is a longer sentence that should be included.";
        let sentences = extract_complete_sentences(text);

        // "Hi." and "Hello there." have fewer than MIN_WORDS_FOR_ANALYSIS words
        assert_eq!(sentences.len(), 1);
        assert!(sentences[0].text.contains("longer sentence"));
    }

    #[test]
    fn test_ends_with_complete_sentence() {
        assert!(ends_with_complete_sentence(
            "This is a complete sentence with enough words."
        ));
        assert!(!ends_with_complete_sentence("This is incomplete"));
        assert!(!ends_with_complete_sentence("Hi.")); // Too short
    }

    #[test]
    fn test_paragraph_breaks() {
        let text = "This is the first paragraph with enough words\nThis is the second paragraph with enough words.";
        let sentences = extract_complete_sentences(text);

        assert_eq!(sentences.len(), 2);
    }

    #[test]
    fn test_unicode_sentence_endings() {
        let text = "これは十分な単語数の文です。これは別の文です！これは質問です？";
        let sentences = extract_complete_sentences(text);

        assert_eq!(sentences.len(), 3);
        assert!(ends_with_complete_sentence(text));
    }

    #[test]
    fn test_ellipsis_sentence_end() {
        let text = "This trail ends with an ellipsis… Here comes another sentence.";
        let sentences = extract_complete_sentences(text);

        assert_eq!(sentences.len(), 2);
        assert!(ends_with_complete_sentence(text));
    }

    #[test]
    fn test_unicode_handling() {
        let text =
            "Dies ist ein deutscher Satz mit genug Wörtern. C'est une phrase française complète!";
        let sentences = extract_complete_sentences(text);

        assert_eq!(sentences.len(), 2);
    }
}
