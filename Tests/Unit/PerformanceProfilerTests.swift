//
//  PerformanceProfilerTests.swift
//  TextWarden
//
//  Unit tests for PerformanceProfiler and OperationMetrics
//

@testable import TextWarden
import XCTest

final class PerformanceProfilerTests: XCTestCase {
    // MARK: - Setup

    override func setUp() {
        super.setUp()
        // Reset metrics before each test
        PerformanceProfiler.shared.resetMetrics()
    }

    // MARK: - OperationMetrics Tests

    func testOperationMetricsRecordsSamples() {
        let metrics = OperationMetrics()

        metrics.record(10.0)
        metrics.record(20.0)
        metrics.record(30.0)

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.count, 3, "Should have recorded 3 samples")
        XCTAssertEqual(snapshot.mean, 20.0, accuracy: 0.001, "Mean should be 20.0")
        XCTAssertEqual(snapshot.min, 10.0, accuracy: 0.001, "Min should be 10.0")
        XCTAssertEqual(snapshot.max, 30.0, accuracy: 0.001, "Max should be 30.0")
    }

    func testOperationMetricsPercentiles() {
        let metrics = OperationMetrics()

        // Record 100 samples: 1, 2, 3, ... 100
        for i in 1 ... 100 {
            metrics.record(Double(i))
        }

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.count, 100, "Should have recorded 100 samples")
        XCTAssertEqual(snapshot.p50, 50.0, accuracy: 1.0, "P50 should be around 50")
        XCTAssertEqual(snapshot.p90, 90.0, accuracy: 1.0, "P90 should be around 90")
        XCTAssertEqual(snapshot.p95, 95.0, accuracy: 1.0, "P95 should be around 95")
        XCTAssertEqual(snapshot.p99, 99.0, accuracy: 1.0, "P99 should be around 99")
    }

    func testOperationMetricsEmptySnapshot() {
        let metrics = OperationMetrics()
        let snapshot = metrics.snapshot()

        XCTAssertEqual(snapshot.count, 0, "Empty metrics should have 0 count")
        XCTAssertEqual(snapshot.mean, 0, "Empty metrics should have 0 mean")
        XCTAssertEqual(snapshot.min, 0, "Empty metrics should have 0 min")
        XCTAssertEqual(snapshot.max, 0, "Empty metrics should have 0 max")
    }

    func testOperationMetricsRingBuffer() {
        let metrics = OperationMetrics()

        // Record more than maxSamples (1000)
        for i in 1 ... 1500 {
            metrics.record(Double(i))
        }

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.count, 1500, "Total count should track all samples")
        // Ring buffer should contain samples 501-1500
        XCTAssertEqual(snapshot.min, 501.0, accuracy: 0.001, "Min should be from recent samples")
        XCTAssertEqual(snapshot.max, 1500.0, accuracy: 0.001, "Max should be from recent samples")
    }

    func testOperationMetricsReset() {
        let metrics = OperationMetrics()

        metrics.record(100.0)
        metrics.record(200.0)
        metrics.reset()

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.count, 0, "After reset, count should be 0")
    }

    // MARK: - PerformanceProfiler Tests

    func testProfilerMeasureBlock() {
        let result = PerformanceProfiler.shared.measure(.textAnalysis, context: "test") {
            // Simulate some work
            Thread.sleep(forTimeInterval: 0.01) // 10ms
            return 42
        }

        XCTAssertEqual(result, 42, "Should return the block's result")

        let snapshot = PerformanceProfiler.shared.getMetricsSnapshot()
        guard let textAnalysisMetrics = snapshot["text-analysis"] else {
            XCTFail("Should have text-analysis metrics")
            return
        }

        XCTAssertEqual(textAnalysisMetrics.count, 1, "Should have 1 sample")
        XCTAssertGreaterThan(textAnalysisMetrics.mean, 5.0, "Mean should be at least 5ms")
        XCTAssertLessThan(textAnalysisMetrics.mean, 100.0, "Mean should be less than 100ms")
    }

    func testProfilerIntervalBasedProfiling() {
        let (state, startTime) = PerformanceProfiler.shared.beginInterval(.positionResolving, context: "test")

        // Simulate work
        Thread.sleep(forTimeInterval: 0.01) // 10ms

        PerformanceProfiler.shared.endInterval(.positionResolving, state: state, startTime: startTime)

        let snapshot = PerformanceProfiler.shared.getMetricsSnapshot()
        guard let metrics = snapshot["position-resolving"] else {
            XCTFail("Should have position-resolving metrics")
            return
        }

        XCTAssertEqual(metrics.count, 1, "Should have 1 sample")
        XCTAssertGreaterThan(metrics.mean, 5.0, "Mean should be at least 5ms")
    }

    func testProfilerResetMetrics() {
        // Record some metrics
        _ = PerformanceProfiler.shared.measure(.menuBarDisplay) {
            Thread.sleep(forTimeInterval: 0.001)
        }

        PerformanceProfiler.shared.resetMetrics()

        let snapshot = PerformanceProfiler.shared.getMetricsSnapshot()
        for (_, metrics) in snapshot {
            XCTAssertEqual(metrics.count, 0, "All metrics should be reset to 0")
        }
    }

    func testProfilerAllOperationsHaveMetrics() {
        let snapshot = PerformanceProfiler.shared.getMetricsSnapshot()

        // Verify all ProfiledOperation cases have entries
        let expectedOperations = [
            "position-resolving",
            "strategy-execution",
            "text-analysis",
            "popover-display",
            "menu-bar-display",
            "overlay-rendering",
            "ax-query",
        ]

        for operation in expectedOperations {
            XCTAssertNotNil(snapshot[operation], "Should have metrics for \(operation)")
        }
    }

    // MARK: - OperationMetricsSnapshot Codable Tests

    func testOperationMetricsSnapshotCodable() throws {
        let snapshot = OperationMetricsSnapshot(
            count: 100,
            mean: 25.5,
            min: 1.0,
            max: 100.0,
            p50: 25.0,
            p90: 90.0,
            p95: 95.0,
            p99: 99.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OperationMetricsSnapshot.self, from: data)

        XCTAssertEqual(decoded.count, snapshot.count)
        XCTAssertEqual(decoded.mean, snapshot.mean, accuracy: 0.001)
        XCTAssertEqual(decoded.min, snapshot.min, accuracy: 0.001)
        XCTAssertEqual(decoded.max, snapshot.max, accuracy: 0.001)
        XCTAssertEqual(decoded.p50, snapshot.p50, accuracy: 0.001)
        XCTAssertEqual(decoded.p90, snapshot.p90, accuracy: 0.001)
        XCTAssertEqual(decoded.p95, snapshot.p95, accuracy: 0.001)
        XCTAssertEqual(decoded.p99, snapshot.p99, accuracy: 0.001)
    }

    // MARK: - Async Tests

    func testProfilerMeasureAsync() async {
        let result = await PerformanceProfiler.shared.measureAsync(.textAnalysis, context: "async-test") {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return "async result"
        }

        XCTAssertEqual(result, "async result", "Should return the async block's result")

        let snapshot = PerformanceProfiler.shared.getMetricsSnapshot()
        guard let metrics = snapshot["text-analysis"] else {
            XCTFail("Should have text-analysis metrics")
            return
        }

        XCTAssertGreaterThanOrEqual(metrics.count, 1, "Should have at least 1 sample")
    }
}
