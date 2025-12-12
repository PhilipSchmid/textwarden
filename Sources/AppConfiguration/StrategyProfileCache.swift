//
//  StrategyProfileCache.swift
//  TextWarden
//
//  Persistent cache for application capability profiles.
//  Stores profiles to disk and reloads on launch.
//

import Foundation

/// Manages persistent storage of application capability profiles
final class StrategyProfileCache {
    static let shared = StrategyProfileCache()

    // MARK: - Properties

    private var profiles: [String: AXCapabilityProfile] = [:]
    private let queue = DispatchQueue(label: "com.textwarden.strategy-profile-cache")
    private let cacheFileName = "strategy-profiles.json"

    /// URL for the cache file
    var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let textWardenDir = appSupport.appendingPathComponent("TextWarden", isDirectory: true)
        return textWardenDir.appendingPathComponent(cacheFileName)
    }

    // MARK: - Initialization

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Get profile for a bundle ID
    func profile(for bundleID: String) -> AXCapabilityProfile? {
        queue.sync {
            profiles[bundleID]
        }
    }

    /// Store a profile (saves to memory and disk)
    func store(_ profile: AXCapabilityProfile) {
        queue.async { [weak self] in
            self?.profiles[profile.bundleID] = profile
            self?.saveToDisk()
        }
    }

    /// Check if a valid (non-expired) profile exists
    func hasValidProfile(for bundleID: String) -> Bool {
        queue.sync {
            guard let profile = profiles[bundleID] else { return false }
            return !profile.isExpired
        }
    }

    /// Clear profile for a specific app (e.g., when user reports issues)
    func clearProfile(for bundleID: String) {
        queue.async { [weak self] in
            self?.profiles.removeValue(forKey: bundleID)
            self?.saveToDisk()
        }
    }

    /// Clear all cached profiles
    func clearAll() {
        queue.async { [weak self] in
            self?.profiles.removeAll()
            self?.saveToDisk()
        }
    }

    /// Get all profiles (for diagnostic export)
    var allProfiles: [AXCapabilityProfile] {
        queue.sync {
            Array(profiles.values).sorted { $0.probedAt > $1.probedAt }
        }
    }

    /// Number of cached profiles
    var profileCount: Int {
        queue.sync {
            profiles.count
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        let fileManager = FileManager.default
        let url = cacheFileURL

        guard fileManager.fileExists(atPath: url.path) else {
            Logger.debug("StrategyProfileCache: No cache file exists at \(url.path)", category: Logger.accessibility)
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedProfiles = try decoder.decode([String: AXCapabilityProfile].self, from: data)

            // Filter out expired profiles
            let validProfiles = loadedProfiles.filter { !$0.value.isExpired }

            queue.async { [weak self] in
                self?.profiles = validProfiles
            }

            let expiredCount = loadedProfiles.count - validProfiles.count
            Logger.info("StrategyProfileCache: Loaded \(validProfiles.count) profiles from disk (\(expiredCount) expired, removed)", category: Logger.accessibility)
        } catch {
            Logger.warning("StrategyProfileCache: Failed to load cache from disk: \(error)", category: Logger.accessibility)
        }
    }

    private func saveToDisk() {
        let fileManager = FileManager.default
        let url = cacheFileURL

        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                Logger.error("StrategyProfileCache: Failed to create directory: \(error)", category: Logger.accessibility)
                return
            }
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profiles)
            try data.write(to: url, options: .atomic)
            Logger.debug("StrategyProfileCache: Saved \(profiles.count) profiles to disk", category: Logger.accessibility)
        } catch {
            Logger.error("StrategyProfileCache: Failed to save cache to disk: \(error)", category: Logger.accessibility)
        }
    }
}
