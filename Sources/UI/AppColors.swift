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
            ? Color(hue: 0, saturation: 0, brightness: 0.14)  // Slightly lighter for Tahoe feel
            : Color(hue: 0, saturation: 0, brightness: 0.98)  // 98% lightness - very light
    }

    /// Gradient background for elevated popovers (Tahoe style)
    var backgroundGradientTop: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.18)  // Lighter at top
            : Color(hue: 0, saturation: 0, brightness: 0.995) // Almost white at top
    }

    var backgroundGradientBottom: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.12)  // Darker at bottom
            : Color(hue: 220/360, saturation: 0.02, brightness: 0.94)  // Subtle cool gray at bottom
    }

    /// Secondary background (cards, elevated surfaces)
    var backgroundElevated: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.10)  // 10% lightness
            : Color(hue: 220/360, saturation: 0.03, brightness: 0.92)  // Subtle cool tint
    }

    /// Tertiary background (highest elevation, hover states)
    var backgroundRaised: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.15)  // 15% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.92)  // 92% lightness
    }

    /// Primary text (high contrast but not harsh)
    var textPrimary: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.95)  // 95% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.25)  // Soft dark gray (not black)
    }

    /// Secondary text (muted, labels, captions)
    var textSecondary: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.65)  // 65% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.50)  // Softer gray
    }

    /// Tertiary text (most muted, placeholders)
    var textTertiary: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.50)  // 50% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.65)  // Light gray
    }

    /// Border color (subtle separation)
    var border: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.20)  // 20% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.80)  // More visible in light mode
    }

    /// Border color for emphasis
    var borderEmphasis: Color {
        colorScheme == .dark
            ? Color(hue: 0, saturation: 0, brightness: 0.30)  // 30% lightness
            : Color(hue: 0, saturation: 0, brightness: 0.75)  // 75% lightness
    }

    // MARK: - Primary/Brand Color (Blue-ish)

    /// Primary brand color (blue)
    var primary: Color {
        colorScheme == .dark
            ? Color(hue: 215/360, saturation: 0.75, brightness: 0.65)  // Rich blue for dark mode
            : Color(hue: 215/360, saturation: 0.70, brightness: 0.55)  // Slightly darker for light mode
    }

    /// Primary color hover state
    var primaryHover: Color {
        colorScheme == .dark
            ? Color(hue: 215/360, saturation: 0.75, brightness: 0.75)  // Lighter on hover
            : Color(hue: 215/360, saturation: 0.70, brightness: 0.45)  // Darker on hover
    }

    /// Primary color subtle background
    var primarySubtle: Color {
        colorScheme == .dark
            ? Color(hue: 215/360, saturation: 0.60, brightness: 0.20)  // Muted blue bg
            : Color(hue: 215/360, saturation: 0.40, brightness: 0.92)  // Light blue bg
    }

    /// Text on primary color background
    var textOnPrimary: Color {
        Color.white  // White text on blue in both modes
    }

    // MARK: - Semantic Colors (States)

    /// Success state (green)
    var success: Color {
        colorScheme == .dark
            ? Color(hue: 145/360, saturation: 0.60, brightness: 0.55)
            : Color(hue: 145/360, saturation: 0.55, brightness: 0.45)
    }

    /// Success subtle background
    var successSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 145/360, saturation: 0.50, brightness: 0.18)
            : Color(hue: 145/360, saturation: 0.35, brightness: 0.92)
    }

    /// Warning state (orange/amber)
    var warning: Color {
        colorScheme == .dark
            ? Color(hue: 35/360, saturation: 0.80, brightness: 0.65)
            : Color(hue: 35/360, saturation: 0.75, brightness: 0.55)
    }

    /// Warning subtle background
    var warningSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 35/360, saturation: 0.60, brightness: 0.20)
            : Color(hue: 35/360, saturation: 0.45, brightness: 0.92)
    }

    /// Error state (red)
    var error: Color {
        colorScheme == .dark
            ? Color(hue: 0/360, saturation: 0.75, brightness: 0.70)
            : Color(hue: 0/360, saturation: 0.70, brightness: 0.55)
    }

    /// Error subtle background
    var errorSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 0/360, saturation: 0.60, brightness: 0.20)
            : Color(hue: 0/360, saturation: 0.45, brightness: 0.92)
    }

    /// Info state (purple)
    var info: Color {
        colorScheme == .dark
            ? Color(hue: 270/360, saturation: 0.65, brightness: 0.65)
            : Color(hue: 270/360, saturation: 0.60, brightness: 0.55)
    }

    /// Info subtle background
    var infoSubtle: Color {
        colorScheme == .dark
            ? Color(hue: 270/360, saturation: 0.50, brightness: 0.18)
            : Color(hue: 270/360, saturation: 0.35, brightness: 0.92)
    }

    // MARK: - Grammar Category Colors

    /// Get color for grammar error category
    func categoryColor(for category: String) -> Color {
        switch category {
        // Spelling and typos: Red (critical)
        case "Spelling", "Typo":
            return error

        // Grammar and structure: Orange (grammatical correctness)
        case "Grammar", "Agreement", "BoundaryError", "Capitalization", "Nonstandard", "Punctuation":
            return warning

        // Style and enhancement: Primary blue (style improvements)
        case "Style", "Enhancement", "WordChoice", "Readability", "Redundancy", "Formatting":
            return primary

        // Usage and word choice issues: Purple/Info
        case "Usage", "Eggcorn", "Malapropism", "Regionalism", "Repetition":
            return info

        // Miscellaneous: Muted text
        default:
            return textSecondary
        }
    }

    /// Get subtle background color for grammar error category
    func categorySubtleBackground(for category: String) -> Color {
        switch category {
        case "Spelling", "Typo":
            return errorSubtle
        case "Grammar", "Agreement", "BoundaryError", "Capitalization", "Nonstandard", "Punctuation":
            return warningSubtle
        case "Style", "Enhancement", "WordChoice", "Readability", "Redundancy", "Formatting":
            return primarySubtle
        case "Usage", "Eggcorn", "Malapropism", "Regionalism", "Repetition":
            return infoSubtle
        default:
            return backgroundRaised
        }
    }

    // MARK: - Shadow & Effects

    /// Shadow for elevated surfaces
    var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.3 : 0.15)
    }
}

// MARK: - Environment Key

struct AppColorsKey: EnvironmentKey {
    static let defaultValue = AppColors(for: .light)
}

extension EnvironmentValues {
    var appColors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Inject AppColors into environment based on current color scheme
    func withAppColors(_ colorScheme: ColorScheme) -> some View {
        environment(\.appColors, AppColors(for: colorScheme))
    }
}
