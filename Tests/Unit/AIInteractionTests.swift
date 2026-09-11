import ApplicationServices
import Foundation
@testable import TextWarden
import XCTest

final class AIInteractionTests: XCTestCase {
    private func context(_ text: String) -> GenerationContext {
        .init(selectedText: text, surroundingText: nil, fullTextLength: text.count, cursorPosition: nil, source: .selection)
    }

    func testComposeDraftExcludesUnselectedDocumentAndKeepsEntireSelection() {
        let instruction = "Write a confirmation about 17 reports."
        for source in [ContextSource.documentStart, .cursorWindow, .none] {
            let draft = GenerationContext(selectedText: nil, surroundingText: "We has reviewed 23 invoices.", fullTextLength: 32, cursorPosition: 0, source: source)
            XCTAssertEqual(draft.composePrompt(instruction: instruction), GenerationContext.empty.composePrompt(instruction: instruction))
            XCTAssertFalse(draft.hasSelection)
        }
        let selection = "We has reviewed 17 reports.\nNo decision yet. 😀"
        XCTAssertTrue(context(selection).composePrompt(instruction: "Fix grammar").contains(selection))
        XCTAssertTrue(context(selection).hasSelection)
        XCTAssertFalse(context("").hasSelection)
        XCTAssertNotEqual(StyleInstructions.compose(for: .formal, hasSelection: true), StyleInstructions.compose(for: .default, hasSelection: true))
    }

    @MainActor
    func testLiveComposeDraftContextRegression() async throws {
        guard ProcessInfo.processInfo.environment["TEXTWARDEN_TEST_AI"] == "1" else { throw XCTSkip("Opt-in local model check") }
        guard #available(macOS 26.0, *) else { throw XCTSkip("Requires macOS 26") }
        let engine = FoundationModelsEngine()
        guard engine.status.isAvailable else { throw XCTSkip(engine.status.userMessage) }
        let draft = GenerationContext(selectedText: nil, surroundingText: "We has reviewed 17 reports and will send the summary tomorrow.", fullTextLength: 75, cursorPosition: 75, source: .documentStart)
        for seed: UInt64? in [nil, 1, 2] {
            let result = try await engine.generateText(instruction: "Write one sentence confirming that we reviewed 17 reports and will send the summary tomorrow.", context: draft, style: .default, variationSeed: seed)
            let attachment = XCTAttachment(string: "seed=\(String(describing: seed))\n\(result)")
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(result.contains("17"))
            XCTAssertTrue(result.lowercased().contains("tomorrow"))
            XCTAssertFalse(result.lowercased().contains("we has"))
        }
    }

    func testSelectionBudgetNeverTruncatesAndAccountsForUnicode() throws {
        try GenerationContext.validateSelection(nil)
        try GenerationContext.validateSelection(String(repeating: "a", count: 4000))
        try GenerationContext.validateSelection(String(repeating: "😀", count: 1000))
        for input in [String(repeating: "a", count: 4001), String(repeating: "😀", count: 1001)] {
            XCTAssertThrowsError(try GenerationContext.validateSelection(input)) { error in
                guard case FoundationModelsError.selectionTooLong = error else { return XCTFail("Unexpected error") }
            }
        }
    }

    @MainActor
    func testComposeDoesNotReuseAnotherSelectionOrChangedInstruction() async {
        let popover = TextGenerationPopover.shared
        let callback = popover.onGenerate
        defer { popover.clear(); popover.onGenerate = callback }
        popover.clear()
        popover.instruction = "Simplify"
        popover.context = context("The first sample contains 17 reports.")
        var calls = 0
        popover.onGenerate = { instruction, _, context, seed in
            calls += 1
            if let seed { XCTAssertLessThanOrEqual(seed, 0x7FFF_FFFF) }
            return instruction + ": " + (context.selectedText ?? "")
        }
        popover.generate()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(popover.generatedResult, "Simplify: The first sample contains 17 reports.")
        popover.context = context("The second sample contains 23 invoices.")
        XCTAssertNil(popover.generatedResult)
        popover.generate()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(popover.generatedResult, "Simplify: The second sample contains 23 invoices.")
        popover.tryAnother()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(calls, 3)
        popover.instruction = "Make formal"
        XCTAssertNil(popover.generatedResult)
        popover.context = context(String(repeating: "x", count: 4001))
        popover.generate()
        XCTAssertEqual(calls, 3, "Oversized selections must not reach the model")
        XCTAssertNotNil(popover.errorMessage)
    }

    @MainActor
    func testComposeDropsLateResultAfterClearCloseOrContextChange() async throws {
        let popover = TextGenerationPopover.shared
        let callback = popover.onGenerate
        defer { popover.clear(); popover.onGenerate = callback }
        for action in 0 ..< 3 {
            popover.clear()
            popover.instruction = "Simplify"
            popover.context = context("Original selection")
            var continuation: CheckedContinuation<String, Never>?
            popover.onGenerate = { _, _, _, _ in
                await withCheckedContinuation { continuation = $0 }
            }
            popover.generate()
            for _ in 0 ..< 20 {
                await Task.yield()
            }
            let pending = try XCTUnwrap(continuation)
            switch action {
            case 0: popover.clear()
            case 1: popover.hide()
            default: popover.context = context("Changed selection")
            }
            pending.resume(returning: "Stale result")
            for _ in 0 ..< 20 {
                await Task.yield()
            }
            XCTAssertNil(popover.generatedResult)
            XCTAssertFalse(popover.isGenerating)
        }
    }

