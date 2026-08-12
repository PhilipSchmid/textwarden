// FoundationModelsEngineFallback.swift
// Builds the non-AI app features when the Foundation Models SDK is unavailable.

import Combine
import Foundation

#if !canImport(FoundationModels)
    @available(macOS 26.0, *)
    @MainActor
    final class FoundationModelsEngine: ObservableObject {
        @Published private(set) var status: StyleEngineStatus = .unknown("")
        @Published private(set) var isAnalyzing = false

        init() {
            checkAvailability()
        }

        func checkAvailability() {
            status = .unknown("Foundation Models framework unavailable")
        }

        func prewarm() async {}

        func analyzeStyle(
            _: String,
            style _: WritingStyle,
            temperaturePreset _: StyleTemperaturePreset = .balanced,
            customVocabulary _: [String] = []
        ) async throws -> [StyleSuggestionModel] {
            throw FoundationModelsError.notAvailable(status)
        }

        func regenerateStyleSuggestion(
            originalText _: String,
            previousSuggestion _: StyleSuggestionModel,
            style _: WritingStyle,
            customVocabulary _: [String] = []
        ) async throws -> StyleSuggestionModel? {
            throw FoundationModelsError.notAvailable(status)
        }

        func generateText(
            instruction _: String,
            context _: GenerationContext,
            style _: WritingStyle,
            variationSeed _: UInt64? = nil
        ) async throws -> String {
            throw FoundationModelsError.notAvailable(status)
        }

        func simplifySentence(
            _: String,
            targetAudience _: TargetAudience,
            writingStyle _: WritingStyle,
            previousSuggestion _: String? = nil
        ) async throws -> [String] {
            throw FoundationModelsError.notAvailable(status)
        }

        func generateReadabilityTips(
            for _: String,
            score _: Int,
            targetAudience _: TargetAudience
        ) async throws -> [String] {
            throw FoundationModelsError.notAvailable(status)
        }
    }
#endif
