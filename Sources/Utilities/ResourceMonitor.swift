// ResourceMonitor.swift
// Background resource monitoring service

import Foundation

/// Background service for periodic resource monitoring
public class ResourceMonitor {
    public static let shared = ResourceMonitor()

    private var samplingTimer: Timer?
    private let samplingInterval: TimeInterval = 5.0  // 5 seconds
    private let samplingQueue = DispatchQueue(label: "com.textwarden.resource-monitor", qos: .utility)

    private var isMonitoring = false

    private init() {}

    // MARK: - Public Interface

    /// Start background resource monitoring
    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        // Start timer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.samplingTimer = Timer.scheduledTimer(
                withTimeInterval: self.samplingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.collectSwiftAppSample()
            }

            // Fire immediately
            self.collectSwiftAppSample()
        }

        Logger.debug("Started resource monitoring (interval: \(samplingInterval)s)", category: Logger.performance)
    }

    /// Stop background resource monitoring
    public func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false

        DispatchQueue.main.async { [weak self] in
            self?.samplingTimer?.invalidate()
            self?.samplingTimer = nil
        }

        Logger.debug("Stopped resource monitoring", category: Logger.performance)
    }

    // MARK: - Private Methods

    private func collectSwiftAppSample() {
        samplingQueue.async {
            let snapshot = SystemMetrics.getResourceSnapshot()

            let sample = ResourceMetricSample(
                component: .swiftApp,
                processLoad: snapshot.processLoad,
                systemLoad1m: snapshot.systemLoad1m,
                systemLoad5m: snapshot.systemLoad5m,
                systemLoad15m: snapshot.systemLoad15m,
                memoryBytes: snapshot.memory,
                memoryVirtual: snapshot.virtualMemory
            )

            // Record to UserStatistics
            DispatchQueue.main.async {
                UserStatistics.shared.recordResourceSample(sample)
            }
        }
    }
}
