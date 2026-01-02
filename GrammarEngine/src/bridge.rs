// FFI Bridge - Swift-Rust interop using swift-bridge
//
// Defines FFI-safe structs and functions for Swift integration.

// Allow non-camel-case types for swift-bridge generated code
#![allow(non_camel_case_types)]

use crate::analyzer;
use crate::swift_logger::{register_swift_callback, SwiftLogCallback, SwiftLoggerLayer};
use std::sync::Once;
use sysinfo::{Pid, ProcessesToUpdate, System};
use tracing::Level;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

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
            enable_brand_names: bool,
            enable_person_names: bool,
            enable_last_names: bool,
            enable_language_detection: bool,
            excluded_languages: Vec<String>,
            enable_sentence_start_capitalization: bool,
            // Individual rule toggles
            enforce_oxford_comma: bool,
            check_ellipsis: bool,
            check_unclosed_quotes: bool,
            check_dashes: bool,
        ) -> AnalysisResult;
    }
}

/// Lightweight helper to read current process memory in bytes
fn read_process_memory(pid: Option<Pid>) -> u64 {
    if let Some(pid) = pid {
        let mut sys = System::new();
        sys.refresh_processes(ProcessesToUpdate::All, false);
        return sys.process(pid).map(|p| p.memory()).unwrap_or(0);
    }
    0
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

// Initialize the logging system with unified Swift logging support
// This should be called once from Swift at application startup, AFTER register_log_callback
fn initialize_logging(log_level: String) {
    INIT_LOGGING.call_once(|| {
        let level = match log_level.to_lowercase().as_str() {
            "debug" => Level::DEBUG,
            "info" => Level::INFO,
            "warn" | "warning" => Level::WARN,
            "error" => Level::ERROR,
            _ => Level::INFO, // default to info
        };

        let filter = EnvFilter::from_default_env().add_directive(level.into());

        // Create the Swift logger layer for unified logging
        let swift_layer = SwiftLoggerLayer::new(level);

        // Also keep console logging for debugging during development
        let fmt_layer = fmt::layer()
            .with_target(true)
            .with_thread_ids(false)
            .with_line_number(true);

        // Initialize with both layers
        tracing_subscriber::registry()
            .with(filter)
            .with(swift_layer)
            .with(fmt_layer)
            .init();

        tracing::info!(
            "Grammar Engine logging initialized at level: {} (unified with Swift)",
            log_level
        );
    });
}

/// Register the Swift log callback for unified logging
///
/// # Safety
/// The callback pointer must be valid and point to a function with signature:
/// `extern "C" fn(level: i32, message: *const c_char)`
///
/// This must be called BEFORE initialize_logging for the callback to be active
/// during initialization.
#[no_mangle]
pub extern "C" fn register_rust_log_callback(callback: SwiftLogCallback) {
    register_swift_callback(callback);
}

// FFI wrapper that calls the analyzer and converts types
#[tracing::instrument(skip(text), fields(text_len = text.len()))]
fn analyze_text(
    text: String,
    dialect: String,
    enable_internet_abbrev: bool,
    enable_genz_slang: bool,
    enable_it_terminology: bool,
    enable_brand_names: bool,
    enable_person_names: bool,
    enable_last_names: bool,
    enable_language_detection: bool,
    excluded_languages: Vec<String>,
    enable_sentence_start_capitalization: bool,
    // Individual rule toggles
    enforce_oxford_comma: bool,
    check_ellipsis: bool,
    check_unclosed_quotes: bool,
    check_dashes: bool,
) -> AnalysisResult {
    // SECURITY: Never log the actual text content - only metadata
    tracing::debug!(
        "FFI analyze_text called: dialect={}, text_len={}, lang_detection={}",
        dialect,
        text.len(),
        enable_language_detection
    );

    let pid = sysinfo::get_current_pid().ok();
    let memory_before = read_process_memory(pid);

    let result = analyzer::analyze_text(
        &text,
        &dialect,
        enable_internet_abbrev,
        enable_genz_slang,
        enable_it_terminology,
        enable_brand_names,
        enable_person_names,
        enable_last_names,
        enable_language_detection,
        excluded_languages,
        enable_sentence_start_capitalization,
        enforce_oxford_comma,
        check_ellipsis,
        check_unclosed_quotes,
        check_dashes,
    );

    // Capture memory after analysis
    let memory_after = read_process_memory(pid);

    let memory_delta = (memory_after as i64) - (memory_before as i64);

    tracing::info!(
        "Analysis completed: {} errors found, {} words, {}ms, mem_delta={}KB",
        result.errors.len(),
        result.word_count,
        result.analysis_time_ms,
        memory_delta / 1024
    );

    // Convert analyzer types to FFI types
    let errors = result
        .errors
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
