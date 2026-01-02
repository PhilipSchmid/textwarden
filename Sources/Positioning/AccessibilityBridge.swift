//
//  AccessibilityBridge.swift
//  TextWarden
//
//  Low-level Accessibility API wrapper
//  Handles the complex C APIs with Swift-friendly interface
//

import AppKit
import ApplicationServices

// MARK: - Safe AXValue Extraction Helpers

/// Safely extract CGRect from a CFTypeRef that should be an AXValue
/// Returns nil if the value is not an AXValue or extraction fails
func safeAXValueGetRect(_ value: CFTypeRef) -> CGRect? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    // Safe: type verified by CFGetTypeID check above
    let axValue = unsafeBitCast(value, to: AXValue.self)
    var rect = CGRect.zero
    guard AXValueGetValue(axValue, .cgRect, &rect) else {
        return nil
    }
    return rect
}

/// Safely extract CGPoint from a CFTypeRef that should be an AXValue
/// Returns nil if the value is not an AXValue or extraction fails
func safeAXValueGetPoint(_ value: CFTypeRef) -> CGPoint? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    // Safe: type verified by CFGetTypeID check above
    let axValue = unsafeBitCast(value, to: AXValue.self)
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

/// Safely extract CGSize from a CFTypeRef that should be an AXValue
/// Returns nil if the value is not an AXValue or extraction fails
func safeAXValueGetSize(_ value: CFTypeRef) -> CGSize? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    // Safe: type verified by CFGetTypeID check above
    let axValue = unsafeBitCast(value, to: AXValue.self)
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
        return nil
    }
    return size
}

/// Safely extract CFRange from a CFTypeRef that should be an AXValue
/// Returns nil if the value is not an AXValue or extraction fails
func safeAXValueGetRange(_ value: CFTypeRef) -> CFRange? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    // Safe: type verified by CFGetTypeID check above
    let axValue = unsafeBitCast(value, to: AXValue.self)
    var range = CFRange(location: 0, length: 0)
    guard AXValueGetValue(axValue, .cfRange, &range) else {
        return nil
    }
    return range
}

// MARK: - Timeout Wrapper

/// Execute a closure with a timeout. Returns true if completed within timeout, false if timed out.
/// The closure runs on a background thread, so the main thread is NOT blocked.
/// WARNING: If the closure times out, it continues running in the background - use for read-only operations only.
func executeWithTimeout(seconds: TimeInterval, closure: @escaping () -> Void) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .userInitiated).async {
        closure()
        semaphore.signal()
    }

    let result = semaphore.wait(timeout: .now() + seconds)
    return result == .success
}

// MARK: - AX Call Watchdog

/// Watchdog that detects and blocklists apps with slow/hanging AX calls.
///
/// This class protects TextWarden from misbehaving accessibility implementations
/// (like Microsoft Office's mso99 framework) that can hang or freeze on certain
/// parameterized AX API calls.
///
/// Features:
/// - **Hang Detection**: Background timer monitors active calls and blocklists apps
///   that take longer than `hangThreshold` (3s) to respond
/// - **Busy Guard**: Prevents pile-up of blocked calls by skipping new requests
///   while a call is in progress (up to `maxBusyTime` of 5s)
/// - **Auto-Recovery**: Blocklisted apps are allowed again after `blocklistDuration` (30s)
///
/// Usage:
/// ```
/// // Check before making AX call
/// guard !AXWatchdog.shared.shouldSkipCalls(for: bundleID) else { return nil }
///
/// // Track the call
/// AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXTextMarkerForIndex")
/// let result = AXUIElementCopyParameterizedAttributeValue(...)
/// AXWatchdog.shared.endCall()
/// ```
final class AXWatchdog {
    static let shared = AXWatchdog()

    // MARK: - Configuration

    /// How long an AX call can take before we consider the app "slow" and blocklist it
    /// Set to 0.8s - triggers blocklisting slightly before the 1.0s native timeout returns,
    /// so subsequent fail-fast checks immediately see the blocklist
    private let hangThreshold: TimeInterval = 0.8

    /// How long to blocklist an app after detecting a hang
    private let blocklistDuration: TimeInterval = 30.0

    /// Check interval for the watchdog timer
    /// Check every 0.1s to quickly detect hangs (must be less than hangThreshold)
    private let checkInterval: TimeInterval = 0.1

    /// Maximum time to consider the worker "busy" before allowing new calls.
    /// If exceeded, we consider the worker stuck and allow new calls (blocklist handles prevention).
    /// Set to 1.2s - slightly longer than the 1.0s timeout to account for overhead.
    private let maxBusyTime: TimeInterval = 1.2

    // MARK: - State

    /// Currently active AX call info
    private struct ActiveCall {
        let bundleID: String
        let startTime: Date
        let attribute: String
    }

    /// Blocklisted apps with expiration time
    private var blocklist: [String: Date] = [:]

    /// Currently active call (if any)
    private var activeCall: ActiveCall?

    /// Lock for thread safety
    private let lock = NSLock()

    /// Watchdog timer
    private var watchdogTimer: DispatchSourceTimer?

    // MARK: - Latency Tracking

    /// Latency samples per app for adaptive mode detection
    private var latencySamples: [String: [TimeInterval]] = [:]

    /// Maximum latency samples to keep per app
    private let maxLatencySamples = 20

    /// Threshold above which we consider an app "slow" and should defer extraction
    private let slowAppLatencyThreshold: TimeInterval = 0.3

    // MARK: - Initialization

    private init() {
        startWatchdog()
    }

