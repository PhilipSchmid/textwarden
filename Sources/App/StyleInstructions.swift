// StyleInstructions.swift
// Writing style instructions for Foundation Models

import Foundation

/// Builds comprehensive instructions for Foundation Models style analysis
struct StyleInstructions {

    // MARK: - Public API

    /// Build instructions for a specific writing style
    /// - Parameters:
    ///   - style: The writing style to optimize for
    ///   - customVocabulary: Optional list of terms to preserve (don't suggest changes for)
    /// - Returns: Complete instructions string for Foundation Models
    static func build(for style: WritingStyle, customVocabulary: [String] = []) -> String {
        var instructions = baseInstructions
        instructions += "\n\n" + styleSpecificInstructions(for: style)

        if !customVocabulary.isEmpty {
            instructions += "\n\n" + vocabularyContext(customVocabulary)
        }

        return instructions
    }

    // MARK: - Base Instructions

    private static var baseInstructions: String {
        """
        You are a professional writing style assistant.

        TASK: Analyze the provided text and suggest improvements for clarity, \
        readability, and style. Focus on making the writing more effective.

        RULES:
        1. The "original" field MUST be an exact verbatim substring from the input text.
        2. Do not suggest changes to technical terms, proper nouns, or domain-specific jargon.
        3. Preserve the original meaning - only improve how it's expressed.
        4. Only suggest changes that meaningfully improve the text.
        5. Return an empty suggestions list if the text is already well-written.
        6. Keep explanations brief (1-2 sentences max).
        7. Focus on one improvement per suggestion - don't combine multiple changes.

        AVOID suggesting changes for:
        - Correctly spelled words that are uncommon
        - Industry-standard terminology
        - Intentional stylistic choices (e.g., fragments for emphasis)
        - Names, brands, or proper nouns
        - Code snippets, URLs, or technical identifiers
        """
    }

    // MARK: - Style-Specific Instructions

    private static func styleSpecificInstructions(for style: WritingStyle) -> String {
        switch style {
        case .formal:
            return formalStyleInstructions
        case .informal:
            return informalStyleInstructions
        case .business:
            return businessStyleInstructions
        case .concise:
            return conciseStyleInstructions
        case .default:
            return defaultStyleInstructions
        }
    }

    private static var formalStyleInstructions: String {
        """
        STYLE: Formal/Professional

        Optimize for professional, academic, or official communication:
        - Prefer precise, professional vocabulary
        - Avoid contractions (don't → do not, won't → will not)
        - Use complete sentences with proper structure
        - Maintain objective, impersonal tone
        - Prefer third person over first person where appropriate
        - Use passive voice where it adds formality or objectivity
        - Avoid colloquialisms and slang

        Examples of improvements:
        - "gonna" → "going to"
        - "a lot of" → "numerous" or "many"
        - "get" → "obtain" or "receive" (context-dependent)
        - "I think" → "It appears" or remove hedging
        """
    }

    private static var informalStyleInstructions: String {
        """
        STYLE: Informal/Conversational

        Optimize for friendly, approachable communication:
        - Use natural, conversational language
        - Contractions are preferred (do not → don't, will not → won't)
        - Shorter sentences are better
        - Active voice is strongly preferred
        - First person is fine and often preferred
        - Can use colloquial expressions appropriately
        - Avoid overly formal or stiff language

        Examples of improvements:
        - "do not" → "don't"
        - "utilize" → "use"
        - "In order to" → "To"
        - "It is important to note that" → remove or simplify
        """
    }

    private static var businessStyleInstructions: String {
        """
        STYLE: Business Communication

        Optimize for clear, professional business writing:
        - Clear, action-oriented language
        - Concise sentences - get to the point quickly
        - Professional but not overly formal
        - Focus on clarity over elegance
        - Avoid jargon unless industry-standard
        - Use active voice for directness
        - Be specific rather than vague

        Examples of improvements:
        - "Please be advised that" → remove
        - "at this point in time" → "now"
        - "in the event that" → "if"
        - "with regard to" → "about" or "regarding"
        """
    }

    private static var conciseStyleInstructions: String {
        """
        STYLE: Concise/Minimalist

        Optimize for brevity and efficiency:
        - Remove unnecessary words ruthlessly
        - Prefer shorter alternatives (utilize → use, in order to → to)
        - One idea per sentence
        - Cut filler phrases (basically, actually, really, very, just)
        - Eliminate redundancy and repetition
        - Remove weak qualifiers
        - Convert nominalizations back to verbs

        Examples of improvements:
        - "due to the fact that" → "because"
        - "in spite of the fact that" → "although"
        - "make a decision" → "decide"
        - "conduct an investigation" → "investigate"
        - "very unique" → "unique"
        - "past history" → "history"
        """
    }

    private static var defaultStyleInstructions: String {
        """
        STYLE: Balanced/General

        Optimize for clear, natural writing:
        - Natural, clear writing that flows well
        - Mix of sentence lengths for good rhythm
        - Active voice preferred but not required
        - Professional yet approachable tone
        - Remove obvious wordiness
        - Fix awkward phrasing

        Focus on improvements that any reader would appreciate:
        - Clarity over cleverness
        - Smooth flow between sentences
        - Appropriate level of detail
        """
    }

    // MARK: - Custom Vocabulary

    private static func vocabularyContext(_ words: [String]) -> String {
        let wordList = words.joined(separator: ", ")
        return """
        CUSTOM VOCABULARY (do not suggest changes for these terms):
        \(wordList)

        These terms are intentional and should be preserved exactly as written.
        """
    }
}
