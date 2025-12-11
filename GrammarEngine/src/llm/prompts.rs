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
        "You are a proofreading assistant that suggests STYLE improvements (not grammar or spelling). \
         You help users improve readability, flow, and clarity of their existing text. \
         {vocab_list}"
    );

    // O - Objective
    let objective = "Your task: Find phrases in the text that could be reworded for better style. \
         For each suggestion, identify an EXACT phrase from the input and propose a clearer alternative. \
         Focus on: awkward phrasing, missing punctuation (especially commas), word choice, and sentence flow. \
         Do NOT: complete partial words, fix typos, or suggest adding content that isn't there.";

    // S - Style instruction per template
    let style_instruction = get_style_instruction(style);

    // T - Tone & Output format
    let output_format = r#"
Output JSON format (respond with ONLY this JSON, no other text):
{
  "suggestions": [
    {
      "original": "exact phrase from input",
      "suggested": "improved version",
      "explanation": "brief reason"
    }
  ]
}

Example - for input "I think that we should probably go":
GOOD: {"suggestions": [{"original": "I think that we", "suggested": "I think we", "explanation": "Remove unnecessary 'that'"}]}
BAD: {"suggestions": [{"original": "I think", "suggested": "I believe that", "explanation": "..."}]} - adds words not improving style

CRITICAL Rules:
- "original" MUST be a VERBATIM substring from the input (copy-paste exact match)
- NEVER invent text, expand words, or complete partial words
- NEVER add content that wasn't in the original
- Do NOT change technical terms, proper nouns, or acronyms
- Preserve the original meaning exactly
- Only suggest changes that genuinely improve clarity, flow, or punctuation
- If no improvements are needed, return {"suggestions": []}
- Keep explanations under 15 words"#;

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
        .map(|p| {
            format!(
                "- '{}' → '{}' (rejected: {})",
                p.original,
                p.suggested,
                p.category.as_str()
            )
        })
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
    // Log only metadata to avoid leaking user text
    tracing::info!(
        "parse_llm_response: Received response_len={}",
        response.len()
    );

    // Try to extract JSON from the response (LLM might include extra text)
    let json_str = extract_json(response)?;

    // Record JSON length to aid debugging without exposing content
    tracing::debug!("parse_llm_response: Extracted JSON len={}", json_str.len());

    // First try parsing as the expected format {"suggestions": [...]}
    if let Ok(parsed) = serde_json::from_str::<LlmResponse>(&json_str) {
        tracing::debug!(
            "parse_llm_response: Parsed {} suggestions",
            parsed.suggestions.len()
        );
        return Ok(parsed.suggestions);
    }

    // If that fails, try parsing as a direct array [{...}, ...]
    // Some models output the array directly instead of wrapping in {"suggestions": ...}
    if let Ok(suggestions) = serde_json::from_str::<Vec<ParsedSuggestion>>(&json_str) {
        tracing::debug!(
            "parse_llm_response: Parsed {} suggestions from direct array",
            suggestions.len()
        );
        return Ok(suggestions);
    }

    // Try one more time: maybe it's a single suggestion object
    if let Ok(single) = serde_json::from_str::<ParsedSuggestion>(&json_str) {
        tracing::debug!("parse_llm_response: Parsed single suggestion");
        return Ok(vec![single]);
    }

    // Nothing worked - report the error with details
    let err = serde_json::from_str::<LlmResponse>(&json_str).unwrap_err();
    tracing::warn!("parse_llm_response: Failed to parse JSON: {}", err);
    Err(ParseError::InvalidJson(err.to_string()))
}

/// Normalize control character representations in model output
/// Some models or logging layers encode control characters as literal strings like <0x0A>
fn normalize_control_chars(input: &str) -> String {
    input
        .replace("<0x0A>", "\n")
        .replace("<0x0D>", "\r")
        .replace("<0x09>", "\t")
}

