//
//  StrategyProfiler.swift
//  TextWarden
//
//  Probes an application's accessibility capabilities to determine
//  optimal positioning strategies and text replacement method.
//
//  All probes are non-invasive (read-only, no cursor/selection changes).
//

import AppKit
import ApplicationServices
import Foundation

/// Probes accessibility capabilities for unknown applications
final class StrategyProfiler {
    static let shared = StrategyProfiler()

    private init() {}

    // MARK: - Public API

    /// Profile an application's accessibility capabilities.
    /// Returns nil if probing cannot be completed (e.g., no text in element).
    func profileApplication(element: AXUIElement, bundleID: String) -> AXCapabilityProfile? {
        // Check if element has text content (required for probing)
        guard hasTextContent(element) else {
            Logger.info("StrategyProfiler: Cannot profile \(bundleID) - no text content in element", category: Logger.accessibility)
            return nil
        }

        Logger.info("StrategyProfiler: Starting profile for \(bundleID)", category: Logger.accessibility)

        // Get app version for cache invalidation
        let appVersion = getAppVersion(for: bundleID)

        // Probe positioning capabilities
        let (boundsForRange, validWidth, validHeight, notWindowFrame) = probeBoundsForRange(element: element)
        let boundsForTextMarkerRange = probeTextMarkerRange(element: element)
        let (lineForIndex, rangeForLine) = probeLineAPIs(element: element)
        let textMarkerForIndex = probeTextMarkerForIndex(element: element)

        // Probe text replacement capability
        let axValueSettable = probeTextReplacementMethod(element: element)

        let profile = AXCapabilityProfile(
            bundleID: bundleID,
            probedAt: Date(),
            appVersion: appVersion,
            boundsForRange: boundsForRange,
            boundsForTextMarkerRange: boundsForTextMarkerRange,
            lineForIndex: lineForIndex,
            rangeForLine: rangeForLine,
            textMarkerForIndex: textMarkerForIndex,
            boundsReturnsValidWidth: validWidth,
            boundsReturnsValidHeight: validHeight,
            boundsNotWindowFrame: notWindowFrame,
            axValueSettable: axValueSettable
        )

        logProfileResults(profile)

        return profile
    }

    // MARK: - Probe Methods

    /// Probe AXBoundsForRange capability
    /// Returns (result, validWidth, validHeight, notWindowFrame)
    private func probeBoundsForRange(element: AXUIElement) -> (ProbeResult, Bool, Bool, Bool) {
        // Get text length to ensure we probe valid range
        guard let textLength = getTextLength(element), textLength > 0 else {
            return (.unknown, false, false, false)
        }

        // Create test range (0, 1) - first character
        var cfRange = CFRange(location: 0, length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return (.unsupported, false, false, false)
        }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success,
              let bv = boundsValue,
              let bounds = safeAXValueGetRect(bv)
        else {
            return (.unsupported, false, false, false)
        }

        // Validate bounds quality
        let validWidth = bounds.width > 0
        let validHeight = bounds.height > 0 && bounds.height < GeometryConstants.maximumLineHeight // Suspiciously large = window frame

        // Check if bounds match element frame (invalid - returns whole element)
        var notWindowFrame = true
        if let elementFrame = AccessibilityBridge.getElementFrame(element) {
            let widthSimilar = abs(bounds.width - elementFrame.width) < 10
            let heightSimilar = abs(bounds.height - elementFrame.height) < 10
            if widthSimilar, heightSimilar {
                notWindowFrame = false
            }
        }

        // Determine result
        if validWidth, validHeight, notWindowFrame {
            return (.supported, validWidth, validHeight, notWindowFrame)
        } else if bounds.width == 0, bounds.height == 0 {
            return (.invalid, validWidth, validHeight, notWindowFrame)
        } else {
            return (.invalid, validWidth, validHeight, notWindowFrame)
        }
    }

    /// Probe AXBoundsForTextMarkerRange capability
    private func probeTextMarkerRange(element: AXUIElement) -> ProbeResult {
        // First try to get a text marker for index 0
        guard let marker = getTextMarkerForIndex(0, in: element) else {
            return .unsupported
        }

        // Try to create a range from marker to marker (single character)
        guard let markerRange = createTextMarkerRange(start: marker, end: marker, in: element) else {
            return .unsupported
        }

        // Try to get bounds for the marker range
        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &boundsValue
        )

        guard result == .success,
              let bv = boundsValue,
              let bounds = safeAXValueGetRect(bv)
        else {
            return .unsupported
        }

        // Validate bounds
        if bounds.width <= 0 || bounds.height <= 0 {
            return .invalid
        }

