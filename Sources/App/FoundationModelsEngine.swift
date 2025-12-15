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
            Logger.debug("Apple Intelligence: Available", category: Logger.llm)

        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                status = .appleIntelligenceNotEnabled
                Logger.info("Apple Intelligence: Not enabled in System Settings", category: Logger.llm)

            case .deviceNotEligible:
                status = .deviceNotEligible
                Logger.info("Apple Intelligence: Device not eligible", category: Logger.llm)

            case .modelNotReady:
                status = .modelNotReady
                Logger.debug("Apple Intelligence: Model not ready yet", category: Logger.llm)

            @unknown default:
                status = .unknown("\(reason)")
                Logger.warning("Apple Intelligence: Unknown unavailability reason", category: Logger.llm)
            }
        }
    }

    // MARK: - Prewarming

    /// Prewarm the model for faster first response
    /// Call this on app launch or when the user is likely to request style checking
    func prewarm() async {
        guard status == .available else {
            Logger.debug("Apple Intelligence: Skipping prewarm, not available", category: Logger.llm)
            return
        }

        let session = LanguageModelSession()
        session.prewarm()
        Logger.debug("Apple Intelligence: Session prewarmed", category: Logger.llm)
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
            Logger.warning("Apple Intelligence: Cannot analyze, not available", category: Logger.llm)
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

        // Configure generation options based on preset
        // Use greedy sampling for consistent mode (deterministic), otherwise use temperature
        let options: GenerationOptions
        if temperaturePreset.usesGreedySampling {
            options = GenerationOptions(sampling: .greedy)
        } else {
            options = GenerationOptions(temperature: temperaturePreset.temperature)
        }

        let samplingInfo = temperaturePreset.usesGreedySampling ? "greedy" : "temp=\(temperaturePreset.temperature)"
        Logger.debug("Apple Intelligence: Analyzing \(text.count) chars, style=\(style.displayName), \(samplingInfo)", category: Logger.llm)

        do {
            let response = try await session.respond(
                to: "Analyze this text for style improvements:\n\n\(text)",
                generating: FMStyleAnalysisResult.self,
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Convert and validate results
            let suggestions = response.content.toStyleSuggestionModels(in: text, style: style)

            Logger.debug("Apple Intelligence: Analysis complete, \(suggestions.count) suggestion(s) in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            return suggestions

        } catch let error as LanguageModelSession.GenerationError {
            Logger.error("Apple Intelligence: Generation error - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.generationFailed(error.localizedDescription)
        } catch {
            Logger.error("Apple Intelligence: Analysis failed - \(error.localizedDescription)", category: Logger.llm)
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

// MARK: - Temperature Configuration

/// Temperature values optimized for grammar and style checking tasks.
///
/// Based on research from WWDC25 and LLM best practices:
/// - Grammar/style checking requires **accuracy over creativity**
/// - Higher temperatures increase hallucination probability
/// - For factual tasks, lower temperatures (0.0-0.3) are recommended
///
/// References:
/// - Apple WWDC25: "Deep dive into the Foundation Models framework"
/// - Research: "Temperature settings at or below 1.50 yield consistent performance"
/// - Best practice: "Use lower temperatures and greedy sampling for factual tasks"
private enum TemperatureValues {
    /// Greedy sampling (temperature 0) - most deterministic, no randomness.
    /// Best for reproducible, accurate suggestions with zero hallucination risk.
    static let greedy: Double = 0.0

    /// Low temperature for reliable, predictable suggestions.
    /// Minimal variance while still allowing some flexibility.
    static let low: Double = 0.3

    /// Moderate temperature for balanced suggestions.
    /// Provides variety while maintaining accuracy for grammar tasks.
    static let moderate: Double = 0.5
}

// MARK: - Temperature Preset

/// Temperature presets for Foundation Models generation.
///
/// These presets are tuned for **grammar and style checking** tasks,
/// which prioritize accuracy over creativity. All values are intentionally
/// kept low to minimize hallucinations and incorrect suggestions.
enum StyleTemperaturePreset: String, CaseIterable, Identifiable {
    case consistent = "consistent"
    case balanced = "balanced"
    case creative = "creative"

    var id: String { rawValue }

    /// The temperature value for Foundation Models generation.
    ///
    /// Values are kept low for grammar/style tasks:
    /// - `consistent`: Uses greedy sampling (0.0) for deterministic output
    /// - `balanced`: Low temperature (0.3) for reliable suggestions
    /// - `creative`: Moderate temperature (0.5) for some variety
    var temperature: Double {
        switch self {
        case .consistent: return TemperatureValues.greedy
        case .balanced: return TemperatureValues.low
        case .creative: return TemperatureValues.moderate
        }
    }

    /// Whether this preset uses greedy (deterministic) sampling
    var usesGreedySampling: Bool {
        self == .consistent
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
            return "Deterministic, most accurate"
        case .balanced:
            return "Reliable with slight variation"
        case .creative:
            return "More variety, still accurate"
        }
    }

    /// SF Symbol name for UI
    var symbolName: String {
        switch self {
        case .consistent: return "checkmark.seal.fill"
        case .balanced: return "dial.medium.fill"
        case .creative: return "wand.and.stars"
        }
    }

    /// Color for statistics charts (RGB values)
    var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .consistent: return (0.2, 0.8, 0.4)   // Green
        case .balanced: return (0.3, 0.5, 0.9)     // Blue
        case .creative: return (0.7, 0.3, 0.8)     // Purple
        }
    }
}
