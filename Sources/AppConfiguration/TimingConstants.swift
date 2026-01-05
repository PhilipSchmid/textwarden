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

    /// Debounce interval for apps with slow AX APIs (Outlook, etc.)
    /// Longer than default to reduce AX call frequency during rapid typing.
    /// Used when defersTextExtraction is true.
    static let slowAppDebounce: TimeInterval = 0.8

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

    /// Text validation check interval (500ms)
    static let textValidationInterval: TimeInterval = 0.5

    // MARK: - Polling Intervals

    /// Permission polling interval
    static let permissionPolling: TimeInterval = 1.0

    /// Permission revocation monitoring interval
    static let revocationMonitoring: TimeInterval = 30.0

    /// Resource monitor sampling interval
    static let resourceSampling: TimeInterval = 5.0

    // MARK: - UI Delays

    /// Tiny delay for rapid sequential operations
    static let tinyDelay: TimeInterval = 0.02

    /// Short delay for UI operations
    static let shortDelay: TimeInterval = 0.05

    /// Medium delay for UI operations
    static let mediumDelay: TimeInterval = 0.1

    /// Long delay for UI operations
    static let longDelay: TimeInterval = 0.2

    /// Focus bounce grace period
    static let focusBounceGrace: TimeInterval = 0.5

    /// Mac Catalyst accessibility stabilization delay
    /// Catalyst apps need extra time for AX hierarchy to fully populate after focus change
    static let catalystAccessibilityDelay: TimeInterval = 0.6

    /// Grace period after applying text replacement before re-analysis
    static let replacementGracePeriod: TimeInterval = 1.5

    /// Accessibility announcement delay
    static let accessibilityAnnounce: TimeInterval = 0.5

    /// Popover auto-hide delay (time to wait after mouse leaves before hiding)
    static let popoverAutoHide: TimeInterval = 0.5

    /// Feedback display duration (e.g., "Copied!" message)
    static let feedbackDisplayDuration: TimeInterval = 1.5

    /// Hover detection delay before showing UI
    static let hoverDelay: TimeInterval = 0.3

    /// Animation frame interval for spinning indicator
    static let animationFrameInterval: TimeInterval = 0.03

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

    /// Initial wait time before checking crash recovery state
    static let crashRecoveryInitialWait: TimeInterval = 3.0

    /// Delay before showing crash recovery dialog to allow app to fully initialize
    static let crashRecoveryDialogDelay: TimeInterval = 2.0

    // MARK: - Accessibility API Timing

    /// Delay to wait for AX API to settle after element position changes
    /// Electron apps need 250-300ms for AX layer to update after UI changes
    static let axBoundsStabilizationDelay: TimeInterval = 0.25

    /// Fast polling interval for character bounds stability check
    static let boundsStabilityPollInterval: TimeInterval = 0.08

    // MARK: - App Lifecycle

    /// Delay before checking startup milestones after menu bar initialization
    static let startupMilestoneCheckDelay: TimeInterval = 2.0

    /// Delay before showing changelog window after app launch
    static let changelogDisplayDelay: TimeInterval = 0.5

    /// Delay for window cleanup after close to allow animations to complete
    static let windowCleanupDelay: TimeInterval = 0.5

    /// Delay before showing onboarding tutorial after permission grant
    static let tutorialDisplayDelay: TimeInterval = 0.3

    /// Delay before returning to accessory mode after closing a window
    static let accessoryModeReturnDelay: TimeInterval = 0.3

    // MARK: - AI/LLM Operations

    /// Retry delay for AI inference operations
    static let aiInferenceRetryDelay: TimeInterval = 6.0

    // MARK: - Clipboard Operations

    /// Delay before restoring clipboard contents
    static let clipboardRestoreDelay: TimeInterval = 0.7

    /// Delay for Electron/WhatsApp clipboard operations
    static let electronClipboardDelay: TimeInterval = 0.5

    // MARK: - Onboarding

    /// Maximum wait time before showing permission troubleshooting (30 seconds)
    /// Reduced from 5 minutes to help users who have stale permission entries from previous installations
    static let maxPermissionWait: TimeInterval = 30

    // MARK: - Statistics

    /// Maximum age for cached statistics (30 days)
    static let statisticsMaxAge: TimeInterval = 30 * 24 * 60 * 60
}
