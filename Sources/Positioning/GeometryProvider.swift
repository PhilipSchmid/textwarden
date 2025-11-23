//
//  GeometryProvider.swift
//  TextWarden
//
//  Protocol for position calculation strategies
//  Enables pluggable positioning algorithms with automatic fallback
//

import Foundation
import AppKit
import ApplicationServices

/// Protocol for position calculation strategies
/// Each strategy implements a different method to determine text error bounds
protocol GeometryProvider {
    /// Strategy name for debugging and logging
    var strategyName: String { get }

    /// Priority level (higher = try first)
    /// Recommended values: 100 (highest), 80 (medium), 50 (lowest/fallback)
    var priority: Int { get }

    /// Check if this strategy can handle the given element
    /// Allows strategies to opt-out based on app type or element capabilities
    func canHandle(element: AXUIElement, bundleID: String) -> Bool

    /// Calculate position geometry for error range
    /// Returns nil if strategy cannot calculate bounds (will try next strategy)
    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult?
}

// MARK: - Geometry Result

/// Result of geometry calculation
/// Contains bounds with metadata about calculation quality
struct GeometryResult {
    /// Screen bounds in Cocoa coordinate system (bottom-left origin)
    let bounds: CGRect

    /// Confidence level (0.0 to 1.0)
    /// 1.0 = Perfect AX API bounds
    /// 0.8-0.9 = Reliable estimation
    /// 0.5-0.7 = Rough estimation
    /// < 0.5 = Low confidence fallback
    let confidence: Double

    /// Strategy that produced this result
    let strategy: String

    /// Additional metadata for debugging
    let metadata: [String: Any]

    /// Check if this result has high confidence
    var isHighConfidence: Bool {
        confidence >= 0.8
    }

    /// Check if this result is usable
    var isUsable: Bool {
        confidence >= 0.5 && bounds.width > 0 && bounds.height > 0
    }

    // MARK: - Factory Methods

    /// Create high-confidence result
    static func highConfidence(
        bounds: CGRect,
        strategy: String,
        metadata: [String: Any] = [:]
    ) -> GeometryResult {
        GeometryResult(
            bounds: bounds,
            confidence: 0.95,
            strategy: strategy,
            metadata: metadata
        )
    }

    /// Create medium-confidence result
    static func mediumConfidence(
        bounds: CGRect,
        strategy: String,
        metadata: [String: Any] = [:]
    ) -> GeometryResult {
        GeometryResult(
            bounds: bounds,
            confidence: 0.75,
            strategy: strategy,
            metadata: metadata
        )
    }

    /// Create low-confidence result (fallback)
    static func lowConfidence(
        bounds: CGRect,
        strategy: String = "fallback",
        reason: String
    ) -> GeometryResult {
        GeometryResult(
            bounds: bounds,
            confidence: 0.3,
            strategy: strategy,
            metadata: ["reason": reason]
        )
    }
}

// MARK: - Electron Detection Utility

/// Helper to detect Electron/Chromium-based apps
enum ElectronDetector {
    /// Known Electron app bundle identifiers
    private static let electronBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",  // Slack
        "com.slite.desktop",           // Slite
        "com.electron.app",            // Generic Electron
        "com.github.atom",             // Atom
        "com.vscodium",                // VSCodium
        "com.discordapp.discord",      // Discord
        "com.figma.Desktop",           // Figma
    ]

    /// Check if bundle ID indicates Electron app
    static func isElectronApp(_ bundleID: String) -> Bool {
        // Check known Electron apps
        if electronBundleIDs.contains(bundleID) {
            return true
        }

        // Check for VS Code variants
        if bundleID.contains("vscode") || bundleID.contains("VSCode") {
            return true
        }

        // Check for Electron in bundle ID
        if bundleID.lowercased().contains("electron") {
            return true
        }

        return false
    }

    /// Check if element is in a Chrome/Chromium browser
    static func isChromiumBrowser(_ bundleID: String) -> Bool {
        return bundleID == "com.google.Chrome" ||
               bundleID == "org.chromium.Chromium" ||
               bundleID == "com.brave.Browser" ||
               bundleID == "com.microsoft.edgemac"
    }

    /// Check if app likely uses web technologies
    static func usesWebTechnologies(_ bundleID: String) -> Bool {
        return isElectronApp(bundleID) || isChromiumBrowser(bundleID)
    }
}
