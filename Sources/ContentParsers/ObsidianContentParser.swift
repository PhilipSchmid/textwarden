import ApplicationServices

struct ObsidianContentParser: ContentParser {
    let bundleIdentifier = "md.obsidian"
    let parserName = "Obsidian"

    func detectUIContext(element _: AXUIElement) -> String? {
        nil
    }

    func estimatedFontSize(context _: String?) -> CGFloat {
        16
    }

    func spacingMultiplier(context _: String?) -> CGFloat {
        1
    }

    func horizontalPadding(context _: String?) -> CGFloat {
        0
    }

    func shouldMonitorElement(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        var classes: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &classes) == .success
        else { return false }

        return Self.isNoteEditor(role: role as? String, classes: classes as? [String])
    }

    static func isNoteEditor(role: String?, classes: [String]?) -> Bool {
        role == kAXTextAreaRole as String && classes?.contains("cm-content") == true
    }
}
