# Apple Foundation Models Integration

This document describes how TextWarden uses Apple's [Foundation Models framework](https://developer.apple.com/documentation/FoundationModels) for AI-powered features.

## Overview

The Foundation Models framework (macOS 26+) provides access to Apple's ~3B parameter on-device language model that powers Apple Intelligence. TextWarden uses this for:

1. **Style Analysis** - Analyzing text for style improvements
2. **Style Regeneration** - Generating alternative suggestions
3. **AI Compose** - Creating new text based on user instructions
4. **Sentence Simplification** - Simplifying complex sentences for target audiences

All processing happens **on-device** with complete privacy and no API costs.

### Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon Mac
- Apple Intelligence enabled in System Settings → Apple Intelligence & Siri

### Availability States

The engine checks availability before every operation:

| Status | Description | User Action |
|--------|-------------|-------------|
| `available` | Ready to use | None |
| `appleIntelligenceNotEnabled` | AI not enabled | Enable in System Settings |
| `deviceNotEligible` | Requires Apple Silicon | Hardware limitation |
| `modelNotReady` | Model downloading/preparing | Wait and retry |

## Key Concepts

### @Generable Types (Guided Generation)

Foundation Models uses **guided generation** to ensure structured, predictable output. TextWarden defines `@Generable` structs with `@Guide` annotations:

```swift
@Generable
struct FMStyleSuggestion {
    @Guide(description: "The exact phrase from the input text...")
    let original: String

    @Guide(description: "The improved version of the phrase...")
    let suggested: String

    @Guide(description: "Brief explanation, max 10 words...")
    let explanation: String
}
```

The model generates instances of these types, ensuring output always matches the expected structure.

### Temperature Configuration

Temperature controls randomness vs determinism. TextWarden uses **conservative values** because grammar/style tasks require accuracy over creativity:

| Preset | Temperature | Sampling | Use Case |
|--------|-------------|----------|----------|
| Consistent | 0.0 | Greedy | Deterministic, reproducible |
| Balanced | 0.3 | Temperature | Default, slight variation |
| Creative | 0.5 | Temperature | More variety (regeneration) |

Higher temperatures increase hallucination risk, so values are intentionally kept low.

### LanguageModelSession

Each operation creates a **fresh** `LanguageModelSession` with task-specific instructions:

```swift
let session = LanguageModelSession(instructions: instructions)
let response = try await session.respond(
    to: prompt,
    generating: FMStyleAnalysisResult.self,
    options: GenerationOptions(temperature: 0.3)
)
```

### Session Architecture: Fresh Per Operation

TextWarden intentionally creates a **new session for each operation** rather than maintaining persistent sessions. This design choice is driven by several factors:

**Why not persistent sessions?**

1. **Token budget constraints** - With only 4,096 tokens total, a persistent session would accumulate history quickly. After 2-3 operations, you'd need complex summarization logic or risk running out of context.

2. **Operations are isolated** - Style analysis of one text has no relevance to generating new text later. Mixing contexts could confuse the model or bias responses.

3. **Predictable behavior** - Fresh sessions ensure consistent, reproducible results. Users expect grammar/style tools to be stateless.

4. **No context pollution** - Each operation gets the full token budget without interference from previous requests.

**How retries work without session history:**

Instead of relying on session memory to "remember" previous outputs, TextWarden uses:

- **Seed-based variation**: Each retry gets a unique seed via `random(top: 40, seed: uniqueSeed)`, guaranteeing different sampling paths
- **Explicit exclusion**: For style regeneration, previous suggestions are passed in the prompt: "Do NOT suggest: X"
- **Higher temperature**: Retries use 0.8 temperature (vs 0.3 for first generation) to encourage variety

This approach provides the benefits of "memory" (avoiding duplicates) without the token overhead of persistent sessions.

## Feature 1: Style Analysis

**Purpose:** Analyze text and suggest style improvements based on user's preferred writing style.

**File:** `Sources/App/FoundationModelsEngine.swift` → `analyzeStyle()`

### Configuration

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Temperature | User-configurable preset | Balanced by default |
| Max suggestions | 5 | Prevent overwhelming user |
| Output type | `FMStyleAnalysisResult` | Array of suggestions |

### System Instructions

Built by `StyleInstructions.build()` in `Sources/App/StyleInstructions.swift`:

