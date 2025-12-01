// FFI Bridge - Swift-Rust interop using swift-bridge
//
// Defines FFI-safe structs and functions for Swift integration.

// Allow non-camel-case types for swift-bridge generated code
#![allow(non_camel_case_types)]

use crate::analyzer;
use crate::llm_types;
use crate::swift_logger::{SwiftLogCallback, SwiftLoggerLayer, register_swift_callback};
use std::sync::Once;
use tracing::Level;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};
use sysinfo::System;

#[cfg(feature = "llm")]
use {
    crate::llm::{LlmEngine, ModelManager},
    std::sync::Arc,
    tokio::sync::RwLock,
};

static INIT_LOGGING: Once = Once::new();

#[cfg(feature = "llm")]
lazy_static::lazy_static! {
    static ref LLM_ENGINE: Arc<RwLock<Option<LlmEngine>>> = Arc::new(RwLock::new(None));
    static ref MODEL_MANAGER: Arc<RwLock<Option<ModelManager>>> = Arc::new(RwLock::new(None));
    static ref TOKIO_RUNTIME: tokio::runtime::Runtime = tokio::runtime::Runtime::new().unwrap();
}

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

    // ============================================
    // LLM Style Checking Types
    // ============================================

    // Style template for writing suggestions
    pub enum StyleTemplate {
        Default,
        Formal,
        Informal,
        Business,
        Concise,
    }

    // Model tier classification
    pub enum ModelTier {
        Balanced,
        Accurate,
        Lightweight,
        Custom,
    }

    // Category for rejection feedback
    pub enum RejectionCategory {
        WrongMeaning,
        TooFormal,
        TooInformal,
        UnnecessaryChange,
        WrongTerm,
        Other,
    }

    // Inference preset for speed/quality tradeoff
    pub enum InferencePreset {
        Fast,
        Balanced,
        Quality,
    }

    // Diff segment kind for visualization
    pub enum DiffKind {
        Unchanged,
        Added,
        Removed,
    }

    // Opaque type for DiffSegment
    extern "Rust" {
        type FfiDiffSegment;

        fn text(&self) -> String;
        fn kind(&self) -> DiffKind;
    }

    // Opaque type for StyleSuggestion
    extern "Rust" {
        type FfiStyleSuggestion;

        fn id(&self) -> String;
        fn original_start(&self) -> usize;
        fn original_end(&self) -> usize;
        fn original_text(&self) -> String;
        fn suggested_text(&self) -> String;
        fn explanation(&self) -> String;
        fn confidence(&self) -> f32;
        fn style(&self) -> StyleTemplate;
        fn diff(&self) -> Vec<FfiDiffSegment>;
    }

    // Opaque type for StyleAnalysisResult
    extern "Rust" {
        type FfiStyleAnalysisResult;

        fn suggestions(&self) -> Vec<FfiStyleSuggestion>;
        fn analysis_time_ms(&self) -> u64;
        fn model_id(&self) -> String;
        fn style(&self) -> StyleTemplate;
        fn is_error(&self) -> bool;
        fn error_message(&self) -> String;
    }

    // Opaque type for ModelInfo
    extern "Rust" {
        type FfiModelInfo;

        fn id(&self) -> String;
        fn name(&self) -> String;
        fn filename(&self) -> String;
        fn download_url(&self) -> String;
        fn size_bytes(&self) -> u64;
        fn speed_rating(&self) -> f32;
        fn quality_rating(&self) -> f32;
        fn languages(&self) -> Vec<String>;
        fn is_multilingual(&self) -> bool;
        fn description(&self) -> String;
        fn tier(&self) -> ModelTier;
        fn is_downloaded(&self) -> bool;
        fn is_default(&self) -> bool;
    }

    // LLM Functions
    extern "Rust" {
        // Initialize the LLM subsystem with app support directory
        fn llm_initialize(app_support_dir: String) -> bool;

        // Get list of available models
        fn llm_get_available_models() -> Vec<FfiModelInfo>;

        // Check if a model is downloaded
        fn llm_is_model_downloaded(model_id: String) -> bool;

        // Load a model into memory
        fn llm_load_model(model_id: String) -> String;

        // Unload the current model from memory
        fn llm_unload_model();

        // Check if any model is currently loaded
        fn llm_is_model_loaded() -> bool;

        // Get the ID of the currently loaded model
        fn llm_get_loaded_model_id() -> String;

        // Analyze text for style suggestions (blocking)
        fn llm_analyze_style(text: String, style: StyleTemplate) -> FfiStyleAnalysisResult;

        // Record that a suggestion was accepted
        fn llm_record_acceptance(original: String, suggested: String, style: StyleTemplate);

        // Record that a suggestion was rejected
        fn llm_record_rejection(
            original: String,
            suggested: String,
            style: StyleTemplate,
            category: RejectionCategory
        );

        // Sync custom vocabulary from Harper dictionary
        fn llm_sync_vocabulary(words: Vec<String>);

        // Delete a downloaded model
        fn llm_delete_model(model_id: String) -> bool;

        // Get the models directory path
        fn llm_get_models_dir() -> String;

        // Import a model from a local file path
        fn llm_import_model(model_id: String, source_path: String) -> bool;

        // Set inference preset (Fast/Balanced/Quality)
        fn llm_set_inference_preset(preset: InferencePreset);
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

        let filter = EnvFilter::from_default_env()
            .add_directive(level.into());

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

        tracing::info!("Grammar Engine logging initialized at level: {} (unified with Swift)", log_level);
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

    let pid = sysinfo::get_current_pid().ok();
    let memory_before = pid
        .and_then(|p| sys_before.process(p))
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

    let memory_after = pid
        .and_then(|p| sys_after.process(p))
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

// ============================================
// LLM FFI Type Implementations
// ============================================

/// FFI wrapper for DiffSegment
#[derive(Clone)]
pub struct FfiDiffSegment {
    text: String,
    kind: llm_types::DiffKind,
}

impl FfiDiffSegment {
    fn text(&self) -> String {
        self.text.clone()
    }

    fn kind(&self) -> ffi::DiffKind {
        match self.kind {
            llm_types::DiffKind::Unchanged => ffi::DiffKind::Unchanged,
            llm_types::DiffKind::Added => ffi::DiffKind::Added,
            llm_types::DiffKind::Removed => ffi::DiffKind::Removed,
        }
    }
}

/// FFI wrapper for StyleSuggestion
#[derive(Clone)]
pub struct FfiStyleSuggestion {
    inner: llm_types::StyleSuggestion,
}

impl FfiStyleSuggestion {
    fn id(&self) -> String {
        self.inner.id.clone()
    }

    fn original_start(&self) -> usize {
        self.inner.original_start
    }

    fn original_end(&self) -> usize {
        self.inner.original_end
    }

    fn original_text(&self) -> String {
        self.inner.original_text.clone()
    }

    fn suggested_text(&self) -> String {
        self.inner.suggested_text.clone()
    }

    fn explanation(&self) -> String {
        self.inner.explanation.clone()
    }

    fn confidence(&self) -> f32 {
        self.inner.confidence
    }

    fn style(&self) -> ffi::StyleTemplate {
        match self.inner.style {
            llm_types::StyleTemplate::Default => ffi::StyleTemplate::Default,
            llm_types::StyleTemplate::Formal => ffi::StyleTemplate::Formal,
            llm_types::StyleTemplate::Informal => ffi::StyleTemplate::Informal,
            llm_types::StyleTemplate::Business => ffi::StyleTemplate::Business,
            llm_types::StyleTemplate::Concise => ffi::StyleTemplate::Concise,
        }
    }

    fn diff(&self) -> Vec<FfiDiffSegment> {
        self.inner
            .diff
            .iter()
            .map(|seg| FfiDiffSegment {
                text: seg.text.clone(),
                kind: seg.kind.clone(),
            })
            .collect()
    }
}

/// FFI wrapper for StyleAnalysisResult
pub struct FfiStyleAnalysisResult {
    suggestions: Vec<FfiStyleSuggestion>,
    analysis_time_ms: u64,
    model_id: String,
    style: llm_types::StyleTemplate,
    error: Option<String>,
}

impl FfiStyleAnalysisResult {
    fn suggestions(&self) -> Vec<FfiStyleSuggestion> {
        self.suggestions.clone()
    }

    fn analysis_time_ms(&self) -> u64 {
        self.analysis_time_ms
    }

    fn model_id(&self) -> String {
        self.model_id.clone()
    }

    fn style(&self) -> ffi::StyleTemplate {
        match self.style {
            llm_types::StyleTemplate::Default => ffi::StyleTemplate::Default,
            llm_types::StyleTemplate::Formal => ffi::StyleTemplate::Formal,
            llm_types::StyleTemplate::Informal => ffi::StyleTemplate::Informal,
            llm_types::StyleTemplate::Business => ffi::StyleTemplate::Business,
            llm_types::StyleTemplate::Concise => ffi::StyleTemplate::Concise,
        }
    }

    fn is_error(&self) -> bool {
        self.error.is_some()
    }

    fn error_message(&self) -> String {
        self.error.clone().unwrap_or_default()
    }
}

/// FFI wrapper for ModelInfo
#[derive(Clone)]
pub struct FfiModelInfo {
    inner: llm_types::ModelInfo,
}

impl FfiModelInfo {
    fn id(&self) -> String {
        self.inner.id.clone()
    }

    fn name(&self) -> String {
        self.inner.name.clone()
    }

    fn filename(&self) -> String {
        self.inner.filename.clone()
    }

    fn download_url(&self) -> String {
        self.inner.download_url.clone()
    }

    fn size_bytes(&self) -> u64 {
        self.inner.size_bytes
    }

    fn speed_rating(&self) -> f32 {
        self.inner.speed_rating
    }

    fn quality_rating(&self) -> f32 {
        self.inner.quality_rating
    }

    fn languages(&self) -> Vec<String> {
        self.inner.languages.clone()
    }

    fn is_multilingual(&self) -> bool {
        self.inner.is_multilingual
    }

    fn description(&self) -> String {
        self.inner.description.clone()
    }

    fn tier(&self) -> ffi::ModelTier {
        match self.inner.tier {
            llm_types::ModelTier::Balanced => ffi::ModelTier::Balanced,
            llm_types::ModelTier::Accurate => ffi::ModelTier::Accurate,
            llm_types::ModelTier::Lightweight => ffi::ModelTier::Lightweight,
            llm_types::ModelTier::Custom => ffi::ModelTier::Custom,
        }
    }

    fn is_downloaded(&self) -> bool {
        self.inner.is_downloaded
    }

    fn is_default(&self) -> bool {
        self.inner.is_default
    }
}

// Helper functions to convert FFI enums to internal types
fn ffi_style_to_internal(style: ffi::StyleTemplate) -> llm_types::StyleTemplate {
    match style {
        ffi::StyleTemplate::Default => llm_types::StyleTemplate::Default,
        ffi::StyleTemplate::Formal => llm_types::StyleTemplate::Formal,
        ffi::StyleTemplate::Informal => llm_types::StyleTemplate::Informal,
        ffi::StyleTemplate::Business => llm_types::StyleTemplate::Business,
        ffi::StyleTemplate::Concise => llm_types::StyleTemplate::Concise,
    }
}

#[cfg(feature = "llm")]
fn ffi_rejection_to_internal(category: ffi::RejectionCategory) -> llm_types::RejectionCategory {
    match category {
        ffi::RejectionCategory::WrongMeaning => llm_types::RejectionCategory::WrongMeaning,
        ffi::RejectionCategory::TooFormal => llm_types::RejectionCategory::TooFormal,
        ffi::RejectionCategory::TooInformal => llm_types::RejectionCategory::TooInformal,
        ffi::RejectionCategory::UnnecessaryChange => llm_types::RejectionCategory::UnnecessaryChange,
        ffi::RejectionCategory::WrongTerm => llm_types::RejectionCategory::WrongTerm,
        ffi::RejectionCategory::Other => llm_types::RejectionCategory::Other,
    }
}

// ============================================
// LLM FFI Function Implementations
// ============================================

#[cfg(feature = "llm")]
use std::path::PathBuf;

/// Initialize the LLM subsystem
#[cfg(feature = "llm")]
fn llm_initialize(app_support_dir: String) -> bool {
    let path = PathBuf::from(&app_support_dir);

    // Initialize model manager
    let manager = ModelManager::new(&path);
    {
        let mut guard = TOKIO_RUNTIME.block_on(MODEL_MANAGER.write());
        *guard = Some(manager);
    }

    // Initialize LLM engine
    match LlmEngine::new(path) {
        Ok(engine) => {
            let mut guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.write());
            *guard = Some(engine);
            tracing::info!("LLM subsystem initialized");
            true
        }
        Err(e) => {
            tracing::error!("Failed to initialize LLM engine: {}", e);
            false
        }
    }
}