    /// Start the background watchdog timer that monitors for hanging calls
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: checkInterval)
        timer.setEventHandler { [weak self] in
            self?.checkForHangingCalls()
        }
        timer.resume()
        watchdogTimer = timer
    }

    // MARK: - Monitoring

    /// Background timer callback - checks if any active call has exceeded the hang threshold
    private func checkForHangingCalls() {
        lock.lock()
        defer { lock.unlock() }

        guard let call = activeCall else { return }

        let elapsed = Date().timeIntervalSince(call.startTime)
        if elapsed > hangThreshold, blocklist[call.bundleID] == nil {
            // This app is hanging - blocklist it
            Logger.warning("AXWatchdog: Detected slow AX call to \(call.bundleID) (\(call.attribute)) - \(String(format: "%.1f", elapsed))s elapsed, blocklisting for \(Int(blocklistDuration))s", category: Logger.accessibility)
            blocklist[call.bundleID] = Date().addingTimeInterval(blocklistDuration)
        }
    }

    // MARK: - Public API

    /// Check if we should skip AX calls for an app.
    /// Returns true if the app is blocklisted or another call is currently in progress.
    func shouldSkipCalls(for bundleID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Check blocklist (with expiration cleanup)
        if let expirationTime = blocklist[bundleID] {
            if Date() < expirationTime {
                return true
            }
            // Blocklist expired - remove it
            blocklist.removeValue(forKey: bundleID)
            Logger.info("AXWatchdog: Blocklist expired for \(bundleID), allowing AX calls again", category: Logger.accessibility)
        }

        // Check if worker is busy (protects against pile-up)
        if let call = activeCall {
            let elapsed = Date().timeIntervalSince(call.startTime)
            if elapsed < maxBusyTime {
                return true
            }
            // Worker stuck too long - allow new calls (blocklist will prevent repeats)
        }

        return false
    }

    /// Mark the start of an AX call. Call `endCall()` when the call completes.
    func beginCall(bundleID: String, attribute: String) {
        lock.lock()
        defer { lock.unlock() }

        activeCall = ActiveCall(bundleID: bundleID, startTime: Date(), attribute: attribute)
    }

    /// Mark the end of an AX call.
    func endCall() {
        lock.lock()
        defer { lock.unlock() }

        // Record latency for dynamic slow-app detection
        if let call = activeCall {
            let duration = Date().timeIntervalSince(call.startTime)
            recordLatency(duration, for: call.bundleID)
        }

        activeCall = nil
    }

    // MARK: - Latency Tracking Methods

    /// Record a completed AX call duration for latency tracking
    private func recordLatency(_ duration: TimeInterval, for bundleID: String) {
        var samples = latencySamples[bundleID] ?? []
        samples.append(duration)
        if samples.count > maxLatencySamples {
            samples.removeFirst()
        }
        latencySamples[bundleID] = samples
    }

    /// Average latency for an app (returns nil if not enough samples)
    func averageLatency(for bundleID: String) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }

        guard let samples = latencySamples[bundleID], samples.count >= 3 else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    /// Check if app should use deferred extraction based on observed latency.
    /// This provides dynamic detection of slow apps even if not explicitly configured.
    func shouldDeferExtraction(for bundleID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Always defer if blocklisted
        if let expirationTime = blocklist[bundleID], Date() < expirationTime {
            return true
        }

        // Defer if average latency exceeds threshold
        if let samples = latencySamples[bundleID], samples.count >= 3 {
            let avgLatency = samples.reduce(0, +) / Double(samples.count)
            if avgLatency > slowAppLatencyThreshold {
                Logger.debug("AXWatchdog: Dynamic defer for \(bundleID) - avg latency \(String(format: "%.3f", avgLatency))s > threshold", category: Logger.accessibility)
                return true
            }
        }

        return false
    }

    /// Explicitly blocklist an app (called when timeout wrappers detect a slow call)
    /// This allows immediate blocklisting without waiting for the background timer.
    func blocklistApp(_ bundleID: String, reason: String) {
        lock.lock()
        defer { lock.unlock() }

        // Don't log if already blocklisted
        guard blocklist[bundleID] == nil else { return }

        Logger.warning("AXWatchdog: Blocklisting \(bundleID) - \(reason)", category: Logger.accessibility)
        blocklist[bundleID] = Date().addingTimeInterval(blocklistDuration)

        // Clear active call if it was for this app
        if activeCall?.bundleID == bundleID {
            activeCall = nil
        }
    }
}

/// Low-level Accessibility API wrapper
/// Isolates all C API complexity and provides clean Swift interface
enum AccessibilityBridge {
    // MARK: - Visibility Detection

    /// Get visible character range using AXVisibleCharacterRange
    /// Returns the range of characters currently visible on screen
    /// CRITICAL: Check visibility BEFORE attempting any positioning
    static func getVisibleCharacterRange(_ element: AXUIElement) -> NSRange? {
        var result: NSRange?

        // 1.5s timeout gives buffer beyond native 1.0s timeout for overhead
        let completed = executeWithTimeout(seconds: 1.5) {
            var value: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(
                element,
                "AXVisibleCharacterRange" as CFString,
                &value
            )

            guard axResult == .success, let axValue = value else {
                Logger.debug("AccessibilityBridge: AXVisibleCharacterRange not available", category: Logger.accessibility)
                return
            }

            guard let range = safeAXValueGetRange(axValue) else {
                Logger.debug("AccessibilityBridge: Could not extract CFRange from AXVisibleCharacterRange", category: Logger.accessibility)
                return
            }

            result = NSRange(location: range.location, length: range.length)
        }

        if !completed {
            Logger.warning("AccessibilityBridge: getVisibleCharacterRange timed out", category: Logger.accessibility)
        }

        return result
    }

    /// Check if a range is within the visible character range
    /// Returns true if range overlaps with visible area, false otherwise
    /// Used to skip positioning for text that's scrolled out of view
    /// NOTE: getVisibleCharacterRange() has timeout protection built-in
    static func isRangeVisible(_ range: NSRange, in element: AXUIElement) -> Bool {
        // getVisibleCharacterRange() already has 0.2s timeout wrapper
        guard let vr = getVisibleCharacterRange(element) else {
            // If timed out or couldn't determine visibility, assume it's visible
            return true
        }

        // Sanity check: if visible range location is absurdly large (> 1 billion chars), it's invalid
        // This happens with Mail's WebKit which returns Int64.max
        if vr.location > 1_000_000_000 || vr.length > 1_000_000_000 {
            Logger.debug("AccessibilityBridge: Visible range is invalid (\(vr)), assuming visible", category: Logger.accessibility)
            return true
        }

        // Sanity check: if visible range has zero length, the app doesn't properly support this API
        // This happens with Mac Catalyst apps like Messages which return {0, 0}
        if vr.length == 0 {
            Logger.debug("AccessibilityBridge: Visible range has zero length (\(vr)), assuming visible", category: Logger.accessibility)
            return true
        }

        // Check if ranges overlap
        let rangeEnd = range.location + range.length
        let visibleEnd = vr.location + vr.length

        let overlaps = range.location < visibleEnd && rangeEnd > vr.location

        if !overlaps {
            Logger.debug("AccessibilityBridge: Range \(range) is outside visible range \(vr)", category: Logger.accessibility)
        }

        return overlaps
    }

    // MARK: - Edit Area Validation

    /// Get the edit area frame (the text field bounds)
    /// Used to validate that calculated bounds are within the edit area
    static func getEditAreaFrame(_ element: AXUIElement) -> CGRect? {
        getElementFrame(element)
    }

    /// Validate that bounds are within the edit area frame
    /// Used to detect invalid positioning results
    static func validateBoundsWithinEditArea(
        _ bounds: CGRect,
        editAreaFrame: CGRect,
        tolerance: CGFloat = 50.0
    ) -> Bool {
        // Expand edit area by tolerance for edge cases
        let expandedEditArea = editAreaFrame.insetBy(dx: -tolerance, dy: -tolerance)

        // Check if bounds origin is within expanded edit area
        let originValid = expandedEditArea.contains(bounds.origin)

        if !originValid {
            Logger.debug("AccessibilityBridge: Bounds origin \(bounds.origin) is outside edit area \(editAreaFrame)", category: Logger.accessibility)
        }

        return originValid
    }

