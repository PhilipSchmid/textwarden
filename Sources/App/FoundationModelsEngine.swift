// FoundationModelsEngine.swift
// Apple Foundation Models integration for style analysis

import Combine
import Foundation
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
            "Ready"
        case .appleIntelligenceNotEnabled:
            "Enable Apple Intelligence in System Settings → Apple Intelligence & Siri"
        case .deviceNotEligible:
            "Style suggestions require a Mac with Apple Silicon"
        case .modelNotReady:
            "Apple Intelligence is preparing the language model..."
        case let .unknown(reason):
            "Style suggestions unavailable: \(reason)"
        }
    }

    /// Whether the user can retry later (transient states)
    var canRetry: Bool {
        switch self {
        case .modelNotReady:
            true
        case .available, .appleIntelligenceNotEnabled, .deviceNotEligible, .unknown:
            false
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
            "checkmark.circle.fill"
        case .appleIntelligenceNotEnabled:
            "apple.intelligence"
        case .deviceNotEligible:
            "exclamationmark.triangle.fill"
        case .modelNotReady:
            "clock.fill"
        case .unknown:
            "questionmark.circle.fill"
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

        case let .unavailable(reason):
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
        let options = if temperaturePreset.usesGreedySampling {
            GenerationOptions(sampling: .greedy)
        } else {
            GenerationOptions(temperature: temperaturePreset.temperature)
        }

        let samplingInfo = temperaturePreset.usesGreedySampling ? "greedy" : "temp=\(temperaturePreset.temperature)"
        Logger.info("Apple Intelligence: [Style] Starting analysis - chars=\(text.count), style=\(style.displayName), \(samplingInfo)", category: Logger.llm)
        Logger.trace("Apple Intelligence: [Style] Calling session.respond()", category: Logger.llm)

        do {
            let response = try await session.respond(
                to: "Analyze this text for style improvements:\n\n\(text)",
                generating: FMStyleAnalysisResult.self,
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.trace("Apple Intelligence: [Style] Response received in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            // Convert and validate results
            let suggestions = response.content.toStyleSuggestionModels(in: text, style: style)

            Logger.info("Apple Intelligence: [Style] Complete - \(suggestions.count) suggestion(s) in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            return suggestions

        } catch let error as LanguageModelSession.GenerationError {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.error("Apple Intelligence: [Style] Generation error after \(String(format: "%.2f", elapsed))s - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.generationFailed(error.localizedDescription)
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.error("Apple Intelligence: [Style] Failed after \(String(format: "%.2f", elapsed))s - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.analysisError(error.localizedDescription)
        }
    }

    /// Regenerate a style suggestion to get an alternative
    ///
    /// Uses a higher temperature for variety and instructs the model to provide
    /// a different suggestion than the previous one.
    ///
    /// - Parameters:
    ///   - originalText: The original text that was analyzed
    ///   - previousSuggestion: The suggestion to regenerate (will be excluded)
    ///   - style: The writing style to optimize for
    ///   - customVocabulary: Terms that should not be changed
    /// - Returns: A new style suggestion model, or nil if no alternative found
    func regenerateStyleSuggestion(
        originalText: String,
        previousSuggestion: StyleSuggestionModel,
        style: WritingStyle,
        customVocabulary: [String] = []
    ) async throws -> StyleSuggestionModel? {
        guard status == .available else {
            Logger.warning("Apple Intelligence: Cannot regenerate, not available", category: Logger.llm)
            throw FoundationModelsError.notAvailable(status)
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Build instructions with exclusion
        let baseInstructions = StyleInstructions.build(
            for: style,
            customVocabulary: customVocabulary
        )

        // Add exclusion instruction
        let exclusionInstructions = """
        \(baseInstructions)

        IMPORTANT: You must provide a DIFFERENT suggestion than this previous one:
        Previous suggestion: "\(previousSuggestion.suggestedText)"

        Provide an alternative way to improve the text. Be creative but accurate.
        """

        // Create session with modified instructions
        let session = LanguageModelSession(instructions: exclusionInstructions)

        // Use moderate temperature for variety in regeneration
        let options = GenerationOptions(temperature: TemperatureValues.moderate)

        Logger.debug("Apple Intelligence: Regenerating suggestion for text (\(previousSuggestion.originalText.count) chars), style=\(style.displayName)", category: Logger.llm)

        do {
            let response = try await session.respond(
                to: "Provide an alternative style improvement for this text:\n\n\(originalText)",
                generating: FMStyleAnalysisResult.self,
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Convert results
            let suggestions = response.content.toStyleSuggestionModels(in: originalText, style: style)

            Logger.debug("Apple Intelligence: Regeneration complete, \(suggestions.count) suggestion(s) in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            // Return the first suggestion that's different from the previous one
            return suggestions.first { $0.suggestedText != previousSuggestion.suggestedText }

        } catch let error as LanguageModelSession.GenerationError {
            Logger.error("Apple Intelligence: Regeneration generation error - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.generationFailed(error.localizedDescription)
        } catch {
            Logger.error("Apple Intelligence: Regeneration failed - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.analysisError(error.localizedDescription)
        }
    }

    // MARK: - Text Generation

    /// Generate text based on user instruction and context
    ///
    /// - Parameters:
    ///   - instruction: The user's instruction for what to generate
    ///   - context: Context from the document (selected text, surrounding text, etc.)
    ///   - style: The writing style to use
    ///   - variationSeed: Optional seed for varied outputs. Pass different values (e.g., attempt number) to get different results.
    ///                    When nil, uses default sampling. When provided, uses random sampling with higher temperature.
    /// - Returns: The generated text, ready to insert
    /// - Throws: If generation fails
    func generateText(
        instruction: String,
        context: GenerationContext,
        style: WritingStyle,
        variationSeed: UInt64? = nil
    ) async throws -> String {
        guard status == .available else {
            Logger.warning("Apple Intelligence: Cannot generate text, not available", category: Logger.llm)
            throw FoundationModelsError.notAvailable(status)
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Build the prompt - user instruction is primary, context is optional reference
        var promptParts: [String] = []

        promptParts.append("User instruction: \(instruction)")
        promptParts.append("\nWriting style: \(style.displayName)")

        // Only include context if user might want to reference it
        // Context is purely informational - the user's instruction takes absolute priority
        //
        // Context budget: Apple Foundation Models has 4096 token limit (input + output combined)
        // At ~3-4 chars/token, we allocate ~1500 tokens (~4500 chars) for context
        // This leaves room for: instructions (~400 tokens) + output (~1000+ tokens)
        let maxContextChars = 4500

        if let selected = context.selectedText, !selected.isEmpty {
            let truncated = selected.prefix(maxContextChars)
            promptParts.append("\n[Optional reference - selected text in document]:\n\"\"\"\n\(truncated)\n\"\"\"")
        } else if let surrounding = context.surroundingText, !surrounding.isEmpty {
            let truncated = surrounding.prefix(maxContextChars)
            switch context.source {
            case .cursorWindow:
                promptParts.append("\n[Optional reference - nearby text for context only]:\n\"\"\"\n\(truncated)\n\"\"\"")
            case .documentStart, .selection:
                promptParts.append("\n[Optional reference - document context]:\n\"\"\"\n\(truncated)\n\"\"\"")
            case .none:
                break
            }
        }

        let prompt = promptParts.joined(separator: "\n")

        // Build instructions - emphasize user instruction priority
        let instructions = """
        You are a text generation assistant. Your ONLY job is to follow the user's instruction exactly.

        Critical rules:
        - The user's instruction is ABSOLUTE - follow it precisely
        - If the user asks for "unrelated" or "random" text, generate completely NEW content
        - Do NOT copy, paraphrase, or base your output on any provided context unless explicitly asked
        - Context is ONLY provided as optional reference - ignore it unless the instruction specifically refers to it
        - Output ONLY the generated text - no explanations, labels, or meta-commentary
        - Match the specified writing style
        """

        let session = LanguageModelSession(instructions: instructions)

        // Configure generation options based on whether we want variation
        // For regeneration (variationSeed != nil), use random sampling with higher temperature
        // This ensures different outputs for each attempt while maintaining quality
        let options = if let seed = variationSeed {
            // Random top-k sampling with seed for varied but reproducible outputs
            // Higher temperature (0.8) encourages more creative alternatives
            GenerationOptions(
                sampling: .random(top: 40, seed: seed),
                temperature: 0.8
            )
        } else {
            // Default: balanced temperature for first generation
            GenerationOptions(temperature: TemperatureValues.low)
        }

        let samplingInfo = variationSeed.map { "random(seed:\($0), temp:0.8)" } ?? "temp:\(TemperatureValues.low)"
        Logger.debug("Apple Intelligence: Generating text for instruction (\(instruction.count) chars), style=\(style.displayName), \(samplingInfo)", category: Logger.llm)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: FMTextGenerationResult.self,
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.debug("Apple Intelligence: Text generation complete in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            return response.content.generatedText

        } catch let error as LanguageModelSession.GenerationError {
            Logger.error("Apple Intelligence: Text generation error - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.generationFailed(error.localizedDescription)
        } catch {
            Logger.error("Apple Intelligence: Text generation failed - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.analysisError(error.localizedDescription)
        }
    }

    // MARK: - Sentence Simplification

    /// Generate simplified alternatives for a complex sentence
    ///
    /// Used to help users improve readability by offering 1-3 simpler versions
    /// of sentences that are too complex for their target audience.
    ///
    /// - Parameters:
    ///   - sentence: The complex sentence to simplify
    ///   - targetAudience: The target audience level for readability
    ///   - writingStyle: The writing style to maintain
    ///   - previousSuggestion: Optional previous suggestion to avoid (for regeneration)
    /// - Returns: Array of 1-3 simplified alternatives (may be empty if cannot simplify)
    /// - Throws: If simplification fails
    func simplifySentence(
        _ sentence: String,
        targetAudience: TargetAudience,
        writingStyle: WritingStyle,
        previousSuggestion: String? = nil
    ) async throws -> [String] {
        guard status == .available else {
            Logger.warning("Apple Intelligence: Cannot simplify sentence, not available", category: Logger.llm)
            throw FoundationModelsError.notAvailable(status)
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Build instructions tailored for sentence simplification
        var instructions = """
        You are a readability expert. Your task is to simplify sentences for a specific target audience.

        Target audience: \(targetAudience.displayName) (\(targetAudience.audienceDescription))
        Target reading level: \(targetAudience.gradeLevel)
        Writing style: \(writingStyle.displayName)

        Simplification guidelines:
        - Break long sentences into shorter ones if needed
        - Replace complex words with simpler alternatives
        - Use active voice instead of passive voice
        - Remove unnecessary jargon and filler words
        - Preserve the core meaning exactly - all key information must be retained
        - Match the specified writing style
        - Do NOT add information that wasn't in the original

        If the sentence is already simple enough for the target audience, return an empty array.
        """

        // Add instruction to avoid previous suggestion during regeneration
        if let previous = previousSuggestion, !previous.isEmpty {
            instructions += """


            CRITICAL: The user rejected this previous simplification, you MUST provide a completely different alternative:
            Rejected: "\(previous)"

            Your new alternative must use different sentence structure, different word choices, or a different way to break up the sentence.
            """
        }

        let session = LanguageModelSession(instructions: instructions)

        // Use higher temperature for regeneration to ensure variety
        let temperature = previousSuggestion != nil ? 0.9 : TemperatureValues.low
        let options = GenerationOptions(temperature: temperature)

        Logger.debug("Apple Intelligence: Simplifying sentence (\(sentence.count) chars) for \(targetAudience.displayName) audience\(previousSuggestion != nil ? " (regeneration, temp=0.9)" : "")", category: Logger.llm)

        do {
            let response = try await session.respond(
                to: "Simplify this sentence:\n\n\"\(sentence)\"",
                generating: FMSentenceSimplificationResult.self,
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Log what was returned before filtering
            Logger.debug("Apple Intelligence: Raw alternatives: \(response.content.alternatives.count)", category: Logger.llm)

            // Filter out any alternatives that are identical to the original or previous suggestion
            let originalTrimmed = sentence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let previousTrimmed = previousSuggestion?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let validAlternatives = response.content.alternatives.filter { alt in
                let trimmed = alt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // Exclude empty alternatives
                if trimmed.isEmpty {
                    Logger.debug("Apple Intelligence: Filtered out empty alternative", category: Logger.llm)
                    return false
                }
                // Exclude original
                if trimmed == originalTrimmed {
                    Logger.debug("Apple Intelligence: Filtered out (same as original): \(trimmed.prefix(50))...", category: Logger.llm)
                    return false
                }
                // Exclude previous suggestion (for regeneration)
                if let prevTrimmed = previousTrimmed, trimmed == prevTrimmed {
                    Logger.debug("Apple Intelligence: Filtered out (same as previous): \(trimmed.prefix(50))...", category: Logger.llm)
                    return false
                }
                return true
            }

            Logger.debug("Apple Intelligence: Simplification complete, \(validAlternatives.count) alternative(s) after filtering in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            return validAlternatives

        } catch let error as LanguageModelSession.GenerationError {
            Logger.error("Apple Intelligence: Simplification generation error - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.generationFailed(error.localizedDescription)
        } catch {
            Logger.error("Apple Intelligence: Simplification failed - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.analysisError(error.localizedDescription)
        }
    }

    // MARK: - Readability Tips Generation

    /// Generate contextual readability tips for text using AI analysis.
    ///
    /// Analyzes the actual text content and provides specific, actionable tips
    /// to improve readability. Tips reference actual issues in the text rather
    /// than giving generic advice.
    ///
    /// - Parameters:
    ///   - text: The text to analyze (document or selection)
    ///   - score: The Flesch Reading Ease score of the text
    ///   - targetAudience: The target audience level
    /// - Returns: Array of 2-3 specific, actionable tips (may be empty for well-written text)
    /// - Throws: If tip generation fails
    func generateReadabilityTips(
        for text: String,
        score: Int,
        targetAudience: TargetAudience
    ) async throws -> [String] {
        guard status == .available else {
            Logger.warning("Apple Intelligence: Cannot generate tips, not available", category: Logger.llm)
            throw FoundationModelsError.notAvailable(status)
        }

        // Don't analyze very short text
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        guard wordCount >= 5 else {
            return []
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Truncate text for analysis if very long (keep first ~1000 chars for context)
        let analysisText = text.count > 1000 ? String(text.prefix(1000)) + "..." : text

        // Determine if tips are expected based on score
        let needsTips = score < 60 // Scores below 60 indicate readability issues

        let instructions = """
        You are a readability analyst. Analyze the text and provide helpful, actionable tips.

        Text statistics: \(wordCount) words, readability score \(score)/100 (Flesch Reading Ease)
        Target audience: \(targetAudience.displayName)

        Score interpretation:
        - 70+: Easy to read, minimal tips needed
        - 50-69: Moderate difficulty, provide 1-2 tips
        - Below 50: Difficult to read, provide 2-3 tips

        Current score (\(score)) indicates: \(needsTips ? "text needs improvement" : "text is readable")

        RULES:
        - Provide general, actionable tips based on patterns you observe
        - Do NOT quote specific text or mention exact word/sentence counts
        - Keep tips concise (under 15 words each)
        - Focus on: sentence length, word complexity, passive voice, clarity
        - For scores below 60, ALWAYS provide at least 1-2 helpful tips
        - For scores 70+, return empty array (text is already good)

        Example good tips:
        - "Consider breaking longer sentences into shorter ones."
        - "Some formal words could be simplified for clarity."
        - "Try using active voice more often."
        """

        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: TemperatureValues.low)

        Logger.info("Apple Intelligence: [Readability] Starting tips generation - words=\(wordCount), score=\(score), audience=\(targetAudience.displayName)", category: Logger.llm)
        Logger.trace("Apple Intelligence: [Readability] Calling session.respond()", category: Logger.llm)

        do {
            let response = try await session.respond(
                to: "Analyze this text for readability and provide helpful tips:\n\n\"\(analysisText)\"",
                generating: FMReadabilityTipsResult.self,
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.trace("Apple Intelligence: [Readability] Response received in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            // Filter out empty tips
            let validTips = response.content.tips.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            Logger.info("Apple Intelligence: [Readability] Complete - \(validTips.count) tip(s) in \(String(format: "%.2f", elapsed))s", category: Logger.llm)
            if !validTips.isEmpty {
                Logger.trace("Apple Intelligence: [Readability] Tips: \(validTips.joined(separator: " | "))", category: Logger.llm)
            }

            return validTips

        } catch let error as LanguageModelSession.GenerationError {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.error("Apple Intelligence: [Readability] Generation error after \(String(format: "%.2f", elapsed))s - \(error.localizedDescription)", category: Logger.llm)
            throw FoundationModelsError.generationFailed(error.localizedDescription)
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.error("Apple Intelligence: [Readability] Failed after \(String(format: "%.2f", elapsed))s - \(error.localizedDescription)", category: Logger.llm)
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
        case let .notAvailable(status):
            "Foundation Models not available: \(status.userMessage)"
        case let .generationFailed(message):
            "Generation failed: \(message)"
        case let .analysisError(message):
            "Analysis error: \(message)"
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
    case consistent
    case balanced
    case creative

    var id: String {
        rawValue
    }

    /// The temperature value for Foundation Models generation.
    ///
    /// Values are kept low for grammar/style tasks:
    /// - `consistent`: Uses greedy sampling (0.0) for deterministic output
    /// - `balanced`: Low temperature (0.3) for reliable suggestions
    /// - `creative`: Moderate temperature (0.5) for some variety
    var temperature: Double {
        switch self {
        case .consistent: TemperatureValues.greedy
        case .balanced: TemperatureValues.low
        case .creative: TemperatureValues.moderate
        }
    }

    /// Whether this preset uses greedy (deterministic) sampling
    var usesGreedySampling: Bool {
        self == .consistent
    }

    /// Display name for UI
    var label: String {
        switch self {
        case .consistent: "Consistent"
        case .balanced: "Balanced"
        case .creative: "Creative"
        }
    }

    /// User-facing description
    var description: String {
        switch self {
        case .consistent:
            "Deterministic, most accurate"
        case .balanced:
            "Reliable with slight variation"
        case .creative:
            "More variety, still accurate"
        }
    }

    /// SF Symbol name for UI
    var symbolName: String {
        switch self {
        case .consistent: "checkmark.seal.fill"
        case .balanced: "dial.medium.fill"
        case .creative: "wand.and.stars"
        }
    }

    /// Color for statistics charts (RGB values)
    var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .consistent: (0.2, 0.8, 0.4) // Green
        case .balanced: (0.3, 0.5, 0.9) // Blue
        case .creative: (0.7, 0.3, 0.8) // Purple
        }
    }
}
