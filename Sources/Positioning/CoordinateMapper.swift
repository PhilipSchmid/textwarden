//
//  CoordinateMapper.swift
//  TextWarden
//
//  Handles coordinate system conversions between macOS's THREE coordinate systems:
//
//  1. QUARTZ COORDINATES (CGWindow, Accessibility APIs, Core Graphics)
//     - Origin: Top-left of PRIMARY screen (screen with frame origin 0,0)
//     - Y-axis: Increases DOWNWARD
//     - Used by: AXUIElement bounds, CGWindowListCopyWindowInfo, CGRect from AX APIs
//     - Example: A point at screen top-left is (0, 0)
//
//  2. COCOA COORDINATES (NSWindow, NSView, NSScreen)
//     - Origin: Bottom-left of PRIMARY screen
//     - Y-axis: Increases UPWARD
//     - Used by: NSWindow frame, NSView frame, overlay window positioning
//     - Example: A point at screen bottom-left is (0, 0)
//
//  3. VIEW-LOCAL COORDINATES (Inside NSView hierarchy)
//     - Origin: Bottom-left of the view's bounds
//     - Y-axis: Increases UPWARD
//     - Used by: Drawing operations, hit testing, NSView.convert()
//
//  CONVERSION RULES:
//  - Quartz → Cocoa: cocoaY = screenHeight - quartzY - rectHeight
//  - Cocoa → Quartz: quartzY = screenHeight - cocoaY - rectHeight
//  - Always use PRIMARY screen height (the one with frame.origin == .zero)
//
//  COMMON PITFALLS:
//  - Multi-monitor: Each screen has its own frame in global coordinates
//  - Screen height: Must use PRIMARY screen height for conversions, not the target screen
//  - Y-flip requires rect height: Point conversion differs from rect conversion
//

import AppKit
import Foundation

// MARK: - Unified Coordinate Type

/// Represents a screen position with explicit coordinate system
/// Eliminates ambiguity when passing coordinates between components
struct ScreenPosition {
    let x: CGFloat
    let y: CGFloat
    let system: CoordinateSystem

    enum CoordinateSystem {
        /// Quartz coordinates: origin at top-left, Y increases downward
        case quartz
        /// Cocoa coordinates: origin at bottom-left, Y increases upward
        case cocoa
    }

    init(x: CGFloat, y: CGFloat, system: CoordinateSystem) {
        self.x = x
        self.y = y
        self.system = system
    }

    init(point: CGPoint, system: CoordinateSystem) {
        x = point.x
        y = point.y
        self.system = system
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }

    /// Convert to Cocoa coordinate system
    func toCocoa(screenHeight: CGFloat? = nil) -> ScreenPosition {
        guard system == .quartz else { return self }
        guard let height = screenHeight ?? NSScreen.main?.frame.height else {
            Logger.warning("CoordinateMapper: Screen height unavailable for conversion", category: Logger.analysis)
            return self // Return unchanged to avoid corrupting coordinates
        }
        return ScreenPosition(x: x, y: height - y, system: .cocoa)
    }

    /// Convert to Quartz coordinate system
    func toQuartz(screenHeight: CGFloat? = nil) -> ScreenPosition {
        guard system == .cocoa else { return self }
        guard let height = screenHeight ?? NSScreen.main?.frame.height else {
            Logger.warning("CoordinateMapper: Screen height unavailable for conversion", category: Logger.analysis)
            return self // Return unchanged to avoid corrupting coordinates
        }
        return ScreenPosition(x: x, y: height - y, system: .quartz)
    }
}

/// Represents a screen rectangle with explicit coordinate system
struct ScreenRect {
    let origin: ScreenPosition
    let size: CGSize

    init(origin: ScreenPosition, size: CGSize) {
        self.origin = origin
        self.size = size
    }

    init(rect: CGRect, system: ScreenPosition.CoordinateSystem) {
        origin = ScreenPosition(point: rect.origin, system: system)
        size = rect.size
    }

    var rect: CGRect {
        CGRect(origin: origin.point, size: size)
    }

    var system: ScreenPosition.CoordinateSystem {
        origin.system
    }

    /// Convert to Cocoa coordinate system
    func toCocoa(screenHeight: CGFloat? = nil) -> ScreenRect {
        guard system == .quartz else { return self }
        let height = screenHeight ?? NSScreen.main?.frame.height ?? 0
        let newY = height - origin.y - size.height
        return ScreenRect(
            origin: ScreenPosition(x: origin.x, y: newY, system: .cocoa),
            size: size
        )
    }