    @MainActor
    func testComposeFailedRetryKeepsReviewedResultAndCannotInsertWhilePending() async throws {
        let popover = TextGenerationPopover.shared
        let callback = popover.onGenerate
        let insert = popover.onInsertText
        defer { popover.clear(); popover.onGenerate = callback; popover.onInsertText = insert }
        popover.clear()
        popover.instruction = "Draft a confirmation"
        popover.onGenerate = { _, _, _, _ in "Reviewed result" }
        popover.generate()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        var pending: CheckedContinuation<String, Error>?
        popover.onGenerate = { _, _, _, _ in try await withCheckedThrowingContinuation { pending = $0 } }
        var inserted: String?
        popover.onInsertText = { inserted = $0 }
        popover.tryAnother()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        let request = try XCTUnwrap(pending)
        XCTAssertTrue(popover.isGenerating)
        popover.insertGeneratedText()
        XCTAssertNil(inserted)
        request.resume(throwing: FoundationModelsError.generationFailed("Synthetic retry failure"))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertFalse(popover.isGenerating)
        XCTAssertEqual(popover.generatedResult, "Reviewed result")
        XCTAssertNotNil(popover.errorMessage)
        popover.insertGeneratedText()
        XCTAssertEqual(inserted, "Reviewed result")
    }

    private func recordQualityOutput(_ output: String, feature: String, input: String, repetition: Int) {
        let attachment = XCTAttachment(string: "Feature: \(feature)\nRepetition: \(repetition)\nInput: \(input)\nOutput:\n\(output)")
        attachment.name = "\(feature)-\(repetition)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @available(macOS 26.0, *)
    @MainActor
    private func qualityEngine() throws -> FoundationModelsEngine {
        guard ProcessInfo.processInfo.environment["TEXTWARDEN_TEST_AI_FEATURE_QUALITY"] == "1" else { throw XCTSkip("Opt-in feature quality evaluation") }
        let engine = FoundationModelsEngine()
        guard engine.status.isAvailable else { throw XCTSkip(engine.status.userMessage) }
        return engine
    }

    @MainActor
    func testLiveDraftQuality() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Requires macOS 26") }
        let engine = try qualityEngine()
        let fixtures = [
            ("Write one sentence: TextWarden reviewed 17 reports and will send the summary tomorrow.", ["TextWarden", "17", "tomorrow"]),
            ("Write a short note saying that we cannot approve the 23 invoices until Friday.", ["23", "Friday"]),
            ("Schreibe einen deutschen Satz: Wir haben 17 Berichte geprüft und senden morgen die Zusammenfassung.", ["17", "morgen"]),
        ]
        for repetition in 0 ..< 3 {
            for (instruction, facts) in fixtures {
                let result = try await engine.generateText(instruction: instruction, context: .empty, style: .default, variationSeed: repetition == 0 ? nil : UInt64(repetition))
                recordQualityOutput(result, feature: "draft", input: instruction, repetition: repetition)
                for fact in facts {
                    XCTAssertTrue(result.contains(fact), "Draft lost required fact: \(fact)")
                }
                if instruction.contains("cannot approve") {
                    let lowercased = result.lowercased()
                    XCTAssertTrue(["cannot approve", "can't approve", "unable to approve", "not approve", "not able to approve"].contains { lowercased.contains($0) }, "Draft lost inability to approve")
                }
                XCTAssertFalse(result.contains("We has"))
            }
        }
    }

