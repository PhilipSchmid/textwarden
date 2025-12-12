//
//  GeometryConstants.swift
//  TextWarden
//
//  Centralized constants for geometry validation and bounds checking.
//  These values are used to filter out invalid or suspicious AX API results.
//

import Foundation
import CoreGraphics

/// Constants for validating geometry bounds from accessibility APIs
enum GeometryConstants {
    // MARK: - Bounds Validation

    /// Minimum width/height to consider bounds valid (filters Chromium bugs with zero/tiny values)
    static let minimumBoundsSize: CGFloat = 5

    /// Maximum line height to consider valid (filters out window-sized bounds)
    /// Values above this suggest the API returned element frame instead of text bounds
    static let maximumLineHeight: CGFloat = 200

    /// Conservative maximum line height for stricter validation
    static let conservativeMaxLineHeight: CGFloat = 100

    /// Maximum character width for single-character bounds validation
    static let maximumCharacterWidth: CGFloat = 100

    /// Maximum text bounds width (filters out full-width element returns)
    static let maximumTextWidth: CGFloat = 800

    // MARK: - Font Size Estimation

    /// Typical single line height range for font size estimation
    static let typicalLineHeightRange: ClosedRange<CGFloat> = 15...50

    /// Expected minimum line height for multi-line detection
    static let multiLineThresholdHeight: CGFloat = 35

    // MARK: - Confidence Thresholds

    /// Minimum confidence for geometry result to be usable
    static let minimumUsableConfidence: Double = 0.5

    // MARK: - Validation Helpers

    /// Check if bounds represent a valid single-line text region
    static func isValidSingleLineBounds(_ bounds: CGRect) -> Bool {
        bounds.width > 0 &&
        bounds.height > minimumBoundsSize &&
        bounds.height < maximumLineHeight
    }

    /// Check if bounds represent a valid character or small text region
    static func isValidCharacterBounds(_ bounds: CGRect) -> Bool {
        bounds.width > 0 &&
        bounds.width < maximumCharacterWidth &&
        bounds.height > 0 &&
        bounds.height < conservativeMaxLineHeight
    }

    /// Check if bounds are non-zero (basic validity)
    static func hasValidSize(_ bounds: CGRect) -> Bool {
        bounds.width > 0 && bounds.height > 0
    }
}
