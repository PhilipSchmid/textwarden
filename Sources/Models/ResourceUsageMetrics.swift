// ResourceUsageMetrics.swift
// Resource usage statistics data model

import Foundation

/// Resource usage metrics for a specific time range
public struct ResourceUsageMetrics: Codable {
    // CPU Load metrics (Unix-style load averages - number of active threads/processes)
    public let cpuLoadMin: Double
    public let cpuLoadMax: Double
    public let cpuLoadAverage: Double
    public let cpuLoadMedian: Double  // Middle value (50th percentile)

    // System Load Averages (if available)
    public let systemLoad1mAverage: Double?
    public let systemLoad5mAverage: Double?
    public let systemLoad15mAverage: Double?

    // Memory metrics (bytes)
    public let memoryMin: UInt64
    public let memoryMax: UInt64
    public let memoryAverage: UInt64
    public let memoryMedian: UInt64  // Middle value (50th percentile)

    public let sampleCount: Int

    public init(
        cpuLoadMin: Double,
        cpuLoadMax: Double,
        cpuLoadAverage: Double,
        cpuLoadMedian: Double,
        systemLoad1mAverage: Double? = nil,
        systemLoad5mAverage: Double? = nil,
        systemLoad15mAverage: Double? = nil,
        memoryMin: UInt64,
        memoryMax: UInt64,
        memoryAverage: UInt64,
        memoryMedian: UInt64,
        sampleCount: Int
    ) {
        self.cpuLoadMin = cpuLoadMin
        self.cpuLoadMax = cpuLoadMax
        self.cpuLoadAverage = cpuLoadAverage
        self.cpuLoadMedian = cpuLoadMedian
        self.systemLoad1mAverage = systemLoad1mAverage
        self.systemLoad5mAverage = systemLoad5mAverage
        self.systemLoad15mAverage = systemLoad15mAverage
        self.memoryMin = memoryMin
        self.memoryMax = memoryMax
        self.memoryAverage = memoryAverage
        self.memoryMedian = memoryMedian
        self.sampleCount = sampleCount
    }
}
