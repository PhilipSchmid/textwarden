// LLM Types - Core types for LLM style checking
//
// These types are always available (not feature-gated) for FFI compatibility.

use serde::{Deserialize, Serialize};

/// Style template for writing suggestions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StyleTemplate {
    Default,
    Formal,
    Informal,
    Business,
    Concise,
}

impl StyleTemplate {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "formal" => Self::Formal,
            "informal" | "casual" => Self::Informal,
            "business" => Self::Business,
            "concise" => Self::Concise,
            _ => Self::Default,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Default => "default",
            Self::Formal => "formal",
            Self::Informal => "informal",
            Self::Business => "business",
            Self::Concise => "concise",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Default => "Default",
            Self::Formal => "Formal",
            Self::Informal => "Casual",
            Self::Business => "Business",
            Self::Concise => "Concise",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Default => "Balanced style improvements",
            Self::Formal => "Professional tone, complete sentences",
            Self::Informal => "Friendly, conversational writing",
            Self::Business => "Clear, action-oriented communication",
            Self::Concise => "Brief and to the point, no filler",
        }
    }
}

/// A single style suggestion from the LLM
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StyleSuggestion {
    pub id: String,
    pub original_start: usize,
    pub original_end: usize,
    pub original_text: String,
    pub suggested_text: String,
    pub explanation: String,
    pub confidence: f32,
    pub style: StyleTemplate,
    #[serde(skip)]
    pub diff: Vec<DiffSegment>,
}

/// Result of style analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StyleAnalysisResult {
    pub suggestions: Vec<StyleSuggestion>,
    pub analysis_time_ms: u64,
    pub model_id: String,
    pub style: StyleTemplate,
}

impl Default for StyleAnalysisResult {
    fn default() -> Self {
        Self {
            suggestions: Vec::new(),
            analysis_time_ms: 0,
            model_id: String::new(),
            style: StyleTemplate::Default,
        }
    }
}

/// Model tier classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ModelTier {
    Balanced,    // Good balance of speed and quality (Qwen 2.5 1.5B)
    Accurate,    // Best quality, slower (Phi-3 Mini)
    Lightweight, // Fastest, lower quality (Gemma 2 2B, Llama 3.2 1B)
    Custom,      // User-provided model
}

/// Information about an available LLM model
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
    pub id: String,
    pub name: String,
    pub filename: String,
    pub download_url: String,
    pub size_bytes: u64,
    pub speed_rating: f32,    // 0-10 scale
    pub quality_rating: f32,  // 0-10 scale
    pub languages: Vec<String>,
    pub is_multilingual: bool,
    pub description: String,
    pub tier: ModelTier,
    pub is_downloaded: bool,
    pub is_default: bool,
}

/// Category for rejection feedback
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RejectionCategory {
    WrongMeaning,
    TooFormal,
    TooInformal,
    UnnecessaryChange,
    WrongTerm,
    Other,
}

impl RejectionCategory {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "wrong_meaning" | "wrongmeaning" => Self::WrongMeaning,
            "too_formal" | "tooformal" => Self::TooFormal,
            "too_informal" | "tooinformal" => Self::TooInformal,
            "unnecessary_change" | "unnecessarychange" => Self::UnnecessaryChange,
            "wrong_term" | "wrongterm" => Self::WrongTerm,
            _ => Self::Other,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::WrongMeaning => "wrong_meaning",
            Self::TooFormal => "too_formal",
            Self::TooInformal => "too_informal",
            Self::UnnecessaryChange => "unnecessary_change",
            Self::WrongTerm => "wrong_term",
            Self::Other => "other",
        }
    }
}

/// A recorded rejection pattern for learning
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RejectionPattern {
    pub id: String,
    pub original: String,
    pub suggested: String,
    pub style: StyleTemplate,
    pub category: RejectionCategory,
    pub rejected_at: u64, // Unix timestamp
}

/// A recorded acceptance pattern for learning
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcceptancePattern {
    pub id: String,
    pub original: String,
    pub accepted: String,
    pub style: StyleTemplate,
    pub accepted_at: u64, // Unix timestamp
}

/// A learned term from user feedback
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LearnedTerm {
    pub id: String,
    pub term: String,
    pub context: Option<String>,
    pub learned_at: u64, // Unix timestamp
    pub source: LearnedTermSource,
}

/// Source of a learned term
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LearnedTermSource {
    UserApproved,
    FromRejection,
    FromAcceptance,
    CustomDictionary,
}

/// User's writing context for personalized suggestions
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserWritingContext {
    pub learned_terms: Vec<LearnedTerm>,
    pub rejection_patterns: Vec<RejectionPattern>,
    pub acceptance_patterns: Vec<AcceptancePattern>,
    pub custom_vocabulary: Vec<String>,
    pub last_updated: u64, // Unix timestamp
}

/// Diff segment for showing changes
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DiffKind {
    Unchanged,
    Added,
    Removed,
}

#[derive(Debug, Clone)]
pub struct DiffSegment {
    pub text: String,
    pub kind: DiffKind,
}

/// Compute a word-level diff between original and suggested text
pub fn compute_diff(original: &str, suggested: &str) -> Vec<DiffSegment> {
    use similar::{ChangeTag, TextDiff};

    let diff = TextDiff::from_words(original, suggested);
    let mut segments = Vec::new();

    for change in diff.iter_all_changes() {
        let kind = match change.tag() {
            ChangeTag::Equal => DiffKind::Unchanged,
            ChangeTag::Insert => DiffKind::Added,
            ChangeTag::Delete => DiffKind::Removed,
        };

        // Try to merge consecutive segments of the same kind
        if let Some(last) = segments.last_mut() {
            let last_segment: &mut DiffSegment = last;
            if last_segment.kind == kind {
                last_segment.text.push_str(change.value());
                continue;
            }
        }

        segments.push(DiffSegment {
            text: change.value().to_string(),
            kind,
        });
    }

    segments
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_style_template_conversion() {
        assert_eq!(StyleTemplate::from_str("formal"), StyleTemplate::Formal);
        assert_eq!(StyleTemplate::from_str("FORMAL"), StyleTemplate::Formal);
        assert_eq!(StyleTemplate::from_str("casual"), StyleTemplate::Informal);
        assert_eq!(StyleTemplate::from_str("unknown"), StyleTemplate::Default);
    }

    #[test]
    fn test_compute_diff() {
        let original = "The meeting was very good";
        let suggested = "The meeting was productive";

        let diff = compute_diff(original, suggested);

        // Should have: unchanged "The meeting was ", removed "very good", added "productive"
        assert!(!diff.is_empty());

        let has_removed = diff.iter().any(|s| s.kind == DiffKind::Removed);
        let has_added = diff.iter().any(|s| s.kind == DiffKind::Added);

        assert!(has_removed, "Should have removed segments");
        assert!(has_added, "Should have added segments");
    }
}
