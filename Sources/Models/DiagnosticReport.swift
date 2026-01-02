//
//  DiagnosticReport.swift
//  TextWarden
//
//  Diagnostic report model for exporting system diagnostics (Issue #18)
//
//  SECURITY NOTICE:
//  This module MUST NEVER include user text content in exports.
//  Only include metadata (lengths, counts, timings) - never actual text.
//  User text may contain passwords, credentials, and personal information.
//

import AppKit
import CoreGraphics
import Foundation
import KeyboardShortcuts
import LaunchAtLogin

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - Apple Intelligence Style Checking Diagnostics

/// Apple Intelligence style checking diagnostics for export
struct AppleIntelligenceDiagnostics: Codable {
    // Feature status
    let styleCheckingEnabled: Bool

    // Apple Intelligence availability
    let appleIntelligenceStatus: String
    let appleIntelligenceAvailable: Bool
    let statusMessage: String

    // Settings
    let selectedWritingStyle: String
    let temperaturePreset: String
    let confidenceThreshold: Double

    // Runtime status
    let isAnalyzing: Bool

    @MainActor
    static func current(preferences: UserPreferences) -> AppleIntelligenceDiagnostics {
        // Get Apple Intelligence status if available on macOS 26+
        var status = "Unknown"
        var available = false
        var statusMessage = "Requires macOS 26+"
        let isAnalyzing = false // Not accessible at report generation time

        if #available(macOS 26.0, *) {
            // Access the shared FoundationModelsEngine to get status
            // Note: We can't easily access the singleton here without dependency injection,
            // so we check availability directly
            #if canImport(FoundationModels)
                let model = SystemLanguageModel.default
                switch model.availability {
                case .available:
                    status = "Available"
                    available = true
                    statusMessage = "Ready"
                case let .unavailable(reason):
                    switch reason {
                    case .appleIntelligenceNotEnabled:
                        status = "NotEnabled"
                        statusMessage = "Apple Intelligence not enabled in System Settings"
                    case .deviceNotEligible:
                        status = "DeviceNotEligible"
                        statusMessage = "Device not eligible (requires Apple Silicon)"
                    case .modelNotReady:
                        status = "ModelNotReady"
                        statusMessage = "Language model not ready yet"
                    @unknown default:
                        status = "Unknown"
                        statusMessage = "Unknown unavailability reason"
                    }
                }
            #endif
        }

        let preset = StyleTemperaturePreset(rawValue: preferences.styleTemperaturePreset) ?? .balanced

        return AppleIntelligenceDiagnostics(
            styleCheckingEnabled: preferences.enableStyleChecking,
            appleIntelligenceStatus: status,
            appleIntelligenceAvailable: available,
            statusMessage: statusMessage,
            selectedWritingStyle: preferences.selectedWritingStyle,
            temperaturePreset: preset.label,
            confidenceThreshold: preferences.styleConfidenceThreshold,
            isAnalyzing: isAnalyzing
        )
    }
}

// MARK: - Performance Metrics

/// Performance metrics for a specific time range
struct PerformanceMetrics: Codable {
    let meanLatencyMs: Double
    let medianLatencyMs: Double
    let p90LatencyMs: Double
    let p95LatencyMs: Double
    let p99LatencyMs: Double
    let sampleCount: Int
}

/// Statistics for a specific time range
struct TimeRangeStatistics: Codable {
    let timeRange: String
    let errorsFound: Int
    let wordsAnalyzed: Int
    let analysisSessions: Int
    let suggestionsApplied: Int
    let suggestionsDismissed: Int
    let wordsAddedToDictionary: Int
    let improvementRate: Double
    let averageErrorsPer100Words: Double
    let categoryBreakdown: [String: Int]
    let appUsageBreakdown: [String: Int]
    let topWritingApp: String?
    let topWritingAppErrorCount: Int
    let performance: PerformanceMetrics?
    let resourceUsage: ResourceUsageMetrics?

