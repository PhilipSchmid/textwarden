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
        register(.teams)
        register(.browsers)
        register(.notion)
        register(.terminals)
        register(.mail)
        register(.messages)
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
        preferredStrategies: [.chromium, .textMarker, .rangeBounds, .elementTree, .lineIndex],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,
            requiresTypingPause: true,
            supportsFormattedText: true,
            childElementTraversal: true,
            delaysAXNotifications: false,  // Slack sends AX notifications immediately
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true  // Electron byte offsets are fragile
        )
    )

    // MARK: - Microsoft Teams

    static let teams = AppConfiguration(
        identifier: "teams",
        displayName: "Microsoft Teams",
        bundleIDs: ["com.microsoft.teams2"],
        category: .electron,
        parserType: .teams,
        fontConfig: FontConfig(
            defaultSize: 14,
            fontFamily: "Segoe UI",
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 0,
        // Teams WebView2 accessibility APIs are fundamentally broken for character positioning:
        // - AXBoundsForRange returns (0, y, 0, 0) - no X position or width
        // - AXBoundsForTextMarkerRange returns window frame, not character bounds
        // - Child element frames don't correspond to visual text positions
        // Visual underlines disabled; floating error indicator still works for corrections.
        preferredStrategies: [],
        features: AppFeatures(
            visualUnderlinesEnabled: false,  // Disabled due to broken WebView2 AX APIs
            textReplacementMethod: .browserStyle,
            requiresTypingPause: false,  // No need to wait - not querying position APIs
            supportsFormattedText: true,
            childElementTraversal: true,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true  // Electron byte offsets are fragile
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
            delaysAXNotifications: true,  // Notion batches AX notifications, needs keyboard detection
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true  // Electron byte offsets are fragile
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

    // MARK: - Apple Mail

    static let mail = AppConfiguration(
        identifier: "mail",
        displayName: "Apple Mail",
        bundleIDs: ["com.apple.mail"],
        category: .native,
        parserType: .mail,
        fontConfig: FontConfig(
            defaultSize: 13,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 4,
        // Mail uses WebKit for composition - needs different strategies and text replacement
        // WebKit elements don't support standard AX bounds queries reliably
        // Text replacement needs browser-style (selection + paste) because AXValue is read-only
        preferredStrategies: [.textMarker, .rangeBounds, .lineIndex],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,  // WebKit needs selection + paste
            requiresTypingPause: false,
            supportsFormattedText: true,  // Mail supports rich text
            childElementTraversal: true,  // May need to traverse AXWebArea children
            delaysAXNotifications: false,  // Mail sends AX notifications promptly like Slack
            focusBouncesDuringPaste: true,  // Mail's WebKit fires multiple focus events during Cmd+V
            requiresFullReanalysisAfterReplacement: true  // WebKit byte offsets are fragile
        )
    )

    // MARK: - Apple Messages

    static let messages = AppConfiguration(
        identifier: "messages",
        displayName: "Apple Messages",
        bundleIDs: ["com.apple.MobileSMS"],
        category: .custom,
        parserType: .generic,
        fontConfig: FontConfig(
            defaultSize: 13,  // Match previous behavior - font size affects text width calculations
            fontFamily: "SF Pro",
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 5,  // Offset for Messages text field padding
        // Messages is a Mac Catalyst app. Standard AX APIs (AXRangeForLine, AXBoundsForRange)
        // return slightly inaccurate X coordinates for wrapped lines with multi-codepoint characters
        // (emojis). The Y coordinate is correct. RangeBoundsStrategy handles this with UTF-16
        // index adjustment for the error range.
        preferredStrategies: [.textMarker, .rangeBounds, .lineIndex, .insertionPoint, .fontMetrics],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,  // Catalyst apps need keyboard-based replacement
            requiresTypingPause: false,
            supportsFormattedText: false,  // Messages input is plain text
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true  // Catalyst byte offsets may be fragile
        )
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
