//
//  BuildInfo.swift
//  TextWarden
//
//  Build information and version tracking
//

import Foundation

/// Build information captured at compile time
struct BuildInfo {
    /// Timestamp when the app was launched (UTC)
    /// Note: This captures app startup time, not compile time
    static let buildTimestamp: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date()) + " UTC"
    }()

    /// Build date as Date object
    static let buildDate: Date = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")

        // Try to parse the timestamp string
        let timestampString = buildTimestamp.replacingOccurrences(of: " UTC", with: "")

        if let date = formatter.date(from: timestampString) {
            return date
        } else {
            // Fallback to current date if parsing fails
            return Date()
        }
    }()

    /// Human-readable session age (e.g., "2 hours ago", "3 days ago")
    static var buildAge: String {
        let now = Date()
        let interval = now.timeIntervalSince(buildDate)

        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if days < 7 {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        }
    }

    /// Short format for logging (e.g., "2025-11-23 12:30 UTC")
    static var shortTimestamp: String {
        let components = buildTimestamp.components(separatedBy: " ")
        if components.count >= 3 {
            return "\(components[0]) \(components[1].prefix(5)) UTC"
        }
        return buildTimestamp
    }

    /// App version from Info.plist
    static let appVersion: String = {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return "Unknown"
    }()

    /// Build number from Info.plist
    static let buildNumber: String = {
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return build
        }
        return "Unknown"
    }()

    /// Full version string (e.g., "1.0.0 (42)")
    static var fullVersion: String {
        return "\(appVersion) (\(buildNumber))"
    }

    /// Harper grammar engine version
    /// NOTE: This should match the version in GrammarEngine/Cargo.toml
    /// Update this when upgrading Harper
    static let harperVersion: String = "0.72"

    /// Complete build info for logging
    static var fullInfo: String {
        return """
        Version: \(fullVersion)
        Session Started: \(buildTimestamp)
        Session Age: \(buildAge)
        """
    }
}