    // MARK: - WebKit Layout-to-Screen Coordinate Conversion

    /// Convert a layout point to screen point for WebKit elements
    /// WebKit internally uses "layout coordinates" which differ from screen coordinates
    /// This is critical for Apple Mail and Safari which use WebKit for text rendering
    static func convertLayoutPointToScreen(
        _ layoutPoint: CGPoint,
        in element: AXUIElement
    ) -> CGPoint? {
        // Create AXValue for the layout point
        var point = layoutPoint
        guard let pointValue = AXValueCreate(.cgPoint, &point) else {
            Logger.warning("AccessibilityBridge: Failed to create CGPoint AXValue for layout-to-screen conversion", category: Logger.accessibility)
            return nil
        }

        var screenPointValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXScreenPointForLayoutPoint" as CFString,
            pointValue,
            &screenPointValue
        )

        guard result == .success, let spv = screenPointValue else {
            Logger.warning("AccessibilityBridge: AXScreenPointForLayoutPoint failed with error \(result.rawValue)", category: Logger.accessibility)
            Logger.warning("AccessibilityBridge: Attempted to convert layout point: \(layoutPoint)", category: Logger.accessibility)

            // Check if element supports this attribute
            let attributes = getSupportedParameterizedAttributes(element)
            if !attributes.contains("AXScreenPointForLayoutPoint") {
                Logger.warning("AccessibilityBridge: Element does NOT support AXScreenPointForLayoutPoint!", category: Logger.accessibility)
                Logger.warning("AccessibilityBridge: Available parameterized attributes: \(attributes)", category: Logger.accessibility)
            }

            return nil
        }

        guard let screenPoint = safeAXValueGetPoint(spv) else {
            Logger.warning("AccessibilityBridge: Failed to extract CGPoint from AXScreenPointForLayoutPoint result", category: Logger.accessibility)
            return nil
        }

