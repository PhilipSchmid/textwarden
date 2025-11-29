// Context Manager - User vocabulary and preference learning
//
// Manages the user's writing context including:
// - Learned terms from feedback
// - Rejection patterns to avoid
// - Acceptance patterns for reinforcement
// - Integration with Harper's custom dictionary

use std::path::PathBuf;
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::llm_types::{
    AcceptancePattern, LearnedTerm, LearnedTermSource, RejectionCategory,
    RejectionPattern, StyleTemplate, UserWritingContext,
};

/// Maximum number of learned terms to keep
const MAX_LEARNED_TERMS: usize = 5000;

/// Maximum number of rejection patterns to keep
const MAX_REJECTION_PATTERNS: usize = 50;

/// Maximum number of acceptance patterns to keep
const MAX_ACCEPTANCE_PATTERNS: usize = 100;

/// Manager for user writing context and preferences
pub struct ContextManager {
    context: UserWritingContext,
    context_path: PathBuf,
    dirty: bool,
}

impl ContextManager {
    /// Create a new context manager
    ///
    /// Loads existing context from disk if available.
    pub fn new(app_support_dir: &PathBuf) -> Self {
        let context_path = app_support_dir.join("user_context.json");
        let context = Self::load_context(&context_path).unwrap_or_default();

        Self {
            context,
            context_path,
            dirty: false,
        }
    }

    /// Load context from disk
    fn load_context(path: &PathBuf) -> Option<UserWritingContext> {
        let content = fs::read_to_string(path).ok()?;
        serde_json::from_str(&content).ok()
    }

    /// Save context to disk
    pub fn save(&mut self) -> Result<(), std::io::Error> {
        if !self.dirty {
            return Ok(());
        }

        // Ensure parent directory exists
        if let Some(parent) = self.context_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let json = serde_json::to_string_pretty(&self.context)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

        fs::write(&self.context_path, json)?;
        self.dirty = false;
        Ok(())
    }

    /// Get current timestamp
    fn now() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }

    /// Record an accepted suggestion
    pub fn record_acceptance(
        &mut self,
        original: &str,
        suggested: &str,
        style: StyleTemplate,
    ) {
        let pattern = AcceptancePattern {
            id: uuid::Uuid::new_v4().to_string(),
            original: original.to_string(),
            accepted: suggested.to_string(),
            style,
            accepted_at: Self::now(),
        };

        self.context.acceptance_patterns.push(pattern);

        // Prune old patterns
        while self.context.acceptance_patterns.len() > MAX_ACCEPTANCE_PATTERNS {
            self.context.acceptance_patterns.remove(0);
        }

        self.context.last_updated = Self::now();
        self.dirty = true;
    }

    /// Record a rejected suggestion
    pub fn record_rejection(
        &mut self,
        original: &str,
        suggested: &str,
        style: StyleTemplate,
        category: RejectionCategory,
    ) {
        let pattern = RejectionPattern {
            id: uuid::Uuid::new_v4().to_string(),
            original: original.to_string(),
            suggested: suggested.to_string(),
            style,
            category,
            rejected_at: Self::now(),
        };

        self.context.rejection_patterns.push(pattern);

        // If the rejection was due to a wrong term, learn those terms
        if category == RejectionCategory::WrongTerm {
            self.learn_terms_from_text(original, LearnedTermSource::FromRejection);
        }

        // Prune old patterns
        while self.context.rejection_patterns.len() > MAX_REJECTION_PATTERNS {
            self.context.rejection_patterns.remove(0);
        }

        self.context.last_updated = Self::now();
        self.dirty = true;
    }

    /// Learn terms from a piece of text
    fn learn_terms_from_text(&mut self, text: &str, source: LearnedTermSource) {
        for word in text.split_whitespace() {
            // Only learn words that are at least 3 characters
            let clean = word.trim_matches(|c: char| !c.is_alphanumeric());
            if clean.len() >= 3 && !self.has_learned_term(clean) {
                self.add_learned_term(clean, None, source);
            }
        }
    }

    /// Check if a term has already been learned
    fn has_learned_term(&self, term: &str) -> bool {
        let term_lower = term.to_lowercase();
        self.context.learned_terms.iter().any(|t| t.term.to_lowercase() == term_lower)
    }

    /// Add a learned term
    pub fn add_learned_term(
        &mut self,
        term: &str,
        context: Option<&str>,
        source: LearnedTermSource,
    ) {
        // Don't add duplicates
        if self.has_learned_term(term) {
            return;
        }

        let learned = LearnedTerm {
            id: uuid::Uuid::new_v4().to_string(),
            term: term.to_string(),
            context: context.map(String::from),
            learned_at: Self::now(),
            source,
        };

        self.context.learned_terms.push(learned);

        // Prune oldest terms if over limit
        while self.context.learned_terms.len() > MAX_LEARNED_TERMS {
            self.context.learned_terms.remove(0);
        }

        self.context.last_updated = Self::now();
        self.dirty = true;
    }

    /// Remove a learned term
    pub fn remove_learned_term(&mut self, term: &str) {
        let term_lower = term.to_lowercase();
        self.context.learned_terms.retain(|t| t.term.to_lowercase() != term_lower);
        self.context.last_updated = Self::now();
        self.dirty = true;
    }

    /// Sync custom vocabulary from Harper's custom dictionary
    pub fn sync_custom_vocabulary(&mut self, custom_dict: &[String]) {
        self.context.custom_vocabulary = custom_dict.to_vec();
        self.context.last_updated = Self::now();
        self.dirty = true;
    }

    /// Get all learned terms as strings
    pub fn get_learned_terms(&self) -> Vec<String> {
        self.context.learned_terms.iter().map(|t| t.term.clone()).collect()
    }

    /// Get the custom vocabulary
    pub fn get_custom_vocabulary(&self) -> &[String] {
        &self.context.custom_vocabulary
    }

    /// Get rejection patterns for a specific style
    pub fn get_rejection_patterns(&self, style: StyleTemplate) -> Vec<&RejectionPattern> {
        self.context
            .rejection_patterns
            .iter()
            .filter(|p| p.style == style)
            .collect()
    }

    /// Get all rejection patterns
    pub fn get_all_rejection_patterns(&self) -> &[RejectionPattern] {
        &self.context.rejection_patterns
    }

    /// Get statistics about the context
    pub fn get_stats(&self) -> ContextStats {
        ContextStats {
            learned_terms_count: self.context.learned_terms.len(),
            rejection_patterns_count: self.context.rejection_patterns.len(),
            acceptance_patterns_count: self.context.acceptance_patterns.len(),
            custom_vocabulary_count: self.context.custom_vocabulary.len(),
            last_updated: self.context.last_updated,
        }
    }

    /// Clear all learned data (for reset)
    pub fn clear(&mut self) {
        self.context = UserWritingContext::default();
        self.context.last_updated = Self::now();
        self.dirty = true;
    }

    /// Get the full context for prompt building
    pub fn get_context(&self) -> &UserWritingContext {
        &self.context
    }
}

