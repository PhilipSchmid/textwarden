// LLMEngine.swift
// High-level Swift wrapper for Rust LLM style checking FFI

import Foundation
import os.log

/// Error type for LLM operations
public struct LLMError: Error, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

/// Swift wrapper for the Rust LLM style analysis engine
public class LLMEngine {

    /// Shared singleton instance
    public static let shared = LLMEngine()

    /// Whether the LLM subsystem has been initialized
    private(set) var isInitialized = false

    /// Whether the LLM feature is compiled into the Rust library
    /// This is determined after the first initialization attempt
    private(set) var isLLMFeatureAvailable = true

    private init() {}

    // MARK: - Initialization

    /// Initialize the LLM subsystem with the app support directory
    ///
    /// This must be called before any other LLM functions.
    /// The app support directory is used to store downloaded models.
    ///
    /// - Parameter appSupportDir: Path to the application support directory
    /// - Returns: true if initialization succeeded
    @discardableResult
    public func initialize(appSupportDir: URL) -> Bool {
        let path = appSupportDir.path
        Logger.info("Initializing LLM engine with path: \(path)", category: Logger.llm)
        let result = llm_initialize(RustString(path))
        isInitialized = result

        if result {
            Logger.info("LLM engine initialized successfully", category: Logger.llm)
            isLLMFeatureAvailable = true
        } else {
            // Check if this is because LLM feature isn't compiled
            // When LLM isn't compiled, the Rust function logs "LLM feature not enabled" and returns false
            Logger.warning("LLM engine initialization failed - LLM feature may not be compiled. Rebuild with 'make build-all' to enable.", category: Logger.llm)
            isLLMFeatureAvailable = false
        }
        return result
    }

    // MARK: - Model Management

    /// Get list of all available models with their download status
    ///
    /// - Returns: Array of model information
    public func getAvailableModels() -> [LLMModelInfo] {
        let ffiModels = llm_get_available_models()
        return ffiModels.map { LLMModelInfo(ffiInfo: $0) }
    }

    /// Check if a specific model is downloaded
    ///
    /// - Parameter modelId: The model identifier
    /// - Returns: true if the model is downloaded locally
    public func isModelDownloaded(_ modelId: String) -> Bool {
        llm_is_model_downloaded(RustString(modelId))
    }

    /// Load a model into memory for inference
    ///
    /// This is a blocking operation that may take several seconds.
    /// Only one model can be loaded at a time.
    ///
    /// - Parameter modelId: The model identifier to load
    /// - Returns: Success or error
    public func loadModel(_ modelId: String) -> Result<Void, LLMError> {
        Logger.info("Loading LLM model (sync): \(modelId)", category: Logger.llm)
        let result = llm_load_model(RustString(modelId)).toString()
        if result.isEmpty {
            Logger.info("LLM model loaded successfully: \(modelId)", category: Logger.llm)
            return .success(())
        } else {
            Logger.error("Failed to load LLM model \(modelId): \(result)", category: Logger.llm)
            return .failure(LLMError(result))
        }
    }

    /// Load a model asynchronously
    ///
    /// - Parameter modelId: The model identifier to load
    /// - Returns: Success or error
    @available(macOS 10.15, *)
    public func loadModel(_ modelId: String) async -> Result<Void, LLMError> {
        Logger.info("Loading LLM model (async): \(modelId)", category: Logger.llm)
        let loadResult = await Task.detached(priority: .userInitiated) { [modelId] in
            let result = llm_load_model(RustString(modelId)).toString()
            if result.isEmpty {
                return Result<Void, LLMError>.success(())
            } else {
                return Result<Void, LLMError>.failure(LLMError(result))
            }
        }.value

        switch loadResult {
        case .success:
            Logger.info("LLM model loaded successfully (async): \(modelId)", category: Logger.llm)
        case .failure(let error):
            Logger.error("Failed to load LLM model (async) \(modelId): \(error.message)", category: Logger.llm)
        }

        return loadResult
    }

