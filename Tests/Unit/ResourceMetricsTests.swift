// ResourceMetricsTests.swift
// Unit tests for resource metrics models

@testable import TextWarden
import XCTest

final class ResourceMetricsTests: XCTestCase {
    func testResourceComponentEnum() {
        // Test all cases exist
        XCTAssertEqual(ResourceComponent.allCases.count, 3)

        // Test identifiers
        XCTAssertEqual(ResourceComponent.swiftApp.identifier, "Swift Application")
        XCTAssertEqual(ResourceComponent.grammarEngine.identifier, "Grammar Engine (Rust)")
        XCTAssertEqual(ResourceComponent.styleEngine.identifier, "Style Engine (Rust)")

        // Test colors are defined
        XCTAssertNotNil(ResourceComponent.swiftApp.color)
        XCTAssertNotNil(ResourceComponent.grammarEngine.color)
        XCTAssertNotNil(ResourceComponent.styleEngine.color)
    }

    func testResourceMetricSampleCreation() {
        let sample = ResourceMetricSample(
            component: .grammarEngine,
            cpuPercent: 25.5,
            memoryBytes: 50_000_000
        )

        XCTAssertEqual(sample.component, .grammarEngine)
        XCTAssertEqual(sample.cpuPercent, 25.5)
        XCTAssertEqual(sample.memoryBytes, 50_000_000)
        XCTAssertNotNil(sample.id)
        XCTAssertNotNil(sample.timestamp)
        XCTAssertNil(sample.cpuPercentUserMode)
        XCTAssertNil(sample.cpuPercentSystemMode)
        XCTAssertNil(sample.memoryVirtualBytes)
        XCTAssertNil(sample.memoryPeakBytes)
        XCTAssertNil(sample.analysisSessionId)
    }

    func testResourceMetricSampleWithOptionalFields() {
        let sessionId = UUID()
        let sample = ResourceMetricSample(
            component: .swiftApp,
            cpuPercent: 50.0,
            memoryBytes: 100_000_000,
            cpuUserMode: 30.0,
            cpuSystemMode: 20.0,
            memoryVirtual: 200_000_000,
            memoryPeak: 150_000_000,
            sessionId: sessionId
        )

        XCTAssertEqual(sample.cpuPercentUserMode, 30.0)
        XCTAssertEqual(sample.cpuPercentSystemMode, 20.0)
        XCTAssertEqual(sample.memoryVirtualBytes, 200_000_000)
        XCTAssertEqual(sample.memoryPeakBytes, 150_000_000)
        XCTAssertEqual(sample.analysisSessionId, sessionId)
    }

    func testResourceMetricSampleCodable() throws {
        let original = ResourceMetricSample(
            component: .grammarEngine,
            cpuPercent: 42.0,
            memoryBytes: 75_000_000,
            memoryVirtual: 150_000_000
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ResourceMetricSample.self, from: data)

        XCTAssertEqual(decoded.component, original.component)
        XCTAssertEqual(decoded.cpuPercent, original.cpuPercent)
        XCTAssertEqual(decoded.memoryBytes, original.memoryBytes)
        XCTAssertEqual(decoded.memoryVirtualBytes, original.memoryVirtualBytes)
    }

    func testComponentResourceStatsStructure() {
        let stats = ComponentResourceStats(
            component: .swiftApp,
            cpuMean: 25.0,
            cpuMedian: 20.0,
            cpuP90: 45.0,
            cpuP95: 50.0,
            cpuP99: 60.0,
            cpuMax: 70.0,
            memoryMean: 50_000_000,
            memoryMedian: 48_000_000,
            memoryP90: 60_000_000,
            memoryP95: 65_000_000,
            memoryP99: 70_000_000,
            memoryMax: 75_000_000,
            memoryPeak: 80_000_000,
            cpuLoad1m: 30.0,
            cpuLoad5m: 25.0,
            cpuLoad15m: 20.0,
            sampleCount: 100
        )

        XCTAssertEqual(stats.component, .swiftApp)
        XCTAssertEqual(stats.cpuMean, 25.0)
        XCTAssertEqual(stats.memoryMean, 50_000_000)
        XCTAssertEqual(stats.sampleCount, 100)
        XCTAssertEqual(stats.cpuLoad1m, 30.0)
    }
}