    /// Convert to Quartz coordinate system
    func toQuartz(screenHeight: CGFloat? = nil) -> ScreenRect {
        guard system == .cocoa else { return self }
        let height = screenHeight ?? NSScreen.main?.frame.height ?? 0
        let newY = height - origin.y - size.height
        return ScreenRect(
            origin: ScreenPosition(x: origin.x, y: newY, system: .quartz),
            size: size
        )
    }
}

// MARK: - Coordinate Mapper

/// Handles coordinate system conversions
/// Accessibility APIs return Quartz coordinates (top-left origin)
/// NSWindow uses Cocoa coordinates (bottom-left origin)
enum CoordinateMapper {
    // MARK: - Coordinate Conversion

    /// Convert from Quartz (top-left origin) to Cocoa (bottom-left origin)
    /// This is the most common conversion needed
    static func toCocoaCoordinates(_ quartzRect: CGRect) -> CGRect {
        // Use PRIMARY screen height (the one with Cocoa frame origin at 0,0)
        // This is where the Quartz coordinate system origin is defined
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        guard let screen = primaryScreen ?? NSScreen.main else {
            Logger.warning("No screen found during coordinate conversion", category: Logger.accessibility)
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
        // Use PRIMARY screen height (the one with Cocoa frame origin at 0,0)
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        guard let screen = primaryScreen ?? NSScreen.main else {
            Logger.warning("No screen found during coordinate conversion", category: Logger.accessibility)
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
        guard GeometryConstants.hasValidSize(rect) else {
            Logger.debug("CoordinateMapper: Invalid bounds: zero or negative dimensions \(rect)", category: Logger.accessibility)
            return false
        }

        // Check for unreasonably large dimensions
        // Anything larger is likely a container bound, not character bounds
        guard rect.width < GeometryConstants.maximumTextWidth,
              rect.height < GeometryConstants.maximumLineHeight
        else {
            Logger.debug("CoordinateMapper: Invalid bounds: dimensions too large for text \(rect)", category: Logger.accessibility)
            return false
        }

        // Check for NaN values
        guard !rect.origin.x.isNaN, !rect.origin.y.isNaN,
              !rect.width.isNaN, !rect.height.isNaN
        else {
            Logger.debug("CoordinateMapper: Invalid bounds: contains NaN values \(rect)", category: Logger.accessibility)
            return false
        }

        // Check for infinite values
        guard !rect.origin.x.isInfinite, !rect.origin.y.isInfinite,
              !rect.width.isInfinite, !rect.height.isInfinite
        else {
            Logger.debug("CoordinateMapper: Invalid bounds: contains infinite values \(rect)", category: Logger.accessibility)
            return false
        }

        // Check for extremely small dimensions (< 1px suggests error)
        guard rect.width >= 1.0, rect.height >= 1.0 else {
            Logger.debug("CoordinateMapper: Invalid bounds: dimensions too small \(rect)", category: Logger.accessibility)
            return false
        }

        // Check for negative coordinates (often indicates stale values)
        // Note: Negative Y is valid in Quartz coords for multi-monitor, so only check extremely negative
        guard rect.origin.x >= -10000, rect.origin.y >= -10000 else {
            Logger.debug("CoordinateMapper: Invalid bounds: extremely negative coordinates \(rect)", category: Logger.accessibility)
            return false
        }

        return true
    }

    /// Enhanced validation that also checks against screen bounds
    /// Validates bounds are within visible screen area
    static func validateBoundsOnScreen(_ rect: CGRect) -> Bool {
        // First do basic validation
        guard validateBounds(rect) else {
            return false
        }

        // Check if bounds are on any screen
        guard isVisibleOnScreen(rect) else {
            Logger.debug("CoordinateMapper: Invalid bounds: not visible on any screen \(rect)", category: Logger.accessibility)
            return false
        }

        return true
    }

    /// Validate bounds with edit area constraint
    /// Bounds should be within the edit area (text field)
    static func validateBoundsWithinEditArea(
        _ rect: CGRect,
        editArea: CGRect,
        tolerance: CGFloat = 50.0
    ) -> Bool {
        // First do basic validation
        guard validateBounds(rect) else {
            return false
        }

        // Check if bounds origin is within expanded edit area
        let expandedEditArea = editArea.insetBy(dx: -tolerance, dy: -tolerance)

        guard expandedEditArea.contains(rect.origin) else {
            Logger.debug("CoordinateMapper: Invalid bounds: origin \(rect.origin) outside edit area \(editArea)", category: Logger.accessibility)
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
        rect.insetBy(dx: -amount, dy: -amount)
    }

    /// Shrink bounds slightly
    /// Useful for creating margins
    static func shrinkBounds(_ rect: CGRect, by amount: CGFloat = 1.0) -> CGRect {
        rect.insetBy(dx: amount, dy: amount)
    }
}
