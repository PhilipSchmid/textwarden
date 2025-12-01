//
//  KeyboardShortcutNames.swift
//  TextWarden
//
//  Defines global keyboard shortcuts for the application
//

import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    // MARK: - Grammar Checking

    /// Toggle grammar checking on/off globally
    static let toggleGrammarChecking = Self("toggleGrammarChecking", default: .init(.g, modifiers: [.command, .shift]))

    /// Trigger style check on current text
    static let runStyleCheck = Self("runStyleCheck", default: .init(.s, modifiers: [.command, .shift]))

    // MARK: - Suggestion Popover

    /// Accept the currently selected suggestion
    static let acceptSuggestion = Self("acceptSuggestion", default: .init(.tab))

    /// Dismiss/close the suggestion popover (Option+Escape to avoid conflicts with other apps)
    static let dismissSuggestion = Self("dismissSuggestion", default: .init(.escape, modifiers: .option))

    /// Navigate to previous error/suggestion (Option + Left Arrow)
    static let previousSuggestion = Self("previousSuggestion", default: .init(.leftArrow, modifiers: .option))

    /// Navigate to next error/suggestion (Option + Right Arrow)
    static let nextSuggestion = Self("nextSuggestion", default: .init(.rightArrow, modifiers: .option))

    // MARK: - Quick Actions

    /// Apply first suggestion (⌥1)
    static let applySuggestion1 = Self("applySuggestion1", default: .init(.one, modifiers: .option))

    /// Apply second suggestion (⌥2)
    static let applySuggestion2 = Self("applySuggestion2", default: .init(.two, modifiers: .option))

    /// Apply third suggestion (⌥3)
    static let applySuggestion3 = Self("applySuggestion3", default: .init(.three, modifiers: .option))
}
