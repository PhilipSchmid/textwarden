//
//  TextAnchor.swift
//  TextWarden
//
//  Universal text position reference
//  Abstracts over multiple Apple Accessibility position types
//

import Foundation
import ApplicationServices

/// TextAnchor - Universal text position reference
/// Abstracts over Apple's various accessibility position types
/// Provides type-safe wrapper with automatic fallback strategies
enum TextAnchor {
    /// Modern opaque position marker (works in Electron/Chrome)
    /// Uses AXTextMarkerForIndex API
    case opaqueMarker(CFTypeRef)

    /// Traditional range-based position (works in native apps)
    /// Uses CFRange with AXBoundsForRange API
    case characterRange(CFRange)

    /// Fallback: Character index with element reference
    /// Used when both modern and classic APIs fail
    case indexBased(index: Int, element: AXUIElement)

    // MARK: - Factory Methods

    /// Create anchor from character index
    /// Tries modern API first, falls back to classic automatically
    static func anchor(at index: Int, in element: AXUIElement) -> TextAnchor? {
        // Strategy 1: Try modern opaque marker API (best for Electron)
        if let marker = AccessibilityBridge.requestOpaqueMarker(at: index, from: element) {
            return .opaqueMarker(marker)
        }

        // Strategy 2: Use character range (works for native apps)
        let range = CFRange(location: index, length: 0)
        return .characterRange(range)
    }

    /// Create anchor range from start and end indices
    static func anchorRange(from start: Int, to end: Int, in element: AXUIElement) -> (TextAnchor, TextAnchor)? {
        guard let startAnchor = anchor(at: start, in: element),
              let endAnchor = anchor(at: end, in: element) else {
            return nil
        }

        return (startAnchor, endAnchor)
    }

    // MARK: - Position Resolution

    /// Get screen position for this anchor
    /// Returns bounds in Cocoa coordinate system (bottom-left origin)
    func resolvePosition(in element: AXUIElement, length: Int = 1) -> CGRect? {
        switch self {
        case .opaqueMarker(let marker):
            // Need both start and end markers for bounds
            // This is handled by AccessibilityBridge.calculateBounds
            return nil  // Use anchorRange instead

        case .characterRange(let range):
            return AccessibilityBridge.resolveBoundsUsingRange(range, in: element)

        case .indexBased(let index, let element):
            // Last resort estimation
            return AccessibilityBridge.estimatePosition(at: index, in: element)
        }
    }
}

// MARK: - Helper Extensions

extension TextAnchor {
    /// Check if this anchor uses modern opaque marker API
    var usesModernAPI: Bool {
        if case .opaqueMarker = self {
            return true
        }
        return false
    }

    /// Get debug description
    var debugDescription: String {
        switch self {
        case .opaqueMarker:
            return "opaque-marker"
        case .characterRange(let range):
            return "range(\(range.location), \(range.length))"
        case .indexBased(let index, _):
            return "index(\(index))"
        }
    }
}
