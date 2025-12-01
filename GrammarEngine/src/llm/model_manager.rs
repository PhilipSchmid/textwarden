// Model Manager - Manage GGUF model files
//
// Handles model discovery and validation of local model files.
// Note: Downloads are handled by Swift's URLSession for proper progress reporting.

use std::fs;
use std::path::PathBuf;

use crate::llm::config::{default_model_id, get_model_config, AVAILABLE_MODELS};
use crate::llm_types::ModelInfo;

/// Manager for LLM model files
pub struct ModelManager {
    models_dir: PathBuf,
    current_model_id: Option<String>,
}

impl ModelManager {
    /// Create a new model manager
    pub fn new(app_support_dir: &PathBuf) -> Self {
        let models_dir = app_support_dir.join("models");

        // Ensure models directory exists
        if let Err(e) = fs::create_dir_all(&models_dir) {
            eprintln!("Warning: Failed to create models directory: {e}");
        }

        Self {
            models_dir,
            current_model_id: None,
        }
    }

    /// Get the models directory path
    pub fn models_dir(&self) -> &PathBuf {
        &self.models_dir
    }

    /// Get the path for a specific model file
    pub fn model_path(&self, model_id: &str) -> Option<PathBuf> {
        let config = get_model_config(model_id)?;
        Some(self.models_dir.join(config.filename))
    }

    /// Check if a model is downloaded
    pub fn is_model_downloaded(&self, model_id: &str) -> bool {
        if let Some(path) = self.model_path(model_id) {
            path.exists()
        } else {
            false
        }
    }

    /// Get the size of a downloaded model file
    pub fn get_model_file_size(&self, model_id: &str) -> Option<u64> {
        let path = self.model_path(model_id)?;
        fs::metadata(&path).ok().map(|m| m.len())
    }

    /// Validate a downloaded model (basic size check)
    pub fn validate_model(&self, model_id: &str) -> Result<bool, String> {
        let config =
            get_model_config(model_id).ok_or_else(|| format!("Unknown model: {model_id}"))?;

        let path = self
            .model_path(model_id)
            .ok_or_else(|| "Invalid model path".to_string())?;

        if !path.exists() {
            return Ok(false);
        }

        let actual_size = fs::metadata(&path)
            .map_err(|e| format!("Failed to read model file: {e}"))?
            .len();

        // Allow 10% variance in file size (compression differences)
        let min_size = (config.size_bytes as f64 * 0.9) as u64;
        let max_size = (config.size_bytes as f64 * 1.1) as u64;

        Ok(actual_size >= min_size && actual_size <= max_size)
    }

    /// Scan for all available models and their download status
    pub fn scan_models(&self) -> Vec<ModelInfo> {
        let default_id = self
            .current_model_id
            .as_deref()
            .unwrap_or(default_model_id());

        AVAILABLE_MODELS
            .iter()
            .map(|config| {
                let is_downloaded = self.is_model_downloaded(config.id);
                let is_default = config.id == default_id;
                config.to_model_info(is_downloaded, is_default)
            })
            .collect()
    }

    /// Get info for a specific model
    pub fn get_model_info(&self, model_id: &str) -> Option<ModelInfo> {
        let config = get_model_config(model_id)?;
        let is_downloaded = self.is_model_downloaded(model_id);
        let is_default = self.current_model_id.as_deref() == Some(model_id);
        Some(config.to_model_info(is_downloaded, is_default))
    }

    /// Set the current/default model
    pub fn set_current_model(&mut self, model_id: &str) -> Result<(), String> {
        if get_model_config(model_id).is_none() {
            return Err(format!("Unknown model: {model_id}"));
        }
        self.current_model_id = Some(model_id.to_string());
        Ok(())
    }

    /// Get the current model ID
    pub fn current_model_id(&self) -> &str {
        self.current_model_id
            .as_deref()
            .unwrap_or(default_model_id())
    }

    /// Delete a downloaded model
    pub fn delete_model(&self, model_id: &str) -> Result<(), String> {
        let path = self
            .model_path(model_id)
            .ok_or_else(|| format!("Unknown model: {model_id}"))?;

        if path.exists() {
            fs::remove_file(&path).map_err(|e| format!("Failed to delete model: {e}"))?;
        }

        Ok(())
    }

    /// Get the total size of all downloaded models
    pub fn total_downloaded_size(&self) -> u64 {
        AVAILABLE_MODELS
            .iter()
            .filter_map(|config| self.get_model_file_size(config.id))
            .sum()
    }

    /// Import a model from a local file path
    pub fn import_model(&self, model_id: &str, source_path: &PathBuf) -> Result<(), String> {
        let config =
            get_model_config(model_id).ok_or_else(|| format!("Unknown model: {model_id}"))?;

        if !source_path.exists() {
            return Err("Source file does not exist".to_string());
        }

        let dest_path = self.models_dir.join(config.filename);

        // Copy the file
        fs::copy(source_path, &dest_path).map_err(|e| format!("Failed to import model: {e}"))?;

        Ok(())
    }

    /// Get recommended model based on system capabilities
    pub fn get_recommended_model(&self) -> &'static str {
        // For now, always recommend the balanced model
        // In the future, could check available RAM/GPU memory
        "qwen2.5-1.5b"
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn create_test_manager() -> ModelManager {
        let temp_dir = env::temp_dir().join("textwarden_model_test");
        ModelManager::new(&temp_dir)
    }

    #[test]
    fn test_model_path() {
        let manager = create_test_manager();

        let path = manager.model_path("qwen2.5-1.5b");
        assert!(path.is_some());
        assert!(path.unwrap().to_string_lossy().contains("qwen2.5-1.5b"));
    }

    #[test]
    fn test_scan_models() {
        let manager = create_test_manager();
        let models = manager.scan_models();

        assert_eq!(models.len(), AVAILABLE_MODELS.len());

        // Check that all models are initially not downloaded
        for model in &models {
            assert!(!model.is_downloaded);
        }
    }

    #[test]
    fn test_set_current_model() {
        let mut manager = create_test_manager();

        assert!(manager.set_current_model("phi3-mini").is_ok());
        assert_eq!(manager.current_model_id(), "phi3-mini");

        assert!(manager.set_current_model("invalid-model").is_err());
    }

    #[test]
    fn test_unknown_model() {
        let manager = create_test_manager();

        assert!(manager.model_path("nonexistent").is_none());
        assert!(!manager.is_model_downloaded("nonexistent"));
    }
}
