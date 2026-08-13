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
/// All operations reserve a per-process slot from `AXWatchdog`; the bounded queue allows
/// unrelated applications to proceed while a problematic app is cooling down.
enum AXAsyncBridge {
    /// Concurrent executor. `AXClient` provides the global bound and the
    /// one-in-flight-call-per-process guarantee.
    private static let axQueue = DispatchQueue(
        label: "com.textwarden.ax-operations",
        qos: .userInitiated,
        attributes: .concurrent
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
                // AccessibilityBridge reserves the process atomically.
                let result = AccessibilityBridge.getElementFrame(element)
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
                guard let call = AXClient.perform(
                    bundleID: bundleID,
                    attribute: "AXValue",
                    operation: {
                        var value: CFTypeRef?
                        let result = AXUIElementCopyAttributeValue(
                            element,
                            kAXValueAttribute as CFString,
                            &value
                        )
                        return (result: result, value: value)
                    }
                ) else {
                    Logger.debug("AXAsyncBridge.extractTextValue: No execution slot for \(bundleID)", category: Logger.accessibility)
                    continuation.resume(returning: nil)
                    return
                }
                let result = call.value.result
                let value = call.value.value

                if result == .success, let textValue = value as? String {
                    continuation.resume(returning: textValue)
                } else {
                    Logger.debug("AXAsyncBridge.extractTextValue: \(AXClient.outcome(for: result)) for \(bundleID)", category: Logger.accessibility)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
