// LLM Engine - Core inference engine for style suggestions
//
// Provides async LLM inference using mistral.rs (pure Rust).
// Handles model loading, text generation, and resource management.

use std::path::PathBuf;
use std::sync::Arc;

#[cfg(feature = "llm")]
use {
    mistralrs::{GgufModelBuilder, Model, RequestBuilder, TextMessageRole, TextMessages},
    tokio::sync::RwLock,
};

use crate::llm::config::{get_model_config, InferenceSettings};
use crate::llm::context::ContextManager;
use crate::llm::prompts::{build_style_prompt, parse_llm_response, ParsedSuggestion};
use crate::llm_types::{compute_diff, RejectionCategory, StyleSuggestion, StyleTemplate};

/// LLM inference engine using mistral.rs
#[cfg(feature = "llm")]
pub struct LlmEngine {
    model: Arc<RwLock<Option<LoadedModel>>>,
    settings: InferenceSettings,
    context_manager: Arc<RwLock<ContextManager>>,
    models_dir: PathBuf,
}

#[cfg(feature = "llm")]
struct LoadedModel {
    model: Model,
    model_id: String,
}

#[cfg(feature = "llm")]
impl LlmEngine {
    /// Create a new LLM engine
    pub fn new(app_support_dir: PathBuf) -> Result<Self, String> {
        let context_manager = ContextManager::new(&app_support_dir);
        let models_dir = app_support_dir.join("models");

        Ok(Self {
            model: Arc::new(RwLock::new(None)),
            settings: InferenceSettings::default(),
            context_manager: Arc::new(RwLock::new(context_manager)),
            models_dir,
        })
    }

    /// Check if a model is currently loaded
    pub async fn is_model_loaded(&self) -> bool {
        self.model.read().await.is_some()
    }

    /// Get the currently loaded model ID
    pub async fn loaded_model_id(&self) -> Option<String> {
        self.model.read().await.as_ref().map(|m| m.model_id.clone())
    }

    /// Load a model from disk
    pub async fn load_model(&self, model_path: PathBuf, model_id: &str) -> Result<(), String> {
        // Check if the same model is already loaded - skip redundant load
        {
            let guard = self.model.read().await;
            if let Some(ref loaded) = *guard {
                if loaded.model_id == model_id {
                    tracing::debug!("Model {} already loaded, skipping", model_id);
                    return Ok(());
                }
            }
        }

        // Explicitly unload any existing model first to free memory
        // This is critical to prevent memory leaks with mistral.rs
        {
            let mut guard = self.model.write().await;
            if guard.is_some() {
                tracing::info!("Unloading previous model before loading new one");
                *guard = None;
                // Drop the guard to release the lock and allow the model to be fully dropped
            }
        }

        // Verify model file exists
        if !model_path.exists() {
            return Err(format!("Model file not found: {}", model_path.display()));
        }

        // Validate GGUF file format before loading to prevent panics in mistral.rs
        Self::validate_gguf_file(&model_path)?;

        // Get model config
        let _config =
            get_model_config(model_id).ok_or_else(|| format!("Unknown model: {model_id}"))?;

        // Get the directory and filename
        let model_dir = model_path
            .parent()
            .ok_or("Invalid model path")?
            .to_string_lossy()
            .to_string();
        let model_filename = model_path
            .file_name()
            .ok_or("Invalid model filename")?
            .to_string_lossy()
            .to_string();

        // Build the model using GgufModelBuilder
        // CRITICAL MEMORY CONFIGURATION:
        // - Disable prefix cache: Prevents KV cache accumulation across requests
        //   (we don't need multi-turn caching for single-shot style checking)
        // - Limit max sequences to 1: We only process one request at a time
        // - These settings prevent the severe memory leak that would otherwise
        //   cause memory to grow from ~5GB to 19GB+ during continuous usage
        let model = GgufModelBuilder::new(model_dir, vec![model_filename])
            .with_logging()
            .with_prefix_cache_n(None) // Disable prefix caching to prevent memory accumulation
            .with_max_num_seqs(1) // Single request processing only
            .build()
            .await
            .map_err(|e| format!("Failed to load model: {e}"))?;

        // Store the loaded model
        let mut guard = self.model.write().await;
        *guard = Some(LoadedModel {
            model,
            model_id: model_id.to_string(),
        });

        Ok(())
    }

