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

func usage() -> Never {
    fputs("""
    Usage:
      macos-e2e-driver.swift activate BUNDLE_ID
      macos-e2e-driver.swift move X Y
      macos-e2e-driver.swift click-editor BUNDLE_ID X Y
      macos-e2e-driver.swift scroll DELTA_Y [DELTA_X]
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
        try setPoint(window, kAXPositionAttribute as CFString, CGPoint(
            x: try number(arguments[2], name: "x"),
            y: try number(arguments[3], name: "y")
        ))
        try setSize(window, kAXSizeAttribute as CFString, CGSize(
            width: try number(arguments[4], name: "width"),
            height: try number(arguments[5], name: "height")
        ))

    case "window-minimize", "window-restore":
        guard arguments.count == 2 else { usage() }
        let application = try activate(arguments[1])
        let window = try focusedWindow(application)
        let minimized = command == "window-minimize"
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

