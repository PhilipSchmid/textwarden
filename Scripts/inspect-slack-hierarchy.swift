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

// Helper to get attribute
func getAttribute(_ element: AXUIElement, _ attribute: String) -> Any? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return result == .success ? value : nil
}

// Helper to get string attribute
func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    return getAttribute(element, attribute) as? String
}

// Recursively traverse and print element hierarchy
func traverseElement(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 8) {
    guard depth < maxDepth else { return }

    let indent = String(repeating: "  ", count: depth)

    // Get role
    guard let role = getStringAttribute(element, kAXRoleAttribute as String) else {
        return
    }

    // Get other attributes
    let title = getStringAttribute(element, kAXTitleAttribute as String) ?? ""
    let value = getStringAttribute(element, kAXValueAttribute as String) ?? ""
    let description = getStringAttribute(element, kAXDescriptionAttribute as String) ?? ""
    let focused = getAttribute(element, kAXFocusedAttribute as String) as? Bool ?? false
    let enabled = getAttribute(element, kAXEnabledAttribute as String) as? Bool ?? false

    // Print element info
    var info = "\(indent)[\(role)]"
    if !title.isEmpty { info += " title=\"\(title.prefix(30))\"" }
    if !value.isEmpty { info += " value=\"\(value.prefix(30))\"" }
    if !description.isEmpty { info += " desc=\"\(description.prefix(30))\"" }
    if focused { info += " [FOCUSED]" }
    if !enabled { info += " [DISABLED]" }

    // Highlight text input elements
    let editableRoles = ["AXTextField", "AXTextArea", "AXWebArea", "AXGroup", "AXScrollArea"]
    if editableRoles.contains(role) {
        info += " ⭐️"
    }

    print(info)

    // Get children
    if let children = getAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement] {
        // Limit children to avoid too much output
        for (index, child) in children.prefix(20).enumerated() {
            traverseElement(child, depth: depth + 1, maxDepth: maxDepth)
            if index >= 19 && children.count > 20 {
                print("\(indent)  ... and \(children.count - 20) more children")
                break
            }
        }
    }
}

print("\n🌲 Slack Accessibility Hierarchy:")
print(String(repeating: "=", count: 60))
traverseElement(appElement)
print(String(repeating: "=", count: 60))
