# Apple Foundation Models Integration

TextWarden uses Apple's [Foundation Models framework](https://developer.apple.com/documentation/FoundationModels) for optional, on-device writing assistance. Harper remains the grammar and spell-checking engine; Foundation Models handles style suggestions, composition, sentence simplification, and readability tips.

## Availability

The app targets macOS 14, but Foundation Models code is compiled conditionally and guarded with `@available(macOS 26.0, *)`.

Users need:

- macOS 26 or later
- A Mac eligible for Apple Intelligence
- Apple Intelligence enabled in **System Settings → Apple Intelligence & Siri**
- The system language model downloaded and ready

`FoundationModelsEngine.checkAvailability()` maps `SystemLanguageModel.default.availability` to the app's `StyleEngineStatus`:

| TextWarden status | Foundation Models state | Meaning |
| --- | --- | --- |
| `available` | Model available | Requests can run |
| `appleIntelligenceNotEnabled` | Apple Intelligence disabled | User must enable it in System Settings |
| `deviceNotEligible` | Device not eligible | Hardware cannot use the system model |
| `modelNotReady` | Model not ready | Model is downloading or preparing; retry later |
| `unknown(String)` | Future or unknown state | Feature stays unavailable and shows the reason |

Every public operation checks availability before creating a session.

## Implementation Files

| File | Responsibility |
| --- | --- |
| `Sources/App/FoundationModelsEngine.swift` | Availability, sessions, prompts, generation options, and errors |
| `Sources/App/StyleTypes+Generable.swift` | Guided-generation result types and conversion to app models |
| `Sources/App/StyleInstructions.swift` | Shared and writing-style-specific instructions |
| `Sources/App/AnalysisCoordinator+StyleChecking.swift` | Manual checks, caching, regeneration, and readability integration |
| `Sources/App/AnalysisCoordinator+GrammarAnalysis.swift` | Automatic style-check scheduling and result handling |
| `Sources/SketchPad/SketchPadViewModel.swift` | Sketch Pad analysis, quick actions, and readability tips |

## Session Model

TextWarden creates a fresh `LanguageModelSession` for each operation. Style analysis, composition, and readability tasks do not share conversation history.

This keeps unrelated documents isolated and prevents prior prompts from consuming the next request's context window. `prewarm()` creates and prewarms a temporary session to reduce setup latency; it does not become a persistent chat session.

## Guided Generation

Foundation Models returns typed `@Generable` values rather than unstructured JSON:

| Type | Output |
| --- | --- |
| `FMStyleAnalysisResult` | Up to five `FMStyleSuggestion` values |
| `FMTextGenerationResult` | Text ready to insert |
| `FMSentenceSimplificationResult` | Zero or one simplified alternative in an array |
| `FMReadabilityTipsResult` | A short list of readability tips |

The style suggestion type contains the exact source phrase, its replacement, and a short explanation. Conversion to `StyleSuggestionModel` rejects output that is unchanged, too short, absent from the source, truncated around parenthetical punctuation, or spread across multiple list items. Overlapping suggestions are filtered before display.

Guided generation constrains the shape of a response. It does not make the response correct, so source matching and replacement validation remain required.

## Style Analysis

`analyzeStyle(_:style:temperaturePreset:customVocabulary:)` builds instructions from the selected `WritingStyle` and custom vocabulary. It asks for meaningful changes only and converts the typed result into validated `StyleSuggestionModel` values.

Supported writing styles are Default, Concise, Formal, Casual, and Business. In code, the user-facing Casual option maps to `WritingStyle.informal`.

### Sampling presets

| Preset | Generation option |
| --- | --- |
| Consistent | Greedy sampling |
| Balanced | Temperature `0.3` |
| Creative | Temperature `0.5` |

Manual style checks pass the selected preset. The automatic style path currently calls `analyzeStyle` without a preset argument, so it uses the default Balanced preset.

Sampling controls variation, not correctness. Greedy output can still miss corrections or change meaning; even a repeatable result needs review. Model and operating-system updates can also change the output.

### Automatic checks

Enabling AI Style Suggestions enables automatic checks. `AnalysisCoordinator` applies these guards before a request:

- Three-second debounce after grammar analysis
- At least 50 characters
- At least 30 seconds since the last automatic style request
- Text must differ from the last request
- No manual or automatic style request already active
- Apple Intelligence, the focused Accessibility element, and app context must still be available
- Automatic checks stay suppressed after accepting or dismissing a style suggestion until the user edits again

The coordinator increments a generation counter and discards a result if newer style work has started.

### Manual checks and caching

`runManualStyleCheck()` checks selected text when a non-empty Accessibility selection exists; otherwise it checks the full field. The cache key combines the analyzed text hash, writing style, engine identifier, and selected temperature name. Entries expire after ten minutes and the cache is limited to 20 entries.

Cached results still pass sensitivity, overlap, and suggestion-history filters before display.

### Regeneration

`regenerateStyleSuggestion()` includes the previous suggestion in the new session's instructions, uses temperature `0.5`, and returns the first validated result whose replacement differs from the previous one.

## AI Compose

`generateText(instruction:context:style:variationSeed:)` has two explicit contracts: without a selection it drafts from the instruction alone; with a selection it edits the entire selected passage according to the instruction. Both use the chosen writing style. The panel labels drafting separately and tells users to select text for rewriting.

