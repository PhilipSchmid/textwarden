//
//  BoundsValidator.swift
//  Gnau
//
//  Validates bounds returned by Accessibility API to filter out implausible values
//

import Foundation
import AppKit

/// Validates bounds returned by the Accessibility API
struct BoundsValidator {

    // MARK: - Validation Constants

    /// Minimum acceptable dimension (width or height)
    private static let minDimension: CGFloat = 0.5

    /// Maximum reasonable width for text (prevents accepting huge scroll areas)
    private static let maxWidth: CGFloat = 5000

    /// Maximum reasonable height for a single line of text
    private static let maxHeight: CGFloat = 500

    /// Minimum aspect ratio (width/height) for text bounds
    private static let minAspectRatio: CGFloat = 0.1

    /// Maximum aspect ratio (width/height) for text bounds
    private static let maxAspectRatio: CGFloat = 100

    // MARK: - Main Validation

    /// Check if bounds are plausible for text positioning
    /// Returns true if bounds pass all validation checks
    /// bundleIdentifier parameter allows app-specific validation rules
    static func isPlausible(_ bounds: CGRect, context: String = "", bundleIdentifier: String? = nil) -> Bool {
        let prefix = context.isEmpty ? "" : "[\(context)] "

        // CRITICAL: Electron apps and browsers often return bounds that pass
        // geometric validation but are positionally incorrect. For these apps,
        // estimation provides more reliable results.
        if let bundleId = bundleIdentifier {
            let electronApps: Set<String> = [
                "com.tinyspeck.slackmacgap",  // Slack
                "com.hnc.Discord",              // Discord
                "com.microsoft.VSCode"          // VS Code
            ]

            // Browsers have unreliable AX bounds, especially in contenteditable areas
            // They sometimes return geometrically valid bounds that are positionally incorrect
            let browserApps: Set<String> = [
                "com.google.Chrome",
                "com.google.Chrome.beta",
                "com.microsoft.edgemac",         // Edge
                "com.brave.Browser",
                "com.vivaldi.Vivaldi",
                "org.chromium.Chromium",
                "com.apple.Safari",
                "org.mozilla.firefox",
                "org.mozilla.firefoxdeveloperedition",
                "com.operasoftware.Opera"
            ]

            if electronApps.contains(bundleId) {
                let msg = "\(prefix)⚠️ BoundsValidator: Rejected - Electron app with known AX inaccuracy (\(bundleId))"
                NSLog(msg)
                logToDebugFile(msg)
                return false
            }

            if browserApps.contains(bundleId) {
                let msg = "\(prefix)⚠️ BoundsValidator: Rejected - Browser with known AX inaccuracy (\(bundleId))"
                NSLog(msg)
                logToDebugFile(msg)
                return false
            }
        }

        // Check 1: Non-zero dimensions
        guard bounds.width >= minDimension && bounds.height >= minDimension else {
            let msg = "\(prefix)⚠️ BoundsValidator: Rejected - dimensions too small (w: \(bounds.width), h: \(bounds.height))"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        // Check 2: Not unreasonably large
        guard bounds.width <= maxWidth && bounds.height <= maxHeight else {
            let msg = "\(prefix)⚠️ BoundsValidator: Rejected - dimensions too large (w: \(bounds.width), h: \(bounds.height))"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        // Check 3: Within screen bounds
        guard isWithinScreenBounds(bounds) else {
            let msg = "\(prefix)⚠️ BoundsValidator: Rejected - outside screen bounds \(bounds)"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        // Check 4: Reasonable aspect ratio (text shouldn't be extremely tall or narrow)
        let aspectRatio = bounds.width / bounds.height
        guard aspectRatio >= minAspectRatio && aspectRatio <= maxAspectRatio else {
            let msg = "\(prefix)⚠️ BoundsValidator: Rejected - unreasonable aspect ratio \(aspectRatio) (w: \(bounds.width), h: \(bounds.height))"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        // Check 5: Not NaN or infinite values
        guard bounds.origin.x.isFinite && bounds.origin.y.isFinite &&
              bounds.width.isFinite && bounds.height.isFinite else {
            let msg = "\(prefix)⚠️ BoundsValidator: Rejected - contains NaN or infinite values"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        let msg = "\(prefix)✅ BoundsValidator: Accepted bounds \(bounds)"
        NSLog(msg)
        logToDebugFile(msg)
        return true
    }

    // MARK: - Helper Methods

    /// Check if bounds fall within any connected screen
    private static func isWithinScreenBounds(_ bounds: CGRect) -> Bool {
        // Get all screens
        let screens = NSScreen.screens

        guard !screens.isEmpty else {
            NSLog("⚠️ BoundsValidator: No screens found")
            return true // Don't reject if we can't determine screens
        }

        // Check if bounds intersect with or are near any screen
        // Allow 100pt tolerance for window chrome, menu bar, etc.
        let tolerance: CGFloat = 100

        for screen in screens {
            let expandedFrame = screen.frame.insetBy(dx: -tolerance, dy: -tolerance)
            if expandedFrame.intersects(bounds) {
                return true
            }
        }

        // Also check if the center point is on any screen
        let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        for screen in screens {
            if screen.frame.contains(centerPoint) {
                return true
            }
        }

        return false
    }

    /// Validate and optionally adjust bounds
    /// Returns adjusted bounds if they can be salvaged, nil if completely invalid
    static func validateAndAdjust(_ bounds: CGRect, context: String = "") -> CGRect? {
        let prefix = context.isEmpty ? "" : "[\(context)] "

        var adjusted = bounds

        // Try to fix common issues

        // Fix 1: Negative dimensions (flip if needed)
        if adjusted.width < 0 {
            adjusted.origin.x += adjusted.width
            adjusted.size.width = abs(adjusted.width)
            let msg = "\(prefix)🔧 BoundsValidator: Fixed negative width"
            NSLog(msg)
            logToDebugFile(msg)
        }

        if adjusted.height < 0 {
            adjusted.origin.y += adjusted.height
            adjusted.size.height = abs(adjusted.height)
            let msg = "\(prefix)🔧 BoundsValidator: Fixed negative height"
            NSLog(msg)
            logToDebugFile(msg)
        }

        // Fix 2: Clamp extremely large dimensions
        if adjusted.width > maxWidth {
            adjusted.size.width = maxWidth
            let msg = "\(prefix)🔧 BoundsValidator: Clamped width to \(maxWidth)"
            NSLog(msg)
            logToDebugFile(msg)
        }

        if adjusted.height > maxHeight {
            adjusted.size.height = maxHeight
            let msg = "\(prefix)🔧 BoundsValidator: Clamped height to \(maxHeight)"
            NSLog(msg)
            logToDebugFile(msg)
        }

        // Now validate the adjusted bounds
        if isPlausible(adjusted, context: context) {
            if adjusted != bounds {
                let msg = "\(prefix)✅ BoundsValidator: Adjusted bounds from \(bounds) to \(adjusted)"
                NSLog(msg)
                logToDebugFile(msg)
            }
            return adjusted
        }

        // Could not salvage
        return nil
    }
}
