//
//  AppConfiguration.swift
//  TextWarden
//
//  Declarative app configuration system.
//  Defines how TextWarden behaves for different applications.
//

import Foundation

// MARK: - App Category

/// Technology category for grouping similar apps with shared defaults
enum AppCategory {
    case native      // Standard macOS apps (TextEdit, Notes, Mail)
    case electron    // Electron-based apps (Slack, Notion, VSCode)
    case browser     // Web browsers (Chrome, Safari, Firefox)
    case terminal    // Terminal emulators
    case custom      // Apps with fully custom behavior
}

// MARK: - Parser Type

/// Identifies a parser implementation
enum ParserType {
    case generic
    case slack
    case browser
    case notion
    case terminal
    case teams
    case mail
}

// MARK: - Strategy Type

/// Identifies a positioning strategy
enum StrategyType: String, CaseIterable {
    case chromium   // Selection-based marker range positioning for Chromium apps (Slack, Teams, etc.)
    case textMarker
    case rangeBounds
    case elementTree
    case lineIndex
    case origin
    case anchorSearch
    case fontMetrics

    // MARK: - Legacy (not registered in PositionResolver)
    // These strategies interfere with typing (manipulate cursor/selection)
    // Kept for compilation of Legacy/ strategy files
    case selectionBounds
    case navigation

    /// Whether this strategy is legacy (disabled, not registered)
    var isLegacy: Bool {
        switch self {
        case .selectionBounds, .navigation:
            return true
        default:
            return false
        }
    }
}

// MARK: - Text Replacement Method

/// How text corrections are applied
enum TextReplacementMethod {
    case standard       // AX API setValue - works for native macOS apps
    case browserStyle   // Selection + keyboard paste - for Electron/browser apps where AX API fails
}

// MARK: - Font Configuration

/// Font settings for an app
struct FontConfig: Equatable {
    let defaultSize: CGFloat
    let fontFamily: String?
    let spacingMultiplier: CGFloat

    static let standard = FontConfig(
        defaultSize: 13,
        fontFamily: nil,
        spacingMultiplier: 1.0
    )
}

// MARK: - App Features

/// Feature flags controlling app-specific behavior
struct AppFeatures: Equatable {
    let visualUnderlinesEnabled: Bool
    let textReplacementMethod: TextReplacementMethod
    let requiresTypingPause: Bool
    let supportsFormattedText: Bool
    let childElementTraversal: Bool

    /// Whether this app delays AX notifications (batches them) instead of sending immediately.
    /// Apps like Notion batch notifications and send them late, requiring keyboard-based typing detection.
    /// Apps like Slack send notifications immediately, so they don't need keyboard detection.
    /// When true, TypingDetector will use keyboard events to proactively trigger re-analysis.
    let delaysAXNotifications: Bool

    /// Whether focus bounces between elements during paste operations.
    /// Some WebKit-based apps (like Mail) fire multiple AXFocusedUIElementChanged notifications
    /// during Cmd+V, causing the monitored element to temporarily become nil.
    /// When true, AnalysisCoordinator uses a grace period to preserve the popover during focus settling.
    let focusBouncesDuringPaste: Bool

    /// Whether this app requires full re-analysis after text replacement.
    /// Electron and WebKit apps have fragile byte offsets that become invalid when text shifts.
    /// When true, all errors are cleared and fresh analysis is triggered after replacement.
    let requiresFullReanalysisAfterReplacement: Bool

    static let standard = AppFeatures(
        visualUnderlinesEnabled: true,
        textReplacementMethod: .standard,
        requiresTypingPause: false,
        supportsFormattedText: false,
        childElementTraversal: false,
        delaysAXNotifications: false,
        focusBouncesDuringPaste: false,
        requiresFullReanalysisAfterReplacement: false
    )
}

// MARK: - App Category Defaults

extension AppCategory {