Selected text is limited to 4,000 UTF-8 bytes and rejected if it exceeds that limit; it is never silently shortened. Nearby document text is not sent to the model for drafting, preventing unrelated facts or grammatical errors from contaminating the new draft. Context extraction still records the editor source for insertion and request identity. Sketch Pad's explicit document-edit actions supply their chosen text as the editing source.

The first request uses temperature `0.3`. Retry uses a counter bounded to 31 bits (the installed runtime rejects larger seeds), with random top-40 sampling. Selected-text retries also use `0.3` to favor fidelity; instruction-only draft retries retain `0.8`. The returned `FMTextGenerationResult.generatedText` is shown for insertion or copying. These settings do not guarantee different wording or correct output.

Retries use fresh model sessions. A failed retry preserves the reviewed result; insertion is disabled while a request is pending. Context exhaustion can involve generated output as well as input, so the error does not claim that a short user request is necessarily too long. No response-token cap is imposed: Apple's documented cap can terminate text without an error, which risks offering incomplete text for insertion.

Results belong to the current instruction, style, and source context. Changing any of these, clearing, or closing Compose cancels generation and discards its results. Request identity also rejects late responses from a model call that has already been cancelled. Reopening retains the instruction and style, not a previous editor's generated text. Retry history exists only within the current request.

## Quick Rewrite review

`rewriteSelection` returns a proposal, not permission to replace text. Every changed result requires an Original / Proposed rewrite preview and explicit **Apply** approval (Return); Cancel or Escape leaves the text unchanged. Unchanged and empty results do not open a review. Existing grammar correction actions do not use this AI review path.

Quick Rewrite requires an Apple Natural Language hypothesis score of at least 0.95 for the selection, explicitly requests that language, and rejects changed output without a matching confident detection. This conservative heuristic can decline valid short passages; it is not a calibrated accuracy guarantee or a verifier for mixed-language text. A writing-style preference must not act as a target language. The low-level `rewriteText` helper remains available to opt-in model experiments; the user-facing action uses the guarded `rewriteSelection` path.

The default system model runs first. A typed refusal or guardrail failure permits one retry using Apple's `permissiveContentTransformations` mode, labelled in the review. An exact quotation extraction adds a context-loss warning without another model call. The check covers bare quoted content and quoted content with only the original prefix or suffix retained. It does not detect paraphrased omissions or establish semantic fidelity. Whole-quotation selections and ordinary edits also require review. Compose continues to require users to review and insert its output.

The captured editor, window, selected text, and selection range or markers are revalidated before replacement. The preview may hold keyboard focus, but cannot retarget another editor. Closing the preview or changing the source selection cancels the operation.

This mode does not guarantee correctness: it can return a refusal as text. It is not enabled for open-ended Compose, style suggestions, or readability features; Apple's guided-generation checks also remain in effect. See [Apple's transformation-mode contract](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/guardrails/permissivecontenttransformations).

## Sentence Simplification

`simplifySentence(_:targetAudience:writingStyle:previousSuggestion:)` asks for one simpler version that preserves meaning and matches the selected audience and writing style.

- First request: temperature `0.3`
- Retry: temperature `0.9`, with the rejected suggestion included as an exclusion

Empty output, the unchanged source sentence, and the rejected previous suggestion are filtered out. The coordinator currently generates simplifications for at most the first three complex sentences in one style-analysis pass.

Sentence eligibility comes from `ReadabilityCalculator`: a sentence needs at least 12 words and must score more than 10 Flesch points below the selected audience threshold.

## Readability Tips

`generateReadabilityTips(for:score:targetAudience:)` provides general advice about sentence length, word complexity, passive voice, and clarity.

- Input needs at least five words.
- Analysis context is truncated to the first 1,000 characters.
- Generation uses temperature `0.3`.
- Empty tips are removed.
- The guided result asks for two or three tips shorter than 15 words and no quotation of user text.

Sketch Pad caches tips and rate-limits regeneration so the system model is not called after every edit.

## Error Handling

All operations throw `FoundationModelsError`:

| Error | Meaning |
| --- | --- |
| `notAvailable(StyleEngineStatus)` | The system model cannot run in its current state |
| `generationFailed(String)` | `LanguageModelSession.GenerationError` |
| `analysisError(String)` | Another request or conversion failure |
| `selectionTooLong` | The selected passage exceeds the input budget; no truncation or replacement occurs |

Callers log the failure and keep Harper grammar results available. Foundation Models failures do not disable local grammar checking.

## Privacy and Logging

Requests go to Apple's on-device system model. TextWarden does not send them to a TextWarden service and does not require an API key.

Foundation Models request errors use fixed messages rather than framework debug descriptions, which may contain source text. Engine and guided-result validation logs use metadata instead of source fragments, alternatives, or generated tips. This is not a guarantee for every diagnostic path in the app: users should still review verbose diagnostic exports before sharing.

## Verification Checklist

When changing the integration:

1. Test every availability state and confirm Harper still works when AI is unavailable.
2. Test selected-text and full-field manual checks.
3. Confirm stale automatic results are discarded after editing or changing focus.
4. Test all sampling presets and regeneration paths.
5. Verify custom vocabulary survives style analysis unchanged.
6. Test emoji and composed Unicode characters in source ranges.
7. Confirm replacement validation aborts when the field no longer contains the expected source.
8. Run `make ci-check`.

## References

- [Foundation Models documentation](https://developer.apple.com/documentation/FoundationModels)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [WWDC25: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25: Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/)
