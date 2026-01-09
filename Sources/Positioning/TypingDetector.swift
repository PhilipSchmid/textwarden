//
//  TypingDetector.swift
//  TextWarden
//
//  Detects typing activity for Electron-based apps (Slack, Notion, etc.)
//  Used to hide underlines during typing to prevent showing stale positions.
//
//  This is necessary because:
//  1. Electron apps have unreliable AX positioning during text changes
//  2. Underline positions become stale as soon as text changes
//  3. We need to wait for typing to pause before recalculating positions
//
//  Two detection mechanisms:
//  1. AX notifications (via notifyTextChange) - called when kAXValueChangedNotification fires
//  2. Keyboard events (via global event monitor) - detects typing even when AX notifications are delayed
//
//  Some apps (like Notion) batch AX notifications, so we need keyboard monitoring as a backup.
//  When typing stops (detected via keyboard events), we proactively trigger text extraction
//  rather than waiting for potentially delayed AX notifications.
//

import AppKit
import Foundation

/// Typing detection for Electron-based apps
/// Used by apps with `requiresTypingPause: true` in their AppConfiguration
final class TypingDetector {
    // MARK: - Singleton

    static let shared = TypingDetector()

    // MARK: - Configuration

    /// Minimum time text must be stable before showing underlines
    /// This matches the debounce interval in TextMonitor for Electron apps
    private let typingPauseThreshold: TimeInterval = TimingConstants.typingPauseThreshold

    // MARK: - State

    /// Last time a typing-related event occurred
    private var lastTypingTime: Date = .distantPast

    /// Whether typing was detected via keyboard (not just AX notification)
    private var typingDetectedViaKeyboard: Bool = false

    /// Callback to hide underlines immediately when typing starts
    var onTypingStarted: (() -> Void)?

    /// Callback when typing stops (after pause threshold) - used to trigger text extraction
    /// This is important for apps like Notion that don't send timely AX notifications
    var onTypingStopped: (() -> Void)?

    /// Current bundle ID being monitored (set by AnalysisCoordinator)
    var currentBundleID: String?

    // MARK: - Keyboard Monitoring

    /// Global keyboard event monitor
    private var keyboardMonitor: Any?

    /// Timer to detect when typing has stopped
    private var typingStoppedTimer: Timer?

    // MARK: - Initialization

    private init() {
        setupKeyboardMonitor()
    }

    deinit {
        cleanup()
    }

    /// Clean up resources (keyboard monitor, timers)
    /// Called during app termination for explicit cleanup since deinit won't be called for singletons
    func cleanup() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        typingStoppedTimer?.invalidate()
        typingStoppedTimer = nil
    }

    // MARK: - Keyboard Event Monitoring

    /// Set up global keyboard monitor to detect typing in Electron apps
    /// This is needed because some apps (Notion) batch AX notifications
    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    /// Handle key down events.
    /// NOTE: Global keyboard monitor callbacks run on a non-main thread,
    /// so we must dispatch to main thread before accessing shared state.
    private func handleKeyDown(_ event: NSEvent) {
        // Capture event properties before dispatching (NSEvent is not thread-safe)
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags

        // Dispatch to main thread for thread-safe access to shared state
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Only trigger for apps that delay AX notifications (like Notion)
            // Apps like Slack send notifications immediately and don't need keyboard detection
            guard let bundleID = currentBundleID else { return }
            let appConfig = AppRegistry.shared.configuration(for: bundleID)
            guard appConfig.features.delaysAXNotifications else { return }

            // Ignore modifier-only keys (shift, ctrl, cmd, etc.)
            // These don't typically indicate typing
            let modifierOnlyFlags: NSEvent.ModifierFlags = [.command, .control, .option]
            if !modifierFlags.isDisjoint(with: modifierOnlyFlags) {
                // If a modifier is held, check if it's just a modifier key press
                // Allow typing characters with shift (uppercase, symbols)
                if !modifierFlags.isDisjoint(with: [.command, .control, .option]) {
                    return
                }
            }

            // Check for function keys and navigation keys - don't hide on these
            // NOTE: Backspace (51) and Forward Delete (117) are NOT ignored because they change text
            let ignoredKeyCodes: Set<UInt16> = [
                53, // Escape
                48, // Tab (usually changes focus, not text)
                123, 124, 125, 126, // Arrow keys
                115, 116, 119, 121, // Home, Page Up, End, Page Down
                122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1-F12
            ]

            if ignoredKeyCodes.contains(keyCode) {
                return
            }

            // This is likely a typing character - notify immediately
            Logger.debug("TypingDetector: Keyboard event detected in \(appConfig.displayName) - hiding underlines", category: Logger.ui)
            notifyTypingEvent(viaKeyboard: true)
        }
    }

    // MARK: - Public API

    /// Called when text changes via AX notification
    /// This should be called from TextMonitor.handleTextChange()
    func notifyTextChange() {
        Logger.trace("TypingDetector: AX text change notification received", category: Logger.ui)
        notifyTypingEvent(viaKeyboard: false)
    }

    /// Called when keyboard event indicates typing
    private func notifyTypingEvent(viaKeyboard: Bool) {
        lastTypingTime = Date()

        if viaKeyboard {
            typingDetectedViaKeyboard = true
        }

        // Notify listeners immediately so underlines can be hidden
        DispatchQueue.main.async { [weak self] in
            self?.onTypingStarted?()
        }

        // Schedule "typing stopped" callback
        // This is important for apps like Notion where AX notifications are delayed
        scheduleTypingStoppedCallback()
    }

    /// Schedule callback for when typing stops
    private func scheduleTypingStoppedCallback() {
        // Cancel any existing timer
        typingStoppedTimer?.invalidate()

        // Schedule new timer for after typing pause threshold
        typingStoppedTimer = Timer.scheduledTimer(withTimeInterval: typingPauseThreshold, repeats: false) { [weak self] _ in
            guard let self else { return }

            // Only trigger if typing was detected via keyboard (not just AX)
            // This ensures we proactively extract text for apps with delayed AX notifications
            guard typingDetectedViaKeyboard else { return }

            Logger.debug("TypingDetector: Typing stopped - triggering text extraction", category: Logger.ui)
            typingDetectedViaKeyboard = false

            DispatchQueue.main.async { [weak self] in
                self?.onTypingStopped?()
            }
        }
    }

    /// Check if user is currently typing (within the pause threshold)
    var isCurrentlyTyping: Bool {
        Date().timeIntervalSince(lastTypingTime) < typingPauseThreshold
    }

    /// Reset typing state (e.g., when switching apps)
    func reset() {
        lastTypingTime = .distantPast
        typingDetectedViaKeyboard = false
        typingStoppedTimer?.invalidate()
        typingStoppedTimer = nil
    }
}
