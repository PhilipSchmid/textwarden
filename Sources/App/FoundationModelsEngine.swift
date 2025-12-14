// FoundationModelsEngine.swift
// Apple Foundation Models integration for style analysis

import Foundation
import Combine
import os.log

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Style Engine Status

/// Status of the Foundation Models style engine
enum StyleEngineStatus: Equatable {
    case available
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case unknown(String)

    /// User-friendly message describing the status
    var userMessage: String {
        switch self {
        case .available:
            return "Ready"
        case .appleIntelligenceNotEnabled:
            return "Enable Apple Intelligence in System Settings → Apple Intelligence & Siri"
        case .deviceNotEligible:
            return "Style suggestions require a Mac with Apple Silicon"
        case .modelNotReady:
            return "Apple Intelligence is preparing the language model..."
        case .unknown(let reason):
            return "Style suggestions unavailable: \(reason)"
        }
    }

    /// Whether the user can retry later (transient states)
    var canRetry: Bool {
        switch self {
        case .modelNotReady:
            return true
        case .available, .appleIntelligenceNotEnabled, .deviceNotEligible, .unknown:
            return false
        }
    }

    /// Whether style checking is currently possible
    var isAvailable: Bool {
        self == .available
    }

    /// SF Symbol name for status indicator
    var symbolName: String {
        switch self {
        case .available:
            return "checkmark.circle.fill"
        case .appleIntelligenceNotEnabled:
            return "apple.intelligence"
        case .deviceNotEligible:
            return "exclamationmark.triangle.fill"
        case .modelNotReady:
            return "clock.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

// MARK: - Foundation Models Engine

/// Engine for style analysis using Apple's Foundation Models framework
@available(macOS 26.0, *)
@MainActor
final class FoundationModelsEngine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var status: StyleEngineStatus = .unknown("")
    @Published private(set) var isAnalyzing: Bool = false

    // MARK: - Initialization

    init() {
        checkAvailability()
    }

    // MARK: - Availability

    /// Check and update the current availability status
    func checkAvailability() {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            status = .available
            Logger.info("Foundation Models available", category: Logger.analysis)

        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                status = .appleIntelligenceNotEnabled
                Logger.info("Apple Intelligence not enabled", category: Logger.analysis)

            case .deviceNotEligible:
                status = .deviceNotEligible
                Logger.info("Device not eligible for Apple Intelligence", category: Logger.analysis)

            case .modelNotReady:
                status = .modelNotReady
                Logger.info("Foundation model not ready yet", category: Logger.analysis)

            @unknown default:
                status = .unknown("\(reason)")
                Logger.warning("Unknown Foundation Models unavailability: \(reason)", category: Logger.analysis)
            }
        }
    }

    // MARK: - Prewarming

    /// Prewarm the model for faster first response
    /// Call this on app launch or when the user is likely to request style checking
    func prewarm() async {
        guard status == .available else {
            Logger.debug("Skipping prewarm - status is \(status)", category: Logger.analysis)
            return
        }

        do {
            let session = LanguageModelSession()
            try await session.prewarm()
            Logger.info("Foundation Models session prewarmed", category: Logger.analysis)
        } catch {
            Logger.warning("Failed to prewarm Foundation Models: \(error)", category: Logger.analysis)
        }
    }

    // MARK: - Style Analysis

    /// Analyze text for style improvements
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - style: The writing style to optimize for
    ///   - temperaturePreset: Controls creativity vs consistency of suggestions
    ///   - customVocabulary: Terms that should not be changed
    /// - Returns: Array of style suggestions
    /// - Throws: If analysis fails
    func analyzeStyle(
        _ text: String,
        style: WritingStyle,
        temperaturePreset: StyleTemperaturePreset = .balanced,
        customVocabulary: [String] = []
    ) async throws -> [StyleSuggestionModel] {
        guard status == .available else {
            Logger.warning("Cannot analyze - Foundation Models not available: \(status)", category: Logger.analysis)
            throw FoundationModelsError.notAvailable(status)
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Build comprehensive instructions
        let instructions = StyleInstructions.build(
            for: style,
            customVocabulary: customVocabulary
        )

        // Create session with instructions
        let session = LanguageModelSession(instructions: instructions)

        // Configure generation options with temperature
        let options = GenerationOptions(temperature: temperaturePreset.temperature)

        Logger.debug("Analyzing text (\(text.count) chars) with style: \(style.displayName), temp: \(temperaturePreset.temperature)", category: Logger.analysis)

        do {
            let response = try await session.respond(
                to: "Analyze this text for style improvements:\n\n\(text)",
                generating: FMStyleAnalysisResult.self,
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Convert and validate results
            let suggestions = response.content.toStyleSuggestionModels(in: text, style: style)

            Logger.info("Foundation Models analysis complete: \(suggestions.count) suggestions in \(String(format: "%.2f", elapsed))s", category: Logger.analysis)

            return suggestions

        } catch let error as LanguageModelSession.GenerationError {
            Logger.error("Foundation Models generation error: \(error)", category: Logger.analysis)
            throw FoundationModelsError.generationFailed(error.localizedDescription)
        } catch {
            Logger.error("Foundation Models analysis failed: \(error)", category: Logger.analysis)
            throw FoundationModelsError.analysisError(error.localizedDescription)
        }
    }
}

// MARK: - Errors

/// Errors that can occur during Foundation Models operations
enum FoundationModelsError: LocalizedError {
    case notAvailable(StyleEngineStatus)
    case generationFailed(String)
    case analysisError(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let status):
            return "Foundation Models not available: \(status.userMessage)"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .analysisError(let message):
            return "Analysis error: \(message)"
        }
    }
}

// MARK: - Temperature Preset

/// Temperature presets for Foundation Models generation
/// Controls the creativity vs consistency of style suggestions
enum StyleTemperaturePreset: String, CaseIterable, Identifiable {
    case consistent = "consistent"
    case balanced = "balanced"
    case creative = "creative"

    var id: String { rawValue }

    /// The actual temperature value for Foundation Models
    var temperature: Double {
        switch self {
        case .consistent: return 0.3
        case .balanced: return 0.7
        case .creative: return 1.2
        }
    }

    /// Display name for UI
    var label: String {
        switch self {
        case .consistent: return "Consistent"
        case .balanced: return "Balanced"
        case .creative: return "Creative"
        }
    }

    /// User-facing description
    var description: String {
        switch self {
        case .consistent:
            return "Predictable, stable suggestions"
        case .balanced:
            return "Good balance of variety"
        case .creative:
            return "More varied, experimental suggestions"
        }
    }

    /// SF Symbol name for UI
    var symbolName: String {
        switch self {
        case .consistent: return "tortoise.fill"
        case .balanced: return "dial.medium.fill"
        case .creative: return "sparkles"
        }
    }
}
