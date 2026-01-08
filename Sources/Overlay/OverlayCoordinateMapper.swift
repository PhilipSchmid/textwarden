//
//  OverlayCoordinateMapper.swift
//  TextWarden
//
//  Handles coordinate system conversions for overlays.
//  Supports app-specific coordinate quirks.
//

import AppKit
import Foundation

// MARK: - Overlay Coordinate Mapper

/// Handles coordinate system conversions between AX, screen, and view coordinates.
///
/// Different apps use different coordinate systems:
/// - Quartz (most AX APIs): Origin at top-left of primary screen
/// - Cocoa (NSWindow/NSView): Origin at bottom-left
/// - Some apps return inverted/flipped coordinates
///
/// This class provides consistent conversions based on the app's behavior.
final class OverlayCoordinateMapper {
    // MARK: - Properties

    /// Current app behavior (for quirk handling)
    private var behavior: AppBehavior?

    // MARK: - Configuration

    /// Configure mapper for a specific app
    func configure(with behavior: AppBehavior?) {
        self.behavior = behavior
    }

    // MARK: - AX to Screen Conversion

    /// Convert AX coordinates to screen coordinates
    /// - Parameters:
    ///   - rect: Rectangle in AX coordinates
    ///   - behavior: App behavior for coordinate system info
    /// - Returns: Rectangle in screen coordinates
    func axToScreen(_ rect: CGRect, behavior: AppBehavior) -> CGRect {
        guard let screen = NSScreen.main else { return rect }
        let screenHeight = screen.frame.height

        var result: CGRect = switch behavior.coordinateSystem.axCoordinateSystem {
        case .quartzTopLeft:
            // Standard AX: origin is top-left, need to flip Y for Cocoa
            CGRect(
                x: rect.origin.x,
                y: screenHeight - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )

        case .cocoaBottomLeft:
            // Already in screen coordinates
            rect

        case .flipped:
            // Y is inverted relative to Quartz - no additional flip needed
            rect
        }

        // Apply quirk corrections
        result = applyQuirks(result, behavior: behavior)

        return result
    }

    /// Convert AX coordinates to screen coordinates using configured behavior
    func axToScreen(_ rect: CGRect) -> CGRect {
        guard let behavior else { return rect }
        return axToScreen(rect, behavior: behavior)
    }

    // MARK: - Screen to View Conversion

    /// Convert screen coordinates to view coordinates
    /// - Parameters:
    ///   - rect: Rectangle in screen coordinates
    ///   - view: Target view
    /// - Returns: Rectangle in view coordinates
    func screenToView(_ rect: CGRect, in view: NSView) -> CGRect {
        guard let window = view.window else { return rect }

        let windowRect = window.convertFromScreen(rect)
        return view.convert(windowRect, from: nil)
    }

    // MARK: - View to Screen Conversion

    /// Convert view coordinates to screen coordinates
    /// - Parameters:
    ///   - rect: Rectangle in view coordinates
    ///   - view: Source view
    /// - Returns: Rectangle in screen coordinates
    func viewToScreen(_ rect: CGRect, in view: NSView) -> CGRect {
        guard let window = view.window else { return rect }

        let windowRect = view.convert(rect, to: nil)
        return window.convertToScreen(windowRect)
    }

    // MARK: - Quirk Handling

    /// Apply app-specific coordinate quirks
    private func applyQuirks(_ rect: CGRect, behavior: AppBehavior) -> CGRect {
        var result = rect

        // Handle negative X coordinates (Slack quirk)
        if behavior.knownQuirks.contains(.negativeXCoordinates), result.origin.x < 0 {
            Logger.trace(
                "Correcting negative X coordinate: \(result.origin.x)",
                category: Logger.ui
            )
            result.origin.x = 0
        }

        // Handle zero frame for offscreen (Teams quirk)
        if behavior.knownQuirks.contains(.zeroFrameForOffscreen), result == .zero {
            Logger.trace(
                "Detected zero frame for offscreen element",
                category: Logger.ui
            )
            return .null // Signal invalid bounds
        }

        return result
    }

    // MARK: - Line Height Compensation

    /// Apply line height compensation to bounds
    /// - Parameters:
    ///   - rect: Original bounds
    ///   - behavior: App behavior for compensation settings
    /// - Returns: Compensated bounds
    func applyLineHeightCompensation(_ rect: CGRect, behavior: AppBehavior) -> CGRect {
        switch behavior.coordinateSystem.lineHeightCompensation {
        case .none:
            return rect

        case let .fixed(points):
            return CGRect(
                x: rect.origin.x,
                y: rect.origin.y - points / 2,
                width: rect.width,
                height: rect.height + points
            )

        case let .percentage(multiplier):
            let heightDelta = rect.height * (multiplier - 1.0)
            return CGRect(
                x: rect.origin.x,
                y: rect.origin.y - heightDelta / 2,
                width: rect.width,
                height: rect.height + heightDelta
            )

        case .detectFromFont:
            // Font-based detection would require access to font metrics
            // For now, apply a sensible default
            return rect
        }
    }

    // MARK: - Bounds Validation

    /// Check if bounds are valid for display
    /// - Parameters:
    ///   - rect: Bounds to validate
    ///   - behavior: App behavior for validation rules
    /// - Returns: true if bounds are valid
    func isValidBounds(_ rect: CGRect, behavior: AppBehavior) -> Bool {
        // Basic sanity checks
        guard rect.width > 0, rect.height > 0 else { return false }
        guard !rect.isNull, !rect.isInfinite else { return false }

        // App-specific validation
        switch behavior.underlineVisibility.boundsValidation {
        case .none:
            return true

        case .requirePositiveOrigin:
            return rect.origin.x >= 0 && rect.origin.y >= 0

        case .requireWithinScreen:
            guard let screen = NSScreen.main else { return true }
            return screen.frame.intersects(rect)

        case .requireStable:
            // Stability check is handled by timing, not here
            return true
        }
    }
}
