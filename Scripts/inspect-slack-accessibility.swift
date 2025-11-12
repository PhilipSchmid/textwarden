#!/usr/bin/env swift

import Foundation
import ApplicationServices

// Get Slack process ID
let task = Process()
task.launchPath = "/usr/bin/pgrep"
task.arguments = ["-x", "Slack"]

let pipe = Pipe()
task.standardOutput = pipe
task.launch()
task.waitUntilExit()

let data = pipe.fileHandleForReading.readDataToEndOfFile()
guard let output = String(data: data, encoding: .utf8),
      let pidString = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first,
      let pid = pid_t(pidString) else {
    print("❌ Slack is not running")
    exit(1)
}

print("✅ Found Slack with PID: \(pid)")

// Create AXUIElement for Slack
let appElement = AXUIElementCreateApplication(pid)

// Get focused element
var focusedElement: CFTypeRef?
let error = AXUIElementCopyAttributeValue(
    appElement,
    kAXFocusedUIElementAttribute as CFString,
    &focusedElement
)

guard error == .success, let element = focusedElement else {
    print("❌ Failed to get focused element: \(error.rawValue)")
    exit(1)
}

let axElement = element as! AXUIElement

print("\n🔍 Focused Element Details:")
print("=" + String(repeating: "=", count: 50))

// Helper function to get attribute value
func getAttribute(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

    if result == .success, let val = value {
        if let strVal = val as? String {
            return strVal
        } else if let numVal = val as? NSNumber {
            return "\(numVal)"
        } else {
            return "\(val)"
        }
    }
    return "<not available>"
}

// Print common attributes
print("Role: \(getAttribute(axElement, kAXRoleAttribute as String))")
print("RoleDescription: \(getAttribute(axElement, kAXRoleDescriptionAttribute as String))")
print("Title: \(getAttribute(axElement, kAXTitleAttribute as String))")
print("Value: \(getAttribute(axElement, kAXValueAttribute as String).prefix(100))...")
print("Description: \(getAttribute(axElement, kAXDescriptionAttribute as String))")
print("Help: \(getAttribute(axElement, kAXHelpAttribute as String))")
print("Enabled: \(getAttribute(axElement, kAXEnabledAttribute as String))")
print("Focused: \(getAttribute(axElement, kAXFocusedAttribute as String))")
print("Subrole: \(getAttribute(axElement, kAXSubroleAttribute as String))")

// Get all attributes
var attributeNames: CFArray?
AXUIElementCopyAttributeNames(axElement, &attributeNames)
if let names = attributeNames as? [String] {
    print("\nAll Available Attributes:")
    for name in names.sorted() {
        print("  - \(name)")
    }
}

print("\n" + String(repeating: "=", count: 50))
