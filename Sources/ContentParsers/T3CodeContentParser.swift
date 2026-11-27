import ApplicationServices

final class T3CodeContentParser: ContentParser {
    let bundleIdentifier = "com.t3tools.t3code"
    let parserName = "T3 Code"

    /// TipTap can scroll without a wheel event or an accessibility notification.
    var scrollAnchor: (editor: AXUIElement, run: AXUIElement, range: NSRange, bounds: CGRect)?

    func detectUIContext(element _: AXUIElement) -> String? {
        nil
    }

    func estimatedFontSize(context _: String?) -> CGFloat {
        14
    }

    func spacingMultiplier(context _: String?) -> CGFloat {
        1
    }

    func horizontalPadding(context _: String?) -> CGFloat {
        0
    }

    func shouldMonitorElement(_ element: AXUIElement) -> Bool {
        var classes: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &classes) == .success else { return false }
        return (classes as? [String])?.contains("composer-tiptap") == true
    }

    func preprocessText(_ text: String) -> String? {
        // The empty TipTap paragraph can expose a newline after submission.
        text.allSatisfy(\.isWhitespace) ? "" : text
    }
}
