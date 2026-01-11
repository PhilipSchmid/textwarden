//
//  UserPreferences.swift
//  TextWarden
//
//  User preferences with UserDefaults persistence
//

import Combine
import Foundation

/// Pause duration options for grammar checking
enum PauseDuration: String, CaseIterable, Codable {
    case active = "Active"
    case oneHour = "Paused for 1 Hour"
    case twentyFourHours = "Paused for 24 Hours"
    case indefinite = "Paused Until Resumed"
}

/// Observable user preferences with automatic persistence
@MainActor
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var resumeTimer: Timer?
    private var cleanupTimer: Timer?

    /// Helper to encode and persist a value with logging on failure
    private func persist(_ value: some Encodable, forKey key: String) {
        do {
            let encoded = try encoder.encode(value)
            defaults.set(encoded, forKey: key)
        } catch {
            Logger.warning("Failed to persist \(key): \(error.localizedDescription)", category: Logger.general)
        }
    }

    /// Current pause state for grammar checking
    @Published var pauseDuration: PauseDuration {
        didSet {
            defaults.set(pauseDuration.rawValue, forKey: Keys.pauseDuration)
            handlePauseChange()
        }
    }

    /// Date when pause expires (for timed pauses)
    @Published var pausedUntil: Date? {
        didSet {
            if let date = pausedUntil {
                defaults.set(date, forKey: Keys.pausedUntil)
            } else {
                defaults.removeObject(forKey: Keys.pausedUntil)
            }
        }
    }

    /// Computed property: whether grammar checking is currently active
    var isEnabled: Bool {
        switch pauseDuration {
        case .active:
            return true
        case .oneHour, .twentyFourHours:
            // Check if pause has expired
            if let until = pausedUntil, Date() < until {
                return false
            } else {
                // Pause expired - auto-resume
                if pauseDuration != .active {
                    DispatchQueue.main.async { [weak self] in
                        self?.pauseDuration = .active
                        self?.pausedUntil = nil
                    }
                }
                return true
            }
        case .indefinite:
            return false
        }
    }

    /// Per-application enable/disable settings
    @Published var disabledApplications: Set<String> {
        didSet {
            persist(disabledApplications, forKey: Keys.disabledApplications)
        }
    }

    /// Per-application pause durations
    @Published var appPauseDurations: [String: PauseDuration] {
        didSet {
            persist(appPauseDurations, forKey: Keys.appPauseDurations)
        }
    }

    /// Per-application pause expiry dates (for timed pauses)
    @Published var appPausedUntil: [String: Date] {
        didSet {
            persist(appPausedUntil, forKey: Keys.appPausedUntil)
        }
    }

    /// Discovered applications (apps that have been activated while TextWarden is running)
    @Published var discoveredApplications: Set<String> {
        didSet {
            persist(discoveredApplications, forKey: Keys.discoveredApplications)
        }
    }

    /// Applications where underlines are disabled (user preference override)
    /// This allows users to disable underlines for specific apps while keeping grammar checking active
    @Published var appUnderlinesDisabled: Set<String> {
        didSet {
            persist(appUnderlinesDisabled, forKey: Keys.appUnderlinesDisabled)
        }
    }

    /// Disabled websites (domains where grammar checking is disabled)
    /// Supports exact matches (e.g., "github.com") and wildcard patterns (e.g., "*.google.com")
    @Published var disabledWebsites: Set<String> {
        didSet {
            persist(disabledWebsites, forKey: Keys.disabledWebsites)
        }
    }

    /// Custom words to ignore
    @Published var customDictionary: Set<String> {
        didSet {
            persist(customDictionary, forKey: Keys.customDictionary)
        }
    }

    /// Permanently ignored grammar rules
    @Published var ignoredRules: Set<String> {
        didSet {
            persist(ignoredRules, forKey: Keys.ignoredRules)
        }
    }

    /// Globally ignored error texts (for "Ignore Everywhere")
    /// Stores error texts that should be ignored across all documents
    @Published var ignoredErrorTexts: Set<String> {
        didSet {
            persist(ignoredErrorTexts, forKey: Keys.ignoredErrorTexts)
        }
    }

    /// Enabled grammar check categories (e.g., "Spelling", "Grammar", "Style")
    @Published var enabledCategories: Set<String> {
        didSet {
            persist(enabledCategories, forKey: Keys.enabledCategories)
        }
    }

    /// All available grammar check categories from Harper
    /// Note: "Readability" is intentionally excluded - we use our own ReadabilityCalculator instead,
    /// which provides better analysis (Flesch Reading Ease) and AI-powered simplification suggestions.
    static let allCategories: Set<String> = [
        "Agreement",
        "BoundaryError",
        "Capitalization",
        "Eggcorn",
        "Enhancement",
        "Formatting",
        "Grammar",
        "Malapropism",
        "Miscellaneous",
        "Nonstandard",
        "Punctuation",
        "Redundancy",
        "Regionalism",
        "Repetition",
        "Spelling",
        "Style",
        "Typo",
        "Usage",
        "WordChoice",
    ]

    // MARK: - Individual Rule Toggles

    /// Enforce Oxford comma (serial comma) in lists
    /// When enabled, flags lists like "apples, bananas and oranges" as needing a comma before "and"
    @Published var enforceOxfordComma: Bool {
        didSet { defaults.set(enforceOxfordComma, forKey: Keys.enforceOxfordComma) }
    }

    /// Check for proper ellipsis formatting
    /// When enabled, suggests using proper ellipsis character (…) instead of three dots (...)
    @Published var checkEllipsis: Bool {
        didSet { defaults.set(checkEllipsis, forKey: Keys.checkEllipsis) }
    }

    /// Check for unclosed quotation marks
    @Published var checkUnclosedQuotes: Bool {
        didSet { defaults.set(checkUnclosedQuotes, forKey: Keys.checkUnclosedQuotes) }
    }

    /// Check dash usage (em-dash vs en-dash vs hyphen)
    @Published var checkDashes: Bool {
        didSet { defaults.set(checkDashes, forKey: Keys.checkDashes) }
    }

    /// Terminal applications disabled by default (users can enable them in Applications preferences)
    /// These apps are set to .indefinite pause on first run to avoid false positives from command output
    static let terminalApplications: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
    ]

    /// Always open settings window in foreground on launch
    @Published var openInForeground: Bool {
        didSet {
            defaults.set(openInForeground, forKey: Keys.openInForeground)
        }
    }

    /// Whether the user has completed onboarding (triggers onboarding on first launch or after reset)
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    /// Whether the menu bar tooltip has been shown after onboarding (shown only once, ever)
    @Published var hasShownMenuBarTooltip: Bool {
        didSet {
            defaults.set(hasShownMenuBarTooltip, forKey: Keys.hasShownMenuBarTooltip)
        }
    }

    // MARK: - Language & Dialect

    /// Selected English dialect for grammar checking
    @Published var selectedDialect: String {
        didSet {
            defaults.set(selectedDialect, forKey: Keys.selectedDialect)
        }
    }

    /// Available English dialects
    static let availableDialects = [
        "American",
        "British",
        "Canadian",
        "Australian",
    ]

    // MARK: - Predefined Wordlists

    // Each wordlist has a Bool toggle that enables/disables it
    // To add a new wordlist:
    // 1. Add a @Published var property here (e.g., enableITTerminology)
    // 2. Add the corresponding Keys constant in the Keys enum below
    // 3. Initialize the property in init() with a default value
    // 4. Load the saved value in init() from UserDefaults
    // 5. Add the toggle to CustomVocabularyView in PreferencesView.swift
    // 6. Add the wordlist category to WordlistCategory enum in slang_dict.rs
    // 7. Update analyzer.rs to conditionally load the wordlist

    /// Enable recognition of internet abbreviations (BTW, FYI, LOL, etc.)
    @Published var enableInternetAbbreviations: Bool {
        didSet {
            defaults.set(enableInternetAbbreviations, forKey: Keys.enableInternetAbbreviations)
        }
    }

    /// Enable recognition of Gen Z slang (ghosting, sus, slay, etc.)
    @Published var enableGenZSlang: Bool {
        didSet {
            defaults.set(enableGenZSlang, forKey: Keys.enableGenZSlang)
        }
    }

    /// Enable recognition of IT terminology (kubernetes, docker, API, etc.)
    @Published var enableITTerminology: Bool {
        didSet {
            defaults.set(enableITTerminology, forKey: Keys.enableITTerminology)
        }
    }

    /// Enable recognition of brand/company names (Apple, Microsoft, Google, etc.)
    @Published var enableBrandNames: Bool {
        didSet {
            defaults.set(enableBrandNames, forKey: Keys.enableBrandNames)
        }
    }

    /// Enable recognition of person names (first names)
    @Published var enablePersonNames: Bool {
        didSet {
            defaults.set(enablePersonNames, forKey: Keys.enablePersonNames)
        }
    }

    /// Enable recognition of surnames/last names
    @Published var enableLastNames: Bool {
        didSet {
            defaults.set(enableLastNames, forKey: Keys.enableLastNames)
        }
    }

    /// Import words from macOS system dictionary (words added via "Learn Spelling" in other apps)
    @Published var enableMacOSDictionary: Bool {
        didSet {
            defaults.set(enableMacOSDictionary, forKey: Keys.enableMacOSDictionary)
        }
    }

    // MARK: - Language Detection

    /// Enable detection and filtering of non-English words
    @Published var enableLanguageDetection: Bool {
        didSet {
            defaults.set(enableLanguageDetection, forKey: Keys.enableLanguageDetection)
        }
    }

    /// Languages to exclude from grammar checking (e.g., "spanish", "german")
    @Published var excludedLanguages: Set<String> {
        didSet {
            persist(excludedLanguages, forKey: Keys.excludedLanguages)
        }
    }

    /// Available languages for detection (from whichlang library)
    static let availableLanguages = [
        "Arabic", "Dutch", "English", "French", "German",
        "Hindi", "Italian", "Japanese", "Korean", "Mandarin",
        "Portuguese", "Russian", "Spanish", "Swedish",
        "Turkish", "Vietnamese",
    ]

    /// Map UI-friendly names to language codes for Rust
    static func languageCode(for name: String) -> String {
        switch name {
        case "Arabic": "arabic"
        case "Dutch": "dutch"
        case "English": "english"
        case "French": "french"
        case "German": "german"
        case "Hindi": "hindi"
        case "Italian": "italian"
        case "Japanese": "japanese"
        case "Korean": "korean"
        case "Mandarin": "mandarin"
        case "Portuguese": "portuguese"
        case "Russian": "russian"
        case "Spanish": "spanish"
        case "Swedish": "swedish"
        case "Turkish": "turkish"
        case "Vietnamese": "vietnamese"
        default: name.lowercased()
        }
    }

    // MARK: - Keyboard Shortcuts

    /// Enable keyboard shortcuts
    @Published var keyboardShortcutsEnabled: Bool {
        didSet {
            defaults.set(keyboardShortcutsEnabled, forKey: Keys.keyboardShortcutsEnabled)
        }
    }

    // MARK: - Suggestion Appearance

    /// Suggestion popover opacity (0.7 to 1.0)
    @Published var suggestionOpacity: Double {
        didSet {
            defaults.set(suggestionOpacity, forKey: Keys.suggestionOpacity)
        }
    }

    /// Suggestion text size (10.0 to 20.0)
    @Published var suggestionTextSize: Double {
        didSet {
            defaults.set(suggestionTextSize, forKey: Keys.suggestionTextSize)
        }
    }

    /// Suggestion position preference
    @Published var suggestionPosition: String {
        didSet {
            defaults.set(suggestionPosition, forKey: Keys.suggestionPosition)
        }
    }

    /// Available position options
    static let suggestionPositions = [
        "Auto",
        "Above",
        "Below",
    ]

    /// App theme (for the TextWarden application UI itself)
    @Published var appTheme: String {
        didSet {
            defaults.set(appTheme, forKey: Keys.appTheme)
        }
    }

    /// Overlay theme (for popovers and error/style indicators)
    @Published var overlayTheme: String {
        didSet {
            defaults.set(overlayTheme, forKey: Keys.overlayTheme)
        }
    }

    /// Available theme options
    static let themeOptions = [
        "System",
        "Light",
        "Dark",
    ]

    /// Whether to show error underlines (global toggle)
    @Published var showUnderlines: Bool {
        didSet {
            defaults.set(showUnderlines, forKey: Keys.showUnderlines)
        }
    }

    /// Error underline thickness (1.0 to 5.0)
    @Published var underlineThickness: Double {
        didSet {
            defaults.set(underlineThickness, forKey: Keys.underlineThickness)
        }
    }

    /// Maximum number of errors before hiding underlines and showing only the indicator
    /// When error count exceeds this threshold, underlines are hidden to reduce visual clutter
    @Published var maxErrorsForUnderlines: Int {
        didSet {
            defaults.set(maxErrorsForUnderlines, forKey: Keys.maxErrorsForUnderlines)
        }
    }

    /// Error indicator position in Terminal and other apps
    @Published var indicatorPosition: String {
        didSet {
            defaults.set(indicatorPosition, forKey: Keys.indicatorPosition)
        }
    }

    /// Available indicator position options
    static let indicatorPositions = [
        "Top Left",
        "Top Right",
        "Center Left",
        "Center Right",
        "Bottom Left",
        "Bottom Right",
    ]

    /// Enable hover-to-show popover behavior
    @Published var enableHoverPopover: Bool {
        didSet {
            defaults.set(enableHoverPopover, forKey: Keys.enableHoverPopover)
        }
    }

    /// Delay in milliseconds before showing popover on hover (0 = instant)
    @Published var popoverHoverDelayMs: Int {
        didSet {
            defaults.set(popoverHoverDelayMs, forKey: Keys.popoverHoverDelayMs)
        }
    }

    // MARK: - Diagnostics

    /// Show debug border for text field bounds (red box)
    @Published var showDebugBorderTextFieldBounds: Bool {
        didSet {
            defaults.set(showDebugBorderTextFieldBounds, forKey: Keys.showDebugBorderTextFieldBounds)
        }
    }

    /// Show debug border for CGWindow coordinates (blue box)
    @Published var showDebugBorderCGWindowCoords: Bool {
        didSet {
            defaults.set(showDebugBorderCGWindowCoords, forKey: Keys.showDebugBorderCGWindowCoords)
        }
    }

    /// Show debug border for Cocoa coordinates (green box)
    @Published var showDebugBorderCocoaCoords: Bool {
        didSet {
            defaults.set(showDebugBorderCocoaCoords, forKey: Keys.showDebugBorderCocoaCoords)
        }
    }

    /// Show character position markers for coordinate debugging
    /// Orange marker = underline start position
    /// Cyan marker = first character position (requires showDebugBorderTextFieldBounds)
    @Published var showDebugCharacterMarkers: Bool {
        didSet {
            defaults.set(showDebugCharacterMarkers, forKey: Keys.showDebugCharacterMarkers)
        }
    }

    // MARK: - Milestones & Donation Prompts

    /// Set of milestone IDs that have been shown to the user
    @Published var shownMilestones: Set<String> {
        didSet {
            persist(shownMilestones, forKey: Keys.shownMilestones)
        }
    }

    /// User has permanently disabled milestone prompts
    @Published var milestonesDisabled: Bool {
        didSet {
            defaults.set(milestonesDisabled, forKey: Keys.milestonesDisabled)
        }
    }

    // MARK: - LLM Style Checking

    // MARK: - Readability Settings

    /// Master toggle for all readability features (enabled by default)
    /// When enabled: Shows Flesch score in indicator, analyzes sentence complexity,
    /// and generates AI simplification suggestions for complex sentences
    @Published var readabilityEnabled: Bool {
        didSet {
            defaults.set(readabilityEnabled, forKey: Keys.readabilityEnabled)
        }
    }

    /// Show violet dashed underlines for complex sentences (only applies when readabilityEnabled is true)
    @Published var showReadabilityUnderlines: Bool {
        didSet {
            defaults.set(showReadabilityUnderlines, forKey: Keys.showReadabilityUnderlines)
        }
    }

    /// Selected target audience for readability analysis
    /// Determines the Flesch score threshold for marking sentences as "too complex"
    @Published var selectedTargetAudience: String {
        didSet {
            defaults.set(selectedTargetAudience, forKey: Keys.selectedTargetAudience)
        }
    }

    /// Available target audience options
    static let targetAudienceOptions: [String] = TargetAudience.allCases.map(\.displayName)

    // MARK: - Style Checking Settings

    /// Enable LLM-powered style suggestions
    @Published var enableStyleChecking: Bool {
        didSet {
            defaults.set(enableStyleChecking, forKey: Keys.enableStyleChecking)
        }
    }

    /// Run style checks automatically while typing (when false, only manual shortcut triggers checks)
    @Published var autoStyleChecking: Bool {
        didSet {
            defaults.set(autoStyleChecking, forKey: Keys.autoStyleChecking)
        }
    }

    /// Always show the capsule indicator when style checking is enabled, even with no grammar errors
    /// This provides quick access to Style Check and AI Compose features
    @Published var alwaysShowCapsule: Bool {
        didSet {
            defaults.set(alwaysShowCapsule, forKey: Keys.alwaysShowCapsule)
        }
    }

    /// Selected writing style template
    @Published var selectedWritingStyle: String {
        didSet {
            defaults.set(selectedWritingStyle, forKey: Keys.selectedWritingStyle)
        }
    }

    /// Selected LLM model ID
    @Published var selectedModelId: String {
        didSet {
            defaults.set(selectedModelId, forKey: Keys.selectedModelId)
        }
    }

    /// Minimum sentence word count for style analysis (default: 5)
    @Published var styleMinSentenceWords: Int {
        didSet {
            defaults.set(styleMinSentenceWords, forKey: Keys.styleMinSentenceWords)
        }
    }

    /// Style suggestion confidence threshold (0.0 - 1.0, default: 0.7)
    @Published var styleConfidenceThreshold: Double {
        didSet {
            defaults.set(styleConfidenceThreshold, forKey: Keys.styleConfidenceThreshold)
        }
    }

    /// Auto-load model on app launch when style checking is enabled
    @Published var styleAutoLoadModel: Bool {
        didSet {
            defaults.set(styleAutoLoadModel, forKey: Keys.styleAutoLoadModel)
        }
    }

    /// Inference preset for speed vs quality tradeoff (Fast/Balanced/Quality)
    /// Note: This setting is hidden when using Foundation Models (FM has consistent quality)
    @Published var styleInferencePreset: String {
        didSet {
            defaults.set(styleInferencePreset, forKey: Keys.styleInferencePreset)
        }
    }

    /// Temperature preset for Foundation Models (controls creativity vs consistency)
    @Published var styleTemperaturePreset: String {
        didSet {
            defaults.set(styleTemperaturePreset, forKey: Keys.styleTemperaturePreset)
        }
    }

    /// Style suggestion sensitivity (controls how many suggestions are shown in auto-check)
    /// - minimal: Only high-impact suggestions
    /// - balanced: High and medium-impact suggestions (default)
    /// - detailed: All suggestions including low-impact
    @Published var styleSensitivity: String {
        didSet {
            defaults.set(styleSensitivity, forKey: Keys.styleSensitivity)
        }
    }

    /// Available writing style options
    static let writingStyles = [
        "Default",
        "Concise",
        "Formal",
        "Casual",
        "Business",
    ]

    private init() {
        // Initialize with default values first
        pauseDuration = .active
        pausedUntil = nil
        disabledApplications = []
        discoveredApplications = []
        appUnderlinesDisabled = []
        disabledWebsites = []
        appPauseDurations = [:]
        appPausedUntil = [:]
        customDictionary = []
        ignoredRules = []
        ignoredErrorTexts = []
        enabledCategories = UserPreferences.allCategories // All categories enabled by default
        openInForeground = false

        // Individual Rule Toggles (all enabled by default to match Harper defaults)
        enforceOxfordComma = true
        checkEllipsis = true
        checkUnclosedQuotes = true
        checkDashes = true

        // Language & Dialect
        selectedDialect = "American"
        enableInternetAbbreviations = true
        enableGenZSlang = true
        enableITTerminology = true
        enableBrandNames = true
        enablePersonNames = true
        enableLastNames = true
        enableMacOSDictionary = true // Uses NSSpellChecker API, no special permissions
        enableLanguageDetection = false // Opt-in feature
        excludedLanguages = []

        // Keyboard Shortcuts
        keyboardShortcutsEnabled = true

        // Suggestion Appearance
        suggestionOpacity = 0.80
        suggestionTextSize = 13.0
        suggestionPosition = "Auto"
        appTheme = "System"
        overlayTheme = "System"
        showUnderlines = true
        underlineThickness = 2.0
        maxErrorsForUnderlines = 10
        indicatorPosition = "Center Right"
        enableHoverPopover = true
        popoverHoverDelayMs = 0

        // Diagnostics
        showDebugBorderTextFieldBounds = false
        showDebugBorderCGWindowCoords = false
        showDebugBorderCocoaCoords = false
        showDebugCharacterMarkers = false

        // Milestones
        shownMilestones = []
        milestonesDisabled = false

        // LLM Style Checking
        enableStyleChecking = false // Off by default
        autoStyleChecking = false // Manual-only by default
        alwaysShowCapsule = false // Hide capsule when no errors by default
        selectedWritingStyle = "Default"
        selectedModelId = "qwen2.5-1.5b" // Balanced model
        styleMinSentenceWords = 5
        styleConfidenceThreshold = 0.7
        styleAutoLoadModel = true
        styleInferencePreset = "balanced" // Default to balanced
        styleTemperaturePreset = "balanced" // Default FM temperature
        styleSensitivity = "balanced" // Default style sensitivity

        // Then load saved preferences
        if let pauseString = defaults.string(forKey: Keys.pauseDuration),
           let pause = PauseDuration(rawValue: pauseString)
        {
            pauseDuration = pause
        }

        pausedUntil = defaults.object(forKey: Keys.pausedUntil) as? Date

        if let data = defaults.data(forKey: Keys.disabledApplications),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            disabledApplications = set
        }

        if let data = defaults.data(forKey: Keys.discoveredApplications),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            discoveredApplications = set
        }

        if let data = defaults.data(forKey: Keys.appUnderlinesDisabled),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            appUnderlinesDisabled = set
        }

        if let data = defaults.data(forKey: Keys.disabledWebsites),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            disabledWebsites = set
        }

        if let data = defaults.data(forKey: Keys.appPauseDurations),
           let dict = try? decoder.decode([String: PauseDuration].self, from: data)
        {
            appPauseDurations = dict
        }

        if let data = defaults.data(forKey: Keys.appPausedUntil),
           let dict = try? decoder.decode([String: Date].self, from: data)
        {
            appPausedUntil = dict
        }

        if let data = defaults.data(forKey: Keys.customDictionary),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            customDictionary = set
        }

        if let data = defaults.data(forKey: Keys.ignoredRules),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            ignoredRules = set
        }

        if let data = defaults.data(forKey: Keys.ignoredErrorTexts),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            ignoredErrorTexts = set
        }

        if let data = defaults.data(forKey: Keys.enabledCategories),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            enabledCategories = set
        }

        openInForeground = defaults.object(forKey: Keys.openInForeground) as? Bool ?? false
        hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false
        hasShownMenuBarTooltip = defaults.object(forKey: Keys.hasShownMenuBarTooltip) as? Bool ?? false

        // Individual Rule Toggles
        enforceOxfordComma = defaults.object(forKey: Keys.enforceOxfordComma) as? Bool ?? true
        checkEllipsis = defaults.object(forKey: Keys.checkEllipsis) as? Bool ?? true
        checkUnclosedQuotes = defaults.object(forKey: Keys.checkUnclosedQuotes) as? Bool ?? true
        checkDashes = defaults.object(forKey: Keys.checkDashes) as? Bool ?? true

        // Language & Dialect
        selectedDialect = defaults.string(forKey: Keys.selectedDialect) ?? "American"
        enableInternetAbbreviations = defaults.object(forKey: Keys.enableInternetAbbreviations) as? Bool ?? true
        enableGenZSlang = defaults.object(forKey: Keys.enableGenZSlang) as? Bool ?? true
        enableITTerminology = defaults.object(forKey: Keys.enableITTerminology) as? Bool ?? true
        enableBrandNames = defaults.object(forKey: Keys.enableBrandNames) as? Bool ?? true
        enablePersonNames = defaults.object(forKey: Keys.enablePersonNames) as? Bool ?? true
        enableLastNames = defaults.object(forKey: Keys.enableLastNames) as? Bool ?? true
        enableMacOSDictionary = defaults.object(forKey: Keys.enableMacOSDictionary) as? Bool ?? true
        enableLanguageDetection = defaults.object(forKey: Keys.enableLanguageDetection) as? Bool ?? false
        if let data = defaults.data(forKey: Keys.excludedLanguages),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            excludedLanguages = set
        }

        // Keyboard Shortcuts
        keyboardShortcutsEnabled = defaults.object(forKey: Keys.keyboardShortcutsEnabled) as? Bool ?? true

        // Suggestion Appearance
        suggestionOpacity = defaults.object(forKey: Keys.suggestionOpacity) as? Double ?? 0.80
        suggestionTextSize = defaults.object(forKey: Keys.suggestionTextSize) as? Double ?? 13.0
        suggestionPosition = defaults.string(forKey: Keys.suggestionPosition) ?? "Auto"
        appTheme = defaults.string(forKey: Keys.appTheme) ?? "System"
        // Migration: if overlayTheme not set, try old suggestionTheme key for backward compatibility
        if let savedOverlayTheme = defaults.string(forKey: Keys.overlayTheme) {
            overlayTheme = savedOverlayTheme
        } else if let oldTheme = defaults.string(forKey: "suggestionTheme") {
            // Migrate from old key name
            overlayTheme = oldTheme
            defaults.set(oldTheme, forKey: Keys.overlayTheme)
        } else {
            overlayTheme = "System"
        }
        showUnderlines = defaults.object(forKey: Keys.showUnderlines) as? Bool ?? true
        underlineThickness = defaults.object(forKey: Keys.underlineThickness) as? Double ?? 2.0
        maxErrorsForUnderlines = defaults.object(forKey: Keys.maxErrorsForUnderlines) as? Int ?? 10
        indicatorPosition = defaults.string(forKey: Keys.indicatorPosition) ?? "Center Right"
        enableHoverPopover = defaults.object(forKey: Keys.enableHoverPopover) as? Bool ?? true
        popoverHoverDelayMs = defaults.object(forKey: Keys.popoverHoverDelayMs) as? Int ?? 0

        // Diagnostics
        showDebugBorderTextFieldBounds = defaults.object(forKey: Keys.showDebugBorderTextFieldBounds) as? Bool ?? false
        showDebugBorderCGWindowCoords = defaults.object(forKey: Keys.showDebugBorderCGWindowCoords) as? Bool ?? false
        showDebugBorderCocoaCoords = defaults.object(forKey: Keys.showDebugBorderCocoaCoords) as? Bool ?? false
        showDebugCharacterMarkers = defaults.object(forKey: Keys.showDebugCharacterMarkers) as? Bool ?? false

        // Milestones
        if let data = defaults.data(forKey: Keys.shownMilestones),
           let set = try? decoder.decode(Set<String>.self, from: data)
        {
            shownMilestones = set
        }
        milestonesDisabled = defaults.object(forKey: Keys.milestonesDisabled) as? Bool ?? false

        // Readability - enabled by default
        // Migration: if user had either old setting enabled, keep readability enabled
        if let existingValue = defaults.object(forKey: Keys.readabilityEnabled) as? Bool {
            readabilityEnabled = existingValue
        } else {
            // Migrate from old settings: enabled if either old setting was enabled (or defaults to true)
            let oldShowScore = defaults.object(forKey: "showReadabilityScore") as? Bool ?? true
            let oldSentenceComplexity = defaults.object(forKey: "sentenceComplexityHighlightingEnabled") as? Bool ?? true
            let migratedValue = oldShowScore || oldSentenceComplexity
            readabilityEnabled = migratedValue
            // Persist the migrated value
            defaults.set(migratedValue, forKey: Keys.readabilityEnabled)
        }
        showReadabilityUnderlines = defaults.object(forKey: Keys.showReadabilityUnderlines) as? Bool ?? true
        selectedTargetAudience = defaults.string(forKey: Keys.selectedTargetAudience) ?? TargetAudience.general.displayName

        // LLM Style Checking
        enableStyleChecking = defaults.object(forKey: Keys.enableStyleChecking) as? Bool ?? false
        autoStyleChecking = defaults.object(forKey: Keys.autoStyleChecking) as? Bool ?? false
        alwaysShowCapsule = defaults.object(forKey: Keys.alwaysShowCapsule) as? Bool ?? false
        selectedWritingStyle = defaults.string(forKey: Keys.selectedWritingStyle) ?? "Default"
        selectedModelId = defaults.string(forKey: Keys.selectedModelId) ?? "qwen2.5-1.5b"
        styleMinSentenceWords = defaults.object(forKey: Keys.styleMinSentenceWords) as? Int ?? 5
        styleConfidenceThreshold = defaults.object(forKey: Keys.styleConfidenceThreshold) as? Double ?? 0.7
        styleAutoLoadModel = defaults.object(forKey: Keys.styleAutoLoadModel) as? Bool ?? true
        styleInferencePreset = defaults.string(forKey: Keys.styleInferencePreset) ?? "balanced"
        styleTemperaturePreset = defaults.string(forKey: Keys.styleTemperaturePreset) ?? "balanced"
        styleSensitivity = defaults.string(forKey: Keys.styleSensitivity) ?? "balanced"

        // This prevents grammar checking in terminals where command output can cause false positives
        // Users can still enable terminals individually via Applications preferences
        for terminalID in Self.terminalApplications {
            if appPauseDurations[terminalID] == nil {
                appPauseDurations[terminalID] = .indefinite
            }
        }
        // Note: Other unsupported apps are auto-paused via ApplicationTracker and ApplicationSettingsView
        // when they're first discovered (whitelist approach)

        if pauseDuration == .oneHour, let until = pausedUntil, Date() < until {
            setupResumeTimer(until: until)
        }

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupExpiredAppPauses()
            }
        }
    }

    deinit {
        resumeTimer?.invalidate()
        cleanupTimer?.invalidate()
    }

    /// Handle pause duration changes
    private func handlePauseChange() {
        // Cancel existing timer
        resumeTimer?.invalidate()
        resumeTimer = nil

        switch pauseDuration {
        case .active:
            // Clear pausedUntil
            pausedUntil = nil

        case .oneHour:
            let until = Date().addingTimeInterval(3600) // 1 hour
            pausedUntil = until
            setupResumeTimer(until: until)

        case .twentyFourHours:
            let until = Date().addingTimeInterval(86400) // 24 hours
            pausedUntil = until
            setupResumeTimer(until: until)

        case .indefinite:
            // Keep pausedUntil nil
            pausedUntil = nil
        }

        DispatchQueue.main.async {
            MenuBarController.shared?.updateMenu()
        }

        // Notify observers that isEnabled may have changed
        objectWillChange.send()
    }

    /// Set up a timer to auto-resume after the pause expires
    private func setupResumeTimer(until: Date) {
        let timeInterval = until.timeIntervalSinceNow
        guard timeInterval > 0 else {
            // Already expired - resume immediately
            DispatchQueue.main.async { [weak self] in
                self?.pauseDuration = .active
                self?.pausedUntil = nil
            }
            return
        }

        resumeTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pauseDuration = .active
                self?.pausedUntil = nil
            }
        }
    }

    /// Periodically checks for and removes expired app-specific pause durations.
    /// Called automatically by a timer every 60 seconds. Updates menu bar if any changes are made.
    private func cleanupExpiredAppPauses() {
        var needsUpdate = false

        for (bundleID, duration) in appPauseDurations {
            if duration == .oneHour || duration == .twentyFourHours {
                if let until = appPausedUntil[bundleID], Date() >= until {
                    appPauseDurations.removeValue(forKey: bundleID)
                    appPausedUntil.removeValue(forKey: bundleID)
                    needsUpdate = true
                }
            }
        }

        if needsUpdate {
            DispatchQueue.main.async {
                MenuBarController.shared?.updateMenu()
            }
        }
    }

    /// Checks if a timed app-specific pause has expired.
    /// This is a pure function with no side effects - cleanup is handled separately by the timer.
    /// - Parameter bundleIdentifier: The bundle identifier of the application
    /// - Returns: `true` if the pause has expired or doesn't exist, `false` if still active
    private func isAppPauseExpired(for bundleIdentifier: String) -> Bool {
        guard let duration = appPauseDurations[bundleIdentifier] else { return false }
        guard duration == .oneHour || duration == .twentyFourHours else { return false }
        guard let until = appPausedUntil[bundleIdentifier] else { return true }
        return Date() >= until
    }

    /// Check if grammar checking is enabled for a specific application
    func isEnabled(for bundleIdentifier: String) -> Bool {
        // Never check grammar in TextWarden's own UI
        if bundleIdentifier == "io.textwarden.TextWarden" {
            return false
        }

        // First check global pause state
        guard isEnabled else { return false }

        // Check if app is permanently disabled
        if disabledApplications.contains(bundleIdentifier) {
            return false
        }

        // Check app-specific pause
        guard let appPause = appPauseDurations[bundleIdentifier] else {
            return true // No app-specific pause set
        }

        switch appPause {
        case .active:
            return true
        case .oneHour, .twentyFourHours:
            // Check if pause has expired (no mutation - cleanup happens via timer)
            // If expired, grammar checking is enabled; otherwise disabled
            return isAppPauseExpired(for: bundleIdentifier)
        case .indefinite:
            return false
        }
    }

    /// Check if underlines are enabled for a specific application
    /// Returns true if underlines should be shown (not in the disabled set)
    func areUnderlinesEnabled(for bundleIdentifier: String) -> Bool {
        !appUnderlinesDisabled.contains(bundleIdentifier)
    }

    /// Set whether underlines are enabled for a specific application
    func setUnderlinesEnabled(_ enabled: Bool, for bundleIdentifier: String) {
        if enabled {
            appUnderlinesDisabled.remove(bundleIdentifier)
        } else {
            appUnderlinesDisabled.insert(bundleIdentifier)
        }
    }

    // MARK: - Website Management

    /// Check if grammar checking is enabled for a specific URL
    /// Returns false if the URL's domain is in the disabled websites list
    func isEnabled(forURL url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }

        for domain in disabledWebsites {
            let pattern = domain.lowercased()

            if pattern.hasPrefix("*.") {
                // Wildcard pattern: *.example.com matches sub.example.com and example.com
                let baseDomain = String(pattern.dropFirst(2))
                if host == baseDomain || host.hasSuffix(".\(baseDomain)") {
                    return false
                }
            } else {
                // Exact match
                if host == pattern {
                    return false
                }
            }
        }

        return true
    }

    /// Add a website to the disabled list
    /// - Parameter domain: Domain to disable (e.g., "github.com" or "*.google.com")
    func disableWebsite(_ domain: String) {
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDomain.isEmpty else { return }
        disabledWebsites.insert(normalizedDomain)
    }

    /// Remove a website from the disabled list
    func enableWebsite(_ domain: String) {
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        disabledWebsites.remove(normalizedDomain)
    }

    /// Check if a specific domain is disabled
    func isWebsiteDisabled(_ domain: String) -> Bool {
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return disabledWebsites.contains(normalizedDomain)
    }

    /// Add a word to the custom dictionary
    func addToCustomDictionary(_ word: String) {
        guard customDictionary.count < 1000 else {
            Logger.warning("Custom dictionary limit reached (1000 words)", category: Logger.general)
            return
        }
        customDictionary.insert(word.lowercased())
    }

    /// Remove a word from the custom dictionary
    func removeFromCustomDictionary(_ word: String) {
        customDictionary.remove(word.lowercased())
    }

    /// Ignore a grammar rule permanently
    func ignoreRule(_ ruleId: String) {
        ignoredRules.insert(ruleId)
    }

    /// Re-enable a previously ignored rule
    func enableRule(_ ruleId: String) {
        ignoredRules.remove(ruleId)
    }

    /// Ignore a specific error text globally
    func ignoreErrorText(_ text: String) {
        guard ignoredErrorTexts.count < 1000 else {
            Logger.warning("Ignored error texts limit reached (1000 entries)", category: Logger.general)
            return
        }
        ignoredErrorTexts.insert(text)
    }

    /// Remove an error text from the ignored list
    func unignoreErrorText(_ text: String) {
        ignoredErrorTexts.remove(text)
    }

    /// Check if an error text is ignored
    func isErrorTextIgnored(_ text: String) -> Bool {
        ignoredErrorTexts.contains(text)
    }

    // MARK: - App-Specific Pause Management

    /// Sets the pause duration for a specific application.
    /// - Parameters:
    ///   - bundleIdentifier: The bundle identifier of the application
    ///   - duration: The pause duration to set (.active, .oneHour, .twentyFourHours, or .indefinite)
    /// - Note: Automatically updates the menu bar and notifies observers of the change
    func setPauseDuration(for bundleIdentifier: String, duration: PauseDuration) {
        switch duration {
        case .active:
            // Always store .active explicitly to prevent re-pausing by auto-pause logic
            // (terminals are paused on init, unsupported apps are paused on discovery)
            appPauseDurations[bundleIdentifier] = duration
            appPausedUntil.removeValue(forKey: bundleIdentifier)

        case .oneHour:
            let until = Date().addingTimeInterval(3600)
            appPauseDurations[bundleIdentifier] = duration
            appPausedUntil[bundleIdentifier] = until

        case .twentyFourHours:
            let until = Date().addingTimeInterval(86400)
            appPauseDurations[bundleIdentifier] = duration
            appPausedUntil[bundleIdentifier] = until

        case .indefinite:
            appPauseDurations[bundleIdentifier] = duration
            appPausedUntil.removeValue(forKey: bundleIdentifier)
        }

        DispatchQueue.main.async {
            MenuBarController.shared?.updateMenu()
        }

        // Notify observers
        objectWillChange.send()
    }

    /// Gets the current pause duration for a specific application.
    /// - Parameter bundleIdentifier: The bundle identifier of the application
    /// - Returns: The current pause duration, or `.active` if no pause is set or if a timed pause has expired
    /// - Note: This is a read-only query - expired pauses are cleaned up automatically by a background timer
    func getPauseDuration(for bundleIdentifier: String) -> PauseDuration {
        guard let duration = appPauseDurations[bundleIdentifier] else {
            return .active
        }

        // Check if timed pause has expired (no mutation - cleanup happens via timer)
        if isAppPauseExpired(for: bundleIdentifier) {
            return .active
        }

        return duration
    }

    /// Gets the expiry date for a timed app-specific pause.
    /// - Parameter bundleIdentifier: The bundle identifier of the application
    /// - Returns: The date when the pause will expire, or `nil` if no timed pause is set
    func getPausedUntil(for bundleIdentifier: String) -> Date? {
        appPausedUntil[bundleIdentifier]
    }

    /// Reset all preferences to defaults
    func resetToDefaults() {
        hasCompletedOnboarding = false
        hasShownMenuBarTooltip = false
        pauseDuration = .active
        pausedUntil = nil
        disabledApplications = []
        // Note: We intentionally don't reset discoveredApplications
        // as it's useful to remember which apps have been used
        customDictionary = []
        ignoredRules = []
        enabledCategories = UserPreferences.allCategories
        enforceOxfordComma = true
        checkEllipsis = true
        checkUnclosedQuotes = true
        checkDashes = true
        selectedDialect = "American"
        enableInternetAbbreviations = true
        enableGenZSlang = true
        enableITTerminology = true
        enableBrandNames = true
        enablePersonNames = true
        enableLastNames = true
        enableMacOSDictionary = true
        keyboardShortcutsEnabled = true
        suggestionOpacity = 0.80
        suggestionTextSize = 13.0
        suggestionPosition = "Auto"
        appTheme = "System"
        overlayTheme = "System"
        showUnderlines = true
        underlineThickness = 2.0
        maxErrorsForUnderlines = 10
        indicatorPosition = "Center Right"
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let pauseDuration = "pauseDuration"
        static let pausedUntil = "pausedUntil"
        static let disabledApplications = "disabledApplications"
        static let discoveredApplications = "discoveredApplications"
        static let appUnderlinesDisabled = "appUnderlinesDisabled"
        static let disabledWebsites = "disabledWebsites"
        static let appPauseDurations = "appPauseDurations"
        static let appPausedUntil = "appPausedUntil"
        static let customDictionary = "customDictionary"
        static let ignoredRules = "ignoredRules"
        static let ignoredErrorTexts = "ignoredErrorTexts"
        static let enabledCategories = "enabledCategories"
        static let openInForeground = "openInForeground"

        // Individual Rule Toggles
        static let enforceOxfordComma = "enforceOxfordComma"
        static let checkEllipsis = "checkEllipsis"
        static let checkUnclosedQuotes = "checkUnclosedQuotes"
        static let checkDashes = "checkDashes"

        // Language & Dialect
        static let selectedDialect = "selectedDialect"
        static let enableInternetAbbreviations = "enableInternetAbbreviations"
        static let enableGenZSlang = "enableGenZSlang"
        static let enableITTerminology = "enableITTerminology"
        static let enableBrandNames = "enableBrandNames"
        static let enablePersonNames = "enablePersonNames"
        static let enableLastNames = "enableLastNames"
        static let enableMacOSDictionary = "enableMacOSDictionary"
        static let enableLanguageDetection = "enableLanguageDetection"
        static let excludedLanguages = "excludedLanguages"

        // Keyboard Shortcuts
        static let keyboardShortcutsEnabled = "keyboardShortcutsEnabled"

        // Suggestion Appearance
        static let suggestionOpacity = "suggestionOpacity"
        static let suggestionTextSize = "suggestionTextSize"
        static let suggestionPosition = "suggestionPosition"
        static let appTheme = "appTheme"
        static let overlayTheme = "overlayTheme"
        static let showUnderlines = "showUnderlines"
        static let underlineThickness = "underlineThickness"
        static let maxErrorsForUnderlines = "maxErrorsForUnderlines"
        static let indicatorPosition = "indicatorPosition"
        static let enableHoverPopover = "enableHoverPopover"
        static let popoverHoverDelayMs = "popoverHoverDelayMs"

        // Diagnostics
        static let showDebugBorderTextFieldBounds = "showDebugBorderTextFieldBounds"
        static let showDebugBorderCGWindowCoords = "showDebugBorderCGWindowCoords"
        static let showDebugBorderCocoaCoords = "showDebugBorderCocoaCoords"
        static let showDebugCharacterMarkers = "showDebugCharacterMarkers"

        // Onboarding
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasShownMenuBarTooltip = "hasShownMenuBarTooltip"

        // Milestones
        static let shownMilestones = "shownMilestones"
        static let milestonesDisabled = "milestonesDisabled"

        // Readability
        static let readabilityEnabled = "readabilityEnabled"
        static let showReadabilityUnderlines = "showReadabilityUnderlines"
        static let selectedTargetAudience = "selectedTargetAudience"

        // LLM Style Checking
        static let enableStyleChecking = "enableStyleChecking"
        static let autoStyleChecking = "autoStyleChecking"
        static let alwaysShowCapsule = "alwaysShowCapsule"
        static let selectedWritingStyle = "selectedWritingStyle"
        static let selectedModelId = "selectedModelId"
        static let styleMinSentenceWords = "styleMinSentenceWords"
        static let styleConfidenceThreshold = "styleConfidenceThreshold"
        static let styleAutoLoadModel = "styleAutoLoadModel"
        static let styleInferencePreset = "styleInferencePreset"
        static let styleTemperaturePreset = "styleTemperaturePreset"
        static let styleSensitivity = "styleSensitivity"
    }
}