#[cfg(not(feature = "llm"))]
fn llm_initialize(_app_support_dir: String) -> bool {
    tracing::warn!("LLM feature not enabled");
    false
}

/// Get available models
#[cfg(feature = "llm")]
fn llm_get_available_models() -> Vec<FfiModelInfo> {
    let guard = TOKIO_RUNTIME.block_on(MODEL_MANAGER.read());
    if let Some(ref manager) = *guard {
        manager
            .scan_models()
            .into_iter()
            .map(|info| FfiModelInfo { inner: info })
            .collect()
    } else {
        Vec::new()
    }
}

#[cfg(not(feature = "llm"))]
fn llm_get_available_models() -> Vec<FfiModelInfo> {
    Vec::new()
}

/// Check if model is downloaded
#[cfg(feature = "llm")]
fn llm_is_model_downloaded(model_id: String) -> bool {
    let guard = TOKIO_RUNTIME.block_on(MODEL_MANAGER.read());
    if let Some(ref manager) = *guard {
        manager.is_model_downloaded(&model_id)
    } else {
        false
    }
}

#[cfg(not(feature = "llm"))]
fn llm_is_model_downloaded(_model_id: String) -> bool {
    false
}

/// Load a model
///
/// This function is wrapped in catch_unwind to prevent panics from crashing the app.
/// Panics can occur in the underlying mistral.rs library when loading corrupted
/// or incompatible model files.
#[cfg(feature = "llm")]
fn llm_load_model(model_id: String) -> String {
    // Wrap the entire loading process in catch_unwind to handle panics gracefully
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let manager_guard = TOKIO_RUNTIME.block_on(MODEL_MANAGER.read());
        let model_path = if let Some(ref manager) = *manager_guard {
            manager.model_path(&model_id)
        } else {
            return "Model manager not initialized".to_string();
        };
        drop(manager_guard);

        let Some(path) = model_path else {
            return format!("Unknown model: {}", model_id);
        };

        // Verify model file exists and is readable before attempting to load
        if !path.exists() {
            return format!("Model file not found: {}", path.display());
        }

        // Check file size is reasonable (at least 1MB for a valid GGUF model)
        if let Ok(metadata) = std::fs::metadata(&path) {
            if metadata.len() < 1_000_000 {
                return format!("Model file appears corrupted (too small): {}", path.display());
            }
        }

        let engine_guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.read());
        if let Some(ref engine) = *engine_guard {
            match TOKIO_RUNTIME.block_on(engine.load_model(path, &model_id)) {
                Ok(()) => {
                    tracing::info!("Model {} loaded successfully", model_id);
                    String::new() // Empty string means success
                }
                Err(e) => {
                    tracing::error!("Failed to load model {}: {}", model_id, e);
                    e
                }
            }
        } else {
            "LLM engine not initialized".to_string()
        }
    }));

    match result {
        Ok(msg) => msg,
        Err(panic_info) => {
            // Convert panic info to a user-friendly error message
            let panic_msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = panic_info.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic during model loading".to_string()
            };
            tracing::error!("PANIC caught during model loading: {}", panic_msg);
            format!("Model loading failed (internal error): {}", panic_msg)
        }
    }
}

