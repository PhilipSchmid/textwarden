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
    guard let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
    ).first else {
        throw DriverError.failure("application is not running: \(bundleIdentifier)")
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

func postKey(_ keyCode: CGKeyCode) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
        throw DriverError.failure("could not create keyboard event")
    }
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

func isRiskyControl(_ element: AXUIElement) -> Bool {
    let riskyLabels = ["send", "submit", "post", "publish", "share"]
    var candidate: AXUIElement? = element
    for _ in 0 ..< 5 {
        guard let current = candidate else { return false }
        let role = stringAttribute(current, kAXRoleAttribute as CFString)
        if role == kAXButtonRole as String || role == kAXMenuItemRole as String {
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

func findPressableElement(_ root: AXUIElement, label: String, remaining: inout Int) -> AXUIElement? {
    guard remaining > 0 else { return nil }
    remaining -= 1

    let role = stringAttribute(root, kAXRoleAttribute as CFString)
    let labels = [
        stringAttribute(root, kAXTitleAttribute as CFString),
        stringAttribute(root, kAXDescriptionAttribute as CFString),
        stringAttribute(root, kAXValueAttribute as CFString),
    ]
    if (role == kAXButtonRole as String || role == "AXLink"),
       labels.compactMap({ $0 }).contains(label)
    {
        return root
    }

    let children = copyAttribute(root, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    for child in children {
        if let match = findPressableElement(child, label: label, remaining: &remaining) {
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

func usage() -> Never {
    fputs("""
    Usage:
      macos-e2e-driver.swift activate BUNDLE_ID
      macos-e2e-driver.swift move X Y
      macos-e2e-driver.swift click-editor BUNDLE_ID X Y
      macos-e2e-driver.swift click-app BUNDLE_ID X Y
      macos-e2e-driver.swift type-app BUNDLE_ID TEXT
      macos-e2e-driver.swift backspace-app BUNDLE_ID
      macos-e2e-driver.swift click-textwarden X Y
      macos-e2e-driver.swift press-textwarden LABEL
      macos-e2e-driver.swift scroll DELTA_Y [DELTA_X]
      macos-e2e-driver.swift point-state X Y
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

    case "backspace-app":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedElement = axElement(copyAttribute(appElement, kAXFocusedUIElementAttribute as CFString)) else {
            throw DriverError.failure("application has no focused element")
        }
        let role = stringAttribute(focusedElement, kAXRoleAttribute as CFString)
        guard boolAttribute(focusedElement, "AXEditable" as CFString)
            || role == kAXTextAreaRole as String
            || role == kAXTextFieldRole as String
        else {
            throw DriverError.failure("refusing backspace outside an editable text element")
        }
        try postKey(51)

    case "type-app":
        guard arguments.count == 3 else { usage() }
        let application = try activate(arguments[1])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedElement = axElement(copyAttribute(appElement, kAXFocusedUIElementAttribute as CFString)) else {
            throw DriverError.failure("application has no focused element")
        }
        let role = stringAttribute(focusedElement, kAXRoleAttribute as CFString)
        guard boolAttribute(focusedElement, "AXEditable" as CFString)
            || role == kAXTextAreaRole as String
            || role == kAXTextFieldRole as String
        else {
            throw DriverError.failure("refusing text input outside an editable text element")
        }
        try postText(arguments[2])

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
        var remaining = 500
        guard let element = findPressableElement(appElement, label: arguments[1], remaining: &remaining),
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
