//
//  StrategyRecommendationEngine.swift
//  TextWarden
//
//  Orchestrates application profiling and strategy recommendation.
//  Called when TextWarden encounters an unknown application.
//

import Foundation
import ApplicationServices

/// Orchestrates profiling and strategy recommendation for unknown applications
final class StrategyRecommendationEngine {
    static let shared = StrategyRecommendationEngine()

    // MARK: - Properties

    private let profiler = StrategyProfiler.shared
    private let cache = StrategyProfileCache.shared
    private let registry = AppRegistry.shared

    /// Apps profiled this session (to avoid repeated profiling attempts)
    private var profiledThisSession: Set<String> = []
    private let sessionLock = NSLock()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Called when text monitoring starts for an application.
    /// Profiles the app if it hasn't been profiled yet.
    func onTextMonitoringStarted(element: AXUIElement, bundleID: String) {
        // Skip if app has explicit configuration
        guard !registry.hasConfiguration(for: bundleID) else {
            Logger.debug("StrategyEngine: Skipping \(bundleID) - has explicit configuration", category: Logger.accessibility)
            return
        }

        // Skip if already profiled this session
        sessionLock.lock()
        let alreadyProfiled = profiledThisSession.contains(bundleID)
        if !alreadyProfiled {
            profiledThisSession.insert(bundleID)
        }
        sessionLock.unlock()

        guard !alreadyProfiled else {
            Logger.debug("StrategyEngine: Skipping \(bundleID) - already profiled this session", category: Logger.accessibility)
            return
        }

        // Skip if we have a valid cached profile
        if cache.hasValidProfile(for: bundleID) {
            Logger.debug("StrategyEngine: Skipping \(bundleID) - valid cached profile exists", category: Logger.accessibility)
            return
        }

        // Profile in background to avoid blocking text monitoring
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.profileApplication(element: element, bundleID: bundleID)
        }
    }

    /// Get profile for a bundle ID (from cache).
    /// Returns nil if no profile exists.
    func profile(for bundleID: String) -> AXCapabilityProfile? {
        cache.profile(for: bundleID)
    }

    /// Get recommended strategies for an app.
    /// Returns nil if app has explicit configuration or no profile exists.
    func recommendedStrategies(for bundleID: String) -> [StrategyType]? {
        // Skip apps with explicit configuration
        guard !registry.hasConfiguration(for: bundleID) else {
            return nil
        }

        // Return cached profile's recommendations
        guard let profile = cache.profile(for: bundleID), !profile.isExpired else {
            return nil
        }

        return profile.recommendedStrategies
    }

    /// Get full AppFeatures for an app based on profile.
    /// Returns nil if no profile exists.
    func appFeatures(for bundleID: String) -> AppFeatures? {
        guard !registry.hasConfiguration(for: bundleID) else {
            return nil
        }

        guard let profile = cache.profile(for: bundleID), !profile.isExpired else {
            return nil
        }

        return profile.appFeatures
    }

    /// Clear profile for a specific app (for debugging/troubleshooting)
    func clearProfile(for bundleID: String) {
        sessionLock.lock()
        profiledThisSession.remove(bundleID)
        sessionLock.unlock()
        cache.clearProfile(for: bundleID)
        Logger.info("StrategyEngine: Cleared profile for \(bundleID)", category: Logger.accessibility)
    }

    /// Clear all profiles (for debugging/troubleshooting)
    func clearAllProfiles() {
        sessionLock.lock()
        profiledThisSession.removeAll()
        sessionLock.unlock()
        cache.clearAll()
        Logger.info("StrategyEngine: Cleared all profiles", category: Logger.accessibility)
    }

    // MARK: - Private Methods

    private func profileApplication(element: AXUIElement, bundleID: String) {
        Logger.info("StrategyEngine: Profiling \(bundleID)...", category: Logger.accessibility)

        guard let profile = profiler.profileApplication(element: element, bundleID: bundleID) else {
            Logger.info("StrategyEngine: Could not profile \(bundleID) - no suitable text element", category: Logger.accessibility)
            return
        }

        // Store in cache
        cache.store(profile)

        Logger.info("StrategyEngine: Successfully profiled \(bundleID)", category: Logger.accessibility)
    }
}
