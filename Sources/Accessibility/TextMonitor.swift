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

        let msg1 = "📍 TextMonitor: startMonitoring for \(appName) (PID: \(processID))"
        NSLog(msg1)
        logToDebugFile(msg1)

        let context = ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: appName
        )

        guard context.shouldCheck() else {
            let msg = "⏸️ TextMonitor: Grammar checking disabled for \(appName)"
            NSLog(msg)
            logToDebugFile(msg)
            return
        }

        self.currentContext = context

        // Create AXUIElement for the application
        let appElement = AXUIElementCreateApplication(processID)

        // Enable manual accessibility for Electron apps (and all apps)
        // This is required for Electron apps like Slack, Discord, VS Code, etc.
        // Without this, Electron apps don't expose their accessibility hierarchy
        // unless VoiceOver is running. This is how Grammarly and LanguageTool work.
        let manualAccessibilityResult = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )

        if manualAccessibilityResult == .success {
            let msg = "✅ TextMonitor: Enabled AXManualAccessibility for \(appName)"
            NSLog(msg)
            logToDebugFile(msg)
        } else {
            let msg = "⚠️ TextMonitor: Could not enable AXManualAccessibility (error: \(manualAccessibilityResult.rawValue)) - app might still work"
            NSLog(msg)
            logToDebugFile(msg)
        }

        // Create observer
        var observerRef: AXObserver?
        let error = AXObserverCreate(processID, axObserverCallback, &observerRef)

        guard error == .success, let observer = observerRef else {
            let msg = "❌ TextMonitor: Failed to create AX observer for \(appName): \(error.rawValue)"
            NSLog(msg)
            logToDebugFile(msg)
            return
        }

        self.observer = observer
        let msg2 = "✅ TextMonitor: Created AX observer for \(appName)"
        NSLog(msg2)
        logToDebugFile(msg2)

        // Add observer to run loop
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        let msg3 = "✅ TextMonitor: Added observer to run loop"
        NSLog(msg3)
        logToDebugFile(msg3)

        // Try to monitor focused element
        monitorFocusedElement(in: appElement)

        // Add notification for focus changes
        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        let focusResult = AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            contextPtr
        )

        let msg4 = "✅ TextMonitor: Added focus change notification (result: \(focusResult.rawValue))"
        NSLog(msg4)
        logToDebugFile(msg4)
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
        let msg1 = "🔍 TextMonitor: Getting focused element..."
        NSLog(msg1)
        logToDebugFile(msg1)

        var focusedElement: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard error == .success, let element = focusedElement else {
            let msg = "❌ TextMonitor: Failed to get focused element: \(error.rawValue)"
            NSLog(msg)
            logToDebugFile(msg)
            return
        }

        let msg2 = "✅ TextMonitor: Got focused element, checking if editable..."
        NSLog(msg2)
        logToDebugFile(msg2)

        let axElement = element as! AXUIElement
        monitorElement(axElement)
    }

    /// Monitor a specific UI element for text changes
    fileprivate func monitorElement(_ element: AXUIElement) {
        let msg1 = "🎯 TextMonitor: monitorElement called"
        NSLog(msg1)
        logToDebugFile(msg1)

        guard let observer = observer else {
            let msg = "❌ TextMonitor: No observer available"
            NSLog(msg)
            logToDebugFile(msg)
            return
        }

        // CRITICAL: Only monitor editable text fields, not read-only content
        // This prevents checking terminal output, chat history, etc.
        guard isEditableElement(element) else {
            let msg = "⏭️ TextMonitor: Skipping non-editable element"
            NSLog(msg)
            logToDebugFile(msg)
            return
        }

        // Remove previous notifications if any
        if let previousElement = monitoredElement {
            AXObserverRemoveNotification(
                observer,
                previousElement,
                kAXValueChangedNotification as CFString
            )
            let msg = "🗑️ TextMonitor: Removed previous element monitoring"
            NSLog(msg)
            logToDebugFile(msg)
        }

        monitoredElement = element
        let msg2 = "✅ TextMonitor: Now monitoring editable text field"
        NSLog(msg2)
        logToDebugFile(msg2)

        // Add value changed notification
        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(
            observer,
            element,
            kAXValueChangedNotification as CFString,
            contextPtr
        )

        let msg3 = "📡 TextMonitor: Added value changed notification (result: \(result.rawValue))"
        NSLog(msg3)
        logToDebugFile(msg3)

        if result == .success {
            let msg4 = "📄 TextMonitor: Extracting initial text..."
            NSLog(msg4)
            logToDebugFile(msg4)
            // Extract initial text
            extractText(from: element)
        } else {
            let msg = "❌ TextMonitor: Failed to add value changed notification: \(result.rawValue)"
            NSLog(msg)
            logToDebugFile(msg)
        }
    }

    /// Maximum text length to analyze (prevent analyzing huge terminal buffers)
    private let maxTextLength = 100_000

    /// Extract text from UI element (T035)
    func extractText(from element: AXUIElement) {
        let msg1 = "📤 TextMonitor: extractText called"
        NSLog(msg1)
        logToDebugFile(msg1)

        var value: CFTypeRef?

        // Try to get AXValue (text content)
        let valueError = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        var extractedText: String?

        if valueError == .success, let textValue = value as? String {
            let msg = "✅ TextMonitor: Got AXValue text (\(textValue.count) chars)"
            NSLog(msg)
            logToDebugFile(msg)
            // Log first 200 chars to see what we're actually getting
            let preview = String(textValue.prefix(200))
            let previewMsg = "📄 TextMonitor: Text preview: \"\(preview)\""
            NSLog(previewMsg)
            logToDebugFile(previewMsg)
            extractedText = textValue
        } else {
            let msg = "⚠️ TextMonitor: Failed to get AXValue (error: \(valueError.rawValue)), trying AXSelectedText"
            NSLog(msg)
            logToDebugFile(msg)
            // Fallback: try AXSelectedText
            var selectedText: CFTypeRef?
            let selectedError = AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                &selectedText
            )

            if selectedError == .success, let selected = selectedText as? String {
                let msg2 = "✅ TextMonitor: Got AXSelectedText (\(selected.count) chars)"
                NSLog(msg2)
                logToDebugFile(msg2)
                extractedText = selected
            } else {
                let msg2 = "❌ TextMonitor: Failed to get AXSelectedText (error: \(selectedError.rawValue))"
                NSLog(msg2)
                logToDebugFile(msg2)
            }
        }

        if let text = extractedText, !text.isEmpty {
            // Skip analyzing huge text buffers (terminals, logs, etc.)
            if text.count > maxTextLength {
                let msg = "⏭️ TextMonitor: Text too long (\(text.count) chars) - skipping analysis"
                NSLog(msg)
                logToDebugFile(msg)
                return
            }

            // Apply app-specific text preprocessing
            guard let context = currentContext else {
                let msg = "⚠️ TextMonitor: No current context available"
                NSLog(msg)
                logToDebugFile(msg)
                return
            }

            let parser = ContentParserFactory.shared.parser(for: context.bundleIdentifier)
            guard let processedText = parser.preprocessText(text) else {
                let msg = "⏭️ TextMonitor: Preprocessing filtered out text - skipping analysis"
                NSLog(msg)
                logToDebugFile(msg)
                return
            }

            let msg = "✅ TextMonitor: Handling text change (\(processedText.count) chars after preprocessing)"
            NSLog(msg)
            logToDebugFile(msg)

            // Log the preprocessed text that will be grammar-checked
            let preprocessedPreview = String(processedText.prefix(200))
            let preprocessedMsg = "📝 TextMonitor: Preprocessed text for grammar checking: \"\(preprocessedPreview)\""
            NSLog(preprocessedMsg)
            logToDebugFile(preprocessedMsg)

            handleTextChange(processedText)
        } else {
            let msg = "⚠️ TextMonitor: No text extracted or text is empty"
            NSLog(msg)
            logToDebugFile(msg)
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
    let msg1 = "🔔 axObserverCallback: Received notification: \(notification as String)"
    NSLog(msg1)
    logToDebugFile(msg1)

    guard let userData = userData else {
        let msg = "❌ axObserverCallback: No userData"
        NSLog(msg)
        logToDebugFile(msg)
        return
    }

    let monitor = Unmanaged<TextMonitor>.fromOpaque(userData).takeUnretainedValue()

    let notificationName = notification as String

    switch notificationName {
    case kAXValueChangedNotification as String:
        let msg = "📝 axObserverCallback: Value changed - extracting text"
        NSLog(msg)
        logToDebugFile(msg)
        monitor.extractText(from: element)

    case kAXFocusedUIElementChangedNotification as String:
        let msg = "🎯 axObserverCallback: Focus changed - monitoring new element"
        NSLog(msg)
        logToDebugFile(msg)
        monitor.monitorElement(element)

    default:
        let msg = "❓ axObserverCallback: Unknown notification: \(notificationName)"
        NSLog(msg)
        logToDebugFile(msg)
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
            let msg = "⚠️ TextMonitor: Could not get role for element"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        let roleMsg = "🔍 TextMonitor: Checking element with role: \(roleString)"
        NSLog(roleMsg)
        logToDebugFile(roleMsg)

        // Check if it's a static text element (read-only)
        // These are what we want to EXCLUDE (terminal output, chat history)
        let readOnlyRoles = [
            kAXStaticTextRole as String,
            "AXScrollArea",          // Often used for terminal buffers
            "AXGroup",                // Generic groups (often contain read-only content)
            "AXLayoutArea"           // Layout areas (not direct input)
        ]

        if readOnlyRoles.contains(roleString) {
            let msg = "⏭️ TextMonitor: Role '\(roleString)' is read-only - skipping"
            NSLog(msg)
            logToDebugFile(msg)
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
            let msg = "⏭️ TextMonitor: Role '\(roleString)' is not in editable whitelist - skipping"
            NSLog(msg)
            logToDebugFile(msg)
            return false
        }

        // For all other roles, check if the element has AXValue and is enabled
        // This allows TextEdit, TextFields, TextAreas, etc.
        let msg = "✅ TextMonitor: Role '\(roleString)' is editable, checking attributes..."
        NSLog(msg)
        logToDebugFile(msg)

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
