//
//  UpdaterViewModel.swift
//  TextWarden
//
//  Swift wrapper for Sparkle auto-update functionality.
//

import Foundation
import Sparkle
import Combine
import os.log

/// ViewModel for managing app updates via Sparkle
final class UpdaterViewModel: ObservableObject {

    /// User preference for automatic update checks
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            Logger.info("Auto update check preference changed to: \(automaticallyChecksForUpdates)", category: Logger.lifecycle)
        }
    }

    /// Whether the updater is ready to check for updates
    @Published var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()

    init() {
        Logger.info("Initializing UpdaterViewModel", category: Logger.lifecycle)

        // Initialize the updater controller
        // startingUpdater: true means the updater will start checking automatically based on settings
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Initialize published property from current state
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates

        // Set update check interval to 24 hours
        updaterController.updater.updateCheckInterval = 24 * 60 * 60

        // Observe canCheckForUpdates state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        Logger.info("UpdaterViewModel initialized - autoCheck: \(automaticallyChecksForUpdates), interval: 24h", category: Logger.lifecycle)
    }

    /// Check for updates manually (shows UI)
    func checkForUpdates() {
        Logger.info("Manual update check triggered", category: Logger.lifecycle)
        updaterController.checkForUpdates(nil)
    }

    /// Check for updates silently in the background
    /// Only shows UI if an update is found
    func checkForUpdatesInBackground() {
        Logger.debug("Background update check triggered", category: Logger.lifecycle)
        updaterController.updater.checkForUpdatesInBackground()
    }
}