    @MainActor
    static func from(_ stats: UserStatistics, timeRange: TimeRange) -> TimeRangeStatistics {
        let timeRangeName = switch timeRange {
        case .session:
            "Since App Start"
        case .day:
            "Last 24 Hours"
        case .week:
            "Last 7 Days"
        case .month:
            "Last 30 Days"
        case .ninetyDays:
            "Last 90 Days"
        }

        // Get latency samples for this time range
        let latencySamples = stats.latencySamples(in: timeRange)
        let performance: PerformanceMetrics?
        if !latencySamples.isEmpty {
            let sorted = latencySamples.sorted()
            let mean = sorted.reduce(0.0, +) / Double(sorted.count)
            let median = sorted[sorted.count / 2]
            let p90Index = Int(Double(sorted.count) * 0.9)
            let p95Index = Int(Double(sorted.count) * 0.95)
            let p99Index = Int(Double(sorted.count) * 0.99)

            performance = PerformanceMetrics(
                meanLatencyMs: mean,
                medianLatencyMs: median,
                p90LatencyMs: sorted[min(p90Index, sorted.count - 1)],
                p95LatencyMs: sorted[min(p95Index, sorted.count - 1)],
                p99LatencyMs: sorted[min(p99Index, sorted.count - 1)],
                sampleCount: sorted.count
            )
        } else {
            performance = nil
        }

        let topApp = stats.topWritingApp(in: timeRange)

        // Calculate resource usage metrics for this time range
        let resourceUsage = stats.resourceUsageMetrics(in: timeRange)

        return TimeRangeStatistics(
            timeRange: timeRangeName,
            errorsFound: stats.errorsFound(in: timeRange),
            wordsAnalyzed: stats.wordsAnalyzed(in: timeRange),
            analysisSessions: stats.analysisSessions(in: timeRange),
            suggestionsApplied: stats.suggestionsApplied(in: timeRange),
            suggestionsDismissed: stats.suggestionsDismissed(in: timeRange),
            wordsAddedToDictionary: stats.wordsAddedToDictionary(in: timeRange),
            improvementRate: stats.improvementRate(in: timeRange),
            averageErrorsPer100Words: stats.averageErrorsPer100Words(in: timeRange),
            categoryBreakdown: stats.categoryBreakdown(in: timeRange),
            appUsageBreakdown: stats.appUsageBreakdown(in: timeRange),
            topWritingApp: topApp?.name,
            topWritingAppErrorCount: topApp?.errorCount ?? 0,
            performance: performance,
            resourceUsage: resourceUsage
        )
    }
}

/// Comprehensive statistics snapshot for diagnostic reports
struct StatisticsSnapshot: Codable {
    // Cumulative totals (all-time)
    let errorsFound: Int
    let suggestionsApplied: Int
    let suggestionsDismissed: Int
    let wordsAddedToDictionary: Int
    let wordsAnalyzed: Int
    let analysisSessions: Int
    let sessionCount: Int
    let activeDaysCount: Int
    let currentStreak: Int

    // Milestone card interaction stats (not shown in UI, for analytics)
    let milestoneSupportClicks: Int
    let milestoneDismissClicks: Int
    let milestoneDisableClicks: Int

    // Cumulative metrics
    let improvementRate: Double
    let averageErrorsPer100Words: Double
    let categoryBreakdown: [String: Int]
    let appUsageBreakdown: [String: Int]
    let topWritingApp: String?
    let topWritingAppErrorCount: Int

    // All-time performance metrics
    let meanLatencyMs: Double
    let medianLatencyMs: Double
    let p90LatencyMs: Double
    let p95LatencyMs: Double
    let p99LatencyMs: Double
    let totalLatencySamples: Int

    // All-time resource usage metrics
    let resourceUsage: ResourceUsageMetrics?

    // App launch tracking (for correlating resource usage with restarts)
    let currentAppLaunchTime: Date
    let appLaunchHistory: [Date]

