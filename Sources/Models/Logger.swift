//
//  Logger.swift
//  TextWarden
//
//  Structured logging system using os_log (T117, T118)
//  Enhanced with configurable log levels and file output (Issue #20)
//

import Foundation
import os.log

/// Log level enum for filtering
enum LogLevel: String, Codable, CaseIterable, Comparable {
    case debug = "Debug"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case critical = "Critical"

    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        case .critical: return 4
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

/// Centralized logging system for TextWarden
struct Logger {
    private static let subsystem = "com.textwarden.app"
    private static let logFileName = "textwarden.log"
    private static let maxLogFileSize = 10 * 1024 * 1024 // 10MB
    private static let maxLogFiles = 5

    // MARK: - Configuration

    /// Default log directory following macOS best practices
    private static var defaultLogDirectory: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/Logs/TextWarden"
    }

    /// Default log file path
    private static var defaultLogFilePath: String {
        "\(defaultLogDirectory)/\(logFileName)"
    }

    /// Minimum log level to output (configurable via UserDefaults)
    static var minimumLogLevel: LogLevel {
        get {
            guard let stored = UserDefaults.standard.string(forKey: "logLevel"),
                  let level = LogLevel(rawValue: stored) else {
                return .info // Default to info
            }
            return level
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "logLevel")
        }
    }

    /// Whether file logging is enabled (configurable via UserDefaults)
    static var fileLoggingEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "enableFileLogging")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "enableFileLogging")
        }
    }

    /// Custom log file path (if set by user)
    static var customLogFilePath: String? {
        get {
            UserDefaults.standard.string(forKey: "customLogFilePath")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "customLogFilePath")
        }
    }

    /// Path to the current log file (custom or default)
    static var logFilePath: String {
        customLogFilePath ?? defaultLogFilePath
    }

    /// Reset to default log file path
    static func resetLogFilePathToDefault() {
        customLogFilePath = nil
    }

    /// Ensure log directory exists
    private static func ensureLogDirectoryExists() {
        let logPath = logFilePath
        let directory = (logPath as NSString).deletingLastPathComponent

        if !FileManager.default.fileExists(atPath: directory) {
            try? FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    // MARK: - Log Categories (T117)

    static let general = OSLog(subsystem: subsystem, category: "general")
    static let permissions = OSLog(subsystem: subsystem, category: "permissions")
    static let analysis = OSLog(subsystem: subsystem, category: "analysis")
    static let accessibility = OSLog(subsystem: subsystem, category: "accessibility")
    static let ffi = OSLog(subsystem: subsystem, category: "ffi")
    static let ui = OSLog(subsystem: subsystem, category: "ui")
    static let performance = OSLog(subsystem: subsystem, category: "performance")
    static let errors = OSLog(subsystem: subsystem, category: "errors")
    static let lifecycle = OSLog(subsystem: subsystem, category: "lifecycle")

    // MARK: - Internal Logging Helper

    private static func log(_ level: LogLevel, _ message: String, category: OSLog) {
        // Check if level meets minimum threshold
        guard level >= minimumLogLevel else { return }

        // Log to os_log
        let osLogType: OSLogType = {
            switch level {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }()
        os_log("%{public}@", log: category, type: osLogType, message)

        // Log to file if enabled
        if fileLoggingEnabled {
            logToFile(level: level, message: message, category: category)
        }
    }

    private static func logToFile(level: LogLevel, message: String, category: OSLog) {
        // Ensure log directory exists
        ensureLogDirectoryExists()

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let categoryName = String(describing: category).components(separatedBy: ":").last ?? "unknown"
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(categoryName)] \(message)\n"

        let logPath = logFilePath
        let fileURL = URL(fileURLWithPath: logPath)

        // Check if we need to rotate logs
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
           let fileSize = attrs[.size] as? Int64,
           fileSize > maxLogFileSize {
            rotateLogs()
        }

        // Append to log file
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private static func rotateLogs() {
        let basePath = logFilePath

        // Delete oldest log file
        let oldestLog = "\(basePath).\(maxLogFiles - 1)"
        try? FileManager.default.removeItem(atPath: oldestLog)

        // Rotate existing logs
        for i in (1..<maxLogFiles - 1).reversed() {
            let currentLog = "\(basePath).\(i)"
            let nextLog = "\(basePath).\(i + 1)"
            if FileManager.default.fileExists(atPath: currentLog) {
                try? FileManager.default.moveItem(atPath: currentLog, toPath: nextLog)
            }
        }

        // Move current log to .1
        if FileManager.default.fileExists(atPath: basePath) {
            try? FileManager.default.moveItem(atPath: basePath, toPath: "\(basePath).1")
        }
    }

    // MARK: - Convenience Methods

    /// Log general information
    static func info(_ message: String, category: OSLog = general) {
        log(.info, message, category: category)
    }

    /// Log debug information
    static func debug(_ message: String, category: OSLog = general) {
        log(.debug, message, category: category)
    }

    /// Log errors (T118)
    static func error(_ message: String, error: Error? = nil, category: OSLog = errors) {
        let fullMessage = if let error = error {
            "\(message): \(error.localizedDescription)"
        } else {
            message
        }
        log(.error, fullMessage, category: category)
    }

    /// Log warnings
    static func warning(_ message: String, category: OSLog = general) {
        log(.warning, message, category: category)
    }

    /// Log critical events (T118)
    static func critical(_ message: String, category: OSLog = errors) {
        log(.critical, message, category: category)
    }

    // MARK: - Structured Event Logging (T118)

    /// Log permission status change
    static func logPermissionChange(granted: Bool) {
        let status = granted ? "granted" : "denied"
        log(.info, "Permission status changed: \(status)", category: permissions)
    }

    /// Log analysis event
    static func logAnalysis(textLength: Int, errorCount: Int, durationMs: Double) {
        log(.info, "Analysis completed: \(textLength) chars, \(errorCount) errors, \(String(format: "%.2f", durationMs)) ms", category: analysis)
    }

    /// Log FFI call
    static func logFFICall(function: String, durationMs: Double) {
        log(.debug, "FFI call: \(function) completed in \(String(format: "%.2f", durationMs)) ms", category: ffi)
    }

    /// Log crash or termination
    static func logCrash(reason: String) {
        log(.critical, "App crash detected: \(reason)", category: lifecycle)
    }

    /// Log app restart
    static func logRestart() {
        log(.info, "App restarting after crash", category: lifecycle)
    }

    /// Log accessibility error
    static func logAccessibilityError(_ error: String, element: String? = nil) {
        if let element = element {
            log(.error, "Accessibility error for \(element): \(error)", category: accessibility)
        } else {
            log(.error, "Accessibility error: \(error)", category: accessibility)
        }
    }
}