        // Check if bounds are suspiciously large (window frame)
        if let elementFrame = AccessibilityBridge.getElementFrame(element) {
            let widthSimilar = abs(bounds.width - elementFrame.width) < 10
            let heightSimilar = abs(bounds.height - elementFrame.height) < 10
            if widthSimilar, heightSimilar {
                return .invalid
            }
        }

        return .supported
    }

    /// Probe AXLineForIndex and AXRangeForLine capabilities
    private func probeLineAPIs(element: AXUIElement) -> (ProbeResult, ProbeResult) {
        // Probe AXLineForIndex with index 0
        var indexValue = 0
        guard let indexRef = CFNumberCreate(kCFAllocatorDefault, .intType, &indexValue) else {
            return (.unsupported, .unsupported)
        }

        var lineValue: CFTypeRef?
        let lineResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXLineForIndex" as CFString,
            indexRef,
            &lineValue
        )

        let lineForIndex: ProbeResult = (lineResult == .success && lineValue != nil) ? .supported : .unsupported

        // Probe AXRangeForLine with line 0
        var lineNum = 0
        guard let lineRef = CFNumberCreate(kCFAllocatorDefault, .intType, &lineNum) else {
            return (lineForIndex, .unsupported)
        }

        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXRangeForLine" as CFString,
            lineRef,
            &rangeValue
        )

        let rangeForLine: ProbeResult = (rangeResult == .success && rangeValue != nil) ? .supported : .unsupported

        return (lineForIndex, rangeForLine)
    }

    /// Probe AXTextMarkerForIndex capability
    private func probeTextMarkerForIndex(element: AXUIElement) -> ProbeResult {
        let marker = getTextMarkerForIndex(0, in: element)
        return marker != nil ? .supported : .unsupported
    }

    /// Probe if AXValue is settable (for text replacement)
    private func probeTextReplacementMethod(element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    // MARK: - Helper Methods

    private func hasTextContent(_ element: AXUIElement) -> Bool {
        guard let length = getTextLength(element) else { return false }
        return length > 0
    }

    private func getTextLength(_ element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &value)
        guard result == .success, let num = value as? Int else { return nil }
        return num
    }

    private func getTextMarkerForIndex(_ index: Int, in element: AXUIElement) -> CFTypeRef? {
        var indexValue = index
        guard let indexRef = CFNumberCreate(kCFAllocatorDefault, .intType, &indexValue) else {
            return nil
        }

        var marker: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerForIndex" as CFString,
            indexRef,
            &marker
        )

        return result == .success ? marker : nil
    }

    private func createTextMarkerRange(start: CFTypeRef, end: CFTypeRef, in element: AXUIElement) -> CFTypeRef? {
        // Create a dictionary with start and end markers
        let markerDict: NSDictionary = [
            "AXTextMarkerRangeStart": start,
            "AXTextMarkerRangeEnd": end,
        ]

        var rangeValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
            markerDict,
            &rangeValue
        )

        return result == .success ? rangeValue : nil
    }

    private func getAppVersion(for bundleID: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: appURL)
        else {
            return nil
        }
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // MARK: - Logging

    private func logProfileResults(_ profile: AXCapabilityProfile) {
        Logger.info("StrategyProfiler: Profiled \(profile.bundleID):", category: Logger.accessibility)
        Logger.info("  Positioning:", category: Logger.accessibility)
        Logger.info("    - BoundsForRange: \(profile.boundsForRange.rawValue) (width:\(profile.boundsReturnsValidWidth), height:\(profile.boundsReturnsValidHeight), notFrame:\(profile.boundsNotWindowFrame))", category: Logger.accessibility)
        Logger.info("    - TextMarkerRange: \(profile.boundsForTextMarkerRange.rawValue)", category: Logger.accessibility)
        Logger.info("    - LineForIndex: \(profile.lineForIndex.rawValue), RangeForLine: \(profile.rangeForLine.rawValue)", category: Logger.accessibility)
        Logger.info("    - TextMarkerForIndex: \(profile.textMarkerForIndex.rawValue)", category: Logger.accessibility)
        Logger.info("  Text Replacement:", category: Logger.accessibility)
        Logger.info("    - AXValue settable: \(profile.axValueSettable) -> \(profile.textReplacementMethod)", category: Logger.accessibility)
        Logger.info("  Recommendations:", category: Logger.accessibility)
        Logger.info("    - Strategies: \(profile.recommendedStrategies.map(\.rawValue))", category: Logger.accessibility)
        Logger.info("    - Visual underlines: \(profile.visualUnderlinesEnabled ? "enabled" : "disabled")", category: Logger.accessibility)
    }
}