    /// Unload the current model to free memory
    pub async fn unload_model(&self) {
        let mut guard = self.model.write().await;
        *guard = None;
    }

    /// Validate a GGUF file before loading to prevent panics in mistral.rs
    fn validate_gguf_file(path: &PathBuf) -> Result<(), String> {
        use std::fs::File;
        use std::io::Read;

        // GGUF magic bytes: "GGUF" (0x47475546 little-endian)
        const GGUF_MAGIC: [u8; 4] = [0x47, 0x47, 0x55, 0x46];
        // Minimum reasonable GGUF file size (header + some data)
        const MIN_GGUF_SIZE: u64 = 1024;

        // Check file size
        let metadata =
            std::fs::metadata(path).map_err(|e| format!("Cannot read model file metadata: {e}"))?;

        let file_size = metadata.len();
        if file_size < MIN_GGUF_SIZE {
            return Err(format!(
                "Model file is too small ({} bytes). It may be corrupted or incomplete.",
                file_size
            ));
        }

        // Read and validate magic bytes
        let mut file =
            File::open(path).map_err(|e| format!("Cannot open model file for validation: {e}"))?;

        let mut magic = [0u8; 4];
        file.read_exact(&mut magic)
            .map_err(|e| format!("Cannot read model file header: {e}"))?;

        if magic != GGUF_MAGIC {
            return Err(format!(
                "Invalid GGUF file: magic bytes mismatch. Expected GGUF, got {:02X}{:02X}{:02X}{:02X}. The model file may be corrupted.",
                magic[0], magic[1], magic[2], magic[3]
            ));
        }

        // Read version (next 4 bytes as u32 little-endian)
        let mut version_bytes = [0u8; 4];
        file.read_exact(&mut version_bytes)
            .map_err(|e| format!("Cannot read GGUF version: {e}"))?;

        let version = u32::from_le_bytes(version_bytes);
        // GGUF versions 1, 2, and 3 are known
        if version == 0 || version > 10 {
            return Err(format!(
                "Unsupported GGUF version: {}. The model file may be corrupted or incompatible.",
                version
            ));
        }

        tracing::debug!(
            "GGUF file validated: size={} bytes, version={}",
            file_size,
            version
        );
        Ok(())
    }

    /// Update inference settings
    pub fn update_settings(&mut self, settings: InferenceSettings) {
        self.settings = settings;
    }

    /// Set inference preset (Fast/Balanced/Quality)
    pub fn set_preset(&mut self, preset: crate::llm::config::InferencePreset) {
        tracing::info!("LlmEngine: Setting inference preset to {:?}", preset);
        self.settings = InferenceSettings::from(preset);
    }

