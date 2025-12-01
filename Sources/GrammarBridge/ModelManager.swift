// ModelManager.swift
// Swift wrapper for LLM model management with observable download progress

import Foundation
import Combine
import os.log

/// Observable manager for LLM models with download progress tracking
@available(macOS 10.15, *)
public class ModelManager: ObservableObject {

    /// Shared singleton instance
    public static let shared = ModelManager()

    /// All available models with their current status
    @Published public private(set) var models: [LLMModelInfo] = []

    /// Currently downloading model IDs (supports parallel downloads)
    @Published public private(set) var downloadingModelIds: Set<String> = []

    /// Download progress per model (keyed by model ID)
    @Published public private(set) var downloadProgresses: [String: ModelDownloadProgress] = [:]

    /// Error message per model (keyed by model ID)
    @Published public private(set) var modelErrors: [String: String] = [:]

    /// Currently loaded model ID
    @Published public private(set) var loadedModelId: String?

    /// Whether a model is being loaded
    @Published public private(set) var isLoadingModel = false

    /// Whether a model is being unloaded
    @Published public private(set) var isUnloadingModel = false

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()

    /// Active download tasks (keyed by model ID)
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    /// Download delegate for progress tracking
    private lazy var downloadDelegate: ModelDownloadDelegate = {
        ModelDownloadDelegate(manager: self)
    }()

