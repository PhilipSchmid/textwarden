//
//  ApplicationContext.swift
//  Gnau
//
//  Model representing the context of an application being monitored
//

import Foundation

/// Represents the application context for text monitoring
struct ApplicationContext {
    /// Bundle identifier of the application (e.g., "com.apple.TextEdit")
    let bundleIdentifier: String

    /// Process ID of the running application
    let processID: pid_t

    /// Human-readable application name
    let applicationName: String

    /// Whether grammar checking is enabled for this application
    var isEnabled: Bool

    /// Timestamp when this context was created
    let createdAt: Date

    /// Initialize application context
    init(
        bundleIdentifier: String,
        processID: pid_t,
        applicationName: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.applicationName = applicationName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// Check if grammar checking should be active for this context
    func shouldCheck() -> Bool {
        guard isEnabled else { return false }

        // Check user preferences
        return UserPreferences.shared.isEnabled(for: bundleIdentifier)
    }

    /// Create a copy with updated enabled status
    func with(isEnabled: Bool) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: applicationName,
            isEnabled: isEnabled,
            createdAt: createdAt
        )
    }
}

// MARK: - Equatable

extension ApplicationContext: Equatable {
    static func == (lhs: ApplicationContext, rhs: ApplicationContext) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.processID == rhs.processID
    }
}

// MARK: - Hashable

extension ApplicationContext: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
        hasher.combine(processID)
    }
}

// MARK: - CustomStringConvertible

extension ApplicationContext: CustomStringConvertible {
    var description: String {
        "\(applicationName) (\(bundleIdentifier)) [PID: \(processID)] - \(isEnabled ? "enabled" : "disabled")"
    }
}

// MARK: - Common Application Contexts

extension ApplicationContext {
    /// Create context for TextEdit
    static func textEdit(processID: pid_t) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: "com.apple.TextEdit",
            processID: processID,
            applicationName: "TextEdit"
        )
    }

    /// Create context for Pages
    static func pages(processID: pid_t) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: "com.apple.Pages",
            processID: processID,
            applicationName: "Pages"
        )
    }

    /// Create context for VS Code
    static func vsCode(processID: pid_t) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: "com.microsoft.VSCode",
            processID: processID,
            applicationName: "Visual Studio Code"
        )
    }

    /// Create context for generic application
    static func application(bundleIdentifier: String, processID: pid_t, name: String) -> ApplicationContext {
        ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: name
        )
    }
}
