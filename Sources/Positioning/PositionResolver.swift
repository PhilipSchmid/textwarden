//
//  PositionResolver.swift
//  Gnau
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
        // Register strategies in priority order (highest first)
        registerStrategies()
    }

    private func registerStrategies() {
        // Will be populated by strategy files
        // For now, initialize empty - strategies will register themselves
        strategies = []

        // Register built-in strategies
        registerStrategy(ModernMarkerStrategy())
        registerStrategy(ClassicRangeStrategy())
        registerStrategy(TextMeasurementStrategy())

        // Sort by priority
        strategies.sort { $0.priority > $1.priority }

        Logger.debug("PositionResolver initialized with \(strategies.count) strategies")
        let initMsg = "🎯 PositionResolver: Initialized with \(strategies.count) strategies"
        NSLog(initMsg)
        logToDebugFile(initMsg)
        for strategy in strategies {
            let stratMsg = "  📍 Strategy: \(strategy.strategyName) (priority: \(strategy.priority))"
            NSLog(stratMsg)
            logToDebugFile(stratMsg)
        }
    }

    // MARK: - Strategy Registration

    /// Register a new positioning strategy
    /// Strategies are automatically sorted by priority
    func registerStrategy(_ strategy: GeometryProvider) {
        strategies.append(strategy)
        strategies.sort { $0.priority > $1.priority }

        Logger.debug("Registered strategy: \(strategy.strategyName) (priority: \(strategy.priority))")
    }

    // MARK: - Position Resolution

    /// Resolve position using best available strategy
    /// Tries each strategy in priority order until one succeeds
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String,
        parser: ContentParser,
        bundleID: String
    ) -> GeometryResult {

        // Create cache key
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

        // Try each strategy in priority order
        let tryMsg = "🔍 PositionResolver: Trying \(strategies.count) strategies for bundleID: \(bundleID)"
        NSLog(tryMsg)
        logToDebugFile(tryMsg)
        for strategy in strategies {
            let stratMsg = "  🎯 Trying strategy: \(strategy.strategyName) (priority: \(strategy.priority))"
            NSLog(stratMsg)
            logToDebugFile(stratMsg)

            // Check if strategy can handle this element
            guard strategy.canHandle(element: element, bundleID: bundleID) else {
                Logger.debug("PositionResolver: Strategy \(strategy.strategyName) cannot handle bundleID: \(bundleID)")
                let failMsg = "  ❌ Strategy \(strategy.strategyName) cannot handle bundleID: \(bundleID)"
                NSLog(failMsg)
                logToDebugFile(failMsg)
                continue
            }

            let canHandleMsg = "  ✅ Strategy \(strategy.strategyName) can handle - trying calculateGeometry..."
            NSLog(canHandleMsg)
            logToDebugFile(canHandleMsg)

            // Try to calculate geometry
            if let result = strategy.calculateGeometry(
                errorRange: errorRange,
                element: element,
                text: text,
                parser: parser
            ) {
                Logger.debug("PositionResolver: Strategy \(strategy.strategyName) succeeded with confidence \(result.confidence)")
                let successMsg = "  ✅ Strategy \(strategy.strategyName) SUCCEEDED with confidence \(result.confidence)"
                NSLog(successMsg)
                logToDebugFile(successMsg)

                // Cache successful result
                cache.store(result, for: cacheKey)

                return result
            } else {
                Logger.debug("PositionResolver: Strategy \(strategy.strategyName) failed")
                let failMsg = "  ❌ Strategy \(strategy.strategyName) FAILED"
                NSLog(failMsg)
                logToDebugFile(failMsg)
            }
        }

        // All strategies failed - return low-confidence fallback
        Logger.warning("PositionResolver: All strategies failed for range \(errorRange)")

        let fallback = createFallbackResult(
            errorRange: errorRange,
            element: element,
            text: text
        )

        // Don't cache fallback results
        return fallback
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
