// Wordlist Dictionary Loader
//
// Extensible system for loading predefined wordlists for Harper grammar engine
// Supports internet abbreviations, Gen Z slang, and future wordlists (IT, medical, legal, etc.)

use harper_core::CharString;
use harper_core::DictWordMetadata;

/// Wordlist categories available in the system
/// Add new variants here when introducing new wordlists
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WordlistCategory {
    /// Internet abbreviations (BTW, FYI, LOL, ASAP, etc.)
    InternetAbbreviations,
    /// Gen Z slang (ghosting, sus, slay, etc.)
    GenZSlang,
    /// IT and technical terminology (API, JSON, localhost, kubernetes, etc.)
    ITTerminology,
    // Future wordlists can be added here:
    // /// Medical terminology (diagnosis, medication, etc.)
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
            WordlistCategory::ITTerminology => WordlistInfo {
                category: *self,
                name: "IT Terminology",
                description: "Technical IT terms from NIST, IANA, Linux, CNCF, and more",
                word_count_estimate: 10000,
            },
        }
    }

    /// Load words for this wordlist category
    /// Returns a Vec of (CharString, DictWordMetadata) tuples
    /// All words are stored in lowercase - Harper's spell checker will match any case automatically
    pub fn load_words(&self) -> Vec<(CharString, DictWordMetadata)> {
        match self {
            WordlistCategory::InternetAbbreviations => {
                const ABBREVIATIONS: &str = include_str!("../wordlists/internet_abbreviations.txt");
                load_words_lowercase_only(ABBREVIATIONS)
            }
            WordlistCategory::GenZSlang => {
                const GENZ_SLANG: &str = include_str!("../wordlists/genz_slang.txt");
                load_words_lowercase_only(GENZ_SLANG)
            }
            WordlistCategory::ITTerminology => {
                const IT_TERMS: &str = include_str!("../wordlists/it_terminology.txt");
                load_words_lowercase_only(IT_TERMS)
            }
        }
    }
}

