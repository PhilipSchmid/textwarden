//
//  PositionResolver.swift
//  TextWarden
//
//  Multi-strategy position resolution engine.
//  Uses AppRegistry to determine which strategies to use for each app.
//

import AppKit
import ApplicationServices

/// Producers keep their native offsets for host-specific strategies. AX queries use UTF-16.
struct PositionRange: Hashable {
    let source: NSRange
    /// Some hosts expose text only through their own AX tree or text markers.
    let utf16: NSRange?

    init(scalars range: NSRange, in text: String, afterScalarPrefix prefix: Int = 0) {
        source = range
        let scalars = text.unicodeScalars
        guard prefix >= 0, range.location >= 0, range.length > 0,
              let origin = scalars.index(scalars.startIndex, offsetBy: prefix, limitedBy: scalars.endIndex),
              let start = scalars.index(origin, offsetBy: range.location, limitedBy: scalars.endIndex),
              let end = scalars.index(start, offsetBy: range.length, limitedBy: scalars.endIndex),
              let lower = String.Index(start, within: text), let upper = String.Index(end, within: text)
        else {
            utf16 = nil
            return
        }
        utf16 = NSRange(lower ..< upper, in: text)
    }

    init(characters range: NSRange, in text: String?, afterScalarPrefix prefix: Int = 0) {
        source = range
        guard let text, prefix >= 0, range.location >= 0, range.length > 0,
              let origin = TextIndexConverter.scalarIndexToStringIndex(prefix, in: text),
              let start = text.index(origin, offsetBy: range.location, limitedBy: text.endIndex),
              let end = text.index(start, offsetBy: range.length, limitedBy: text.endIndex)
        else {
            utf16 = nil
            return
        }
        utf16 = NSRange(start ..< end, in: text)
    }

    /// Expand a separator to the adjacent words before resolving its geometry.
    static func grammar(_ source: NSRange, in text: String, afterScalarPrefix prefix: Int = 0) -> Self {
        let range = Self(scalars: source, in: text, afterScalarPrefix: prefix)
        guard source.length == 1 else { return range }

        func words(at utf16: NSRange?, after origin: String.Index) -> Range<String.Index>? {
            guard let utf16, let separator = Range(utf16, in: text),
                  text[separator.lowerBound].isWhitespace || text[separator.lowerBound].isPunctuation
            else { return nil }
            let start = text[origin ..< separator.lowerBound].lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? origin
            let end = text[separator.upperBound...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            guard start < separator.lowerBound, separator.upperBound < end else { return nil }
            return start ..< end
        }

        // Dedicated host strategies historically receive the overlay's character-based expansion.
        let legacy = Self(characters: source, in: text)
        let hostRange = words(at: legacy.utf16, after: text.startIndex).map {
            NSRange(location: text.distance(from: text.startIndex, to: $0.lowerBound), length: text.distance(from: $0.lowerBound, to: $0.upperBound))
        } ?? source
        let native = TextIndexConverter.scalarIndexToStringIndex(prefix, in: text).flatMap { words(at: range.utf16, after: $0) }
        return Self(source: hostRange, utf16: native.map { NSRange($0, in: text) } ?? range.utf16)
    }

    private init(source: NSRange, utf16: NSRange?) {
        self.source = source
        self.utf16 = utf16
    }

    func range(for strategy: StrategyType) -> NSRange? {
        switch strategy {
        case .lineIndex, .rangeBounds, .elementTree: utf16
        default: source
        }
    }
}

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

    init(rangeBounds: RangeBoundsStrategy = RangeBoundsStrategy(), elementTree: ElementTreeStrategy = ElementTreeStrategy()) {
        registerStrategies(rangeBounds: rangeBounds, elementTree: elementTree)
    }