```
You are a professional writing style assistant.

TASK: Analyze the provided text and suggest improvements for clarity,
readability, and style.

RULES:
1. The "original" field MUST be an exact verbatim substring
2. The "suggested" field MUST be DIFFERENT from "original"
3. Preserve the original meaning
4. Only suggest meaningful improvements
5. Return empty list if text is already well-written
...
```

### Style-Specific Instructions

Additional instructions are appended based on writing style:

| Style | Focus |
|-------|-------|
| **Formal** | Professional vocabulary, no contractions, objective tone |
| **Informal** | Conversational, contractions preferred, shorter sentences |
| **Business** | Clear, action-oriented, concise |
| **Concise** | Remove unnecessary words, eliminate filler |
| **Default** | Balanced clarity and natural flow |

### Prompt Format

```
Analyze this text for style improvements:

<user's text>
```

### Output Processing

Results are validated and filtered:
1. Reject identical original/suggested (hallucinations)
2. Verify original text exists in input (exact substring)
3. Reject multi-paragraph suggestions
4. Filter overlapping suggestions

## Feature 2: Style Regeneration

**Purpose:** Generate an alternative suggestion when user wants a different option.

**File:** `Sources/App/FoundationModelsEngine.swift` → `regenerateStyleSuggestion()`

### Configuration

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Temperature | 0.5 (moderate) | Encourage variety |
| Exclusion | Previous suggestion | Avoid duplicates |

### System Instructions

Base style instructions plus exclusion:

```
<base style instructions>

IMPORTANT: You must provide a DIFFERENT suggestion than this previous one:
Previous suggestion: "<previous suggested text>"

Provide an alternative way to improve the text. Be creative but accurate.
```

### Prompt Format

```
Provide an alternative style improvement for this text:

<original text>
```

## Feature 3: AI Compose

**Purpose:** Generate new text based on user instructions (e.g., "Write a greeting" or "Summarize this").

**File:** `Sources/App/FoundationModelsEngine.swift` → `generateText()`

### Configuration

| Parameter | First Generation | Retry (with variationSeed) |
|-----------|------------------|---------------------------|
| Sampling | Default | `random(top: 40, seed: <unique>)` |
| Temperature | 0.3 (low) | 0.8 (higher for variety) |
| Context limit | 4,500 chars (~1,500 tokens) | 4,500 chars (~1,500 tokens) |
| Output type | `FMTextGenerationResult` | `FMTextGenerationResult` |

### Token Budget

Apple Foundation Models has a **4,096 token context window** (input + output combined). At ~3-4 characters per token for English:

| Component | Token Budget | Character Budget |
|-----------|--------------|------------------|
| System instructions | ~400 tokens | ~1,200 chars |
| User instruction | ~100 tokens | ~300 chars |
| **Context** | **~1,500 tokens** | **~4,500 chars** |
| Output buffer | ~1,000+ tokens | ~3,000+ chars |

Reference: [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)

### Retry Mechanism

When users click "Retry", the system generates different outputs by:
1. Using **random top-k sampling** (`top: 40`) instead of default sampling
2. Providing a **unique seed** (timestamp XOR counter) for each attempt
3. Using **higher temperature** (0.8) to encourage creative alternatives

This approach is based on Apple's [Foundation Models documentation](https://developer.apple.com/documentation/FoundationModels):
> "You fix the number of available responses and provide a stable seed. As soon as seed changes, the response changes."

### System Instructions

```
You are a text generation assistant. Your ONLY job is to follow the user's instruction exactly.

Critical rules:
- The user's instruction is ABSOLUTE - follow it precisely
- If the user asks for "unrelated" or "random" text, generate completely NEW content
- Do NOT copy, paraphrase, or base your output on any provided context unless explicitly asked
- Context is ONLY provided as optional reference - ignore it unless the instruction refers to it
- Output ONLY the generated text - no explanations, labels, or meta-commentary
- Match the specified writing style
```

### Prompt Format

```
User instruction: <user's instruction>

Writing style: <selected style>

[Optional reference - nearby text for context only]:
"""
<limited context, max 4,500 chars>
"""
```

### Context Handling

Context is provided as **optional reference only**:

