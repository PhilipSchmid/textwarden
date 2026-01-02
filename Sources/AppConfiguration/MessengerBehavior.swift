//
//  MessengerBehavior.swift
//  TextWarden
//
//  Shared behavioral patterns for messenger/chat applications.
//  Handles conversation switching, message sent detection, and stale AX data.
//
//  Supported apps:
//  - Apple Messages (Mac Catalyst)
//  - WhatsApp (Mac Catalyst)
//  - Telegram (native macOS)
//

import Foundation

/// Encapsulates behavioral patterns shared across messenger applications
enum MessengerBehavior {
    // MARK: - Bundle IDs

    /// Apple Messages bundle ID
    static let messagesBundleID = "com.apple.MobileSMS"

    /// WhatsApp bundle ID
    static let whatsAppBundleID = "net.whatsapp.WhatsApp"

    /// Telegram bundle ID
    static let telegramBundleID = "ru.keepcoder.Telegram"

    /// All supported messenger bundle IDs
    static let allBundleIDs: Set<String> = [
        messagesBundleID,
        whatsAppBundleID,
        telegramBundleID,
    ]

    /// Mac Catalyst messenger apps (share similar AX behavior)
    static let catalystMessengerBundleIDs: Set<String> = [
        messagesBundleID,
        whatsAppBundleID,
    ]

    // MARK: - Timing Constants

    /// Delay after conversation switch before re-analyzing text.
    /// WhatsApp needs longer delay due to slower AX API updates.
    static func conversationSwitchDelay(for bundleID: String) -> TimeInterval {
        switch bundleID {
        case whatsAppBundleID:
            // WhatsApp's AX API is notoriously slow to update after conversation switch
            // May still return stale text from previous conversation if read too quickly
            0.5
        case messagesBundleID:
            // Messages updates faster but still needs settling time
            0.2
        case telegramBundleID:
            // Telegram is native and updates quickly
            0.15
        default:
            0.2
        }
    }

    /// Grace period after replacement before validating text.
    /// Catalyst apps have delayed AX notifications.
    static let postReplacementGracePeriod: TimeInterval = 1.5

    /// Grace period after conversation switch before allowing text validation.
    /// Prevents race conditions with conversation switch handler.
    static let postConversationSwitchGracePeriod: TimeInterval = 0.6

    // MARK: - App Detection

    /// Check if a bundle ID is a supported messenger app
    static func isMessengerApp(_ bundleID: String) -> Bool {
        allBundleIDs.contains(bundleID)
    }

    /// Check if a bundle ID is a Mac Catalyst messenger app
    static func isCatalystMessengerApp(_ bundleID: String) -> Bool {
        catalystMessengerBundleIDs.contains(bundleID)
    }

    /// Check if this app has stale AX data issues after conversation switch
    static func hasStaleDataIssues(_ bundleID: String) -> Bool {
        // WhatsApp is notorious for returning stale text after conversation switches
        bundleID == whatsAppBundleID
    }

    // MARK: - Behavior Helpers

    /// Determine if text should be considered stale after conversation switch.
    /// Returns true if the text appears unchanged (likely stale AX data).
    static func isTextLikelyStale(
        currentText: String,
        previousText: String,
        bundleID: String
    ) -> Bool {
        // Only applies to apps with known stale data issues
        guard hasStaleDataIssues(bundleID) else {
            return false
        }

        // If text is identical to what we had before the switch,
        // it's likely stale data from the previous conversation
        return currentText == previousText && !currentText.isEmpty
    }

    /// Check if element frame change indicates a conversation switch.
    /// Messenger apps move the text input field when switching conversations.
    static func isConversationSwitch(
        positionChange: CGFloat,
        threshold: CGFloat = 10.0
    ) -> Bool {
        positionChange > threshold
    }

    /// Check if element frame change indicates a message was sent.
    /// Text field shrinks when message is sent in chat apps.
    static func isMessageSent(
        heightChange: CGFloat,
        threshold: CGFloat = 5.0
    ) -> Bool {
        // Height decreased significantly (shrunk)
        heightChange < -threshold
    }

    /// Check if element frame change indicates user is typing more.
    /// Text field grows as user types more text.
    static func isTypingMore(
        heightChange: CGFloat,
        threshold: CGFloat = 5.0
    ) -> Bool {
        heightChange > threshold
    }
}
