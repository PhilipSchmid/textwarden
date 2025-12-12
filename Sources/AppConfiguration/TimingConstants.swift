//
//  TimingConstants.swift
//  TextWarden
//
//  Centralized timing constants for the application.
//  Having these in one place makes it easier to tune performance.
//

import Foundation

/// Centralized timing constants for TextWarden
enum TimingConstants {

    // MARK: - Debounce Intervals

    /// Default debounce interval for text change detection (50ms for snappy UX)
    static let defaultDebounce: TimeInterval = 0.05

    /// Debounce interval for Chromium/Electron apps (1s due to AX quirks)
    static let chromiumDebounce: TimeInterval = 1.0

    /// Debounce interval for style analysis (2s to avoid excessive LLM calls)
    static let styleDebounce: TimeInterval = 2.0

    // MARK: - Cache Expiration

    /// Grammar analysis cache expiration (5 minutes)
    static let analysisCacheExpiration: TimeInterval = 300

    /// Style analysis cache expiration (10 minutes)
    static let styleCacheExpiration: TimeInterval = 600

    /// Position cache expiration (5 seconds)
    static let positionCacheExpiration: TimeInterval = 5.0

    /// Cursor position cache timeout (500ms)
    static let cursorCacheTimeout: TimeInterval = 0.5

    // MARK: - Polling Intervals

    /// Permission polling interval
    static let permissionPolling: TimeInterval = 1.0

    /// Permission revocation monitoring interval
    static let revocationMonitoring: TimeInterval = 30.0

    /// Resource monitor sampling interval
    static let resourceSampling: TimeInterval = 5.0

    // MARK: - UI Delays

    /// Short delay for UI operations
    static let shortDelay: TimeInterval = 0.05

    /// Medium delay for UI operations
    static let mediumDelay: TimeInterval = 0.1

    /// Long delay for UI operations
    static let longDelay: TimeInterval = 0.2

    /// Focus bounce grace period
    static let focusBounceGrace: TimeInterval = 0.5

    /// Accessibility announcement delay
    static let accessibilityAnnounce: TimeInterval = 0.5

    /// Popover auto-hide delay
    static let popoverAutoHide: TimeInterval = 2.0

    // MARK: - Keyboard Operations

    /// App activation delay before keyboard events
    static let keyboardActivationDelay: TimeInterval = 0.2

    /// Arrow key navigation delay
    static let arrowKeyDelay: TimeInterval = 0.001

    /// Required text settle time before analysis
    static let textSettleTime: TimeInterval = 0.15

    // MARK: - Typing Detection

    /// Pause threshold to detect typing stopped
    static let typingPauseThreshold: TimeInterval = 1.0

    // MARK: - Crash Recovery

    /// Heartbeat interval for crash detection
    static let heartbeatInterval: TimeInterval = 5.0

    /// Timeout to detect a crash
    static let crashDetectionTimeout: TimeInterval = 10.0

    /// Cooldown between restart attempts
    static let restartCooldown: TimeInterval = 60.0

    // MARK: - Onboarding

    /// Maximum wait time for permission grant (5 minutes)
    static let maxPermissionWait: TimeInterval = 300

    // MARK: - Statistics

    /// Maximum age for cached statistics (30 days)
    static let statisticsMaxAge: TimeInterval = 30 * 24 * 60 * 60
}
