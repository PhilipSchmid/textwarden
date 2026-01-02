//
//  AIRephraseCache.swift
//  TextWarden
//
//  Thread-safe LRU cache for AI rephrase suggestions.
//  Extracted from AnalysisCoordinator to reduce file size and improve maintainability.
//

import Foundation

/// Thread-safe LRU cache for AI rephrase suggestions.
/// Uses a dictionary for O(1) lookup and an array to track access order.
/// Note: Swift's Dictionary does NOT maintain insertion order, so we use
/// a separate array to track LRU ordering.
final class AIRephraseCache: @unchecked Sendable {
    private var cache: [String: String] = [:]
    private var accessOrder: [String] = [] // Oldest at front, newest at back
    private let queue = DispatchQueue(label: "com.textwarden.aiRephraseCache")
    private let maxEntries: Int

    init(maxEntries: Int = 50) {
        self.maxEntries = maxEntries
    }

    /// Get cached rephrase for a sentence.
    /// Marks the entry as recently used (moves to end of access order).
    func get(_ key: String) -> String? {
        queue.sync {
            guard let value = cache[key] else { return nil }
            // Move to end to mark as recently used (LRU semantics)
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
                accessOrder.append(key)
            }
            return value
        }
    }

    /// Store rephrase with LRU eviction if cache is full.
    func set(_ key: String, value: String) {
        queue.sync {
            // If updating existing entry, remove from access order first
            if cache[key] != nil {
                if let index = accessOrder.firstIndex(of: key) {
                    accessOrder.remove(at: index)
                }
            } else if cache.count >= maxEntries, !accessOrder.isEmpty {
                // LRU eviction - remove oldest entry (first in access order)
                let oldestKey = accessOrder.removeFirst()
                cache.removeValue(forKey: oldestKey)
            }
            cache[key] = value
            accessOrder.append(key)
        }
    }

    /// Current number of cached entries
    var count: Int {
        queue.sync { cache.count }
    }
}
