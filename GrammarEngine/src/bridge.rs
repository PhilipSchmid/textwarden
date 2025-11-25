// FFI Bridge - Swift-Rust interop using swift-bridge
//
// Defines FFI-safe structs and functions for Swift integration.

// Allow non-camel-case types for swift-bridge generated code
#![allow(non_camel_case_types)]

use crate::analyzer;
use std::sync::Once;
use tracing::Level;
use tracing_subscriber::{fmt, EnvFilter};
use sysinfo::System;

static INIT_LOGGING: Once = Once::new();

#[swift_bridge::bridge]
mod ffi {
    pub enum ErrorSeverity {
        Error,
        Warning,
        Info,
    }

    // Opaque type for GrammarError to support Vec<GrammarError>
    extern "Rust" {
        type GrammarError;

        fn start(&self) -> usize;
        fn end(&self) -> usize;
        fn message(&self) -> String;
        fn severity(&self) -> ErrorSeverity;
        fn category(&self) -> String;
        fn lint_id(&self) -> String;
        fn suggestions(&self) -> Vec<String>;
    }

    // Opaque type for AnalysisResult
    extern "Rust" {
        type AnalysisResult;

        fn errors(&self) -> Vec<GrammarError>;
        fn word_count(&self) -> usize;
        fn analysis_time_ms(&self) -> u64;
        fn memory_before_bytes(&self) -> u64;
        fn memory_after_bytes(&self) -> u64;
        fn memory_delta_bytes(&self) -> i64;
    }

    extern "Rust" {
        fn initialize_logging(log_level: String);

        fn analyze_text(
            text: String,
            dialect: String,
            enable_internet_abbrev: bool,
            enable_genz_slang: bool,
            enable_it_terminology: bool,
            enable_language_detection: bool,
            excluded_languages: Vec<String>,
            enable_sentence_start_capitalization: bool
        ) -> AnalysisResult;
    }
}

// FFI type implementations
#[derive(Clone)]
pub struct GrammarError {
    start: usize,
    end: usize,
    message: String,
    severity: analyzer::ErrorSeverity,
    category: String,
    lint_id: String,
    suggestions: Vec<String>,
}

impl GrammarError {
    fn start(&self) -> usize {
        self.start
    }

    fn end(&self) -> usize {
        self.end
    }

    fn message(&self) -> String {
        self.message.clone()
    }

    fn severity(&self) -> ffi::ErrorSeverity {
        match self.severity {
            analyzer::ErrorSeverity::Error => ffi::ErrorSeverity::Error,
            analyzer::ErrorSeverity::Warning => ffi::ErrorSeverity::Warning,
            analyzer::ErrorSeverity::Info => ffi::ErrorSeverity::Info,
        }
    }

    fn category(&self) -> String {
        self.category.clone()
    }

    fn lint_id(&self) -> String {
        self.lint_id.clone()
    }

    fn suggestions(&self) -> Vec<String> {
        self.suggestions.clone()
    }
}

pub struct AnalysisResult {
    errors: Vec<GrammarError>,
    word_count: usize,
    analysis_time_ms: u64,
    memory_before_bytes: u64,
    memory_after_bytes: u64,
    memory_delta_bytes: i64,
}

impl AnalysisResult {
    fn errors(&self) -> Vec<GrammarError> {
        self.errors.clone()
    }

    fn word_count(&self) -> usize {
        self.word_count
    }

    fn analysis_time_ms(&self) -> u64 {
        self.analysis_time_ms
    }

    fn memory_before_bytes(&self) -> u64 {
        self.memory_before_bytes
    }

    fn memory_after_bytes(&self) -> u64 {
        self.memory_after_bytes
    }

    fn memory_delta_bytes(&self) -> i64 {
        self.memory_delta_bytes
    }
}

// Initialize the logging system
// This should be called once from Swift at application startup
fn initialize_logging(log_level: String) {
    INIT_LOGGING.call_once(|| {
        let level = match log_level.to_lowercase().as_str() {
            "debug" => Level::DEBUG,
            "info" => Level::INFO,
            "warn" | "warning" => Level::WARN,
            "error" => Level::ERROR,
            _ => Level::INFO, // default to info
        };

        let filter = EnvFilter::from_default_env()
            .add_directive(level.into());

        fmt()
            .with_env_filter(filter)
            .with_target(true)
            .with_thread_ids(false)
            .with_line_number(true)
            .init();

        tracing::info!("Grammar Engine logging initialized at level: {}", log_level);
    });
}

// FFI wrapper that calls the analyzer and converts types
#[tracing::instrument(skip(text), fields(text_len = text.len()))]
fn analyze_text(
    text: String,
    dialect: String,
    enable_internet_abbrev: bool,
    enable_genz_slang: bool,
    enable_it_terminology: bool,
    enable_language_detection: bool,
    excluded_languages: Vec<String>,
    enable_sentence_start_capitalization: bool
) -> AnalysisResult {
    // SECURITY: Never log the actual text content - only metadata
    tracing::debug!(
        "FFI analyze_text called: dialect={}, text_len={}, lang_detection={}",
        dialect, text.len(), enable_language_detection
    );

    // Capture memory before analysis
    let mut sys_before = System::new_all();
    sys_before.refresh_all();

    let pid = sysinfo::get_current_pid().unwrap();
    let memory_before = sys_before
        .process(pid)
        .map(|p| p.memory())
        .unwrap_or(0);

    let result = analyzer::analyze_text(
        &text,
        &dialect,
        enable_internet_abbrev,
        enable_genz_slang,
        enable_it_terminology,
        enable_language_detection,
        excluded_languages,
        enable_sentence_start_capitalization
    );

    // Capture memory after analysis
    let mut sys_after = System::new_all();
    sys_after.refresh_all();

    let memory_after = sys_after
        .process(pid)
        .map(|p| p.memory())
        .unwrap_or(0);

    let memory_delta = (memory_after as i64) - (memory_before as i64);

    tracing::info!(
        "Analysis completed: {} errors found, {} words, {}ms, mem_delta={}KB",
        result.errors.len(),
        result.word_count,
        result.analysis_time_ms,
        memory_delta / 1024
    );

    // Convert analyzer types to FFI types
    let errors = result.errors
        .into_iter()
        .map(|err| GrammarError {
            start: err.start,
            end: err.end,
            message: err.message,
            severity: err.severity,
            category: err.category,
            lint_id: err.lint_id,
            suggestions: err.suggestions,
        })
        .collect();

    AnalysisResult {
        errors,
        word_count: result.word_count,
        analysis_time_ms: result.analysis_time_ms,
        memory_before_bytes: memory_before,
        memory_after_bytes: memory_after,
        memory_delta_bytes: memory_delta,
    }
}
