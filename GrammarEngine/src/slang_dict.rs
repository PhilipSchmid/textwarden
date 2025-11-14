// Wordlist Dictionary Loader
//
// Extensible system for loading predefined wordlists for Harper grammar engine
// Supports internet abbreviations, Gen Z slang, and future wordlists (IT, medical, legal, etc.)

use harper_core::CharString;
use harper_core::WordMetadata;

/// Wordlist categories available in the system
/// Add new variants here when introducing new wordlists
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WordlistCategory {
    /// Internet abbreviations (BTW, FYI, LOL, ASAP, etc.)
    InternetAbbreviations,
    /// Gen Z slang (ghosting, sus, slay, etc.)
    GenZSlang,
    // Future wordlists can be added here:
    // /// IT and technical terminology (API, JSON, localhost, etc.)
    // ITTerminology,
    // /// Medical terminology (diagnosis,症状, medication, etc.)
    // MedicalTerms,
    // /// Legal terminology (plaintiff, defendant, jurisdiction, etc.)
    // LegalTerms,
}

/// Metadata about a wordlist
pub struct WordlistInfo {
    pub category: WordlistCategory,
    pub name: &'static str,
    pub description: &'static str,
    pub word_count_estimate: usize,
}

impl WordlistCategory {
    /// Get metadata about this wordlist category
    pub fn info(&self) -> WordlistInfo {
        match self {
            WordlistCategory::InternetAbbreviations => WordlistInfo {
                category: *self,
                name: "Internet Abbreviations",
                description: "Common internet abbreviations and initialisms",
                word_count_estimate: 3200,
            },
            WordlistCategory::GenZSlang => WordlistInfo {
                category: *self,
                name: "Gen Z Slang",
                description: "Modern slang and informal language",
                word_count_estimate: 270,
            },
        }
    }

    /// Load words for this wordlist category
    /// Returns a Vec of (CharString, WordMetadata) tuples
    /// All words are stored in lowercase - Harper's spell checker will match any case automatically
    pub fn load_words(&self) -> Vec<(CharString, WordMetadata)> {
        match self {
            WordlistCategory::InternetAbbreviations => {
                const ABBREVIATIONS: &str = include_str!("../internet_abbreviations.txt");
                load_words_lowercase_only(ABBREVIATIONS)
            }
            WordlistCategory::GenZSlang => {
                const GENZ_SLANG: &str = include_str!("../genz_slang.txt");
                load_words_lowercase_only(GENZ_SLANG)
            }
            // Future wordlists:
            // WordlistCategory::ITTerminology => {
            //     const IT_TERMS: &str = include_str!("../it_terminology.txt");
            //     load_words_lowercase_only(IT_TERMS)
            // }
        }
    }
}

/// Load internet abbreviations from embedded file
/// Returns a Vec of (CharString, WordMetadata) tuples
/// Stores words in lowercase - Harper's spell checker will match any case automatically
///
/// DEPRECATED: Use WordlistCategory::InternetAbbreviations.load_words() instead
/// This function is kept for backward compatibility
pub fn load_internet_abbreviations() -> Vec<(CharString, WordMetadata)> {
    WordlistCategory::InternetAbbreviations.load_words()
}

/// Load Gen Z slang words from embedded file
/// Returns a Vec of (CharString, WordMetadata) tuples
/// Stores words in lowercase - Harper's spell checker will match any case automatically
///
/// DEPRECATED: Use WordlistCategory::GenZSlang.load_words() instead
/// This function is kept for backward compatibility
pub fn load_genz_slang() -> Vec<(CharString, WordMetadata)> {
    WordlistCategory::GenZSlang.load_words()
}

/// Parse text file with one word per line (ignoring comments and empty lines)
/// Returns a Vec of (CharString, WordMetadata) tuples
fn load_words_from_text(text: &str) -> Vec<(CharString, WordMetadata)> {
    text.lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            // Skip empty lines and comments
            if trimmed.is_empty() || trimmed.starts_with('#') {
                return None;
            }

            // Convert to CharString (Vec<char>)
            let char_string: CharString = trimmed.chars().collect();

            // Create default metadata for the word
            // This marks it as a valid word with no special grammatical properties
            let metadata = WordMetadata::default();

            Some((char_string, metadata))
        })
        .collect()
}

