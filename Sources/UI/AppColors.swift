//
//  AppColors.swift
//  TextWarden
//
//  Modern color schema following HSL-based design principles
//  - Neutral colors for backgrounds, text, and borders
//  - Blue-ish primary/brand color
//  - Semantic colors for states
//  - Full light and dark mode support
//

import SwiftUI

/// Modern color schema for TextWarden's UI
/// Based on HSL color format for harmonious, programmatic shade generation
struct AppColors {
    // MARK: - Color Scheme Context

    let colorScheme: ColorScheme

    init(for colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }

    // MARK: - Neutral Colors (Backgrounds, Text, Borders)

    /// Primary background (darkest in dark mode, lightest in light mode)
    var background: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.14) // Slightly lighter for Tahoe feel
            : Color(hue: 0, saturation: 0, brightness: 0.98) // 98% lightness - very light
    }

    /// Gradient background for elevated popovers (Tahoe style)
    /// Dark mode uses subtle blue-gray tint for a more modern, refined look
    var backgroundGradientTop: Color {
        colorScheme == .dark
            ? Color(hue: 220 / 360, saturation: 0.08, brightness: 0.20) // Subtle blue-gray, lighter at top
            : Color(hue: 220 / 360, saturation: 0.02, brightness: 0.995) // Almost white with cool hint
    }

    var backgroundGradientBottom: Color {
        colorScheme == .dark
            ? Color(hue: 220 / 360, saturation: 0.10, brightness: 0.13) // Subtle blue-gray, darker at bottom
            : Color(hue: 220 / 360, saturation: 0.04, brightness: 0.96) // Soft cool gray at bottom
    }

    /// Secondary background (cards, elevated surfaces)
    var backgroundElevated: Color {
        colorScheme == .dark
            ? Color(hue: 220 / 360, saturation: 0.12, brightness: 0.11) // Subtle blue-gray tint
            : Color(hue: 220 / 360, saturation: 0.03, brightness: 0.94) // Subtle cool tint
    }

    /// Tertiary background (highest elevation, hover states)
    var backgroundRaised: Color {
        colorScheme == .dark
            ? Color(hue: 220 / 360, saturation: 0.10, brightness: 0.18) // Blue-gray for hover
            : Color(hue: 220 / 360, saturation: 0.02, brightness: 0.92) // Cool gray
    }

    /// Primary text (high contrast but not harsh)
    var textPrimary: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.95) // 95% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.25) // Soft dark gray (not black)
    }

    /// Secondary text (muted, labels, captions)
    var textSecondary: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.65) // 65% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.50) // Softer gray
    }

    /// Tertiary text (most muted, placeholders)
    var textTertiary: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.50) // 50% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.65) // Light gray
    }

    /// Border color (subtle separation)
    var border: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.20) // 20% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.80) // More visible in light mode
    }

    /// Border color for emphasis
    var borderEmphasis: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.30) // 30% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.75) // 75% lightness
    }

    // MARK: - Primary/Brand Color (Blue-ish)

    /// Primary brand color (blue)
    var primary: Color {
        colorScheme == .dark
            ? Color(hue: 215 / 360, saturation: 0.75, brightness: 0.65) // Rich blue for dark mode
            : Color(hue: 215 / 360, saturation: 0.70, brightness: 0.55) // Slightly darker for light mode
    }

    /// Primary color hover state
    var primaryHover: Color {
        colorScheme == .dark
            ? Color(hue: 215 / 360, saturation: 0.75, brightness: 0.75) // Lighter on hover
            : Color(hue: 215 / 360, saturation: 0.70, brightness: 0.45) // Darker on hover
    }

    /// Primary color subtle background
    var primarySubtle: Color {
        colorScheme == .dark
            ? Color(hue: 215 / 360, saturation: 0.60, brightness: 0.20) // Muted blue bg
            : Color(hue: 215 / 360, saturation: 0.40, brightness: 0.92) // Light blue bg
    }

    /// Text on primary color background
    var textOnPrimary: Color {
        Color.white // White text on blue in both modes
    }

    /// Link/interactive text color - balanced for readability
    /// Uses a refined blue that complements the blue-gray backgrounds
    var link: Color {
        colorScheme == .dark
            ? Color(hue: 205 / 360, saturation: 0.65, brightness: 0.78) // Softer cyan-blue for dark mode
            : Color(hue: 215 / 360, saturation: 0.75, brightness: 0.50) // Rich blue for light mode
    }

    /// Link color for subtle/muted state (e.g., underlines)
    var linkSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 205 / 360, saturation: 0.45, brightness: 0.55)
            : Color(hue: 215 / 360, saturation: 0.45, brightness: 0.55)
    }

    // MARK: - Semantic Colors (States)

    /// Success state (green)
    var success: Color {
        colorScheme == .dark
            ? Color(hue: 145 / 360, saturation: 0.60, brightness: 0.55)
            : Color(hue: 145 / 360, saturation: 0.55, brightness: 0.45)
    }

    /// Success subtle background
    var successSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 145 / 360, saturation: 0.50, brightness: 0.18)
            : Color(hue: 145 / 360, saturation: 0.35, brightness: 0.92)
    }

    /// Warning state (orange/amber)
    var warning: Color {
        colorScheme == .dark
            ? Color(hue: 35 / 360, saturation: 0.80, brightness: 0.65)
            : Color(hue: 35 / 360, saturation: 0.75, brightness: 0.55)
    }

    /// Warning subtle background
    var warningSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 35 / 360, saturation: 0.60, brightness: 0.20)
            : Color(hue: 35 / 360, saturation: 0.45, brightness: 0.92)
    }

    /// Error state (red)
    var error: Color {
        colorScheme == .dark
            ? Color(hue: 0 / 360, saturation: 0.75, brightness: 0.70)
            : Color(hue: 0 / 360, saturation: 0.70, brightness: 0.55)
    }

    /// Error subtle background
    var errorSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 0 / 360, saturation: 0.60, brightness: 0.20)
            : Color(hue: 0 / 360, saturation: 0.45, brightness: 0.92)
    }

    /// Info state (purple)
    var info: Color {
        colorScheme == .dark
            ? Color(hue: 270 / 360, saturation: 0.65, brightness: 0.65)
            : Color(hue: 270 / 360, saturation: 0.60, brightness: 0.55)
    }

    /// Info subtle background
    var infoSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 270 / 360, saturation: 0.50, brightness: 0.18)
            : Color(hue: 270 / 360, saturation: 0.35, brightness: 0.92)
    }

    // MARK: - Unified Suggestion Category Colors

    /// Clarity color (blue) - for readability suggestions
    var clarity: Color {
        colorScheme == .dark
            ? Color(hue: 210 / 360, saturation: 0.70, brightness: 0.65) // Softer blue for dark mode
            : Color(hue: 210 / 360, saturation: 0.65, brightness: 0.50) // Rich blue for light mode
    }

    /// Style color (purple) - for style suggestions
    var style: Color {
        colorScheme == .dark
            ? Color(hue: 280 / 360, saturation: 0.60, brightness: 0.65) // Purple for dark mode
            : Color(hue: 280 / 360, saturation: 0.55, brightness: 0.55) // Purple for light mode
    }

    /// Get color for unified suggestion category
    func categoryColor(for category: SuggestionCategory) -> Color {
        switch category {
        case .correctness:
            error // Red for spelling, grammar, punctuation
        case .clarity:
            clarity // Blue for readability simplifications
        case .style:
            style // Purple for style improvements
        }
    }

    // MARK: - Grammar Category Colors (Legacy)

    /// Get color for grammar error category (legacy Harper categories)
    func categoryColor(for category: String) -> Color {
        switch category {
        // Spelling and typos: Red (critical)
        case "Spelling", "Typo":
            error

        // Grammar and structure: Orange (grammatical correctness)
        case "Grammar", "Agreement", "BoundaryError", "Capitalization", "Nonstandard", "Punctuation":
            warning

        // Style and enhancement: Primary blue (style improvements)
        case "Style", "Enhancement", "WordChoice", "Readability", "Redundancy", "Formatting":
            primary

        // Usage and word choice issues: Purple/Info
        case "Usage", "Eggcorn", "Malapropism", "Regionalism", "Repetition":
            info

        // Miscellaneous: Muted text
        default:
            textSecondary
        }
    }

    /// Get subtle background color for grammar error category
    func categorySubtleBackground(for category: String) -> Color {
        switch category {
        case "Spelling", "Typo":
            errorSubtle
        case "Grammar", "Agreement", "BoundaryError", "Capitalization", "Nonstandard", "Punctuation":
            warningSubtle
        case "Style", "Enhancement", "WordChoice", "Readability", "Redundancy", "Formatting":
            primarySubtle
        case "Usage", "Eggcorn", "Malapropism", "Regionalism", "Repetition":
            infoSubtle
        default:
            backgroundRaised
        }
    }

    // MARK: - Shadow & Effects

    /// Shadow for elevated surfaces
    var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.3 : 0.15)
    }
}

extension EnvironmentValues {
    @Entry var appColors: AppColors = .init(for: .light)
}

// MARK: - View Extension

extension View {
    /// Inject AppColors into environment based on current color scheme
    func withAppColors(_ colorScheme: ColorScheme) -> some View {
        environment(\.appColors, AppColors(for: colorScheme))
    }
}
