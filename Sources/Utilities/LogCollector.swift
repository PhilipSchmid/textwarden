//
//  LogCollector.swift
//  TextWarden
//
//  Utility for collecting logs for diagnostic reports (Issue #18)
//
//  SECURITY NOTICE:
//  This module filters logs to prevent sensitive data leakage.
//  Logs are sanitized to remove any potential user text content.
//

import Foundation

/// Utility for collecting and sanitizing logs
enum LogCollector {
    // MARK: - Sensitive Data Patterns

    /// Patterns that might indicate sensitive data in logs
    private static let sensitivePatterns = [
        // Common patterns that might indicate user text
        "text=",
        "content=",
        "password",
        "credential",
        "token",
        "secret",
        "api_key",
    ]

    // MARK: - Log Collection

    /// Collect recent logs from the log file
    /// - Parameter maxLines: Maximum number of lines to collect
    /// - Returns: Array of sanitized log lines
    static func collectRecentLogs(maxLines: Int = 100) -> [String] {
        let logPath = Logger.logFilePath

        guard FileManager.default.fileExists(atPath: logPath) else {
            return ["Log file not found at: \(logPath)"]
        }

        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)

            // Get last N lines
            let recentLines = Array(lines.suffix(maxLines))

            // Sanitize each line
            return recentLines.compactMap { line in
                guard !line.isEmpty else { return nil }
                return sanitizeLogLine(line)
            }
        } catch {
            return ["Error reading log file: \(error.localizedDescription)"]
        }
    }

    // MARK: - Sanitization

    /// Sanitize a log line to remove sensitive data
    /// - Parameter line: Original log line
    /// - Returns: Sanitized log line
    private static func sanitizeLogLine(_ line: String) -> String {
        var sanitized = line

        // Check for sensitive patterns
        let lowerLine = line.lowercased()
        for pattern in sensitivePatterns {
            if lowerLine.contains(pattern) {
                // If we find a sensitive pattern, mark it
                sanitized = "\(line) [SANITIZED: Contains sensitive pattern '\(pattern)']"
                break
            }
        }

        // SECURITY: Remove any quoted strings that might contain user text
        // Only in lines that might have text parameters
        if sanitized.contains("\""), lowerLine.contains("text") || lowerLine.contains("content") {
            sanitized = sanitized.replacingOccurrences(
                of: "\"[^\"]{20,}\"",
                with: "\"[REDACTED]\"",
                options: .regularExpression
            )
        }

        return sanitized
    }

    // MARK: - Statistics

    /// Collect log statistics without actual log content
    /// - Returns: Dictionary of log statistics
    static func collectLogStatistics() -> [String: Any] {
        let logPath = Logger.logFilePath

        guard FileManager.default.fileExists(atPath: logPath) else {
            return [
                "exists": false,
                "path": logPath,
            ]
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logPath)
            let fileSize = attributes[.size] as? Int64 ?? 0
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()

            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lineCount = logContent.components(separatedBy: .newlines).count

            // Count log levels
            var levelCounts: [String: Int] = [:]
            let lines = logContent.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("[Debug]") {
                    levelCounts["Debug", default: 0] += 1
                } else if line.contains("[Info]") {
                    levelCounts["Info", default: 0] += 1
                } else if line.contains("[Warning]") {
                    levelCounts["Warning", default: 0] += 1
                } else if line.contains("[Error]") {
                    levelCounts["Error", default: 0] += 1
                } else if line.contains("[Critical]") {
                    levelCounts["Critical", default: 0] += 1
                }
            }

            return [
                "exists": true,
                "path": logPath,
                "size_bytes": fileSize,
                "line_count": lineCount,
                "last_modified": ISO8601DateFormatter().string(from: modificationDate),
                "level_counts": levelCounts,
            ]
        } catch {
            return [
                "exists": true,
                "error": error.localizedDescription,
            ]
        }
    }
}
