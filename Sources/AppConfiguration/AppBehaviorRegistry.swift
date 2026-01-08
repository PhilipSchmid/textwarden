//
//  AppBehaviorRegistry.swift
//  TextWarden
//
//  Central registry for all app behaviors.
//  NO defaults. NO categories. Each app is completely isolated.
//
//  Design principle: Every app gets its own complete configuration.
//  Changing one app's behavior cannot affect another app's behavior.
//

import Foundation

// MARK: - App Behavior Registry

/// Central registry for all app behaviors.
///
/// Unlike `AppRegistry` which uses category-based defaults that can cause
/// cross-app contamination, this registry treats each app as completely
/// isolated. Each app has its own `AppBehavior` with explicit values.
///
/// Usage:
/// ```swift
/// let behavior = AppBehaviorRegistry.shared.behavior(for: "com.tinyspeck.slackmacgap")
/// if behavior.scrollBehavior.hideOnScrollStart {
///     // Hide overlays during scroll
/// }
/// ```
final class AppBehaviorRegistry {
    static let shared = AppBehaviorRegistry()

    // MARK: - Storage

    private var behaviors: [String: AppBehavior] = [:]

    // MARK: - Initialization

    private init() {
        registerBuiltInBehaviors()
    }

    // MARK: - Registration

    private func register(_ behavior: AppBehavior) {
        behaviors[behavior.bundleIdentifier] = behavior
    }

    private func registerBuiltInBehaviors() {
        // Electron/Chromium apps
        register(SlackBehavior())
        register(NotionBehavior())
        register(ClaudeBehavior())
        register(ChatGPTBehavior())
        register(PerplexityBehavior())
        register(TeamsBehavior())
        register(ProtonMailBehavior())

        // Apple native apps
        register(MailBehavior())
        register(MessagesBehavior())
        register(NotesBehavior())
        register(TextEditBehavior())
        register(RemindersBehavior())
        register(CalendarBehavior())
        register(PagesBehavior())

        // Messenger apps
        register(WhatsAppBehavior())
        register(TelegramBehavior())

        // Microsoft Office
        register(WordBehavior())
        register(PowerPointBehavior())
        register(OutlookBehavior())

        // Other native apps
        register(WebExBehavior())

        // Web browsers (each gets its own behavior instance)
        for browserBehavior in BrowserBehaviorFactory.createAllBrowserBehaviors() {
            register(browserBehavior)
        }
    }

    // MARK: - Public API

    /// Get behavior for a bundle ID.
    /// Returns a default behavior for unknown apps (with conservative settings).
    func behavior(for bundleIdentifier: String) -> AppBehavior {
        if let registered = behaviors[bundleIdentifier] {
            return registered
        }
        // Return default behavior for unknown apps
        return DefaultBehavior(bundleIdentifier: bundleIdentifier)
    }

    /// Get behavior for a bundle ID, or nil if not explicitly registered.
    func registeredBehavior(for bundleIdentifier: String) -> AppBehavior? {
        behaviors[bundleIdentifier]
    }

    /// Check if app has an explicit behavior registered
    func hasRegisteredBehavior(for bundleIdentifier: String) -> Bool {
        behaviors[bundleIdentifier] != nil
    }

    /// All registered bundle identifiers
    var registeredBundleIDs: [String] {
        Array(behaviors.keys)
    }

    /// Number of registered behaviors
    var registeredCount: Int {
        behaviors.count
    }
}

// MARK: - AppConfiguration Integration

extension AppBehaviorRegistry {
    /// Get behavior for an AppConfiguration.
    /// Tries each bundle ID in the configuration until a registered behavior is found.
    /// Falls back to default behavior if no registered behavior matches.
    ///
    /// This is the preferred method when you have an AppConfiguration, as it:
    /// - Handles apps with multiple bundle IDs
    /// - Returns a registered behavior if any bundle ID matches
    /// - Provides a sensible default for unknown configurations
    func behavior(for appConfig: AppConfiguration) -> AppBehavior {
        // Try to find a registered behavior for any of the app's bundle IDs
        for bundleID in appConfig.bundleIDs {
            if let registered = behaviors[bundleID] {
                return registered
            }
        }
        // Fall back to default using the first bundle ID (or identifier if no bundle IDs)
        let fallbackID = appConfig.bundleIDs.first ?? appConfig.identifier
        return DefaultBehavior(bundleIdentifier: fallbackID)
    }
}

// MARK: - Convenience Extensions

extension AppBehaviorRegistry {
    /// Check if app has a specific quirk
    func hasQuirk(_ quirk: AppQuirk, for bundleIdentifier: String) -> Bool {
        behavior(for: bundleIdentifier).knownQuirks.contains(quirk)
    }

    /// Get timing profile for app
    func timingProfile(for bundleIdentifier: String) -> TimingProfile {
        behavior(for: bundleIdentifier).timingProfile
    }

    /// Get scroll behavior for app
    func scrollBehavior(for bundleIdentifier: String) -> ScrollBehavior {
        behavior(for: bundleIdentifier).scrollBehavior
    }

    /// Get popover behavior for app
    func popoverBehavior(for bundleIdentifier: String) -> PopoverBehavior {
        behavior(for: bundleIdentifier).popoverBehavior
    }
}
