//
//  PositionCache.swift
//  TextWarden
//
//  High-performance cache for position calculations
//  Dramatically reduces expensive AX API calls
//

import ApplicationServices
import Foundation

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
        queue.sync {
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
            Logger.debug("PositionCache hit for \(key.description) (age: \(String(format: "%.2f", entry.age))s, hits: \(entry.hitCount + 1))", category: Logger.performance)

            return entry.result
        }
    }

    /// Store result in cache.
    /// Automatically evicts old entries if needed.
    /// Uses sync to prevent race conditions with get().
    func store(_ result: GeometryResult, for key: CacheKey) {
        queue.sync {
            // Evict old entries if at capacity
            if self.cache.count >= self.maxEntries {
                self.evictOldest()
            }

            self.cache[key] = CacheEntry(
                result: result,
                timestamp: Date(),
                hitCount: 0
            )

            Logger.debug("PositionCache stored result for \(key.description)", category: Logger.performance)
        }
    }

    /// Clear all cache entries.
    /// Uses sync to ensure cache is cleared before returning.
    func clear() {
        queue.sync {
            self.cache.removeAll()
            self.hits = 0
            self.misses = 0
            Logger.debug("PositionCache cleared", category: Logger.performance)
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
            Logger.debug("PositionCache evicted \(oldest.key.description) (hits: \(oldest.value.hitCount), age: \(String(format: "%.2f", oldest.value.age))s)", category: Logger.performance)
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
        queue.sync {
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

/// Key for cache lookups.
/// Combines element identity (PID + role + identifier), text range, and text content hash.
/// Uses stable identifiers instead of pointer addresses to avoid cache collisions
/// when elements are released and reallocated.
struct CacheKey: Hashable {
    let pid: pid_t
    let elementRole: String
    let elementIdentifier: String
    let range: NSRange
    let textHash: Int

    init(element: AXUIElement, range: NSRange, textHash: Int) {
        // Use PID + element attributes for stable identification
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        self.pid = pid

        // Get element role (e.g., "AXTextArea", "AXTextField")
        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String
        {
            elementRole = role
        } else {
            elementRole = "unknown"
        }

        // Get element identifier if available (some apps provide unique IDs)
        var identifierValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue) == .success,
           let identifier = identifierValue as? String
        {
            elementIdentifier = identifier
        } else {
            // Fall back to element description or position hash for uniqueness
            var descValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue) == .success,
               let desc = descValue as? String
            {
                elementIdentifier = desc
            } else {
                // Use frame position as a last resort (less stable but better than pointer)
                var posValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
                   let positionValue = posValue,
                   CFGetTypeID(positionValue) == AXValueGetTypeID()
                {
                    var point = CGPoint.zero
                    // Safe cast after type check
                    let axValue = positionValue as! AXValue
                    if AXValueGetValue(axValue, .cgPoint, &point) {
                        elementIdentifier = "pos:\(Int(point.x)),\(Int(point.y))"
                    } else {
                        elementIdentifier = "fallback"
                    }
                } else {
                    elementIdentifier = "fallback"
                }
            }
        }

        self.range = range
        self.textHash = textHash
    }

    var description: String {
        "pid:\(pid) role:\(elementRole) id:\(elementIdentifier) range:(\(range.location),\(range.length)) text:\(textHash)"
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
        "PositionCache: \(entries) entries, \(hits) hits, \(misses) misses, \(String(format: "%.1f%%", hitRate * 100)) hit rate"
    }
}
