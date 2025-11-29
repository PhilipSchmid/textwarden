// LLM Module - Style checking using local language models
//
// This module provides LLM-based style suggestions using locally-running
// language models. It supports multiple models (Qwen, Phi, Gemma) and
// learns from user feedback over time.

pub mod config;
pub mod context;
pub mod engine;
pub mod model_manager;
pub mod prompts;
pub mod sentence_detector;

// Re-export commonly used types
pub use config::{ModelConfig, InferenceSettings, AVAILABLE_MODELS};
pub use context::ContextManager;
pub use engine::LlmEngine;
pub use model_manager::ModelManager;
pub use prompts::{build_style_prompt, parse_llm_response};
pub use sentence_detector::{extract_complete_sentences, ends_with_complete_sentence, SentenceSpan};
