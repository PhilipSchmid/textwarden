//
//  TextMonitor.swift
//  Gnau
//
//  Monitors text changes in accessible applications using AX API
//

import Foundation
import ApplicationServices
import Combine

/// Monitors text changes in applications via Accessibility API
class TextMonitor: ObservableObject {
    /// Published text changes
    @Published private(set) var currentText: String = ""

    /// Current application context
    @Published private(set) var currentContext: ApplicationContext?

    /// AX observer for the current application
    private var observer: AXObserver?

    /// Current UI element being monitored
    internal var monitoredElement: AXUIElement?

    /// Debounce timer for text changes
    private var debounceTimer: Timer?

    /// Debounce interval in seconds
    private let debounceInterval: TimeInterval = 0.1  // 100ms

    /// Callback for text changes
    var onTextChange: ((String, ApplicationContext) -> Void)?

    /// Start monitoring an application
    func startMonitoring(processID: pid_t, bundleIdentifier: String, appName: String) {
        stopMonitoring()

        let context = ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: appName
        )

        guard context.shouldCheck() else {
            print("Grammar checking disabled for \(appName)")
            return
        }

        self.currentContext = context

        // Create AXUIElement for the application
        let appElement = AXUIElementCreateApplication(processID)

        // Create observer
        var observerRef: AXObserver?
        let error = AXObserverCreate(processID, axObserverCallback, &observerRef)

        guard error == .success, let observer = observerRef else {
            print("Failed to create AX observer: \(error.rawValue)")
            return
        }

        self.observer = observer

        // Add observer to run loop
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        // Try to monitor focused element
        monitorFocusedElement(in: appElement)

        // Add notification for focus changes
        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            contextPtr
        )
    }

    /// Stop monitoring
    func stopMonitoring() {
        if let observer = observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }

        observer = nil
        monitoredElement = nil
        currentContext = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    /// Monitor the focused UI element
    private func monitorFocusedElement(in appElement: AXUIElement) {
        var focusedElement: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard error == .success, let element = focusedElement else {
            print("Failed to get focused element: \(error.rawValue)")
            return
        }

        let axElement = element as! AXUIElement
        monitorElement(axElement)
    }

    /// Monitor a specific UI element for text changes
    fileprivate func monitorElement(_ element: AXUIElement) {
        guard let observer = observer else { return }

        // CRITICAL: Only monitor editable text fields, not read-only content
        // This prevents checking terminal output, chat history, etc.
        guard isEditableElement(element) else {
            print("⏭️ TextMonitor: Skipping non-editable element")
            return
        }

        // Remove previous notifications if any
        if let previousElement = monitoredElement {
            AXObserverRemoveNotification(
                observer,
                previousElement,
                kAXValueChangedNotification as CFString
            )
        }

        monitoredElement = element
        print("✅ TextMonitor: Now monitoring editable text field")

        // Add value changed notification
        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(
            observer,
            element,
            kAXValueChangedNotification as CFString,
            contextPtr
        )

        if result == .success {
            // Extract initial text
            extractText(from: element)
        }
    }

    /// Maximum text length to analyze (prevent analyzing huge terminal buffers)
    private let maxTextLength = 10_000

    /// Extract text from UI element (T035)
    func extractText(from element: AXUIElement) {
        var value: CFTypeRef?

        // Try to get AXValue (text content)
        let valueError = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        var extractedText: String?

        if valueError == .success, let textValue = value as? String {
            extractedText = textValue
        } else {
            // Fallback: try AXSelectedText
            var selectedText: CFTypeRef?
            let selectedError = AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                &selectedText
            )

            if selectedError == .success, let selected = selectedText as? String {
                extractedText = selected
            }
        }

        if let text = extractedText, !text.isEmpty {
            // Skip analyzing huge text buffers (terminals, logs, etc.)
            if text.count > maxTextLength {
                print("⏭️ TextMonitor: Text too long (\(text.count) chars) - skipping analysis")
                return
            }

            handleTextChange(text)
        }
    }

    /// Handle text change with debouncing (T036)
    private func handleTextChange(_ text: String) {
        // Invalidate existing timer
        debounceTimer?.invalidate()

        // Create new timer
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            guard let self = self, let context = self.currentContext else { return }

            DispatchQueue.main.async {
                self.currentText = text
                self.onTextChange?(text, context)
            }
        }
    }
}

// MARK: - AX Observer Callback

/// Callback function for AX observer notifications
private func axObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData = userData else { return }

    let monitor = Unmanaged<TextMonitor>.fromOpaque(userData).takeUnretainedValue()

    let notificationName = notification as String

    switch notificationName {
    case kAXValueChangedNotification as String:
        monitor.extractText(from: element)

    case kAXFocusedUIElementChangedNotification as String:
        monitor.monitorElement(element)

    default:
        break
    }
}

// MARK: - Helper Extensions

extension TextMonitor {
    /// Check if element is an editable text field (not read-only content)
    func isEditableElement(_ element: AXUIElement) -> Bool {
        // Check role
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        guard let roleString = role as? String else {
            print("⚠️ TextMonitor: Could not get role for element")
            return false
        }

        print("🔍 TextMonitor: Checking element with role: \(roleString)")

        // Check if it's a static text element (read-only)
        // These are what we want to EXCLUDE (terminal output, chat history)
        let readOnlyRoles = [
            kAXStaticTextRole as String,
            "AXScrollArea",          // Often used for terminal buffers
            "AXGroup",                // Generic groups (often contain read-only content)
            "AXLayoutArea"           // Layout areas (not direct input)
        ]

        if readOnlyRoles.contains(roleString) {
            print("⏭️ TextMonitor: Role '\(roleString)' is read-only - skipping")
            return false
        }

        // Only allow known editable roles
        let editableRoles = [
            kAXTextFieldRole as String,   // Single-line text input
            kAXTextAreaRole as String,    // Multi-line text input
            kAXComboBoxRole as String     // Combo boxes with text input
        ]

        if !editableRoles.contains(roleString) {
            print("⏭️ TextMonitor: Role '\(roleString)' is not in editable whitelist - skipping")
            return false
        }

        // For all other roles, check if the element has AXValue and is enabled
        // This allows TextEdit, TextFields, TextAreas, etc.
        print("✅ TextMonitor: Role '\(roleString)' is editable, checking attributes...")

        // Additional check: verify element is not read-only
        // Some text areas might be marked as read-only
        var isEnabled: CFTypeRef?
        let enabledResult = AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &isEnabled
        )

        // If we can check enabled status, ensure it's enabled
        if enabledResult == .success, let enabled = isEnabled as? Bool {
            return enabled
        }

        // If we can't check, assume editable (to avoid false negatives)
        return true
    }

    /// Legacy compatibility - use isEditableElement instead
    func supportsTextMonitoring(_ element: AXUIElement) -> Bool {
        return isEditableElement(element)
    }
}
