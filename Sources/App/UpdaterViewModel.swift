//
//  UpdaterViewModel.swift
//  TextWarden
//
//  Swift wrapper for Sparkle auto-update functionality.
//

import Combine
import Foundation
import os.log
import Sparkle

/// Status of update check (for UI display)
enum UpdateCheckStatus: String, Equatable {
    case idle
    case checking
    case success
    case error
}

/// Delegate to receive update check results from Sparkle
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// Callback to update status on success (no error in update cycle)
    var onSuccess: ((Date) -> Void)?
    /// Callback to update status on error
    var onError: ((String) -> Void)?
    /// Whether to include experimental channel in updates
    var includeExperimentalUpdates: Bool = false

    func updater(_: SPUUpdater, didFinishUpdateCycleFor _: SPUUpdateCheck, error: (any Error)?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error as? NSError {
                // SUNoUpdateError (error code 1001) means "no update found" - this is success, not failure
                // The user is already on the latest version
                let isNoUpdateError = error.domain == "SUSparkleErrorDomain" && error.code == 1001
                if isNoUpdateError {
                    Logger.info("Update check completed - already on latest version", category: Logger.lifecycle)
                    self?.onSuccess?(Date())
                } else {
                    Logger.warning("Update check failed: \(error.localizedDescription) (domain: \(error.domain), code: \(error.code))", category: Logger.lifecycle)
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    self?.onError?(formatter.string(from: Date()))
                }
            } else {
                Logger.info("Update check completed successfully", category: Logger.lifecycle)
                self?.onSuccess?(Date())
            }
        }
    }

    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        if includeExperimentalUpdates {
            Logger.debug("Experimental updates enabled - including experimental channel", category: Logger.lifecycle)
            return Set(["experimental"])
        }
        // Empty set means default channel only
        return Set()
    }
}

/// User driver delegate to control update window presentation
/// Prevents multiple update windows from showing repeatedly for scheduled checks
final class UpdaterUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    /// Track the version we've already shown an update alert for
    private var lastAlertedVersion: String?

    /// Controls whether Sparkle should show the update window for scheduled (automatic) checks
    /// Returns false to suppress repeated update windows - user can still check manually
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Always show if in immediate focus (user just launched or interacted)
        if immediateFocus {
            Logger.info("Showing scheduled update (immediate focus): \(update.displayVersionString)", category: Logger.lifecycle)
            lastAlertedVersion = update.versionString
            return true
        }

        // For background checks, only show once per version
        if lastAlertedVersion == update.versionString {
            Logger.debug("Suppressing repeated update alert for version \(update.displayVersionString)", category: Logger.lifecycle)
            return false
        }

        Logger.info("Showing scheduled update: \(update.displayVersionString)", category: Logger.lifecycle)
        lastAlertedVersion = update.versionString
        return true
    }

    /// Reset the alerted version when the update session finishes
    /// This allows showing the alert again if user dismisses and a new check happens later
    func standardUserDriverWillFinishUpdateSession() {
        // Don't reset - keep tracking to prevent repeated alerts
        Logger.debug("Update session finished", category: Logger.lifecycle)
    }
}

/// ViewModel for managing app updates via Sparkle
@MainActor
final class UpdaterViewModel: ObservableObject {
    /// User preference for automatic update checks (synced with Sparkle)
    @Published var automaticallyChecksForUpdates: Bool = false {
        didSet {
            // Sync with Sparkle - this enables/disables the 24h automatic checks
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            Logger.info("Auto update check preference changed to: \(automaticallyChecksForUpdates)", category: Logger.lifecycle)
        }
    }

    /// User preference for receiving experimental updates
    @Published var includeExperimentalUpdates: Bool {
        didSet {
            updaterDelegate.includeExperimentalUpdates = includeExperimentalUpdates
            UserDefaults.standard.set(includeExperimentalUpdates, forKey: "TWIncludeExperimentalUpdates")
            Logger.info("Experimental updates preference changed to: \(includeExperimentalUpdates)", category: Logger.lifecycle)
        }
    }

    /// Whether the updater is ready to check for updates
    @Published var canCheckForUpdates = false

    /// Last time updates were checked
    @Published var lastUpdateCheckDate: Date?

    /// Current status of update check
    @Published var checkStatus: UpdateCheckStatus = .idle {
        didSet {
            UserDefaults.standard.set(checkStatus.rawValue, forKey: "TWUpdateCheckStatus")
        }
    }

    /// Cached status text for display (updated only when status changes)
    @Published var statusText: String = "Last checked: Never" {
        didSet {
            UserDefaults.standard.set(statusText, forKey: "TWUpdateStatusText")
        }
    }

    private let updaterController: SPUStandardUpdaterController
    private let updaterDelegate: UpdaterDelegate
    private let userDriverDelegate: UpdaterUserDriverDelegate
    private var cancellables = Set<AnyCancellable>()

