#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

enum DriverError: Error, CustomStringConvertible {
    case usage(String)
    case failure(String)

    var description: String {
        switch self {
        case let .usage(message), let .failure(message): message
        }
    }
}

func number(_ value: String, name: String) throws -> CGFloat {
    guard let parsed = Double(value), parsed.isFinite else {
        throw DriverError.usage("invalid \(name): \(value)")
    }
    return CGFloat(parsed)
}

func runningApplication(_ bundleIdentifier: String) throws -> NSRunningApplication {
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    guard let application = applications.first else {
        throw DriverError.failure("application is not running: \(bundleIdentifier)")
    }
    if let frontmost = NSWorkspace.shared.frontmostApplication,
       frontmost.bundleIdentifier == bundleIdentifier
    {
        return frontmost
    }
    return application
}

func activate(_ bundleIdentifier: String) throws -> NSRunningApplication {
    let application = try runningApplication(bundleIdentifier)
    guard application.activate(options: [.activateAllWindows]) else {
        throw DriverError.failure("activation request failed: \(bundleIdentifier)")
    }

    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
            return application
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    throw DriverError.failure("application did not become frontmost: \(bundleIdentifier)")
}

func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return value
}

func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    copyAttribute(element, attribute) as? String
}

func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool {
    (copyAttribute(element, attribute) as? Bool) == true
}

func axElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
}

func axValue(_ value: CFTypeRef?) -> AXValue? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXValue.self)
}

func focusedWindow(_ application: NSRunningApplication) throws -> AXUIElement {
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    if let window = axElement(copyAttribute(appElement, kAXFocusedWindowAttribute as CFString)) {
        return window
    }
    if let window = axElement(copyAttribute(appElement, kAXMainWindowAttribute as CFString)) {
        return window
    }
    throw DriverError.failure("application has no focused window: \(application.bundleIdentifier ?? "unknown")")
}

func minimizedWindow(_ application: NSRunningApplication) throws -> AXUIElement {
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    let windows = copyAttribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement]
    let minimizedWindows = windows?.filter { boolAttribute($0, kAXMinimizedAttribute as CFString) } ?? []
    guard minimizedWindows.count == 1, let window = minimizedWindows.first else {
        throw DriverError.failure("expected exactly one minimized window")
    }
    return window
}

func pointAttribute(_ element: AXUIElement, _ attribute: CFString) throws -> CGPoint {
    guard let value = axValue(copyAttribute(element, attribute)),
          AXValueGetType(value) == .cgPoint
    else {
        throw DriverError.failure("window does not expose \(attribute)")
    }
    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else {
        throw DriverError.failure("could not read \(attribute)")
    }
    return point
}

func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) throws -> CGSize {
    guard let value = axValue(copyAttribute(element, attribute)),
          AXValueGetType(value) == .cgSize
    else {
        throw DriverError.failure("window does not expose \(attribute)")
    }
    var size = CGSize.zero
    guard AXValueGetValue(value, .cgSize, &size) else {
        throw DriverError.failure("could not read \(attribute)")
    }
    return size
}

func setPoint(_ element: AXUIElement, _ attribute: CFString, _ point: CGPoint) throws {
    var point = point
    guard let value = AXValueCreate(.cgPoint, &point),
          AXUIElementSetAttributeValue(element, attribute, value) == .success
    else {
        throw DriverError.failure("could not set \(attribute)")
    }
}

func setSize(_ element: AXUIElement, _ attribute: CFString, _ size: CGSize) throws {
    var size = size
    guard let value = AXValueCreate(.cgSize, &size),
          AXUIElementSetAttributeValue(element, attribute, value) == .success
    else {
        throw DriverError.failure("could not set \(attribute)")
    }
}

func frameMatches(
    position: CGPoint,
    size: CGSize,
    expectedPosition: CGPoint,
    expectedSize: CGSize,
    tolerance: CGFloat = 2
) -> Bool {
    abs(position.x - expectedPosition.x) <= tolerance
        && abs(position.y - expectedPosition.y) <= tolerance
        && abs(size.width - expectedSize.width) <= tolerance
        && abs(size.height - expectedSize.height) <= tolerance
}

func postMouse(_ type: CGEventType, at point: CGPoint) throws {
    guard let event = CGEvent(
        mouseEventSource: CGEventSource(stateID: .hidSystemState),
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else {
        throw DriverError.failure("could not create mouse event")
    }
    event.post(tap: .cghidEventTap)
}

func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
        throw DriverError.failure("could not create keyboard event")
    }
    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    usleep(50_000)
    keyUp.post(tap: .cghidEventTap)
}

