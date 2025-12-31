//
//  UIConstants.swift
//  TextWarden
//
//  Centralized UI constants for the application.
//  Having these in one place makes it easier to maintain visual consistency.
//

import Foundation

/// Centralized UI constants for TextWarden
enum UIConstants {

    // MARK: - Window Dimensions

    /// Minimum window dimension to be considered valid (not a tooltip/popup)
    static let minimumValidWindowSize: CGFloat = 100

    /// Maximum valid text line height in pixels
    static let maximumTextLineHeight: CGFloat = 100

    // MARK: - Floating Indicator

    /// Size of the floating error indicator (circular mode)
    static let indicatorSize: CGFloat = 36

    /// Enlarged size during drag
    static let indicatorDragSize: CGFloat = 41

    // MARK: - Capsule Indicator (when style checking enabled)

    /// Height of each section in the capsule indicator (matches circular indicator size)
    static let capsuleSectionHeight: CGFloat = 36

    /// Width of the capsule indicator (matches circular indicator size)
    static let capsuleWidth: CGFloat = 36

    /// Corner radius for capsule indicator (half of capsuleWidth for rounded ends)
    static let capsuleCornerRadius: CGFloat = 18

    /// Spacing between sections in the capsule (seamless for unified look)
    static let capsuleSectionSpacing: CGFloat = 0

    /// Popover spacing from indicator (accounts for ~400px popover width + centering)
    /// Formula: gap + popoverWidth/2, where gap is visual spacing desired
    static let popoverLeftSpacing: CGFloat = 215   // 15px gap + 200px (half of ~400px popover)
    static let popoverRightSpacing: CGFloat = 215  // 15px gap + 200px (half of ~400px popover)

    // MARK: - Underlines

    /// Default underline thickness
    static let underlineThickness: CGFloat = 2.0

    /// Underline vertical offset from baseline (smaller = closer to text)
    static let underlineOffset: CGFloat = 1.0

    // MARK: - Position Validation

    /// Maximum retries for position synchronization
    static let maxPositionSyncRetries: Int = 20

    /// Delay between position sync retries (ms)
    static let positionSyncRetryDelay: TimeInterval = 0.05

    // MARK: - Error Thresholds

    /// Maximum errors before hiding underlines to avoid visual clutter
    static let maxErrorsForUnderlines: Int = 50

    // MARK: - Animation

    /// Border guide width for indicator drag feedback
    static let borderGuideWidth: CGFloat = 40
}
