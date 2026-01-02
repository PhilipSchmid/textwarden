//
//  PositionResolver.swift
//  TextWarden
//
//  Multi-strategy position resolution engine.
//  Uses AppRegistry to determine which strategies to use for each app.
//

import AppKit
import ApplicationServices

/// Position resolution engine with multiple strategies
/// Uses AppRegistry to filter and order strategies per app
class PositionResolver {
    // MARK: - Singleton

    static let shared = PositionResolver()

    // MARK: - Properties

    private let cache = PositionCache()

    /// All available strategies (used as pool for filtering)
    private var allStrategies: [GeometryProvider] = []

    /// Strategies indexed by type for quick lookup
    private var strategiesByType: [StrategyType: GeometryProvider] = [:]

    // MARK: - Initialization

    private init() {
        registerStrategies()
    }

    private func registerStrategies() {
        // Register all active strategies
        // Note: SelectionBoundsStrategy and NavigationStrategy have been moved to Legacy/
        // as they interfere with typing (manipulate cursor/selection)
        let strategies: [GeometryProvider] = [
            // Tier: Precise
            SlackStrategy(), // Dedicated strategy for Slack - highest priority
            TeamsStrategy(), // Dedicated strategy for Teams - same tree traversal approach
            NotionStrategy(), // Dedicated strategy for Notion - same tree traversal approach
            OutlookStrategy(), // Dedicated strategy for Outlook compose
            WordStrategy(), // Dedicated strategy for Word documents
            WebExStrategy(), // Dedicated strategy for Cisco WebEx chat
            MailStrategy(), // Dedicated strategy for Apple Mail's WebKit compose
            ProtonMailStrategy(), // Dedicated strategy for Proton Mail's Rooster editor
            ChromiumStrategy(),
            TextMarkerStrategy(),
            RangeBoundsStrategy(),

            // Tier: Reliable
            InsertionPointStrategy(), // For Mac Catalyst apps (Messages, etc.)
            ElementTreeStrategy(),
            LineIndexStrategy(),
            OriginStrategy(),
            AnchorSearchStrategy(),

            // Tier: Estimated
            FontMetricsStrategy(),
        ]

        // Store all strategies
        allStrategies = strategies

        // Index by type for quick lookup
        for strategy in strategies {
            strategiesByType[strategy.strategyType] = strategy
        }

        // Sort by tier and priority
        allStrategies.sort { lhs, rhs in
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }
            return lhs.tierPriority < rhs.tierPriority
        }