    /// Unload the current model from memory
    ///
    /// Call this to free memory when style checking is not needed.
    public func unloadModel() {
        Logger.info("Unloading LLM model from memory", category: Logger.llm)
        llm_unload_model()
        Logger.debug("LLM model unloaded", category: Logger.llm)
    }

    /// Check if any model is currently loaded
    ///
    /// - Returns: true if a model is loaded and ready for inference
    public func isModelLoaded() -> Bool {
        llm_is_model_loaded()
    }

    /// Get the ID of the currently loaded model
    ///
    /// - Returns: Model ID or empty string if no model is loaded
    public func getLoadedModelId() -> String {
        llm_get_loaded_model_id().toString()
    }

    // MARK: - Style Analysis

    /// Analyze text for style suggestions
    ///
    /// This is a blocking operation. Use the async version for UI contexts.
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - style: The writing style to target
    /// - Returns: Style analysis result with suggestions
    public func analyzeStyle(_ text: String, style: WritingStyle = .default) -> StyleAnalysisResultModel {
        Logger.info("LLMEngine.analyzeStyle: Starting analysis, text_len=\(text.count), style=\(style.displayName)", category: Logger.llm)
        let startTime = CFAbsoluteTimeGetCurrent()

        let ffiResult = llm_analyze_style(RustString(text), style.ffiStyle)
        let result = StyleAnalysisResultModel(ffiResult: ffiResult)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Logger.info("LLMEngine.analyzeStyle: Completed in \(Int(elapsed))ms, suggestions=\(result.suggestions.count), isError=\(result.isError), error=\(result.error ?? "none")", category: Logger.llm)

        return result
    }

    /// Analyze text for style suggestions asynchronously
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - style: The writing style to target
    /// - Returns: Style analysis result with suggestions
    @available(macOS 10.15, *)
    public func analyzeStyle(_ text: String, style: WritingStyle = .default) async -> StyleAnalysisResultModel {
        await Task.detached(priority: .userInitiated) { [text, style] in
            let ffiResult = llm_analyze_style(RustString(text), style.ffiStyle)
            return StyleAnalysisResultModel(ffiResult: ffiResult)
        }.value
    }

    // MARK: - Sentence Rephrasing

    /// Rephrase a sentence to improve readability while preserving meaning
    ///
    /// This is used for readability errors (like long sentences) where the grammar engine
    /// doesn't provide suggestions. The LLM will rewrite the sentence to be clearer,
    /// potentially splitting it into multiple sentences.
    ///
    /// - Parameter sentence: The sentence to rephrase
    /// - Returns: The rephrased text, or nil if rephrasing failed
    public func rephraseSentence(_ sentence: String) -> String? {
        Logger.info("LLMEngine.rephraseSentence: Starting rephrase, sentence_len=\(sentence.count)", category: Logger.llm)
        let startTime = CFAbsoluteTimeGetCurrent()

        let result = llm_rephrase_sentence(RustString(sentence)).toString()

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        Logger.info("LLMEngine.rephraseSentence: Completed in \(Int(elapsed))ms", category: Logger.llm)

        // Check for error prefix
        if result.hasPrefix("ERROR:") {
            let errorMsg = String(result.dropFirst(6))
            Logger.warning("LLMEngine.rephraseSentence: Failed - \(errorMsg)", category: Logger.llm)
            return nil
        }

        return result
    }

    /// Rephrase a sentence asynchronously
    ///
    /// - Parameter sentence: The sentence to rephrase
    /// - Returns: The rephrased text, or nil if rephrasing failed
    @available(macOS 10.15, *)
    public func rephraseSentence(_ sentence: String) async -> String? {
        await Task.detached(priority: .userInitiated) { [sentence] in
            let result = llm_rephrase_sentence(RustString(sentence)).toString()

            if result.hasPrefix("ERROR:") {
                return nil
            }

            return result
        }.value
    }

    // MARK: - Preference Learning

