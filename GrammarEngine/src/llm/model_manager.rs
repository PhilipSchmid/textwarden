// Model Manager - Manage GGUF model files
//
// Handles model discovery and validation of local model files.
// Note: Downloads are handled by Swift's URLSession for proper progress reporting.

use std::{
    fs,
    io::Read,
    path::{Path, PathBuf},
};

use crate::llm::config::{default_model_id, get_model_config, AVAILABLE_MODELS};
use crate::llm_types::ModelInfo;
use sha2::{Digest, Sha256};
use tracing::warn;

/// GGUF file expectations
const GGUF_MAGIC: [u8; 4] = [0x47, 0x47, 0x55, 0x46];
const MIN_GGUF_SIZE: u64 = 1024;

fn compute_sha256(path: &Path) -> Result<String, String> {
    let mut file =
        fs::File::open(path).map_err(|e| format!("Failed to open {}: {}", path.display(), e))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 8192];

    loop {
        let bytes_read = file
            .read(&mut buffer)
            .map_err(|e| format!("Failed to read {}: {}", path.display(), e))?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

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
            warn!(
                "Failed to create models directory: {} (path={})",
                e,
                models_dir.display()
            );
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

        if actual_size < MIN_GGUF_SIZE {
            return Err(format!(
                "Model file too small to be valid GGUF ({} bytes): {}",
                actual_size,
                path.display()
            ));
        }

        if !(min_size..=max_size).contains(&actual_size) {
            return Ok(false);
        }

        // Validate GGUF magic and version to guard against corrupted downloads/imports
        let mut file = fs::File::open(&path)
            .map_err(|e| format!("Failed to open model file {}: {}", path.display(), e))?;

        let mut magic = [0u8; 4];
        file.read_exact(&mut magic)
            .map_err(|e| format!("Failed to read GGUF magic from {}: {}", path.display(), e))?;
        if magic != GGUF_MAGIC {
            return Err(format!(
                "Invalid GGUF magic in {}: expected GGUF, got {:02X?}",
                path.display(),
                magic
            ));
        }

        let mut version_bytes = [0u8; 4];
        file.read_exact(&mut version_bytes)
            .map_err(|e| format!("Failed to read GGUF version from {}: {}", path.display(), e))?;
        let version = u32::from_le_bytes(version_bytes);
        if version == 0 || version > 10 {
            return Err(format!(
                "Unsupported GGUF version {} in {}",
                version,
                path.display()
            ));
        }

        // If a checksum file is present (filename + .sha256), verify it
        if let Some(file_name) = path.file_name() {
            let checksum_path =
                path.with_file_name(format!("{}.sha256", file_name.to_string_lossy()));
            if checksum_path.exists() {
                let expected = fs::read_to_string(&checksum_path).map_err(|e| {
                    format!("Failed to read checksum {}: {}", checksum_path.display(), e)
                })?;
                let expected = expected.trim().to_lowercase();

                if expected.len() != 64 || !expected.chars().all(|c| c.is_ascii_hexdigit()) {
                    return Err(format!(
                        "Checksum file {} is not a valid SHA256 hex string",
                        checksum_path.display()
                    ));
                }

                let actual = compute_sha256(&path)?;
                if actual != expected {
                    return Err(format!(
                        "Checksum mismatch for {}: expected {}, got {}",
                        path.display(),
                        expected,
                        actual
                    ));
                }
            }
        }

        Ok(true)
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
    use std::io::Write;

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

    #[test]
    fn test_compute_sha256_matches_known_digest() {
        let dir = env::temp_dir().join("textwarden_model_checksum_test");
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("sample.bin");

        let mut file = fs::File::create(&path).expect("create sample file");
        file.write_all(b"hello world")
            .expect("write sample content");

        let digest = compute_sha256(&path).expect("compute checksum");
        assert_eq!(
            digest,
            "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
        );

        let _ = fs::remove_file(path);
    }
}