    /// Generate style suggestions for text
    pub async fn analyze_style(
        &self,
        text: &str,
        style: StyleTemplate,
    ) -> Result<Vec<StyleSuggestion>, String> {
        tracing::info!(
            "LlmEngine::analyze_style: START text_len={}, style={:?}",
            text.len(),
            style
        );

        // Get the loaded model
        let guard = self.model.read().await;
        let loaded = guard.as_ref().ok_or_else(|| {
            tracing::warn!("LlmEngine::analyze_style: No model loaded");
            "No model loaded".to_string()
        })?;

        tracing::debug!(
            "LlmEngine::analyze_style: Model loaded, id={}",
            loaded.model_id
        );

        // Get context data for prompt building
        let ctx_manager = self.context_manager.read().await;
        let custom_vocabulary = ctx_manager.get_custom_vocabulary().to_vec();
        let learned_terms = ctx_manager.get_learned_terms();
        let rejection_patterns = ctx_manager
            .get_rejection_patterns(style)
            .into_iter()
            .cloned()
            .collect::<Vec<_>>();
        drop(ctx_manager);

        tracing::debug!(
            "LlmEngine::analyze_style: Context - vocab={}, learned_terms={}, rejection_patterns={}",
            custom_vocabulary.len(),
            learned_terms.len(),
            rejection_patterns.len()
        );

        // Build the prompt
        let prompt = build_style_prompt(
            text,
            style,
            &custom_vocabulary,
            &learned_terms,
            &rejection_patterns,
        );

        tracing::debug!(
            "LlmEngine::analyze_style: Prompt built, len={}",
            prompt.len()
        );

        // Generate response using mistral.rs
        tracing::info!("LlmEngine::analyze_style: Calling mistral.rs generate...");
        let generate_start = std::time::Instant::now();
        let response = self.generate(&loaded.model, &prompt).await?;
        let generate_elapsed = generate_start.elapsed().as_millis();

        tracing::info!(
            "LlmEngine::analyze_style: generate() completed in {}ms, response_len={}",
            generate_elapsed,
            response.len()
        );
        tracing::debug!("LlmEngine::analyze_style: Raw response: {}", response);

        // Parse the response
        let parsed = parse_llm_response(&response).map_err(|e| {
            // Include truncated raw response in error for debugging
            let preview: String = response.chars().take(500).collect();
            tracing::error!(
                "LlmEngine::analyze_style: Failed to parse response: {}. Raw response preview: {}",
                e,
                preview
            );
            format!("Failed to parse LLM response: {e}. Raw response preview: {preview}")
        })?;

        tracing::debug!(
            "LlmEngine::analyze_style: Parsed {} raw suggestions",
            parsed.len()
        );

        // Convert to StyleSuggestions with diff computation
        let suggestions: Vec<StyleSuggestion> = parsed
            .into_iter()
            .filter_map(|p| self.create_suggestion(&p, text, style))
            .collect();

        tracing::info!(
            "LlmEngine::analyze_style: END returning {} suggestions",
            suggestions.len()
        );

        Ok(suggestions)
    }

    /// Rephrase a sentence to improve readability while preserving meaning
    /// Used for readability errors (like long sentences) where Harper doesn't provide suggestions
    pub async fn rephrase_sentence(&self, sentence: &str) -> Result<String, String> {
        tracing::info!(
            "LlmEngine::rephrase_sentence: START sentence_len={}",
            sentence.len()
        );

        // Get the loaded model
        let guard = self.model.read().await;
        let loaded = guard.as_ref().ok_or_else(|| {
            tracing::warn!("LlmEngine::rephrase_sentence: No model loaded");
            "No model loaded".to_string()
        })?;

        // Build a simple prompt for rephrasing
        let prompt = format!(
            "Rewrite this sentence to improve readability while preserving the exact meaning:\n\n\
            Original: {}\n\n\
            You may split it into multiple sentences if that improves clarity. \
            Provide only the rewritten text, no explanation.",
            sentence
        );

        tracing::debug!(
            "LlmEngine::rephrase_sentence: Prompt built, len={}",
            prompt.len()
        );

        // Generate response
        let generate_start = std::time::Instant::now();
        let response = self.generate(&loaded.model, &prompt).await?;
        let generate_elapsed = generate_start.elapsed().as_millis();

        tracing::info!(
            "LlmEngine::rephrase_sentence: generate() completed in {}ms, response_len={}",
            generate_elapsed,
            response.len()
        );

        // Clean up the response - remove any leading/trailing whitespace and quotes
        let cleaned = response
            .trim()
            .trim_matches('"')
            .trim_matches('\'')
            .trim()
            .to_string();

        // Validate the response isn't empty or just the original
        if cleaned.is_empty() {
            return Err("LLM returned empty response".to_string());
        }

        // Normalize for comparison (ignore case and extra whitespace)
        let original_normalized: String = sentence
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .to_lowercase();
        let cleaned_normalized: String = cleaned
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .to_lowercase();

        if original_normalized == cleaned_normalized {
            return Err("LLM returned the same sentence without changes".to_string());
        }

        tracing::info!(
            "LlmEngine::rephrase_sentence: END returning rephrased text, len={}",
            cleaned.len()
        );

        Ok(cleaned)
    }

