//
//  Logger.swift
//  Gnau
//
//  Structured logging system using os_log (T117, T118)
//

import Foundation
import os.log

/// Centralized logging system for Gnau
struct Logger {
    private static let subsystem = "com.gnau.app"

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

    // MARK: - Convenience Methods

    /// Log general information
    static func info(_ message: String, category: OSLog = general) {
        os_log("%{public}@", log: category, type: .info, message)
    }

    /// Log debug information
    static func debug(_ message: String, category: OSLog = general) {
        os_log("%{public}@", log: category, type: .debug, message)
    }

    /// Log errors (T118)
    static func error(_ message: String, error: Error? = nil, category: OSLog = errors) {
        if let error = error {
            os_log("%{public}@: %{public}@", log: category, type: .error, message, error.localizedDescription)
        } else {
            os_log("%{public}@", log: category, type: .error, message)
        }
    }

    /// Log warnings
    static func warning(_ message: String, category: OSLog = general) {
        os_log("%{public}@", log: category, type: .default, message)
    }

    /// Log critical events (T118)
    static func critical(_ message: String, category: OSLog = errors) {
        os_log("%{public}@", log: category, type: .fault, message)
    }

    // MARK: - Structured Event Logging (T118)

    /// Log permission status change
    static func logPermissionChange(granted: Bool) {
        let status = granted ? "granted" : "denied"
        os_log("Permission status changed: %{public}@", log: permissions, type: .info, status)
    }

    /// Log analysis event
    static func logAnalysis(textLength: Int, errorCount: Int, durationMs: Double) {
        os_log(
            "Analysis completed: %d chars, %d errors, %.2f ms",
            log: analysis,
            type: .info,
            textLength,
            errorCount,
            durationMs
        )
    }

    /// Log FFI call
    static func logFFICall(function: String, durationMs: Double) {
        os_log(
            "FFI call: %{public}@ completed in %.2f ms",
            log: ffi,
            type: .debug,
            function,
            durationMs
        )
    }

    /// Log crash or termination
    static func logCrash(reason: String) {
        os_log("App crash detected: %{public}@", log: lifecycle, type: .fault, reason)
    }

    /// Log app restart
    static func logRestart() {
        os_log("App restarting after crash", log: lifecycle, type: .info)
    }

    /// Log accessibility error
    static func logAccessibilityError(_ error: String, element: String? = nil) {
        if let element = element {
            os_log(
                "Accessibility error for %{public}@: %{public}@",
                log: accessibility,
                type: .error,
                element,
                error
            )
        } else {
            os_log("Accessibility error: %{public}@", log: accessibility, type: .error, error)
        }
    }
}