        Logger.debug("AccessibilityBridge: Converted layout point \(layoutPoint) → screen point \(screenPoint)", category: Logger.accessibility)
        return screenPoint
    }

    /// Convert a layout size to screen size for WebKit elements
    static func convertLayoutSizeToScreen(
        _ layoutSize: CGSize,
        in element: AXUIElement
    ) -> CGSize? {
        var size = layoutSize
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            return nil
        }

        var screenSizeValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXScreenSizeForLayoutSize" as CFString,
            sizeValue,
            &screenSizeValue
        )

        guard result == .success, let ssv = screenSizeValue else {
            return nil
        }

        return safeAXValueGetSize(ssv)
    }

    /// Convert a layout rect to screen rect for WebKit elements
    /// This is the main function used to convert WebKit bounds to screen coordinates
    static func convertLayoutRectToScreen(
        _ layoutRect: CGRect,
        in element: AXUIElement
    ) -> CGRect? {
        // Convert origin
        guard let screenOrigin = convertLayoutPointToScreen(layoutRect.origin, in: element) else {
            Logger.debug("AccessibilityBridge: Layout-to-screen origin conversion failed", category: Logger.accessibility)
            return nil
        }

        // Convert size (optional - size usually doesn't change much)
        let screenSize: CGSize = if let convertedSize = convertLayoutSizeToScreen(layoutRect.size, in: element) {
            convertedSize
        } else {
            // Fall back to same size if conversion fails
            layoutRect.size
        }

        let screenRect = CGRect(origin: screenOrigin, size: screenSize)
        Logger.debug("AccessibilityBridge: Converted layout rect \(layoutRect) to screen rect \(screenRect)", category: Logger.accessibility)
        return screenRect
    }

    /// Check if element supports WebKit layout-to-screen coordinate conversion
    /// Returns true for WebKit-based apps like Mail, Safari
    static func supportsLayoutToScreenConversion(_ element: AXUIElement) -> Bool {
        let attributes = getSupportedParameterizedAttributes(element)
        return attributes.contains("AXScreenPointForLayoutPoint")
    }

    // MARK: - Capability Detection

    /// Check if element supports modern opaque marker API
    /// Used to determine if ModernMarkerStrategy can be used
    static func supportsOpaqueMarkers(_ element: AXUIElement) -> Bool {
        // Get bundleID for watchdog tracking
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"

        // Check if we should skip AX calls (blocklisted or worker busy)
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("supportsOpaqueMarkers: Skipping \(bundleID) - watchdog protection active", category: Logger.accessibility)
            return false
        }

        // Try to create a marker for index 0 as capability test
        var indexValue = 0
        guard let indexRef = CFNumberCreate(
            kCFAllocatorDefault,
            .intType,
            &indexValue
        ) else {
            return false
        }

        // Track the AX call with watchdog
        AXWatchdog.shared.beginCall(bundleID: bundleID, attribute: "AXTextMarkerForIndex")

        var markerValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerForIndex" as CFString,
            indexRef,
            &markerValue
        )

        AXWatchdog.shared.endCall()

        return result == .success && markerValue != nil
    }

    // MARK: - Opaque Marker API (Modern - for Electron/Chrome)

    /// Request opaque marker for character index
    /// Returns marker that can be used with calculateBounds(from:to:)
    static func requestOpaqueMarker(
        at index: Int,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var indexValue: Int = index
        guard let indexRef = CFNumberCreate(
            kCFAllocatorDefault,
            .intType,
            &indexValue
        ) else {
            Logger.debug("Failed to create CFNumber for index \(index)", category: Logger.accessibility)
            return nil
        }

        var markerValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerForIndex" as CFString,
            indexRef,
            &markerValue
        )

        guard result == .success, let marker = markerValue else {
            if result != .success {
                Logger.debug("Failed to create opaque marker at index \(index): AXError \(result.rawValue)", category: Logger.accessibility)
            }
            return nil
        }

        return marker
    }

    /// Calculate bounds between two opaque markers
    /// Returns bounds in Quartz coordinates (top-left origin) - caller must convert
    static func calculateBounds(
        from startMarker: CFTypeRef,
        to endMarker: CFTypeRef,
        in element: AXUIElement
    ) -> CGRect? {
        Logger.debug("AccessibilityBridge.calculateBounds() called", category: Logger.accessibility)

        // Log what parameterized attributes this element supports (ONCE per session)
        enum DebugState {
            static var hasLoggedAttributes = false
        }
        if !DebugState.hasLoggedAttributes {
            logSupportedAttributes(element, bundleID: "current")
            DebugState.hasLoggedAttributes = true
        }

        // Validate markers by converting them back to indices
        if let startIndex = indexForMarker(startMarker, in: element) {
            Logger.debug("  Start marker validates to index: \(startIndex)", category: Logger.accessibility)
        } else {
            Logger.debug("  Could not get index for start marker", category: Logger.accessibility)
        }

        if let endIndex = indexForMarker(endMarker, in: element) {
            Logger.debug("  End marker validates to index: \(endIndex)", category: Logger.accessibility)
        } else {
            Logger.debug("  Could not get index for end marker", category: Logger.accessibility)
        }

        // Try to get text between markers to validate range
        if let text = getTextUsingMarkers(from: startMarker, to: endMarker, in: element) {
            Logger.debug("  Marker range text length: \(text.count)", category: Logger.accessibility)
        } else {
            Logger.debug("  Could not get text for marker range", category: Logger.accessibility)
        }

        // Method 1: Use AXTextMarkerRangeForUnorderedTextMarkers API to create proper range
        Logger.info("  Trying AXTextMarkerRangeForUnorderedTextMarkers to create proper range...", category: Logger.accessibility)

        let markerPair = [startMarker, endMarker] as CFArray
        var rangeValue: CFTypeRef?

        let rangeResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
            markerPair,
            &rangeValue
        )

        Logger.info("  AXTextMarkerRangeForUnorderedTextMarkers result: \(rangeResult.rawValue)", category: Logger.accessibility)

        var markerRange: CFTypeRef
        if rangeResult == .success, let properRange = rangeValue {
            Logger.info("  ✓ Created proper marker range via AXTextMarkerRangeForUnorderedTextMarkers", category: Logger.accessibility)
            markerRange = properRange
        } else {
            // Fallback: Pass markers as simple array (some apps accept this)
            Logger.info("  AXTextMarkerRangeForUnorderedTextMarkers failed (\(rangeResult.rawValue)), using array fallback", category: Logger.accessibility)
            markerRange = markerPair
        }

        var boundsValue: CFTypeRef?
        Logger.debug("  Calling AXUIElementCopyParameterizedAttributeValue with AXBoundsForTextMarkerRange...", category: Logger.accessibility)

        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &boundsValue
        )

        Logger.debug("  AXBoundsForTextMarkerRange result: \(result.rawValue) (success=\(result == .success))", category: Logger.accessibility)

        guard result == .success else {
            Logger.debug("  FAILED at AXUIElementCopyParameterizedAttributeValue - AXError code: \(result.rawValue)", category: Logger.accessibility)

            // Log what the error code means
            let errorDesc = switch result {
            case .apiDisabled: "API disabled (user needs to enable accessibility)"
            case .notImplemented: "Not implemented (attribute not supported)"
            case .attributeUnsupported: "Attribute unsupported"
            case .invalidUIElement: "Invalid UI element"
            case .illegalArgument: "Illegal argument (marker range format wrong?)"
            case .failure: "Generic failure"
            default: "Unknown error"
            }
            Logger.debug("  Error description: \(errorDesc)", category: Logger.accessibility)

            return nil
        }

        Logger.debug("  AXBoundsForTextMarkerRange succeeded", category: Logger.accessibility)

        // Debug: Check if boundsValue is nil
        let isNil = boundsValue == nil
        Logger.debug("  boundsValue isNil=\(isNil)", category: Logger.accessibility)

        guard let bv = boundsValue else {
            Logger.debug("  FAILED: boundsValue is nil", category: Logger.accessibility)
            return nil
        }

        let typeID = CFGetTypeID(bv)
        let axValueTypeID = AXValueGetTypeID()
        let typeMatch = (typeID == axValueTypeID)
        Logger.debug("  boundsValue typeID=\(typeID), AXValue typeID=\(axValueTypeID), match=\(typeMatch)", category: Logger.accessibility)

        guard typeMatch else {
            Logger.debug("  FAILED: boundsValue is not an AXValue type", category: Logger.accessibility)
            return nil
        }

        Logger.debug("  Type validation passed, extracting CGRect from AXValue...", category: Logger.accessibility)

        guard let rect = safeAXValueGetRect(bv) else {
            Logger.debug("  FAILED at CGRect extraction from AXValue", category: Logger.accessibility)
            return nil
        }

        Logger.debug("  AXValueGetValue result: true, rect: \(rect)", category: Logger.accessibility)

        // Validate bounds before returning
        Logger.debug("  Validating bounds via CoordinateMapper...", category: Logger.accessibility)

        let isValid = CoordinateMapper.validateBounds(rect)
        Logger.debug("  Bounds validation result: \(isValid)", category: Logger.accessibility)

        guard isValid else {
            Logger.debug("  FAILED at bounds validation: \(rect)", category: Logger.accessibility)
            return nil
        }

        Logger.debug("  SUCCESS - Returning valid bounds: \(rect)", category: Logger.accessibility)

        return rect
    }

    // MARK: - Classic Range API (for native apps)

    /// Resolve bounds using traditional CFRange API
    /// Returns bounds in Quartz coordinates (top-left origin) - caller must convert
    static func resolveBoundsUsingRange(
        _ range: CFRange,
        in element: AXUIElement
    ) -> CGRect? {
        // Create range value using var (same as working standalone script)
        var cfRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            Logger.debug("Failed to create AXValue for CFRange", category: Logger.accessibility)
            return nil
        }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success else {
            // Debug: Log element details to compare with working script
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? "unknown"
            Logger.debug("AXBoundsForRange failed: error \(result.rawValue), pid=\(pid), role=\(role), range=(\(range.location),\(range.length))", category: Logger.accessibility)
            return nil
        }

        guard let axValue = boundsValue,
              CFGetTypeID(axValue) == AXValueGetTypeID()
        else {
            Logger.debug("AXBoundsForRange returned non-AXValue type", category: Logger.accessibility)
            return nil
        }

        guard let rect = safeAXValueGetRect(axValue) else {
            Logger.debug("Failed to extract CGRect from AXValue", category: Logger.accessibility)
            return nil
        }

        // Validate bounds before returning
        guard CoordinateMapper.validateBounds(rect) else {
            Logger.debug("Range bounds failed validation: \(rect)", category: Logger.accessibility)
            return nil
        }

        return rect
    }

    // MARK: - Multi-Line Bounds API

    /// Calculate per-line bounds for a text range that may span multiple lines
    /// Returns an array of bounds, one for each line the range spans
    /// Returns nil if line-based APIs are not available
    /// Returns bounds in Quartz coordinates (top-left origin) - caller must convert
    static func resolveMultiLineBounds(
        _ range: NSRange,
        in element: AXUIElement
    ) -> [CGRect]? {
        // First, get the overall bounds to check if this might be multi-line
        let cfRange = CFRange(location: range.location, length: range.length)
        guard let overallBounds = resolveBoundsUsingRange(cfRange, in: element) else {
            Logger.debug("AccessibilityBridge: Could not get overall bounds for range \(range)", category: Logger.accessibility)
            return nil
        }

        // Estimate typical line height by getting bounds for a single character
        var typicalLineHeight: CGFloat = GeometryConstants.defaultLineHeight
        let singleCharRange = CFRange(location: range.location, length: 1)
        if let charBounds = resolveBoundsUsingRange(singleCharRange, in: element) {
            typicalLineHeight = max(charBounds.height, GeometryConstants.minimumLineHeight)
        }

        // Check if bounds suggest multi-line (height > 1.5x typical line height)
        let estimatedLineCount = Int(ceil(overallBounds.height / typicalLineHeight))
        let likelyMultiLine = overallBounds.height > typicalLineHeight * GeometryConstants.suspiciousHeightMultiplier

        Logger.debug("AccessibilityBridge: Range \(range) overall bounds: \(overallBounds), lineHeight: \(typicalLineHeight), estimatedLines: \(estimatedLineCount), likelyMultiLine: \(likelyMultiLine)", category: Logger.accessibility)

        // Try to get line numbers from AX API
        let startLine = tryGetLineForIndex(range.location, in: element)
        let endIndex = range.location + range.length - 1
        let endLine = tryGetLineForIndex(max(0, endIndex), in: element)

        let axReportsMultiLine = startLine != nil && endLine != nil && startLine != endLine

        Logger.debug("AccessibilityBridge: AX reports lines \(startLine ?? -1) to \(endLine ?? -1), axReportsMultiLine: \(axReportsMultiLine)", category: Logger.accessibility)

        // If AX says single-line AND bounds don't suggest multi-line, return single bounds
        if !axReportsMultiLine, !likelyMultiLine {
            Logger.debug("AccessibilityBridge: Treating as single-line (AX and bounds agree)", category: Logger.accessibility)
            return [overallBounds]
        }

        // Try Method 1: Use AXRangeForLine to get each line's character range
        // Only if AX reported valid different line numbers
        var lineBounds: [CGRect] = []

        if axReportsMultiLine, let start = startLine, let end = endLine {
            var rangeForLineWorks = true

            for lineNum in start ... end {
                // Get the character range for this line
                guard let lineRange = tryGetRangeForLine(lineNum, in: element) else {
                    Logger.debug("AccessibilityBridge: AXRangeForLine failed for line \(lineNum)", category: Logger.accessibility)
                    rangeForLineWorks = false
                    break
                }

                // Calculate the intersection of our error range with this line's range
                let lineStart = lineRange.location
                let lineEnd = lineRange.location + lineRange.length
                let errorStart = range.location
                let errorEnd = range.location + range.length

                let intersectStart = max(lineStart, errorStart)
                let intersectEnd = min(lineEnd, errorEnd)

                guard intersectStart < intersectEnd else {
                    Logger.debug("AccessibilityBridge: No intersection for line \(lineNum)", category: Logger.accessibility)
                    continue
                }

                let intersectRange = CFRange(location: intersectStart, length: intersectEnd - intersectStart)

                // Get bounds for this portion of text
                if let bounds = resolveBoundsUsingRange(intersectRange, in: element) {
                    lineBounds.append(bounds)
                    Logger.debug("AccessibilityBridge: Line \(lineNum) bounds: \(bounds)", category: Logger.accessibility)
                }
            }

            if rangeForLineWorks, !lineBounds.isEmpty {
                Logger.debug("AccessibilityBridge: Calculated \(lineBounds.count) line bounds using AXRangeForLine", category: Logger.accessibility)
                return lineBounds
            }
        }

        // Method 2: Sample characters to detect line breaks using Y-coordinate changes
        // For very long ranges, sample every N characters to find approximate line boundaries
        Logger.debug("AccessibilityBridge: Falling back to Y-coordinate sampling for multi-line bounds (estimatedLines: \(estimatedLineCount))", category: Logger.accessibility)
        lineBounds = []

        let rangeLength = range.length

        // Sample rate: check every ~10 characters, but at least sample each expected line
        let sampleStep = max(1, min(10, rangeLength / max(estimatedLineCount * 3, 1)))

        var lineBreakIndices: [Int] = [range.location] // Start of first line
        var lastY: CGFloat?

        var sampleIndex = range.location
        while sampleIndex < range.location + range.length {
            let charRange = CFRange(location: sampleIndex, length: 1)
            if let charBounds = resolveBoundsUsingRange(charRange, in: element) {
                // Detect line change by Y coordinate change (more than half line height = new line)
                if let prevY = lastY {
                    let yDiff = abs(charBounds.origin.y - prevY)
                    if yDiff > charBounds.height * 0.5 {
                        // Line break detected - find exact boundary with binary search
                        let exactBreak = findLineBreak(
                            between: lineBreakIndices.last ?? range.location,
                            and: sampleIndex,
                            in: element,
                            previousY: prevY
                        ) ?? sampleIndex
                        lineBreakIndices.append(exactBreak)
                        Logger.debug("AccessibilityBridge: Detected line break at index \(exactBreak)", category: Logger.accessibility)
                    }
                }
                lastY = charBounds.origin.y
            }
            sampleIndex += sampleStep
        }

        // Add end of range as final boundary
        lineBreakIndices.append(range.location + range.length)

        // Convert line break indices to bounds
        for i in 0 ..< (lineBreakIndices.count - 1) {
            let lineStart = lineBreakIndices[i]
            let lineEnd = lineBreakIndices[i + 1]
            let lineLength = lineEnd - lineStart

            if lineLength > 0 {
                let lineRange = CFRange(location: lineStart, length: lineLength)
                if let bounds = resolveBoundsUsingRange(lineRange, in: element) {
                    lineBounds.append(bounds)
                    Logger.debug("AccessibilityBridge: Line \(i) bounds from sampling: \(bounds)", category: Logger.accessibility)
                }
            }
        }

        // If we found multiple lines via sampling, return them
        if lineBounds.count > 1 {
            Logger.debug("AccessibilityBridge: Calculated \(lineBounds.count) line bounds using Y-coordinate sampling", category: Logger.accessibility)
            return lineBounds
        }

        // Method 3: Geometric fallback - split the overall bounds into estimated line segments
        // This is used when AX APIs don't support line-level queries but we know it's multi-line
        Logger.debug("AccessibilityBridge: Using geometric fallback to split bounds into \(estimatedLineCount) lines", category: Logger.accessibility)
        lineBounds = []

        for lineIndex in 0 ..< estimatedLineCount {
            // Calculate the Y position for this line segment
            // Overall bounds are in Quartz (top-left origin), so Y increases downward
            let lineY = overallBounds.origin.y + (CGFloat(lineIndex) * typicalLineHeight)

            // For the width, we need to estimate where each line starts and ends
            // For the first line, start at the left edge of overall bounds
            // For middle lines, assume they span the full width
            // For the last line, it may end before the right edge

            let lineRect: CGRect
            if lineIndex == 0 {
                // First line - starts at overall X, width is full or to end of line
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: overallBounds.width,
                    height: typicalLineHeight
                )
            } else if lineIndex == estimatedLineCount - 1 {
                // Last line - may not span full width
                // Estimate based on proportional text
                let lastLineWidth = min(overallBounds.width, overallBounds.width * GeometryConstants.lastLineWidthRatio)
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: lastLineWidth,
                    height: typicalLineHeight
                )
            } else {
                // Middle lines - span full width
                lineRect = CGRect(
                    x: overallBounds.origin.x,
                    y: lineY,
                    width: overallBounds.width,
                    height: typicalLineHeight
                )
            }

            lineBounds.append(lineRect)
            Logger.debug("AccessibilityBridge: Geometric line \(lineIndex) bounds: \(lineRect)", category: Logger.accessibility)
        }

        if !lineBounds.isEmpty {
            Logger.debug("AccessibilityBridge: Created \(lineBounds.count) line bounds using geometric split", category: Logger.accessibility)
            return lineBounds
        }

        // Ultimate fallback - return the overall bounds as single element
        Logger.debug("AccessibilityBridge: All methods failed, returning overall bounds as single line", category: Logger.accessibility)
        return [overallBounds]
    }

    /// Binary search to find exact line break point between two indices
    private static func findLineBreak(
        between start: Int,
        and end: Int,
        in element: AXUIElement,
        previousY: CGFloat
    ) -> Int? {
        guard end > start + 1 else { return end }

        var low = start
        var high = end

        while high - low > 1 {
            let mid = (low + high) / 2
            let charRange = CFRange(location: mid, length: 1)

            if let charBounds = resolveBoundsUsingRange(charRange, in: element) {
                let yDiff = abs(charBounds.origin.y - previousY)
                if yDiff > charBounds.height * 0.5 {
                    // Line break is before or at mid
                    high = mid
                } else {
                    // Line break is after mid
                    low = mid
                }
            } else {
                // Can't get bounds, move forward
                low = mid
            }
        }

        return high
    }

    // MARK: - Estimation (Fallback)

    /// Estimate position when all AX APIs fail
    /// Very rough estimation - last resort only
    static func estimatePosition(
        at index: Int,
        in element: AXUIElement
    ) -> CGRect? {
        guard let elementFrame = getElementFrame(element) else {
            return nil
        }

        // Rough estimation based on character index
        let averageCharWidth: CGFloat = 9.0
        let estimatedX = elementFrame.origin.x + (CGFloat(index) * averageCharWidth)
        let estimatedY = elementFrame.origin.y + (elementFrame.height * 0.25)

        return CGRect(
            x: estimatedX,
            y: estimatedY,
            width: averageCharWidth * 5, // Assume ~5 characters
            height: elementFrame.height * 0.5
        )
    }

    // MARK: - Helper Methods

    /// Get element frame in Quartz coordinates
    /// Returns the frame (position + size) of an AXUIElement, or nil if unavailable
    /// NOTE: Uses timeout to prevent freezing on slow AX implementations
    static func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var result: CGRect?

        // 1.5s timeout gives buffer beyond native 1.0s timeout for overhead
        let completed = executeWithTimeout(seconds: 1.5) {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?

            let positionResult = AXUIElementCopyAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                &positionValue
            )

            let sizeResult = AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeValue
            )

            guard positionResult == .success,
                  sizeResult == .success,
                  let position = positionValue,
                  let size = sizeValue
            else {
                return
            }

            guard let origin = safeAXValueGetPoint(position),
                  let rectSize = safeAXValueGetSize(size)
            else {
                return
            }

            result = CGRect(origin: origin, size: rectSize)
        }

        if !completed {
            Logger.warning("AccessibilityBridge: getElementFrame timed out", category: Logger.accessibility)
        }

        return result
    }

    /// Get element position in Quartz coordinates
    /// Returns the position (origin) of an AXUIElement, or nil if unavailable
    /// NOTE: Uses timeout to prevent freezing on slow AX implementations
    static func getElementPosition(_ element: AXUIElement) -> CGPoint? {
        var result: CGPoint?

        // 1.5s timeout gives buffer beyond native 1.0s timeout for overhead
        let completed = executeWithTimeout(seconds: 1.5) {
            var positionValue: CFTypeRef?

            let positionResult = AXUIElementCopyAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                &positionValue
            )

            guard positionResult == .success,
                  let position = positionValue,
                  let point = safeAXValueGetPoint(position)
            else {
                return
            }

            result = point
        }

        if !completed {
            Logger.warning("AccessibilityBridge: getElementPosition timed out", category: Logger.accessibility)
        }

        return result
    }

    /// Find the window element containing the given element
    /// Walks up the AX hierarchy looking for kAXWindowAttribute or AXWindow role
    /// - Parameter element: The element to find the window for
    /// - Returns: The window AXUIElement, or nil if not found
    static func findWindowElement(_ element: AXUIElement) -> AXUIElement? {
        // First try direct window attribute
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success,
           let wv = windowValue,
           CFGetTypeID(wv) == AXUIElementGetTypeID()
        {
            // Safe: type verified by CFGetTypeID check above
            return unsafeBitCast(wv, to: AXUIElement.self)
        }

        // Walk up the parent hierarchy
        var currentElement: AXUIElement? = element
        for _ in 0 ..< 10 {
            guard let current = currentElement else { break }

            // Check if current element has window attribute
            if AXUIElementCopyAttributeValue(current, kAXWindowAttribute as CFString, &windowValue) == .success,
               let wv = windowValue,
               CFGetTypeID(wv) == AXUIElementGetTypeID()
            {
                // Safe: type verified by CFGetTypeID check above
                return unsafeBitCast(wv, to: AXUIElement.self)
            }

            // Check if current element IS a window (by role)
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String,
               role == "AXWindow" || role == kAXWindowRole as String
            {
                return current
            }

            // Move to parent
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = parentValue,
                  CFGetTypeID(parent) == AXUIElementGetTypeID()
            else {
                break
            }
            // Safe: type verified by CFGetTypeID check above
            currentElement = unsafeBitCast(parent, to: AXUIElement.self)
        }

        return nil
    }

    /// Get the frame of the window containing the given element
    /// Returns frame in Quartz coordinates (top-left origin)
    /// - Parameter element: The element whose window frame to get
    /// - Returns: The window frame in Quartz coordinates, or nil if not found
    static func getWindowFrame(_ element: AXUIElement) -> CGRect? {
        guard let window = findWindowElement(element) else {
            return nil
        }
        return getElementFrame(window)
    }

    /// Get bounds for a text range using AXBoundsForRange API
    /// Returns nil if the API fails or returns invalid bounds (Chromium bugs)
    /// - Parameters:
    ///   - range: The text range to get bounds for
    ///   - element: The AXUIElement containing the text
    ///   - minSize: Minimum width/height to consider valid (default from GeometryConstants)
    ///   - maxHeight: Maximum height to consider valid (default from GeometryConstants)
    /// - Returns: Bounds in Quartz coordinates, or nil if invalid
    static func getBoundsForRange(
        _ range: NSRange,
        in element: AXUIElement,
        minSize: CGFloat = GeometryConstants.minimumBoundsSize,
        maxHeight: CGFloat = GeometryConstants.conservativeMaxLineHeight
    ) -> CGRect? {
        var boundsValue: CFTypeRef?
        var axRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &axRange) else {
            return nil
        }

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
            return nil
        }

        // Validate: reject Chromium bugs (zero/tiny bounds) or element-sized bounds
        guard bounds.width > minSize, bounds.height > minSize, bounds.height < maxHeight else {
            return nil
        }

        return bounds
    }

    /// Get text content using modern marker API
    /// Useful for validation and debugging
    static func getTextUsingMarkers(
        from startMarker: CFTypeRef,
        to endMarker: CFTypeRef,
        in element: AXUIElement
    ) -> String? {
        let markerRange = [startMarker, endMarker] as CFArray

        var textValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRange,
            &textValue
        )

        guard result == .success, let text = textValue as? String else {
            return nil
        }

        return text
    }

    /// Convert marker back to character index
    /// Useful for validation
    static func indexForMarker(_ marker: CFTypeRef, in element: AXUIElement) -> Int? {
        var indexValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXIndexForTextMarker" as CFString,
            marker,
            &indexValue
        )

        guard result == .success,
              let number = indexValue as? NSNumber
        else {
            return nil
        }

        return number.intValue
    }

    /// Get all supported parameterized attributes for an element
    /// Diagnostic function to discover what APIs are available
    static func getSupportedParameterizedAttributes(_ element: AXUIElement) -> [String] {
        var attributesValue: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(
            element,
            &attributesValue
        )

        guard result == .success,
              let cfArray = attributesValue,
              let attributes = cfArray as? [String]
        else {
            return []
        }

        return attributes
    }

    /// Log all supported parameterized attributes for debugging
    static func logSupportedAttributes(_ element: AXUIElement, bundleID: String) {
        let attributes = getSupportedParameterizedAttributes(element)
        Logger.debug("Supported parameterized attributes for \(bundleID):", category: Logger.accessibility)

        for attr in attributes {
            Logger.debug("  \(attr)", category: Logger.accessibility)
        }

        if attributes.isEmpty {
            Logger.debug("  No parameterized attributes found", category: Logger.accessibility)
        }
    }

    // MARK: - Comprehensive Notion Diagnostic

    /// Comprehensive diagnostic to find ANY working positioning method for Notion
    /// This function tries EVERY possible AX API method and logs results
    static func runNotionDiagnostic(_ element: AXUIElement) -> NotionDiagnosticResult {
        var result = NotionDiagnosticResult()

        Logger.info("=== NOTION AX DIAGNOSTIC START ===", category: Logger.accessibility)

        // 1. Get basic element info
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        result.role = roleValue as? String ?? "unknown"
        Logger.info("Element role: \(result.role)", category: Logger.accessibility)

        // 2. Get element frame
        if let frame = getElementFrame(element) {
            result.elementFrame = frame
            Logger.info("Element frame: \(frame)", category: Logger.accessibility)
        }

        // 3. Get text content
        var textValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        if let text = textValue as? String {
            result.textLength = text.count
            result.textPreview = String(text.prefix(100))
            Logger.info("Text length: \(text.count) chars", category: Logger.accessibility)
        }

        // 4. List all supported attributes
        var attrNames: CFArray?
        if AXUIElementCopyAttributeNames(element, &attrNames) == .success,
           let names = attrNames as? [String]
        {
            result.supportedAttributes = names
            Logger.info("Supported attributes (\(names.count)): \(names.joined(separator: ", "))")
        }

        // 5. List all supported parameterized attributes
        result.supportedParamAttributes = getSupportedParameterizedAttributes(element)
        Logger.info("Supported parameterized attributes: \(result.supportedParamAttributes.joined(separator: ", "))")

        // 6. Try AXBoundsForRange with different ranges
        Logger.info("--- Testing AXBoundsForRange ---", category: Logger.accessibility)
        let testRanges: [(String, CFRange)] = [
            ("char0", CFRange(location: 0, length: 1)),
            ("char0-5", CFRange(location: 0, length: 5)),
            ("char10-15", CFRange(location: 10, length: 5)),
            ("char50-55", CFRange(location: 50, length: 5)),
        ]

        for (name, range) in testRanges {
            if let bounds = tryGetBoundsForRange(range, in: element) {
                Logger.info("  \(name): \(bounds) ✓", category: Logger.accessibility)
                result.workingRangeBounds[name] = bounds
            } else {
                Logger.info("  \(name): FAILED ✗", category: Logger.accessibility)
            }
        }

        // 7. Try AXLineForIndex - get which line a character is on
        Logger.info("--- Testing AXLineForIndex ---", category: Logger.accessibility)
        for index in [0, 10, 50, 100] {
            if let lineNum = tryGetLineForIndex(index, in: element) {
                Logger.info("  Index \(index) -> Line \(lineNum) ✓", category: Logger.accessibility)
                result.lineForIndex[index] = lineNum
            } else {
                Logger.info("  Index \(index): FAILED ✗", category: Logger.accessibility)
            }
        }

        // 8. Try AXRangeForLine - get character range for a line
        Logger.info("--- Testing AXRangeForLine ---", category: Logger.accessibility)
        for line in [0, 1, 2, 3] {
            if let range = tryGetRangeForLine(line, in: element) {
                Logger.info("  Line \(line) -> Range(\(range.location), \(range.length)) ✓", category: Logger.accessibility)
                result.rangeForLine[line] = range

                // Also try to get bounds for this line
                let cfRange = CFRange(location: range.location, length: range.length)
                if let bounds = tryGetBoundsForRange(cfRange, in: element) {
                    Logger.info("    Line \(line) bounds: \(bounds) ✓", category: Logger.accessibility)
                    result.lineBounds[line] = bounds
                }
            } else {
                Logger.info("  Line \(line): FAILED ✗", category: Logger.accessibility)
            }
        }

        // 9. Try AXInsertionPointLineNumber
        Logger.info("--- Testing Insertion Point ---", category: Logger.accessibility)
        var insertionLineValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointLineNumber" as CFString, &insertionLineValue) == .success,
           let lineNum = insertionLineValue as? Int
        {
            result.insertionPointLine = lineNum
            Logger.info("  AXInsertionPointLineNumber: \(lineNum) ✓", category: Logger.accessibility)
        } else {
            Logger.info("  AXInsertionPointLineNumber: FAILED ✗", category: Logger.accessibility)
        }

        // 10. Try AXSelectedTextRange (cursor position)
        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
           let selectedRangeValue,
           let selectedRange = safeAXValueGetRange(selectedRangeValue)
        {
            result.cursorPosition = selectedRange.location
            Logger.info("  Cursor position: \(selectedRange.location) ✓", category: Logger.accessibility)

            // Try to get bounds AT cursor position
            let cursorRange = CFRange(location: selectedRange.location, length: 1)
            if let cursorBounds = tryGetBoundsForRange(cursorRange, in: element) {
                result.cursorBounds = cursorBounds
                Logger.info("  Cursor bounds: \(cursorBounds) ✓", category: Logger.accessibility)
            }
        }

        // 11. Try AXNumberOfCharacters
        var numCharsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &numCharsValue) == .success,
           let numChars = numCharsValue as? Int
        {
            result.numberOfCharacters = numChars
            Logger.info("  AXNumberOfCharacters: \(numChars) ✓", category: Logger.accessibility)
        }

        // 12. Try to find children with bounds
        Logger.info("--- Testing Children Hierarchy ---", category: Logger.accessibility)
        result.childrenWithBounds = findChildrenWithValidBounds(element, depth: 0, maxDepth: 5)
        Logger.info("  Found \(result.childrenWithBounds.count) children with valid bounds", category: Logger.accessibility)

        // 13. Check AXVisibleCharacterRange
        if let visibleRange = getVisibleCharacterRange(element) {
            result.visibleRange = visibleRange
            Logger.info("  AXVisibleCharacterRange: \(visibleRange) ✓", category: Logger.accessibility)
        }

        Logger.info("=== NOTION AX DIAGNOSTIC END ===", category: Logger.accessibility)

        return result
    }

    /// Try to get bounds for a range, returning nil on failure
    private static func tryGetBoundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
        var cfRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard result == .success, let bv = boundsValue,
              let rect = safeAXValueGetRect(bv)
        else {
            return nil
        }

        // Return even if bounds seem invalid - we want to see what we get
        return rect
    }

    /// Try to get line number for character index
    private static func tryGetLineForIndex(_ index: Int, in element: AXUIElement) -> Int? {
        var indexValue = index
        guard let indexRef = CFNumberCreate(kCFAllocatorDefault, .intType, &indexValue) else {
            return nil
        }

        var lineValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXLineForIndex" as CFString,
            indexRef,
            &lineValue
        )

        guard result == .success, let line = lineValue as? Int else {
            return nil
        }

        return line
    }

    /// Try to get character range for a line number
    private static func tryGetRangeForLine(_ lineNumber: Int, in element: AXUIElement) -> NSRange? {
        var lineValue = lineNumber
        guard let lineRef = CFNumberCreate(kCFAllocatorDefault, .intType, &lineValue) else {
            return nil
        }

        var rangeValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXRangeForLine" as CFString,
            lineRef,
            &rangeValue
        )

        guard result == .success, let rv = rangeValue,
              let range = safeAXValueGetRange(rv)
        else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    /// Recursively find children that have valid bounds
    private static func findChildrenWithValidBounds(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int
    ) -> [ChildBoundsInfo] {
        guard depth < maxDepth else { return [] }

        var results: [ChildBoundsInfo] = []

        // Get children
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else {
            return results
        }

        for (index, child) in children.prefix(20).enumerated() {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? "unknown"

            // Get child's frame
            if let frame = getElementFrame(child), frame.width > 0, frame.height > 0, frame.height < GeometryConstants.maximumLineHeight {
                // Get text if available
                var textValue: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &textValue)
                let text = textValue as? String

                let info = ChildBoundsInfo(
                    depth: depth,
                    index: index,
                    role: role,
                    frame: frame,
                    textPreview: text?.prefix(30).description
                )
                results.append(info)

                Logger.debug("    Child[\(depth)][\(index)] role=\(role) frame=\(frame) hasText=\(text != nil)")
            }

            // Recurse
            results.append(contentsOf: findChildrenWithValidBounds(child, depth: depth + 1, maxDepth: maxDepth))
        }

        return results
    }
}