    // Time-filtered statistics (grouped by timeframe for performance insights)
    let timeRangeStatistics: [TimeRangeStatistics]

    @MainActor
    static func from(_ stats: UserStatistics) -> StatisticsSnapshot {
        let topApp = stats.topWritingApp

        // Generate statistics for all time ranges
        let timeRanges: [TimeRange] = [.session, .day, .week, .month, .ninetyDays]
        let timeRangeStats = timeRanges.map { TimeRangeStatistics.from(stats, timeRange: $0) }

        // Calculate overall resource usage metrics (all samples)
        let overallResourceUsage = stats.overallResourceUsageMetrics()

        return StatisticsSnapshot(
            errorsFound: stats.errorsFound,
            suggestionsApplied: stats.suggestionsApplied,
            suggestionsDismissed: stats.suggestionsDismissed,
            wordsAddedToDictionary: stats.wordsAddedToDictionary,
            wordsAnalyzed: stats.wordsAnalyzed,
            analysisSessions: stats.analysisSessions,
            sessionCount: stats.sessionCount,
            activeDaysCount: stats.activeDays.count,
            currentStreak: stats.currentStreak,
            milestoneSupportClicks: stats.milestoneSupportClicks,
            milestoneDismissClicks: stats.milestoneDismissClicks,
            milestoneDisableClicks: stats.milestoneDisableClicks,
            improvementRate: stats.improvementRate,
            averageErrorsPer100Words: stats.averageErrorsPer100Words,
            categoryBreakdown: stats.categoryBreakdown,
            appUsageBreakdown: stats.appUsageBreakdown,
            topWritingApp: topApp?.name,
            topWritingAppErrorCount: topApp?.errorCount ?? 0,
            meanLatencyMs: stats.meanLatencyMs,
            medianLatencyMs: stats.medianLatencyMs,
            p90LatencyMs: stats.p90LatencyMs,
            p95LatencyMs: stats.p95LatencyMs,
            p99LatencyMs: stats.p99LatencyMs,
            totalLatencySamples: stats.latencySamples.count,
            resourceUsage: overallResourceUsage,
            currentAppLaunchTime: stats.appLaunchTimestamp,
            appLaunchHistory: stats.appLaunchHistory,
            timeRangeStatistics: timeRangeStats
        )
    }
}

/// System information for diagnostic reports
struct SystemInfo: Codable {
    let osVersion: String
    let architecture: String
    let locale: String

    static func current() -> SystemInfo {
        let processInfo = ProcessInfo.processInfo
        return SystemInfo(
            osVersion: processInfo.operatingSystemVersionString,
            architecture: getMachineArchitecture(),
            locale: Locale.current.identifier
        )
    }

    private static func getMachineArchitecture() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

/// Permissions status for diagnostic reports
struct PermissionsStatus: Codable {
    let accessibilityGranted: Bool
    let lastPermissionCheck: Date

    @MainActor
    static func current() -> PermissionsStatus {
        PermissionsStatus(
            accessibilityGranted: PermissionManager.shared.isPermissionGranted,
            lastPermissionCheck: Date()
        )
    }
}

/// Application state for diagnostic reports
struct ApplicationState: Codable {
    let isPaused: Bool
    let currentPauseDuration: String
    let activeApplication: String?
    let discoveredApplications: [String: String] // bundleID: applicationName
    let pausedApplications: [String: String] // bundleID: pauseDuration (includes "Paused Indefinitely")
    let pausedByDefaultApplications: [String: String] // bundleID: applicationName (terminals/hidden apps)

