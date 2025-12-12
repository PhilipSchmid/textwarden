// SystemMetricsTests.swift
// Unit tests for SystemMetrics utility

import XCTest
@testable import TextWarden

final class SystemMetricsTests: XCTestCase {

    func testGetMemoryUsage() {
        let memory = SystemMetrics.getMemoryUsage()

        XCTAssertGreaterThan(memory, 0, "Memory usage should be positive")
        XCTAssertLessThan(memory, 16_000_000_000, "Memory should be < 16GB (sanity check)")

        XCTContext.runActivity(named: "Memory usage") { activity in
            let attachment = XCTAttachment(string: ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    func testGetVirtualMemorySize() {
        let virtualMemory = SystemMetrics.getVirtualMemorySize()

        XCTAssertGreaterThan(virtualMemory, 0, "Virtual memory should be positive")

        XCTContext.runActivity(named: "Virtual memory size") { activity in
            let attachment = XCTAttachment(string: ByteCountFormatter.string(fromByteCount: Int64(virtualMemory), countStyle: .memory))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    func testGetCPUUsage() {
        let cpu = SystemMetrics.getCPUUsage()

        XCTAssertGreaterThanOrEqual(cpu, 0, "CPU usage should be non-negative")

        let coreCount = ProcessInfo.processInfo.processorCount
        // CPU can exceed 100% on multi-core systems (100% per core)
        XCTAssertLessThanOrEqual(cpu, 100.0 * Double(coreCount) * 2, "CPU should be reasonable")

        XCTContext.runActivity(named: "CPU usage") { activity in
            let attachment = XCTAttachment(string: String(format: "%.2f%%", cpu))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    func testGetResourceSnapshot() {
        let snapshot = SystemMetrics.getResourceSnapshot()

        XCTAssertGreaterThan(snapshot.memory, 0)
        XCTAssertGreaterThan(snapshot.virtualMemory, 0)
        XCTAssertGreaterThanOrEqual(snapshot.cpu, 0)

        XCTContext.runActivity(named: "Resource snapshot") { activity in
            let details = "CPU: \(String(format: "%.2f%%", snapshot.cpu)), Memory: \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.memory), countStyle: .memory))"
            let attachment = XCTAttachment(string: details)
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    func testConsistentReadings() {
        // Take multiple readings to ensure consistency
        var readings: [(cpu: Double, memory: UInt64)] = []

        for _ in 0..<5 {
            let snapshot = SystemMetrics.getResourceSnapshot()
            readings.append((cpu: snapshot.cpu, memory: snapshot.memory))
            Thread.sleep(forTimeInterval: 0.1)
        }

        // All readings should be valid
        for reading in readings {
            XCTAssertGreaterThanOrEqual(reading.cpu, 0)
            XCTAssertGreaterThan(reading.memory, 0)
        }
    }

    func testPerformanceOfMemoryReading() {
        measure {
            for _ in 0..<100 {
                _ = SystemMetrics.getMemoryUsage()
            }
        }
        // Should be very fast (< 10ms for 100 calls)
    }

    func testPerformanceOfCPUReading() {
        measure {
            for _ in 0..<100 {
                _ = SystemMetrics.getCPUUsage()
            }
        }
        // Should be fast enough for periodic sampling
    }
}