    /// Record that a suggestion was accepted by the user
    ///
    /// This helps the LLM learn user preferences over time.
    ///
    /// - Parameters:
    ///   - original: The original text
    ///   - suggested: The accepted suggested text
    ///   - style: The style that was used
    public func recordAcceptance(original: String, suggested: String, style: WritingStyle) {
        llm_record_acceptance(
            RustString(original),
            RustString(suggested),
            style.ffiStyle
        )
    }

    /// Record that a suggestion was rejected by the user
    ///
    /// This helps the LLM avoid similar suggestions in the future.
    ///
    /// - Parameters:
    ///   - original: The original text
    ///   - suggested: The rejected suggested text
    ///   - style: The style that was used
    ///   - category: The reason for rejection
    public func recordRejection(
        original: String,
        suggested: String,
        style: WritingStyle,
        category: SuggestionRejectionCategory
    ) {
        llm_record_rejection(
            RustString(original),
            RustString(suggested),
            style.ffiStyle,
            category.ffiCategory
        )
    }

    // MARK: - Vocabulary Sync

    /// Sync custom vocabulary from Harper dictionary
    ///
    /// Words in the custom vocabulary will be included in the LLM prompt
    /// to prevent false positives on custom/technical terms.
    ///
    /// - Parameter words: Array of custom words from the dictionary
    public func syncVocabulary(_ words: [String]) {
        let rustVec = RustVec<RustString>()
        for word in words {
            rustVec.push(value: RustString(word))
        }
        llm_sync_vocabulary(rustVec)
    }

    // MARK: - Inference Settings

    /// Set the inference preset (Fast/Balanced/Quality)
    ///
    /// This controls the speed vs quality tradeoff:
    /// - **Fast**: Quick responses, shorter suggestions. Best for rapid feedback during editing.
    /// - **Balanced**: Good balance of speed and detail. Recommended for most users.
    /// - **Quality**: Thorough analysis with detailed explanations. Best for reviewing important writing.
    ///
    /// - Parameter preset: The inference preset to use
    public func setInferencePreset(_ preset: LLMInferencePreset) {
        Logger.info("Setting inference preset to: \(preset.displayName)", category: Logger.llm)
        llm_set_inference_preset(preset.ffiPreset)
    }

    // MARK: - Model Management

    /// Delete a downloaded model
    ///
    /// - Parameter modelId: The model identifier to delete
    /// - Returns: true if deletion succeeded
    public func deleteModel(_ modelId: String) -> Bool {
        llm_delete_model(RustString(modelId))
    }

    /// Get the models directory path
    ///
    /// - Returns: Path to the models directory
    public func getModelsDirectory() -> String {
        llm_get_models_dir().toString()
    }

    /// Import a model from a local file
    ///
    /// - Parameters:
    ///   - modelId: The model identifier (must match a known model config)
    ///   - sourcePath: Path to the source GGUF file
    /// - Returns: true if import succeeded
    public func importModel(_ modelId: String, from sourcePath: URL) -> Bool {
        llm_import_model(RustString(modelId), RustString(sourcePath.path))
    }
}

// MARK: - Convenience Extensions

extension LLMEngine {

    /// Check if style checking is available (initialized and model loaded)
    public var isReady: Bool {
        isInitialized && isModelLoaded()
    }

    /// Get the first downloaded model, if any
    public var firstDownloadedModel: LLMModelInfo? {
        getAvailableModels().first { $0.isDownloaded }
    }

    /// Get the recommended model for this system
    public var recommendedModelId: String {
        "qwen2.5-1.5b" // Balanced model for most systems
    }

    /// Ensure a model is loaded, loading the recommended one if needed
    ///
    /// - Returns: Success or error
    @available(macOS 10.15, *)
    public func ensureModelLoaded() async -> Result<Void, LLMError> {
        if isModelLoaded() {
            return .success(())
        }

        // Try to load the first downloaded model
        if let model = firstDownloadedModel {
            return await loadModel(model.id)
        }

        return .failure(LLMError("No models downloaded. Please download a model first."))
    }
}