    /// Default features for this category
    var defaultFeatures: AppFeatures {
        switch self {
        case .native:
            return AppFeatures(
                visualUnderlinesEnabled: true,
                textReplacementMethod: .standard,
                requiresTypingPause: false,
                supportsFormattedText: false,
                childElementTraversal: false,
                delaysAXNotifications: false,
                focusBouncesDuringPaste: false,
                requiresFullReanalysisAfterReplacement: false
            )
        case .electron:
            return AppFeatures(
                visualUnderlinesEnabled: true,
                textReplacementMethod: .browserStyle,
                requiresTypingPause: false,
                supportsFormattedText: false,
                childElementTraversal: true,
                delaysAXNotifications: false,  // Most Electron apps send notifications immediately
                focusBouncesDuringPaste: false,
                requiresFullReanalysisAfterReplacement: true  // Electron byte offsets are fragile
            )
        case .browser:
            return AppFeatures(
                visualUnderlinesEnabled: false,
                textReplacementMethod: .browserStyle,
                requiresTypingPause: false,
                supportsFormattedText: false,
                childElementTraversal: true,
                delaysAXNotifications: false,
                focusBouncesDuringPaste: false,
                requiresFullReanalysisAfterReplacement: true  // Browser byte offsets are fragile
            )
        case .terminal:
            return AppFeatures(
                visualUnderlinesEnabled: false,
                textReplacementMethod: .standard,
                requiresTypingPause: false,
                supportsFormattedText: false,
                childElementTraversal: false,
                delaysAXNotifications: false,
                focusBouncesDuringPaste: false,
                requiresFullReanalysisAfterReplacement: false
            )
        case .custom:
            return .standard
        }
    }

    /// Default strategy order for this category
    var defaultStrategies: [StrategyType] {
        switch self {
        case .native:
            return [.rangeBounds, .lineIndex, .anchorSearch, .fontMetrics]
        case .electron:
            return [.textMarker, .rangeBounds, .elementTree, .lineIndex, .fontMetrics]
        case .browser:
            return [.textMarker, .rangeBounds, .elementTree, .lineIndex]
        case .terminal:
            return []  // Underlines disabled
        case .custom:
            // Exclude legacy strategies that interfere with typing
            return StrategyType.allCases.filter { !$0.isLegacy }
        }
    }

    /// Strategies disabled by default for this category
    /// Note: Legacy strategies (selectionBounds, navigation) have been removed entirely
    var defaultDisabledStrategies: Set<StrategyType> {
        return []
    }

    /// Default font configuration
    var defaultFontConfig: FontConfig {
        return .standard
    }

    /// Default horizontal padding
    var defaultPadding: CGFloat {
        return 8
    }
}

// MARK: - App Configuration

/// Complete configuration for an app or app category
struct AppConfiguration {
    let identifier: String
    let displayName: String
    let bundleIDs: Set<String>
    let category: AppCategory

    // Parser (required)
    let parserType: ParserType

    // Optional overrides (nil = use category defaults)
    private let _fontConfig: FontConfig?
    private let _horizontalPadding: CGFloat?
    private let _preferredStrategies: [StrategyType]?
    private let _disabledStrategies: Set<StrategyType>?
    private let _features: AppFeatures?

    init(
        identifier: String,
        displayName: String,
        bundleIDs: Set<String>,
        category: AppCategory,
        parserType: ParserType,
        fontConfig: FontConfig? = nil,
        horizontalPadding: CGFloat? = nil,
        preferredStrategies: [StrategyType]? = nil,
        disabledStrategies: Set<StrategyType>? = nil,
        features: AppFeatures? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.bundleIDs = bundleIDs
        self.category = category
        self.parserType = parserType
        self._fontConfig = fontConfig
        self._horizontalPadding = horizontalPadding
        self._preferredStrategies = preferredStrategies
        self._disabledStrategies = disabledStrategies
        self._features = features
    }

    // MARK: - Effective Values (with category fallbacks)

    /// Font configuration (falls back to category default)
    var fontConfig: FontConfig {
        _fontConfig ?? category.defaultFontConfig
    }

    /// Horizontal padding (falls back to category default)
    var horizontalPadding: CGFloat {
        _horizontalPadding ?? category.defaultPadding
    }

    /// Preferred strategy order (falls back to category default)
    var preferredStrategies: [StrategyType] {
        _preferredStrategies ?? category.defaultStrategies
    }

    /// Disabled strategies (falls back to category default)
    var disabledStrategies: Set<StrategyType> {
        _disabledStrategies ?? category.defaultDisabledStrategies
    }

    /// App features (falls back to category default)
    var features: AppFeatures {
        _features ?? category.defaultFeatures
    }
}