    @MainActor
    static func current(preferences: UserPreferences) -> ApplicationState {
        let tracker = ApplicationTracker.shared
        let isPaused = preferences.pauseDuration != .active

        // Get paused applications with names
        var pausedApps: [String: String] = [:]
        for (bundleID, duration) in preferences.appPauseDurations {
            if duration != .active {
                let appName = getApplicationName(for: bundleID)
                pausedApps[bundleID] = "\(appName) (\(duration.rawValue))"
            }
        }

        // Get discovered applications with names
        var discoveredApps: [String: String] = [:]
        for bundleID in preferences.discoveredApplications {
            let appName = getApplicationName(for: bundleID)
            discoveredApps[bundleID] = appName
        }

        // Get applications that are paused by default (terminals, etc.)
        var pausedByDefault: [String: String] = [:]
        for bundleID in UserPreferences.terminalApplications {
            let appName = getApplicationName(for: bundleID)
            pausedByDefault[bundleID] = appName
        }

        return ApplicationState(
            isPaused: isPaused,
            currentPauseDuration: preferences.pauseDuration.rawValue,
            activeApplication: tracker.activeApplication?.applicationName,
            discoveredApplications: discoveredApps,
            pausedApplications: pausedApps,
            pausedByDefaultApplications: pausedByDefault
        )
    }

    /// Get human-readable application name from bundle ID
    private static func getApplicationName(for bundleID: String) -> String {
        let workspace = NSWorkspace.shared

        // Try to get app from running applications first
        if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return app.localizedName ?? bundleID
        }

        // Try to get app URL from bundle identifier
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let appName = FileManager.default.displayName(atPath: appURL.path)
            // Remove .app extension if present
            if appName.hasSuffix(".app") {
                return String(appName.dropLast(4))
            }
            return appName
        }

        // Fallback to bundle ID
        return bundleID
    }
}

/// Complete settings dump for diagnostic reports
struct SettingsDump: Codable {
    // Launch
    let autoStart: Bool

    // Language & Grammar
    let selectedDialect: String
    let enabledCategories: [String]
    let enableLanguageDetection: Bool
    let excludedLanguages: [String]

    // Predefined Wordlists
    let internetAbbreviationsEnabled: Bool
    let genZSlangEnabled: Bool
    let itTerminologyEnabled: Bool

    // Appearance
    let appTheme: String
    let overlayTheme: String
    let suggestionOpacity: Double
    let suggestionTextSize: Double
    let suggestionPosition: String
    let underlineThickness: Double
    let indicatorPosition: String

    // Logging
    let logLevel: String
    let fileLoggingEnabled: Bool
    let logFilePath: String

    // Debug Overlays
    let debugOverlaysEnabled: Bool
    let showTextFieldBounds: Bool
    let showCGWindowCoords: Bool
    let showCocoaCoords: Bool

    // Keyboard Shortcuts
    let keyboardShortcutsEnabled: Bool
    let shortcuts: [String: String]

    @MainActor
    static func from(_ preferences: UserPreferences, shortcuts: [String: String] = [:]) -> SettingsDump {
        SettingsDump(
            autoStart: LaunchAtLogin.isEnabled,
            selectedDialect: preferences.selectedDialect,
            enabledCategories: Array(preferences.enabledCategories).sorted(),
            enableLanguageDetection: preferences.enableLanguageDetection,
            excludedLanguages: Array(preferences.excludedLanguages).sorted(),
            internetAbbreviationsEnabled: preferences.enableInternetAbbreviations,
            genZSlangEnabled: preferences.enableGenZSlang,
            itTerminologyEnabled: preferences.enableITTerminology,
            appTheme: preferences.appTheme,
            overlayTheme: preferences.overlayTheme,
            suggestionOpacity: preferences.suggestionOpacity,
            suggestionTextSize: preferences.suggestionTextSize,
            suggestionPosition: preferences.suggestionPosition,
            underlineThickness: preferences.underlineThickness,
            indicatorPosition: preferences.indicatorPosition,
            logLevel: Logger.minimumLogLevel.rawValue,
            fileLoggingEnabled: Logger.fileLoggingEnabled,
            logFilePath: Logger.logFilePath,
            debugOverlaysEnabled: preferences.showDebugBorderTextFieldBounds ||
                preferences.showDebugBorderCGWindowCoords ||
                preferences.showDebugBorderCocoaCoords,
            showTextFieldBounds: preferences.showDebugBorderTextFieldBounds,
            showCGWindowCoords: preferences.showDebugBorderCGWindowCoords,
            showCocoaCoords: preferences.showDebugBorderCocoaCoords,
            keyboardShortcutsEnabled: preferences.keyboardShortcutsEnabled,
            shortcuts: shortcuts
        )
    }