// MARK: - Diagnostic Result Structures

struct NotionDiagnosticResult {
    var role: String = ""
    var elementFrame: CGRect?
    var textLength: Int = 0
    var textPreview: String = ""
    var supportedAttributes: [String] = []
    var supportedParamAttributes: [String] = []
    var workingRangeBounds: [String: CGRect] = [:]
    var lineForIndex: [Int: Int] = [:]
    var rangeForLine: [Int: NSRange] = [:]
    var lineBounds: [Int: CGRect] = [:]
    var insertionPointLine: Int?
    var cursorPosition: Int?
    var cursorBounds: CGRect?
    var numberOfCharacters: Int?
    var visibleRange: NSRange?
    var childrenWithBounds: [ChildBoundsInfo] = []

    /// Check if we have any working positioning method
    var hasWorkingMethod: Bool {
        !workingRangeBounds.isEmpty ||
            !lineBounds.isEmpty ||
            cursorBounds != nil ||
            !childrenWithBounds.isEmpty
    }

    /// Get the best available method description
    var bestMethodDescription: String {
        if !lineBounds.isEmpty {
            return "Line-based bounds (AXRangeForLine + AXBoundsForRange)"
        }
        if cursorBounds != nil {
            return "Cursor-relative positioning"
        }
        if !workingRangeBounds.isEmpty {
            return "Direct range bounds"
        }
        if !childrenWithBounds.isEmpty {
            return "Children element bounds"
        }
        return "No working method found"
    }
}

