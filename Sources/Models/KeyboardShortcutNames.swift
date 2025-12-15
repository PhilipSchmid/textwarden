//
//  KeyboardShortcutNames.swift
//  TextWarden
//
//  Defines global keyboard shortcuts for the application
//

import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    // MARK: - Global Controls

    /// Toggle TextWarden on/off globally ("T" for TextWarden)
    static let toggleTextWarden = Self("toggleTextWarden", default: .init(.t, modifiers: [.command, .control]))

    /// Trigger style check on current text
    static let runStyleCheck = Self("runStyleCheck", default: .init(.s, modifiers: [.command, .control]))

    /// Fix all errors that have exactly one suggestion (obvious fixes) - "A" for Apply All
    static let fixAllObvious = Self("fixAllObvious", default: .init(.a, modifiers: [.command, .control]))

    // MARK: - Suggestion Popover

    /// Toggle suggestion popover (show if hidden, hide if shown) - "G" for Grammar
    static let showSuggestionPopover = Self("showSuggestionPopover", default: .init(.g, modifiers: [.command, .control]))

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

    // MARK: - Popover Shortcuts Management

    /// All shortcuts that should only be active when the popover is visible
    /// These are disabled at startup and enabled/disabled dynamically
    static let popoverShortcuts: [KeyboardShortcuts.Name] = [
        .acceptSuggestion,
        .dismissSuggestion,
        .previousSuggestion,
        .nextSuggestion,
        .applySuggestion1,
        .applySuggestion2,
        .applySuggestion3
    ]

    /// Enable all popover-specific shortcuts
    static func enablePopoverShortcuts() {
        for shortcut in popoverShortcuts {
            KeyboardShortcuts.enable(shortcut)
        }
    }

    /// Disable all popover-specific shortcuts
    static func disablePopoverShortcuts() {
        for shortcut in popoverShortcuts {
            KeyboardShortcuts.disable(shortcut)
        }
    }
}
