//
//  BuildInfo.swift
//  TextWarden
//
//  Build information and version tracking
//

import Foundation

/// Build information captured at compile time
enum BuildInfo {
    /// Date when the app was launched
    static let launchDate: Date = .init()

    /// Timestamp when the app was launched (UTC)
    static let launchTimestamp: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: launchDate) + " UTC"
    }()

    /// Human-readable uptime (e.g., "2 hours", "3 days")
    static var uptime: String {
        let now = Date()
        let interval = now.timeIntervalSince(launchDate)

        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if days < 7 {
            return "\(days) day\(days == 1 ? "" : "s")"
        } else {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s")"
        }
    }

    /// Short format for logging (e.g., "2025-11-23 12:30 UTC")
    static var shortTimestamp: String {
        let components = launchTimestamp.components(separatedBy: " ")
        if components.count >= 3 {
            return "\(components[0]) \(components[1].prefix(5)) UTC"
        }
        return launchTimestamp
    }

    // Legacy aliases for backward compatibility
    static var buildTimestamp: String { launchTimestamp }
    static var buildDate: Date { launchDate }
    static var buildAge: String { uptime }

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
        "\(appVersion) (\(buildNumber))"
    }

    /// Complete build info for logging
    static var fullInfo: String {
        """
        Version: \(fullVersion)
        App Started: \(launchTimestamp)
        Uptime: \(uptime)
        """
    }
}