func isSafeTextInput(_ text: String) -> Bool {
    text.count <= 500 && !text.contains("\n") && !text.contains("\r")
}

func postText(_ text: String) throws {
    guard isSafeTextInput(text) else {
        throw DriverError.failure("refusing unsafe text input")
    }

    for character in text {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            throw DriverError.failure("could not create text event")
        }
        let utf16 = Array(String(character).utf16)
        utf16.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        keyDown.post(tap: .cghidEventTap)
        usleep(20_000)
        keyUp.post(tap: .cghidEventTap)
    }
}

struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
}

func pasteText(_ text: String) throws {
    guard isSafeTextInput(text) else {
        throw DriverError.failure("refusing unsafe text input")
    }
    let pasteboard = NSPasteboard.general
    let snapshot = ClipboardSnapshot(items: (pasteboard.pasteboardItems ?? []).map { item in
        Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
            item.data(forType: type).map { (type, $0) }
        })
    })
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
        throw DriverError.failure("could not set temporary clipboard text")
    }
    let replacementChangeCount = pasteboard.changeCount
    try postKey(9, flags: .maskCommand)
    usleep(300_000)

    guard pasteboard.changeCount == replacementChangeCount else { return }
    pasteboard.clearContents()
    let restoredItems = snapshot.items.compactMap { representations -> NSPasteboardItem? in
        guard !representations.isEmpty else { return nil }
        let item = NSPasteboardItem()
        for (type, data) in representations {
            item.setData(data, forType: type)
        }
        return item
    }
    if !restoredItems.isEmpty {
        pasteboard.writeObjects(restoredItems)
    }
}

func editorAt(_ point: CGPoint) -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success else {
        return nil
    }

    var candidate = element
    for _ in 0 ..< 10 {
        guard let current = candidate else { return nil }
        let role = stringAttribute(current, kAXRoleAttribute as CFString)
        if boolAttribute(current, "AXEditable" as CFString)
            || role == kAXTextAreaRole as String
            || role == kAXTextFieldRole as String
        {
            return current
        }
        candidate = axElement(copyAttribute(current, kAXParentAttribute as CFString))
    }
    return nil
}

func isEditable(_ element: AXUIElement) -> Bool {
    let role = stringAttribute(element, kAXRoleAttribute as CFString)
    return boolAttribute(element, "AXEditable" as CFString)
        || role == kAXTextAreaRole as String
        || role == kAXTextFieldRole as String
}

func elementFrame(_ element: AXUIElement) -> CGRect? {
    guard let positionValue = axValue(copyAttribute(element, kAXPositionAttribute as CFString)),
          AXValueGetType(positionValue) == .cgPoint,
          let sizeValue = axValue(copyAttribute(element, kAXSizeAttribute as CFString)),
          AXValueGetType(sizeValue) == .cgSize
    else {
        return nil
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &position),
          AXValueGetValue(sizeValue, .cgSize, &size),
          size.width > 0,
          size.height > 0
    else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

func collectEditors(_ root: AXUIElement, remaining: inout Int, into editors: inout [AXUIElement]) {
    guard remaining > 0 else { return }
    remaining -= 1

    if isEditable(root), elementFrame(root) != nil {
        editors.append(root)
    }

    let children = copyAttribute(root, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    for child in children {
        collectEditors(child, remaining: &remaining, into: &editors)
    }
}

func editors(in application: NSRunningApplication) -> [AXUIElement] {
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    var remaining = 10_000
    var editors: [AXUIElement] = []
    collectEditors(appElement, remaining: &remaining, into: &editors)
    return editors
}

func textLength(_ element: AXUIElement) -> Int? {
    if let value = directTextValue(element) {
        return value.utf16.count
    }
    return copyAttribute(element, kAXNumberOfCharactersAttribute as CFString) as? Int
}

func directTextValue(_ element: AXUIElement) -> String? {
    if let value = copyAttribute(element, kAXValueAttribute as CFString) as? String {
        return value
    }
    return (copyAttribute(element, kAXValueAttribute as CFString) as? NSAttributedString)?.string
}

func textValue(_ element: AXUIElement) -> String? {
    if let value = directTextValue(element) {
        return value
    }
    guard let length = copyAttribute(
        element,
        kAXNumberOfCharactersAttribute as CFString
    ) as? Int,
        (0 ... 100_000).contains(length)
    else {
        return nil
    }
    guard length > 0 else { return "" }

    var range = CFRange(location: 0, length: length)
    guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXStringForRangeParameterizedAttribute as CFString,
        rangeValue,
        &value
    ) == .success else {
        return nil
    }
    return value as? String
}

func focusedEditor(_ application: NSRunningApplication) throws -> AXUIElement {
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    guard let element = axElement(copyAttribute(appElement, kAXFocusedUIElementAttribute as CFString)),
          isEditable(element)
    else {
        throw DriverError.failure("application has no focused editable element")
    }
    return element
}

func elementAt(_ point: CGPoint) -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success else { return nil }
    return element
}

