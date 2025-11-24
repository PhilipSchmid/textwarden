//
//  TextMonitor.swift
//  TextWarden
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
    private let debounceInterval: TimeInterval = 0.05  // 50ms for snappier UX

    /// Callback for text changes
    var onTextChange: ((String, ApplicationContext) -> Void)?

    /// Retry scheduler for accessibility API operations
    private let retryScheduler = RetryScheduler(config: .accessibilityAPI)

    /// Start monitoring an application
    func startMonitoring(processID: pid_t, bundleIdentifier: String, appName: String) {
        stopMonitoring()

        Logger.debug("TextMonitor: startMonitoring for \(appName) (PID: \(processID))", category: Logger.accessibility)

        let context = ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: appName
        )

        guard context.shouldCheck() else {
            Logger.debug("TextMonitor: Grammar checking disabled for \(appName)", category: Logger.accessibility)
            return
        }

        self.currentContext = context

        let appElement = AXUIElementCreateApplication(processID)

        // Enable manual accessibility for Electron apps (and all apps)
        // This is required for Electron apps like Slack, Discord, VS Code, etc.
        // Without this, Electron apps don't expose their accessibility hierarchy
        // unless VoiceOver is running.
        let manualAccessibilityResult = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )

        if manualAccessibilityResult == .success {
            Logger.debug("TextMonitor: Enabled AXManualAccessibility for \(appName)", category: Logger.accessibility)
        } else {
            Logger.debug("TextMonitor: Could not enable AXManualAccessibility (error: \(manualAccessibilityResult.rawValue)) - app might still work", category: Logger.accessibility)
        }

        var observerRef: AXObserver?
        let error = AXObserverCreate(processID, axObserverCallback, &observerRef)

        guard error == .success, let observer = observerRef else {
            Logger.debug("TextMonitor: Failed to create AX observer for \(appName): \(error.rawValue)", category: Logger.accessibility)
            return
        }

        self.observer = observer
        Logger.debug("TextMonitor: Created AX observer for \(appName)", category: Logger.accessibility)

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        Logger.debug("TextMonitor: Added observer to run loop", category: Logger.accessibility)

        // Try to monitor focused element
        monitorFocusedElement(in: appElement)

        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        let focusResult = AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            contextPtr
        )

        Logger.debug("TextMonitor: Added focus change notification (result: \(focusResult.rawValue))", category: Logger.accessibility)
    }

    /// Stop monitoring
    func stopMonitoring() {
        // Cancel any pending retry attempts
        retryScheduler.cancel()

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
    private func monitorFocusedElement(in appElement: AXUIElement, retryAttempt: Int = 0) {
        let maxAttempts = RetryConfig.accessibilityAPI.maxAttempts
        Logger.debug("TextMonitor: Getting focused element... (attempt \(retryAttempt + 1)/\(maxAttempts + 1))", category: Logger.accessibility)

        var focusedElement: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard error == .success, let element = focusedElement else {
            // Retry if we haven't reached max attempts
            if retryAttempt < maxAttempts {
                scheduleRetry(attempt: retryAttempt) { [weak self] in
                    self?.monitorFocusedElement(in: appElement, retryAttempt: retryAttempt + 1)
                }
                Logger.debug("TextMonitor: Failed to get focused element (\(error.rawValue)), will retry...", category: Logger.accessibility)
            } else {
                Logger.debug("TextMonitor: Failed to get focused element after \(maxAttempts + 1) attempts: \(error.rawValue)", category: Logger.accessibility)
            }
            return
        }

        Logger.debug("TextMonitor: Got focused element, checking if editable...", category: Logger.accessibility)

        let axElement = element as! AXUIElement

        // CRITICAL FIX: AXFocusedUIElement might return the wrong element (e.g., sidebar in Slack)
        // If the focused element is not editable, search for editable text fields
        if !isEditableElement(axElement) {
            Logger.debug("TextMonitor: Focused element is not editable, searching for editable field...", category: Logger.accessibility)

            // Strategy 1: Search children of focused element
            if let editableChild = findEditableChild(in: axElement) {
                Logger.debug("TextMonitor: Found editable child in focused element!", category: Logger.accessibility)
                monitorElement(editableChild, retryAttempt: retryAttempt)
                return
            }

            // Strategy 2: Search from main window down
            Logger.debug("TextMonitor: No children found, searching from main window...", category: Logger.accessibility)

            if let editableInWindow = findEditableInMainWindow(appElement) {
                Logger.debug("TextMonitor: Found editable field in main window!", category: Logger.accessibility)
                monitorElement(editableInWindow, retryAttempt: retryAttempt)
                return
            }

            Logger.debug("TextMonitor: No editable field found, will monitor focused element anyway", category: Logger.accessibility)
        }

        monitorElement(axElement, retryAttempt: retryAttempt)
    }

    /// Schedule a retry using RetryScheduler configuration
    private func scheduleRetry(attempt: Int, action: @escaping () -> Void) {
        // Cancel any existing retry
        retryScheduler.cancel()

        // Calculate delay using RetryConfig
        let config = RetryConfig.accessibilityAPI
        let delay = config.delay(for: attempt)

        Logger.debug("TextMonitor: Scheduling retry \(attempt + 1) in \(String(format: "%.3f", delay))s", category: Logger.accessibility)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }

    /// Monitor a specific UI element for text changes
    fileprivate func monitorElement(_ element: AXUIElement, retryAttempt: Int = 0) {
        let maxAttempts = RetryConfig.accessibilityAPI.maxAttempts
        Logger.debug("TextMonitor: monitorElement called (attempt \(retryAttempt + 1)/\(maxAttempts + 1))", category: Logger.accessibility)

        guard let observer = observer else {
            Logger.debug("TextMonitor: No observer available", category: Logger.accessibility)
            return
        }

        // CRITICAL: Only monitor editable text fields, not read-only content
        // This prevents checking terminal output, chat history, etc.
        guard isEditableElement(element) else {
            // Retry if we haven't reached max attempts and this isn't explicitly a read-only role
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            let roleString = role as? String ?? "Unknown"

            let readOnlyRoles = [
                kAXStaticTextRole as String,
                "AXScrollArea",
                "AXLayoutArea"
            ]

            // Only retry if it's not explicitly a read-only role (e.g., AXGroup might become editable)
            if retryAttempt < maxAttempts && !readOnlyRoles.contains(roleString) {
                scheduleRetry(attempt: retryAttempt) { [weak self] in
                    self?.monitorElement(element, retryAttempt: retryAttempt + 1)
                }
                Logger.debug("TextMonitor: Element not editable yet (role: \(roleString)), will retry...", category: Logger.accessibility)
            } else {
                Logger.debug("TextMonitor: Skipping non-editable element (role: \(roleString))", category: Logger.accessibility)
            }
            return
        }

        // Cancel any pending retries since we found an editable element
        retryScheduler.cancel()

        if let previousElement = monitoredElement {
            AXObserverRemoveNotification(
                observer,
                previousElement,
                kAXValueChangedNotification as CFString
            )
            Logger.debug("TextMonitor: Removed previous element monitoring", category: Logger.accessibility)
        }

        monitoredElement = element
        Logger.debug("TextMonitor: Now monitoring editable text field", category: Logger.accessibility)

        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(
            observer,
            element,
            kAXValueChangedNotification as CFString,
            contextPtr
        )

        Logger.debug("TextMonitor: Added value changed notification (result: \(result.rawValue))", category: Logger.accessibility)

        if result == .success {
            Logger.debug("TextMonitor: Extracting initial text...", category: Logger.accessibility)
            // Extract initial text
            extractText(from: element)
        } else {
            Logger.debug("TextMonitor: Failed to add value changed notification: \(result.rawValue)", category: Logger.accessibility)
        }
    }

    /// Maximum text length to analyze (prevent analyzing huge terminal buffers)
    private let maxTextLength = 100_000

    /// Extract text from UI element (T035)
    func extractText(from element: AXUIElement) {
        Logger.debug("TextMonitor: extractText called", category: Logger.accessibility)

        var value: CFTypeRef?

        // Try to get AXValue (text content)
        let valueError = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        var extractedText: String?

        if valueError == .success, let textValue = value as? String {
            Logger.debug("TextMonitor: Got AXValue text (\(textValue.count) chars)", category: Logger.accessibility)
            // Log first 200 chars to see what we're actually getting
            let preview = String(textValue.prefix(200))
            Logger.debug("TextMonitor: Text preview: \"\(preview)\"", category: Logger.accessibility)
            extractedText = textValue
        } else {
            Logger.debug("TextMonitor: Failed to get AXValue (error: \(valueError.rawValue)), trying AXSelectedText", category: Logger.accessibility)
            // Fallback: try AXSelectedText
            var selectedText: CFTypeRef?
            let selectedError = AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                &selectedText
            )

            if selectedError == .success, let selected = selectedText as? String {
                Logger.debug("TextMonitor: Got AXSelectedText (\(selected.count) chars)", category: Logger.accessibility)
                extractedText = selected
            } else {
                Logger.debug("TextMonitor: Failed to get AXSelectedText (error: \(selectedError.rawValue))", category: Logger.accessibility)
            }
        }

        if let text = extractedText, !text.isEmpty {
            // Skip analyzing huge text buffers (terminals, logs, etc.)
            if text.count > maxTextLength {
                Logger.debug("TextMonitor: Text too long (\(text.count) chars) - skipping analysis", category: Logger.accessibility)
                return
            }

            // Apply app-specific text preprocessing
            guard let context = currentContext else {
                Logger.debug("TextMonitor: No current context available", category: Logger.accessibility)
                return
            }

            let parser = ContentParserFactory.shared.parser(for: context.bundleIdentifier)
            guard let processedText = parser.preprocessText(text) else {
                Logger.debug("TextMonitor: Preprocessing filtered out text - skipping analysis", category: Logger.accessibility)
                return
            }

            Logger.debug("TextMonitor: Handling text change (\(processedText.count) chars after preprocessing)", category: Logger.accessibility)

            // Log the preprocessed text that will be grammar-checked
            let preprocessedPreview = String(processedText.prefix(200))
            Logger.debug("TextMonitor: Preprocessed text for grammar checking: \"\(preprocessedPreview)\"", category: Logger.accessibility)

            handleTextChange(processedText)
        } else {
            Logger.debug("TextMonitor: No text extracted or text is empty", category: Logger.accessibility)
        }
    }

    /// Handle text change with debouncing (T036)
    private func handleTextChange(_ text: String) {
        // Invalidate existing timer
        debounceTimer?.invalidate()

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
    Logger.debug("axObserverCallback: Received notification: \(notification as String)", category: Logger.accessibility)

    guard let userData = userData else {
        Logger.debug("axObserverCallback: No userData", category: Logger.accessibility)
        return
    }

    let monitor = Unmanaged<TextMonitor>.fromOpaque(userData).takeUnretainedValue()

    let notificationName = notification as String

    switch notificationName {
    case kAXValueChangedNotification as String:
        Logger.debug("axObserverCallback: Value changed - extracting text", category: Logger.accessibility)
        monitor.extractText(from: element)

    case kAXFocusedUIElementChangedNotification as String:
        Logger.debug("axObserverCallback: Focus changed - monitoring new element", category: Logger.accessibility)
        monitor.monitorElement(element)

    default:
        Logger.debug("axObserverCallback: Unknown notification: \(notificationName)", category: Logger.accessibility)
        break
    }
}

