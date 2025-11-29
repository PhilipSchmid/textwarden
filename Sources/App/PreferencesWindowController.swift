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
    case grammar = 1
    case style = 2
    case applications = 3
    case websites = 4
    case statistics = 5
    case diagnostics = 6
    case about = 7
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
