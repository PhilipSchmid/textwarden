//
//  StandardReplacement.swift
//  TextWarden
//
//  Standard text replacement using AX API setValue.
//  Works for native macOS apps with proper accessibility support (Telegram, WebEx, etc.)
//

@preconcurrency import ApplicationServices
import Foundation

/// Standard replacement method using AX API direct text manipulation
struct StandardReplacement {
    // MARK: - Execution

    /// Execute text replacement using AX API setValue.
    /// - Parameter context: The replacement context with resolved indices
    /// - Returns: Result of the replacement operation
    func execute(_ context: ReplacementContext) -> ReplacementResult {
        Logger.debug(
            "StandardReplacement: Executing for \(context.appConfig.identifier) at range \(context.resolvedRange.location)..<\(context.resolvedRange.location + context.resolvedRange.length)",
            category: Logger.analysis
        )

        // 1. Set selection to the error range
        if let error = setSelection(context) {
            return .failed(error)
        }

        // 2. Replace selected text with the replacement
        if let error = replaceSelectedText(context) {
            return .failed(error)
        }

        // 3. Move cursor to end of replacement
        moveCursorAfterReplacement(context)

        Logger.info(
            "StandardReplacement: Successfully replaced '\(context.errorText)' with '\(context.replacement)'",
            category: Logger.analysis
        )

        return .success
    }

    // MARK: - Selection

    /// Set the AX selection to the error range
    private func setSelection(_ context: ReplacementContext) -> ReplacementError? {
        let range = context.resolvedRange
        var cfRange = CFRange(location: range.location, length: range.length)

        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.error("StandardReplacement: Failed to create AXValue for range", category: Logger.analysis)
            return .selectionFailed(axError: -1)
        }

        let result = AXUIElementSetAttributeValue(
            context.element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if result != .success {
            Logger.warning(
                "StandardReplacement: Selection failed with AX error \(result.rawValue)",
                category: Logger.analysis
            )
            return .selectionFailed(axError: result.rawValue)
        }

        return nil
    }

    // MARK: - Replacement

    /// Replace the selected text with the replacement string
    private func replaceSelectedText(_ context: ReplacementContext) -> ReplacementError? {
        let result = AXUIElementSetAttributeValue(
            context.element,
            kAXSelectedTextAttribute as CFString,
            context.replacement as CFString
        )

        if result != .success {
            Logger.warning(
                "StandardReplacement: setValue failed with AX error \(result.rawValue)",
                category: Logger.analysis
            )
            return .axSetValueFailed(axError: result.rawValue)
        }

        return nil
    }

    // MARK: - Cursor Positioning

    /// Move cursor to the end of the replaced text
    private func moveCursorAfterReplacement(_ context: ReplacementContext) {
        let newCursorPosition = context.resolvedRange.location + context.replacement.count
        var cursorRange = CFRange(location: newCursorPosition, length: 0)

        guard let rangeValue = AXValueCreate(.cfRange, &cursorRange) else {
            return
        }

        // Best effort - don't fail if cursor positioning doesn't work
        _ = AXUIElementSetAttributeValue(
            context.element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
    }
}