    /// Collect keyboard shortcuts (MUST be called on main thread)
    @MainActor
    static func collectShortcuts() -> [String: String] {
        var shortcutsDict: [String: String] = [:]

        // IMPORTANT: This must be called on the main thread because
        // KeyboardShortcuts.Shortcut.description accesses input sources
        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleTextWarden) {
            shortcutsDict["Toggle TextWarden"] = shortcut.description
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .acceptSuggestion) {
            shortcutsDict["Accept Suggestion"] = shortcut.description
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .dismissSuggestion) {
            shortcutsDict["Dismiss Suggestion"] = shortcut.description
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .previousSuggestion) {
            shortcutsDict["Previous Suggestion"] = shortcut.description
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .nextSuggestion) {
            shortcutsDict["Next Suggestion"] = shortcut.description
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .applySuggestion1) {
            shortcutsDict["Apply Suggestion 1"] = shortcut.description
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .applySuggestion2) {
            shortcutsDict["Apply Suggestion 2"] = shortcut.description
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .applySuggestion3) {
            shortcutsDict["Apply Suggestion 3"] = shortcut.description
        }

        return shortcutsDict
    }
}

// MARK: - Strategy Profile Diagnostics

/// Diagnostics for auto-detected app capability profiles
struct StrategyProfileDiagnostics: Codable {
    let profileCount: Int
    let profileCachePath: String
    let profiles: [AXCapabilityProfile]

    static func current() -> StrategyProfileDiagnostics {
        let cache = StrategyProfileCache.shared
        return StrategyProfileDiagnostics(
            profileCount: cache.profileCount,
            profileCachePath: cache.cacheFileURL.path,
            profiles: cache.allProfiles
        )
    }
}

/// Complete diagnostic report
struct DiagnosticReport: Codable {
    let reportTimestamp: Date
    let reportVersion: String

    // Build & App Info
    let appVersion: String
    let buildNumber: String
    let buildTimestamp: String

    // System Info
    let systemInfo: SystemInfo
    let permissionsStatus: PermissionsStatus
    let applicationState: ApplicationState

    // Settings (complete dump)
    let settings: SettingsDump

    // Statistics (comprehensive with time-range breakdown and performance metrics)
    let statistics: StatisticsSnapshot

    // Apple Intelligence Style Checking
    let appleIntelligence: AppleIntelligenceDiagnostics

    // Strategy Profiles (auto-detected app capabilities)
    let strategyProfiles: StrategyProfileDiagnostics

    // Crash Info (count of actual .crash/.ips files in crash_reports/ folder)
    let crashReportCount: Int

    // Note: Logs and full crash reports (.crash/.ips files) are exported as separate files in the ZIP

    /// Generate a complete diagnostic report (without logs - those go in separate files)
    @MainActor
    static func generate(
        preferences: UserPreferences,
        crashReportCount: Int = 0,
        shortcuts: [String: String] = [:]
    ) -> DiagnosticReport {
        DiagnosticReport(
            reportTimestamp: Date(),
            reportVersion: "6.0", // Bumped to 6.0 for Apple Intelligence migration
            appVersion: BuildInfo.appVersion,
            buildNumber: BuildInfo.buildNumber,
            buildTimestamp: BuildInfo.buildTimestamp,
            systemInfo: SystemInfo.current(),
            permissionsStatus: PermissionsStatus.current(),
            applicationState: ApplicationState.current(preferences: preferences),
            settings: SettingsDump.from(preferences, shortcuts: shortcuts),
            statistics: StatisticsSnapshot.from(UserStatistics.shared),
            appleIntelligence: AppleIntelligenceDiagnostics.current(preferences: preferences),
            strategyProfiles: StrategyProfileDiagnostics.current(),
            crashReportCount: crashReportCount
        )
    }