/// Parse text file and convert all words to lowercase
/// Harper's spell checker automatically accepts any case when words are stored in lowercase
/// This works because SpellCheck checks both exact match and to_lower() match
/// Returns a Vec of (CharString, WordMetadata) tuples
fn load_words_lowercase_only(text: &str) -> Vec<(CharString, WordMetadata)> {
    text.lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            // Skip empty lines and comments
            if trimmed.is_empty() || trimmed.starts_with('#') {
                return None;
            }

            // Convert to lowercase CharString (Vec<char>)
            let lowercase: CharString = trimmed.to_lowercase().chars().collect();

            // Create default metadata for the word
            let metadata = WordMetadata::default();

            Some((lowercase, metadata))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_load_internet_abbreviations() {
        let abbrevs = load_internet_abbreviations();

        // Should have loaded many abbreviations (lowercase only now)
        assert!(abbrevs.len() > 3000, "Should have 3000+ abbreviations");

        // Check for some common ones (all lowercase)
        let words: Vec<String> = abbrevs.iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        assert!(words.contains(&"btw".to_string()), "Should contain 'btw'");
        assert!(words.contains(&"fyi".to_string()), "Should contain 'fyi'");
        assert!(words.contains(&"lol".to_string()), "Should contain 'lol'");
        assert!(words.contains(&"asap".to_string()), "Should contain 'asap'");
        assert!(words.contains(&"imho".to_string()), "Should contain 'imho'");
        assert!(words.contains(&"afaict".to_string()), "Should contain 'afaict'");
    }

    #[test]
    fn test_load_genz_slang() {
        let slang = load_genz_slang();

        // Should have loaded slang words
        assert!(slang.len() > 100, "Should have 100+ slang terms");

        // Check for some modern slang
        let words: Vec<String> = slang.iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Note: these are lowercase in the file
        assert!(words.iter().any(|w| w.to_lowercase() == "ghosting"), "Should contain 'ghosting'");
        assert!(words.iter().any(|w| w.to_lowercase() == "sus"), "Should contain 'sus'");
        assert!(words.iter().any(|w| w.to_lowercase() == "slay"), "Should contain 'slay'");
    }

    #[test]
    fn test_comments_and_empty_lines_ignored() {
        let test_text = "# This is a comment\nBTW\n\n  \nFYI\n# Another comment\nLOL";
        let words = load_words_from_text(test_text);

        assert_eq!(words.len(), 3, "Should only load 3 words, ignoring comments and empty lines");

        let word_strings: Vec<String> = words.iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        assert_eq!(word_strings, vec!["BTW", "FYI", "LOL"]);
    }

    #[test]
    fn test_lowercase_only_generation() {
        // Test that only lowercase variants are generated
        let test_text = "BTW\nFYI\nLOL";
        let words = load_words_lowercase_only(test_text);

        // Should generate only 3 words (one per line, all lowercase)
        assert_eq!(words.len(), 3, "Should generate 3 lowercase words");

        let word_strings: Vec<String> = words.iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Check that we have only lowercase variants
        assert!(word_strings.contains(&"btw".to_string()), "Should contain lowercase 'btw'");
        assert!(word_strings.contains(&"fyi".to_string()), "Should contain lowercase 'fyi'");
        assert!(word_strings.contains(&"lol".to_string()), "Should contain lowercase 'lol'");

        // Should NOT contain uppercase or title case
        assert!(!word_strings.contains(&"BTW".to_string()), "Should NOT contain uppercase 'BTW'");
        assert!(!word_strings.contains(&"Btw".to_string()), "Should NOT contain title case 'Btw'");
    }

    #[test]
    fn test_real_abbreviations_loaded() {
        // Test that real abbreviations are loaded (lowercase only)
        let abbrevs = load_internet_abbreviations();

        // Should have 3000+ abbreviations (no case variants)
        assert!(abbrevs.len() > 3000, "Should have 3000+ abbreviations");

        let abbrev_strings: Vec<String> = abbrevs.iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Test specific critical abbreviations (all lowercase)
        assert!(abbrev_strings.contains(&"btw".to_string()), "Should contain 'btw'");
        assert!(abbrev_strings.contains(&"fyi".to_string()), "Should contain 'fyi'");
        assert!(abbrev_strings.contains(&"lol".to_string()), "Should contain 'lol'");
        assert!(abbrev_strings.contains(&"afaict".to_string()), "Should contain 'afaict'");
        assert!(abbrev_strings.contains(&"imho".to_string()), "Should contain 'imho'");

        // Should NOT contain uppercase variants
        assert!(!abbrev_strings.contains(&"BTW".to_string()), "Should NOT contain 'BTW'");
        assert!(!abbrev_strings.contains(&"AFAICT".to_string()), "Should NOT contain 'AFAICT'");

        println!("Loaded {} total abbreviations (lowercase only)", abbrevs.len());
    }
}
