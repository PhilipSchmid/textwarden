//
//  PositionResolver.swift
//  TextWarden
//
//  Multi-strategy position resolution engine.
//  Uses AppRegistry to determine which strategies to use for each app.
//

import Foundation
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
            ChromiumStrategy(),
            TextMarkerStrategy(),
            RangeBoundsStrategy(),

            // Tier: Reliable
            ElementTreeStrategy(),
            LineIndexStrategy(),
            OriginStrategy(),
            AnchorSearchStrategy(),

            // Tier: Estimated
            FontMetricsStrategy()
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

        Logger.debug("PositionResolver: Initialized with \(allStrategies.count) strategies")
        for strategy in allStrategies {
            Logger.debug("  Strategy: \(strategy.strategyName) (tier: \(strategy.tier.description), priority: \(strategy.tierPriority))")
        }
    }

    // MARK: - Strategy Selection

    /// Get strategies for a specific app, filtered and ordered by AppRegistry configuration
    private func strategiesForApp(bundleID: String) -> [GeometryProvider] {
        let config = AppRegistry.shared.configuration(for: bundleID)

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

        // Check cache first
        if let cached = cache.get(key: cacheKey) {
            Logger.debug("PositionResolver: Using cached result for \(cacheKey.description)")
            return cached
        }

        // Check visibility BEFORE attempting positioning
        if !AccessibilityBridge.isRangeVisible(errorRange, in: element) {
            Logger.debug("PositionResolver: Range \(errorRange) is not visible - skipping positioning")
            return GeometryResult.unavailable(reason: "Range not visible (scrolled out of view)")
        }

        // Get edit area frame for validation
        let editAreaFrame = AccessibilityBridge.getEditAreaFrame(element)

        // Get strategies for this app (filtered and ordered by AppRegistry)
        let strategies = strategiesForApp(bundleID: bundleID)

        Logger.debug("PositionResolver: Trying \(strategies.count) strategies for bundleID: \(bundleID)", category: Logger.ui)

        for strategy in strategies {
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
                    Logger.debug("PositionResolver: Strategy \(strategy.strategyName) returned unavailable")
                    return result
                }

                // Validate bounds are within edit area
                if let editArea = editAreaFrame {
                    let quartzBounds = CoordinateMapper.toQuartzCoordinates(result.bounds)
                    if !AccessibilityBridge.validateBoundsWithinEditArea(quartzBounds, editAreaFrame: editArea) {
                        Logger.debug("PositionResolver: Strategy \(strategy.strategyName) bounds outside edit area")
                        continue
                    }
                }

                Logger.debug("PositionResolver: Strategy \(strategy.strategyName) succeeded with confidence \(result.confidence)")
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
        Logger.warning("PositionResolver: All strategies failed for range \(errorRange)")
        return GeometryResult.unavailable(reason: "All positioning strategies failed")
    }

    // MARK: - Cache Management

    /// Clear position cache
    func clearCache() {
        cache.clear()
    }

    /// Get cache statistics
    func cacheStatistics() -> CacheStatistics {
        return cache.statistics()
    }

    // MARK: - Debugging

    /// Get strategies that would be used for a bundle ID (for debugging)
    func debugStrategiesFor(bundleID: String) -> [(name: String, type: StrategyType, tier: StrategyTier)] {
        return strategiesForApp(bundleID: bundleID).map {
            (name: $0.strategyName, type: $0.strategyType, tier: $0.tier)
        }
    }
}