    /// Create a StyleSuggestion from parsed LLM output
    fn create_suggestion(
        &self,
        parsed: &ParsedSuggestion,
        original_text: &str,
        style: StyleTemplate,
    ) -> Option<StyleSuggestion> {
        // Validate the suggestion first
        if !Self::is_valid_suggestion(parsed) {
            tracing::warn!(
                "LlmEngine: Rejecting invalid suggestion - original: '{}', suggested: '{}', explanation: '{}'",
                parsed.original,
                parsed.suggested,
                parsed.explanation
            );
            return None;
        }

        // Find the byte position of the original text in the source
        let byte_start = original_text.find(&parsed.original)?;

        // Convert byte offset to character index (macOS uses character indices, not bytes)
        // This is critical for proper text replacement with Unicode text
        let char_start = original_text[..byte_start].chars().count();
        let char_end = char_start + parsed.original.chars().count();

        // Compute diff for visualization
        let diff = compute_diff(&parsed.original, &parsed.suggested);

        Some(StyleSuggestion {
            id: uuid::Uuid::new_v4().to_string(),
            original_text: parsed.original.clone(),
            suggested_text: parsed.suggested.clone(),
            explanation: parsed.explanation.clone(),
            original_start: char_start,
            original_end: char_end,
            confidence: 0.8, // Default confidence for LLM suggestions
            style,
            diff,
        })
    }

    /// Validate that a suggestion makes sense
    /// Returns false for obviously nonsensical suggestions from LLM hallucinations
    fn is_valid_suggestion(parsed: &ParsedSuggestion) -> bool {
        let original = parsed.original.trim();
        let suggested = parsed.suggested.trim();
        let explanation_lower = parsed.explanation.to_lowercase();

        // 1. Reject if original and suggested are identical
        if original == suggested {
            tracing::debug!("Validation failed: original and suggested are identical");
            return false;
        }

        // 2. Reject if suggested contains original repeated (duplicate hallucination)
        // e.g., original="test", suggested="test test"
        if suggested.contains(&format!("{} {}", original, original))
            || suggested.contains(&format!("{}{}", original, original))
        {
            tracing::debug!("Validation failed: suggested contains original repeated");
            return false;
        }

        // 3. Reject if original contains suggested and explanation mentions removing
        // This catches cases where LLM swapped original/suggested
        let removal_keywords = [
            "remov",
            "delet",
            "eliminat",
            "shorter",
            "concise",
            "redundan",
            "duplicate",
        ];
        let suggests_removal = removal_keywords
            .iter()
            .any(|kw| explanation_lower.contains(kw));

        if suggests_removal && suggested.len() > original.len() {
            // Explanation talks about removal but suggested is longer - likely swapped
            tracing::debug!(
                "Validation failed: explanation suggests removal but suggested is longer"
            );
            return false;
        }

        // 4. Reject if suggested is just original with text appended/prepended
        // and the appended text is very similar to original (repetition)
        if suggested.starts_with(original) || suggested.ends_with(original) {
            let extra = if suggested.starts_with(original) {
                suggested.strip_prefix(original).unwrap_or("").trim()
            } else {
                suggested.strip_suffix(original).unwrap_or("").trim()
            };

            // If the extra part is similar to original, it's likely a repetition hallucination
            if !extra.is_empty()
                && (extra == original || original.contains(extra) || extra.contains(original))
            {
                tracing::debug!(
                    "Validation failed: suggested appears to be repetition of original"
                );
                return false;
            }
        }

        // 5. Reject very short suggestions that are just noise
        if original.len() < 2 || suggested.len() < 2 {
            tracing::debug!("Validation failed: original or suggested too short");
            return false;
        }

        // 6. Reject word completion hallucinations
        // Pattern: original ends mid-word, suggested completes the word
        // e.g., original="Are they also p", suggested="Are they also properly"
        if suggested.starts_with(original) {
            let extra = &suggested[original.len()..];
            // If original ends with a letter and extra starts with a letter, it's word completion
            if let (Some(orig_last), Some(extra_first)) =
                (original.chars().last(), extra.chars().next())
            {
                if orig_last.is_alphabetic() && extra_first.is_alphabetic() {
                    tracing::debug!(
                        "Validation failed: word completion hallucination detected (original='{}', suggested='{}')",
                        original,
                        suggested
                    );
                    return false;
                }
            }
        }

        true
    }

