//
//  AppBehavior.swift
//  TextWarden
//
//  Complete behavior specification for overlay visibility and popover management.
//  Each app MUST define ALL values - no defaults, no inheritance.
//
//  This protocol replaces category-based grouping (e.g., .electron, .native)
//  with per-app isolation to prevent cross-app contamination.
//

import Foundation

// MARK: - App Behavior Protocol

/// Complete behavior specification for a single application's overlay system.
/// Each app MUST define ALL values - no defaults, no inheritance.
///
/// This protocol captures:
/// - When to show/hide underlines
/// - Popover appearance and behavior
/// - Scroll and mouse handling
/// - App-specific positioning quirks
/// - Timing profiles
///
/// Design principle: Every app is completely isolated. Changing Slack's behavior
/// cannot affect Notion's behavior, and vice versa.
protocol AppBehavior {
    // MARK: - Identity

    /// The bundle identifier this behavior applies to
    var bundleIdentifier: String { get }

    /// Human-readable display name
    var displayName: String { get }

    // MARK: - Underline Visibility

    /// Configuration for when and how to show underlines
    var underlineVisibility: UnderlineVisibilityBehavior { get }

    // MARK: - Popover Behavior

    /// Configuration for popover appearance and interaction
    var popoverBehavior: PopoverBehavior { get }

    // MARK: - Scroll Handling

    /// Configuration for scroll-related overlay behavior
    var scrollBehavior: ScrollBehavior { get }

    // MARK: - Mouse Handling

    /// Configuration for mouse-related overlay behavior
    var mouseBehavior: MouseBehavior { get }

    // MARK: - Coordinate System

    /// Configuration for coordinate system handling
    var coordinateSystem: CoordinateSystemBehavior { get }

    // MARK: - Timing

    /// Timing profile for debouncing and delays
    var timingProfile: TimingProfile { get }

    // MARK: - Known Quirks

    /// Set of known quirks/bugs that require special handling
    var knownQuirks: Set<AppQuirk> { get }

    // MARK: - Text Index System

    /// Whether this app uses UTF-16 code units for text indices.
    /// - Web-based apps (Electron/Chromium): true (JavaScript uses UTF-16)
    /// - WebKit-based compose views (Mail, Office): true
    /// - Native macOS apps: false (use grapheme clusters)
    var usesUTF16TextIndices: Bool { get }
}
