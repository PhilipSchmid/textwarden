//
//  ReadabilityTipsCache.swift
//  TextWarden
//
//  Thread-safe LRU cache for AI-generated readability tips.
//  Caches contextual tips to avoid repeated API calls for the same text.
//

import Foundation

/// Cache key combining text hash and target audience
struct ReadabilityTipsCacheKey: Hashable {
    let textHash: Int
    let targetAudience: String

    init(text: String, targetAudience: String) {
        // Use a stable hash of the text (first 500 chars to keep key generation fast)
        let truncated = String(text.prefix(500))
        textHash = truncated.hashValue
        self.targetAudience = targetAudience
    }
}

/// Cached readability tips with metadata
struct CachedReadabilityTips {
    let tips: [String]
    let score: Int
    let timestamp: Date

    /// Check if cache entry is still valid (5 minute TTL)
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 300 // 5 minutes
    }
}

/// Thread-safe LRU cache for AI-generated readability tips.
/// Uses text hash + audience as key, stores array of tip strings.
final class ReadabilityTipsCache: @unchecked Sendable {
    private var cache: [ReadabilityTipsCacheKey: CachedReadabilityTips] = [:]
    private var accessOrder: [ReadabilityTipsCacheKey] = []
    private let queue = DispatchQueue(label: "com.textwarden.readabilityTipsCache")
    private let maxEntries: Int

    init(maxEntries: Int = 30) {
        self.maxEntries = maxEntries
    }

    /// Get cached tips for text and audience.
    /// Returns nil if not cached or expired.
    func get(text: String, targetAudience: String) -> [String]? {
        let key = ReadabilityTipsCacheKey(text: text, targetAudience: targetAudience)
        return queue.sync {
            guard let cached = cache[key], cached.isValid else {
                // Remove expired entry if present
                if cache[key] != nil {
                    cache.removeValue(forKey: key)
                    accessOrder.removeAll { $0 == key }
                }
                return nil
            }
            // Move to end for LRU
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
                accessOrder.append(key)
            }
            return cached.tips
        }
    }

    /// Store tips with LRU eviction if cache is full.
    func set(text: String, targetAudience: String, tips: [String], score: Int) {
        let key = ReadabilityTipsCacheKey(text: text, targetAudience: targetAudience)
        queue.sync {
            // Remove existing entry from access order
            if cache[key] != nil {
                accessOrder.removeAll { $0 == key }
            } else if cache.count >= maxEntries, !accessOrder.isEmpty {
                // LRU eviction
                let oldestKey = accessOrder.removeFirst()
                cache.removeValue(forKey: oldestKey)
            }

            cache[key] = CachedReadabilityTips(
                tips: tips,
                score: score,
                timestamp: Date()
            )
            accessOrder.append(key)
        }
    }

    /// Clear all cached tips
    func clear() {
        queue.sync {
            cache.removeAll()
            accessOrder.removeAll()
        }
    }

    /// Current number of cached entries
    var count: Int {
        queue.sync { cache.count }
    }
}