/// Extract JSON from potentially mixed response
fn extract_json(response: &str) -> Result<String, ParseError> {
    // First normalize any literal control character representations
    let normalized = normalize_control_chars(response);
    let response = normalized.as_str();

    // First, try to extract from markdown code blocks
    // e.g., ```json\n{...}\n``` or ```\n{...}\n```
    if let Some(json_from_block) = extract_from_code_block(response) {
        return Ok(json_from_block);
    }

    // Try to find JSON object { ... }
    if let Some(json_obj) = extract_json_object(response) {
        return Ok(json_obj);
    }

    // Try to find JSON array [ ... ]
    if let Some(json_arr) = extract_json_array(response) {
        return Ok(json_arr);
    }

    Err(ParseError::NoJsonFound)
}

/// Extract JSON from markdown code block
fn extract_from_code_block(response: &str) -> Option<String> {
    // Look for ```json ... ``` or ``` ... ```
    let patterns = ["```json", "```JSON", "```"];

    for pattern in patterns {
        if let Some(start_idx) = response.find(pattern) {
            let content_start = start_idx + pattern.len();
            // Find the closing ```
            if let Some(end_idx) = response[content_start..].find("```") {
                let content = response[content_start..content_start + end_idx].trim();
                if content.starts_with('{') || content.starts_with('[') {
                    return Some(content.to_string());
                }
            }
        }
    }
    None
}

/// Extract the FIRST complete JSON object from the response
/// Uses brace counting to find the matching closing brace
fn extract_json_object(response: &str) -> Option<String> {
    let start = response.find('{')?;
    let bytes = response[start..].as_bytes();

    let mut depth = 0;
    let mut in_string = false;
    let mut escape_next = false;

    for (i, &byte) in bytes.iter().enumerate() {
        if escape_next {
            escape_next = false;
            continue;
        }

        match byte {
            b'\\' if in_string => {
                escape_next = true;
            }
            b'"' => {
                in_string = !in_string;
            }
            b'{' if !in_string => {
                depth += 1;
            }
            b'}' if !in_string => {
                depth -= 1;
                if depth == 0 {
                    // Found the matching closing brace
                    return Some(response[start..=start + i].to_string());
                }
            }
            _ => {}
        }
    }

    None
}

