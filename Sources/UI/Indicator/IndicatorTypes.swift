//
//  IndicatorTypes.swift
//  TextWarden
//
//  Types and enums for the floating error indicator
//

import Cocoa

// MARK: - Capsule Section Types

/// Section types in the capsule indicator
enum CapsuleSectionType: Int, CaseIterable {
    case grammar = 0 // Upper section
    case style = 1 // Middle section
    case textGeneration = 2 // Lower section (future)
}

/// Visual state per section
enum SectionDisplayState: Equatable {
    // Grammar states
    case grammarCount(Int) // Show error count
    case grammarSuccess // Green tick (0 errors, stays visible)

    // Style states
    case styleIdle // Sparkle icon, ready to check (no animation)
    case styleLoading // Sparkle with spinning border
    case styleCount(Int) // Show suggestion count
    case styleSuccess // Checkmark (0 suggestions after check)

    // Text generation states
    case textGenIdle // Pen icon, ready
    case textGenActive // Generating animation

    case hidden // Section not visible
}

/// Complete state for a section
struct CapsuleSectionState {
    let type: CapsuleSectionType
    var displayState: SectionDisplayState
    var isHovered: Bool
    var ringColor: NSColor

    init(type: CapsuleSectionType, displayState: SectionDisplayState = .hidden, isHovered: Bool = false, ringColor: NSColor = .gray) {
        self.type = type
        self.displayState = displayState
        self.isHovered = isHovered
        self.ringColor = ringColor
    }
}

// MARK: - Shape and Orientation

/// Indicator shape mode
enum IndicatorShape {
    case circle // Grammar-only mode (when style checking disabled)
    case capsule // Grammar + Style mode (when style checking enabled)
}

/// Capsule orientation based on indicator position
enum CapsuleOrientation {
    case vertical // Sections stacked top to bottom (for side attachment)
    case horizontal // Sections arranged left to right (for top/bottom attachment)

    /// Determine orientation based on indicator position preference
    static func from(position: String) -> CapsuleOrientation {
        // Top and Bottom positions → horizontal capsule
        // Center positions → vertical capsule
        if position.hasPrefix("Top") || position.hasPrefix("Bottom") {
            .horizontal
        } else {
            .vertical
        }
    }
}

/// Direction a popover opens from the indicator (shared across all popovers)
enum PopoverOpenDirection {
    case left // Popover opens to the left of indicator
    case right // Popover opens to the right of indicator
    case top // Popover opens above indicator
    case bottom // Popover opens below indicator
}

// MARK: - Indicator Mode

/// High-level mode for the floating indicator
enum IndicatorMode {
    case errors([GrammarErrorModel])
    case styleSuggestions([StyleSuggestionModel])
    case both(errors: [GrammarErrorModel], styleSuggestions: [StyleSuggestionModel])

    var hasErrors: Bool {
        switch self {
        case let .errors(errors): !errors.isEmpty
        case .styleSuggestions: false
        case let .both(errors, _): !errors.isEmpty
        }
    }

    var hasStyleSuggestions: Bool {
        switch self {
        case .errors: false
        case let .styleSuggestions(suggestions): !suggestions.isEmpty
        case let .both(_, suggestions): !suggestions.isEmpty
        }
    }

    var isEmpty: Bool {
        switch self {
        case let .errors(errors): errors.isEmpty
        case let .styleSuggestions(suggestions): suggestions.isEmpty
        case let .both(errors, suggestions): errors.isEmpty && suggestions.isEmpty
        }
    }
}

/// Display mode for the indicator view (visual state)
enum IndicatorDisplayMode {
    case count(Int)
    case sparkle
    case sparkleWithCount(Int)
    case spinning
    case styleCheckComplete // Checkmark to show style check finished successfully
}
