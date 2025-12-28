//
//  TextReplacementCoordinator.swift
//  TextWarden
//
//  Main coordinator for text replacement operations.
//  Routes to the appropriate replacement method based on app configuration.
//

import Foundation
@preconcurrency import ApplicationServices

/// Protocol for text replacement coordination
protocol TextReplacementCoordinating: Sendable {
    /// Replace error text with a suggestion
    @MainActor
    func replace(
        error: GrammarErrorModel,
        suggestion: String,
        element: AXUIElement,
        currentText: String,
        appConfig: AppConfiguration
    ) async -> ReplacementResult
}

/// Coordinates text replacement operations across different app types
@MainActor
final class TextReplacementCoordinator: TextReplacementCoordinating {

    // MARK: - Dependencies

    private let validator = ReplacementValidator()
    private let standardReplacement = StandardReplacement()
    private let keyboardReplacement = KeyboardReplacement()

    // MARK: - Initialization

    init() {}

    // MARK: - Main Entry Point

    /// Replace error text with a suggestion.
    /// Routes to the appropriate replacement method based on app configuration.
    /// - Parameters:
    ///   - error: The grammar error to fix
    ///   - suggestion: The replacement text
    ///   - element: The AX element containing the text
    ///   - currentText: Current text content of the element
    ///   - appConfig: Configuration for the target application
    /// - Returns: Result of the replacement operation
    func replace(
        error: GrammarErrorModel,
        suggestion: String,
        element: AXUIElement,
        currentText: String,
        appConfig: AppConfiguration
    ) async -> ReplacementResult {

        Logger.debug(
            "TextReplacementCoordinator: Starting replacement for \(appConfig.identifier) at \(error.start)..<\(error.end)",
            category: Logger.analysis
        )

        // 1. Build context with resolved indices
        guard let context = ReplacementContext(
            element: element,
            appConfig: appConfig,
            currentText: currentText,
            harperStart: error.start,
            harperEnd: error.end,
            replacement: suggestion
        ) else {
            Logger.warning(
                "TextReplacementCoordinator: Failed to build replacement context",
                category: Logger.analysis
            )
            return .failed(.indexOutOfBounds(index: error.start, textLength: currentText.unicodeScalars.count))
        }

        // 2. Validate before replacing
        if let validationError = validator.validate(context) {
            Logger.warning(
                "TextReplacementCoordinator: Validation failed - \(validationError)",
                category: Logger.analysis
            )
            return .failed(validationError)
        }

        // 3. Route by configured method
        let result: ReplacementResult
        switch appConfig.features.textReplacementMethod {
        case .standard:
            result = standardReplacement.execute(context)

        case .browserStyle:
            result = await keyboardReplacement.execute(context)
        }

        // 4. Log result
        switch result {
        case .success:
            Logger.info(
                "TextReplacementCoordinator: Replacement succeeded for \(appConfig.identifier)",
                category: Logger.analysis
            )
        case .unverified:
            Logger.info(
                "TextReplacementCoordinator: Replacement completed (unverified) for \(appConfig.identifier)",
                category: Logger.analysis
            )
        case .failed(let error):
            Logger.warning(
                "TextReplacementCoordinator: Replacement failed - \(error)",
                category: Logger.analysis
            )
        }

        return result
    }

    // MARK: - Convenience

    /// Get the length delta for position adjustment after replacement
    static func lengthDelta(for error: GrammarErrorModel, suggestion: String) -> Int {
        return suggestion.count - (error.end - error.start)
    }
}
