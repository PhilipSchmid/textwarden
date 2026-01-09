//
//  PerformanceProfiler.swift
//  TextWarden
//
//  Performance profiling using OSSignposter for Instruments integration
//  and in-memory metrics collection for diagnostics export
//

import Foundation
import os

// MARK: - Profiled Operations

/// Categories of operations to profile
enum ProfiledOperation: String, CaseIterable {
    // Core analysis operations
    case textAnalysis = "text-analysis"
    case errorFiltering = "error-filtering"

    // Position resolution
    case positionResolving = "position-resolving"
    case strategyExecution = "strategy-execution"

    // Overlay operations
    case overlayShow = "overlay-show"
    case overlayHide = "overlay-hide"
    case overlayRebuild = "overlay-rebuild"
    case overlayRendering = "overlay-rendering"

    // Text monitoring
    case textExtraction = "text-extraction"
    case focusMonitoring = "focus-monitoring"
    case focusCoalescing = "focus-coalescing" // Tracks coalesced focus events

    // UI operations
    case popoverDisplay = "popover-display"
    case menuBarDisplay = "menu-bar-display"

    // Low-level operations
    case accessibilityQuery = "ax-query"
    case positionRefresh = "position-refresh"
}

// MARK: - Metrics Snapshot

/// Snapshot of metrics for a single operation type
struct OperationMetricsSnapshot: Codable {
    let count: Int
    let mean: Double
    let min: Double
    let max: Double
    let p50: Double
    let p90: Double
    let p95: Double
    let p99: Double
}

// MARK: - Operation Metrics

/// Ring buffer for recent operation durations with statistical calculations
final class OperationMetrics {
    private let maxSamples = 1000
    private var samples: [Double] = []
    private var totalCount: Int = 0
    private var totalSum: Double = 0

    func record(_ durationMs: Double) {
        samples.append(durationMs)
        if samples.count > maxSamples {
            samples.removeFirst()
        }
        totalCount += 1
        totalSum += durationMs
    }

    func snapshot() -> OperationMetricsSnapshot {
        guard !samples.isEmpty else {
            return OperationMetricsSnapshot(
                count: 0, mean: 0, min: 0, max: 0,
                p50: 0, p90: 0, p95: 0, p99: 0
            )
        }

        let sorted = samples.sorted()
        return OperationMetricsSnapshot(
            count: totalCount,
            mean: totalSum / Double(totalCount),
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            p50: percentile(sorted, 0.50),
            p90: percentile(sorted, 0.90),
            p95: percentile(sorted, 0.95),
            p99: percentile(sorted, 0.99)
        )
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[index]
    }

    func reset() {
        samples.removeAll()
        totalCount = 0
        totalSum = 0
    }
}

// MARK: - Performance Profiler

/// Thread-safe singleton for performance profiling using OSSignposter
final class PerformanceProfiler: @unchecked Sendable {
    static let shared = PerformanceProfiler()

    private let signposter: OSSignposter
    private let metricsLock = NSLock()
    private var operationMetrics: [ProfiledOperation: OperationMetrics] = [:]

    private init() {
        signposter = OSSignposter(
            subsystem: "io.textwarden.TextWarden",
            category: "Performance"
        )
        // Initialize metrics for all operations
        for operation in ProfiledOperation.allCases {
            operationMetrics[operation] = OperationMetrics()
        }
    }

    // MARK: - Interval-based Profiling

    /// Begin a profiled interval, returns state for ending the interval
    func beginInterval(_ operation: ProfiledOperation, context: String = "") -> (OSSignpostIntervalState, CFAbsoluteTime) {
        let id = signposter.makeSignpostID()
        // Use a static name "Operation" with dynamic operation/context in the message
        let state = signposter.beginInterval("Operation", id: id, "\(operation.rawValue) \(context)")
        return (state, CFAbsoluteTimeGetCurrent())
    }

    /// End a profiled interval and record metrics
    func endInterval(_ operation: ProfiledOperation, state: OSSignpostIntervalState, startTime: CFAbsoluteTime) {
        signposter.endInterval("Operation", state)

        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to ms
        recordMetric(operation, durationMs: duration)
    }

    // MARK: - Block-based Profiling

    /// Profile a synchronous block of code
    func measure<T>(_ operation: ProfiledOperation, context: String = "", block: () throws -> T) rethrows -> T {
        let (state, startTime) = beginInterval(operation, context: context)
        defer { endInterval(operation, state: state, startTime: startTime) }
        return try block()
    }

    /// Profile an async block of code
    func measureAsync<T>(_ operation: ProfiledOperation, context: String = "", block: () async throws -> T) async rethrows -> T {
        let (state, startTime) = beginInterval(operation, context: context)
        defer { endInterval(operation, state: state, startTime: startTime) }
        return try await block()
    }

    // MARK: - Metrics Collection

    private func recordMetric(_ operation: ProfiledOperation, durationMs: Double) {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        operationMetrics[operation]?.record(durationMs)
    }

    /// Get current metrics snapshot for all operations
    func getMetricsSnapshot() -> [String: OperationMetricsSnapshot] {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        var snapshot: [String: OperationMetricsSnapshot] = [:]
        for (operation, metrics) in operationMetrics {
            snapshot[operation.rawValue] = metrics.snapshot()
        }
        return snapshot
    }

    /// Reset all metrics (useful for testing)
    func resetMetrics() {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        for operation in ProfiledOperation.allCases {
            operationMetrics[operation] = OperationMetrics()
        }
    }
}
