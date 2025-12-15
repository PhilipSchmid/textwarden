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
@MainActor
class TextMonitor: ObservableObject {

    // MARK: - Published State

    /// Published text changes
    @Published private(set) var currentText: String = ""

    /// Current application context
    @Published private(set) var currentContext: ApplicationContext?

    // MARK: - Private State

    /// AX observer for the current application
    private var observer: AXObserver?

    /// Current UI element being monitored
    internal var monitoredElement: AXUIElement?

    /// Debounce timer for text changes
    private var debounceTimer: Timer?

    /// Default debounce interval in seconds
    private let defaultDebounceInterval: TimeInterval = TimingConstants.defaultDebounce

    /// Extended debounce for Chromium apps that require delayed positioning
    /// Slack and other Chromium apps need cursor manipulation for accurate positioning,
    /// which can only happen after typing stops. Longer debounce = less cursor interference.
    private let chromiumDebounceInterval: TimeInterval = TimingConstants.chromiumDebounce

    /// Get the appropriate debounce interval for the current app
    private var debounceInterval: TimeInterval {
        guard let bundleID = currentContext?.bundleIdentifier else {
            return defaultDebounceInterval
        }

        // Use AppRegistry to determine if app needs typing pause
        let appConfig = AppRegistry.shared.configuration(for: bundleID)
        if appConfig.features.requiresTypingPause {
            return chromiumDebounceInterval
        }

        return defaultDebounceInterval
    }

    // MARK: - Callbacks

    /// Callback for text changes (after debounce)
    var onTextChange: ((String, ApplicationContext) -> Void)?

    /// Callback for immediate text changes (before debounce) - used to hide overlays immediately
    var onImmediateTextChange: ((String, ApplicationContext) -> Void)?

    /// Retry scheduler for accessibility API operations
    private let retryScheduler = RetryScheduler(config: .accessibilityAPI)

    /// Tracked work item for retry cancellation
    private var retryWorkItem: DispatchWorkItem?

    // MARK: - Monitoring Control

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
        cancelPendingRetries()

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

