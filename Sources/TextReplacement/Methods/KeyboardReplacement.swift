//
//  KeyboardReplacement.swift
//  TextWarden
//
//  Keyboard-based text replacement using selection + clipboard paste.
//  Used for Electron apps, WebKit views, browsers, and other apps where
//  direct AX API setValue doesn't work reliably.
//

import Foundation
import AppKit
@preconcurrency import ApplicationServices

/// Keyboard-based replacement using selection + clipboard paste
struct KeyboardReplacement {

    // MARK: - Execution

    /// Execute text replacement using keyboard simulation.
    /// - Parameter context: The replacement context with resolved indices
    /// - Returns: Result of the replacement operation
    @MainActor
    func execute(_ context: ReplacementContext) async -> ReplacementResult {
        Logger.debug(
            "KeyboardReplacement: Executing for \(context.appConfig.identifier) at range \(context.resolvedRange.location)..<\(context.resolvedRange.location + context.resolvedRange.length)",
            category: Logger.analysis
        )

        // 1. Set selection to the error range
        if let error = setSelection(context) {
            return .failed(error)
        }

        // 2. Perform clipboard-based paste
        return await performClipboardPaste(context)
    }

    // MARK: - Selection

    /// Set the AX selection to the error range
    private func setSelection(_ context: ReplacementContext) -> ReplacementError? {
        let range = context.resolvedRange
        var cfRange = CFRange(location: range.location, length: range.length)

        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.error("KeyboardReplacement: Failed to create AXValue for range", category: Logger.analysis)
            return .selectionFailed(axError: -1)
        }

        let result = AXUIElementSetAttributeValue(
            context.element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        // Note: Selection may "fail" but still work in some Electron apps
        // We log the result but continue with paste anyway
        if result != .success {
            Logger.debug(
                "KeyboardReplacement: Selection returned \(result.rawValue) - continuing with paste",
                category: Logger.analysis
            )
        }

        return nil
    }

    // MARK: - Clipboard Paste

    /// Perform clipboard-based text replacement
    @MainActor
    private func performClipboardPaste(_ context: ReplacementContext) async -> ReplacementResult {
        // Backup current clipboard
        let savedState = ClipboardManager.save()

        // Set replacement text on clipboard
        ClipboardManager.copy(context.replacement)

        // Activate the target application
        activateTargetApp(context)

        // Wait for activation
        try? await Task.sleep(nanoseconds: UInt64(TimingConstants.longDelay * 1_000_000_000))

        // Try menu-based paste first
        var pasteSucceeded = tryMenuPaste(context)

        // Fall back to keyboard paste
        if !pasteSucceeded {
            let delay = keyboardDelay(for: context.appConfig)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            pressKey(key: VirtualKeyCode.v, flags: .maskCommand)
            pasteSucceeded = true
            Logger.debug("KeyboardReplacement: Pasted via Cmd+V", category: Logger.analysis)
        }

        // Wait for paste to complete
        try? await Task.sleep(nanoseconds: UInt64(0.15 * 1_000_000_000))

        // Restore clipboard
        ClipboardManager.restoreAfterDelay(savedState, delay: TimingConstants.clipboardRestoreDelay)

        Logger.info(
            "KeyboardReplacement: Replaced '\(context.errorText)' with '\(context.replacement)'",
            category: Logger.analysis
        )

        // Electron apps can't verify replacement, return unverified
        return .unverified
    }

    // MARK: - App Activation

    /// Activate the target application to receive keyboard events
    private func activateTargetApp(_ context: ReplacementContext) {
        guard let bundleID = context.appConfig.bundleIDs.first else { return }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let targetApp = apps.first {
            targetApp.activate()
            Logger.debug("KeyboardReplacement: Activated \(context.appConfig.displayName)", category: Logger.analysis)
        }
    }

    // MARK: - Menu Paste

    /// Try to paste via Edit > Paste menu action
    /// Returns true if menu paste succeeded
    private func tryMenuPaste(_ context: ReplacementContext) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        guard let pasteMenuItem = findPasteMenuItem(in: appElement) else {
            return false
        }

        let result = AXUIElementPerformAction(pasteMenuItem, kAXPressAction as CFString)
        if result == .success {
            Logger.debug("KeyboardReplacement: Pasted via menu action", category: Logger.analysis)
            return true
        }

        return false
    }

    /// Find the Paste menu item in the application's menu bar
    private func findPasteMenuItem(in appElement: AXUIElement) -> AXUIElement? {
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarRef = menuBarValue,
              CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let menuBar = unsafeBitCast(menuBarRef, to: AXUIElement.self)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String,
               title.lowercased().contains("edit") {

                var menuChildrenValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &menuChildrenValue) == .success,
                   let menuChildren = menuChildrenValue as? [AXUIElement] {

                    for menuChild in menuChildren {
                        var itemChildrenValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(menuChild, kAXChildrenAttribute as CFString, &itemChildrenValue) == .success,
                           let items = itemChildrenValue as? [AXUIElement] {

                            for item in items {
                                var itemTitleValue: CFTypeRef?
                                if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &itemTitleValue) == .success,
                                   let itemTitle = itemTitleValue as? String,
                                   itemTitle.lowercased().contains("paste") {
                                    return item
                                }
                            }
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Keyboard Events

    /// Get keyboard operation delay for the app
    private func keyboardDelay(for appConfig: AppConfiguration) -> TimeInterval {
        // Most Electron apps work with minimal delay
        return TimingConstants.shortDelay
    }

    /// Simulate a key press event
    private func pressKey(key: CGKeyCode, flags: CGEventFlags) {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            Logger.debug("KeyboardReplacement: Failed to create CGEventSource", category: Logger.analysis)
            return
        }

        // Apply macOS Control modifier bug workaround
        var adjustedFlags = flags
        if flags.contains(.maskControl) {
            adjustedFlags.insert(.maskSecondaryFn)
        }

        if let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: true) {
            keyDown.flags = adjustedFlags
            keyDown.post(tap: .cghidEventTap)
        }

        if let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: false) {
            keyUp.flags = adjustedFlags
            keyUp.post(tap: .cghidEventTap)
        }

        // Small delay between key events
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}
