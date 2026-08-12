//
//  AXClient.swift
//  TextWarden
//
//  Typed Accessibility API outcomes shared by callers that need to make a safe fallback decision.
//

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

/// Centralizes AX error classification. Callers still own their specific value conversion.
enum AXClient {
    static func outcome(for error: AXError) -> AXOperationOutcome {
        AXOperationOutcome(error)
    }
}
