//
//  ReplacementResult.swift
//  TextWarden
//
//  Result types for text replacement operations.
//

import Foundation

/// Result of a text replacement operation
enum ReplacementResult: Equatable {
    /// Replacement completed and verified successfully
    case success

    /// Replacement completed but could not be verified
    /// (common for Electron apps where reading back text is unreliable)
    case unverified

    /// Replacement failed with a specific error
    case failed(ReplacementError)
}

/// Errors that can occur during text replacement
enum ReplacementError: Error, Equatable, CustomStringConvertible {

    // MARK: - Validation Errors (abort immediately)

    /// The text at the error position doesn't match what was expected
    case textMismatch(expected: String, actual: String)

    /// The error indices are outside the text bounds
    case indexOutOfBounds(index: Int, textLength: Int)

    /// The monitored element is no longer valid
    case elementInvalid

    // MARK: - Execution Errors

    /// Failed to set the selection range via AX API
    case selectionFailed(axError: Int32)

    /// Failed to set the replacement text via AX API setValue
    case axSetValueFailed(axError: Int32)

    // MARK: - Description

    var description: String {
        switch self {
        case .textMismatch(let expected, let actual):
            return "Text mismatch: expected '\(expected)' but found '\(actual)'"
        case .indexOutOfBounds(let index, let textLength):
            return "Index \(index) out of bounds (text length: \(textLength))"
        case .elementInvalid:
            return "Monitored element is no longer valid"
        case .selectionFailed(let error):
            return "Selection failed with AX error: \(error)"
        case .axSetValueFailed(let error):
            return "AX setValue failed with error: \(error)"
        }
    }
}
