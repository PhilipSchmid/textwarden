//
//  PositionCache.swift
//  TextWarden
//
//  High-performance cache for position calculations
//  Dramatically reduces expensive AX API calls
//

import Foundation
import ApplicationServices

/// High-performance cache for geometry calculations
/// Uses LRU eviction with hit count weighting and time-based expiration
class PositionCache {

    // MARK: - Cache Entry

    private struct CacheEntry {
        let result: GeometryResult
        let timestamp: Date
        var hitCount: Int

        var age: TimeInterval {
            Date().timeIntervalSince(timestamp)
        }
    }

    // MARK: - Properties

    private var cache: [CacheKey: CacheEntry] = [:]
    private let maxEntries = 100
    private let maxAge: TimeInterval = TimingConstants.positionCacheExpiration
    private let queue = DispatchQueue(label: "com.textwarden.position-cache", qos: .userInitiated)

    // Statistics
    private var hits: Int = 0
    private var misses: Int = 0

    // MARK: - Cache Operations

    /// Get cached result for key
    /// Returns nil if not in cache or expired
    func get(key: CacheKey) -> GeometryResult? {
        return queue.sync {
            guard let entry = cache[key] else {
                misses += 1
                return nil
            }

            // Check if entry is still fresh
            if entry.age > maxAge {
                cache.removeValue(forKey: key)
                misses += 1
                return nil
            }

            cache[key] = CacheEntry(
                result: entry.result,
                timestamp: entry.timestamp,
                hitCount: entry.hitCount + 1
            )

            hits += 1
            Logger.debug("PositionCache hit for \(key.description) (age: \(String(format: "%.2f", entry.age))s, hits: \(entry.hitCount + 1))")

            return entry.result
        }
    }

    /// Store result in cache
    /// Automatically evicts old entries if needed
    func store(_ result: GeometryResult, for key: CacheKey) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Evict old entries if at capacity
            if self.cache.count >= self.maxEntries {
                self.evictOldest()
            }

            self.cache[key] = CacheEntry(
                result: result,
                timestamp: Date(),
                hitCount: 0
            )

            Logger.debug("PositionCache stored result for \(key.description)")
        }
    }

    /// Clear all cache entries
    func clear() {
        queue.async { [weak self] in
            self?.cache.removeAll()
            self?.hits = 0
            self?.misses = 0
            Logger.debug("PositionCache cleared")
        }
    }

    // MARK: - Eviction

    private func evictOldest() {
        // LRU eviction with hit count weighting
        // Score = hitCount - (age * 10)
        // Lower score = more likely to be evicted

        let sorted = cache.sorted { entry1, entry2 in
            let score1 = Double(entry1.value.hitCount) - (entry1.value.age * 10)
            let score2 = Double(entry2.value.hitCount) - (entry2.value.age * 10)
            return score1 < score2
        }

        if let oldest = sorted.first {
            cache.removeValue(forKey: oldest.key)
            Logger.debug("PositionCache evicted \(oldest.key.description) (hits: \(oldest.value.hitCount), age: \(String(format: "%.2f", oldest.value.age))s)")
        }
    }

    // MARK: - Statistics

    /// Get cache hit rate (0.0 to 1.0)
    func hitRate() -> Double {
        queue.sync {
            let total = hits + misses
            guard total > 0 else { return 0.0 }
            return Double(hits) / Double(total)
        }
    }

    /// Get cache statistics for debugging
    func statistics() -> CacheStatistics {
        return queue.sync {
            // Calculate hit rate inline to avoid deadlock (hitRate() also uses queue.sync)
            let total = hits + misses
            let rate = total > 0 ? Double(hits) / Double(total) : 0.0
            return CacheStatistics(
                entries: cache.count,
                hits: hits,
                misses: misses,
                hitRate: rate
            )
        }
    }
}

// MARK: - Cache Key

/// Key for cache lookups
/// Combines element identity, text range, and text content hash
struct CacheKey: Hashable {
    let elementHash: Int
    let range: NSRange
    let textHash: Int

    init(element: AXUIElement, range: NSRange, textHash: Int) {
        // Note: This assumes element pointer stays valid during cache lifetime
        self.elementHash = unsafeBitCast(element, to: Int.self)
        self.range = range
        self.textHash = textHash
    }

    var description: String {
        return "element:\(elementHash) range:(\(range.location),\(range.length)) text:\(textHash)"
    }
}

// MARK: - Cache Statistics

/// Statistics for cache performance monitoring
struct CacheStatistics {
    let entries: Int
    let hits: Int
    let misses: Int
    let hitRate: Double

    var description: String {
        return "PositionCache: \(entries) entries, \(hits) hits, \(misses) misses, \(String(format: "%.1f%%", hitRate * 100)) hit rate"
    }
}
