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

    // MARK: - Suggestion Popover

    /// Accept the currently selected suggestion
    static let acceptSuggestion = Self("acceptSuggestion", default: .init(.tab))

    /// Dismiss/close the suggestion popover
    static let dismissSuggestion = Self("dismissSuggestion", default: .init(.escape))

    /// Navigate to previous error/suggestion
    static let previousSuggestion = Self("previousSuggestion", default: .init(.upArrow))

    /// Navigate to next error/suggestion
    static let nextSuggestion = Self("nextSuggestion", default: .init(.downArrow))

    // MARK: - Quick Actions

    /// Apply first suggestion (⌘1)
    static let applySuggestion1 = Self("applySuggestion1", default: .init(.one, modifiers: .command))

    /// Apply second suggestion (⌘2)
    static let applySuggestion2 = Self("applySuggestion2", default: .init(.two, modifiers: .command))

    /// Apply third suggestion (⌘3)
    static let applySuggestion3 = Self("applySuggestion3", default: .init(.three, modifiers: .command))
}