    @MainActor
    func testLiveSelectedComposeQuality() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Requires macOS 26") }
        let engine = try qualityEngine()
        let fixtures = [
            ("We has reviewed 23 invoices. We will not pay until Friday.", ["23", "not", "Friday"], "We has"),
            ("Wir haben 17 Berichte geprüfft. Wir senden sie morgen.", ["17", "morgen"], "geprüfft"),
            ("Nous avons examinés 17 rapports. Nous les enverrons demain.", ["17", "demain"], "examinés"),
            ("We has not approved version 4.2 yet. We may release it on Tuesday if the tests pass.", ["not", "4.2", "may", "Tuesday", "if"], "We has"),
            ("Could you explains why the 31 checks failed?", ["31", "?"], "you explains"),
        ]
        for repetition in 0 ..< 3 {
            for (source, facts, error) in fixtures {
                for style in WritingStyle.allCases {
                    let result = try await engine.generateText(instruction: "Fix grammar and spelling only. Keep the original language.", context: context(source), style: style, variationSeed: repetition == 0 ? nil : UInt64(repetition))
                    recordQualityOutput(result, feature: "selected-compose-\(style.displayName)", input: source, repetition: repetition)
                    for fact in facts {
                        XCTAssertTrue(result.contains(fact), "Rewrite lost required fact: \(fact)")
                    }
                    XCTAssertFalse(result.contains(error), "Rewrite left the known error unchanged")
                }
            }
        }
    }

    @MainActor
    func testLiveShorterDoesNotExtractQuotedInstruction() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Requires macOS 26") }
        let engine = try qualityEngine()
        let source = "The reviewer wrote, \"Do not approve this proposal.\" I am quoting the review, not asking you to reject the proposal."
        for repetition in 0 ..< 3 {
            let result = try await engine.generateText(instruction: "Make this text shorter and more concise", context: context(source), style: .default, variationSeed: repetition == 0 ? nil : UInt64(repetition))
            recordQualityOutput(result, feature: "shorter-quotation-attribution", input: source, repetition: repetition)
            // Narrow regression for the observed loss of speaker attribution, not a semantic quality score.
            let bareQuotation = result.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
            XCTAssertNotEqual(bareQuotation, "Do not approve this proposal.", "Shorter extracted a quotation without its speaker attribution or clarification")
        }
    }

    @MainActor
    func testLiveSimplificationQuality() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Requires macOS 26") }
        let engine = try qualityEngine()
        let source = "It is necessary for us to review all 17 reports before we can make a decision about the proposal."
        for repetition in 0 ..< 3 {
            let alternatives = try await engine.simplifySentence(source, targetAudience: .general, writingStyle: .default)
            recordQualityOutput(alternatives.joined(separator: "\n---\n"), feature: "simplification", input: source, repetition: repetition)
            XCTAssertFalse(alternatives.isEmpty)
            for result in alternatives {
                XCTAssertTrue(result.contains("17"))
                XCTAssertTrue(result.lowercased().contains("before"), "Simplification lost the prerequisite")
                XCTAssertLessThan(result.count, source.count, "Simplification did not shorten the wordy fixture")
            }
        }
    }

    @MainActor
    func testLiveStyleQuality() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Requires macOS 26") }
        let engine = try qualityEngine()
        let source = "At this point in time, we are currently in the process of reviewing 17 reports."
        for repetition in 0 ..< 3 {
            let suggestions = try await engine.analyzeStyle(source, style: .concise, temperaturePreset: .consistent)
            recordQualityOutput(suggestions.map { "\($0.originalText) => \($0.suggestedText)" }.joined(separator: "\n"), feature: "style", input: source, repetition: repetition)
            XCTAssertFalse(suggestions.isEmpty)
            for suggestion in suggestions {
                XCTAssertTrue(source.contains(suggestion.originalText), "Style edit is not source-anchored")
                XCTAssertLessThan(suggestion.suggestedText.count, suggestion.originalText.count, "Concise style did not shorten the wordy fixture")
                if suggestion.originalText.contains("17") { XCTAssertTrue(suggestion.suggestedText.contains("17")) }
            }
        }
    }

    @MainActor
    func testGeneratedInsertionInvalidatesOldErrorsAndEndsReplacementSuppression() {
        let coordinator = AnalysisCoordinator.shared
        coordinator.textMonitor.stopMonitoring()
        defer {
            coordinator.clearCache()
            coordinator.monitoredContext = nil
        }
        let context = ApplicationContext(bundleIdentifier: "com.apple.TextEdit", processID: 42, applicationName: "TextEdit")
        let source = "We will send the summary tomorroww."
        let errors = GrammarEngine.shared.analyzeText(source, dialect: "American").errors
        XCTAssertFalse(errors.isEmpty)
        coordinator.monitoredContext = context
        coordinator.currentSegment = TextSegment(content: source, startIndex: 0, endIndex: source.count, context: context)
        coordinator.previousText = source
        coordinator.lastAnalyzedText = source
        coordinator.currentErrors = errors
        coordinator.lastReplacementTime = Date()
        let generation = coordinator.grammarAnalysisGeneration
        XCTAssertTrue(coordinator.isInReplacementMode)

        let other = ApplicationContext(bundleIdentifier: "com.example.other", processID: 43, applicationName: "Other")
        coordinator.refreshAfterGeneratedInsertion(in: other, element: AXUIElementCreateSystemWide())
        XCTAssertEqual(coordinator.currentErrors.count, errors.count, "An old insertion must not reset a different app")
        XCTAssertTrue(coordinator.isInReplacementMode)

        coordinator.refreshAfterGeneratedInsertion(in: context, element: AXUIElementCreateSystemWide())
        XCTAssertFalse(coordinator.isInReplacementMode, "Fresh results must not be dropped during correction grace")
        XCTAssertFalse(AnalysisCoordinator.isInReplacementModeThreadSafe)
        XCTAssertTrue(coordinator.currentErrors.isEmpty)
        XCTAssertNil(coordinator.currentSegment)
        XCTAssertEqual(coordinator.previousText, "")
        XCTAssertEqual(coordinator.lastAnalyzedText, "")
        XCTAssertGreaterThan(coordinator.grammarAnalysisGeneration, generation, "Old in-flight grammar results must be invalidated")
    }
}
