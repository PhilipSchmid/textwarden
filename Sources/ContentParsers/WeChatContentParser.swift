import ApplicationServices

struct WeChatContentParser: ContentParser {
    let bundleIdentifier = "com.tencent.xinWeChat"
    let parserName = "WeChat"
    private static let composerIdentifier = "chat_input_field"

    func detectUIContext(element _: AXUIElement) -> String? {
        nil
    }

    func estimatedFontSize(context _: String?) -> CGFloat {
        AppConfiguration.wechat.fontConfig.defaultSize
    }

    func spacingMultiplier(context _: String?) -> CGFloat {
        AppConfiguration.wechat.fontConfig.spacingMultiplier
    }

    func horizontalPadding(context _: String?) -> CGFloat {
        AppConfiguration.wechat.horizontalPadding
    }

    func shouldMonitorElement(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        var identifier: CFTypeRef?
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier) == .success,
              identifier as? String == Self.composerIdentifier,
              AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focused) == .success
        else { return false }

        return Self.isFocusedComposer(role: role as? String, identifier: identifier as? String, focused: focused as? Bool)
    }

    static func isFocusedComposer(role: String?, identifier: String?, focused: Bool?) -> Bool {
        role == kAXTextAreaRole as String && identifier == composerIdentifier && focused == true
    }

    func extractText(from element: AXUIElement) -> String? {
        // A successful empty AXValue is the cleared draft after send or deletion.
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
