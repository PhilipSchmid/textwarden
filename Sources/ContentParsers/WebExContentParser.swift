//
//  WebExContentParser.swift
//  TextWarden
//
//  Content parser for Cisco WebEx chat
//  Filters compose area from video/controls and uses AppRegistry for font config
//

import Foundation
import AppKit

/// Content parser for Cisco WebEx
/// Focuses on chat compose area, filtering out video area, participant list, and controls
class WebExContentParser: ContentParser {
    let bundleIdentifier: String = "Cisco-Systems.Spark"
    let parserName: String = "Cisco WebEx"

    /// Configuration from AppRegistry
    private var config: AppConfiguration {
        AppRegistry.shared.configuration(for: bundleIdentifier)
    }

    func detectUIContext(element: AXUIElement) -> String? {
        if WebExContentParser.isComposeElement(element) {
            return "compose"
        }
        return nil
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        return config.fontConfig.defaultSize
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        return config.fontConfig.spacingMultiplier
    }

    func horizontalPadding(context: String?) -> CGFloat {
        return config.horizontalPadding
    }

    func fontFamily(context: String?) -> String? {
        return config.fontConfig.fontFamily
    }

    /// Only monitor compose area elements, not sent messages in conversation
    /// This prevents grammar checking of already-sent messages when clicked
    func shouldMonitorElement(_ element: AXUIElement) -> Bool {
        return WebExContentParser.isComposeElement(element)
    }

    /// Check if element is WebEx chat compose area (not sent messages)
    /// The compose area has AXIdentifier "ConversationInputTextView"
    /// Sent messages are in the MessagesView table and have generic _NS:xxx identifiers
    static func isComposeElement(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Must be a text editing element
        guard role == kAXTextAreaRole as String || role == kAXTextFieldRole as String else {
            return false
        }

        // Check AXIdentifier - compose area has "ConversationInputTextView"
        var identifierRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef) == .success,
           let identifier = identifierRef as? String {
            if identifier == "ConversationInputTextView" {
                Logger.debug("WebExContentParser: Accepting compose area (ConversationInputTextView)", category: Logger.accessibility)
                return true
            }
        }

        // Check parent hierarchy for "Spark Text View" (compose area container)
        var parentRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
           let parent = parentRef,
           CFGetTypeID(parent) == AXUIElementGetTypeID() {
            let parentElement = parent as! AXUIElement
            var parentIdRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(parentElement, kAXIdentifierAttribute as CFString, &parentIdRef) == .success,
               let parentId = parentIdRef as? String {
                if parentId == "Spark Text View" {
                    Logger.debug("WebExContentParser: Accepting element with Spark Text View parent", category: Logger.accessibility)
                    return true
                }
            }
        }

        Logger.debug("WebExContentParser: Rejecting - not a compose element", category: Logger.accessibility)
        return false
    }
}
