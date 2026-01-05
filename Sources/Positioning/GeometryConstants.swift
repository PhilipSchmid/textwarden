//
//  GeometryConstants.swift
//  TextWarden
//
//  Centralized constants for geometry validation and bounds checking.
//  These values are used to filter out invalid or suspicious AX API results.
//

import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - BoundedTextPart Protocol

/// Protocol for text parts that can provide bounds for a character range
/// Used by positioning strategies to calculate precise sub-element bounds
protocol BoundedTextPart {
    /// Character range in the full text
    var range: NSRange { get }

    /// Visual bounds from AXFrame (Quartz coordinates)
    var frame: CGRect { get }

    /// AX element reference for querying AXBoundsForRange
    var element: AXUIElement { get }
}

// MARK: - Multi-Part Bounds Calculation

/// Utility for calculating correct bounds when text spans multiple TextParts
enum TextPartBoundsCalculator {
    /// Calculate union bounds for a target range that spans multiple TextParts.
    /// For each overlapping part, calculates sub-element bounds for just the portion within the target range,
    /// rather than using the entire TextPart frame (which could extend into adjacent text).
    ///
    /// - Parameters:
    ///   - targetRange: The character range to calculate bounds for
    ///   - overlappingParts: All TextParts that overlap with the target range
    ///   - getBoundsForRange: Closure to query AXBoundsForRange on a child element
    /// - Returns: Union bounds for all parts, or nil if no bounds could be calculated
    static func calculateMultiPartBounds(
        targetRange: NSRange,
        overlappingParts: [some BoundedTextPart],
        getBoundsForRange: (_ location: Int, _ length: Int, _ element: AXUIElement) -> CGRect?
    ) -> CGRect? {
        let targetEnd = targetRange.location + targetRange.length
        var unionBounds: CGRect?

        for part in overlappingParts {
            // Calculate the intersection of the target range with this part's range
            let partEnd = part.range.location + part.range.length
            let overlapStart = max(targetRange.location, part.range.location)
            let overlapEnd = min(targetEnd, partEnd)
            let overlapLength = overlapEnd - overlapStart

            guard overlapLength > 0 else { continue }

            // Calculate local offset within this TextPart
            let offsetInPart = overlapStart - part.range.location

            // Get sub-element bounds for just this portion
            if let partBounds = getBoundsForRange(offsetInPart, overlapLength, part.element),
               partBounds.width > 0, partBounds.height > 0, partBounds.height < 50
            {
                if let existing = unionBounds {
                    unionBounds = existing.union(partBounds)
                } else {
                    unionBounds = partBounds
                }
            } else {
                // Fallback to full frame if sub-element bounds fail
                if let existing = unionBounds {
                    unionBounds = existing.union(part.frame)
                } else {
                    unionBounds = part.frame
                }
            }
        }

        return unionBounds
    }
}

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
    static let typicalLineHeightRange: ClosedRange<CGFloat> = 15 ... 50

    /// Expected minimum line height for multi-line detection
    static let multiLineThresholdHeight: CGFloat = 35

    // MARK: - Confidence Thresholds

    /// Minimum confidence for geometry result to be usable
    static let minimumUsableConfidence: Double = 0.5

    /// High confidence when using real AX positioning data
    static let highConfidence: Double = 0.95

    /// Reliable confidence when using real AX data with minor estimation
    static let reliableConfidence: Double = 0.90

    /// Good confidence when using cursor/insertion point info
    static let goodConfidence: Double = 0.85

    /// Medium confidence for estimated or fallback positioning
    static let mediumConfidence: Double = 0.75

    /// Lower confidence for heuristic-based positioning
    static let lowerConfidence: Double = 0.65

    /// Low confidence for multi-line or cross-line estimation
    static let lowConfidence: Double = 0.60

    // MARK: - Line Height Estimation

    /// Default line height fallback when detection fails
    static let defaultLineHeight: CGFloat = 20.0

    /// Minimum line height for any text
    static let minimumLineHeight: CGFloat = 12.0

    /// Line height multiplier for font size estimation (fontSize * 1.3)
    static let lineHeightMultiplier: CGFloat = 1.3

    /// Larger line height multiplier for expected heights (fontSize * 1.5)
    static let largerLineHeightMultiplier: CGFloat = 1.5

    /// Even larger multiplier for cursor-based calculations (fontSize * 1.6)
    static let cursorLineHeightMultiplier: CGFloat = 1.6

    /// Multiplier for detecting suspiciously tall lines (normalHeight * 1.5)
    static let suspiciousHeightMultiplier: CGFloat = 1.5

    /// Estimated last line width as percentage of full width
    static let lastLineWidthRatio: CGFloat = 0.7

    /// Normal line height for typical text (16px)
    static let normalLineHeight: CGFloat = 16.0

    /// Minimum line height for constrained layouts (Messages)
    static let constrainedMinLineHeight: CGFloat = 18.0

    /// Maximum line height for constrained layouts (Messages)
    static let constrainedMaxLineHeight: CGFloat = 26.0

    /// Maximum single line height before using normalLineHeight fallback
    static let maxSingleLineHeight: CGFloat = 30.0

    // MARK: - Chromium/Electron Delays (microseconds for usleep)

    /// Short delay for Chromium AX processing (15ms)
    static let chromiumShortDelay: UInt32 = 15000

    /// Medium delay for Chromium operations (20ms)
    static let chromiumMediumDelay: UInt32 = 20000

    /// Delay between key presses (1ms)
    static let keyPressDelay: UInt32 = 1000

    /// Short UI update delay (5ms)
    static let shortUIDelay: UInt32 = 5000

    // MARK: - Slack-Specific Constants

    /// Debounce interval for Slack click-based recheck (milliseconds)
    /// Prevents excessive recalculation while allowing timely updates
    static let slackRecheckDebounceMs: Int = 200

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
