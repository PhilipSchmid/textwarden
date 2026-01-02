// ResourceMonitor.swift
// Background resource monitoring service

import Foundation

/// Background service for periodic resource monitoring
public class ResourceMonitor {
    public static let shared = ResourceMonitor()

    private var samplingTimer: Timer?
    private let samplingInterval: TimeInterval = TimingConstants.resourceSampling
    private let samplingQueue = DispatchQueue(label: "com.textwarden.resource-monitor", qos: .utility)

    /// Serial queue to protect isMonitoring flag from concurrent access
    private let stateQueue = DispatchQueue(label: "com.textwarden.resource-monitor.state", qos: .userInitiated)
    private var _isMonitoring = false

    private init() {}

    // MARK: - Public Interface

    /// Start background resource monitoring
    public func startMonitoring() {
        // Thread-safe check-and-set to prevent duplicate starts
        let shouldStart = stateQueue.sync { () -> Bool in
            guard !_isMonitoring else { return false }
            _isMonitoring = true
            return true
        }

        guard shouldStart else { return }

        // Start timer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            samplingTimer = Timer.scheduledTimer(
                withTimeInterval: samplingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.collectSwiftAppSample()
            }

            // Fire immediately
            collectSwiftAppSample()
        }

        Logger.debug("Started resource monitoring (interval: \(samplingInterval)s)", category: Logger.performance)
    }

    /// Stop background resource monitoring
    public func stopMonitoring() {
        // Thread-safe check-and-set to prevent duplicate stops
        let shouldStop = stateQueue.sync { () -> Bool in
            guard _isMonitoring else { return false }
            _isMonitoring = false
            return true
        }

        guard shouldStop else { return }

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
