// LLM Prompts - CO-STAR framework implementation for style suggestions
//
// Based on research from prompt engineering best practices:
// - CO-STAR framework (Context, Objective, Style, Tone, Audience, Response)
// - Custom vocabulary integration to prevent false positives
// - Rejection pattern learning for personalized suggestions

use crate::llm_types::{RejectionPattern, StyleTemplate};

/// Build a style analysis prompt using the CO-STAR framework
///
/// # Arguments
/// * `text` - The text to analyze
/// * `style` - The target style template
/// * `custom_vocabulary` - User's custom word list (from Harper dictionary)
/// * `learned_terms` - Terms learned from user feedback
/// * `rejection_patterns` - Recent rejections to avoid similar suggestions
pub fn build_style_prompt(
    text: &str,
    style: StyleTemplate,
    custom_vocabulary: &[String],
    learned_terms: &[String],
    rejection_patterns: &[RejectionPattern],
) -> String {
    // C - Context
    let vocab_list = if custom_vocabulary.is_empty() && learned_terms.is_empty() {
        String::new()
    } else {
        let all_terms: Vec<&str> = custom_vocabulary
            .iter()
            .chain(learned_terms.iter())
            .map(String::as_str)
            .take(100) // Limit to avoid token overflow
            .collect();
        format!(
            "The user has a custom vocabulary that should NEVER be flagged as errors: [{}].",
            all_terms.join(", ")
        )
    };

    let context = format!(
        "You are a writing style assistant integrated into a text editor. \
         Your task is to suggest improvements while preserving the author's intent. \
         {vocab_list}"
    );

    // O - Objective
    let objective = "Analyze the text and suggest style improvements. \
         Return ONLY a valid JSON response with suggested rewrites.";

    // S - Style instruction per template
    let style_instruction = get_style_instruction(style);

    // T - Tone & Output format
    let output_format = r#"
Output JSON format (respond with ONLY this JSON, no other text):
{
  "suggestions": [
    {
      "original": "the exact text to replace",
      "suggested": "the improved version",
      "explanation": "brief reason for the change"
    }
  ]
}

Rules:
- Do NOT change technical terms, proper nouns, or acronyms
- Do NOT suggest changes to words in the user's custom vocabulary
- Preserve the original meaning exactly
- Only suggest changes that genuinely improve clarity or style
- If no improvements are needed, return {"suggestions": []}
- Keep explanations under 20 words"#;

    // Include rejection patterns to avoid similar suggestions
    let rejection_context = build_rejection_context(rejection_patterns, style);

    format!(
        "{context}\n\n{objective}\n\nStyle: {style_instruction}\n{output_format}{rejection_context}\n\nText to analyze:\n{text}"
    )
}

/// Get the style-specific instruction
fn get_style_instruction(style: StyleTemplate) -> &'static str {
    match style {
        StyleTemplate::Formal => {
            "Use formal English: complete sentences, no contractions, \
             precise vocabulary, professional tone. Avoid colloquialisms."
        }
        StyleTemplate::Informal => {
            "Use casual, conversational English: natural language, \
             contractions are fine, be friendly but clear. Keep it approachable."
        }
        StyleTemplate::Business => {
            "Use business English: concise, action-oriented, \
             professional but approachable, focus on clarity and impact. \
             Use active voice."
        }
        StyleTemplate::Concise => {
            "Eliminate unnecessary words. Be brief and direct. \
             Remove filler phrases ('very', 'really', 'just'), redundancies, \
             and verbose constructions. Every word should add value."
        }
        StyleTemplate::Default => {
            "Improve clarity and readability while preserving the author's voice. \
             Fix awkward phrasing and improve flow without changing the tone."
        }
    }
}

/// Build context from rejection patterns
fn build_rejection_context(patterns: &[RejectionPattern], current_style: StyleTemplate) -> String {
    if patterns.is_empty() {
        return String::new();
    }

    // Filter to patterns matching current style and take most recent
    let relevant: Vec<&RejectionPattern> = patterns
        .iter()
        .filter(|p| p.style == current_style)
        .take(5)
        .collect();

    if relevant.is_empty() {
        return String::new();
    }

    let examples: Vec<String> = relevant
        .iter()
        .map(|p| format!("- '{}' → '{}' (rejected: {})", p.original, p.suggested, p.category.as_str()))
        .collect();

    format!(
        "\n\nThe user has previously REJECTED these types of changes (avoid similar):\n{}",
        examples.join("\n")
    )
}

