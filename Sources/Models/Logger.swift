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
    case trace = "Trace"     // Most verbose - high-frequency events like mouse movement
    case debug = "Debug"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case critical = "Critical"

    var priority: Int {
        switch self {
        case .trace: return -1
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

    // MARK: - Cached Resources (Performance Optimization)

    /// Serial queue for async file logging to avoid blocking main thread
    private static let fileLoggingQueue = DispatchQueue(label: "com.textwarden.logger", qos: .utility)

    /// Cached date formatter (creating a new one per log is expensive)
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    /// Persistent file handle for efficient writes
    private static var cachedFileHandle: FileHandle?
    private static var cachedLogPath: String?

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
    static let llm = OSLog(subsystem: subsystem, category: "llm")
    static let ui = OSLog(subsystem: subsystem, category: "ui")
    static let performance = OSLog(subsystem: subsystem, category: "performance")
    static let errors = OSLog(subsystem: subsystem, category: "errors")
    static let lifecycle = OSLog(subsystem: subsystem, category: "lifecycle")
    static let rust = OSLog(subsystem: subsystem, category: "rust")

    // MARK: - Rust Log Bridge (Unified Logging)

    /// Register the Swift callback with Rust for unified logging
    /// Call this BEFORE initializing the Rust grammar engine
    static func registerRustLogCallback() {
        register_rust_log_callback(rustLogCallback)
    }

    /// Handle incoming log messages from Rust
    /// - Parameters:
    ///   - level: Log level (0=ERROR, 1=WARN, 2=INFO, 3=DEBUG, 4=TRACE)
    ///   - message: The log message from Rust
    fileprivate static func handleRustLog(level: Int32, message: String) {
        let logLevel: LogLevel = switch level {
        case 0: .error
        case 1: .warning
        case 2: .info
        case 3: .debug
        case 4: .trace
        default: .debug
        }

        // Use the internal log method with rust category
        log(logLevel, "[Rust] \(message)", category: rust)
    }

    // MARK: - Internal Logging Helper

    private static func log(_ level: LogLevel, _ message: String, category: OSLog) {
        // Check if level meets minimum threshold
        guard level >= minimumLogLevel else { return }

        // Log to os_log
        let osLogType: OSLogType = {
            switch level {
            case .trace: return .debug   // Trace uses debug level in os_log
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
        // Capture values for async block
        let timestamp = dateFormatter.string(from: Date())
        let categoryName = String(describing: category).components(separatedBy: ":").last ?? "unknown"
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(categoryName)] \(message)\n"

        // Dispatch file I/O to background queue to avoid blocking main thread
        fileLoggingQueue.async {
            writeToLogFile(logLine)
        }
    }

    /// Write a log line to the file (called on fileLoggingQueue)
    private static func writeToLogFile(_ logLine: String) {
        let logPath = logFilePath

        // Ensure log directory exists (only check once when path changes)
        if cachedLogPath != logPath {
            ensureLogDirectoryExists()
            cachedFileHandle = nil  // Reset handle when path changes
            cachedLogPath = logPath
        }

        // Check if we need to rotate logs (check periodically, not every write)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
           let fileSize = attrs[.size] as? Int64,
           fileSize > maxLogFileSize {
            cachedFileHandle = nil  // Close handle before rotation
            rotateLogs()
        }

        guard let data = logLine.data(using: .utf8) else { return }

        // Get or create the cached file handle
        if cachedFileHandle == nil {
            let fileURL = URL(fileURLWithPath: logPath)
            if FileManager.default.fileExists(atPath: logPath) {
                cachedFileHandle = try? FileHandle(forWritingTo: fileURL)
                cachedFileHandle?.seekToEndOfFile()
            } else {
                // Create the file
                try? data.write(to: fileURL)
                cachedFileHandle = try? FileHandle(forWritingTo: fileURL)
                cachedFileHandle?.seekToEndOfFile()
                return  // Already wrote the data
            }
        }

        // Write using cached handle
        cachedFileHandle?.write(data)
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

    /// Log trace information (highest verbosity, for high-frequency events)
    static func trace(_ message: String, category: OSLog = general) {
        log(.trace, message, category: category)
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

// MARK: - Rust FFI Callback

/// C callback function for receiving logs from Rust
/// This function is called from Rust via FFI
/// - Parameters:
///   - level: Log level (0=ERROR, 1=WARN, 2=INFO, 3=DEBUG, 4=TRACE)
///   - messagePtr: Pointer to null-terminated C string containing the log message
private let rustLogCallback: @convention(c) (Int32, UnsafePointer<CChar>?) -> Void = { level, messagePtr in
    guard let messagePtr = messagePtr else { return }
    let message = String(cString: messagePtr)
    Logger.handleRustLog(level: level, message: message)
}