/// Parse text file and convert all words to lowercase
/// Harper's spell checker automatically accepts any case when words are stored in lowercase
/// This works because SpellCheck checks both exact match and to_lower() match
/// Returns a Vec of (CharString, DictWordMetadata) tuples
fn load_words_lowercase_only(text: &str) -> Vec<(CharString, DictWordMetadata)> {
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
            let metadata = DictWordMetadata::default();

            Some((lowercase, metadata))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_load_internet_abbreviations() {
        let abbrevs = WordlistCategory::InternetAbbreviations.load_words();

        // Should have loaded many abbreviations (lowercase only now)
        assert!(abbrevs.len() > 3000, "Should have 3000+ abbreviations");

        // Check for some common ones (all lowercase)
        let words: Vec<String> = abbrevs
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        assert!(words.contains(&"btw".to_string()), "Should contain 'btw'");
        assert!(words.contains(&"fyi".to_string()), "Should contain 'fyi'");
        assert!(words.contains(&"lol".to_string()), "Should contain 'lol'");
        assert!(words.contains(&"asap".to_string()), "Should contain 'asap'");
        assert!(words.contains(&"imho".to_string()), "Should contain 'imho'");
        assert!(
            words.contains(&"afaict".to_string()),
            "Should contain 'afaict'"
        );
    }

    #[test]
    fn test_load_genz_slang() {
        let slang = WordlistCategory::GenZSlang.load_words();

        // Should have loaded slang words
        assert!(slang.len() > 100, "Should have 100+ slang terms");

        // Check for some modern slang
        let words: Vec<String> = slang
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Note: these are lowercase in the file
        assert!(
            words.iter().any(|w| w.to_lowercase() == "ghosting"),
            "Should contain 'ghosting'"
        );
        assert!(
            words.iter().any(|w| w.to_lowercase() == "sus"),
            "Should contain 'sus'"
        );
        assert!(
            words.iter().any(|w| w.to_lowercase() == "slay"),
            "Should contain 'slay'"
        );
    }

    #[test]
    fn test_comments_and_empty_lines_ignored() {
        let test_text = "# This is a comment\nBTW\n\n  \nFYI\n# Another comment\nLOL";
        let words = load_words_lowercase_only(test_text);

        assert_eq!(
            words.len(),
            3,
            "Should only load 3 words, ignoring comments and empty lines"
        );

        let word_strings: Vec<String> = words
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        assert_eq!(word_strings, vec!["btw", "fyi", "lol"]);
    }

    #[test]
    fn test_lowercase_only_generation() {
        // Test that only lowercase variants are generated
        let test_text = "BTW\nFYI\nLOL";
        let words = load_words_lowercase_only(test_text);

        // Should generate only 3 words (one per line, all lowercase)
        assert_eq!(words.len(), 3, "Should generate 3 lowercase words");

        let word_strings: Vec<String> = words
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Check that we have only lowercase variants
        assert!(
            word_strings.contains(&"btw".to_string()),
            "Should contain lowercase 'btw'"
        );
        assert!(
            word_strings.contains(&"fyi".to_string()),
            "Should contain lowercase 'fyi'"
        );
        assert!(
            word_strings.contains(&"lol".to_string()),
            "Should contain lowercase 'lol'"
        );

        // Should NOT contain uppercase or title case
        assert!(
            !word_strings.contains(&"BTW".to_string()),
            "Should NOT contain uppercase 'BTW'"
        );
        assert!(
            !word_strings.contains(&"Btw".to_string()),
            "Should NOT contain title case 'Btw'"
        );
    }

    #[test]
    fn test_real_abbreviations_loaded() {
        // Test that real abbreviations are loaded (lowercase only)
        let abbrevs = WordlistCategory::InternetAbbreviations.load_words();

        // Should have 3000+ abbreviations (no case variants)
        assert!(abbrevs.len() > 3000, "Should have 3000+ abbreviations");

        let abbrev_strings: Vec<String> = abbrevs
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Test specific critical abbreviations (all lowercase)
        assert!(
            abbrev_strings.contains(&"btw".to_string()),
            "Should contain 'btw'"
        );
        assert!(
            abbrev_strings.contains(&"fyi".to_string()),
            "Should contain 'fyi'"
        );
        assert!(
            abbrev_strings.contains(&"lol".to_string()),
            "Should contain 'lol'"
        );
        assert!(
            abbrev_strings.contains(&"afaict".to_string()),
            "Should contain 'afaict'"
        );
        assert!(
            abbrev_strings.contains(&"imho".to_string()),
            "Should contain 'imho'"
        );

        // Should NOT contain uppercase variants
        assert!(
            !abbrev_strings.contains(&"BTW".to_string()),
            "Should NOT contain 'BTW'"
        );
        assert!(
            !abbrev_strings.contains(&"AFAICT".to_string()),
            "Should NOT contain 'AFAICT'"
        );

        println!(
            "Loaded {} total abbreviations (lowercase only)",
            abbrevs.len()
        );
    }

    #[test]
    fn test_load_it_terminology() {
        let it_terms = WordlistCategory::ITTerminology.load_words();

        // Should have 10000+ terms
        assert!(
            it_terms.len() > 10000,
            "Should have 10000+ IT terms, got {}",
            it_terms.len()
        );

        // Check for some common IT terms
        let term_strings: Vec<String> = it_terms
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Cloud/DevOps terms
        assert!(
            term_strings.contains(&"kubernetes".to_string()),
            "Should contain 'kubernetes'"
        );
        assert!(
            term_strings.contains(&"docker".to_string()),
            "Should contain 'docker'"
        );
        assert!(
            term_strings.contains(&"nginx".to_string()),
            "Should contain 'nginx'"
        );

        // Programming terms
        assert!(
            term_strings.contains(&"javascript".to_string()),
            "Should contain 'javascript'"
        );
        assert!(
            term_strings.contains(&"python".to_string()),
            "Should contain 'python'"
        );
        assert!(
            term_strings.contains(&"api".to_string()),
            "Should contain 'api'"
        );
        assert!(
            term_strings.contains(&"json".to_string()),
            "Should contain 'json'"
        );

        // Networking terms
        assert!(
            term_strings.contains(&"http".to_string()),
            "Should contain 'http'"
        );
        assert!(
            term_strings.contains(&"tcp".to_string()),
            "Should contain 'tcp'"
        );
        assert!(
            term_strings.contains(&"ssh".to_string()),
            "Should contain 'ssh'"
        );

        // Security terms
        assert!(
            term_strings.contains(&"encryption".to_string()),
            "Should contain 'encryption'"
        );
        assert!(
            term_strings.contains(&"firewall".to_string()),
            "Should contain 'firewall'"
        );

        // Linux terms
        assert!(
            term_strings.contains(&"chmod".to_string()),
            "Should contain 'chmod'"
        );

        println!("Loaded {} total IT terms", it_terms.len());
    }

    #[test]
    fn test_it_terminology_hyphenated_compounds() {
        let it_terms = WordlistCategory::ITTerminology.load_words();
        let term_strings: Vec<String> = it_terms
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Test that important hyphenated compounds are preserved
        assert!(
            term_strings.contains(&"real-time".to_string()),
            "Should contain 'real-time'"
        );
        assert!(
            term_strings.contains(&"end-to-end".to_string()),
            "Should contain 'end-to-end'"
        );
        assert!(
            term_strings.contains(&"peer-to-peer".to_string()),
            "Should contain 'peer-to-peer'"
        );
        assert!(
            term_strings.contains(&"serverless".to_string()),
            "Should contain 'serverless'"
        );
    }

    #[test]
    fn test_it_terminology_vendor_and_technology_names() {
        let it_terms = WordlistCategory::ITTerminology.load_words();
        let term_strings: Vec<String> = it_terms
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Technology names should be included (both individual and compound forms)
        assert!(
            term_strings.contains(&"apache".to_string()),
            "Should contain 'apache'"
        );
        assert!(
            term_strings.contains(&"kafka".to_string()),
            "Should contain 'kafka'"
        );
        // Compound forms may also be included for common technology stacks
        assert!(
            term_strings.contains(&"apache-kafka".to_string()),
            "Should contain 'apache-kafka'"
        );
    }

    #[test]
    fn test_wordlist_category_info() {
        // Test metadata for all categories
        let internet_info = WordlistCategory::InternetAbbreviations.info();
        assert_eq!(internet_info.name, "Internet Abbreviations");
        assert!(internet_info.word_count_estimate > 3000);

        let genz_info = WordlistCategory::GenZSlang.info();
        assert_eq!(genz_info.name, "Gen Z Slang");
        assert!(genz_info.word_count_estimate > 200);

        let it_info = WordlistCategory::ITTerminology.info();
        assert_eq!(it_info.name, "IT Terminology");
        assert!(it_info.word_count_estimate > 9000);
    }

    #[test]
    fn test_it_terminology_source_variety() {
        let it_terms = WordlistCategory::ITTerminology.load_words();
        let term_strings: Vec<String> = it_terms
            .iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect();

        // Terms from different sources to verify comprehensive coverage

        // NIST cybersecurity terms
        assert!(
            term_strings.contains(&"authentication".to_string()),
            "Should contain NIST term 'authentication'"
        );

        // IANA protocols
        assert!(
            term_strings.contains(&"ssh".to_string()),
            "Should contain IANA protocol 'ssh'"
        );

        // Linux syscalls
        assert!(
            term_strings.contains(&"open".to_string()),
            "Should contain Linux syscall 'open'"
        );

        // Programming languages from GitHub Linguist
        assert!(
            term_strings.contains(&"rust".to_string()),
            "Should contain programming language 'rust'"
        );

        // CNCF technologies
        assert!(
            term_strings.contains(&"prometheus".to_string()),
            "Should contain CNCF tech 'prometheus'"
        );
    }
}