/// Parse the LLM response JSON into suggestions
///
/// Returns a vector of (original, suggested, explanation) tuples
pub fn parse_llm_response(response: &str) -> Result<Vec<ParsedSuggestion>, ParseError> {
    // Try to extract JSON from the response (LLM might include extra text)
    let json_str = extract_json(response)?;

    // Parse the JSON
    let parsed: LlmResponse = serde_json::from_str(&json_str)
        .map_err(|e| ParseError::InvalidJson(e.to_string()))?;

    Ok(parsed.suggestions)
}

/// Extract JSON from potentially mixed response
fn extract_json(response: &str) -> Result<String, ParseError> {
    // Find the first { and last }
    let start = response.find('{').ok_or(ParseError::NoJsonFound)?;
    let end = response.rfind('}').ok_or(ParseError::NoJsonFound)?;

    if end <= start {
        return Err(ParseError::NoJsonFound);
    }

    Ok(response[start..=end].to_string())
}

/// Parsed LLM response structure
#[derive(Debug, serde::Deserialize)]
struct LlmResponse {
    suggestions: Vec<ParsedSuggestion>,
}

/// A parsed suggestion from the LLM
#[derive(Debug, Clone, serde::Deserialize)]
pub struct ParsedSuggestion {
    pub original: String,
    pub suggested: String,
    pub explanation: String,
}

/// Error type for parsing LLM responses
#[derive(Debug, Clone)]
pub enum ParseError {
    NoJsonFound,
    InvalidJson(String),
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoJsonFound => write!(f, "No JSON found in response"),
            Self::InvalidJson(e) => write!(f, "Invalid JSON: {e}"),
        }
    }
}

impl std::error::Error for ParseError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_style_prompt_basic() {
        let prompt = build_style_prompt(
            "The meeting was very good.",
            StyleTemplate::Concise,
            &[],
            &[],
            &[],
        );

        assert!(prompt.contains("The meeting was very good."));
        assert!(prompt.contains("Concise") || prompt.contains("brief"));
        assert!(prompt.contains("JSON"));
    }

    #[test]
    fn test_build_style_prompt_with_vocabulary() {
        let vocab = vec!["kubernetes".to_string(), "GraphQL".to_string()];
        let prompt = build_style_prompt(
            "Deploy to kubernetes.",
            StyleTemplate::Business,
            &vocab,
            &[],
            &[],
        );

        assert!(prompt.contains("kubernetes"));
        assert!(prompt.contains("GraphQL"));
        assert!(prompt.contains("NEVER be flagged"));
    }

    #[test]
    fn test_parse_llm_response_valid() {
        let response = r#"{"suggestions": [{"original": "very good", "suggested": "excellent", "explanation": "More concise"}]}"#;
        let result = parse_llm_response(response);

        assert!(result.is_ok());
        let suggestions = result.unwrap();
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].original, "very good");
        assert_eq!(suggestions[0].suggested, "excellent");
    }

    #[test]
    fn test_parse_llm_response_with_extra_text() {
        let response = r#"Here's my analysis:
{"suggestions": [{"original": "test", "suggested": "example", "explanation": "Better word"}]}
Hope this helps!"#;

        let result = parse_llm_response(response);
        assert!(result.is_ok());
    }

    #[test]
    fn test_parse_llm_response_empty() {
        let response = r#"{"suggestions": []}"#;
        let result = parse_llm_response(response);

        assert!(result.is_ok());
        assert!(result.unwrap().is_empty());
    }

    #[test]
    fn test_parse_llm_response_invalid() {
        let response = "This is not JSON at all";
        let result = parse_llm_response(response);

        assert!(result.is_err());
    }

    #[test]
    fn test_style_instructions_different() {
        let formal = get_style_instruction(StyleTemplate::Formal);
        let informal = get_style_instruction(StyleTemplate::Informal);
        let concise = get_style_instruction(StyleTemplate::Concise);

        assert_ne!(formal, informal);
        assert_ne!(formal, concise);
        assert_ne!(informal, concise);
    }
}
