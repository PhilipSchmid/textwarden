// ResourceMetrics.swift
// Data models for resource monitoring metrics

import Foundation

/// A single resource measurement sample
public struct ResourceMetricSample: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let component: ResourceComponent

    // CPU Load Metrics (Unix-style load averages)
    public let processLoad: Double // Process CPU load (active threads)
    public let systemLoad1m: Double? // System 1-minute load average
    public let systemLoad5m: Double? // System 5-minute load average
    public let systemLoad15m: Double? // System 15-minute load average

    // Legacy CPU percentage (deprecated, kept for backward compatibility)
    public let cpuPercent: Double // Deprecated: use processLoad instead

    // Memory Metrics
    public let memoryBytes: UInt64 // Physical memory (RSS/phys_footprint)
    public let memoryVirtualBytes: UInt64? // Optional: Virtual memory
    public let memoryPeakBytes: UInt64? // Optional: Peak since last reset

    // Context
    public let analysisSessionId: UUID? // Link to DetailedAnalysisSession if applicable

    public init(
        component: ResourceComponent,
        processLoad: Double,
        systemLoad1m: Double? = nil,
        systemLoad5m: Double? = nil,
        systemLoad15m: Double? = nil,
        memoryBytes: UInt64,
        memoryVirtual: UInt64? = nil,
        memoryPeak: UInt64? = nil,
        sessionId: UUID? = nil
    ) {
        id = UUID()
        timestamp = Date()
        self.component = component
        self.processLoad = processLoad
        self.systemLoad1m = systemLoad1m
        self.systemLoad5m = systemLoad5m
        self.systemLoad15m = systemLoad15m
        cpuPercent = processLoad // For backward compatibility
        self.memoryBytes = memoryBytes
        memoryVirtualBytes = memoryVirtual
        memoryPeakBytes = memoryPeak
        analysisSessionId = sessionId
    }

    /// Internal initializer for downsampling (preserves custom timestamp)
    init(
        timestamp: Date,
        component: ResourceComponent,
        processLoad: Double,
        memoryBytes: UInt64,
        systemLoad1m: Double? = nil,
        systemLoad5m: Double? = nil,
        systemLoad15m: Double? = nil
    ) {
        id = UUID()
        self.timestamp = timestamp
        self.component = component
        self.processLoad = processLoad
        self.systemLoad1m = systemLoad1m
        self.systemLoad5m = systemLoad5m
        self.systemLoad15m = systemLoad15m
        cpuPercent = processLoad
        self.memoryBytes = memoryBytes
        memoryVirtualBytes = nil
        memoryPeakBytes = nil
        analysisSessionId = nil
    }
}

/// Aggregated statistics for a component
public struct ComponentResourceStats: Codable {
    public let component: ResourceComponent

    // CPU Statistics (in percent)
    public let cpuMean: Double
    public let cpuMedian: Double
    public let cpuP90: Double
    public let cpuP95: Double
    public let cpuP99: Double
    public let cpuMax: Double

    // Memory Statistics (in bytes)
    public let memoryMean: UInt64
    public let memoryMedian: UInt64
    public let memoryP90: UInt64
    public let memoryP95: UInt64
    public let memoryP99: UInt64
    public let memoryMax: UInt64
    public let memoryPeak: UInt64

    // Load Averages (CPU only, similar to Unix `top`)
    public let cpuLoad1m: Double? // 1-minute average
    public let cpuLoad5m: Double? // 5-minute average
    public let cpuLoad15m: Double? // 15-minute average

    public let sampleCount: Int
}
