// LLM Configuration - Model definitions and settings
//
// Defines the available LLM models and their configurations.

use crate::llm_types::{ModelInfo, ModelTier};

/// Configuration for an LLM model
#[derive(Debug, Clone)]
pub struct ModelConfig {
    pub id: &'static str,
    pub name: &'static str,
    pub filename: &'static str,
    pub download_url: &'static str,
    pub size_bytes: u64,
    pub context_length: u32,
    pub speed_rating: f32,
    pub quality_rating: f32,
    pub languages: &'static [&'static str],
    pub description: &'static str,
    pub tier: ModelTier,
}

impl ModelConfig {
    /// Convert to ModelInfo for FFI
    pub fn to_model_info(&self, is_downloaded: bool, is_default: bool) -> ModelInfo {
        ModelInfo {
            id: self.id.to_string(),
            name: self.name.to_string(),
            filename: self.filename.to_string(),
            download_url: self.download_url.to_string(),
            size_bytes: self.size_bytes,
            speed_rating: self.speed_rating,
            quality_rating: self.quality_rating,
            languages: self.languages.iter().map(|s| (*s).to_string()).collect(),
            is_multilingual: self.languages.len() > 1,
            description: self.description.to_string(),
            tier: self.tier,
            is_downloaded,
            is_default,
        }
    }
}

/// Available models for download
/// These are the recommended models from our research:
/// - Qwen 2.5 1.5B: Best overall balance
/// - Phi-3 Mini: Accurate/high quality
/// - Gemma 2 2B: Lightweight/fast
pub static AVAILABLE_MODELS: &[ModelConfig] = &[
    ModelConfig {
        id: "qwen2.5-1.5b",
        name: "Qwen 2.5 1.5B",
        filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        download_url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
        size_bytes: 1_050_000_000, // ~1.0 GB
        context_length: 32768,
        speed_rating: 8.0,
        quality_rating: 8.4,
        languages: &["en", "de", "fr", "es", "it", "pt", "nl", "pl", "ru", "zh", "ja", "ko", "ar", "vi", "th", "id", "ms", "tl", "hi", "bn", "ta", "te", "mr", "ur", "fa", "tr", "he", "uk", "cs"],
        description: "Best overall balance of speed and quality. Supports 29+ languages including English, German, French, Chinese.",
        tier: ModelTier::Balanced,
    },
    ModelConfig {
        id: "phi3-mini",
        name: "Phi-3 Mini",
        filename: "Phi-3-mini-4k-instruct-q4.gguf",
        download_url: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf",
        size_bytes: 2_300_000_000, // ~2.3 GB
        context_length: 4096,
        speed_rating: 6.5,
        quality_rating: 9.6,
        languages: &["en"],
        description: "Microsoft's compact powerhouse. Best writing quality, minimal hallucination. Recommended for serious writers.",
        tier: ModelTier::Accurate,
    },
    ModelConfig {
        id: "smollm3-3b",
        name: "SmolLM3 3B",
        filename: "HuggingFaceTB_SmolLM3-3B-Q4_K_M.gguf",
        download_url: "https://huggingface.co/bartowski/HuggingFaceTB_SmolLM3-3B-GGUF/resolve/main/HuggingFaceTB_SmolLM3-3B-Q4_K_M.gguf",
        size_bytes: 2_061_584_302, // ~1.92 GB
        context_length: 8192,
        speed_rating: 7.0,
        quality_rating: 8.8,
        languages: &["en", "fr", "es", "de", "it", "pt"],
        description: "HuggingFace's SmolLM3 with dual-mode reasoning. Excellent multilingual support for 6 European languages.",
        tier: ModelTier::Accurate,
    },
    ModelConfig {
        id: "llama-3.2-3b",
        name: "Llama 3.2 3B",
        filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        download_url: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        size_bytes: 2_019_377_696, // ~2.0 GB
        context_length: 8192,
        speed_rating: 7.0,
        quality_rating: 8.5,
        languages: &["en", "de", "fr", "it", "pt", "hi", "es", "th"],
        description: "Meta's compact multilingual model. Strong quality with good language support.",
        tier: ModelTier::Balanced,
    },
    ModelConfig {
        id: "gemma2-2b",
        name: "Gemma 2 2B",
        filename: "gemma-2-2b-it-Q4_K_M.gguf",
        download_url: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
        size_bytes: 1_708_582_752, // ~1.6 GB (verified from HuggingFace)
        context_length: 8192,
        speed_rating: 9.0,
        quality_rating: 7.0,
        languages: &["en"],
        description: "Google's edge-optimized model. Fastest inference, ideal for MacBook Air 8GB or when speed is priority.",
        tier: ModelTier::Lightweight,
    },
    ModelConfig {
        id: "llama-3.2-1b",
        name: "Llama 3.2 1B",
        filename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        download_url: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        size_bytes: 807_694_464, // ~0.8 GB
        context_length: 8192,
        speed_rating: 9.5,
        quality_rating: 6.0,
        languages: &["en", "de", "fr", "it", "pt", "hi", "es", "th"],
        description: "Meta's ultra-fast lightweight model. Best for quick suggestions on older hardware.",
        tier: ModelTier::Lightweight,
    },
];