    /// Generate text using the loaded model
    async fn generate(&self, model: &Model, prompt: &str) -> Result<String, String> {
        tracing::debug!(
            "generate: Building request with max_tokens={}, temp={}, top_p={}",
            self.settings.max_tokens,
            self.settings.temperature,
            self.settings.top_p
        );

        // Build a chat request with the prompt as a system message
        let messages = TextMessages::new().add_message(TextMessageRole::User, prompt);

        // Build request with our settings
        let request = RequestBuilder::from(messages)
            .set_sampler_max_len(self.settings.max_tokens as usize)
            .set_sampler_temperature(f64::from(self.settings.temperature))
            .set_sampler_topk(50)
            .set_sampler_topp(f64::from(self.settings.top_p));

        tracing::debug!("generate: Sending request to model...");

        // Send the request
        let response = model.send_chat_request(request).await.map_err(|e| {
            tracing::error!("generate: Model request failed: {}", e);
            format!("Generation failed: {e}")
        })?;

        tracing::debug!(
            "generate: Response received, choices={}",
            response.choices.len()
        );

        // Extract the response text
        let content = response
            .choices
            .first()
            .and_then(|c| c.message.content.as_ref())
            .ok_or_else(|| {
                tracing::warn!("generate: No content in response");
                "No response generated".to_string()
            })?;

        tracing::debug!("generate: Extracted content, len={}", content.len());

        Ok(content.clone())
    }

    /// Record that a suggestion was accepted
    pub async fn record_acceptance(&self, original: &str, suggested: &str, style: StyleTemplate) {
        let mut ctx_manager = self.context_manager.write().await;
        ctx_manager.record_acceptance(original, suggested, style);
        let _ = ctx_manager.save();
    }

    /// Record that a suggestion was rejected
    pub async fn record_rejection(
        &self,
        original: &str,
        suggested: &str,
        style: StyleTemplate,
        category: RejectionCategory,
    ) {
        let mut ctx_manager = self.context_manager.write().await;
        ctx_manager.record_rejection(original, suggested, style, category);
        let _ = ctx_manager.save();
    }

    /// Sync custom vocabulary from Harper dictionary
    pub async fn sync_vocabulary(&self, words: &[String]) {
        let mut ctx_manager = self.context_manager.write().await;
        ctx_manager.sync_custom_vocabulary(words);
        let _ = ctx_manager.save();
    }

    /// Get context statistics
    pub async fn get_context_stats(&self) -> crate::llm::context::ContextStats {
        self.context_manager.read().await.get_stats()
    }

    /// Get the models directory path
    pub fn models_dir(&self) -> &PathBuf {
        &self.models_dir
    }
}

/// Stub implementation when LLM feature is disabled
#[cfg(not(feature = "llm"))]
pub struct LlmEngine {
    _phantom: std::marker::PhantomData<()>,
}

#[cfg(not(feature = "llm"))]
impl LlmEngine {
    pub fn new(_app_support_dir: PathBuf) -> Result<Self, String> {
        Err("LLM feature not enabled".to_string())
    }

    pub async fn is_model_loaded(&self) -> bool {
        false
    }

    pub async fn loaded_model_id(&self) -> Option<String> {
        None
    }

    pub async fn load_model(&self, _model_path: PathBuf, _model_id: &str) -> Result<(), String> {
        Err("LLM feature not enabled".to_string())
    }

    pub async fn unload_model(&self) {}

    pub async fn analyze_style(
        &self,
        _text: &str,
        _style: StyleTemplate,
    ) -> Result<Vec<StyleSuggestion>, String> {
        Err("LLM feature not enabled".to_string())
    }

    pub async fn rephrase_sentence(&self, _sentence: &str) -> Result<String, String> {
        Err("LLM feature not enabled".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_creation_without_feature() {
        // This test verifies the stub compiles correctly
        #[cfg(not(feature = "llm"))]
        {
            let result = LlmEngine::new(PathBuf::from("/tmp"));
            assert!(result.is_err());
        }
    }
}