// MARK: - Helper Extensions

extension TextMonitor {
    /// Search for editable field from main window
    /// This is more reliable than AXFocusedUIElement for Electron apps
    private func findEditableInMainWindow(_ appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            &windowRef
        )

        if result != .success {
            // Try focused window instead
            result = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &windowRef
            )
        }

        guard result == .success, let window = windowRef else {
            Logger.debug("TextMonitor: Could not get main/focused window", category: Logger.accessibility)
            return nil
        }

        let windowElement = window as! AXUIElement

        Logger.debug("TextMonitor: Searching main window for editable field...", category: Logger.accessibility)

        // Search window hierarchy for editable text field
        return findEditableChild(in: windowElement, maxDepth: 10)
    }

    /// Recursively search for an editable child element
    /// This is needed for Electron apps like Slack where AXFocusedUIElement returns wrong element
    private func findEditableChild(in element: AXUIElement, maxDepth: Int = 5, currentDepth: Int = 0) -> AXUIElement? {
        // Prevent infinite recursion
        guard currentDepth < maxDepth else {
            return nil
        }

        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )

        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        Logger.debug("TextMonitor: Searching \(children.count) children at depth \(currentDepth)...", category: Logger.accessibility)

        // First pass: look for direct editable children
        for child in children {
            if isEditableElement(child) {
                return child
            }
        }

        // Second pass: recursively search children
        for child in children {
            if let editableDescendant = findEditableChild(in: child, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                return editableDescendant
            }
        }

        return nil
    }

    /// Check if element is an editable text field (not read-only content)
    func isEditableElement(_ element: AXUIElement) -> Bool {
        // Check role
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        guard let roleString = role as? String else {
            Logger.debug("TextMonitor: Could not get role for element", category: Logger.accessibility)
            return false
        }

        Logger.debug("TextMonitor: Checking element with role: \(roleString)", category: Logger.accessibility)

        // Check if it's a static text element (read-only)
        // These are what we want to EXCLUDE (terminal output, chat history)
        let readOnlyRoles = [
            kAXStaticTextRole as String,
            "AXScrollArea",          // Often used for terminal buffers
            "AXGroup",                // Generic groups (often contain read-only content)
            "AXLayoutArea"           // Layout areas (not direct input)
        ]

        if readOnlyRoles.contains(roleString) {
            Logger.debug("TextMonitor: Role '\(roleString)' is read-only - skipping", category: Logger.accessibility)
            return false
        }

        // Only allow known editable roles
        let editableRoles = [
            kAXTextFieldRole as String,   // Single-line text input
            kAXTextAreaRole as String,    // Multi-line text input
            kAXComboBoxRole as String,    // Combo boxes with text input
            "AXWebArea",                  // Web content area (Electron/Chrome)
            "AXTextField",                // Web-based text fields (Electron/Chrome)
            "AXTextMarker",               // Contenteditable areas (Electron/Chrome)
            "AXHTMLElement"               // HTML elements with contenteditable (Electron)
        ]

        if !editableRoles.contains(roleString) {
            Logger.debug("TextMonitor: Role '\(roleString)' is not in editable whitelist - skipping", category: Logger.accessibility)
            return false
        }

        // For all other roles, check if the element has AXValue and is enabled
        // This allows TextEdit, TextFields, TextAreas, etc.
        Logger.debug("TextMonitor: Role '\(roleString)' is editable, checking attributes...", category: Logger.accessibility)

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

}