/// Statistics about the user's context
#[derive(Debug, Clone)]
pub struct ContextStats {
    pub learned_terms_count: usize,
    pub rejection_patterns_count: usize,
    pub acceptance_patterns_count: usize,
    pub custom_vocabulary_count: usize,
    pub last_updated: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn create_test_manager() -> ContextManager {
        let temp_dir = env::temp_dir().join("textwarden_test");
        ContextManager::new(&temp_dir)
    }

    #[test]
    fn test_record_acceptance() {
        let mut manager = create_test_manager();

        manager.record_acceptance("very good", "excellent", StyleTemplate::Concise);

        let stats = manager.get_stats();
        assert_eq!(stats.acceptance_patterns_count, 1);
    }

    #[test]
    fn test_record_rejection() {
        let mut manager = create_test_manager();

        manager.record_rejection(
            "kubernetes cluster",
            "Kubernetes cluster",
            StyleTemplate::Formal,
            RejectionCategory::WrongTerm,
        );

        let stats = manager.get_stats();
        assert_eq!(stats.rejection_patterns_count, 1);

        // Should have learned "kubernetes" and "cluster"
        assert!(stats.learned_terms_count >= 1);
    }

    #[test]
    fn test_add_learned_term() {
        let mut manager = create_test_manager();

        manager.add_learned_term("GraphQL", Some("API technology"), LearnedTermSource::UserApproved);

        let terms = manager.get_learned_terms();
        assert!(terms.contains(&"GraphQL".to_string()));
    }

    #[test]
    fn test_no_duplicate_terms() {
        let mut manager = create_test_manager();

        manager.add_learned_term("kubernetes", None, LearnedTermSource::UserApproved);
        manager.add_learned_term("kubernetes", None, LearnedTermSource::UserApproved);
        manager.add_learned_term("KUBERNETES", None, LearnedTermSource::UserApproved);

        let stats = manager.get_stats();
        assert_eq!(stats.learned_terms_count, 1);
    }

    #[test]
    fn test_sync_custom_vocabulary() {
        let mut manager = create_test_manager();

        let vocab = vec!["customword".to_string(), "anotherword".to_string()];
        manager.sync_custom_vocabulary(&vocab);

        assert_eq!(manager.get_custom_vocabulary().len(), 2);
    }

    #[test]
    fn test_get_rejection_patterns_by_style() {
        let mut manager = create_test_manager();

        manager.record_rejection("test1", "test2", StyleTemplate::Formal, RejectionCategory::TooFormal);
        manager.record_rejection("test3", "test4", StyleTemplate::Concise, RejectionCategory::UnnecessaryChange);

        let formal_patterns = manager.get_rejection_patterns(StyleTemplate::Formal);
        assert_eq!(formal_patterns.len(), 1);

        let concise_patterns = manager.get_rejection_patterns(StyleTemplate::Concise);
        assert_eq!(concise_patterns.len(), 1);
    }
}
