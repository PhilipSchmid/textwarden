//
//  UserPreferences.swift
//  Gnau
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

    /// Discovered applications (apps that have been activated while Gnau is running)
    @Published var discoveredApplications: Set<String> {
        didSet {
            if let encoded = try? encoder.encode(discoveredApplications) {
                defaults.set(encoded, forKey: Keys.discoveredApplications)
            }
        }
    }

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

    /// Launch Gnau automatically at login
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LoginItemManager.shared.setLaunchAtLogin(launchAtLogin)
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

    // Future wordlists follow the same pattern:
    // /// Enable recognition of IT and technical terminology (API, JSON, localhost, etc.)
    // @Published var enableITTerminology: Bool {
    //     didSet {
    //         defaults.set(enableITTerminology, forKey: Keys.enableITTerminology)
    //     }
    // }

    // MARK: - Keyboard Shortcuts

    /// Enable keyboard shortcuts
    @Published var keyboardShortcutsEnabled: Bool {
        didSet {
            defaults.set(keyboardShortcutsEnabled, forKey: Keys.keyboardShortcutsEnabled)
        }
    }

    /// Shortcut to toggle grammar checking on/off
    @Published var toggleShortcut: String {
        didSet {
            defaults.set(toggleShortcut, forKey: Keys.toggleShortcut)
        }
    }

    /// Shortcut to accept current suggestion
    @Published var acceptSuggestionShortcut: String {
        didSet {
            defaults.set(acceptSuggestionShortcut, forKey: Keys.acceptSuggestionShortcut)
        }
    }

    /// Shortcut to dismiss current suggestion
    @Published var dismissSuggestionShortcut: String {
        didSet {
            defaults.set(dismissSuggestionShortcut, forKey: Keys.dismissSuggestionShortcut)
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

    /// Suggestion theme
    @Published var suggestionTheme: String {
        didSet {
            defaults.set(suggestionTheme, forKey: Keys.suggestionTheme)
        }
    }

    /// Available theme options
    static let suggestionThemes = [
        "System",
        "Light",
        "Dark"
    ]

    /// Error underline thickness (1.0 to 5.0)
    @Published var underlineThickness: Double {
        didSet {
            defaults.set(underlineThickness, forKey: Keys.underlineThickness)
        }
    }

    private init() {
        // Initialize with default values first
        self.pauseDuration = .active
        self.pausedUntil = nil
        self.disabledApplications = []
        self.discoveredApplications = []
        self.appPauseDurations = [:]
        self.appPausedUntil = [:]
        self.customDictionary = []
        self.ignoredRules = []
        self.ignoredErrorTexts = []
        self.analysisDelayMs = 20
        self.enabledCategories = UserPreferences.allCategories // All categories enabled by default
        self.launchAtLogin = false

        // Language & Dialect
        self.selectedDialect = "American"
        self.enableInternetAbbreviations = true
        self.enableGenZSlang = true
        self.enableITTerminology = true
        self.enableLanguageDetection = false  // Opt-in feature
        self.excludedLanguages = []

        // Keyboard Shortcuts
        self.keyboardShortcutsEnabled = true
        self.toggleShortcut = "⌘⇧G"
        self.acceptSuggestionShortcut = "⇥"
        self.dismissSuggestionShortcut = "⎋"

        // Suggestion Appearance
        self.suggestionOpacity = 0.95
        self.suggestionTextSize = 13.0
        self.suggestionPosition = "Auto"
        self.suggestionTheme = "System"
        self.underlineThickness = 3.0

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

        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false

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

        // Keyboard Shortcuts
        self.keyboardShortcutsEnabled = defaults.object(forKey: Keys.keyboardShortcutsEnabled) as? Bool ?? true
        self.toggleShortcut = defaults.string(forKey: Keys.toggleShortcut) ?? "⌘⇧G"
        self.acceptSuggestionShortcut = defaults.string(forKey: Keys.acceptSuggestionShortcut) ?? "⇥"
        self.dismissSuggestionShortcut = defaults.string(forKey: Keys.dismissSuggestionShortcut) ?? "⎋"

        // Suggestion Appearance
        self.suggestionOpacity = defaults.object(forKey: Keys.suggestionOpacity) as? Double ?? 0.95
        self.suggestionTextSize = defaults.object(forKey: Keys.suggestionTextSize) as? Double ?? 13.0
        self.suggestionPosition = defaults.string(forKey: Keys.suggestionPosition) ?? "Auto"
        self.suggestionTheme = defaults.string(forKey: Keys.suggestionTheme) ?? "System"
        self.underlineThickness = defaults.object(forKey: Keys.underlineThickness) as? Double ?? 3.0

        // Set up timer if paused for 1 hour
        if pauseDuration == .oneHour, let until = pausedUntil, Date() < until {
            setupResumeTimer(until: until)
        }

        // Set up cleanup timer to check for expired app-specific pauses every minute
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
            // Set pausedUntil to 1 hour from now
            let until = Date().addingTimeInterval(3600) // 1 hour
            pausedUntil = until
            setupResumeTimer(until: until)

        case .twentyFourHours:
            // Set pausedUntil to 24 hours from now
            let until = Date().addingTimeInterval(86400) // 24 hours
            pausedUntil = until
            setupResumeTimer(until: until)

        case .indefinite:
            // Keep pausedUntil nil
            pausedUntil = nil
        }

        // Update menu bar to reflect new state
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
        // Never check grammar in Gnau's own UI
        if bundleIdentifier == "app.gnau.Gnau" {
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

    /// Add a word to the custom dictionary
    func addToCustomDictionary(_ word: String) {
        guard customDictionary.count < 1000 else {
            print("Custom dictionary limit reached (1000 words)")
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
            print("Ignored error texts limit reached (1000 entries)")
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
            // Remove app-specific pause
            appPauseDurations.removeValue(forKey: bundleIdentifier)
            appPausedUntil.removeValue(forKey: bundleIdentifier)

        case .oneHour:
            // Set 1 hour pause for app
            let until = Date().addingTimeInterval(3600)
            appPauseDurations[bundleIdentifier] = duration
            appPausedUntil[bundleIdentifier] = until

        case .twentyFourHours:
            // Set 24 hour pause for app
            let until = Date().addingTimeInterval(86400)
            appPauseDurations[bundleIdentifier] = duration
            appPausedUntil[bundleIdentifier] = until

        case .indefinite:
            // Set indefinite pause for app
            appPauseDurations[bundleIdentifier] = duration
            appPausedUntil.removeValue(forKey: bundleIdentifier)
        }

        // Update menu bar
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
        keyboardShortcutsEnabled = true
        toggleShortcut = "⌘⇧G"
        acceptSuggestionShortcut = "⇥"
        dismissSuggestionShortcut = "⎋"
        suggestionOpacity = 0.95
        suggestionTextSize = 13.0
        suggestionPosition = "Auto"
        suggestionTheme = "System"
        underlineThickness = 3.0
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let pauseDuration = "pauseDuration"
        static let pausedUntil = "pausedUntil"
        static let disabledApplications = "disabledApplications"
        static let discoveredApplications = "discoveredApplications"
        static let appPauseDurations = "appPauseDurations"
        static let appPausedUntil = "appPausedUntil"
        static let customDictionary = "customDictionary"
        static let ignoredRules = "ignoredRules"
        static let ignoredErrorTexts = "ignoredErrorTexts"
        static let analysisDelayMs = "analysisDelayMs"
        static let enabledCategories = "enabledCategories"
        static let launchAtLogin = "launchAtLogin"

        // Language & Dialect
        static let selectedDialect = "selectedDialect"
        static let enableInternetAbbreviations = "enableInternetAbbreviations"
        static let enableGenZSlang = "enableGenZSlang"
        static let enableITTerminology = "enableITTerminology"
        static let enableLanguageDetection = "enableLanguageDetection"
        static let excludedLanguages = "excludedLanguages"

        // Keyboard Shortcuts
        static let keyboardShortcutsEnabled = "keyboardShortcutsEnabled"
        static let toggleShortcut = "toggleShortcut"
        static let acceptSuggestionShortcut = "acceptSuggestionShortcut"
        static let dismissSuggestionShortcut = "dismissSuggestionShortcut"

        // Suggestion Appearance
        static let suggestionOpacity = "suggestionOpacity"
        static let suggestionTextSize = "suggestionTextSize"
        static let suggestionPosition = "suggestionPosition"
        static let suggestionTheme = "suggestionTheme"
        static let underlineThickness = "underlineThickness"
    }
}
