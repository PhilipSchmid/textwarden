//
//  ClipboardManager.swift
//  TextWarden
//
//  Centralized clipboard management utility for consistent pasteboard operations.
//  Handles save/restore patterns needed for text replacement operations.
//

import AppKit
import Foundation

/// Centralized clipboard manager for pasteboard operations
enum ClipboardManager {

    // MARK: - Simple Operations

    /// Copy text to the system clipboard.
    /// - Parameter text: The text to copy
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Get current clipboard text content.
    /// - Returns: The string content, or nil if clipboard doesn't contain text
    static func currentText() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }

    /// Clear clipboard contents.
    static func clear() {
        NSPasteboard.general.clearContents()
    }

    // MARK: - Save/Restore Operations

    /// Saved clipboard state for restoration
    struct SavedState {
        let text: String?
        let changeCount: Int

        fileprivate init(text: String?, changeCount: Int) {
            self.text = text
            self.changeCount = changeCount
        }
    }

    /// Save current clipboard state for later restoration.
    /// - Returns: The saved state to pass to `restore(_:)`
    static func save() -> SavedState {
        let pasteboard = NSPasteboard.general
        return SavedState(
            text: pasteboard.string(forType: .string),
            changeCount: pasteboard.changeCount
        )
    }

    /// Set clipboard content after saving state.
    /// - Parameters:
    ///   - text: The text to set on clipboard
    ///   - saved: Previously saved state (for change count tracking)
    static func setForReplacement(_ text: String, savedState: SavedState) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Restore clipboard to saved state.
    /// Only restores if clipboard change count indicates our content is still there
    /// (i.e., user hasn't performed another copy operation).
    /// - Parameter state: The saved state from `save()`
    static func restore(_ state: SavedState) {
        let pasteboard = NSPasteboard.general

        // Only restore if clipboard wasn't modified by user since we set it
        // Change count increments by 1 for our clearContents+setString
        guard pasteboard.changeCount == state.changeCount + 1 else {
            Logger.debug("ClipboardManager: Skipping restore - clipboard was modified by user", category: Logger.analysis)
            return
        }

        pasteboard.clearContents()
        if let originalText = state.text {
            pasteboard.setString(originalText, forType: .string)
            Logger.debug("ClipboardManager: Restored original clipboard content", category: Logger.analysis)
        } else {
            Logger.debug("ClipboardManager: Cleared clipboard (no original content to restore)", category: Logger.analysis)
        }
    }

    /// Restore clipboard to saved state after a delay.
    /// - Parameters:
    ///   - state: The saved state from `save()`
    ///   - delay: Delay before restoring (defaults to TimingConstants.clipboardRestoreDelay)
    @MainActor
    static func restoreAfterDelay(_ state: SavedState, delay: TimeInterval = TimingConstants.clipboardRestoreDelay) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            restore(state)
        }
    }

    // MARK: - Scoped Operations

    /// Perform an operation with temporary clipboard content, then restore.
    /// - Parameters:
    ///   - text: Temporary text to place on clipboard
    ///   - delay: Delay before restoring original content
    ///   - operation: The operation to perform while clipboard contains the temporary text
    @MainActor
    static func withTemporaryContent<T>(_ text: String, restoreDelay: TimeInterval = TimingConstants.clipboardRestoreDelay, operation: () async throws -> T) async rethrows -> T {
        let savedState = save()
        copy(text)

        let result = try await operation()

        restoreAfterDelay(savedState, delay: restoreDelay)
        return result
    }

    /// Perform an operation with temporary clipboard content, restoring only if clipboard unchanged.
    /// This variant doesn't use a fixed delay but checks change count immediately.
    /// - Parameters:
    ///   - text: Temporary text to place on clipboard
    ///   - operation: The operation to perform
    @MainActor
    static func withTemporaryContentImmediate<T>(_ text: String, operation: () async throws -> T) async rethrows -> T {
        let savedState = save()
        copy(text)

        let result = try await operation()

        restore(savedState)
        return result
    }
}
