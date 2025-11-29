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
        // Verify model file exists
        if !model_path.exists() {
            return Err(format!("Model file not found: {}", model_path.display()));
        }

        // Get model config
        let _config = get_model_config(model_id)
            .ok_or_else(|| format!("Unknown model: {model_id}"))?;

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
        let model = GgufModelBuilder::new(model_dir, vec![model_filename])
            .with_logging()
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

    /// Update inference settings
    pub fn update_settings(&mut self, settings: InferenceSettings) {
        self.settings = settings;
    }

    /// Generate style suggestions for text
    pub async fn analyze_style(
        &self,
        text: &str,
        style: StyleTemplate,
    ) -> Result<Vec<StyleSuggestion>, String> {
        // Get the loaded model
        let guard = self.model.read().await;
        let loaded = guard.as_ref().ok_or("No model loaded")?;

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

        // Build the prompt
        let prompt = build_style_prompt(
            text,
            style,
            &custom_vocabulary,
            &learned_terms,
            &rejection_patterns,
        );

        // Generate response using mistral.rs
        let response = self.generate(&loaded.model, &prompt).await?;

        // Parse the response
        let parsed = parse_llm_response(&response)
            .map_err(|e| format!("Failed to parse LLM response: {e}"))?;

        // Convert to StyleSuggestions with diff computation
        let suggestions = parsed
            .into_iter()
            .filter_map(|p| self.create_suggestion(&p, text, style))
            .collect();

        Ok(suggestions)
    }

    /// Create a StyleSuggestion from parsed LLM output
    fn create_suggestion(
        &self,
        parsed: &ParsedSuggestion,
        original_text: &str,
        style: StyleTemplate,
    ) -> Option<StyleSuggestion> {
        // Find the position of the original text in the source
        let start = original_text.find(&parsed.original)?;
        let end = start + parsed.original.len();

        // Compute diff for visualization
        let diff = compute_diff(&parsed.original, &parsed.suggested);

        Some(StyleSuggestion {
            id: uuid::Uuid::new_v4().to_string(),
            original_text: parsed.original.clone(),
            suggested_text: parsed.suggested.clone(),
            explanation: parsed.explanation.clone(),
            original_start: start,
            original_end: end,
            confidence: 0.8, // Default confidence for LLM suggestions
            style,
            diff,
        })
    }

    /// Generate text using the loaded model
    async fn generate(&self, model: &Model, prompt: &str) -> Result<String, String> {
        // Build a chat request with the prompt as a system message
        let messages = TextMessages::new()
            .add_message(TextMessageRole::User, prompt);

        // Build request with our settings
        let request = RequestBuilder::from(messages)
            .set_sampler_max_len(self.settings.max_tokens as usize)
            .set_sampler_temperature(f64::from(self.settings.temperature))
            .set_sampler_topk(50)
            .set_sampler_topp(f64::from(self.settings.top_p));

        // Send the request
        let response = model
            .send_chat_request(request)
            .await
            .map_err(|e| format!("Generation failed: {e}"))?;

        // Extract the response text
        let content = response
            .choices
            .first()
            .and_then(|c| c.message.content.as_ref())
            .ok_or("No response generated")?;

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
