//
//  CrashRecoveryManager.swift
//  TextWarden
//
//  Automatic crash recovery and restart management
//

import Foundation
import AppKit

/// Manages crash detection and automatic recovery
class CrashRecoveryManager {
    static let shared = CrashRecoveryManager()

    private let heartbeatInterval: TimeInterval = TimingConstants.heartbeatInterval
    private let crashDetectionTimeout: TimeInterval = TimingConstants.crashDetectionTimeout
    private let maxRestartAttempts = 3
    private let restartCooldown: TimeInterval = TimingConstants.restartCooldown

    private var heartbeatTimer: Timer?
    private var lastHeartbeat: Date?
    private var restartAttempts: Int = 0
    private var lastRestartTime: Date?

    private let defaults = UserDefaults.standard
    private let heartbeatKey = "lastHeartbeat"
    private let crashCountKey = "crashCount"
    private let lastCrashKey = "lastCrashTime"

    private init() {
        checkForPreviousCrash()
        startHeartbeat()
    }

    // MARK: - Crash Detection

    /// Check if the app crashed previously
    private func checkForPreviousCrash() {
        guard let lastHeartbeat = defaults.object(forKey: heartbeatKey) as? Date else {
            Logger.info("First launch or clean shutdown", category: Logger.lifecycle)
            return
        }

        let timeSinceHeartbeat = Date().timeIntervalSince(lastHeartbeat)

        if timeSinceHeartbeat > crashDetectionTimeout {
            Logger.logCrash(reason: "No heartbeat for \(Int(timeSinceHeartbeat)) seconds")
            handleCrashDetected()
        } else {
            Logger.info("Clean shutdown detected", category: Logger.lifecycle)
        }

        // Reset crash counter if enough time has passed
        if let lastCrash = defaults.object(forKey: lastCrashKey) as? Date {
            let timeSinceCrash = Date().timeIntervalSince(lastCrash)
            if timeSinceCrash > restartCooldown {
                restartAttempts = 0
                defaults.set(0, forKey: crashCountKey)
            } else {
                restartAttempts = defaults.integer(forKey: crashCountKey)
            }
        }
    }

    /// Handle detected crash
    private func handleCrashDetected() {
        restartAttempts += 1
        defaults.set(restartAttempts, forKey: crashCountKey)
        defaults.set(Date(), forKey: lastCrashKey)

        if restartAttempts > maxRestartAttempts {
            Logger.critical("Max restart attempts exceeded (\(maxRestartAttempts))", category: Logger.lifecycle)
            showCrashDialog()
        } else {
            Logger.logRestart()
            showRestartIndicator()
        }
    }

    /// Show restart indicator
    private func showRestartIndicator() {
        DispatchQueue.main.async {
            if let menuBarController = MenuBarController.shared {
                menuBarController.showRestartIndicator()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.crashRecoveryInitialWait) {
                if let menuBarController = MenuBarController.shared {
                    menuBarController.hideRestartIndicator()
                }
            }
        }
    }

    /// Show crash dialog for excessive restarts
    private func showCrashDialog() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let alert = NSAlert()
            alert.messageText = "TextWarden encountered repeated crashes"
            alert.informativeText = """
            The app has crashed \(self.restartAttempts) times. \
            This may indicate a serious issue. Would you like to:

            • Reset preferences and try again
            • View crash logs
            • Quit the application
            """
            alert.addButton(withTitle: "Reset & Restart")
            alert.addButton(withTitle: "View Logs")
            alert.addButton(withTitle: "Quit")
            alert.alertStyle = .critical

            let response = alert.runModal()

            switch response {
            case .alertFirstButtonReturn:
                // Reset preferences
                UserPreferences.shared.resetToDefaults()
                self.restartAttempts = 0
                self.defaults.set(0, forKey: self.crashCountKey)
                Logger.info("Preferences reset, restarting", category: Logger.lifecycle)

            case .alertSecondButtonReturn:
                // Open Console app filtered to TextWarden logs
                self.openConsoleLogs()

            default:
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Open Console.app with TextWarden logs
    private func openConsoleLogs() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Console"]
        try? task.run()
    }

    // MARK: - Heartbeat Management

    /// Start heartbeat timer
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()

        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.recordHeartbeat()
        }

        // Record initial heartbeat
        recordHeartbeat()
    }

    /// Record heartbeat to detect crashes
    private func recordHeartbeat() {
        let now = Date()
        lastHeartbeat = now
        defaults.set(now, forKey: heartbeatKey)
    }

    /// Stop heartbeat (clean shutdown)
    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        defaults.removeObject(forKey: heartbeatKey)
        Logger.info("Clean shutdown initiated", category: Logger.lifecycle)
    }

    // MARK: - Health Check

    /// Current health status
    func healthStatus() -> HealthStatus {
        return HealthStatus(
            isHealthy: restartAttempts < maxRestartAttempts,
            restartAttempts: restartAttempts,
            lastHeartbeat: lastHeartbeat,
            lastCrash: defaults.object(forKey: lastCrashKey) as? Date
        )
    }

    // MARK: - Crash Logs

    /// Crash logs for diagnostic export
    func crashLogs() -> [String] {
        var logs: [String] = []

        // Add crash count information
        let crashCount = defaults.integer(forKey: crashCountKey)
        if crashCount > 0 {
            logs.append("Total crash count: \(crashCount)")
        }

        // Add last crash time
        if let lastCrash = defaults.object(forKey: lastCrashKey) as? Date {
            let formatter = ISO8601DateFormatter()
            logs.append("Last crash: \(formatter.string(from: lastCrash))")
            logs.append("Time since last crash: \(formatTimeInterval(Date().timeIntervalSince(lastCrash)))")
        }

        // Add restart attempts
        if restartAttempts > 0 {
            logs.append("Current restart attempts: \(restartAttempts)")
        }

        // Add health status
        let health = healthStatus()
        logs.append("Health status: \(health.isHealthy ? "Healthy" : "Unhealthy")")

        if logs.isEmpty {
            return ["No crash reports available"]
        }

        return logs
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Health Status

struct HealthStatus {
    let isHealthy: Bool
    let restartAttempts: Int
    let lastHeartbeat: Date?
    let lastCrash: Date?
}
