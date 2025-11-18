//
//  ApplicationContext.swift
//  Gnau
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

// MARK: - App Type Detection (inspired by Grammarly's approach)

extension ApplicationContext {
    /// Known Electron-based apps that require special handling
    /// Based on reverse engineering Grammarly and Refine.app
    private static let electronApps: Set<String> = [
        "com.tinyspeck.slackmacgap",      // Slack
        "com.hnc.Discord",                 // Discord
        "com.microsoft.VSCode",            // VS Code
        "com.electron.app",                // Generic Electron
        "com.github.GitHubClient",         // GitHub Desktop
        "com.microsoft.teams",             // Microsoft Teams (Electron)
        "com.notion.desktop"               // Notion
    ]

    /// Known Chromium-based apps
    private static let chromiumApps: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium"
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
        "com.github.wez.wezterm"
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
    /// Returns true for Electron apps, Terminal apps, and browsers where AX API is known to fail
    /// Inspired by SelectedTextKit and Grammarly's approach to browser text replacement
    var requiresKeyboardReplacement: Bool {
        isElectronApp || isTerminalApp || isBrowser
    }

    /// Get recommended timing delay for keyboard operations (in seconds)
    /// Based on Grammarly's "fast_batching_selection_wait" approach
    var keyboardOperationDelay: TimeInterval {
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            // Slack needs longer delays due to React rendering
            return 0.15
        case "com.hnc.Discord":
            // Discord is also React-based
            return 0.15
        case "com.microsoft.VSCode":
            // VS Code is faster
            return 0.08
        case "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser":
            // Chromium browsers need moderate delays for contenteditable areas
            return 0.10
        case "com.apple.Safari":
            // Safari is generally faster
            return 0.08
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
            // Firefox has known issues, use longer delay
            return 0.12
        default:
            // Default delay: browsers/Electron apps need more time than native apps
            if isBrowser {
                return 0.10
            }
            return isElectronApp ? 0.1 : 0.05
        }
    }

    /// Check if this app supports format-preserving replacements
    /// Future feature: preserve bold/italic/links when replacing text
    var supportsFormatPreservation: Bool {
        // For now, only native macOS apps support this
        return !isElectronApp && !isChromiumBased
    }

    /// Estimated font size for text measurement (heuristic-based)
    /// Used when AX API bounds are unavailable or implausible
    var estimatedFontSize: CGFloat {
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            return 15.0
        case "com.hnc.Discord":
            return 15.0
        case "com.microsoft.VSCode":
            return 14.0
        default:
            return isElectronApp ? 15.0 : 13.0
        }
    }

    /// Character width correction factor (per character)
    /// Accounts for cumulative rendering differences between NSFont measurement
    /// and actual app rendering. Applied as: measuredWidth - (charCount * correction)
    var characterWidthCorrection: CGFloat {
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            // Disable correction - use raw NSFont measurement
            // Font measurement appears more accurate than expected
            return 0.0
        case "com.hnc.Discord":
            return 0.0
        default:
            return 0.0
        }
    }

    /// Horizontal padding inside text input elements
    /// Used for estimation when AX API fails
    var estimatedLeftPadding: CGFloat {
        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            // Slack's message input has approximately 12px left padding
            return 12.0
        case "com.hnc.Discord":
            return 12.0
        case "com.microsoft.VSCode":
            return 10.0
        default:
            return isElectronApp ? 12.0 : 8.0
        }
    }
}
