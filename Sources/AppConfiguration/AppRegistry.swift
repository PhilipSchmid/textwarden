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

    /// Get effective configuration for a bundle ID.
    /// Uses auto-detected profile for unknown apps, falls back to default.
    func effectiveConfiguration(for bundleID: String) -> AppConfiguration {
        // If explicit config exists, use it
        if let config = configurations[bundleID] {
            return config
        }

        // Try to get profile from recommendation engine
        let engine = StrategyRecommendationEngine.shared
        if let profile = engine.profile(for: bundleID), !profile.isExpired {
            // Build dynamic configuration from profile
            return AppConfiguration(
                identifier: bundleID,
                displayName: bundleID,
                bundleIDs: [bundleID],
                category: .custom,
                parserType: .generic,
                preferredStrategies: profile.recommendedStrategies,
                features: profile.appFeatures
            )
        }

        return .default
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
        register(.claude)
        register(.chatgpt)
        register(.perplexity)
        register(.browsers)
        register(.notion)
        register(.mail)
        register(.messages)
        register(.notes)
        register(.textEdit)
        register(.reminders)
        register(.pages)
        register(.whatsapp)
        register(.telegram)
        register(.word)
        register(.powerpoint)
        register(.outlook)
        register(.webex)
        // Note: .default is not registered, used as fallback
        // Note: Terminal apps are not supported (hidden by default in UserPreferences)
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
        preferredStrategies: [.slack],  // Dedicated strategy only - returns unavailable on failure (no fallback)
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,
            requiresTypingPause: true,
            supportsFormattedText: true,
            childElementTraversal: true,
            delaysAXNotifications: false,  // Slack sends AX notifications immediately
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true,  // Electron byte offsets are fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Claude (Anthropic)

    static let claude = AppConfiguration(
        identifier: "claude",
        displayName: "Claude",
        bundleIDs: ["com.anthropic.claudefordesktop"],
        category: .electron,
        parserType: .claude,  // Dedicated parser without Slack's newline quirks
        fontConfig: FontConfig(
            defaultSize: 16,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 12,
        preferredStrategies: [.chromium, .textMarker, .rangeBounds, .elementTree, .lineIndex],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,
            requiresTypingPause: true,
            supportsFormattedText: false,  // Claude input is plain text
            childElementTraversal: true,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true,  // Electron byte offsets are fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - ChatGPT (OpenAI)

    static let chatgpt = AppConfiguration(
        identifier: "chatgpt",
        displayName: "ChatGPT",
        bundleIDs: ["com.openai.chat"],
        category: .electron,
        parserType: .generic,  // RangeBoundsStrategy works well
        fontConfig: FontConfig(
            defaultSize: 16,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 12,
        preferredStrategies: [.rangeBounds, .textMarker, .elementTree, .lineIndex],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,
            requiresTypingPause: false,  // Uses rangeBounds (direct AX API), no cursor manipulation needed
            supportsFormattedText: false,
            childElementTraversal: true,
            delaysAXNotifications: true,  // ChatGPT batches AX notifications, needs keyboard detection
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true,  // Electron byte offsets are fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Perplexity

    static let perplexity = AppConfiguration(
        identifier: "perplexity",
        displayName: "Perplexity",
        bundleIDs: ["ai.perplexity.mac"],
        category: .electron,
        parserType: .generic,
        fontConfig: FontConfig(
            defaultSize: 16,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 12,
        // AnchorSearch works well, Chromium/RangeBounds fail for this app
        preferredStrategies: [.anchorSearch, .textMarker, .elementTree],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,
            requiresTypingPause: false,  // Uses anchorSearch (direct AX API), no cursor manipulation needed
            supportsFormattedText: false,
            childElementTraversal: true,
            delaysAXNotifications: true,  // Electron app, needs keyboard detection
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true,  // Electron byte offsets are fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
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
        // Teams' main AXTextArea doesn't support AXBoundsForRange, BUT child AXStaticText
        // elements DO support it - same pattern as Slack (both are Chromium-based).
        // TeamsStrategy traverses the AX tree to find AXStaticText children and queries
        // AXBoundsForRange on them directly for precise positioning.
        preferredStrategies: [.teams],  // Dedicated strategy using child element traversal
        features: AppFeatures(
            visualUnderlinesEnabled: true,  // Enabled - TeamsStrategy uses child element bounds
            textReplacementMethod: .browserStyle,
            requiresTypingPause: true,  // Wait for typing pause before querying AX tree
            supportsFormattedText: true,
            childElementTraversal: true,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true,  // Electron byte offsets are fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
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
            "ai.perplexity.comet"  // Perplexity Comet browser
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
        // Notion is Chromium/Electron-based like Slack and Teams. The same child element
        // tree traversal approach works: parent AXTextArea's AXBoundsForRange returns
        // invalid results, but child AXStaticText elements DO support AXBoundsForRange
        // with local character ranges for precise positioning.
        preferredStrategies: [.notion],
        features: AppFeatures(
            visualUnderlinesEnabled: true,  // Enabled - NotionStrategy uses child element bounds
            textReplacementMethod: .browserStyle,
            requiresTypingPause: true,  // Wait for typing pause before querying AX tree
            supportsFormattedText: false,
            childElementTraversal: true,
            delaysAXNotifications: true,  // Notion batches AX notifications, needs keyboard detection
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true,  // Electron byte offsets are fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
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
        // Mail uses WebKit for composition - dedicated MailStrategy handles WebKit bounds
        // Text replacement needs browser-style (selection + paste) because AXValue is read-only
        preferredStrategies: [.mail],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,  // WebKit needs selection + paste
            requiresTypingPause: false,
            supportsFormattedText: true,  // Mail supports rich text
            childElementTraversal: true,  // May need to traverse AXWebArea children
            delaysAXNotifications: false,  // Mail sends AX notifications promptly like Slack
            focusBouncesDuringPaste: true,  // Mail's WebKit fires multiple focus events during Cmd+V
            requiresFullReanalysisAfterReplacement: true,  // WebKit byte offsets are fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
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
            requiresFullReanalysisAfterReplacement: true,  // Catalyst byte offsets may be fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Apple Notes

    static let notes = AppConfiguration(
        identifier: "notes",
        displayName: "Apple Notes",
        bundleIDs: ["com.apple.Notes"],
        category: .native,
        parserType: .generic,
        fontConfig: FontConfig(
            defaultSize: 12,
            fontFamily: nil,  // System font
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 0,
        // Notes uses standard NSTextView with reliable AXBoundsForRange for positioning.
        preferredStrategies: [.rangeBounds, .lineIndex, .fontMetrics],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .standard,
            requiresTypingPause: false,
            supportsFormattedText: true,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - TextEdit

    static let textEdit = AppConfiguration(
        identifier: "textedit",
        displayName: "TextEdit",
        bundleIDs: ["com.apple.TextEdit"],
        category: .native,
        parserType: .generic,
        fontConfig: FontConfig(
            defaultSize: 12,
            fontFamily: nil,  // System font
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 0,
        // TextEdit is the quintessential NSTextView app with full AX support.
        preferredStrategies: [.rangeBounds, .lineIndex, .fontMetrics],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .standard,
            requiresTypingPause: false,
            supportsFormattedText: true,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Apple Reminders

    static let reminders = AppConfiguration(
        identifier: "reminders",
        displayName: "Apple Reminders",
        bundleIDs: ["com.apple.reminders"],
        category: .native,
        parserType: .generic,
        fontConfig: FontConfig(
            defaultSize: 13,
            fontFamily: nil,  // System font
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 0,
        // Reminders uses standard Cocoa text fields for task titles and notes.
        preferredStrategies: [.rangeBounds, .lineIndex, .fontMetrics],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .standard,
            requiresTypingPause: false,
            supportsFormattedText: false,  // Plain text tasks
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Apple Pages

    static let pages = AppConfiguration(
        identifier: "pages",
        displayName: "Apple Pages",
        bundleIDs: ["com.apple.iWork.Pages"],
        category: .native,
        parserType: .generic,
        fontConfig: FontConfig(
            defaultSize: 12,
            fontFamily: nil,  // System font
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 0,
        // Pages uses standard AXTextArea with reliable AXBoundsForRange for positioning.
        // RangeBoundsStrategy handles this well. No dedicated strategy needed.
        preferredStrategies: [.rangeBounds, .lineIndex, .fontMetrics],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,  // Standard AX setValue reports success but doesn't work
            requiresTypingPause: false,
            supportsFormattedText: true,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,  // Native app with reliable AXValue
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - WhatsApp

    static let whatsapp = AppConfiguration(
        identifier: "whatsapp",
        displayName: "WhatsApp",
        bundleIDs: ["net.whatsapp.WhatsApp"],
        category: .custom,
        parserType: .generic,
        fontConfig: FontConfig(
            defaultSize: 14,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 5,
        // WhatsApp is a Mac Catalyst app with similar behavior to Messages.
        // Uses the same strategy chain for positioning.
        // Known issue: AX API may return stale text after conversation switch.
        // See MessengerBehavior for special handling of stale data.
        preferredStrategies: [.textMarker, .rangeBounds, .lineIndex, .insertionPoint, .fontMetrics],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,  // Catalyst apps need keyboard-based replacement
            requiresTypingPause: false,
            supportsFormattedText: false,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: true,  // Catalyst byte offsets may be fragile
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Telegram

    static let telegram = AppConfiguration(
        identifier: "telegram",
        displayName: "Telegram",
        bundleIDs: ["ru.keepcoder.Telegram"],
        category: .custom,
        parserType: .generic,
        fontConfig: FontConfig(
            defaultSize: 13,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 0,
        // Telegram is a native macOS app with a custom text view.
        // AXBoundsForRange works and provides pixel-perfect positioning.
        // Note: AXNumberOfCharacters uses UTF-16 units, so emoji handling
        // requires UTF-16 index conversion (handled by RangeBoundsStrategy).
        preferredStrategies: [.rangeBounds, .lineIndex, .fontMetrics],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .standard,
            requiresTypingPause: false,
            supportsFormattedText: true,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Microsoft Word

    static let word = AppConfiguration(
        identifier: "word",
        displayName: "Microsoft Word",
        bundleIDs: ["com.microsoft.Word"],
        category: .native,
        parserType: .word,
        fontConfig: FontConfig(
            defaultSize: 12,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 4,
        // Word uses a dedicated strategy for positioning. AXBoundsForRange works reliably
        // on Word 16.104+ (tested Dec 2024). Word's AXTextArea is a flat element with all
        // text content - no child elements like Outlook's compose body.
        // Text replacement needs browser-style (selection + keyboard paste) as standard
        // AX setValue doesn't work reliably for Word.
        preferredStrategies: [.word],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,  // Standard AX setValue doesn't work for Word
            requiresTypingPause: false,
            supportsFormattedText: true,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,  // Word AXValue updates reliably
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Microsoft PowerPoint

    static let powerpoint = AppConfiguration(
        identifier: "powerpoint",
        displayName: "Microsoft PowerPoint",
        bundleIDs: ["com.microsoft.Powerpoint"],
        category: .native,
        parserType: .powerpoint,
        fontConfig: FontConfig(
            defaultSize: 18,
            fontFamily: nil,
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 4,
        // PowerPoint uses the same mso99 framework as Word and likely has the same crash issue
        // with parameterized accessibility attribute queries.
        // Visual underlines disabled; floating error indicator still works for corrections.
        preferredStrategies: [],
        features: AppFeatures(
            visualUnderlinesEnabled: false,  // Disabled (same AX API issues as Word)
            textReplacementMethod: .browserStyle,  // Standard AX setValue doesn't work
            requiresTypingPause: false,
            supportsFormattedText: true,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,  // PowerPoint AXValue updates reliably
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
        )
    )

    // MARK: - Microsoft Outlook

    static let outlook = AppConfiguration(
        identifier: "outlook",
        displayName: "Microsoft Outlook",
        bundleIDs: ["com.microsoft.Outlook"],
        category: .native,
        parserType: .outlook,
        fontConfig: FontConfig(
            defaultSize: 12,
            fontFamily: "Aptos",
            spacingMultiplier: 1.5  // Aptos font renders wider than system font metrics
        ),
        horizontalPadding: 20,  // Outlook compose has left margin with sparkle icon
        // Outlook uses a dedicated strategy that handles both subject field (AXTextField) and
        // compose body (AXTextArea). AXBoundsForRange works on both, with tree traversal fallback.
        // Text replacement needs browser-style to preserve formatting (AXSetValue strips rich text).
        preferredStrategies: [.outlook],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .browserStyle,  // AXSetValue works but strips formatting
            requiresTypingPause: false,
            supportsFormattedText: true,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,  // Office apps update AXValue reliably
            defersTextExtraction: true,  // Defer AX calls to prevent freeze with Copilot
            requiresFrameValidation: true,  // Copilot chat panel changes frame dynamically
            hasTextMarkerIndexOffset: true  // Copilot has invisible characters causing index mismatch
        )
    )

    // MARK: - Cisco WebEx

    static let webex = AppConfiguration(
        identifier: "webex",
        displayName: "Cisco WebEx",
        bundleIDs: ["Cisco-Systems.Spark"],
        category: .native,
        parserType: .webex,
        fontConfig: FontConfig(
            defaultSize: 14,
            fontFamily: nil,  // System font
            spacingMultiplier: 1.0
        ),
        horizontalPadding: 8,
        // WebEx uses standard Cocoa text views - AXBoundsForRange works directly
        preferredStrategies: [.webex],
        features: AppFeatures(
            visualUnderlinesEnabled: true,
            textReplacementMethod: .standard,
            requiresTypingPause: true,  // Wait for typing pause to avoid flagging incomplete words
            supportsFormattedText: false,
            childElementTraversal: false,
            delaysAXNotifications: false,
            focusBouncesDuringPaste: false,
            requiresFullReanalysisAfterReplacement: false,
            defersTextExtraction: false,
            requiresFrameValidation: false,
            hasTextMarkerIndexOffset: false
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
