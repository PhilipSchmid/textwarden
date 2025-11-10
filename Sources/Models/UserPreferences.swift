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
    case indefinite = "Paused Until Resumed"
}

/// Observable user preferences with automatic persistence
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var resumeTimer: Timer?

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
        case .oneHour:
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

    // MARK: - Updates

    /// Automatically check for updates
    @Published var autoCheckForUpdates: Bool {
        didSet {
            defaults.set(autoCheckForUpdates, forKey: Keys.autoCheckForUpdates)
        }
    }

    private init() {
        // Initialize with default values first
        self.pauseDuration = .active
        self.pausedUntil = nil
        self.disabledApplications = []
        self.customDictionary = []
        self.ignoredRules = []
        self.analysisDelayMs = 20
        self.enabledCategories = UserPreferences.allCategories // All categories enabled by default
        self.launchAtLogin = false

        // Language & Dialect
        self.selectedDialect = "American"

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

        // Updates
        self.autoCheckForUpdates = true

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

        if let data = defaults.data(forKey: Keys.customDictionary),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.customDictionary = set
        }

        if let data = defaults.data(forKey: Keys.ignoredRules),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.ignoredRules = set
        }

        self.analysisDelayMs = defaults.object(forKey: Keys.analysisDelayMs) as? Int ?? 20

        if let data = defaults.data(forKey: Keys.enabledCategories),
           let set = try? decoder.decode(Set<String>.self, from: data) {
            self.enabledCategories = set
        }

        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false

        // Language & Dialect
        self.selectedDialect = defaults.string(forKey: Keys.selectedDialect) ?? "American"

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

        // Updates
        self.autoCheckForUpdates = defaults.object(forKey: Keys.autoCheckForUpdates) as? Bool ?? true

        // Set up timer if paused for 1 hour
        if pauseDuration == .oneHour, let until = pausedUntil, Date() < until {
            setupResumeTimer(until: until)
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

    /// Check if grammar checking is enabled for a specific application
    func isEnabled(for bundleIdentifier: String) -> Bool {
        return isEnabled && !disabledApplications.contains(bundleIdentifier)
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

    /// Reset all preferences to defaults
    func resetToDefaults() {
        pauseDuration = .active
        pausedUntil = nil
        disabledApplications = []
        customDictionary = []
        ignoredRules = []
        analysisDelayMs = 20
        enabledCategories = UserPreferences.allCategories
        selectedDialect = "American"
        keyboardShortcutsEnabled = true
        toggleShortcut = "⌘⇧G"
        acceptSuggestionShortcut = "⇥"
        dismissSuggestionShortcut = "⎋"
        suggestionOpacity = 0.95
        suggestionTextSize = 13.0
        suggestionPosition = "Auto"
        suggestionTheme = "System"
        autoCheckForUpdates = true
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let pauseDuration = "pauseDuration"
        static let pausedUntil = "pausedUntil"
        static let disabledApplications = "disabledApplications"
        static let customDictionary = "customDictionary"
        static let ignoredRules = "ignoredRules"
        static let analysisDelayMs = "analysisDelayMs"
        static let enabledCategories = "enabledCategories"
        static let launchAtLogin = "launchAtLogin"

        // Language & Dialect
        static let selectedDialect = "selectedDialect"

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

        // Updates
        static let autoCheckForUpdates = "autoCheckForUpdates"
    }
}