#[cfg(not(feature = "llm"))]
fn llm_load_model(_model_id: String) -> String {
    "LLM feature not enabled".to_string()
}

/// Unload the current model
///
/// This function is wrapped in catch_unwind to prevent panics from crashing the app.
#[cfg(feature = "llm")]
fn llm_unload_model() {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.read());
        if let Some(ref engine) = *guard {
            TOKIO_RUNTIME.block_on(engine.unload_model());
            tracing::info!("Model unloaded");
        }
    }));
}

#[cfg(not(feature = "llm"))]
fn llm_unload_model() {}

/// Check if model is loaded
#[cfg(feature = "llm")]
fn llm_is_model_loaded() -> bool {
    let guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.read());
    if let Some(ref engine) = *guard {
        TOKIO_RUNTIME.block_on(engine.is_model_loaded())
    } else {
        false
    }
}

#[cfg(not(feature = "llm"))]
fn llm_is_model_loaded() -> bool {
    false
}

/// Get loaded model ID
#[cfg(feature = "llm")]
fn llm_get_loaded_model_id() -> String {
    let guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.read());
    if let Some(ref engine) = *guard {
        TOKIO_RUNTIME.block_on(engine.loaded_model_id()).unwrap_or_default()
    } else {
        String::new()
    }
}

