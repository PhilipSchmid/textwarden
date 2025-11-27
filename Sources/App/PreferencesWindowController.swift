//
//  PreferencesWindowController.swift
//  TextWarden
//
//  Controls which tab is shown in the preferences window
//

import Foundation
import Combine

/// Type-safe enum for settings tabs - use this instead of raw integers
/// to ensure navigation remains correct even if tabs are reordered
enum SettingsTab: Int, CaseIterable {
    case general = 0
    case spellChecking = 1
    case applications = 2
    case websites = 3
    case statistics = 4
    case diagnostics = 5
    case about = 6
}

class PreferencesWindowController: ObservableObject {
    static let shared = PreferencesWindowController()

    @Published var selectedTab: Int = SettingsTab.general.rawValue

    private init() {}

    func selectTab(_ tab: SettingsTab) {
        selectedTab = tab.rawValue
    }

    /// Legacy support - prefer using SettingsTab enum directly
    func selectTab(_ tab: Int) {
        selectedTab = tab
    }
}