struct ChildBoundsInfo {
    let depth: Int
    let index: Int
    let role: String
    let frame: CGRect
    let textPreview: String?
}

// MARK: - InsertionPointFrame Strategy

extension AccessibilityBridge {
    /// Get AXInsertionPointFrame for current cursor position
    /// Works in Chromium when AXBoundsForRange fails
    static func getInsertionPointFrame(_ element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXInsertionPointFrame" as CFString,
            &value
        )

        guard result == .success, let axValue = value else {
            Logger.debug("AccessibilityBridge: AXInsertionPointFrame failed with error \(result.rawValue)", category: Logger.accessibility)
            return nil
        }

        guard let rect = safeAXValueGetRect(axValue) else {
            Logger.debug("AccessibilityBridge: Could not extract CGRect from AXInsertionPointFrame", category: Logger.accessibility)
            return nil
        }

        return rect
    }

    /// Get current selection range
    static func getSelectedTextRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success, let axValue = value else {
            return nil
        }

        return safeAXValueGetRange(axValue)
    }

    /// Set selection range - used for cursor-based positioning
    /// Returns true if successful
    static func setSelectedTextRange(_ element: AXUIElement, location: Int, length: Int = 0) -> Bool {
        var range = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            Logger.debug("AccessibilityBridge: Failed to create CFRange value", category: Logger.accessibility)
            return false
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if result != .success {
            Logger.debug("AccessibilityBridge: Failed to set selection range, error \(result.rawValue)", category: Logger.accessibility)
        }

        return result == .success
    }
}