    /// Export as JSON string
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(self) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Export as ZIP package containing JSON overview, log files, and crash reports
    /// - Parameters:
    ///   - destinationURL: Where to save the ZIP file
    ///   - preferences: User preferences
    ///   - shortcuts: Keyboard shortcuts (must be collected on main thread)
    /// - Returns: True if successful, false otherwise
    @MainActor
    static func exportAsZIP(to destinationURL: URL, preferences: UserPreferences, shortcuts: [String: String] = [:]) -> Bool {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            // Create temp directory structure
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let crashReportsDir = tempDir.appendingPathComponent("crash_reports")
            try fileManager.createDirectory(at: crashReportsDir, withIntermediateDirectories: true)

            // 1. Find actual crash reports first
            let diagnosticReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath
            var crashFilesToCopy: [String] = []
            if fileManager.fileExists(atPath: diagnosticReportsPath) {
                let contents = try? fileManager.contentsOfDirectory(atPath: diagnosticReportsPath)
                let crashFiles = contents?.filter {
                    $0.hasPrefix("TextWarden") && ($0.hasSuffix(".crash") || $0.hasSuffix(".ips"))
                } ?? []
                // Get up to 10 most recent
                crashFilesToCopy = Array(crashFiles.sorted(by: >).prefix(10))
            }

            // 2. Generate and save JSON overview with crash report count
            let report = DiagnosticReport.generate(preferences: preferences, crashReportCount: crashFilesToCopy.count, shortcuts: shortcuts)
            guard let jsonString = report.toJSON() else {
                Logger.error("Failed to generate JSON for diagnostic report", category: Logger.errors)
                return false
            }

            let overviewURL = tempDir.appendingPathComponent("diagnostic_overview.json")
            try jsonString.write(to: overviewURL, atomically: true, encoding: .utf8)

            // 3. Copy log files (all rotated logs if they exist)
            let logPath = Logger.logFilePath
            if fileManager.fileExists(atPath: logPath) {
                let logFileName = (logPath as NSString).lastPathComponent
                let destLogURL = tempDir.appendingPathComponent(logFileName)
                try fileManager.copyItem(atPath: logPath, toPath: destLogURL.path)

                // Copy rotated logs
                for i in 1 ..< 5 {
                    let rotatedLog = "\(logPath).\(i)"
                    if fileManager.fileExists(atPath: rotatedLog) {
                        let rotatedFileName = "\(logFileName).\(i)"
                        let destRotatedURL = tempDir.appendingPathComponent(rotatedFileName)
                        try fileManager.copyItem(atPath: rotatedLog, toPath: destRotatedURL.path)
                    }
                }
            }

            // 4. Copy actual macOS crash reports from DiagnosticReports
            for crashFile in crashFilesToCopy {
                let sourcePath = (diagnosticReportsPath as NSString).appendingPathComponent(crashFile)
                let destURL = crashReportsDir.appendingPathComponent(crashFile)
                try? fileManager.copyItem(atPath: sourcePath, toPath: destURL.path)
            }

            // 5. Create ZIP archive
            let zipSuccess = createZIPArchive(from: tempDir, to: destinationURL)

            // 6. Clean up temp directory
            try? fileManager.removeItem(at: tempDir)

            return zipSuccess
        } catch {
            Logger.error("Failed to export diagnostic package", error: error, category: Logger.errors)
            try? fileManager.removeItem(at: tempDir)
            return false
        }
    }

    /// Create ZIP archive from directory
    private static func createZIPArchive(from sourceURL: URL, to destinationURL: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceURL.path, destinationURL.path]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            Logger.error("Failed to create ZIP archive", error: error, category: Logger.errors)
            return false
        }
    }
}