| Context Source | Description | Included |
|----------------|-------------|----------|
| Selection | User-selected text | Yes (up to 4,500 chars) |
| Cursor window | Text around cursor | Yes (up to 4,500 chars) |
| Document start | Beginning of short docs | Yes (up to 4,500 chars) |
| None | No context available | Omitted |

**Important:** The user's instruction takes absolute priority over context. If user asks for "unrelated" content, the model should ignore context entirely.

## Feature 4: Sentence Simplification

**Purpose:** Simplify complex sentences to make them appropriate for a target audience's reading level.

**File:** `Sources/App/FoundationModelsEngine.swift` → `simplifySentence()`

### How It Works

When readability analysis identifies sentences that are too complex for the selected target audience (based on Flesch score thresholds), users can hover over the violet dashed underlines to get AI-powered simplification suggestions.

### Target Audiences

| Audience | Min Flesch Score | Grade Level | Description |
|----------|------------------|-------------|-------------|
| Accessible | 70+ | ~7th grade | Everyone should understand |
| General | 60+ | ~9th grade | Average adult reader |
| Professional | 50+ | ~11th grade | Business readers |
| Technical | 40+ | College | Specialized readers |
| Academic | 30+ | Graduate | Academic/research |

### Configuration

| Parameter | First Generation | Regeneration |
|-----------|------------------|--------------|
| Temperature | Low (0.3) | High (0.9) |
| Output type | `FMSentenceSimplificationResult` | `FMSentenceSimplificationResult` |

### System Instructions

```
You are a readability expert. Your task is to simplify sentences for a specific target audience.

Target audience: <audience name> (<description>)
Target reading level: <grade level>
Writing style: <selected style>

Simplification guidelines:
- Break long sentences into shorter ones if needed
- Replace complex words with simpler alternatives
- Use active voice instead of passive voice
- Remove unnecessary jargon and filler words
- Preserve the core meaning exactly
- Match the specified writing style
- Do NOT add information that wasn't in the original
```

### Regeneration

When a user clicks "Retry", the system:
1. Passes the previous suggestion in the prompt with explicit exclusion instruction
2. Uses higher temperature (0.9) to encourage variety
3. Filters out alternatives identical to the previous suggestion

### Output Processing

Results are filtered to remove:
1. Empty alternatives
2. Alternatives identical to the original sentence
3. Alternatives identical to the previous suggestion (for regeneration)

## @Generable Type Definitions

Located in `Sources/App/StyleTypes+Generable.swift`:

### FMStyleSuggestion

```swift
@Generable
struct FMStyleSuggestion {
    @Guide(description: "The exact phrase from the input text that should be improved. Must be a verbatim substring.")
    let original: String

    @Guide(description: "The improved version. MUST be different from original.")
    let suggested: String

    @Guide(description: "Brief explanation, maximum 10 words.")
    let explanation: String
}
```

### FMStyleAnalysisResult

```swift
@Generable
struct FMStyleAnalysisResult {
    @Guide(description: "List of suggestions. Return empty array if text is well-written. Maximum 5 suggestions.")
    let suggestions: [FMStyleSuggestion]
}
```

### FMTextGenerationResult

```swift
@Generable
struct FMTextGenerationResult {
    @Guide(description: "The generated text. Ready to insert directly. No explanations or meta-commentary.")
    let generatedText: String
}
```

### FMSentenceSimplificationResult

```swift
@Generable
struct FMSentenceSimplificationResult {
    @Guide(description: "A single simplified version of the sentence in an array.")
    let alternatives: [String]
}
```

## Error Handling

All operations throw `FoundationModelsError`:

| Error | Cause | Recovery |
|-------|-------|----------|
| `notAvailable` | AI not ready/eligible | Check `status.canRetry` |
| `generationFailed` | Model error | Retry or show error |
| `analysisError` | Other failures | Show error to user |

## Performance

### Prewarming

Call `prewarm()` on app launch to reduce first-response latency:

```swift
Task {
    await foundationModelsEngine.prewarm()
}
```

### Typical Latency

- Style analysis: 0.5-2.0s (depends on text length)
- Regeneration: 0.5-1.5s
- Text generation: 0.5-2.0s (depends on output length)

## References

- [Foundation Models Documentation](https://developer.apple.com/documentation/FoundationModels)
- [WWDC25: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25: Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/)
- [Apple Machine Learning Research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