/// Extract the FIRST complete JSON array from the response
/// Uses bracket counting to find the matching closing bracket
fn extract_json_array(response: &str) -> Option<String> {
    let start = response.find('[')?;
    let bytes = response[start..].as_bytes();

    let mut depth = 0;
    let mut in_string = false;
    let mut escape_next = false;

    for (i, &byte) in bytes.iter().enumerate() {
        if escape_next {
            escape_next = false;
            continue;
        }

        match byte {
            b'\\' if in_string => {
                escape_next = true;
            }
            b'"' => {
                in_string = !in_string;
            }
            b'[' if !in_string => {
                depth += 1;
            }
            b']' if !in_string => {
                depth -= 1;
                if depth == 0 {
                    // Found the matching closing bracket
                    return Some(response[start..=start + i].to_string());
                }
            }
            _ => {}
        }
    }

    None
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
    fn test_parse_llm_response_direct_array() {
        // Some models output the array directly instead of wrapping in {"suggestions": ...}
        let response = r#"[{"original": "very good", "suggested": "excellent", "explanation": "More concise"}]"#;
        let result = parse_llm_response(response);

        assert!(result.is_ok());
        let suggestions = result.unwrap();
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].original, "very good");
    }

    #[test]
    fn test_parse_llm_response_markdown_code_block() {
        let response = r#"Here's my analysis:
```json
{"suggestions": [{"original": "test", "suggested": "example", "explanation": "Better"}]}
```
Let me know if you need more help!"#;

        let result = parse_llm_response(response);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().len(), 1);
    }

    #[test]
    fn test_parse_llm_response_single_suggestion() {
        let response =
            r#"{"original": "very", "suggested": "quite", "explanation": "Less casual"}"#;
        let result = parse_llm_response(response);

        assert!(result.is_ok());
        let suggestions = result.unwrap();
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].original, "very");
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

    #[test]
    fn test_parse_llm_response_with_continued_output() {
        // Simulate Phi-3 style output where the model continues after valid JSON
        // This was causing "key must be a string at line 1 column 2" errors
        let response = r#"{"suggestions": [{"original": "test", "suggested": "example", "explanation": "Better"}]}<|end|><|assistant|> {"suggestions": [{"original": "another"#;
        let result = parse_llm_response(response);

        assert!(result.is_ok(), "Should extract first complete JSON object");
        let suggestions = result.unwrap();
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].original, "test");
        assert_eq!(suggestions[0].suggested, "example");
    }

    #[test]
    fn test_extract_json_object_stops_at_first_complete() {
        // Should extract only the first complete JSON object
        let response = r#"{"a": 1}<|end|>{"b": 2}"#;
        let result = extract_json_object(response);

        assert!(result.is_some());
        assert_eq!(result.unwrap(), r#"{"a": 1}"#);
    }

    #[test]
    fn test_extract_json_object_with_nested_braces() {
        // Should correctly handle nested braces
        let response = r#"{"outer": {"inner": "value"}}<extra stuff>"#;
        let result = extract_json_object(response);

        assert!(result.is_some());
        assert_eq!(result.unwrap(), r#"{"outer": {"inner": "value"}}"#);
    }

    #[test]
    fn test_extract_json_object_with_braces_in_strings() {
        // Should ignore braces inside strings
        let response = r#"{"text": "use {curly} braces"}<more>"#;
        let result = extract_json_object(response);

        assert!(result.is_some());
        assert_eq!(result.unwrap(), r#"{"text": "use {curly} braces"}"#);
    }

    #[test]
    fn test_parse_llm_response_multiline_json() {
        // Test with actual multi-line JSON like the model returns
        let response = r#"{
  "suggestions": [
    {
      "original": "very good",
      "suggested": "excellent",
      "explanation": "More concise"
    }
  ]
}<|end|><|assistant|>"#;
        let result = parse_llm_response(response);

        assert!(result.is_ok(), "Should parse multi-line JSON");
        let suggestions = result.unwrap();
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].original, "very good");
    }

    #[test]
    fn test_parse_llm_response_multiline_with_continuation() {
        // Simulate exact model output with pretty-printed JSON and continuation
        let response = r#"{
  "suggestions": [
    {
      "original": "This is a test message",
      "suggested": "This is a test",
      "explanation": "Improved clarity"
    }
  ]
}<|end|><|assistant|> {
  "suggestions": [
    {
      "original": "another"#;
        let result = parse_llm_response(response);

        assert!(
            result.is_ok(),
            "Should extract first complete JSON from multi-line response"
        );
        let suggestions = result.unwrap();
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].original, "This is a test message");
    }

    #[test]
    fn test_parse_llm_response_with_literal_0x0a() {
        // Test with literal <0x0A> strings (as might be encoded by logging systems)
        // This exact format was observed in production logs
        let response = r#"{<0x0A>  "suggestions": [<0x0A>    {<0x0A>      "original": "very good",<0x0A>      "suggested": "excellent",<0x0A>      "explanation": "More concise"<0x0A>    }<0x0A>  ]<0x0A>}"#;
        let result = parse_llm_response(response);

        assert!(
            result.is_ok(),
            "Should handle literal <0x0A> strings: {:?}",
            result
        );
        let suggestions = result.unwrap();
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].original, "very good");
        assert_eq!(suggestions[0].suggested, "excellent");
    }

    #[test]
    fn test_normalize_control_chars() {
        let input = "Hello<0x0A>World<0x09>Tab<0x0D>Return";
        let normalized = normalize_control_chars(input);
        assert_eq!(normalized, "Hello\nWorld\tTab\rReturn");
    }
}
