//
//  PreferencesWindowController.swift
//  TextWarden
//
//  Controls which tab is shown in the preferences window
//

import Foundation
import Combine

class PreferencesWindowController: ObservableObject {
    static let shared = PreferencesWindowController()

    @Published var selectedTab: Int = 0

    private init() {}

    func selectTab(_ tab: Int) {
        selectedTab = tab
    }
}
