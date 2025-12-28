//
//  ReplacementValidator.swift
//  TextWarden
//
//  Validates replacement context before executing text replacement.
//  Prevents replacing wrong text if indices have shifted since analysis.
//

import Foundation
@preconcurrency import ApplicationServices

/// Validates replacement context to ensure safe text replacement
struct ReplacementValidator {

    // MARK: - Validation

    /// Validate the replacement context before executing.
    /// Returns an error if validation fails, nil if validation passes.
    /// - Parameter context: The replacement context to validate
    /// - Returns: ReplacementError if validation fails, nil if valid
    func validate(_ context: ReplacementContext) -> ReplacementError? {
        let textToValidate = context.currentText

        // 1. Validate element is still valid
        if let elementError = validateElement(context.element) {
            return elementError
        }

        // 2. Validate indices are within bounds
        if let boundsError = validateBounds(context, in: textToValidate) {
            return boundsError
        }

        // 3. Validate text at position matches expected
        if let mismatchError = validateTextMatch(context, in: textToValidate) {
            return mismatchError
        }

        return nil
    }

    // MARK: - Element Validation

    /// Validate the AX element is still valid and accessible
    private func validateElement(_ element: AXUIElement) -> ReplacementError? {
        // Check if element responds to basic attribute query
        var roleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)

        if result != .success {
            Logger.warning(
                "ReplacementValidator: Element no longer valid (AX error: \(result.rawValue))",
                category: Logger.analysis
            )
            return .elementInvalid
        }

        return nil
    }

    // MARK: - Bounds Validation

    /// Validate Harper indices are within text bounds
    private func validateBounds(_ context: ReplacementContext, in text: String) -> ReplacementError? {
        let scalars = text.unicodeScalars
        let scalarCount = scalars.count

        // Check start index
        if context.harperRange.lowerBound < 0 || context.harperRange.lowerBound >= scalarCount {
            Logger.warning(
                "ReplacementValidator: Start index \(context.harperRange.lowerBound) out of bounds (text has \(scalarCount) scalars)",
                category: Logger.analysis
            )
            return .indexOutOfBounds(index: context.harperRange.lowerBound, textLength: scalarCount)
        }

        // Check end index
        if context.harperRange.upperBound < 0 || context.harperRange.upperBound > scalarCount {
            Logger.warning(
                "ReplacementValidator: End index \(context.harperRange.upperBound) out of bounds (text has \(scalarCount) scalars)",
                category: Logger.analysis
            )
            return .indexOutOfBounds(index: context.harperRange.upperBound, textLength: scalarCount)
        }

        return nil
    }

    // MARK: - Text Match Validation

    /// Validate text at the error position matches what we expect to replace
    private func validateTextMatch(_ context: ReplacementContext, in text: String) -> ReplacementError? {
        // Extract text at the current position using Harper indices
        guard let actualText = TextIndexConverter.extractErrorText(
            start: context.harperRange.lowerBound,
            end: context.harperRange.upperBound,
            from: text
        ) else {
            Logger.warning(
                "ReplacementValidator: Failed to extract text at \(context.harperRange)",
                category: Logger.analysis
            )
            return .textMismatch(expected: context.errorText, actual: "")
        }

        // Compare with expected error text
        if actualText != context.errorText {
            Logger.warning(
                "ReplacementValidator: Text mismatch - expected '\(context.errorText)' but found '\(actualText)'",
                category: Logger.analysis
            )
            return .textMismatch(expected: context.errorText, actual: actualText)
        }

        return nil
    }
}
