//
//  PreferencesWindowController.swift
//  TextWarden
//
//  Controls which tab is shown in the preferences window
//

import Foundation
import Combine
import AppKit

/// Type-safe enum for settings tabs - use this instead of raw integers
/// to ensure navigation remains correct even if tabs are reordered
enum SettingsTab: Int, CaseIterable {
    case general = 0
    case grammar = 1
    case style = 2
    case applications = 3
    case websites = 4
    case statistics = 5
    case diagnostics = 6
    case about = 7
}

@MainActor
class PreferencesWindowController: ObservableObject {
    static let shared = PreferencesWindowController()

    @Published var selectedTab: Int = SettingsTab.general.rawValue

    private var themeObserver: AnyCancellable?

    private init() {
        // Observe app theme changes and update NSApp.appearance accordingly
        themeObserver = UserPreferences.shared.$appTheme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTheme in
                self?.updateAppearance(for: newTheme)
            }

        // Set initial appearance
        updateAppearance(for: UserPreferences.shared.appTheme)
    }

    /// Updates NSApp.appearance based on the theme preference
    /// This provides seamless theme switching without view recreation
    func updateAppearance(for theme: String) {
        switch theme {
        case "Light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default: // "System"
            // Setting to nil makes the app follow system appearance
            NSApp.appearance = nil
        }
    }

    func selectTab(_ tab: SettingsTab) {
        selectedTab = tab.rawValue
    }

    /// Legacy support - prefer using SettingsTab enum directly
    func selectTab(_ tab: Int) {
        selectedTab = tab
    }
}
