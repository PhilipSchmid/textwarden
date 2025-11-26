//
//  PositionResolver.swift
//  TextWarden
//
//  Multi-strategy position resolution engine
//  Automatically selects best strategy and falls back on failure
//

import Foundation
import ApplicationServices

/// Position resolution engine with multiple strategies
/// Automatically tries strategies in priority order until one succeeds
class PositionResolver {

    // MARK: - Singleton

    static let shared = PositionResolver()

    // MARK: - Properties

    private let cache = PositionCache()
    private var strategies: [GeometryProvider] = []

    // MARK: - Initialization

    private init() {
        registerStrategies()
    }

    private func registerStrategies() {
        strategies = []
        // Strategies are organized by capability tiers (precise > reliable > estimated > fallback)
        // Within each tier, lower tierPriority values are tried first

        // Tier: Precise - Direct AX bounds that are known to be reliable
        registerStrategy(TextMarkerStrategy())      // Opaque markers (Electron/Chrome)
        registerStrategy(RangeBoundsStrategy())     // CFRange bounds (native apps)

        // Tier: Reliable - Calculations based on known-good anchors
        registerStrategy(ElementTreeStrategy())     // Child element traversal (Notion)
        registerStrategy(LineIndexStrategy())       // Line-based positioning
        registerStrategy(OriginStrategy())          // Position extraction when dimensions are zero
        registerStrategy(AnchorSearchStrategy())    // Probe nearby characters for anchor

        // Tier: Estimated - Font-based measurement
        registerStrategy(FontMetricsStrategy())     // App-specific font estimation

        // Tier: Fallback - Last resort methods
        registerStrategy(SelectionBoundsStrategy()) // Selection manipulation
        registerStrategy(NavigationStrategy())      // Cursor navigation

        // Sort by tier (ascending), then by tierPriority (ascending)
        strategies.sort { lhs, rhs in
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }
            return lhs.tierPriority < rhs.tierPriority
        }

        Logger.debug("PositionResolver initialized with \(strategies.count) strategies")
        Logger.debug("PositionResolver: Initialized with \(strategies.count) strategies", category: Logger.ui)
        for strategy in strategies {
            Logger.debug("  Strategy: \(strategy.strategyName) (tier: \(strategy.tier.description), priority: \(strategy.tierPriority))", category: Logger.ui)
        }
    }

    // MARK: - Strategy Registration

    /// Register a new positioning strategy
    /// Strategies are automatically sorted by tier and priority
    func registerStrategy(_ strategy: GeometryProvider) {
        strategies.append(strategy)
        strategies.sort { lhs, rhs in
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }
            return lhs.tierPriority < rhs.tierPriority
        }

        Logger.debug("Registered strategy: \(strategy.strategyName) (tier: \(strategy.tier.description))")
    }

    // MARK: - Position Resolution

    /// Resolve position using best available strategy
    /// Tries each strategy in tier order until one succeeds
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
        // This prevents incorrect underline positioning for text that's scrolled out of view
        if !AccessibilityBridge.isRangeVisible(errorRange, in: element) {
            Logger.debug("PositionResolver: Range \(errorRange) is not visible - skipping positioning")
            return GeometryResult.unavailable(reason: "Range not visible (scrolled out of view)")
        }

        // Get edit area frame for validation
        let editAreaFrame = AccessibilityBridge.getEditAreaFrame(element)

        // Try each strategy in tier order
        Logger.debug("PositionResolver: Trying \(strategies.count) strategies for bundleID: \(bundleID)", category: Logger.ui)
        for strategy in strategies {
            Logger.debug("  Trying strategy: \(strategy.strategyName) (tier: \(strategy.tier.description))", category: Logger.ui)

            // Check if strategy can handle this element
            guard strategy.canHandle(element: element, bundleID: bundleID) else {
                Logger.debug("PositionResolver: Strategy \(strategy.strategyName) cannot handle bundleID: \(bundleID)")
                Logger.debug("  Strategy \(strategy.strategyName) cannot handle bundleID: \(bundleID)", category: Logger.ui)
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
                // Validate bounds are within edit area
                if let editArea = editAreaFrame {
                    // Convert result bounds to Quartz for comparison (editArea is in Quartz)
                    let quartzBounds = CoordinateMapper.toQuartzCoordinates(result.bounds)
                    if !AccessibilityBridge.validateBoundsWithinEditArea(quartzBounds, editAreaFrame: editArea) {
                        Logger.debug("PositionResolver: Strategy \(strategy.strategyName) bounds outside edit area - trying next strategy")
                        continue
                    }
                }

                Logger.debug("PositionResolver: Strategy \(strategy.strategyName) succeeded with confidence \(result.confidence)")
                Logger.debug("  Strategy \(strategy.strategyName) SUCCEEDED with confidence \(result.confidence)", category: Logger.ui)

                // Cache successful result
                cache.store(result, for: cacheKey)

                return result
            } else {
                Logger.debug("PositionResolver: Strategy \(strategy.strategyName) failed")
                Logger.debug("  Strategy \(strategy.strategyName) FAILED", category: Logger.ui)
            }
        }

        // Graceful degradation - don't show underline rather than show it wrong
        Logger.warning("PositionResolver: All strategies failed for range \(errorRange) - using graceful degradation")

        // Return an "unavailable" result that tells the UI not to show an underline
        // This is better than showing an underline in the wrong position
        return GeometryResult.unavailable(reason: "All positioning strategies failed")
    }

    // MARK: - Fallback

    private func createFallbackResult(
        errorRange: NSRange,
        element: AXUIElement,
        text: String
    ) -> GeometryResult {
        // Very rough estimation
        if let estimatedBounds = AccessibilityBridge.estimatePosition(
            at: errorRange.location,
            in: element
        ) {
            return GeometryResult.lowConfidence(
                bounds: estimatedBounds,
                reason: "All positioning strategies failed"
            )
        }

        // Ultimate fallback - center of screen
        return GeometryResult.lowConfidence(
            bounds: CGRect(x: 400, y: 400, width: 100, height: 20),
            reason: "Complete positioning failure, using screen center"
        )
    }

    // MARK: - Cache Management

    /// Clear position cache
    /// Useful when app switches or text field changes
    func clearCache() {
        cache.clear()
    }

    /// Get cache statistics
    func cacheStatistics() -> CacheStatistics {
        return cache.statistics()
    }
}
