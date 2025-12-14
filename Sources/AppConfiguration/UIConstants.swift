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

    /// Size of the floating error indicator
    static let indicatorSize: CGFloat = 40

    /// Enlarged size during drag
    static let indicatorDragSize: CGFloat = 45

    /// Popover spacing from indicator (left side, accounts for popover width)
    static let popoverLeftSpacing: CGFloat = 400

    /// Popover spacing from indicator (right side)
    static let popoverRightSpacing: CGFloat = 30

    // MARK: - Underlines

    /// Default underline thickness
    static let underlineThickness: CGFloat = 2.0

    /// Underline vertical offset from baseline
    static let underlineOffset: CGFloat = 2.0

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