    /// Custom URLSession with delegate for downloads
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: downloadDelegate, delegateQueue: .main)
    }()

    /// Models directory URL
    private lazy var modelsDirectoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TextWarden/Models", isDirectory: true)
    }()

    /// Default model configurations
    /// File sizes verified from Hugging Face x-linked-size headers (November 2025)
    /// Speed/Quality ratings are relative estimates based on model architecture and size
    private static let defaultModelConfigs: [ModelConfig] = [
        ModelConfig(
            id: "qwen2.5-1.5b",
            name: "Qwen 2.5 1.5B",
            vendor: "Alibaba",
            filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            downloadUrl: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            sizeBytes: 1_117_320_736,  // Verified from HuggingFace
            speedRating: 8.5,
            qualityRating: 7.5,
            languages: ["en", "zh", "de", "fr", "es", "pt", "it", "ru", "ja", "ko"],
            isMultilingual: true,
            description: "Balanced model with excellent speed and good quality. Recommended for most users.",
            tier: .balanced,
            isDefault: false
        ),
        ModelConfig(
            id: "phi3-mini",
            name: "Phi-3 Mini 3.8B",
            vendor: "Microsoft",
            filename: "Phi-3-mini-4k-instruct-q4.gguf",
            downloadUrl: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf",
            sizeBytes: 2_393_231_072,  // Verified from HuggingFace
            speedRating: 6.5,
            qualityRating: 9.0,
            languages: ["en"],
            isMultilingual: false,
            description: "High accuracy model. Best quality suggestions but slower.",
            tier: .accurate,
            isDefault: false
        ),
        ModelConfig(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            vendor: "Meta",
            filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            downloadUrl: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            sizeBytes: 2_019_377_696,  // Verified from HuggingFace
            speedRating: 7.0,
            qualityRating: 8.5,
            languages: ["en", "de", "fr", "it", "pt", "hi", "es", "th"],
            isMultilingual: true,
            description: "Compact model with strong multilingual support.",
            tier: .balanced,
            isDefault: false
        ),
        ModelConfig(
            id: "gemma2-2b",
            name: "Gemma 2 2B",
            vendor: "Google",
            filename: "gemma-2-2b-it-Q4_K_M.gguf",
            downloadUrl: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
            sizeBytes: 1_708_582_752,  // Verified from HuggingFace
            speedRating: 8.0,
            qualityRating: 7.0,
            languages: ["en"],
            isMultilingual: false,
            description: "Efficient model. Good balance of speed and quality.",
            tier: .balanced,
            isDefault: false
        ),
        ModelConfig(
            id: "llama-3.2-1b",
            name: "Llama 3.2 1B",
            vendor: "Meta",
            filename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            downloadUrl: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            sizeBytes: 807_694_464,  // Verified from HuggingFace
            speedRating: 9.5,
            qualityRating: 6.0,
            languages: ["en", "de", "fr", "it", "pt", "hi", "es", "th"],
            isMultilingual: true,
            description: "Ultra-fast lightweight model. Best for quick suggestions on older hardware.",
            tier: .lightweight,
            isDefault: false
        )
    ]

    private init() {
        createModelsDirectoryIfNeeded()
        refreshModels()
    }

    // MARK: - Directory Management

    private func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            Logger.error("Error creating models directory", error: error, category: Logger.llm)
        }
    }

    // MARK: - Model List

    /// Refresh the list of available models and check which are downloaded locally
    public func refreshModels() {
        let ffiModels = LLMEngine.shared.getAvailableModels()

        // Use FFI models if available, otherwise use default configs with local check
        if ffiModels.isEmpty {
            models = Self.defaultModelConfigs.map { config in
                let isDownloaded = isModelDownloadedLocally(filename: config.filename)
                return LLMModelInfo(
                    id: config.id,
                    name: config.name,
                    vendor: config.vendor,
                    filename: config.filename,
                    downloadUrl: config.downloadUrl,
                    sizeBytes: config.sizeBytes,
                    speedRating: config.speedRating,
                    qualityRating: config.qualityRating,
                    languages: config.languages,
                    isMultilingual: config.isMultilingual,
                    description: config.description,
                    tier: config.tier,
                    isDownloaded: isDownloaded,
                    isDefault: config.isDefault
                )
            }
        } else {
            models = ffiModels
        }

        loadedModelId = LLMEngine.shared.getLoadedModelId()
        if loadedModelId?.isEmpty == true {
            loadedModelId = nil
        }
    }

    /// Check if a model file exists locally
    private func isModelDownloadedLocally(filename: String) -> Bool {
        let fileURL = modelsDirectoryURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Get a specific model by ID
    public func model(withId id: String) -> LLMModelInfo? {
        models.first { $0.id == id }
    }

    /// Get all downloaded models
    public var downloadedModels: [LLMModelInfo] {
        models.filter { $0.isDownloaded }
    }

    /// Check if any model is downloaded
    public var hasDownloadedModels: Bool {
        models.contains { $0.isDownloaded }
    }

    // MARK: - Model Loading

    /// Load a model into memory
    public func loadModel(_ modelId: String) async {
        guard !isLoadingModel else {
            Logger.debug("Model load skipped - already loading", category: Logger.llm)
            return
        }

        // Check if the same model is already loaded - skip redundant load
        if loadedModelId == modelId {
            Logger.debug("Model load skipped - \(modelId) already loaded", category: Logger.llm)
            return
        }

        // If a different model is loaded, unload it first to free memory
        if loadedModelId != nil {
            Logger.info("Unloading current model before loading new one", category: Logger.llm)
            unloadModel()
        }

        // Check if model exists
        guard let model = models.first(where: { $0.id == modelId }) else {
            Logger.error("Cannot load model - model not found: \(modelId)", category: Logger.llm)
            await MainActor.run {
                modelErrors[modelId] = "Model not found"
            }
            return
        }

        // Check if model is downloaded
        guard model.isDownloaded else {
            Logger.warning("Cannot load model - not downloaded: \(modelId)", category: Logger.llm)
            await MainActor.run {
                modelErrors[modelId] = "Model not downloaded"
            }
            return
        }

        // Double-check model file actually exists on disk (defensive validation)
        let modelPath = modelsDirectoryURL.appendingPathComponent(model.filename)
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            Logger.error("Cannot load model - file missing on disk: \(modelPath.path)", category: Logger.llm)
            await MainActor.run {
                modelErrors[modelId] = "Model file not found on disk"
                // Refresh models to update download status
                refreshModels()
            }
            return
        }

        // Verify file size is reasonable (at least 100MB for a valid GGUF model)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: modelPath.path),
           let fileSize = attrs[.size] as? UInt64,
           fileSize < 100_000_000 {
            Logger.error("Model file appears corrupted (too small): \(fileSize) bytes", category: Logger.llm)
            await MainActor.run {
                modelErrors[modelId] = "Model file appears corrupted"
            }
            return
        }

        Logger.info("Starting model load: \(model.name) (\(modelId))", category: Logger.llm)

        await MainActor.run {
            isLoadingModel = true
            modelErrors.removeValue(forKey: modelId)
        }

        let result = await LLMEngine.shared.loadModel(modelId)

        await MainActor.run {
            isLoadingModel = false
            switch result {
            case .success:
                loadedModelId = modelId
                Logger.info("Model loaded successfully: \(model.name)", category: Logger.llm)

                // Apply the user's preferred inference preset
                let presetString = UserPreferences.shared.styleInferencePreset
                if let preset = LLMInferencePreset(rawValue: presetString) {
                    LLMEngine.shared.setInferencePreset(preset)
                    Logger.debug("Applied inference preset: \(preset.displayName)", category: Logger.llm)
                }
            case .failure(let error):
                modelErrors[modelId] = error.message
                Logger.error("Model load failed: \(model.name) - \(error.message)", category: Logger.llm)
            }
        }
    }

    /// Unload the current model from memory
    /// Thread-safe: can be called from any thread
    public func unloadModel() {
        let modelName: String?
        if let loadedId = loadedModelId, let model = models.first(where: { $0.id == loadedId }) {
            modelName = model.name
        } else {
            modelName = nil
        }

        if let name = modelName {
            Logger.info("Unloading model: \(name)", category: Logger.llm)
        }

        // Set unloading state on main thread
        DispatchQueue.main.async { [weak self] in
            self?.isUnloadingModel = true
        }

        // FFI call can happen on any thread
        LLMEngine.shared.unloadModel()

        // Update @Published properties on main thread
        DispatchQueue.main.async { [weak self] in
            self?.loadedModelId = nil
            self?.isUnloadingModel = false
            Logger.debug("Model unloaded, loadedModelId cleared", category: Logger.llm)
        }
    }

    /// Check if a specific model is loaded
    public func isModelLoaded(_ modelId: String) -> Bool {
        loadedModelId == modelId
    }

    // MARK: - Download State Queries

    /// Check if a model is currently downloading
    public func isDownloading(_ modelId: String) -> Bool {
        downloadingModelIds.contains(modelId)
    }

    /// Get download progress for a model
    public func downloadProgress(for modelId: String) -> ModelDownloadProgress? {
        downloadProgresses[modelId]
    }

    /// Get error for a model
    public func error(for modelId: String) -> String? {
        modelErrors[modelId]
    }

    // MARK: - Model Download (Parallel Support)

    /// Start downloading a model (supports parallel downloads)
    @discardableResult
    public func startDownload(_ modelId: String) -> Bool {
        // Don't start if already downloading
        guard !downloadingModelIds.contains(modelId) else {
            return false
        }

        // Clear any previous error for this model
        modelErrors.removeValue(forKey: modelId)

        // Always use Swift-native download for proper progress tracking
        // Note: FFI download progress polling is not fully implemented in Rust
        guard let model = models.first(where: { $0.id == modelId }),
              let url = URL(string: model.downloadUrl) else {
            modelErrors[modelId] = "Model not found or invalid URL"
            return false
        }

        downloadingModelIds.insert(modelId)
        startSwiftDownload(model: model, url: url)
        return true
    }

    /// Swift-native download implementation (supports parallel downloads)
    private func startSwiftDownload(model: LLMModelInfo, url: URL) {
        let modelId = model.id
        let expectedBytes = model.sizeBytes
        let destinationURL = modelsDirectoryURL.appendingPathComponent(model.filename)

        // Set initial progress immediately
        downloadProgresses[modelId] = ModelDownloadProgress(
            modelId: modelId,
            bytesDownloaded: 0,
            totalBytes: expectedBytes,
            status: .starting,
            percentage: 0
        )

        // Create download task using delegate-based session
        let task = downloadSession.downloadTask(with: url)

        // Associate task with model info for delegate callbacks
        downloadDelegate.associateTask(task, modelId: modelId, expectedBytes: expectedBytes, destinationURL: destinationURL)

        downloadTasks[modelId] = task
        task.resume()
    }

    /// Cancel a specific download
    public func cancelDownload(_ modelId: String) {
        guard downloadingModelIds.contains(modelId) else { return }

        // Cancel Swift-native download
        if let task = downloadTasks[modelId] {
            task.cancel()
            downloadTasks.removeValue(forKey: modelId)
            downloadingModelIds.remove(modelId)
            downloadProgresses.removeValue(forKey: modelId)
        }
    }

    /// Cancel all downloads
    public func cancelAllDownloads() {
        for modelId in downloadingModelIds {
            cancelDownload(modelId)
        }
    }

    /// Delete a downloaded model
    @discardableResult
    public func deleteModel(_ modelId: String) -> Bool {
        // Cancel any ongoing download
        if downloadingModelIds.contains(modelId) {
            cancelDownload(modelId)
        }

        // Unload if this model is currently loaded
        if loadedModelId == modelId {
            unloadModel()
        }

        // Clear any errors
        modelErrors.removeValue(forKey: modelId)

        // Try FFI delete first
        if LLMEngine.shared.deleteModel(modelId) {
            refreshModels()
            return true
        }

        // Fallback to Swift-native delete
        guard let model = models.first(where: { $0.id == modelId }) else {
            modelErrors[modelId] = "Model not found"
            return false
        }

        let fileURL = modelsDirectoryURL.appendingPathComponent(model.filename)

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            refreshModels()
            return true
        } catch {
            modelErrors[modelId] = "Failed to delete model: \(error.localizedDescription)"
            return false
        }
    }

    /// Import a model from a local file
    @discardableResult
    public func importModel(_ modelId: String, from url: URL) -> Bool {
        if LLMEngine.shared.importModel(modelId, from: url) {
            refreshModels()
            return true
        } else {
            modelErrors[modelId] = "Failed to import model"
            return false
        }
    }

    // MARK: - Convenience

    /// Get the models directory URL
    public var modelsDirectory: URL? {
        let path = LLMEngine.shared.getModelsDirectory()
        if path.isEmpty {
            return modelsDirectoryURL
        }
        return URL(fileURLWithPath: path)
    }

    /// Total size of all downloaded models
    public var totalDownloadedSize: UInt64 {
        downloadedModels.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Formatted total size string
    public var formattedTotalSize: String {
        let gb = Double(totalDownloadedSize) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(totalDownloadedSize) / 1_000_000.0
            return String(format: "%.0f MB", mb)
        }
    }

    /// Clear error for a specific model
    public func clearError(for modelId: String) {
        modelErrors.removeValue(forKey: modelId)
    }

    /// Clear all errors
    public func clearAllErrors() {
        modelErrors.removeAll()
    }

    // MARK: - Internal Callbacks (for delegate)

    /// Update download progress (called by delegate)
    func updateDownloadProgress(modelId: String, bytesDownloaded: UInt64, totalBytes: UInt64, percentage: Double) {
        downloadProgresses[modelId] = ModelDownloadProgress(
            modelId: modelId,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            status: .downloading,
            percentage: percentage
        )
    }

    /// Handle download completion (called by delegate)
    func handleDownloadCompleted(modelId: String, tempURL: URL, destinationURL: URL) {
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            downloadTasks.removeValue(forKey: modelId)
            downloadingModelIds.remove(modelId)
            downloadProgresses.removeValue(forKey: modelId)
            refreshModels()
        } catch {
            modelErrors[modelId] = "Failed to save model: \(error.localizedDescription)"
            downloadTasks.removeValue(forKey: modelId)
            downloadingModelIds.remove(modelId)
            downloadProgresses.removeValue(forKey: modelId)
        }
    }

    /// Handle download error (called by delegate)
    func handleDownloadError(modelId: String, error: Error?) {
        // Check if cancelled
        if let error = error, (error as NSError).code == NSURLErrorCancelled {
            downloadTasks.removeValue(forKey: modelId)
            downloadingModelIds.remove(modelId)
            downloadProgresses.removeValue(forKey: modelId)
            return
        }

        if let error = error {
            modelErrors[modelId] = "Download failed: \(error.localizedDescription)"
        }
        downloadTasks.removeValue(forKey: modelId)
        downloadingModelIds.remove(modelId)
        downloadProgresses.removeValue(forKey: modelId)
    }

    /// Get destination URL for a model
    func destinationURL(for modelId: String) -> URL? {
        guard let model = models.first(where: { $0.id == modelId }) else { return nil }
        return modelsDirectoryURL.appendingPathComponent(model.filename)
    }
}

