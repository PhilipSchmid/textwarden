//
//  PermissionManager.swift
//  TextWarden
//
//  Manages Accessibility permissions and status
//

import Foundation
import AppKit
import ApplicationServices
import Combine

/// Manages Accessibility API permissions
@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    /// Whether Accessibility permissions are currently granted
    @Published private(set) var isPermissionGranted: Bool = false

    /// Callback when permission is granted
    var onPermissionGranted: (() -> Void)?

    /// Callback when permission is revoked (T113)
    var onPermissionRevoked: (() -> Void)?

    /// Timer for polling permission status
    private var pollTimer: Timer?

    /// Timer for continuous permission monitoring (T113)
    private var revocationMonitorTimer: Timer?

    private init() {
        // Initialize with actual permission status (synchronous check)
        isPermissionGranted = AXIsProcessTrusted()
        Logger.logPermissionChange(granted: isPermissionGranted)

        // Start continuous monitoring for revocation (T113)
        if isPermissionGranted {
            startRevocationMonitoring()
        }
    }

    /// Check if Accessibility permissions are granted
    func checkPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        isPermissionGranted = trusted
        return trusted
    }

    /// Check permission status and update published property
    /// Alias for checkPermission() used by OnboardingView
    func checkPermissionStatus() {
        let wasGranted = isPermissionGranted
        let isGranted = checkPermission()

        // Call callback if permission was just granted
        if !wasGranted && isGranted {
            Logger.info("Permission just granted", category: Logger.permissions)
            onPermissionGranted?()
        }
    }

    /// Check if app can request permission
    func canRequestPermission() -> Bool {
        // Always true on macOS 13.0+
        return true
    }

    /// Request Accessibility permissions
    /// This will trigger the system permission dialog
    func requestPermission() {
        Logger.info("Requesting Accessibility permission", category: Logger.permissions)

        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let result = AXIsProcessTrustedWithOptions(options)

        Logger.debug("AXIsProcessTrustedWithOptions returned: \(result)", category: Logger.permissions)

        // Start polling to detect when permission is granted
        startPolling()
    }

    /// Start polling for permission status changes
    func startPolling(interval: TimeInterval = TimingConstants.permissionPolling) {
        stopPolling()

        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let wasGranted = self.isPermissionGranted
                let isGranted = self.checkPermission()

                // Stop polling once permission is granted
                if !wasGranted && isGranted {
                    self.stopPolling()
                    // Start continuous monitoring for revocation (T113)
                    self.startRevocationMonitoring()
                }
            }
        }
    }

    /// Stop polling for permission status
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Permission Revocation Monitoring (T113)

    /// Start continuous monitoring for permission revocation
    private func startRevocationMonitoring(interval: TimeInterval = TimingConstants.revocationMonitoring) {
        stopRevocationMonitoring()

        Logger.info("Starting permission revocation monitoring (every \(Int(interval))s)", category: Logger.permissions)

        revocationMonitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForRevocation()
            }
        }
    }

    /// Stop revocation monitoring
    private func stopRevocationMonitoring() {
        revocationMonitorTimer?.invalidate()
        revocationMonitorTimer = nil
    }

    /// Check if permission was revoked
    private func checkForRevocation() {
        let wasGranted = isPermissionGranted
        let isGranted = checkPermission()

        // Permission was revoked
        if wasGranted && !isGranted {
            Logger.critical("Accessibility permission was revoked!", category: Logger.permissions)
            Logger.logPermissionChange(granted: false)

            DispatchQueue.main.async {
                self.onPermissionRevoked?()
            }
        }
    }

    /// Open System Settings to Accessibility preferences
    func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Alias for openSystemSettings() used by OnboardingView
    func openSystemPreferences() {
        openSystemSettings()
    }

    deinit {
        // Directly invalidate timers (can't call @MainActor methods from deinit)
        pollTimer?.invalidate()
        revocationMonitorTimer?.invalidate()
    }
}

// MARK: - Permission Status

extension PermissionManager {
    /// Get detailed permission status
    var permissionStatus: PermissionStatus {
        if isPermissionGranted {
            return .granted
        } else {
            return .denied
        }
    }

    enum PermissionStatus {
        case granted
        case denied

        var description: String {
            switch self {
            case .granted:
                return "Accessibility permissions granted"
            case .denied:
                return "Accessibility permissions required"
            }
        }
    }
}
