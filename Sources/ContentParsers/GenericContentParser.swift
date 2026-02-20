//
//  GenericContentParser.swift
//  TextWarden
//
//  Generic content parser for apps without specific implementations
//  Uses standard AX API and reads from AppConfiguration when available
//

import AppKit
import Foundation

/// Generic content parser for apps without specific implementations
/// Reads configuration from AppRegistry when available, otherwise uses conservative defaults
class GenericContentParser: ContentParser {
    let bundleIdentifier: String
    let parserName = "Generic"

    /// Thread-local storage for current bundle ID being processed
    /// This allows the shared instance to look up config for the actual app
    private static var currentBundleID: String?

    /// Get configuration for current app or fall back to stored bundleIdentifier
    private var config: AppConfiguration {
        let bundleID = Self.currentBundleID ?? bundleIdentifier
        return AppRegistry.shared.configuration(for: bundleID)
    }

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    /// Set the current bundle ID for config lookups
    /// Called by the factory or positioning code before using this parser
    func setCurrentBundleID(_ bundleID: String) {
        Self.currentBundleID = bundleID
    }

    func detectUIContext(element _: AXUIElement) -> String? {
        // Generic parser doesn't distinguish UI contexts
        nil
    }

    func estimatedFontSize(context _: String?) -> CGFloat {
        // Use font size from AppConfiguration if available, otherwise conservative default
        config.fontConfig.defaultSize
    }

    func spacingMultiplier(context _: String?) -> CGFloat {
        // Use spacing multiplier from AppConfiguration if available
        config.fontConfig.spacingMultiplier
    }

    func fontFamily(context _: String?) -> String? {
        // Use font family from AppConfiguration if available
        config.fontConfig.fontFamily
    }

    func horizontalPadding(context _: String?) -> CGFloat {
        // Use horizontal padding from AppConfiguration
        config.horizontalPadding
    }

    // Generic parser uses default implementation from protocol
    // which tries AX API first, then falls back to text measurement
}
