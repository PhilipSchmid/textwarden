//
//  AXAsyncBridge.swift
//  TextWarden
//
//  Async wrappers for Accessibility API calls.
//  Executes AX operations on a dedicated background queue to prevent main thread blocking.
//

@preconcurrency import ApplicationServices
import Foundation

/// Async wrappers for Accessibility API calls.
///
/// This bridge moves AX operations off the main thread to prevent UI sluggishness
/// during slow AX calls (particularly common with Notion, Outlook, and other Electron apps).
///
/// All operations respect the `AXWatchdog` blocklist and busy-guard to prevent
/// pile-up of blocked calls.
enum AXAsyncBridge {
    /// Dedicated serial queue for AX operations.
    /// Using serial queue ensures calls don't pile up and provides predictable ordering.
    private static let axQueue = DispatchQueue(
        label: "com.textwarden.ax-operations",
        qos: .userInitiated
    )

    // MARK: - Element Properties

    /// Get element frame asynchronously.
    ///
    /// - Parameters:
    ///   - element: The AXUIElement to get the frame for
    ///   - bundleID: Bundle identifier for watchdog tracking
    /// - Returns: The element's frame in Quartz coordinates, or nil if unavailable or blocked
    static func getElementFrame(
        _ element: AXUIElement,
        bundleID: String
    ) async -> CGRect? {
        guard !AXWatchdog.shared.shouldSkipCalls(for: bundleID) else {
            Logger.debug("AXAsyncBridge.getElementFrame: Skipping \(bundleID) - watchdog protection active", category: Logger.accessibility)
            return nil
        }

        return await withCheckedContinuation { continuation in
            axQueue.async {
                AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXFrame")
                let result = AccessibilityBridge.getElementFrame(element)
                AXWatchdog.shared.endCall()
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Text Extraction

    /// Extract text value from element asynchronously.
    ///
    /// - Parameters:
    ///   - element: The AXUIElement to extract text from
    ///   - bundleID: Bundle identifier for watchdog tracking
    /// - Returns: The text content, or nil if unavailable or blocked
    static func extractTextValue(
        from element: AXUIElement,
        bundleID: String
    ) async -> String? {
        guard !AXWatchdog.shared.shouldSkipCalls(for: bundleID) else {
            Logger.debug("AXAsyncBridge.extractTextValue: Skipping \(bundleID) - watchdog protection active", category: Logger.accessibility)
            return nil
        }

        return await withCheckedContinuation { continuation in
            axQueue.async {
                AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXValue")

                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(
                    element,
                    kAXValueAttribute as CFString,
                    &value
                )

                AXWatchdog.shared.endCall()

                if result == .success, let textValue = value as? String {
                    continuation.resume(returning: textValue)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
