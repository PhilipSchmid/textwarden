//
//  CoordinateMapper.swift
//  TextWarden
//
//  Handles coordinate system conversions
//  macOS has THREE coordinate systems - we handle them all correctly
//

import Foundation
import AppKit

/// Handles coordinate system conversions
/// Accessibility APIs return Quartz coordinates (top-left origin)
/// NSWindow uses Cocoa coordinates (bottom-left origin)
enum CoordinateMapper {

    // MARK: - Coordinate Conversion

    /// Convert from Quartz (top-left origin) to Cocoa (bottom-left origin)
    /// This is the most common conversion needed
    static func toCocoaCoordinates(_ quartzRect: CGRect) -> CGRect {
        guard let screen = NSScreen.main else {
            Logger.warning("No main screen found during coordinate conversion")
            return quartzRect
        }

        let screenHeight = screen.frame.height
        var cocoaRect = quartzRect

        // Flip Y-axis: Quartz Y=0 is top, Cocoa Y=0 is bottom
        cocoaRect.origin.y = screenHeight - quartzRect.origin.y - quartzRect.height

        return cocoaRect
    }

    /// Convert from Cocoa (bottom-left origin) to Quartz (top-left origin)
    /// Rarely needed but included for completeness
    static func toQuartzCoordinates(_ cocoaRect: CGRect) -> CGRect {
        guard let screen = NSScreen.main else {
            Logger.warning("No main screen found during coordinate conversion")
            return cocoaRect
        }

        let screenHeight = screen.frame.height
        var quartzRect = cocoaRect

        // Flip Y-axis
        quartzRect.origin.y = screenHeight - cocoaRect.origin.y - cocoaRect.height

        return quartzRect
    }

    // MARK: - Bounds Validation

    /// Validate that bounds are reasonable
    /// Catches common AX API bugs and invalid values
    static func validateBounds(_ rect: CGRect) -> Bool {
        // Check for positive dimensions
        guard rect.width > 0 && rect.height > 0 else {
            Logger.debug("Invalid bounds: zero or negative dimensions \(rect)")
            return false
        }

        // Check for unreasonably large dimensions
        // Text bounds should never exceed 800px wide or 200px tall
        // Anything larger is likely a container bound, not character bounds
        guard rect.width < 800 && rect.height < 200 else {
            Logger.debug("Invalid bounds: dimensions too large for text \(rect)")
            return false
        }

        // Check for NaN values
        guard !rect.origin.x.isNaN && !rect.origin.y.isNaN &&
              !rect.width.isNaN && !rect.height.isNaN else {
            Logger.debug("Invalid bounds: contains NaN values \(rect)")
            return false
        }

        // Check for infinite values
        guard !rect.origin.x.isInfinite && !rect.origin.y.isInfinite &&
              !rect.width.isInfinite && !rect.height.isInfinite else {
            Logger.debug("Invalid bounds: contains infinite values \(rect)")
            return false
        }

        // Check for extremely small dimensions (< 1px suggests error)
        guard rect.width >= 1.0 && rect.height >= 1.0 else {
            Logger.debug("Invalid bounds: dimensions too small \(rect)")
            return false
        }

        return true
    }

    // MARK: - Screen Constraints

    /// Constrain rect to visible screen area
    /// Prevents overlays from appearing off-screen
    static func constrainToScreen(_ rect: CGRect) -> CGRect {
        guard let screen = NSScreen.main else {
            return rect
        }

        var constrained = rect
        let screenBounds = screen.visibleFrame

        // Ensure rect origin is within screen bounds
        constrained.origin.x = max(screenBounds.minX, min(
            constrained.origin.x,
            screenBounds.maxX - constrained.width
        ))

        constrained.origin.y = max(screenBounds.minY, min(
            constrained.origin.y,
            screenBounds.maxY - constrained.height
        ))

        // If rect is too large, constrain dimensions
        if constrained.width > screenBounds.width {
            constrained.size.width = screenBounds.width
        }

        if constrained.height > screenBounds.height {
            constrained.size.height = screenBounds.height
        }

        return constrained
    }

    /// Check if rect is visible on any screen
    /// Returns false if completely off-screen
    static func isVisibleOnScreen(_ rect: CGRect) -> Bool {
        // Check all screens (including external monitors)
        for screen in NSScreen.screens {
            if screen.frame.intersects(rect) {
                return true
            }
        }

        return false
    }

    // MARK: - Multi-Monitor Support

    /// Get the screen that contains the majority of the rect
    /// Important for multi-monitor setups
    static func findPrimaryScreen(for rect: CGRect) -> NSScreen? {
        var maxIntersectionArea: CGFloat = 0
        var primaryScreen: NSScreen?

        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            let intersectionArea = intersection.width * intersection.height

            if intersectionArea > maxIntersectionArea {
                maxIntersectionArea = intersectionArea
                primaryScreen = screen
            }
        }

        return primaryScreen ?? NSScreen.main
    }

    /// Convert rect to coordinates of specific screen
    /// Useful when element is on external monitor
    static func toScreenCoordinates(_ rect: CGRect, screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame

        var screenRect = rect
        screenRect.origin.x -= screenFrame.origin.x
        screenRect.origin.y -= screenFrame.origin.y

        return screenRect
    }

    // MARK: - Bounds Adjustment

    /// Expand bounds slightly to ensure full coverage
    /// Helps with rounding errors and pixel-perfect alignment
    static func expandBounds(_ rect: CGRect, by amount: CGFloat = 1.0) -> CGRect {
        return rect.insetBy(dx: -amount, dy: -amount)
    }

    /// Shrink bounds slightly
    /// Useful for creating margins
    static func shrinkBounds(_ rect: CGRect, by amount: CGFloat = 1.0) -> CGRect {
        return rect.insetBy(dx: amount, dy: amount)
    }
}