    /// Whether an update check is currently in progress (prevents duplicate UI from manual checks)
    private var isUpdateCheckInProgress = false

    init() {
        Logger.info("Initializing UpdaterViewModel", category: Logger.lifecycle)

        // Create delegates first
        let delegate = UpdaterDelegate()
        updaterDelegate = delegate

        let userDriver = UpdaterUserDriverDelegate()
        userDriverDelegate = userDriver

        // Initialize the updater controller with our delegates
        // startingUpdater: false - we control when checks happen (startup + 24h interval)
        // userDriverDelegate: controls when update windows are shown (prevents repeated popups)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: userDriver
        )

        // Now start the updater manually
        do {
            try updaterController.updater.start()
        } catch {
            Logger.error("Failed to start updater: \(error.localizedDescription)", category: Logger.lifecycle)
        }

        // Check if this is first launch - default to disabled
        // Sparkle persists this in SUEnableAutomaticChecks
        let hasSetPreference = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") != nil
        if !hasSetPreference {
            updaterController.updater.automaticallyChecksForUpdates = false
            Logger.info("First launch - auto update checks disabled by default", category: Logger.lifecycle)
        }

        // Sync our property with Sparkle's current state
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates

        // Load experimental updates preference from UserDefaults (defaults to false)
        let experimentalEnabled = UserDefaults.standard.bool(forKey: "TWIncludeExperimentalUpdates")
        includeExperimentalUpdates = experimentalEnabled
        delegate.includeExperimentalUpdates = experimentalEnabled

        // Load last update check date from Sparkle's UserDefaults
        lastUpdateCheckDate = updaterController.updater.lastUpdateCheckDate

        // Restore persisted status (survives app restarts and view recreation)
        if let savedStatusText = UserDefaults.standard.string(forKey: "TWUpdateStatusText") {
            statusText = savedStatusText
        } else {
            statusText = "Last checked: \(formatDate(lastUpdateCheckDate))"
        }
        if let savedStatusRaw = UserDefaults.standard.string(forKey: "TWUpdateCheckStatus"),
           let savedStatus = UpdateCheckStatus(rawValue: savedStatusRaw)
        {
            checkStatus = savedStatus
        }

        // Set update check interval to 24 hours
        updaterController.updater.updateCheckInterval = 24 * 60 * 60

        // Observe canCheckForUpdates state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        // Set up delegate callbacks (after self is initialized)
        delegate.onSuccess = { [weak self] date in
            guard let self else { return }
            isUpdateCheckInProgress = false
            checkStatus = .success
            lastUpdateCheckDate = date
            statusText = "Up to date (\(formatDate(date)))"
        }

        delegate.onError = { [weak self] timestamp in
            guard let self else { return }
            isUpdateCheckInProgress = false
            checkStatus = .error
            statusText = "Failed to check (\(timestamp))"
        }

        // Sparkle handles automatic checks every 24h when automaticallyChecksForUpdates is true
        // IMPORTANT: Do NOT manually trigger checkForUpdatesInBackground() on startup
        // This interferes with Sparkle's internal scheduler and can cause duplicate update windows
        // See: https://sparkle-project.org/documentation/programmatic-setup/
        Logger.info("UpdaterViewModel initialized - autoCheck: \(automaticallyChecksForUpdates), interval: 24h", category: Logger.lifecycle)
    }

    /// Check for updates manually (shows UI)
    func checkForUpdates() {
        // Prevent duplicate checks if one is already in progress
        guard !isUpdateCheckInProgress else {
            Logger.debug("Skipping manual update check - check already in progress", category: Logger.lifecycle)
            return
        }

        Logger.info("Manual update check triggered", category: Logger.lifecycle)
        isUpdateCheckInProgress = true
        checkStatus = .checking
        statusText = "Checking..."
        updaterController.checkForUpdates(nil)
        // Status will be updated by the delegate callback
    }

    /// Check for updates silently in the background
    /// Only shows UI if an update is found
    /// Note: Prefer letting Sparkle handle automatic checks via automaticallyChecksForUpdates
    func checkForUpdatesInBackground() {
        // Prevent duplicate checks if one is already in progress
        // Note: Sparkle also checks sessionInProgress internally
        guard !isUpdateCheckInProgress else {
            Logger.debug("Skipping background update check - check already in progress", category: Logger.lifecycle)
            return
        }

        Logger.info("Background update check triggered", category: Logger.lifecycle)
        isUpdateCheckInProgress = true
        updaterController.updater.checkForUpdatesInBackground()
        // lastUpdateCheckDate will be updated by the delegate callback
    }

    /// Format a date for display
    private func formatDate(_ date: Date?) -> String {
        guard let date else {
            return "Never"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Format a date for display (non-optional)
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Whether currently checking for updates
    var isChecking: Bool {
        if case .checking = checkStatus {
            return true
        }
        return false
    }
}