#[cfg(not(feature = "llm"))]
fn llm_get_loaded_model_id() -> String {
    String::new()
}

/// Analyze text for style suggestions
///
/// This function is wrapped in catch_unwind to prevent panics from crashing the app.
#[cfg(feature = "llm")]
fn llm_analyze_style(text: String, style: ffi::StyleTemplate) -> FfiStyleAnalysisResult {
    let internal_style = ffi_style_to_internal(style);
    let start = std::time::Instant::now();

    // Capture memory before analysis
    let mut sys_before = System::new_all();
    sys_before.refresh_all();
    let pid = sysinfo::get_current_pid().ok();
    let memory_before = pid
        .and_then(|p| sys_before.process(p))
        .map(|p| p.memory())
        .unwrap_or(0);

    tracing::info!(
        "llm_analyze_style: START text_len={}, style={:?}, memory_before={}MB",
        text.len(),
        internal_style,
        memory_before / 1024 / 1024
    );

    // Wrap in catch_unwind to handle any panics during analysis
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.read());
        if let Some(ref engine) = *guard {
            tracing::debug!("llm_analyze_style: Engine found, calling analyze_style");
            match TOKIO_RUNTIME.block_on(engine.analyze_style(&text, internal_style)) {
                Ok(suggestions) => {
                    let analysis_time_ms = start.elapsed().as_millis() as u64;
                    let model_id = TOKIO_RUNTIME
                        .block_on(engine.loaded_model_id())
                        .unwrap_or_default();

                    tracing::info!(
                        "llm_analyze_style: SUCCESS suggestions={}, time={}ms, model={}",
                        suggestions.len(),
                        analysis_time_ms,
                        model_id
                    );

                    FfiStyleAnalysisResult {
                        suggestions: suggestions
                            .into_iter()
                            .map(|s| FfiStyleSuggestion { inner: s })
                            .collect(),
                        analysis_time_ms,
                        model_id,
                        style: internal_style,
                        error: None,
                    }
                }
                Err(e) => {
                    tracing::error!("llm_analyze_style: Engine returned error: {}", e);
                    FfiStyleAnalysisResult {
                        suggestions: Vec::new(),
                        analysis_time_ms: start.elapsed().as_millis() as u64,
                        model_id: String::new(),
                        style: internal_style,
                        error: Some(e),
                    }
                }
            }
        } else {
            tracing::warn!("llm_analyze_style: LLM engine not initialized");
            FfiStyleAnalysisResult {
                suggestions: Vec::new(),
                analysis_time_ms: 0,
                model_id: String::new(),
                style: internal_style,
                error: Some("LLM engine not initialized".to_string()),
            }
        }
    }));

    // Capture memory after analysis
    let mut sys_after = System::new_all();
    sys_after.refresh_all();
    let memory_after = pid
        .and_then(|p| sys_after.process(p))
        .map(|p| p.memory())
        .unwrap_or(0);
    let memory_delta_mb = (memory_after as i64 - memory_before as i64) / 1024 / 1024;

    tracing::info!(
        "llm_analyze_style: END memory_after={}MB, delta={}MB, elapsed={}ms",
        memory_after / 1024 / 1024,
        memory_delta_mb,
        start.elapsed().as_millis()
    );

    match result {
        Ok(analysis_result) => analysis_result,
        Err(panic_info) => {
            let panic_msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = panic_info.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic during style analysis".to_string()
            };
            tracing::error!("PANIC caught during style analysis: {}", panic_msg);
            FfiStyleAnalysisResult {
                suggestions: Vec::new(),
                analysis_time_ms: start.elapsed().as_millis() as u64,
                model_id: String::new(),
                style: internal_style,
                error: Some(format!("Analysis failed (internal error): {}", panic_msg)),
            }
        }
    }
}

