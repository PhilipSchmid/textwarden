//
//  GenericContentParser.swift
//  TextWarden
//
//  Generic content parser for apps without specific implementations
//  Uses standard AX API and reads from AppConfiguration when available
//

import Foundation
import AppKit

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

    func detectUIContext(element: AXUIElement) -> String? {
        // Generic parser doesn't distinguish UI contexts
        return nil
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Use font size from AppConfiguration if available, otherwise conservative default
        return config.fontConfig.defaultSize
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // Use spacing multiplier from AppConfiguration if available
        return config.fontConfig.spacingMultiplier
    }

    func fontFamily(context: String?) -> String? {
        // Use font family from AppConfiguration if available
        return config.fontConfig.fontFamily
    }

    func horizontalPadding(context: String?) -> CGFloat {
        // Use horizontal padding from AppConfiguration
        return config.horizontalPadding
    }

    /// Generic parser uses default implementation from protocol
    /// which tries AX API first, then falls back to text measurement
}