        // CFGetTypeID check ensures this is an AXUIElement before casting
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
            Logger.warning("TextMonitor: Focused element is not AXUIElement type", category: Logger.accessibility)
            return
        }
        // Safe: type verified by CFGetTypeID check above
        let axElement = unsafeBitCast(element, to: AXUIElement.self)

        // CRITICAL FIX: AXFocusedUIElement might return the wrong element (e.g., sidebar in Slack)
        // If the focused element is not editable, search for editable text fields
        var needsAlternativeElement = !isEditableElement(axElement)

        // App-specific check: Some apps (like Word) may return toolbar elements as focused
        // even though they pass isEditableElement. Check with the parser.
        if !needsAlternativeElement, let bundleID = currentContext?.bundleIdentifier {
            needsAlternativeElement = !isValidContentElement(axElement, bundleID: bundleID)
        }

        if needsAlternativeElement {
            Logger.debug("TextMonitor: Focused element is not suitable, searching for content field...", category: Logger.accessibility)

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

            // Strategy 3 (Word-specific): Use parser to find document element
            if let bundleID = currentContext?.bundleIdentifier, bundleID == "com.microsoft.Word" {
                if let documentElement = WordContentParser.findDocumentElement(from: axElement) {
                    Logger.debug("TextMonitor: Found Word document element via parser!", category: Logger.accessibility)
                    monitorElement(documentElement, retryAttempt: retryAttempt)
                    return
                }
            }

            // Note: PowerPoint Notes section uses standard AXTextArea and is found by normal monitoring
            // Slide text boxes are not accessible via macOS Accessibility API

            Logger.debug("TextMonitor: No suitable field found, will monitor focused element anyway", category: Logger.accessibility)
        }

        monitorElement(axElement, retryAttempt: retryAttempt)
    }

    /// Schedule a retry using RetryScheduler configuration
    private func scheduleRetry(attempt: Int, action: @escaping () -> Void) {
        // Cancel any existing retry (both the scheduler and our tracked work item)
        retryScheduler.cancel()
        retryWorkItem?.cancel()
        retryWorkItem = nil

        // Calculate delay using RetryConfig
        let config = RetryConfig.accessibilityAPI
        let delay = config.delay(for: attempt)

        Logger.debug("TextMonitor: Scheduling retry \(attempt + 1) in \(String(format: "%.3f", delay))s", category: Logger.accessibility)

        // Create and track a cancellable work item
        let workItem = DispatchWorkItem(block: action)
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Cancel any pending retries
    private func cancelPendingRetries() {
        retryScheduler.cancel()
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }

    /// Monitor a specific UI element for text changes
    fileprivate func monitorElement(_ element: AXUIElement, retryAttempt: Int = 0) {
        let maxAttempts = RetryConfig.accessibilityAPI.maxAttempts
        Logger.debug("TextMonitor: monitorElement called (attempt \(retryAttempt + 1)/\(maxAttempts + 1))", category: Logger.accessibility)

        guard let observer = observer else {
            Logger.debug("TextMonitor: No observer available", category: Logger.accessibility)
            return
        }

        // For browsers, skip UI elements like search fields, URL bars, find-in-page
        // These are not meaningful for grammar checking - we want actual web content
        if let bundleID = currentContext?.bundleIdentifier,
           AppRegistry.shared.configuration(for: bundleID).parserType == .browser {
            if BrowserContentParser.isBrowserUIElement(element) {
                Logger.debug("TextMonitor: Skipping browser UI element (not web content)", category: Logger.accessibility)
                // Clear any existing monitoring and notify to hide overlays
                if let previousElement = monitoredElement {
                    AXObserverRemoveNotification(observer, previousElement, kAXValueChangedNotification as CFString)
                }
                monitoredElement = nil
                currentText = ""
                // Notify that we've stopped monitoring (this will trigger overlay hiding)
                if let context = currentContext {
                    onTextChange?("", context)
                }
                return
            }
        }

        // For Apple Mail, skip non-composition elements (sidebar folders, message list, search)
        // Only check text in actual email composition areas (new mail, reply, forward)
        // Mail's WebKit fires focus events for parent AXGroup elements even while editing,
        // so preserve the monitored element if it's already a valid composition area.
        if let bundleID = currentContext?.bundleIdentifier,
           AppRegistry.shared.configuration(for: bundleID).parserType == .mail {
            if !MailContentParser.isMailCompositionElement(element) {
                // If we already have a valid composition element monitored, preserve it
                // and just ignore this non-composition focus event
                if let existingElement = monitoredElement,
                   MailContentParser.isMailCompositionElement(existingElement) {
                    Logger.trace("TextMonitor: Ignoring non-composition Mail focus event - preserving existing composition element", category: Logger.accessibility)
                    return
                }

                Logger.debug("TextMonitor: Skipping non-composition Mail element (sidebar/list/search)", category: Logger.accessibility)
                // Clear any existing monitoring and notify to hide overlays
                if let previousElement = monitoredElement {
                    AXObserverRemoveNotification(observer, previousElement, kAXValueChangedNotification as CFString)
                }
                monitoredElement = nil
                currentText = ""
                // Notify that we've stopped monitoring (this will trigger overlay hiding)
                if let context = currentContext {
                    onTextChange?("", context)
                }
                return
            }
        }

        // For PowerPoint, focus bounces rapidly between elements when clicking in the Notes area.
        // PowerPoint only exposes the Notes section via accessibility API (slide text boxes are not accessible).
        // If we already have a valid monitored Notes element (AXTextArea), preserve it when focus
        // bounces to non-editable elements (AXGroup, AXUnknown, AXScrollArea, etc.).
        if let bundleID = currentContext?.bundleIdentifier,
           bundleID == "com.microsoft.Powerpoint",
           let existingElement = monitoredElement {

            // Check if new element is the Notes AXTextArea
            var newRoleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &newRoleRef)
            let newRole = newRoleRef as? String ?? ""

            // Only AXTextArea is valid for Notes - PowerPoint doesn't expose slide text via accessibility
            let newIsNotesTextArea = (newRole == kAXTextAreaRole as String)

            if newIsNotesTextArea {
                // New element is also a Notes text area - allow the switch
                Logger.debug("TextMonitor: PowerPoint - new AXTextArea detected, allowing switch", category: Logger.accessibility)
                // Continue with normal monitoring
            } else {
                // New element is NOT editable - this is focus bounce noise, preserve existing
                var existingValueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(existingElement, kAXValueAttribute as CFString, &existingValueRef) == .success,
                   existingValueRef != nil {
                    Logger.debug("TextMonitor: PowerPoint focus bounce - preserving existing monitoring", category: Logger.accessibility)
                    return  // Keep monitoring existing element, ignore this focus change
                }
            }
        }

        // CRITICAL: Only monitor editable text fields, not read-only content
        // This prevents checking terminal output, chat history, etc.
        guard isEditableElement(element) else {
            // Retry if we haven't reached max attempts and this isn't explicitly a read-only role
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            let roleString = role as? String ?? "Unknown"

            // Roles that are definitively non-editable - don't retry, clear monitoring immediately
            // This ensures overlays hide promptly when focus moves to navigation elements
            let readOnlyRoles: Set<String> = [
                kAXStaticTextRole as String,  // Static labels
                "AXScrollArea",               // Scroll containers
                "AXLayoutArea",               // Layout containers
                "AXTable",                    // Tables (e.g., WebEx conversation list)
                "AXWindow",                   // Window itself
                "AXList",                     // List views
                "AXOutline"                   // Tree/outline views (e.g., sidebar navigation)
            ]

            // Only retry if it's not explicitly a read-only role (e.g., AXGroup might become editable)
            if retryAttempt < maxAttempts && !readOnlyRoles.contains(roleString) {
                scheduleRetry(attempt: retryAttempt) { [weak self] in
                    self?.monitorElement(element, retryAttempt: retryAttempt + 1)
                }
                Logger.debug("TextMonitor: Element not editable yet (role: \(roleString)), will retry...", category: Logger.accessibility)
            } else {
                Logger.debug("TextMonitor: Skipping non-editable element (role: \(roleString)) - clearing monitoring", category: Logger.accessibility)
                // Clear monitoring and notify to hide overlays - focus moved to non-editable element
                if let previousElement = monitoredElement {
                    AXObserverRemoveNotification(observer, previousElement, kAXValueChangedNotification as CFString)
                }
                monitoredElement = nil
                currentText = ""
                // Notify that we've stopped monitoring (this will trigger overlay hiding)
                if let context = currentContext {
                    onTextChange?("", context)
                }
            }
            return
        }

        // Cancel any pending retries since we found an editable element
        cancelPendingRetries()

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

            // Trigger profiling for unknown apps (does nothing if app has explicit config)
            if let bundleID = currentContext?.bundleIdentifier {
                StrategyRecommendationEngine.shared.onTextMonitoringStarted(
                    element: element,
                    bundleID: bundleID
                )
            }
        } else {
            Logger.debug("TextMonitor: Failed to add value changed notification: \(result.rawValue)", category: Logger.accessibility)
        }
    }

    // MARK: - Text Extraction

    /// Maximum text length to analyze (prevent analyzing huge terminal buffers)
    private let maxTextLength = 100_000

    /// Extract text from UI element
    func extractText(from element: AXUIElement) {
        Logger.debug("TextMonitor: extractText called", category: Logger.accessibility)

        var extractedText: String?

        // First, try app-specific extraction via ContentParser
        // This allows apps like Apple Mail to use custom extraction logic
        if let bundleID = currentContext?.bundleIdentifier {
            let parser = ContentParserFactory.shared.parser(for: bundleID)
            if let parserText = parser.extractText(from: element) {
                Logger.debug("TextMonitor: Got text from parser (\(parserText.count) chars)", category: Logger.accessibility)
                extractedText = parserText
            }
        }

        // Fall back to standard AXValue extraction
        if extractedText == nil {
            var value: CFTypeRef?
            let valueError = AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &value
            )

            if valueError == .success, let textValue = value as? String, !textValue.isEmpty {
                Logger.debug("TextMonitor: Got AXValue text (\(textValue.count) chars)", category: Logger.accessibility)
                extractedText = textValue
            } else {
                Logger.debug("TextMonitor: AXValue empty or failed (error: \(valueError.rawValue)), trying AXSelectedText", category: Logger.accessibility)
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
            handleTextChange(processedText)
        } else {
            Logger.debug("TextMonitor: No text extracted or text is empty", category: Logger.accessibility)
        }
    }

    /// Handle text change with debouncing
    private func handleTextChange(_ text: String) {
        guard let context = currentContext else { return }

        // IMMEDIATE: Notify about text change right away (before debounce)
        // This allows hiding overlays immediately when typing starts
        onImmediateTextChange?(text, context)

        // Notify typing detector for all apps
        // This enables hiding underlines during typing for Electron apps (Slack, Notion, etc.)
        TypingDetector.shared.notifyTextChange()

        // Also notify ChromiumStrategy for its internal cache/cursor management
        ChromiumStrategy.notifyTextChange()

        // Invalidate existing timer
        debounceTimer?.invalidate()

        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
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

    // Dispatch to main actor since TextMonitor is @MainActor isolated
    Task { @MainActor in
        if notificationName == kAXValueChangedNotification as String {
            Logger.debug("axObserverCallback: Value changed - extracting text", category: Logger.accessibility)
            monitor.extractText(from: element)
        } else if notificationName == kAXFocusedUIElementChangedNotification as String {
            Logger.debug("axObserverCallback: Focus changed - monitoring new element", category: Logger.accessibility)
            monitor.monitorElement(element)
        } else {
            Logger.debug("axObserverCallback: Unknown notification: \(notificationName)", category: Logger.accessibility)
        }
    }
}