        Logger.debug("PositionResolver: Initialized with \(allStrategies.count) strategies", category: Logger.accessibility)
        for strategy in allStrategies {
            Logger.debug("  Strategy: \(strategy.strategyName) (tier: \(strategy.tier.description), priority: \(strategy.tierPriority))", category: Logger.accessibility)
        }
    }

    // MARK: - Strategy Selection

    /// Get strategies for a specific app, filtered and ordered by AppRegistry configuration.
    /// Uses effectiveConfiguration() to include auto-detected profiles for unknown apps.
    private func strategiesForApp(bundleID: String) -> [GeometryProvider] {
        let config = AppRegistry.shared.effectiveConfiguration(for: bundleID)

        // Start with preferred strategies if specified, otherwise use all
        var orderedStrategies: [GeometryProvider]

        if !config.preferredStrategies.isEmpty {
            // Use preferred order from configuration
            orderedStrategies = config.preferredStrategies.compactMap { type in
                strategiesByType[type]
            }

            // Add any remaining strategies not in the preferred list (maintaining tier order)
            let preferredSet = Set(config.preferredStrategies)
            let remaining = allStrategies.filter { !preferredSet.contains($0.strategyType) }
            orderedStrategies.append(contentsOf: remaining)
        } else {
            // Use default tier-based ordering
            orderedStrategies = allStrategies
        }

        // Filter out disabled strategies
        let disabledSet = config.disabledStrategies
        orderedStrategies = orderedStrategies.filter { !disabledSet.contains($0.strategyType) }

        return orderedStrategies
    }

    // MARK: - Position Resolution

    /// Resolve position using best available strategy
    /// Tries each strategy in order until one succeeds
    /// Returns an "unavailable" result (confidence 0) if text is not visible or all strategies fail
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String,
        parser: ContentParser,
        bundleID: String
    ) -> GeometryResult {
        let cacheKey = CacheKey(
            element: element,
            range: errorRange,
            textHash: text.hashValue
        )

        // Check cache first - but skip during replacement mode because
        // Electron/WebKit AX trees update asynchronously, so cached bounds
        // from immediately after replacement may be stale
        if !AnalysisCoordinator.isInReplacementModeThreadSafe, let cached = cache.get(key: cacheKey) {
            Logger.debug("PositionResolver: Using cached result for \(cacheKey.description)", category: Logger.accessibility)
            return cached
        }

        // Check watchdog BEFORE making any AX calls
        // These pre-strategy AX calls can also hang on misbehaving apps
        let watchdogActive = AXWatchdog.shared.shouldSkipCalls(for: bundleID)

        // FAIL-FAST: If app is already blacklisted, skip everything immediately
        if watchdogActive {
            Logger.debug("PositionResolver: Skipping - watchdog active for \(bundleID)", category: Logger.accessibility)
            return GeometryResult.unavailable(reason: "AX API unresponsive - skipping positioning")
        }

        // Check visibility BEFORE attempting positioning
        AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXVisibleCharacterRange")
        let isVisible = AccessibilityBridge.isRangeVisible(errorRange, in: element)
        AXWatchdog.shared.endCall()

        // FAIL-FAST: If visibility check caused blacklisting (timed out), abort immediately
        // This prevents wasting 50+ seconds trying strategies that will all fail
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.warning("PositionResolver: AX timeout detected - aborting positioning for \(bundleID)", category: Logger.accessibility)
            return GeometryResult.unavailable(reason: "AX API unresponsive (Copilot or overlay active?)")
        }

        if !isVisible {
            Logger.debug("PositionResolver: Range \(errorRange) is not visible - skipping positioning", category: Logger.accessibility)
            return GeometryResult.unavailable(reason: "Range not visible (scrolled out of view)")
        }

        // Get edit area frame for validation
        AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXPosition/AXSize")
        let editAreaFrame = AccessibilityBridge.getEditAreaFrame(element)
        AXWatchdog.shared.endCall()

        // FAIL-FAST: Check again after frame query
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.warning("PositionResolver: AX timeout detected - aborting positioning for \(bundleID)", category: Logger.accessibility)
            return GeometryResult.unavailable(reason: "AX API unresponsive (Copilot or overlay active?)")
        }

        // Get strategies for this app (filtered and ordered by AppRegistry)
        let strategies = strategiesForApp(bundleID: bundleID)

        Logger.debug("PositionResolver: Trying \(strategies.count) strategies for bundleID: \(bundleID)", category: Logger.ui)

        for strategy in strategies {
            // FAIL-FAST: Check watchdog before each strategy to catch timeouts early
            if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
                Logger.warning("PositionResolver: AX timeout during strategy loop - aborting", category: Logger.accessibility)
                return GeometryResult.unavailable(reason: "AX API became unresponsive during positioning")
            }

            Logger.debug("  Trying strategy: \(strategy.strategyName) (tier: \(strategy.tier.description))", category: Logger.ui)

            // Check if strategy can handle this element (technical capability check)
            guard strategy.canHandle(element: element, bundleID: bundleID) else {
                Logger.debug("  Strategy \(strategy.strategyName) cannot handle element", category: Logger.ui)
                continue
            }

            Logger.debug("  Strategy \(strategy.strategyName) can handle - trying calculateGeometry...", category: Logger.ui)

            // Try to calculate geometry
            if let result = strategy.calculateGeometry(
                errorRange: errorRange,
                element: element,
                text: text,
                parser: parser
            ) {
                // Check if this is an "unavailable" result - return immediately
                if result.isUnavailable {
                    Logger.debug("PositionResolver: Strategy \(strategy.strategyName) returned unavailable", category: Logger.accessibility)
                    return result
                }

                // Validate bounds are within edit area
                if let editArea = editAreaFrame {
                    let quartzBounds = CoordinateMapper.toQuartzCoordinates(result.bounds)
                    if !AccessibilityBridge.validateBoundsWithinEditArea(quartzBounds, editAreaFrame: editArea) {
                        Logger.debug("PositionResolver: Strategy \(strategy.strategyName) bounds outside edit area", category: Logger.accessibility)
                        continue
                    }
                }

                Logger.debug("PositionResolver: Strategy \(strategy.strategyName) succeeded with confidence \(result.confidence)", category: Logger.accessibility)
                Logger.debug("  Strategy \(strategy.strategyName) SUCCEEDED with confidence \(result.confidence)", category: Logger.ui)

                // Cache successful result (unless strategy opts out)
                let skipCache = result.metadata["skip_resolver_cache"] as? Bool ?? false
                if !skipCache {
                    cache.store(result, for: cacheKey)
                }

                return result
            } else {
                Logger.debug("  Strategy \(strategy.strategyName) FAILED", category: Logger.ui)
            }
        }

        // Graceful degradation - don't show underline rather than show it wrong
        Logger.warning("PositionResolver: All strategies failed for range \(errorRange)", category: Logger.accessibility)
        return GeometryResult.unavailable(reason: "All positioning strategies failed")
    }

    // MARK: - Cache Management

    /// Clear position cache and strategy internal caches
    func clearCache() {
        cache.clear()

        // Also clear internal caches of all strategies
        // This is important when AX tree structure changes (e.g., formatting changes)
        for strategy in allStrategies {
            strategy.clearInternalCache()
        }
    }

    /// Get cache statistics
    func cacheStatistics() -> CacheStatistics {
        cache.statistics()
    }

    // MARK: - Debugging

    /// Get strategies that would be used for a bundle ID (for debugging)
    func debugStrategiesFor(bundleID: String) -> [(name: String, type: StrategyType, tier: StrategyTier)] {
        strategiesForApp(bundleID: bundleID).map {
            (name: $0.strategyName, type: $0.strategyType, tier: $0.tier)
        }
    }
}
