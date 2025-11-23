//
//  GenericContentParser.swift
//  TextWarden
//
//  Generic content parser for apps without specific implementations
//  Uses standard AX API and reasonable defaults
//

import Foundation
import AppKit

/// Generic content parser for apps without specific implementations
/// Falls back to standard AX API with conservative defaults
class GenericContentParser: ContentParser {
    let bundleIdentifier: String
    let parserName = "Generic"

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    func detectUIContext(element: AXUIElement) -> String? {
        // Generic parser doesn't distinguish UI contexts
        return nil
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Conservative default
        return 13.0
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // No correction for unknown apps - use raw NSFont measurement
        return 1.0
    }

    func horizontalPadding(context: String?) -> CGFloat {
        // Conservative default padding
        return 8.0
    }

    /// Generic parser uses default implementation from protocol
    /// which tries AX API first, then falls back to text measurement
}
