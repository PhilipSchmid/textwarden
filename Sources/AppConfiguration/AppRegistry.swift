//
//  AppRegistry.swift
//  TextWarden
//
//  Central registry of all app configurations.
//  Single source of truth for app-specific behavior.
//

import Foundation

// MARK: - App Registry

/// Central registry for all app configurations
final class AppRegistry {

    static let shared = AppRegistry()

    /// Bundle ID -> Configuration mapping
    private var configurations: [String: AppConfiguration] = [:]

    /// Identifier -> Configuration mapping
    private var configsByIdentifier: [String: AppConfiguration] = [:]

    private init() {
        registerBuiltInConfigurations()
    }

    // MARK: - Public API

    /// Get configuration for a bundle ID
    /// Returns default configuration if not found
    func configuration(for bundleID: String) -> AppConfiguration {
        return configurations[bundleID] ?? .default
    }

    /// Get configuration by identifier (e.g., "slack", "notion")
    func configuration(identifier: String) -> AppConfiguration? {
        return configsByIdentifier[identifier]
    }

    /// All registered configurations (excluding default)
    var allConfigurations: [AppConfiguration] {
        Array(configsByIdentifier.values)
    }

    /// Check if a bundle ID has a specific configuration
    func hasConfiguration(for bundleID: String) -> Bool {
        return configurations[bundleID] != nil
    }

    // MARK: - Registration

    private func register(_ config: AppConfiguration) {
        configsByIdentifier[config.identifier] = config
        for bundleID in config.bundleIDs {
            configurations[bundleID] = config
        }
    }

    private func registerBuiltInConfigurations() {
        register(.slack)
        register(.browsers)
        register(.notion)
        register(.terminals)
        // Note: .default is not registered, used as fallback
    }
}

// MARK: - Built-in Configurations

extension AppConfiguration {

    // MARK: - Slack

    static let slack = AppConfiguration(
        identifier: "slack",
        displayName: "Slack",
        bundleIDs: ["com.tinyspeck.slackmacgap"],
        category: .electron,
        parserType: .slack,
        fontConfig: FontConfig(
            defaultSize: 15,
            fontFamily: "Lato",
            spacingMultiplier: 0.97
        ),
        horizontalPadding: 12,
        preferredStrategies: [.slack, .textMarker, .rangeBounds, .elementTree, .lineIndex],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,
            requiresTypingPause: true,
            supportsFormattedText: true,
            childElementTraversal: true,
            delaysAXNotifications: false  // Slack sends AX notifications immediately
        )
    )

    // MARK: - Web Browsers

    static let browsers = AppConfiguration(
        identifier: "browsers",
        displayName: "Web Browsers",
        bundleIDs: [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "org.mozilla.firefox",
            "org.mozilla.firefoxdeveloperedition",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.Dev",
            "com.operasoftware.Opera",
            "com.operasoftware.OperaGX",
            "company.thebrowser.Browser",  // Arc
            "com.brave.Browser",
            "com.brave.Browser.beta",
            "com.vivaldi.Vivaldi",
            "com.nickvision.comet"
        ],
        category: .browser,
        parserType: .browser,
        fontConfig: FontConfig(
            defaultSize: 14,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 2
        // Uses browser category defaults for strategies and features
    )

    // MARK: - Notion

    static let notion = AppConfiguration(
        identifier: "notion",
        displayName: "Notion",
        bundleIDs: [
            "notion.id",
            "com.notion.id",
            "com.notion.desktop"
        ],
        category: .electron,
        parserType: .notion,
        fontConfig: FontConfig(
            defaultSize: 16,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 0,
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,
            requiresTypingPause: true,
            supportsFormattedText: false,
            childElementTraversal: true,
            delaysAXNotifications: true  // Notion batches AX notifications, needs keyboard detection
        )
    )

    // MARK: - Terminal Apps

    static let terminals = AppConfiguration(
        identifier: "terminals",
        displayName: "Terminal Apps",
        bundleIDs: [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "co.zeit.hyper",
            "dev.warp.Warp-Stable",
            "org.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm"
        ],
        category: .terminal,
        parserType: .terminal,
        horizontalPadding: 5
        // Uses terminal category defaults (underlines disabled)
    )

    // MARK: - Default (Fallback)

    static let `default` = AppConfiguration(
        identifier: "default",
        displayName: "Default",
        bundleIDs: [],
        category: .native,
        parserType: .generic
        // Uses native category defaults
    )
}
