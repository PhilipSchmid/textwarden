// Grammar Engine - Core library for grammar checking using Harper
//
// This library provides FFI-safe interfaces for Swift integration.

pub mod bridge;
pub mod analyzer;
pub mod slang_dict;
pub mod language_filter;

// LLM Style Checking module (feature-gated)
#[cfg(feature = "llm")]
pub mod llm;

// Always available LLM types (for FFI compatibility even without llm feature)
pub mod llm_types;
