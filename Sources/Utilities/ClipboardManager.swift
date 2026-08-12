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
        NSPasteboard.general.string(forType: .string)
    }

    /// Clear clipboard contents.
    static func clear() {
        NSPasteboard.general.clearContents()
    }

    // MARK: - Save/Restore Operations

    /// Saved clipboard state for restoration
    struct SavedState {
        fileprivate struct Item {
            let representations: [String: Data]
        }

        fileprivate let items: [Item]
        let changeCount: Int
        fileprivate let replacementChangeCount: Int?

        fileprivate init(items: [Item], changeCount: Int, replacementChangeCount: Int? = nil) {
            self.items = items
            self.changeCount = changeCount
            self.replacementChangeCount = replacementChangeCount
        }
    }

    /// Save current clipboard state for later restoration.
    /// - Returns: The saved state to pass to `restore(_:)`
    static func save() -> SavedState {
        let pasteboard = NSPasteboard.general
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type.rawValue] = data
                }
            }
            return SavedState.Item(representations: representations)
        }
        return SavedState(
            items: items,
            changeCount: pasteboard.changeCount
        )
    }

    /// Set clipboard content after saving state.
    /// - Parameters:
    ///   - text: The text to set on clipboard
    ///   - saved: Previously saved state (for change count tracking)
    static func setForReplacement(_ text: String, savedState: SavedState) -> SavedState {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return SavedState(
            items: savedState.items,
            changeCount: savedState.changeCount,
            replacementChangeCount: pasteboard.changeCount
        )
    }

    /// Restore clipboard to saved state.
    /// Only restores if clipboard change count indicates our content is still there
    /// (i.e., user hasn't performed another copy operation).
    /// - Parameter state: The saved state from `save()`
    static func restore(_ state: SavedState) {
        let pasteboard = NSPasteboard.general

        // Only restore if our replacement content is still on the clipboard. The exact change
        // count is captured after setting it because clearContents and setString may advance the
        // counter differently across macOS versions.
        guard let replacementChangeCount = state.replacementChangeCount,
              pasteboard.changeCount == replacementChangeCount
        else {
            Logger.debug("ClipboardManager: Skipping restore - clipboard was modified by user", category: Logger.analysis)
            return
        }

        pasteboard.clearContents()
        let restoredItems = state.items.compactMap { savedItem -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            for (rawType, data) in savedItem.representations {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: rawType))
            }
            return savedItem.representations.isEmpty ? nil : item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
        Logger.debug("ClipboardManager: Restored \(restoredItems.count) original clipboard item(s)", category: Logger.analysis)
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
        let replacementState = setForReplacement(text, savedState: savedState)

        let result = try await operation()

        restoreAfterDelay(replacementState, delay: restoreDelay)
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
        let replacementState = setForReplacement(text, savedState: savedState)

        let result = try await operation()

        restore(replacementState)
        return result
    }
}