func processIDAt(_ point: CGPoint) -> pid_t? {
    guard let element = elementAt(point) else { return nil }

    var processID: pid_t = 0
    return AXUIElementGetPid(element, &processID) == .success ? processID : nil
}

func supportsAction(_ element: AXUIElement, _ action: CFString) -> Bool {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let names = names as? [String]
    else {
        return false
    }
    return names.contains(action as String)
}

func isRiskyControl(_ element: AXUIElement) -> Bool {
    let riskyLabels = ["send", "submit", "post", "publish", "share"]
    var candidate: AXUIElement? = element
    for _ in 0 ..< 5 {
        guard let current = candidate else { return false }
        if supportsAction(current, kAXPressAction as CFString) {
            let labels = [
                stringAttribute(current, kAXTitleAttribute as CFString),
                stringAttribute(current, kAXDescriptionAttribute as CFString),
                stringAttribute(current, kAXHelpAttribute as CFString),
            ].compactMap { $0?.lowercased() }
            return labels.contains { label in riskyLabels.contains(where: label.contains) }
        }
        candidate = axElement(copyAttribute(current, kAXParentAttribute as CFString))
    }
    return false
}

func findPressableElement(
    _ root: AXUIElement,
    label: String,
    allowShortcutSuffix: Bool = false,
    requiresPressAction: Bool = true,
    occurrence: inout Int,
    remaining: inout Int
) -> AXUIElement? {
    guard remaining > 0 else { return nil }
    remaining -= 1

    let labels = [
        stringAttribute(root, kAXTitleAttribute as CFString),
        stringAttribute(root, kAXDescriptionAttribute as CFString),
        stringAttribute(root, kAXValueAttribute as CFString),
    ]
    let normalizedLabel = label.lowercased()
    let hasMatchingLabel = labels.compactMap { $0?.lowercased() }.contains { candidate in
        candidate == normalizedLabel
            || (allowShortcutSuffix && candidate.hasPrefix(normalizedLabel))
    }
    if (!requiresPressAction || supportsAction(root, kAXPressAction as CFString)),
       hasMatchingLabel
    {
        if occurrence == 0 {
            return root
        }
        occurrence -= 1
    }

    let children = copyAttribute(root, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    for child in children {
        if let match = findPressableElement(
            child,
            label: label,
            allowShortcutSuffix: allowShortcutSuffix,
            requiresPressAction: requiresPressAction,
            occurrence: &occurrence,
            remaining: &remaining
        ) {
            return match
        }
    }
    return nil
}

func isSelfChatLabel(_ label: String) -> Bool {
    let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "saved messages"
        || normalized == "message yourself"
        || normalized == "note to self"
        || normalized.contains("(you)")
}

func findSelfChatElement(
    _ root: AXUIElement,
    requiresPressAction: Bool,
    remaining: inout Int
) -> AXUIElement? {
    guard remaining > 0 else { return nil }
    remaining -= 1

    let labels = [
        stringAttribute(root, kAXTitleAttribute as CFString),
        stringAttribute(root, kAXDescriptionAttribute as CFString),
        stringAttribute(root, kAXValueAttribute as CFString),
    ]
    if (!requiresPressAction || supportsAction(root, kAXPressAction as CFString)),
       labels.compactMap({ $0 }).contains(where: isSelfChatLabel)
    {
        return root
    }

    let children = copyAttribute(root, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    for child in children {
        if let match = findSelfChatElement(
            child,
            requiresPressAction: requiresPressAction,
            remaining: &remaining
        ) {
            return match
        }
    }
    return nil
}

func printWindowState(bundleIdentifier: String, application: NSRunningApplication, window: AXUIElement) throws {
    let position = try pointAttribute(window, kAXPositionAttribute as CFString)
    let size = try sizeAttribute(window, kAXSizeAttribute as CFString)
    let state: [String: Any] = [
        "bundleIdentifier": bundleIdentifier,
        "pid": application.processIdentifier,
        "x": position.x,
        "y": position.y,
        "width": size.width,
        "height": size.height,
        "minimized": boolAttribute(window, kAXMinimizedAttribute as CFString),
    ]
    let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func printApplicationWindows(_ bundleIdentifier: String) throws {
    let processIDs = Set(
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
    )
    guard !processIDs.isEmpty else {
        throw DriverError.failure("application is not running: \(bundleIdentifier)")
    }
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    let windows = windowInfo.compactMap { info -> [String: Any]? in
        guard let processID = info[kCGWindowOwnerPID as String] as? pid_t,
              processIDs.contains(processID),
              let layer = info[kCGWindowLayer as String] as? Int,
              layer == 0,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"],
              let y = bounds["Y"],
              let width = bounds["Width"],
              let height = bounds["Height"]
        else {
            return nil
        }
        return [
            "height": height,
            "pid": processID,
            "width": width,
            "x": x,
            "y": y,
        ]
    }
    let data = try JSONSerialization.data(withJSONObject: windows, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func printPointState(_ point: CGPoint) throws {
    guard let element = elementAt(point) else {
        throw DriverError.failure("no accessibility element at point")
    }

    var processID: pid_t = 0
    _ = AXUIElementGetPid(element, &processID)
    var roles: [String] = []
    var candidate: AXUIElement? = element
    for _ in 0 ..< 20 {
        guard let current = candidate else { break }
        roles.append(stringAttribute(current, kAXRoleAttribute as CFString) ?? "unknown")
        candidate = axElement(copyAttribute(current, kAXParentAttribute as CFString))
    }

    let state: [String: Any] = [
        "pid": processID,
        "x": point.x,
        "y": point.y,
        "roles": roles,
    ]
    let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func printFocusedElementState(_ application: NSRunningApplication) throws {
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    var focusedValue: CFTypeRef?
    let focusedResult = AXUIElementCopyAttributeValue(
        appElement,
        kAXFocusedUIElementAttribute as CFString,
        &focusedValue
    )
    let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"

    guard focusedResult == .success, let focused = axElement(focusedValue) else {
        let state: [String: Any] = [
            "focused": false,
            "focusedElementError": focusedResult.rawValue,
            "frontmostBundleIdentifier": frontmostBundleIdentifier,
        ]
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        return
    }

    var selectedTextValue: CFTypeRef?
    let selectedTextResult = AXUIElementCopyAttributeValue(
        focused,
        kAXSelectedTextAttribute as CFString,
        &selectedTextValue
    )
    var selectedRangeValue: CFTypeRef?
    let selectedRangeResult = AXUIElementCopyAttributeValue(
        focused,
        kAXSelectedTextRangeAttribute as CFString,
        &selectedRangeValue
    )
    var selectedRange = CFRange(location: -1, length: -1)
    if selectedRangeResult == .success, let rangeValue = axValue(selectedRangeValue) {
        _ = AXValueGetValue(rangeValue, .cfRange, &selectedRange)
    }

    var selectedRangeSettable = DarwinBoolean(false)
    _ = AXUIElementIsAttributeSettable(
        focused,
        kAXSelectedTextRangeAttribute as CFString,
        &selectedRangeSettable
    )
    var selectedMarkerRangeSettable = DarwinBoolean(false)
    _ = AXUIElementIsAttributeSettable(
        focused,
        "AXSelectedTextMarkerRange" as CFString,
        &selectedMarkerRangeSettable
    )
    var parameterizedNames: CFArray?
    _ = AXUIElementCopyParameterizedAttributeNames(focused, &parameterizedNames)
    var focusedAttributeSettable = DarwinBoolean(false)
    _ = AXUIElementIsAttributeSettable(
        focused,
        kAXFocusedAttribute as CFString,
        &focusedAttributeSettable
    )

    let state: [String: Any] = [
        "focused": true,
        "focusedAttributeSettable": focusedAttributeSettable.boolValue,
        "frontmostBundleIdentifier": frontmostBundleIdentifier,
        "identity": String(CFHash(focused), radix: 16),
        "parameterizedAttributes": (parameterizedNames as? [String])?.sorted() ?? [],
        "role": stringAttribute(focused, kAXRoleAttribute as CFString) ?? "unknown",
        "selectedMarkerRangeSettable": selectedMarkerRangeSettable.boolValue,
        "selectedRangeError": selectedRangeResult.rawValue,
        "selectedRangeLength": selectedRange.length,
        "selectedRangeLocation": selectedRange.location,
        "selectedRangeSettable": selectedRangeSettable.boolValue,
        "selectedTextError": selectedTextResult.rawValue,
        "selectedTextUTF16Length": (selectedTextValue as? String)?.utf16.count ?? -1,
        "utf16Length": textLength(focused) ?? -1,
    ]
    let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

let textWardenBundleIdentifier = "io.textwarden.TextWarden"
let appPauseDurationsKey = "appPauseDurations"
let appPausedUntilKey = "appPausedUntil"

func textWardenPreferences() throws -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: textWardenBundleIdentifier) else {
        throw DriverError.failure("could not open TextWarden preferences")
    }
    return defaults
}

func decodedPreference<Value: Decodable>(
    _ type: Value.Type,
    key: String,
    defaults: UserDefaults
) throws -> Value {
    guard let data = defaults.data(forKey: key) else {
        throw DriverError.failure("TextWarden preference is unavailable: \(key)")
    }
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw DriverError.failure("could not decode TextWarden preference: \(key)")
    }
}

func persistPreference(_ value: some Encodable, key: String, defaults: UserDefaults) throws {
    do {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
        guard defaults.synchronize() else {
            throw DriverError.failure("could not persist TextWarden preference: \(key)")
        }
    } catch let error as DriverError {
        throw error
    } catch {
        throw DriverError.failure("could not encode TextWarden preference: \(key)")
    }
}

func printAppPauseState(_ bundleIdentifier: String) throws {
    let defaults = try textWardenPreferences()
    let durations = try decodedPreference(
        [String: String].self,
        key: appPauseDurationsKey,
        defaults: defaults
    )
    let pausedUntil = try decodedPreference(
        [String: Date].self,
        key: appPausedUntilKey,
        defaults: defaults
    )
    let state: [String: Any] = [
        "bundleIdentifier": bundleIdentifier,
        "duration": durations[bundleIdentifier] ?? NSNull(),
        "pausedUntilUnixSeconds": pausedUntil[bundleIdentifier]?.timeIntervalSince1970 ?? NSNull(),
    ]
    let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func setAppPauseState(_ bundleIdentifier: String, value: String, pausedUntilArgument: String?) throws {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: textWardenBundleIdentifier).isEmpty else {
        throw DriverError.failure("stop TextWarden before changing its pause preferences")
    }

    let rawDuration: String?
    switch value {
    case "unset": rawDuration = nil
    case "active": rawDuration = "Active"
    case "one-hour": rawDuration = "Paused for 1 Hour"
    case "twenty-four-hours": rawDuration = "Paused for 24 Hours"
    case "indefinite": rawDuration = "Paused Until Resumed"
    default: throw DriverError.usage("invalid app pause value: \(value)")
    }

    let isTimed = value == "one-hour" || value == "twenty-four-hours"
    guard isTimed == (pausedUntilArgument != nil) else {
        throw DriverError.usage("timed app pauses require an exact Unix timestamp")
    }
    let pausedUntil: Date?
    if let pausedUntilArgument {
        guard let seconds = Double(pausedUntilArgument), seconds.isFinite else {
            throw DriverError.usage("invalid app pause timestamp: \(pausedUntilArgument)")
        }
        pausedUntil = Date(timeIntervalSince1970: seconds)
    } else {
        pausedUntil = nil
    }

    let defaults = try textWardenPreferences()
    var durations = try decodedPreference(
        [String: String].self,
        key: appPauseDurationsKey,
        defaults: defaults
    )
    var pausedUntilDates = try decodedPreference(
        [String: Date].self,
        key: appPausedUntilKey,
        defaults: defaults
    )
    durations[bundleIdentifier] = rawDuration
    pausedUntilDates[bundleIdentifier] = pausedUntil
    try persistPreference(durations, key: appPauseDurationsKey, defaults: defaults)
    try persistPreference(pausedUntilDates, key: appPausedUntilKey, defaults: defaults)
}

func usage() -> Never {
    fputs("""
    Usage:
      macos-e2e-driver.swift activate BUNDLE_ID
      macos-e2e-driver.swift move X Y
      macos-e2e-driver.swift click-editor BUNDLE_ID X Y
      macos-e2e-driver.swift click-app BUNDLE_ID X Y
      macos-e2e-driver.swift editors BUNDLE_ID
      macos-e2e-driver.swift check-editor BUNDLE_ID EXPECTED_TEXT
      macos-e2e-driver.swift check-editor-trimmed BUNDLE_ID EXPECTED_TEXT
      macos-e2e-driver.swift focused-element-state BUNDLE_ID
      macos-e2e-driver.swift app-pause-state BUNDLE_ID
      macos-e2e-driver.swift app-pause-set BUNDLE_ID unset|active|indefinite
      macos-e2e-driver.swift app-pause-set BUNDLE_ID one-hour|twenty-four-hours UNIX_SECONDS
      macos-e2e-driver.swift focus-editor BUNDLE_ID INDEX
      macos-e2e-driver.swift press-app BUNDLE_ID LABEL [OCCURRENCE]
      macos-e2e-driver.swift press-self-chat BUNDLE_ID
      macos-e2e-driver.swift press-menu BUNDLE_ID LABEL
      macos-e2e-driver.swift tab-app BUNDLE_ID
      macos-e2e-driver.swift escape-app BUNDLE_ID
      macos-e2e-driver.swift shortcut-app BUNDLE_ID command-0|command-n
      macos-e2e-driver.swift type-app BUNDLE_ID TEXT
      macos-e2e-driver.swift paste-app BUNDLE_ID TEXT
      macos-e2e-driver.swift backspace-app BUNDLE_ID
      macos-e2e-driver.swift clear-editor BUNDLE_ID EXPECTED_UTF16_LENGTH
      macos-e2e-driver.swift click-textwarden X Y
      macos-e2e-driver.swift press-textwarden LABEL
      macos-e2e-driver.swift scroll DELTA_Y [DELTA_X]
      macos-e2e-driver.swift point-state X Y
      macos-e2e-driver.swift windows BUNDLE_ID
      macos-e2e-driver.swift window-state BUNDLE_ID
      macos-e2e-driver.swift window-set BUNDLE_ID X Y WIDTH HEIGHT
      macos-e2e-driver.swift window-minimize BUNDLE_ID
      macos-e2e-driver.swift window-restore BUNDLE_ID
      macos-e2e-driver.swift self-test
    """ + "\n", stderr)
    exit(2)
}

func run(_ arguments: [String]) throws {
    guard let command = arguments.first else { usage() }

    switch command {
    case "activate":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        print("frontmost pid=\(application.processIdentifier) bundle=\(arguments[1])")

    case "move":
        guard arguments.count == 3 else { usage() }
        try postMouse(.mouseMoved, at: CGPoint(
            x: try number(arguments[1], name: "x"),
            y: try number(arguments[2], name: "y")
        ))

    case "click-editor":
        guard arguments.count == 4 else { usage() }
        _ = try activate(arguments[1])
        let point = CGPoint(
            x: try number(arguments[2], name: "x"),
            y: try number(arguments[3], name: "y")
        )
        guard editorAt(point) != nil else {
            throw DriverError.failure("refusing click outside an editable text element")
        }
        try postMouse(.mouseMoved, at: point)
        usleep(80_000)
        try postMouse(.leftMouseDown, at: point)
        usleep(100_000)
        try postMouse(.leftMouseUp, at: point)

    case "click-app":
        guard arguments.count == 4 else { usage() }
        let application = try activate(arguments[1])
        let point = CGPoint(
            x: try number(arguments[2], name: "x"),
            y: try number(arguments[3], name: "y")
        )
        guard processIDAt(point) == application.processIdentifier,
              let element = elementAt(point)
        else {
            throw DriverError.failure("refusing click outside the target application")
        }
        guard !isRiskyControl(element) else {
            throw DriverError.failure("refusing click on a send-like control")
        }
        try postMouse(.mouseMoved, at: point)
        usleep(80_000)
        try postMouse(.leftMouseDown, at: point)
        usleep(100_000)
        try postMouse(.leftMouseUp, at: point)

    case "editors":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focused = axElement(copyAttribute(appElement, kAXFocusedUIElementAttribute as CFString))
        let states = editors(in: application).enumerated().compactMap { index, editor -> [String: Any]? in
            guard let frame = elementFrame(editor) else { return nil }
            let length: Any = textLength(editor).map { $0 as Any } ?? NSNull()
            return [
                "index": index,
                "identity": String(CFHash(editor), radix: 16),
                "role": stringAttribute(editor, kAXRoleAttribute as CFString) ?? "unknown",
                "focused": focused.map { CFEqual($0, editor) } ?? false,
                "utf16Length": length,
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.width,
                "height": frame.height,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: states, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))

    case "focused-element-state":
        guard arguments.count == 2 else { usage() }
        try printFocusedElementState(try runningApplication(arguments[1]))

    case "app-pause-state":
        guard arguments.count == 2 else { usage() }
        try printAppPauseState(arguments[1])

    case "app-pause-set":
        guard arguments.count == 3 || arguments.count == 4 else { usage() }
        try setAppPauseState(
            arguments[1],
            value: arguments[2],
            pausedUntilArgument: arguments.count == 4 ? arguments[3] : nil
        )

    case "check-editor", "check-editor-trimmed":
        guard arguments.count == 3, isSafeTextInput(arguments[2]) else { usage() }
        let editor = try focusedEditor(try activate(arguments[1]))
        guard let actual = textValue(editor) else {
            throw DriverError.failure("focused editor text is unavailable")
        }
        let comparableActual = command == "check-editor-trimmed"
            ? actual.trimmingCharacters(in: .whitespacesAndNewlines)
            : actual
        guard comparableActual == arguments[2] else {
            throw DriverError.failure("focused editor text did not match expected value")
        }
        print("PASS: focused editor matches expected text (\(arguments[2].utf16.count) UTF-16 units)")

    case "focus-editor":
        guard arguments.count == 3, let index = Int(arguments[2]) else { usage() }
        let application = try activate(arguments[1])
        let candidates = editors(in: application)
        guard candidates.indices.contains(index), let frame = elementFrame(candidates[index]) else {
            throw DriverError.failure("editable element index is unavailable")
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard processIDAt(point) == application.processIdentifier,
              editorAt(point) != nil
        else {
            throw DriverError.failure("editable element center is not exposed by the target application")
        }
        try postMouse(.mouseMoved, at: point)
        usleep(80_000)
        try postMouse(.leftMouseDown, at: point)
        usleep(100_000)
        try postMouse(.leftMouseUp, at: point)

    case "press-app":
        guard arguments.count == 3 || arguments.count == 4 else { usage() }
        var occurrence = arguments.count == 4 ? Int(arguments[3]) ?? -1 : 0
        guard occurrence >= 0 else { usage() }
        let application = try activate(arguments[1])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var remaining = 10_000
        let requestedOccurrence = occurrence
        var element = findPressableElement(
            appElement,
            label: arguments[2],
            occurrence: &occurrence,
            remaining: &remaining
        )
        if element.flatMap(elementFrame) == nil {
            occurrence = requestedOccurrence
            remaining = 10_000
            element = findPressableElement(
                appElement,
                label: arguments[2],
                allowShortcutSuffix: true,
                occurrence: &occurrence,
                remaining: &remaining
            )
        }
        if element.flatMap(elementFrame) == nil {
            occurrence = requestedOccurrence
            remaining = 10_000
            element = findPressableElement(
                appElement,
                label: arguments[2],
                requiresPressAction: false,
                occurrence: &occurrence,
                remaining: &remaining
            )
        }
        guard let element,
              !isRiskyControl(element),
              let frame = elementFrame(element)
        else {
            throw DriverError.failure("could not safely press application action: \(arguments[2])")
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard processIDAt(point) == application.processIdentifier else {
            throw DriverError.failure("application action is not exposed at its accessibility frame")
        }
        try postMouse(.mouseMoved, at: point)
        usleep(80_000)
        try postMouse(.leftMouseDown, at: point)
        usleep(100_000)
        try postMouse(.leftMouseUp, at: point)

    case "press-menu":
        guard arguments.count == 3 else { usage() }
        let application = try activate(arguments[1])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let menuBar = axElement(copyAttribute(appElement, kAXMenuBarAttribute as CFString)) else {
            throw DriverError.failure("application does not expose a menu bar")
        }
        var occurrence = 0
        var remaining = 2_000
        guard let item = findPressableElement(
            menuBar,
            label: arguments[2],
            allowShortcutSuffix: true,
            occurrence: &occurrence,
            remaining: &remaining
        ),
              !isRiskyControl(item),
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        else {
            throw DriverError.failure("could not safely press application menu item: \(arguments[2])")
        }

    case "press-self-chat":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var remaining = 10_000
        var element = findSelfChatElement(
            appElement,
            requiresPressAction: true,
            remaining: &remaining
        )
        if element.flatMap(elementFrame) == nil {
            remaining = 10_000
            element = findSelfChatElement(
                appElement,
                requiresPressAction: false,
                remaining: &remaining
            )
        }
        guard let element,
              !isRiskyControl(element),
              let frame = elementFrame(element)
        else {
            throw DriverError.failure("application exposes no explicit self-chat action")
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard processIDAt(point) == application.processIdentifier else {
            throw DriverError.failure("self-chat action is not exposed at its accessibility frame")
        }
        try postMouse(.mouseMoved, at: point)
        usleep(80_000)
        try postMouse(.leftMouseDown, at: point)
        usleep(100_000)
        try postMouse(.leftMouseUp, at: point)

    case "backspace-app":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        _ = try focusedEditor(application)
        try postKey(51)

    case "tab-app":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        _ = try focusedEditor(application)
        try postKey(48)

    case "escape-app":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        _ = try focusedEditor(application)
        try postKey(53)

    case "shortcut-app":
        guard arguments.count == 3 else { usage() }
        let keyCode: CGKeyCode
        switch arguments[2] {
        case "command-0": keyCode = 29
        case "command-n": keyCode = 45
        default: usage()
        }
        _ = try activate(arguments[1])
        try postKey(keyCode, flags: .maskCommand)

    case "clear-editor":
        guard arguments.count == 3, let expectedLength = Int(arguments[2]), expectedLength >= 0 else { usage() }
        let application = try activate(arguments[1])
        let editor = try focusedEditor(application)
        guard textLength(editor) == expectedLength else {
            throw DriverError.failure("refusing to clear editor with unexpected text length")
        }
        try postKey(0, flags: .maskCommand)
        try postKey(51)

    case "type-app":
        guard arguments.count == 3 else { usage() }
        let application = try activate(arguments[1])
        _ = try focusedEditor(application)
        try postText(arguments[2])

    case "paste-app":
        guard arguments.count == 3 else { usage() }
        let application = try activate(arguments[1])
        _ = try focusedEditor(application)
        try pasteText(arguments[2])

    case "click-textwarden":
        guard arguments.count == 3 else { usage() }
        let point = CGPoint(
            x: try number(arguments[1], name: "x"),
            y: try number(arguments[2], name: "y")
        )
        let textWarden = try runningApplication("io.textwarden.TextWarden")
        guard processIDAt(point) == textWarden.processIdentifier else {
            throw DriverError.failure("refusing click outside a TextWarden window")
        }
        try postMouse(.mouseMoved, at: point)
        usleep(80_000)
        try postMouse(.leftMouseDown, at: point)
        usleep(100_000)
        try postMouse(.leftMouseUp, at: point)

    case "press-textwarden":
        guard arguments.count == 2 else { usage() }
        let textWarden = try runningApplication("io.textwarden.TextWarden")
        let appElement = AXUIElementCreateApplication(textWarden.processIdentifier)
        var occurrence = 0
        var remaining = 10_000
        guard let element = findPressableElement(
            appElement,
            label: arguments[1],
            occurrence: &occurrence,
            remaining: &remaining
        ),
              AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        else {
            throw DriverError.failure("could not press TextWarden action: \(arguments[1])")
        }

    case "scroll":
        guard arguments.count == 2 || arguments.count == 3 else { usage() }
        let deltaY = Int32(try number(arguments[1], name: "deltaY"))
        let deltaX = arguments.count == 3 ? Int32(try number(arguments[2], name: "deltaX")) : 0
        guard let event = CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            throw DriverError.failure("could not create scroll event")
        }
        event.post(tap: .cghidEventTap)

    case "point-state":
        guard arguments.count == 3 else { usage() }
        try printPointState(CGPoint(
            x: try number(arguments[1], name: "x"),
            y: try number(arguments[2], name: "y")
        ))

    case "windows":
        guard arguments.count == 2 else { usage() }
        try printApplicationWindows(arguments[1])

    case "window-state":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        try printWindowState(
            bundleIdentifier: arguments[1],
            application: application,
            window: focusedWindow(application)
        )

    case "window-set":
        guard arguments.count == 6 else { usage() }
        let application = try activate(arguments[1])
        let window = try focusedWindow(application)
        let expectedPosition = CGPoint(
            x: try number(arguments[2], name: "x"),
            y: try number(arguments[3], name: "y")
        )
        let expectedSize = CGSize(
            width: try number(arguments[4], name: "width"),
            height: try number(arguments[5], name: "height")
        )
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            try setSize(window, kAXSizeAttribute as CFString, expectedSize)
            try setPoint(window, kAXPositionAttribute as CFString, expectedPosition)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))

            let position = try pointAttribute(window, kAXPositionAttribute as CFString)
            let size = try sizeAttribute(window, kAXSizeAttribute as CFString)
            if frameMatches(
                position: position,
                size: size,
                expectedPosition: expectedPosition,
                expectedSize: expectedSize
            ) {
                return
            }
        }
        throw DriverError.failure("window did not reach requested frame")

    case "window-minimize", "window-restore":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        let minimized = command == "window-minimize"
        let window = if minimized {
            try focusedWindow(application)
        } else {
            try minimizedWindow(application)
        }
        guard AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            minimized as CFBoolean
        ) == .success else {
            throw DriverError.failure("could not set window minimized state")
        }

    case "self-test":
        let parsed = try number("12.5", name: "x")
        assert(parsed == 12.5)
        assert(isSafeTextInput("draft only"))
        assert(!isSafeTextInput("never\nsend"))
        assert(isSelfChatLabel("Example User (You)"))
        assert(isSelfChatLabel("Saved Messages"))
        assert(!isSelfChatLabel("General"))
        assert(!isEditable(AXUIElementCreateSystemWide()))
        assert(frameMatches(
            position: CGPoint(x: 10, y: 20),
            size: CGSize(width: 300, height: 200),
            expectedPosition: CGPoint(x: 11, y: 19),
            expectedSize: CGSize(width: 301, height: 199)
        ))
        do {
            _ = try number("nan", name: "x")
            assertionFailure("non-finite numbers must fail")
        } catch {}
        print("PASS: macOS E2E driver self-test")

    default:
        usage()
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("ERROR: \(error)\n", stderr)
    exit(1)
}