#[cfg(not(feature = "llm"))]
fn llm_analyze_style(_text: String, style: ffi::StyleTemplate) -> FfiStyleAnalysisResult {
    FfiStyleAnalysisResult {
        suggestions: Vec::new(),
        analysis_time_ms: 0,
        model_id: String::new(),
        style: ffi_style_to_internal(style),
        error: Some("LLM feature not enabled".to_string()),
    }
}

/// Record acceptance
#[cfg(feature = "llm")]
fn llm_record_acceptance(original: String, suggested: String, style: ffi::StyleTemplate) {
    let internal_style = ffi_style_to_internal(style);
    let guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.read());
    if let Some(ref engine) = *guard {
        TOKIO_RUNTIME.block_on(engine.record_acceptance(&original, &suggested, internal_style));
    }
}

#[cfg(not(feature = "llm"))]
fn llm_record_acceptance(_original: String, _suggested: String, _style: ffi::StyleTemplate) {}

/// Record rejection
#[cfg(feature = "llm")]
fn llm_record_rejection(
    original: String,
    suggested: String,
    style: ffi::StyleTemplate,
    category: ffi::RejectionCategory,
) {
    let internal_style = ffi_style_to_internal(style);
    let internal_category = ffi_rejection_to_internal(category);
    let guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.read());
    if let Some(ref engine) = *guard {
        TOKIO_RUNTIME.block_on(engine.record_rejection(
            &original,
            &suggested,
            internal_style,
            internal_category,
        ));
    }
}

