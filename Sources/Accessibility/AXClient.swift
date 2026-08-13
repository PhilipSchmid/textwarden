//
//  AXClient.swift
//  TextWarden
//
//  Typed Accessibility API outcomes shared by callers that need to make a safe fallback decision.
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum AXOperationOutcome: Equatable {
    case success
    case unsupported
    case invalidElement
    case unavailable
    case permissionDenied
    case timeout
    case invalidValue

    init(_ error: AXError) {
        switch error {
        case .success:
            self = .success
        case .attributeUnsupported, .actionUnsupported, .parameterizedAttributeUnsupported, .notImplemented:
            self = .unsupported
        case .invalidUIElement, .invalidUIElementObserver:
            self = .invalidElement
        case .apiDisabled:
            self = .permissionDenied
        case .cannotComplete:
            self = .timeout
        case .noValue, .illegalArgument:
            self = .invalidValue
        default:
            self = .unavailable
        }
    }
}

struct AXCallToken: Hashable {
    fileprivate let identifier = UUID()
}

struct AXCallExecution<Value> {
    let value: Value
}

/// Centralizes AX error classification. Callers still own their specific value conversion.
enum AXClient {
    static func outcome(for error: AXError) -> AXOperationOutcome {
        AXOperationOutcome(error)
    }

    /// Executes one synchronous AX transaction only after atomically reserving the target
    /// process. Returning nil means no AX request was made because the process is busy, cooling
    /// down, or the global bound is full.
    static func perform<Value>(
        bundleID: String,
        attribute: String,
        operation: () -> Value
    ) -> AXCallExecution<Value>? {
        guard let token = AXWatchdog.shared.tryBeginCall(
            bundleID: bundleID,
            attribute: attribute,
            allowingReentrancy: true
        ) else {
            return nil
        }
        defer { AXWatchdog.shared.endCall(token) }
        return AXCallExecution(value: operation())
    }

    static func bundleIdentifier(for element: AXUIElement) -> String {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return "unknown"
        }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"
    }
}
