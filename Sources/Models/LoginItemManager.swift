//
//  LoginItemManager.swift
//  Gnau
//
//  Manages launch at login functionality using ServiceManagement
//

import Foundation
import ServiceManagement

/// Manages login item registration for auto-start at login
class LoginItemManager {
    static let shared = LoginItemManager()

    private init() {}

    /// Set whether the app should launch at login
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if #available(macOS 13.0, *) {
                    try SMAppService.mainApp.register()
                    print("✅ LoginItemManager: Registered for login")
                } else {
                    // Fallback for older macOS versions
                    setLaunchAtLoginLegacy(enabled: true)
                }
            } else {
                if #available(macOS 13.0, *) {
                    try SMAppService.mainApp.unregister()
                    print("❌ LoginItemManager: Unregistered from login")
                } else {
                    // Fallback for older macOS versions
                    setLaunchAtLoginLegacy(enabled: false)
                }
            }
        } catch {
            print("⚠️ LoginItemManager: Failed to set launch at login: \(error)")
        }
    }

    /// Check if the app is currently registered to launch at login
    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return isLaunchAtLoginEnabledLegacy()
        }
    }

    // MARK: - Legacy Support (macOS 12 and earlier)

    private func setLaunchAtLoginLegacy(enabled: Bool) {
        #if compiler(>=5.5)
        if #available(macOS 12.0, *) {
            // Use LSSharedFileList for macOS 12
            let identifier = Bundle.main.bundleIdentifier ?? "com.philipschmid.Gnau"
            if enabled {
                print("⚠️ LoginItemManager: Legacy login item not implemented for macOS 12")
            } else {
                print("⚠️ LoginItemManager: Legacy login item removal not implemented for macOS 12")
            }
        }
        #endif
    }

    private func isLaunchAtLoginEnabledLegacy() -> Bool {
        #if compiler(>=5.5)
        if #available(macOS 12.0, *) {
            // Check using LSSharedFileList for macOS 12
            return false // Not implemented
        }
        #endif
        return false
    }
}