// MARK: - Model Config (Internal)

private struct ModelConfig {
    let id: String
    let name: String
    let vendor: String
    let filename: String
    let downloadUrl: String
    let sizeBytes: UInt64
    let speedRating: Float
    let qualityRating: Float
    let languages: [String]
    let isMultilingual: Bool
    let description: String
    let tier: LLMModelTier
    let isDefault: Bool
}

// MARK: - Model Tiers

@available(macOS 10.15, *)
extension ModelManager {

    /// Get models grouped by tier
    public var modelsByTier: [LLMModelTier: [LLMModelInfo]] {
        Dictionary(grouping: models) { $0.tier }
    }

    /// Get the balanced (recommended) model
    public var balancedModel: LLMModelInfo? {
        models.first { $0.tier == .balanced }
    }

    /// Get the accurate (high-quality) model
    public var accurateModel: LLMModelInfo? {
        models.first { $0.tier == .accurate }
    }

    /// Get the lightweight model
    public var lightweightModel: LLMModelInfo? {
        models.first { $0.tier == .lightweight }
    }
}

// MARK: - Download Delegate

/// URLSession delegate for tracking download progress
@available(macOS 10.15, *)
private class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {

    private weak var manager: ModelManager?

    /// Registered downloads: task identifier -> (modelId, expectedBytes, destinationURL)
    private var downloadInfo: [Int: (modelId: String, expectedBytes: UInt64, destinationURL: URL)] = [:]

