// FoundationModelsEngine.swift
// Apple Foundation Models integration for style analysis

import Combine
import Foundation
import NaturalLanguage
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
            "Apple Intelligence is preparing the language model. TextWarden will check automatically."
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

// swiftformat:disable indent
#if canImport(FoundationModels)
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

        // Bound unexpectedly verbose structured responses; incomplete results fail without being applied.
        // Configure generation options based on preset
        // Use greedy sampling for consistent mode (deterministic), otherwise use temperature
        var options = if temperaturePreset.usesGreedySampling {
            GenerationOptions(sampling: .greedy)
        } else {
            GenerationOptions(temperature: temperaturePreset.temperature)
        }
        if #available(macOS 27.0, *) {
            // OS 27's default/greedy structured sampling can repeat until context exhaustion.
            // Use the same bounded sampling as Compose; a fixed seed favors minimal variation.
            options = GenerationOptions(
                sampling: .random(top: 40, seed: temperaturePreset.usesGreedySampling ? 0 : nil),
                temperature: temperaturePreset.usesGreedySampling ? TemperatureValues.low : temperaturePreset.temperature
            )
            options.maximumResponseTokens = 1024
        }

        let samplingInfo: String = if #available(macOS 27.0, *), temperaturePreset.usesGreedySampling {
            "seeded-consistent"
        } else {
            temperaturePreset.usesGreedySampling ? "greedy" : "temp=\(temperaturePreset.temperature)"
        }
        Logger.info("Apple Intelligence: [Style] Starting analysis - chars=\(text.count), style=\(style.displayName), \(samplingInfo)", category: Logger.llm)
        Logger.trace("Apple Intelligence: [Style] Calling session.respond()", category: Logger.llm)

        do {
            let response = try await styleResponse(
                session: session,
                prompt: "Analyze this text for style improvements:\n\n\(text)",
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.trace("Apple Intelligence: [Style] Response received in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            // Convert and validate results
            let suggestions = response.toStyleSuggestionModels(in: text, style: style)

            Logger.info("Apple Intelligence: [Style] Complete - \(suggestions.count) suggestion(s) in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            return suggestions

        } catch let error as LanguageModelSession.GenerationError {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.error("Apple Intelligence: [Style] Generation error after \(String(format: "%.2f", elapsed))s - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.generationFailed(FoundationModelsError.safeMessage(for: error))
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.error("Apple Intelligence: [Style] Failed after \(String(format: "%.2f", elapsed))s - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.analysisError(FoundationModelsError.safeMessage(for: error))
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
        var options = GenerationOptions(temperature: TemperatureValues.moderate)
        if #available(macOS 27.0, *) { options.maximumResponseTokens = 1024 }

        Logger.debug("Apple Intelligence: Regenerating suggestion for text (\(previousSuggestion.originalText.count) chars), style=\(style.displayName)", category: Logger.llm)

        do {
            let response = try await styleResponse(
                session: session,
                prompt: "Provide an alternative style improvement for this text:\n\n\(originalText)",
                options: options
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Convert results
            let suggestions = response.toStyleSuggestionModels(in: originalText, style: style)

            Logger.debug("Apple Intelligence: Regeneration complete, \(suggestions.count) suggestion(s) in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            // Return the first suggestion that's different from the previous one
            return suggestions.first { $0.suggestedText != previousSuggestion.suggestedText }

        } catch let error as LanguageModelSession.GenerationError {
            Logger.error("Apple Intelligence: Regeneration generation error - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.generationFailed(FoundationModelsError.safeMessage(for: error))
        } catch {
            Logger.error("Apple Intelligence: Regeneration failed - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.analysisError(FoundationModelsError.safeMessage(for: error))
        }
    }

    private func styleResponse(session: LanguageModelSession, prompt: String, options: GenerationOptions) async throws -> FMStyleAnalysisResult {
        if #available(macOS 27.0, *) {
            let response = try await session.respond(to: prompt, schema: FMStyleAnalysisResult.generationSchema, options: options)
            return try FMStyleAnalysisResult(validatingEntriesIn: response.content)
        }
        return try await session.respond(to: prompt, generating: FMStyleAnalysisResult.self, options: options).content
    }

    // MARK: - Text Generation

    /// Only a blocked selected-text rewrite may use transformation mode, and its result must be previewed.
    func rewriteSelection(_ text: String, style: WritingStyle, preset: StyleTemperaturePreset, customVocabulary: [String]) async throws -> SelectionRewriteResult {
        try GenerationContext.validateSelection(text)
        guard let language = SelectionRewriteResult.confidentLanguage(for: text),
              let languageName = Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue)
        else { throw FoundationModelsError.uncertainRewriteLanguage }
        let result = try await SelectionRewriteResult.generate(source: text) { transformation in
            try await self.rewriteText(text, style: style, preset: preset, customVocabulary: customVocabulary,
                                       sourceLanguage: languageName,
                                       model: transformation ? SystemLanguageModel(guardrails: .permissiveContentTransformations) : .default)
        }
        guard !result.hasChanges(comparedTo: text) || SelectionRewriteResult.confidentLanguage(for: result.text) == language else {
            throw FoundationModelsError.rewriteLanguageChanged
        }
        return result
    }

    func rewriteText(_ text: String, style: WritingStyle, preset: StyleTemperaturePreset, customVocabulary: [String], seed: UInt64? = nil, sourceLanguage: String? = nil) async throws -> String {
        try await rewriteText(text, style: style, preset: preset, customVocabulary: customVocabulary, seed: seed, sourceLanguage: sourceLanguage, model: .default)
    }

    private func rewriteText(_ text: String, style: WritingStyle, preset: StyleTemperaturePreset, customVocabulary: [String], seed: UInt64? = nil, sourceLanguage: String? = nil, model: SystemLanguageModel) async throws -> String {
        try GenerationContext.validateSelection(text)
        guard status.isAvailable else { throw FoundationModelsError.notAvailable(status) }
        let session = LanguageModelSession(model: model, instructions: StyleInstructions.rewrite(for: style, customVocabulary: customVocabulary))
        let options = GenerationOptions(
            sampling: preset.usesGreedySampling ? .greedy : seed.map { .random(probabilityThreshold: 0.95, seed: $0) },
            temperature: preset.temperature
        )
        // Make the editing task and language explicit; a bare selection can be treated as a request to answer.
        let language = sourceLanguage ?? NLLanguageRecognizer.dominantLanguage(for: text)
            .flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0.rawValue) } ?? "the original language"
        // Never truncate a selection that will be replaced in full.
        var prompt = """
        Rewrite this \(language) text in the \(style.displayName) style. Fix mistakes and unnecessary wording, but keep all its information.

        <text_to_edit>
        \(text)
        </text_to_edit>

        Return only the edited text in \(language), without the text_to_edit tags.
        """
        if #available(macOS 27.0, *) {
            prompt += "\nPreserve sentence types: statements remain statements, questions remain questions. Copy quoted examples exactly, including their punctuation."
        }
        let response = try await session.respond(to: prompt, options: options)
        return response.content
    }

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
        try GenerationContext.validateSelection(context.selectedText)
        guard status == .available else {
            Logger.warning("Apple Intelligence: Cannot generate text, not available", category: Logger.llm)
            throw FoundationModelsError.notAvailable(status)
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        let prompt = context.composePrompt(instruction: instruction)
        var instructions = StyleInstructions.compose(for: style, hasSelection: context.hasSelection)
        if #available(macOS 27.0, *), let selection = context.selectedText,
           let language = SelectionRewriteResult.confidentLanguage(for: selection)
               .flatMap({ Locale(identifier: "en").localizedString(forLanguageCode: $0.rawValue) })
        {
            instructions += "\nThe source language is \(language). Write in \(language) by default; follow an explicit translation request from the user."
        }

        let session = LanguageModelSession(instructions: instructions)

        // A fresh session avoids accumulating retry history in the model's context.
        // Sampling encourages alternatives; it cannot guarantee variety or quality.
        // Selected edits favor fidelity; drafting retains the wider creative sampling range.
        let retryTemperature = context.hasSelection ? TemperatureValues.low : 0.8
        let options = if let seed = variationSeed {
            GenerationOptions(
                sampling: .random(top: 40, seed: seed),
                temperature: retryTemperature
            )
        } else {
            // Default: balanced temperature for first generation
            GenerationOptions(temperature: TemperatureValues.low)
        }

        let samplingInfo = variationSeed.map { "random(seed:\($0), temp:\(retryTemperature))" } ?? "temp:\(TemperatureValues.low)"
        Logger.debug("Apple Intelligence: Generating text for instruction (\(instruction.count) chars), style=\(style.displayName), \(samplingInfo)", category: Logger.llm)

        do {
            let generatedText: String = if #available(macOS 27.0, *) {
                try await session.respond(to: prompt, options: options).content
            } else {
                try await session.respond(to: prompt, generating: FMTextGenerationResult.self, options: options).content.generatedText
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.debug("Apple Intelligence: Text generation complete in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            return generatedText

        } catch let error as LanguageModelSession.GenerationError {
            Logger.error("Apple Intelligence: Text generation error - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.generationFailed(FoundationModelsError.safeMessage(for: error))
        } catch {
            Logger.error("Apple Intelligence: Text generation failed - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.analysisError(FoundationModelsError.safeMessage(for: error))
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

        Logger.debug("Apple Intelligence: Simplifying sentence (\(sentence.count) chars) for \(targetAudience.displayName) audience\(previousSuggestion != nil ? " (regeneration)" : "")", category: Logger.llm)

        do {
            let alternatives: [String]
            if #available(macOS 27.0, *) {
                // Reuse the source-preserving editing contract; OS 27's simplification schema
                // can produce malformed conditionals and change relationships while paraphrasing.
                var instruction = "Simplify this text to make it easier to understand for \(targetAudience.displayName) readers (\(targetAudience.audienceDescription), \(targetAudience.gradeLevel) reading level). Prefer removing redundant wording to paraphrasing. Keep prepositions and clauses expressing conditions, obligations, and decisions verbatim. If no safe simplification is possible, keep it unchanged."
                if let previousSuggestion, !previousSuggestion.isEmpty {
                    instruction += "\nProvide a different alternative from this previous suggestion: \(previousSuggestion)"
                }
                let context = GenerationContext(selectedText: sentence, surroundingText: nil, fullTextLength: sentence.count, cursorPosition: nil, source: .selection)
                alternatives = try await [generateText(instruction: instruction, context: context, style: writingStyle, variationSeed: previousSuggestion == nil ? nil : 1)]
            } else {
                alternatives = try await session.respond(
                    to: "Simplify this sentence:\n\n\"\(sentence)\"",
                    generating: FMSentenceSimplificationResult.self,
                    options: options
                ).content.alternatives
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Log what was returned before filtering
            Logger.debug("Apple Intelligence: Raw alternatives: \(alternatives.count)", category: Logger.llm)

            // Filter out any alternatives that are identical to the original or previous suggestion
            let originalTrimmed = sentence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let previousTrimmed = previousSuggestion?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let validAlternatives = alternatives.filter { alt in
                let trimmed = alt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // Exclude empty alternatives
                if trimmed.isEmpty {
                    Logger.debug("Apple Intelligence: Filtered out empty alternative", category: Logger.llm)
                    return false
                }
                // Exclude original
                if trimmed == originalTrimmed {
                    Logger.debug("Apple Intelligence: Filtered out alternative identical to source", category: Logger.llm)
                    return false
                }
                // Exclude previous suggestion (for regeneration)
                if let prevTrimmed = previousTrimmed, trimmed == prevTrimmed {
                    Logger.debug("Apple Intelligence: Filtered out alternative identical to previous suggestion", category: Logger.llm)
                    return false
                }
                return true
            }

            Logger.debug("Apple Intelligence: Simplification complete, \(validAlternatives.count) alternative(s) after filtering in \(String(format: "%.2f", elapsed))s", category: Logger.llm)

            return validAlternatives

        } catch let error as LanguageModelSession.GenerationError {
            Logger.error("Apple Intelligence: Simplification generation error - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.generationFailed(FoundationModelsError.safeMessage(for: error))
        } catch {
            Logger.error("Apple Intelligence: Simplification failed - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.analysisError(FoundationModelsError.safeMessage(for: error))
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

        var instructions = """
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
        if #available(macOS 27.0, *) {
            instructions += "\nRecommend changes only for problems actually present in the text. Do not recommend fixing passive voice in text that already uses active voice. Fewer relevant tips are better than invented issues."
        }

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

            return validTips

        } catch let error as LanguageModelSession.GenerationError {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.error("Apple Intelligence: [Readability] Generation error after \(String(format: "%.2f", elapsed))s - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.generationFailed(FoundationModelsError.safeMessage(for: error))
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.error("Apple Intelligence: [Readability] Failed after \(String(format: "%.2f", elapsed))s - \(FoundationModelsError.safeMessage(for: error))", category: Logger.llm)
            throw FoundationModelsError.analysisError(FoundationModelsError.safeMessage(for: error))
        }
    }
}
#endif
// swiftformat:enable indent

// MARK: - Errors

/// Errors that can occur during Foundation Models operations
enum FoundationModelsError: LocalizedError {
    case notAvailable(StyleEngineStatus)
    case generationFailed(String)
    case analysisError(String)
    case selectionTooLong
    case uncertainRewriteLanguage
    case rewriteLanguageChanged

    var errorDescription: String? {
        switch self {
        case let .notAvailable(status):
            "Foundation Models not available: \(status.userMessage)"
        case let .generationFailed(message):
            "Generation failed: \(message)"
        case let .analysisError(message):
            "Analysis error: \(message)"
        case .selectionTooLong:
            "Select a shorter passage. The selection was not shortened or changed."
        case .uncertainRewriteLanguage:
            "Language unclear · select more text"
        case .rewriteLanguageChanged:
            "Language changed · text unchanged"
        }
    }
}

/// Generated text is a proposal, never permission to replace the user's selection.
struct SelectionRewriteResult: Equatable {
    enum PreviewReason {
        case standard, transformation, quotationExtraction
    }

    let text: String
    let reason: PreviewReason

    static func confidentLanguage(for text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        // ponytail: conservative detector threshold, not a language guarantee.
        // Ambiguous passages are declined rather than steered into a guessed language.
        guard let language = recognizer.dominantLanguage,
              recognizer.languageHypotheses(withMaximum: 1)[language, default: 0] >= 0.95
        else { return nil }
        return language
    }

    func hasChanges(comparedTo source: String) -> Bool {
        // A selection often includes the separator after a sentence. Trimming it
        // is not a rewrite; keep internal spacing and punctuation significant.
        text.trimmingCharacters(in: .whitespacesAndNewlines) != source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    static func generate(source: String, request: (_ transformation: Bool) async throws -> String) async throws -> Self {
        try Task.checkCancellation()
        do {
            let text = try await request(false)
            try Task.checkCancellation()
            return Self(text: text, reason: extractsQuotation(text, from: source) ? .quotationExtraction : .standard)
        } catch {
            try Task.checkCancellation()
            guard FoundationModelsError.isBlocked(error) else { throw error }
            let text = try await request(true)
            try Task.checkCancellation()
            return Self(text: text, reason: .transformation)
        }
    }

    /// Detect exact quotation extractions, including a retained prefix or suffix.
    static func extractsQuotation(_ proposed: String, from source: String) -> Bool {
        let quotes = [("\"", "\""), ("“", "”"), ("„", "“"), ("«", "»"), ("'", "'"), ("‘", "’"), ("「", "」"), ("『", "』"), ("`", "`")]
        var body = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in quotes where body.count >= 2 && body.hasPrefix(open) && body.hasSuffix(close) {
            body = String(body.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard !body.isEmpty else { return false }
        // ponytail: exact quoted content only; paraphrased omissions still need semantic review.
        for (open, close) in quotes {
            var start = source.startIndex
            while let opening = source.range(of: open, range: start ..< source.endIndex),
                  let closing = source.range(of: close, range: opening.upperBound ..< source.endIndex)
            {
                start = closing.upperBound
                let quoted = String(source[opening.upperBound ..< closing.lowerBound])
                let prefix = String(source[..<opening.lowerBound])
                let suffix = String(source[closing.upperBound...])
                let prefixHasWords = prefix.rangeOfCharacter(from: .alphanumerics) != nil
                let suffixHasWords = suffix.rangeOfCharacter(from: .alphanumerics) != nil
                if body == quoted.trimmingCharacters(in: .whitespacesAndNewlines), prefixHasWords || suffixHasWords { return true }
                if body == (quoted + suffix).trimmingCharacters(in: .whitespacesAndNewlines), prefixHasWords { return true }
                if body == (prefix + quoted).trimmingCharacters(in: .whitespacesAndNewlines), suffixHasWords { return true }
            }
        }
        return false
    }
}

extension FoundationModelsError {
    static func isBlocked(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal: return true
                default: return false
                }
            }
        #endif
        return false
    }

    /// Shared by all AI features; framework descriptions can include private prompts or outputs.
    static func safeMessage(for error: Error) -> String {
        if error is CancellationError { return "Request cancelled" }
        if let error = error as? FoundationModelsError { return error.localizedDescription }
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal: return "Apple Intelligence could not process this request."
                case .exceededContextWindowSize: return "The model ran out of space while processing the text or generating its response. Try again, or use a shorter passage or instruction."
                case .unsupportedLanguageOrLocale: return "Apple Intelligence does not support this language."
                case .assetsUnavailable: return "Apple Intelligence is unavailable. Please try again later."
                case .rateLimited, .concurrentRequests: return "Apple Intelligence is busy. Please try again."
                default: break
                }
            }
        #endif
        return "Apple Intelligence could not complete this request. Please try again."
    }
}

// MARK: - Temperature Configuration

/// Sampling controls variation, not correctness. Greedy output can still change meaning.
private enum TemperatureValues {
    static let greedy: Double = 0.0
    static let low: Double = 0.3
    static let moderate: Double = 0.5
}

// MARK: - Temperature Preset

/// Low-variation presets for Foundation Models generation; none guarantees fidelity.
enum StyleTemperaturePreset: String, CaseIterable, Identifiable {
    case consistent
    case balanced
    case creative

    var id: String {
        rawValue
    }

    /// The temperature value for Foundation Models generation.
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
            "Minimal variation"
        case .balanced:
            "Some variation"
        case .creative:
            "More variation"
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
