//
//  UserPreferences.swift
//  TextWarden
//
//  User preferences with UserDefaults persistence
//

import Foundation
import Combine

/// Pause duration options for grammar checking
enum PauseDuration: String, CaseIterable, Codable {
    case active = "Active"
    case oneHour = "Paused for 1 Hour"
    case twentyFourHours = "Paused for 24 Hours"
    case indefinite = "Paused Until Resumed"
}

/// Observable user preferences with automatic persistence
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var resumeTimer: Timer?
    private var cleanupTimer: Timer?

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
                    DispatchQueue.main.async {
                        self.pauseDuration = .active
                        self.pausedUntil = nil
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
            if let encoded = try? encoder.encode(disabledApplications) {
                defaults.set(encoded, forKey: Keys.disabledApplications)
            }
        }
    }

    /// Per-application pause durations
    @Published var appPauseDurations: [String: PauseDuration] {
        didSet {
            if let encoded = try? encoder.encode(appPauseDurations) {
                defaults.set(encoded, forKey: Keys.appPauseDurations)
            }
        }
    }

    /// Per-application pause expiry dates (for timed pauses)
    @Published var appPausedUntil: [String: Date] {
        didSet {
            if let encoded = try? encoder.encode(appPausedUntil) {
                defaults.set(encoded, forKey: Keys.appPausedUntil)
            }
        }
    }

    /// Discovered applications (apps that have been activated while TextWarden is running)
    @Published var discoveredApplications: Set<String> {
        didSet {
            if let encoded = try? encoder.encode(discoveredApplications) {
                defaults.set(encoded, forKey: Keys.discoveredApplications)
            }
        }
    }

    /// Hidden applications (apps that user has hidden from the discovered list)
    @Published var hiddenApplications: Set<String> {
        didSet {
            if let encoded = try? encoder.encode(hiddenApplications) {
                defaults.set(encoded, forKey: Keys.hiddenApplications)
            }
        }
    }

    /// Disabled websites (domains where grammar checking is disabled)
    /// Supports exact matches (e.g., "github.com") and wildcard patterns (e.g., "*.google.com")
    @Published var disabledWebsites: Set<String> {
        didSet {
            if let encoded = try? encoder.encode(disabledWebsites) {
                defaults.set(encoded, forKey: Keys.disabledWebsites)
            }
        }
    }

    /// Default hidden applications (system utilities and apps where grammar checking doesn't make sense)
    ///
    /// **Easy Configuration Guide:**
    /// To add your own apps to this list, simply add the bundle identifier as a new string in the set below.
    /// To find an app's bundle ID:
    /// 1. Right-click the app in Finder > Show Package Contents
    /// 2. Open Info.plist and look for CFBundleIdentifier
    /// OR run: `mdls -name kMDItemCFBundleIdentifier /path/to/App.app`
    ///
    /// Example: "com.yourcompany.YourApp"
    static let defaultHiddenApplications: Set<String> = [
        // TextWarden itself
        "com.philipschmid.TextWarden",  // TextWarden
        // System services and background apps
        "com.apple.loginwindow",  // Login Window
        "com.apple.UserNotificationCenter",  // Notification Center
        "com.apple.notificationcenterui",  // Notification Center UI
        "com.apple.accessibility.universalAccessAuthWarn",  // Accessibility Warning
        "com.apple.controlcenter",  // Control Center
        "com.apple.systemuiserver",  // System UI Server
        "com.apple.QuickLookUIService",  // Quick Look UI Service
        "com.apple.appkit.xpc.openAndSavePanelService",  // Open/Save Panel Service
        "com.apple.CloudKit.ShareBear",  // CloudKit Share Service
        "com.apple.bird",  // iCloud Sync Daemon
        "com.apple.CommCenter",  // Communication Center
        "com.apple.cloudphotosd",  // iCloud Photos Daemon
        "com.apple.iCloudHelper",  // iCloud Helper
        "com.apple.InputMethodKit.TextReplacementService",  // Text Replacement Service
        "com.apple.Console",  // Console
        "com.apple.dock",  // Dock
        "com.apple.systempreferences",  // System Preferences
        // System utilities
        "com.apple.finder",  // Finder
        "com.apple.archiveutility",  // Archive Utility
        "com.apple.universalcontrol",  // Universal Control
        // Utility apps
        "com.TechSmith.Snagit",  // Snagit
        "com.TechSmith.SnagitHelper",  // Snagit Helper
        "com.techsmith.snagit.capturehelper",  // Snagit Capture Helper
        "com.surteesstudios.Bartender",  // Bartender
        "com.1password.1password",  // 1Password
        "com.linebreak.CloudApp",  // CloudApp
        "com.particlebacker.FastFace",  // Meeter (legacy bundle ID)
        "com.patricebecker.FastFace",  // Meeter
        "com.raycast.macos",  // Raycast
        "com.spotify.client",  // Spotify
        // Security software (Intego)
        "com.intego.NetUpdate",  // Intego NetUpdate
        "com.intego.app.netbarrier",  // Intego NetBarrier
        "com.intego.netbarrier.alert",  // Intego NetBarrier Alert
        "com.intego.virusbarrier.application",  // Intego VirusBarrier
        "com.intego.virusbarrier.alert",  // Intego VirusBarrier Alert
        "com.apple.Photos",            // Apple Photos
        "com.apple.Preview",           // Apple Preview
        "com.apple.ProblemReporter",   // Apple Problem Reporter
        "com.prakashjoshipax.VoiceInk", // VoiceInk
        "com.apple.keychainaccess",    // Keychain Access
        "com.apple.Passwords",         // Passwords
        "com.apple.Music",             // Apple Music
        // Hardware device managers
        "com.logi.cp-dev-mgr"          // Logitech Device Manager
    ]

    /// Custom words to ignore
    @Published var customDictionary: Set<String> {
        didSet {
            if let encoded = try? encoder.encode(customDictionary) {
                defaults.set(encoded, forKey: Keys.customDictionary)
            }
        }
    }

    /// Permanently ignored grammar rules
    @Published var ignoredRules: Set<String> {
        didSet {
            if let encoded = try? encoder.encode(ignoredRules) {
                defaults.set(encoded, forKey: Keys.ignoredRules)
            }
        }
    }

    /// Globally ignored error texts (for "Ignore Everywhere")
    /// Stores error texts that should be ignored across all documents
    @Published var ignoredErrorTexts: Set<String> {
        didSet {
            if let encoded = try? encoder.encode(ignoredErrorTexts) {
                defaults.set(encoded, forKey: Keys.ignoredErrorTexts)
            }
        }
    }

    /// Analysis delay in milliseconds (for performance tuning)
    @Published var analysisDelayMs: Int {
        didSet {
            defaults.set(analysisDelayMs, forKey: Keys.analysisDelayMs)
        }
    }

    /// Enabled grammar check categories (e.g., "Spelling", "Grammar", "Style")
    @Published var enabledCategories: Set<String> {
        didSet {
            if let encoded = try? encoder.encode(enabledCategories) {
                defaults.set(encoded, forKey: Keys.enabledCategories)
            }
        }
    }

    /// All available grammar check categories from Harper
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
        "Readability",
        "Redundancy",
        "Regionalism",
        "Repetition",
        "Spelling",
        "Style",
        "Typo",
        "Usage",
        "WordChoice"
    ]

    /// Terminal applications disabled by default (users can enable them in Applications preferences)
    /// These apps are set to .indefinite pause on first run to avoid false positives from command output
    static let terminalApplications: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm"
    ]

    /// Applications paused by default (users can enable them in Applications preferences)
    /// These apps are set to .indefinite pause on first run because grammar checking is typically not useful
    static let defaultPausedApplications: Set<String> = [
        "com.apple.iCal"  // Apple Calendar
    ]

    /// Always open settings window in foreground on launch
    @Published var openInForeground: Bool {
        didSet {
            defaults.set(openInForeground, forKey: Keys.openInForeground)
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
        "Australian"
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
            if let encoded = try? encoder.encode(excludedLanguages) {
                defaults.set(encoded, forKey: Keys.excludedLanguages)
            }
        }
    }

    // MARK: - TextWarden Enhancements

    /// Enable sentence-start capitalization (TextWarden enhancement to Harper's suggestions)
    /// When enabled, ensures suggestions at sentence starts are properly capitalized
    @Published var enableSentenceStartCapitalization: Bool {
        didSet {
            defaults.set(enableSentenceStartCapitalization, forKey: Keys.enableSentenceStartCapitalization)
        }
    }

    /// Available languages for detection (from whichlang library)
    static let availableLanguages = [
        "Arabic", "Dutch", "English", "French", "German",
        "Hindi", "Italian", "Japanese", "Korean", "Mandarin",
        "Portuguese", "Russian", "Spanish", "Swedish",
        "Turkish", "Vietnamese"
    ]

    /// Map UI-friendly names to language codes for Rust
    static func languageCode(for name: String) -> String {
        switch name {
        case "Arabic": return "arabic"
        case "Dutch": return "dutch"
        case "English": return "english"
        case "French": return "french"
        case "German": return "german"
        case "Hindi": return "hindi"
        case "Italian": return "italian"
        case "Japanese": return "japanese"
        case "Korean": return "korean"
        case "Mandarin": return "mandarin"
        case "Portuguese": return "portuguese"
        case "Russian": return "russian"
        case "Spanish": return "spanish"
        case "Swedish": return "swedish"
        case "Turkish": return "turkish"
        case "Vietnamese": return "vietnamese"
        default: return name.lowercased()
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
        "Below"
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
        "Dark"
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
        "Bottom Right"
    ]

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

    // MARK: - LLM Style Checking

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
    @Published var styleInferencePreset: String {
        didSet {
            defaults.set(styleInferencePreset, forKey: Keys.styleInferencePreset)
        }
    }

    /// Available writing style options
    static let writingStyles = [
        "Default",
        "Concise",
        "Formal",
        "Casual",
        "Business"
    ]

    private init() {
        // Initialize with default values first
        self.pauseDuration = .active
        self.pausedUntil = nil
        self.disabledApplications = []
        self.discoveredApplications = []
        self.hiddenApplications = UserPreferences.defaultHiddenApplications
        self.disabledWebsites = []
        self.appPauseDurations = [:]
        self.appPausedUntil = [:]
        self.customDictionary = []
        self.ignoredRules = []
        self.ignoredErrorTexts = []
        self.analysisDelayMs = 20
        self.enabledCategories = UserPreferences.allCategories // All categories enabled by default
        self.openInForeground = false

        // Language & Dialect
        self.selectedDialect = "American"
        self.enableInternetAbbreviations = true
        self.enableGenZSlang = true
        self.enableITTerminology = true
        self.enableLanguageDetection = false  // Opt-in feature
        self.excludedLanguages = []

        // Keyboard Shortcuts
        self.keyboardShortcutsEnabled = true

        // Suggestion Appearance
        self.suggestionOpacity = 0.80
        self.suggestionTextSize = 13.0
        self.suggestionPosition = "Auto"
        self.appTheme = "System"
        self.overlayTheme = "System"
        self.showUnderlines = true
        self.underlineThickness = 3.0
        self.indicatorPosition = "Bottom Right"

        // Diagnostics
        self.showDebugBorderTextFieldBounds = true
        self.showDebugBorderCGWindowCoords = true
        self.showDebugBorderCocoaCoords = true

        // LLM Style Checking
        self.enableStyleChecking = false  // Off by default
        self.autoStyleChecking = false    // Manual-only by default
        self.selectedWritingStyle = "Default"
        self.selectedModelId = "qwen2.5-1.5b"  // Balanced model
        self.styleMinSentenceWords = 5
        self.styleConfidenceThreshold = 0.7
        self.styleAutoLoadModel = true
        self.styleInferencePreset = "balanced"  // Default to balanced

        // Then load saved preferences
        if let pauseString = defaults.string(forKey: Keys.pauseDuration),
           let pause = PauseDuration(rawValue: pauseString) {
            self.pauseDuration = pause
        }

        self.pausedUntil = defaults.object(forKey: Keys.pausedUntil) as? Date

        if let data = defaults.data(forKey: Keys.disabledApplications),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.disabledApplications = set
        }

        if let data = defaults.data(forKey: Keys.discoveredApplications),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.discoveredApplications = set
        }

        if let data = defaults.data(forKey: Keys.hiddenApplications),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.hiddenApplications = set
        }

        if let data = defaults.data(forKey: Keys.disabledWebsites),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.disabledWebsites = set
        }

        if let data = defaults.data(forKey: Keys.appPauseDurations),
           let dict = try? decoder.decode([String: PauseDuration].self, from: data) {
            self.appPauseDurations = dict
        }

        if let data = defaults.data(forKey: Keys.appPausedUntil),
           let dict = try? decoder.decode([String: Date].self, from: data) {
            self.appPausedUntil = dict
        }

        if let data = defaults.data(forKey: Keys.customDictionary),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.customDictionary = set
        }

        if let data = defaults.data(forKey: Keys.ignoredRules),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.ignoredRules = set
        }

        if let data = defaults.data(forKey: Keys.ignoredErrorTexts),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.ignoredErrorTexts = set
        }

        self.analysisDelayMs = defaults.object(forKey: Keys.analysisDelayMs) as? Int ?? 20

        if let data = defaults.data(forKey: Keys.enabledCategories),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.enabledCategories = set
        }

        self.openInForeground = defaults.object(forKey: Keys.openInForeground) as? Bool ?? false

        // Language & Dialect
        self.selectedDialect = defaults.string(forKey: Keys.selectedDialect) ?? "American"
        self.enableInternetAbbreviations = defaults.object(forKey: Keys.enableInternetAbbreviations) as? Bool ?? true
        self.enableGenZSlang = defaults.object(forKey: Keys.enableGenZSlang) as? Bool ?? true
        self.enableITTerminology = defaults.object(forKey: Keys.enableITTerminology) as? Bool ?? true
        self.enableLanguageDetection = defaults.object(forKey: Keys.enableLanguageDetection) as? Bool ?? false
        if let data = defaults.data(forKey: Keys.excludedLanguages),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.excludedLanguages = set
        }

        // TextWarden Enhancements
        self.enableSentenceStartCapitalization = defaults.object(forKey: Keys.enableSentenceStartCapitalization) as? Bool ?? true

        // Keyboard Shortcuts
        self.keyboardShortcutsEnabled = defaults.object(forKey: Keys.keyboardShortcutsEnabled) as? Bool ?? true

        // Suggestion Appearance
        self.suggestionOpacity = defaults.object(forKey: Keys.suggestionOpacity) as? Double ?? 0.80
        self.suggestionTextSize = defaults.object(forKey: Keys.suggestionTextSize) as? Double ?? 13.0
        self.suggestionPosition = defaults.string(forKey: Keys.suggestionPosition) ?? "Auto"
        self.appTheme = defaults.string(forKey: Keys.appTheme) ?? "System"
        // Migration: if overlayTheme not set, try old suggestionTheme key for backward compatibility
        if let savedOverlayTheme = defaults.string(forKey: Keys.overlayTheme) {
            self.overlayTheme = savedOverlayTheme
        } else if let oldTheme = defaults.string(forKey: "suggestionTheme") {
            // Migrate from old key name
            self.overlayTheme = oldTheme
            defaults.set(oldTheme, forKey: Keys.overlayTheme)
        } else {
            self.overlayTheme = "System"
        }
        self.showUnderlines = defaults.object(forKey: Keys.showUnderlines) as? Bool ?? true
        self.underlineThickness = defaults.object(forKey: Keys.underlineThickness) as? Double ?? 3.0
        self.indicatorPosition = defaults.string(forKey: Keys.indicatorPosition) ?? "Bottom Right"

        // Diagnostics
        self.showDebugBorderTextFieldBounds = defaults.object(forKey: Keys.showDebugBorderTextFieldBounds) as? Bool ?? true
        self.showDebugBorderCGWindowCoords = defaults.object(forKey: Keys.showDebugBorderCGWindowCoords) as? Bool ?? true
        self.showDebugBorderCocoaCoords = defaults.object(forKey: Keys.showDebugBorderCocoaCoords) as? Bool ?? true

        // LLM Style Checking
        self.enableStyleChecking = defaults.object(forKey: Keys.enableStyleChecking) as? Bool ?? false
        self.autoStyleChecking = defaults.object(forKey: Keys.autoStyleChecking) as? Bool ?? false
        self.selectedWritingStyle = defaults.string(forKey: Keys.selectedWritingStyle) ?? "Default"
        self.selectedModelId = defaults.string(forKey: Keys.selectedModelId) ?? "qwen2.5-1.5b"
        self.styleMinSentenceWords = defaults.object(forKey: Keys.styleMinSentenceWords) as? Int ?? 5
        self.styleConfidenceThreshold = defaults.object(forKey: Keys.styleConfidenceThreshold) as? Double ?? 0.7
        self.styleAutoLoadModel = defaults.object(forKey: Keys.styleAutoLoadModel) as? Bool ?? true
        self.styleInferencePreset = defaults.string(forKey: Keys.styleInferencePreset) ?? "balanced"

        // This prevents grammar checking in terminals where command output can cause false positives
        // Users can still enable terminals individually via Applications preferences
        for terminalID in Self.terminalApplications {
            if appPauseDurations[terminalID] == nil {
                appPauseDurations[terminalID] = .indefinite
            }
        }

        // Pause default applications where grammar checking is typically not useful
        // Users can still enable these individually via Applications preferences
        for appID in Self.defaultPausedApplications {
            if appPauseDurations[appID] == nil {
                appPauseDurations[appID] = .indefinite
            }
        }

        // Migrate apps from discovered to hidden if they're in defaultHiddenApplications
        // This ensures apps added to defaultHiddenApplications are automatically hidden
        let appsToHide = discoveredApplications.intersection(Self.defaultHiddenApplications)
        if !appsToHide.isEmpty {
            discoveredApplications.subtract(appsToHide)
            hiddenApplications.formUnion(appsToHide)
        }

        if pauseDuration == .oneHour, let until = pausedUntil, Date() < until {
            setupResumeTimer(until: until)
        }

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanupExpiredAppPauses()
        }
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
            DispatchQueue.main.async {
                self.pauseDuration = .active
                self.pausedUntil = nil
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
        if bundleIdentifier == "com.philipschmid.TextWarden" {
            return false
        }

        // First check global pause state
        guard isEnabled else { return false }

        // Check if app is permanently disabled
        if disabledApplications.contains(bundleIdentifier) {
            return false
        }

        // Check if app is hidden (hidden apps should not be checked)
        // Hiding an app from the list implies the user doesn't want TextWarden interaction
        if hiddenApplications.contains(bundleIdentifier) {
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
        return ignoredErrorTexts.contains(text)
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
            appPauseDurations.removeValue(forKey: bundleIdentifier)
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
        return appPausedUntil[bundleIdentifier]
    }

    /// Reset all preferences to defaults
    func resetToDefaults() {
        pauseDuration = .active
        pausedUntil = nil
        disabledApplications = []
        // Note: We intentionally don't reset discoveredApplications
        // as it's useful to remember which apps have been used
        customDictionary = []
        ignoredRules = []
        analysisDelayMs = 20
        enabledCategories = UserPreferences.allCategories
        selectedDialect = "American"
        enableInternetAbbreviations = true
        enableGenZSlang = true
        enableITTerminology = true
        enableSentenceStartCapitalization = true
        keyboardShortcutsEnabled = true
        suggestionOpacity = 0.80
        suggestionTextSize = 13.0
        suggestionPosition = "Auto"
        appTheme = "System"
        overlayTheme = "System"
        showUnderlines = true
        underlineThickness = 3.0
        indicatorPosition = "Bottom Right"
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let pauseDuration = "pauseDuration"
        static let pausedUntil = "pausedUntil"
        static let disabledApplications = "disabledApplications"
        static let discoveredApplications = "discoveredApplications"
        static let hiddenApplications = "hiddenApplications"
        static let disabledWebsites = "disabledWebsites"
        static let appPauseDurations = "appPauseDurations"
        static let appPausedUntil = "appPausedUntil"
        static let customDictionary = "customDictionary"
        static let ignoredRules = "ignoredRules"
        static let ignoredErrorTexts = "ignoredErrorTexts"
        static let analysisDelayMs = "analysisDelayMs"
        static let enabledCategories = "enabledCategories"
        static let openInForeground = "openInForeground"

        // Language & Dialect
        static let selectedDialect = "selectedDialect"
        static let enableInternetAbbreviations = "enableInternetAbbreviations"
        static let enableGenZSlang = "enableGenZSlang"
        static let enableITTerminology = "enableITTerminology"
        static let enableLanguageDetection = "enableLanguageDetection"
        static let excludedLanguages = "excludedLanguages"

        // TextWarden Enhancements
        static let enableSentenceStartCapitalization = "enableSentenceStartCapitalization"

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
        static let indicatorPosition = "indicatorPosition"

        // Diagnostics
        static let showDebugBorderTextFieldBounds = "showDebugBorderTextFieldBounds"
        static let showDebugBorderCGWindowCoords = "showDebugBorderCGWindowCoords"
        static let showDebugBorderCocoaCoords = "showDebugBorderCocoaCoords"

        // LLM Style Checking
        static let enableStyleChecking = "enableStyleChecking"
        static let autoStyleChecking = "autoStyleChecking"
        static let selectedWritingStyle = "selectedWritingStyle"
        static let selectedModelId = "selectedModelId"
        static let styleMinSentenceWords = "styleMinSentenceWords"
        static let styleConfidenceThreshold = "styleConfidenceThreshold"
        static let styleAutoLoadModel = "styleAutoLoadModel"
        static let styleInferencePreset = "styleInferencePreset"
    }
}
