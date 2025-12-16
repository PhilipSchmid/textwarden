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

// MARK: - Strategy Capability Tiers

/// Semantic capability tiers for positioning strategies
/// Strategies are tried in tier order (precise first, fallback last)
enum StrategyTier: Int, Comparable {
    /// Direct AX bounds that are known to be reliable
    case precise = 1

    /// Calculations based on known-good anchors or line-level data
    case reliable = 2

    /// Font-based measurement and estimation
    case estimated = 3

    /// Last resort methods
    case fallback = 4

    static func < (lhs: StrategyTier, rhs: StrategyTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .precise: return "precise"
        case .reliable: return "reliable"
        case .estimated: return "estimated"
        case .fallback: return "fallback"
        }
    }
}

/// Protocol for position calculation strategies
/// Each strategy implements a different method to determine text error bounds
protocol GeometryProvider {
    /// Strategy name for debugging and logging
    var strategyName: String { get }

    /// Strategy type identifier for configuration matching
    var strategyType: StrategyType { get }

    /// Capability tier - determines execution order
    /// Strategies in lower tiers (precise) are tried before higher tiers (fallback)
    var tier: StrategyTier { get }

    /// Order within the same tier (lower = try first)
    /// Used to differentiate between strategies in the same tier
    var tierPriority: Int { get }

    /// Check if this strategy can handle the given element
    /// Note: App-specific filtering is handled by AppRegistry - this should check
    /// technical capabilities only (e.g., whether AX APIs are available)
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

// MARK: - Default Implementation

extension GeometryProvider {
    /// Default tier priority within a tier
    var tierPriority: Int { 50 }
}

// MARK: - Geometry Result

/// Result of geometry calculation
/// Contains bounds with metadata about calculation quality
struct GeometryResult {
    /// Screen bounds in Cocoa coordinate system (bottom-left origin)
    /// For single-line text, this is the only bounds needed
    let bounds: CGRect

    /// Per-line bounds for multi-line text
    /// If nil or empty, the error fits on a single line and `bounds` should be used
    /// Each rect represents one line of the multi-line text, in reading order (top to bottom)
    let lineBounds: [CGRect]?

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

    /// Memberwise initializer with optional lineBounds (defaults to nil)
    init(
        bounds: CGRect,
        lineBounds: [CGRect]? = nil,
        confidence: Double,
        strategy: String,
        metadata: [String: Any]
    ) {
        self.bounds = bounds
        self.lineBounds = lineBounds
        self.confidence = confidence
        self.strategy = strategy
        self.metadata = metadata
    }

    /// Check if this result has high confidence
    var isHighConfidence: Bool {
        confidence >= 0.8
    }

    /// Check if this result is usable
    var isUsable: Bool {
        confidence >= 0.5 && bounds.width > 0 && bounds.height > 0
    }

    /// Check if this result indicates positioning is unavailable (graceful degradation)
    /// Unavailable results indicate we should not show an underline rather than show it wrong
    var isUnavailable: Bool {
        confidence == 0 && strategy == "unavailable"
    }

    /// Check if this is a multi-line result
    var isMultiLine: Bool {
        guard let lineBounds = lineBounds else { return false }
        return lineBounds.count > 1
    }

    /// Get all line bounds (returns single-element array with main bounds if not multi-line)
    var allLineBounds: [CGRect] {
        if let lineBounds = lineBounds, !lineBounds.isEmpty {
            return lineBounds
        }
        return [bounds]
    }

    // MARK: - Factory Methods

    /// Create high-confidence result
    static func highConfidence(
        bounds: CGRect,
        strategy: String,
        lineBounds: [CGRect]? = nil,
        metadata: [String: Any] = [:]
    ) -> GeometryResult {
        GeometryResult(
            bounds: bounds,
            lineBounds: lineBounds,
            confidence: 0.95,
            strategy: strategy,
            metadata: metadata
        )
    }

    /// Create medium-confidence result
    static func mediumConfidence(
        bounds: CGRect,
        strategy: String,
        lineBounds: [CGRect]? = nil,
        metadata: [String: Any] = [:]
    ) -> GeometryResult {
        GeometryResult(
            bounds: bounds,
            lineBounds: lineBounds,
            confidence: 0.75,
            strategy: strategy,
            metadata: metadata
        )
    }

    /// Create low-confidence result (fallback)
    static func lowConfidence(
        bounds: CGRect,
        strategy: String = "fallback",
        lineBounds: [CGRect]? = nil,
        reason: String
    ) -> GeometryResult {
        GeometryResult(
            bounds: bounds,
            lineBounds: lineBounds,
            confidence: 0.3,
            strategy: strategy,
            metadata: ["reason": reason]
        )
    }

    /// Create an "unavailable" result (graceful degradation)
    /// Used when positioning cannot be determined reliably
    /// It's better to hide underlines than show them incorrectly
    static func unavailable(reason: String) -> GeometryResult {
        GeometryResult(
            bounds: .zero,
            lineBounds: nil,
            confidence: 0,
            strategy: "unavailable",
            metadata: ["reason": reason, "hideSuggested": true]
        )
    }
}

// MARK: - Electron Detection Utility

/// Helper to detect Electron/Chromium-based apps
enum ElectronDetector {
    /// Known Electron app bundle identifiers
    private static let electronBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",    // Slack
        "com.anthropic.claudefordesktop", // Claude
        "com.openai.chat",              // ChatGPT
        "ai.perplexity.mac",            // Perplexity
        "com.slite.desktop",            // Slite
        "com.electron.app",             // Generic Electron
        "com.github.atom",              // Atom
        "com.vscodium",                 // VSCodium
        "com.discordapp.discord",       // Discord
        "com.figma.Desktop",            // Figma
        "notion.id",                    // Notion
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