/// Get model config by ID
pub fn get_model_config(id: &str) -> Option<&'static ModelConfig> {
    AVAILABLE_MODELS.iter().find(|m| m.id == id)
}

/// Get the default model ID
pub fn default_model_id() -> &'static str {
    "qwen2.5-1.5b"
}

/// Inference preset for user-friendly speed/quality tradeoff
///
/// These presets control how the LLM generates responses:
/// - **Fast**: Shorter responses, more deterministic (faster inference)
/// - **Balanced**: Default settings, good tradeoff
/// - **Quality**: Longer responses, more thorough analysis
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InferencePreset {
    /// Prioritizes speed - shorter responses, more deterministic
    Fast,
    /// Default balanced settings
    #[default]
    Balanced,
    /// Prioritizes quality - more thorough analysis
    Quality,
}

impl InferencePreset {
    /// Get human-readable name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Fast => "Fast",
            Self::Balanced => "Balanced",
            Self::Quality => "Quality",
        }
    }

    /// Get description explaining what this preset does
    pub fn description(&self) -> &'static str {
        match self {
            Self::Fast => "Faster responses, shorter suggestions. Best when you want quick feedback.",
            Self::Balanced => "Good balance of speed and thoroughness. Recommended for most users.",
            Self::Quality => "More thorough analysis, detailed suggestions. Best for important writing.",
        }
    }
}

/// LLM inference settings
#[derive(Debug, Clone)]
pub struct InferenceSettings {
    /// Maximum tokens to generate
    pub max_tokens: u32,
    /// Temperature for sampling (0.0 = deterministic, 1.0 = creative)
    /// Lower = more consistent/predictable, Higher = more varied
    pub temperature: f32,
    /// Top-p sampling threshold (nucleus sampling)
    pub top_p: f32,
    /// Number of threads for inference
    pub n_threads: u32,
    /// Number of GPU layers (0 = CPU only, -1 = all)
    pub n_gpu_layers: i32,
}

impl Default for InferenceSettings {
    fn default() -> Self {
        Self::from(InferencePreset::Balanced)
    }
}

impl From<InferencePreset> for InferenceSettings {
    fn from(preset: InferencePreset) -> Self {
        match preset {
            InferencePreset::Fast => Self {
                max_tokens: 256,      // Shorter responses = faster
                temperature: 0.2,     // More deterministic = faster sampling
                top_p: 0.85,
                n_threads: 4,
                n_gpu_layers: -1,
            },
            InferencePreset::Balanced => Self {
                max_tokens: 512,      // Good balance
                temperature: 0.3,     // Slightly creative but consistent
                top_p: 0.9,
                n_threads: 4,
                n_gpu_layers: -1,
            },
            InferencePreset::Quality => Self {
                max_tokens: 768,      // Allow more detailed explanations
                temperature: 0.1,     // More deterministic = more accurate
                top_p: 0.95,          // Consider more tokens
                n_threads: 4,
                n_gpu_layers: -1,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_available_models() {
        assert!(!AVAILABLE_MODELS.is_empty());
        assert!(AVAILABLE_MODELS.len() >= 3);

        // Check that default model exists
        let default = get_model_config(default_model_id());
        assert!(default.is_some());
    }

    #[test]
    fn test_model_info_conversion() {
        let config = &AVAILABLE_MODELS[0];
        let info = config.to_model_info(true, true);

        assert_eq!(info.id, config.id);
        assert_eq!(info.name, config.name);
        assert!(info.is_downloaded);
        assert!(info.is_default);
    }
}
