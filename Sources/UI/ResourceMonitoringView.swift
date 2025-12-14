//
//  ResourceMonitoringView.swift
//  TextWarden
//
//  Resource monitoring view showing CPU and memory usage.
//

import SwiftUI
import Charts

// MARK: - Resource Monitoring View

struct ResourceMonitoringView: View {
    @ObservedObject private var statistics = UserStatistics.shared
    @State private var selectedTimeRange: ResourceTimeRange = .oneHour
    @State private var selectedCPUDate: Date?
    @State private var selectedMemoryDate: Date?

    enum ResourceTimeRange: String, CaseIterable {
        case fifteenMin = "15m"
        case oneHour = "1h"
        case oneDay = "1d"
        case sevenDays = "7d"
        case thirtyDays = "30d"

        var minutes: Int {
            switch self {
            case .fifteenMin: return 15
            case .oneHour: return 60
            case .oneDay: return 24 * 60
            case .sevenDays: return 7 * 24 * 60
            case .thirtyDays: return 30 * 24 * 60
            }
        }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                // Header with time range selector
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("System Resource Usage")
                            .font(.headline)
                        Spacer()
                        Picker("", selection: $selectedTimeRange) {
                            ForEach(ResourceTimeRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Text("Monitor CPU and memory usage of the TextWarden process")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("CPU load shows active threads. A load of 1.0 means one CPU core is fully utilized. On a \(ProcessInfo.processInfo.activeProcessorCount)-core system, full utilization would be \(ProcessInfo.processInfo.activeProcessorCount).0.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Metrics display
                let samples = filteredSamples()
                if !samples.isEmpty {
                    // CPU Metrics
                    cpuMetricsView(samples: samples)

                    Divider()
                        .padding(.vertical, 8)

                    // Memory Metrics
                    memoryMetricsView(samples: samples)

                    Divider()
                        .padding(.vertical, 8)

                    // Log Volume Metrics
                    logVolumeMetricsView()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No data available for selected time range")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Resource monitoring started when the app launched.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
        } header: {
            Text("Resource Monitoring")
                .font(.headline)
        }
    }

    // MARK: - CPU Metrics View

    @ViewBuilder
    private func cpuMetricsView(samples: [ResourceMetricSample]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.orange)
                Text("CPU Load Over Time")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // CPU Load Line Chart
            let peakLoad = samples.map(\.processLoad).max() ?? 0.0
            let maxLoad = peakLoad * 1.2  // Add 20% headroom

            // Add horizontal padding by extending the time domain
            let rawTimeRange = (samples.first?.timestamp ?? Date())...(samples.last?.timestamp ?? Date())
            let duration = rawTimeRange.upperBound.timeIntervalSince(rawTimeRange.lowerBound)
            let padding = duration * 0.045  // 4.5% padding on each side (~45pt equivalent)
            let timeRange = rawTimeRange.lowerBound.addingTimeInterval(-padding)...rawTimeRange.upperBound.addingTimeInterval(padding)

            // Filter app launches to only those within the raw time range (before padding)
            let visibleLaunches = statistics.appLaunchHistory.filter {
                $0 >= rawTimeRange.lowerBound && $0 <= rawTimeRange.upperBound
            }

            Chart {
                // CPU load line
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Load", sample.processLoad)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                }

                // Peak load line (dotted)
                RuleMark(y: .value("Peak", peakLoad))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Peak: \(String(format: "%.2f", peakLoad))")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.background.opacity(0.8))
                            .cornerRadius(4)
                    }

                // App launch markers (dots)
                ForEach(visibleLaunches, id: \.self) { launchTime in
                    PointMark(
                        x: .value("Launch", launchTime),
                        y: .value("Load", 0)
                    )
                    .foregroundStyle(.gray)
                    .symbolSize(60)
                }

                // Tooltip on hover
                if let selectedCPUDate {
                    // Find the nearest sample to the selected date
                    let nearestSample = samples.min(by: { abs($0.timestamp.timeIntervalSince(selectedCPUDate)) < abs($1.timestamp.timeIntervalSince(selectedCPUDate)) })
                    if let selectedSample = nearestSample {
                        RuleMark(x: .value("Selected", selectedSample.timestamp))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .top, alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedSample.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Load: \(String(format: "%.2f", selectedSample.processLoad))")
                                        .font(.callout)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                    if let sys1m = selectedSample.systemLoad1m {
                                        Text("System: \(String(format: "%.2f", sys1m))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(.background)
                                .cornerRadius(8)
                                .shadow(radius: 3)
                            }
                    }
                }
            }
            .chartXSelection(value: $selectedCPUDate)
            .chartXScale(domain: timeRange)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let load = value.as(Double.self) {
                            Text(String(format: "%.1f", load))
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYScale(domain: 0...maxLoad)
            .frame(height: 200)

            // Summary statistics
            let loadValues = samples.map(\.processLoad)
            let avgLoad = loadValues.reduce(0, +) / Double(loadValues.count)
            let medianLoad = median(loadValues)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", loadValues.min() ?? 0))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Max")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", loadValues.max() ?? 0))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", avgLoad))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Median")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", medianLoad))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }

                Spacer()

                Text("\(samples.count) samples")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Legend for app restart markers
            if !visibleLaunches.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.gray)
                        .frame(width: 8, height: 8)
                    Text("Gray dots indicate app restarts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Memory Metrics View

    @ViewBuilder
    private func memoryMetricsView(samples: [ResourceMetricSample]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "memorychip")
                    .foregroundColor(.blue)
                Text("Memory Usage Over Time")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Memory Line Chart
            let maxMemoryMB = Double(samples.map(\.memoryBytes).max() ?? 0) / 1_048_576
            let minMemoryMB = Double(samples.map(\.memoryBytes).min() ?? 0) / 1_048_576

            // Add horizontal padding by extending the time domain
            let rawTimeRange = (samples.first?.timestamp ?? Date())...(samples.last?.timestamp ?? Date())
            let duration = rawTimeRange.upperBound.timeIntervalSince(rawTimeRange.lowerBound)
            let padding = duration * 0.045  // 4.5% padding on each side (~45pt equivalent)
            let timeRange = rawTimeRange.lowerBound.addingTimeInterval(-padding)...rawTimeRange.upperBound.addingTimeInterval(padding)

            // Filter app launches to only those within the raw time range (before padding)
            let visibleLaunches = statistics.appLaunchHistory.filter {
                $0 >= rawTimeRange.lowerBound && $0 <= rawTimeRange.upperBound
            }

            Chart {
                // Memory line
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Memory", Double(sample.memoryBytes) / 1_048_576) // Convert to MB
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
                }

                // Peak memory line (dotted)
                RuleMark(y: .value("Peak", maxMemoryMB))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Peak: \(Int(maxMemoryMB)) MB")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.background.opacity(0.8))
                            .cornerRadius(4)
                    }

                // App launch markers (dots)
                ForEach(visibleLaunches, id: \.self) { launchTime in
                    PointMark(
                        x: .value("Launch", launchTime),
                        y: .value("Memory", minMemoryMB)
                    )
                    .foregroundStyle(.gray)
                    .symbolSize(60)
                }

                // Tooltip on hover
                if let selectedMemoryDate {
                    // Find the nearest sample to the selected date
                    let nearestSample = samples.min(by: { abs($0.timestamp.timeIntervalSince(selectedMemoryDate)) < abs($1.timestamp.timeIntervalSince(selectedMemoryDate)) })
                    if let selectedSample = nearestSample {
                        RuleMark(x: .value("Selected", selectedSample.timestamp))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .top, alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedSample.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(selectedSample.memoryBytes), countStyle: .memory))
                                        .font(.callout)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                                .padding(8)
                                .background(.background)
                                .cornerRadius(8)
                                .shadow(radius: 3)
                            }
                    }
                }
            }
            .chartXSelection(value: $selectedMemoryDate)
            .chartXScale(domain: timeRange)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let mb = value.as(Double.self) {
                            Text("\(Int(mb)) MB")
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYScale(domain: (minMemoryMB * 0.9)...(maxMemoryMB * 1.1))
            .frame(height: 200)

            // Summary statistics
            let memoryValues = samples.map(\.memoryBytes)
            let avgBytes = memoryValues.reduce(0, +) / UInt64(memoryValues.count)
            let medianBytes = medianUInt64(memoryValues)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(memoryValues.min() ?? 0), countStyle: .memory))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Max")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(memoryValues.max() ?? 0), countStyle: .memory))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(avgBytes), countStyle: .memory))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Median")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(medianBytes), countStyle: .memory))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }

                Spacer()

                Text("\(samples.count) samples")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Legend for app restart markers
            if !visibleLaunches.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.gray)
                        .frame(width: 8, height: 8)
                    Text("Gray dots indicate app restarts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Log Volume Metrics View

    @ViewBuilder
    private func logVolumeMetricsView() -> some View {
        let counts = statistics.logCountBySeverity(inMinutes: selectedTimeRange.minutes)
        let totalLogs = counts.trace + counts.debug + counts.info + counts.warning + counts.error + counts.critical
        let minLevel = Logger.minimumLogLevel

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.purple)
                Text("Log Volume")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            if totalLogs == 0 {
                Text("No log data yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding(.vertical, 8)
            } else {
                // Only consider counts for enabled levels when calculating max
                let enabledCounts = [
                    minLevel <= .critical ? counts.critical : 0,
                    minLevel <= .error ? counts.error : 0,
                    minLevel <= .warning ? counts.warning : 0,
                    minLevel <= .info ? counts.info : 0,
                    minLevel <= .debug ? counts.debug : 0,
                    minLevel <= .trace ? counts.trace : 0
                ]
                let maxCount = max(enabledCounts.max() ?? 1, 1)

                VStack(alignment: .leading, spacing: 10) {
                    // Only show levels at or above the minimum configured level
                    if minLevel <= .critical {
                        LogVolumeRow(label: "Critical", count: counts.critical, maxCount: maxCount, color: .red)
                            .help("Unrecoverable errors requiring immediate attention")
                    }

                    if minLevel <= .error {
                        LogVolumeRow(label: "Error", count: counts.error, maxCount: maxCount, color: .orange)
                            .help("Failures that affect functionality")
                    }

                    if minLevel <= .warning {
                        LogVolumeRow(label: "Warning", count: counts.warning, maxCount: maxCount, color: .yellow)
                            .help("Recoverable issues like API fallbacks or timeouts")
                    }

                    if minLevel <= .info {
                        LogVolumeRow(label: "Info", count: counts.info, maxCount: maxCount, color: .blue)
                            .help("Significant milestones like app launch or analysis completion")
                    }

                    if minLevel <= .debug {
                        LogVolumeRow(label: "Debug", count: counts.debug, maxCount: maxCount, color: .gray)
                            .help("Routine operations useful for debugging")
                    }

                    if minLevel <= .trace {
                        LogVolumeRow(label: "Trace", count: counts.trace, maxCount: maxCount, color: Color.gray.opacity(0.5))
                            .help("High-frequency events like mouse movement")
                    }
                }
                .padding(.vertical, 4)

                Text("Total logs: \(totalLogs)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Helper Methods

    private func filteredSamples() -> [ResourceMetricSample] {
        let cutoffDate = Calendar.current.date(byAdding: .minute, value: -selectedTimeRange.minutes, to: Date()) ?? Date.distantPast

        let allSamples = statistics.resourceSamples
            .filter { $0.component == .swiftApp }
            .filter { $0.timestamp >= cutoffDate }
            .sorted { $0.timestamp < $1.timestamp }

        // Downsample for longer time ranges to keep charts smooth
        // Target ~180 points for optimal visual appearance
        let targetPoints = 180
        guard allSamples.count > targetPoints else { return allSamples }

        // For 15m, keep all samples (usually ~180 at 5s intervals)
        // For longer ranges, downsample by averaging windows
        let step = max(1, allSamples.count / targetPoints)
        var downsampled: [ResourceMetricSample] = []

        for i in stride(from: 0, to: allSamples.count, by: step) {
            let windowEnd = min(i + step, allSamples.count)
            let window = Array(allSamples[i..<windowEnd])

            guard !window.isEmpty else { continue }

            // Use the middle sample's timestamp for accurate positioning
            let midIndex = window.count / 2
            let timestamp = window[midIndex].timestamp

            // Average the values in the window
            let avgLoad = window.map(\.processLoad).reduce(0, +) / Double(window.count)
            let avgMemory = UInt64(window.map { Double($0.memoryBytes) }.reduce(0, +) / Double(window.count))

            // Take system load from middle sample (or nil if any is nil)
            let sys1m = window[midIndex].systemLoad1m
            let sys5m = window[midIndex].systemLoad5m
            let sys15m = window[midIndex].systemLoad15m

            downsampled.append(ResourceMetricSample(
                timestamp: timestamp,
                component: .swiftApp,
                processLoad: avgLoad,
                memoryBytes: avgMemory,
                systemLoad1m: sys1m,
                systemLoad5m: sys5m,
                systemLoad15m: sys15m
            ))
        }

        return downsampled
    }

    /// Calculate median of Double values
    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let sorted = values.sorted()
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            return sorted[sorted.count / 2]
        }
    }

    /// Calculate median of UInt64 values
    private func medianUInt64(_ values: [UInt64]) -> UInt64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            return sorted[sorted.count / 2]
        }
    }

    // MARK: - Helper Views

    private func loadBadge(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f%%", value))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(loadColor(value))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private func loadColor(_ value: Double) -> Color {
        switch value {
        case 0..<25: return .green
        case 25..<50: return .yellow
        case 50..<75: return .orange
        default: return .red
        }
    }

    private func percentileRow(_ label: String, value: Double, max: Double, color: Color, isPercent: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 40, alignment: .leading)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                    Rectangle()
                        .fill(color)
                        .frame(width: max > 0 ? geometry.size.width * CGFloat(value / max) : 0)
                }
            }
            .frame(height: 6)
            .cornerRadius(3)

            if isPercent {
                Text(String(format: "%.1f%%", value))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                    .monospacedDigit()
            } else {
                Text(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory))
                    .font(.caption)
                    .frame(width: 70, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Log Volume Helper Views

/// Horizontal bar row for log volume by severity (matches LatencyRow style)
private struct LogVolumeRow: View {
    let label: String
    let count: Int
    let maxCount: Int
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            // Visual bar indicator
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    // Bar (scaled relative to max value)
                    let percentage = maxCount > 0 ? (Double(count) / Double(maxCount)) : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.5))
                        .frame(width: geometry.size.width * 0.75 * percentage)
                        .frame(height: 6)
                        .accessibilityHidden(true)

                    Spacer()

                    // Value
                    Text("\(count)")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(count > 0 ? color : .secondary)
                }
            }
            .frame(height: 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(count) logs")
    }
}