    init(manager: ModelManager) {
        self.manager = manager
        super.init()
    }

    /// Associate task with model info for progress tracking
    func associateTask(_ task: URLSessionDownloadTask, modelId: String, expectedBytes: UInt64, destinationURL: URL) {
        downloadInfo[task.taskIdentifier] = (modelId, expectedBytes, destinationURL)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let manager = manager,
              let info = downloadInfo[downloadTask.taskIdentifier] else { return }

        let modelId = info.modelId
        let expectedBytes = info.expectedBytes

        // Use server-provided total if available, otherwise use expected
        let total: UInt64
        if totalBytesExpectedToWrite > 0 {
            total = UInt64(totalBytesExpectedToWrite)
        } else {
            total = expectedBytes
        }

        let percentage = total > 0 ? Double(totalBytesWritten) / Double(total) * 100 : 0

        // Use callback method
        manager.updateDownloadProgress(
            modelId: modelId,
            bytesDownloaded: UInt64(totalBytesWritten),
            totalBytes: total,
            percentage: percentage
        )
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let manager = manager,
              let info = downloadInfo[downloadTask.taskIdentifier] else { return }

        let modelId = info.modelId
        let destinationURL = info.destinationURL
        downloadInfo.removeValue(forKey: downloadTask.taskIdentifier)

        // Use callback method
        manager.handleDownloadCompleted(modelId: modelId, tempURL: location, destinationURL: destinationURL)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let manager = manager else { return }

        // Find model ID
        guard let info = downloadInfo[task.taskIdentifier] else { return }
        let modelId = info.modelId
        downloadInfo.removeValue(forKey: task.taskIdentifier)

        // Use callback method (handles both error and cancellation)
        manager.handleDownloadError(modelId: modelId, error: error)
    }
}
