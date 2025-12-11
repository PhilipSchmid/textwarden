//
//  ApplicationContext.swift
//  TextWarden
//
//  Model representing the context of an application being monitored
//

import Foundation

/// Represents the application context for text monitoring
struct ApplicationContext {
    /// Bundle identifier of the application (e.g., "com.apple.TextEdit")
    let bundleIdentifier: String

    /// Process ID of the running application
    let processID: pid_t

    /// Human-readable application name
    let applicationName: String

    /// Whether grammar checking is enabled for this application
    var isEnabled: Bool

    /// Timestamp when this context was created
    let createdAt: Date

    /// Initialize application context
    init(
        bundleIdentifier: String,
        processID: pid_t,
        applicationName: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.applicationName = applicationName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// Check if grammar checking should be active for this context
    func shouldCheck() -> Bool {
        guard isEnabled else { return false }

        // Check user preferences
        return UserPreferences.shared.isEnabled(for: bundleIdentifier)
    }

    /// Create a copy with updated enabled status
    func with(isEnabled: Bool) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: applicationName,
            isEnabled: isEnabled,
            createdAt: createdAt
        )
    }
}

// MARK: - Equatable

extension ApplicationContext: Equatable {
    static func == (lhs: ApplicationContext, rhs: ApplicationContext) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.processID == rhs.processID
    }
}

// MARK: - Hashable

extension ApplicationContext: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
        hasher.combine(processID)
    }
}

// MARK: - CustomStringConvertible

extension ApplicationContext: CustomStringConvertible {
    var description: String {
        "\(applicationName) (\(bundleIdentifier)) [PID: \(processID)] - \(isEnabled ? "enabled" : "disabled")"
    }
}

// MARK: - Common Application Contexts

extension ApplicationContext {
    /// Create context for TextEdit
    static func textEdit(processID: pid_t) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: "com.apple.TextEdit",
            processID: processID,
            applicationName: "TextEdit"
        )
    }

    /// Create context for Pages
    static func pages(processID: pid_t) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: "com.apple.Pages",
            processID: processID,
            applicationName: "Pages"
        )
    }

    /// Create context for VS Code
    static func vsCode(processID: pid_t) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: "com.microsoft.VSCode",
            processID: processID,
            applicationName: "Visual Studio Code"
        )
    }

    /// Create context for generic application
    static func application(bundleIdentifier: String, processID: pid_t, name: String) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: name
        )
    }
}

// MARK: - App Type Detection

extension ApplicationContext {
    /// Known Electron-based apps that require special handling
    private static let electronApps: Set<String> = [
        "com.tinyspeck.slackmacgap",      // Slack
        "com.hnc.Discord",                 // Discord
        "com.microsoft.VSCode",            // VS Code
        "com.electron.app",                // Generic Electron
        "com.github.GitHubClient",         // GitHub Desktop
        "com.microsoft.teams",             // Microsoft Teams (Electron)
        "notion.id"                        // Notion
    ]

    /// Known Chromium-based apps (includes Electron apps since Electron uses Chromium)
    private static let chromiumApps: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "ai.perplexity.comet",
        "company.thebrowser.Browser",      // Arc browser
        "company.thebrowser.Browser.beta", // Arc browser beta
        "notion.id"                        // Notion (Electron/Chromium-based)
    ]

    /// Known browser applications (including non-Chromium browsers)
    /// These require special handling because AX API often returns success but doesn't trigger browser events
    private static let browserApps: Set<String> = [
        "com.apple.Safari",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.operasoftware.Opera"
    ]

    /// Known terminal applications
    private static let terminalApps: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty"
    ]

    /// Check if this is an Electron-based application
    /// Electron apps require keyboard-based text replacement due to broken AX APIs
    var isElectronApp: Bool {
        Self.electronApps.contains(bundleIdentifier) ||
        bundleIdentifier.contains("electron")
    }

    /// Check if this is a Chromium-based application
    /// Chromium apps may have accessibility tree issues
    var isChromiumBased: Bool {
        Self.chromiumApps.contains(bundleIdentifier) ||
        bundleIdentifier.contains("chromium")
    }

    /// Check if this is a terminal application
    /// Terminal apps require special text filtering to avoid checking command output
    var isTerminalApp: Bool {
        Self.terminalApps.contains(bundleIdentifier)
    }

    /// Check if this is a browser application (including both Chromium and non-Chromium browsers)
    /// Browsers often have issues with AX API text replacement silently failing
    var isBrowser: Bool {
        isChromiumBased || Self.browserApps.contains(bundleIdentifier)
    }

    /// Check if this app requires keyboard-based text replacement
    /// Returns true for apps where AX API setValue is known to fail
    /// Uses AppRegistry's textReplacementMethod setting
    var requiresKeyboardReplacement: Bool {
        let config = AppRegistry.shared.configuration(for: bundleIdentifier)
        return config.features.textReplacementMethod == .browserStyle || isMacCatalystApp
    }

    /// Known Mac Catalyst apps (iOS apps running on macOS)
    private static let macCatalystApps: Set<String> = [
        "com.apple.MobileSMS",       // Messages
        "com.apple.news",            // Apple News
        "com.apple.stocks",          // Stocks
        "net.whatsapp.WhatsApp",     // WhatsApp (Catalyst version)
        "ru.keepcoder.Telegram"      // Telegram (Catalyst version)
    ]

    /// Check if this is a Mac Catalyst app (iOS app running on macOS)
    /// Mac Catalyst apps often have incomplete AX API support for text manipulation
    var isMacCatalystApp: Bool {
        Self.macCatalystApps.contains(bundleIdentifier)
    }

    /// Get recommended timing delay for keyboard operations (in seconds)
    /// Delegates to ApplicationConfiguration for centralized config management
    var keyboardOperationDelay: TimeInterval {
        ApplicationConfiguration.keyboardOperationDelay(for: bundleIdentifier)
    }

    /// Check if this app supports format-preserving replacements
    /// Delegates to ApplicationConfiguration for centralized config management
    var supportsFormatPreservation: Bool {
        ApplicationConfiguration.supportsFormatPreservation(for: bundleIdentifier)
    }

    /// Estimated font size for text measurement (heuristic-based)
    /// Delegates to ApplicationConfiguration for centralized config management
    var estimatedFontSize: CGFloat {
        ApplicationConfiguration.estimatedFontSize(for: bundleIdentifier)
    }

    /// Character width correction factor (per character)
    /// Delegates to ApplicationConfiguration for centralized config management
    var characterWidthCorrection: CGFloat {
        ApplicationConfiguration.characterWidthCorrection(for: bundleIdentifier)
    }

    /// Horizontal padding inside text input elements
    /// Delegates to ApplicationConfiguration for centralized config management
    var estimatedLeftPadding: CGFloat {
        ApplicationConfiguration.estimatedLeftPadding(for: bundleIdentifier)
    }
}