// MARK: - Element Discovery

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

        // CFGetTypeID check ensures this is an AXUIElement before casting
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else {
            Logger.warning("TextMonitor: Window is not AXUIElement type", category: Logger.accessibility)
            return nil
        }
        // Safe: type verified by CFGetTypeID check above
        let windowElement = unsafeBitCast(window, to: AXUIElement.self)

        Logger.debug("TextMonitor: Searching main window for editable field...", category: Logger.accessibility)

        // Search window hierarchy for editable text field
        return findEditableChild(in: windowElement, maxDepth: 10)
    }

    /// Maximum elements to check during traversal to prevent freezing on large hierarchies (e.g., Apple Mail)
    private static let maxTraversalElements = 200

    /// Roles that are containers unlikely to contain editable text - skip recursing into these
    /// Note: AXGroup is NOT included because some apps (e.g., Apple Mail compose) nest editable content in groups
    private static let nonEditableContainerRoles: Set<String> = [
        "AXCell",           // Table cells (email list rows)
        "AXRow",            // Table rows
        "AXColumn",         // Table columns
        "AXTable",          // Tables (email lists, spreadsheet-like views)
        "AXOutline",        // Outline views (folder trees)
        "AXOutlineRow",     // Outline rows
        "AXList",           // List views
        "AXBrowser",        // Browser/column views
        "AXImage",          // Images
        "AXButton",         // Buttons
        "AXCheckBox",       // Checkboxes
        "AXRadioButton",    // Radio buttons
        "AXMenuItem",       // Menu items
        "AXMenuBar",        // Menu bar
        "AXMenu",           // Menus
        "AXToolbar",        // Toolbars
        "AXStaticText"      // Static text (read-only)
    ]

    /// Recursively search for an editable child element
    /// This is needed for Electron apps like Slack where AXFocusedUIElement returns wrong element
    private func findEditableChild(in element: AXUIElement, maxDepth: Int = 5, currentDepth: Int = 0, elementsChecked: inout Int) -> AXUIElement? {
        // Prevent infinite recursion and runaway traversal
        guard currentDepth < maxDepth else {
            return nil
        }

        guard elementsChecked < Self.maxTraversalElements else {
            Logger.warning("TextMonitor: Traversal limit reached (\(Self.maxTraversalElements) elements) - stopping search", category: Logger.accessibility)
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

        // Limit children to check at each level to prevent explosion
        let childrenToCheck = children.prefix(50)

        Logger.trace("TextMonitor: Searching \(childrenToCheck.count) children at depth \(currentDepth)...", category: Logger.accessibility)

        // First pass: look for direct editable children
        for child in childrenToCheck {
            elementsChecked += 1
            if elementsChecked >= Self.maxTraversalElements {
                return nil
            }

            if isEditableElement(child) {
                // Additional check: for Word, ensure element is valid content (not toolbar)
                if let bundleID = currentContext?.bundleIdentifier {
                    if !isValidContentElement(child, bundleID: bundleID) {
                        Logger.trace("TextMonitor: Skipping element - not valid content for app", category: Logger.accessibility)
                        continue
                    }
                }
                return child
            }
        }

        // Second pass: recursively search children, but skip non-editable containers
        for child in childrenToCheck {
            // Get role to check if we should skip recursing
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            if let roleString = role as? String, Self.nonEditableContainerRoles.contains(roleString) {
                // Skip recursing into containers that won't have editable content
                continue
            }

            if let editableDescendant = findEditableChild(in: child, maxDepth: maxDepth, currentDepth: currentDepth + 1, elementsChecked: &elementsChecked) {
                return editableDescendant
            }
        }

        return nil
    }

    /// Wrapper for findEditableChild that initializes the element counter
    private func findEditableChild(in element: AXUIElement, maxDepth: Int = 5, currentDepth: Int = 0) -> AXUIElement? {
        var elementsChecked = 0
        return findEditableChild(in: element, maxDepth: maxDepth, currentDepth: currentDepth, elementsChecked: &elementsChecked)
    }

    /// Check if element is an editable text field (not read-only content)
    func isEditableElement(_ element: AXUIElement) -> Bool {
        // Check role
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        guard let roleString = role as? String else {
            Logger.trace("TextMonitor: Could not get role for element", category: Logger.accessibility)
            return false
        }

        Logger.trace("TextMonitor: Checking element with role: \(roleString)", category: Logger.accessibility)

        // Check if it's a static text element (read-only)
        // These are what we want to EXCLUDE (terminal output, chat history)
        let readOnlyRoles = [
            kAXStaticTextRole as String,
            "AXScrollArea",          // Often used for terminal buffers
            "AXGroup"                // Generic groups (often contain read-only content)
        ]

        if readOnlyRoles.contains(roleString) {
            Logger.trace("TextMonitor: Role '\(roleString)' is read-only - skipping", category: Logger.accessibility)
            return false
        }

        // AXLayoutArea is usually read-only, but PowerPoint uses it for editable text boxes
        if roleString == "AXLayoutArea" {
            if let bundleID = currentContext?.bundleIdentifier,
               bundleID == "com.microsoft.Powerpoint" {
                // PowerPoint uses AXLayoutArea for slide text boxes - check if it has content
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
                    Logger.trace("TextMonitor: PowerPoint AXLayoutArea with AXValue - accepting", category: Logger.accessibility)
                    return true
                }
            }
            Logger.trace("TextMonitor: Role 'AXLayoutArea' is read-only - skipping", category: Logger.accessibility)
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
            Logger.trace("TextMonitor: Role '\(roleString)' is not in editable whitelist - skipping", category: Logger.accessibility)
            return false
        }

        // For all other roles, check if the element has AXValue and is enabled
        // This allows TextEdit, TextFields, TextAreas, etc.
        Logger.trace("TextMonitor: Role '\(roleString)' is editable, checking attributes...", category: Logger.accessibility)

        // Additional check: verify element is not read-only
        // Some text areas might be marked as read-only
        var isEnabled: CFTypeRef?
        let enabledResult = AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &isEnabled
        )

        // If we can check enabled status, ensure it's enabled
        let bundleID = currentContext?.bundleIdentifier ?? "unknown"
        Logger.trace("TextMonitor: Enabled check result=\(enabledResult.rawValue), bundleID=\(bundleID)", category: Logger.accessibility)

        if enabledResult == .success, let enabled = isEnabled as? Bool {
            Logger.trace("TextMonitor: AXEnabled=\(enabled) for role \(roleString)", category: Logger.accessibility)
            if !enabled {
                // Microsoft Office AXTextArea reports AXEnabled=false even when editable
                // Accept AXTextArea for Word/PowerPoint since we've validated via content parser
                if roleString == kAXTextAreaRole as String,
                   (bundleID == "com.microsoft.Word" || bundleID == "com.microsoft.Powerpoint") {
                    Logger.trace("TextMonitor: Office AXTextArea reports disabled, but accepting anyway", category: Logger.accessibility)
                    return true
                }
            }
            return enabled
        }

        // If we can't check, assume editable (to avoid false negatives)
        Logger.trace("TextMonitor: Could not check enabled status, assuming editable", category: Logger.accessibility)
        return true
    }

    /// Check if element is valid content for the specific app (not toolbar/UI element)
    /// Some apps like Word return toolbar elements as focused even though they're technically editable
    private func isValidContentElement(_ element: AXUIElement, bundleID: String) -> Bool {
        // Word-specific check: filter out toolbar/ribbon elements
        if bundleID == "com.microsoft.Word" {
            let isDocument = WordContentParser.isDocumentElement(element)
            if !isDocument {
                Logger.trace("TextMonitor: Word element rejected by parser (likely toolbar)", category: Logger.accessibility)
            }
            return isDocument
        }

        // PowerPoint-specific check: filter out toolbar/ribbon elements
        if bundleID == "com.microsoft.Powerpoint" {
            let isSlide = PowerPointContentParser.isSlideElement(element)
            if !isSlide {
                Logger.trace("TextMonitor: PowerPoint element rejected by parser (likely toolbar)", category: Logger.accessibility)
            }
            return isSlide
        }

        // For other apps, assume the element is valid
        return true
    }

}