#[cfg(not(feature = "llm"))]
fn llm_record_rejection(
    _original: String,
    _suggested: String,
    _style: ffi::StyleTemplate,
    _category: ffi::RejectionCategory,
) {
}

/// Sync vocabulary
#[cfg(feature = "llm")]
fn llm_sync_vocabulary(words: Vec<String>) {
    let guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.read());
    if let Some(ref engine) = *guard {
        TOKIO_RUNTIME.block_on(engine.sync_vocabulary(&words));
    }
}

#[cfg(not(feature = "llm"))]
fn llm_sync_vocabulary(_words: Vec<String>) {}

#[cfg(feature = "llm")]
fn llm_delete_model(model_id: String) -> bool {
    let guard = TOKIO_RUNTIME.block_on(MODEL_MANAGER.read());
    if let Some(ref manager) = *guard {
        manager.delete_model(&model_id).is_ok()
    } else {
        false
    }
}

#[cfg(not(feature = "llm"))]
fn llm_delete_model(_model_id: String) -> bool {
    false
}

#[cfg(feature = "llm")]
fn llm_get_models_dir() -> String {
    let guard = TOKIO_RUNTIME.block_on(MODEL_MANAGER.read());
    if let Some(ref manager) = *guard {
        manager.models_dir().to_string_lossy().to_string()
    } else {
        String::new()
    }
}

#[cfg(not(feature = "llm"))]
fn llm_get_models_dir() -> String {
    String::new()
}

#[cfg(feature = "llm")]
fn llm_import_model(model_id: String, source_path: String) -> bool {
    let path = PathBuf::from(source_path);
    let guard = TOKIO_RUNTIME.block_on(MODEL_MANAGER.read());
    if let Some(ref manager) = *guard {
        manager.import_model(&model_id, &path).is_ok()
    } else {
        false
    }
}

#[cfg(not(feature = "llm"))]
fn llm_import_model(_model_id: String, _source_path: String) -> bool {
    false
}

/// Convert FFI InferencePreset to internal InferencePreset
#[cfg(feature = "llm")]
fn ffi_preset_to_internal(preset: ffi::InferencePreset) -> crate::llm::config::InferencePreset {
    match preset {
        ffi::InferencePreset::Fast => crate::llm::config::InferencePreset::Fast,
        ffi::InferencePreset::Balanced => crate::llm::config::InferencePreset::Balanced,
        ffi::InferencePreset::Quality => crate::llm::config::InferencePreset::Quality,
    }
}

/// Set the inference preset (Fast/Balanced/Quality)
///
/// This controls the speed vs quality tradeoff:
/// - **Fast**: Shorter responses, more deterministic (faster inference)
/// - **Balanced**: Default settings, good tradeoff
/// - **Quality**: More thorough analysis, detailed suggestions
#[cfg(feature = "llm")]
fn llm_set_inference_preset(preset: ffi::InferencePreset) {
    let internal_preset = ffi_preset_to_internal(preset);
    tracing::info!("Setting inference preset to {:?}", internal_preset);

    let mut guard = TOKIO_RUNTIME.block_on(LLM_ENGINE.write());
    if let Some(ref mut engine) = *guard {
        engine.set_preset(internal_preset);
    }
}

#[cfg(not(feature = "llm"))]
fn llm_set_inference_preset(_preset: ffi::InferencePreset) {}