    private func registerStrategies(rangeBounds: RangeBoundsStrategy, elementTree: ElementTreeStrategy) {
        // Register all active strategies
        // Note: SelectionBoundsStrategy and NavigationStrategy have been moved to Legacy/
        // as they interfere with typing (manipulate cursor/selection)
        let strategies: [GeometryProvider] = [
            // Tier: Precise
            SlackStrategy(), // Dedicated strategy for Slack - highest priority
            TeamsStrategy(), // Dedicated strategy for Teams - same tree traversal approach
            NotionStrategy(), // Dedicated strategy for Notion - same tree traversal approach
            ObsidianStrategy(),
            OutlookStrategy(), // Dedicated strategy for Outlook compose
            WordStrategy(), // Dedicated strategy for Word documents
            PowerPointStrategy(), // Dedicated strategy for PowerPoint Notes
            WebExStrategy(), // Dedicated strategy for Cisco WebEx chat
            MailStrategy(), // Dedicated strategy for Apple Mail's WebKit compose
            ProtonMailStrategy(), // Dedicated strategy for Proton Mail's Rooster editor
            ClaudeStrategy(), // Fast selection-based strategy for Claude Desktop
            ChromiumStrategy(),
            TextMarkerStrategy(),
            rangeBounds,

            // Tier: Reliable
            InsertionPointStrategy(), // For Mac Catalyst apps (Messages, etc.)
            elementTree,
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

            // For apps with a single dedicated strategy (Slack, Claude, Teams, etc.),
            // don't add fallback strategies - they would give incorrect positions.
            // Only add fallbacks for apps with multiple preferred strategies.
            if config.preferredStrategies.count > 1 {
                let preferredSet = Set(config.preferredStrategies)
                let remaining = allStrategies.filter { !preferredSet.contains($0.strategyType) }
                orderedStrategies.append(contentsOf: remaining)
            }
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
        for errorRange: PositionRange,
        in element: AXUIElement,
        text: String,
        parser: ContentParser,
        bundleID: String
    ) -> GeometryResult {
        // Performance profiling
        let (profilingState, profilingStartTime) = PerformanceProfiler.shared.beginInterval(.positionResolving, context: bundleID)
        defer { PerformanceProfiler.shared.endInterval(.positionResolving, state: profilingState, startTime: profilingStartTime) }

        // Check if this app uses a dedicated strategy (single preferred strategy = no fallback)
        let config = AppRegistry.shared.effectiveConfiguration(for: bundleID)
        let hasDedicatedStrategy = config.preferredStrategies.count == 1

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

        // FAIL-FAST: If app is already blocklisted, skip everything immediately
        if watchdogActive {
            Logger.debug("PositionResolver: Skipping - watchdog active for \(bundleID)", category: Logger.accessibility)
            return GeometryResult.unavailable(reason: "AX API unresponsive - skipping positioning")
        }

        // Check visibility BEFORE attempting positioning. AccessibilityBridge owns the atomic
        // reservation for this call.
        let isVisible = errorRange.utf16.map { AccessibilityBridge.isRangeVisible($0, in: element) } ?? true

        // FAIL-FAST: If visibility check caused blocklisting (timed out), abort immediately
        // This prevents wasting 50+ seconds trying strategies that will all fail
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.warning("PositionResolver: AX timeout detected - aborting positioning for \(bundleID)", category: Logger.accessibility)
            return GeometryResult.unavailable(reason: "AX API unresponsive (Copilot or overlay active?)")
        }

        if !isVisible {
            Logger.debug("PositionResolver: Range \(errorRange) is not visible - skipping positioning", category: Logger.accessibility)
            return GeometryResult.unavailable(reason: "Range not visible (scrolled out of view)")
        }

        // Get edit area frame for validation. AccessibilityBridge owns the reservation.
        let editAreaFrame = AccessibilityBridge.getEditAreaFrame(element)

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
            guard let range = errorRange.range(for: strategy.strategyType) else { continue }
            if let result = strategy.calculateGeometry(
                errorRange: range,
                element: element,
                text: text,
                parser: parser
            ) {
                // Check if this is an "unavailable" result - return immediately
                if result.isUnavailable {
                    Logger.debug("PositionResolver: Strategy \(strategy.strategyName) returned unavailable", category: Logger.accessibility)
                    return result
                }

                // Validate bounds are within edit area (unless strategy opts out)
                // Some strategies like ClaudeStrategy skip this because their bounds come from a different
                // coordinate system that's known to be correct for the target app
                let skipEditAreaValidation = result.metadata["skip_edit_area_validation"] as? Bool ?? false
                if !skipEditAreaValidation, let editArea = editAreaFrame {
                    // Edit area is in Quartz coordinates (from AX). Most strategies return Cocoa coordinates.
                    let boundsForValidation = CoordinateMapper.toQuartzCoordinates(result.bounds)
                    if !AccessibilityBridge.validateBoundsWithinEditArea(boundsForValidation, editAreaFrame: editArea) {
                        Logger.debug("PositionResolver: Strategy \(strategy.strategyName) bounds outside edit area. Bounds: \(boundsForValidation), EditArea: \(editArea)", category: Logger.accessibility)
                        // For apps with a single dedicated strategy, return unavailable immediately
                        // instead of trying fallback strategies that would give incorrect positions
                        if hasDedicatedStrategy {
                            return GeometryResult.unavailable(reason: "Text scrolled out of visible area")
                        }
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
