//
//  RuntimeHealth.swift
//  TextWarden
//
//  A privacy-safe, user-facing summary of TextWarden's current ability to check text.
//

import Combine
import Foundation

enum CheckingState: String, Codable, Equatable {
    case active
    case limited
    case recovering
    case inactive

    var displayName: String {
        switch self {
        case .active: "Active"
        case .limited: "Limited support"
        case .recovering: "Recovering"
        case .inactive: "Paused"
        }
    }
}

enum InactiveReason: String, Codable, Equatable {
    case permission
    case globalPause
    case appPause
    case siteDisabled
    case consentRequired
    case secureField
    case unsupportedField
    case unsupportedApplication
    case noEditableField

    var displayMessage: String {
        switch self {
        case .permission: "Accessibility permission is needed to check writing in other apps."
        case .globalPause: "TextWarden is paused."
        case .appPause: "TextWarden is paused for this app."
        case .siteDisabled: "TextWarden is disabled for this website."
        case .consentRequired: "Choose how TextWarden works here."
        case .secureField: "TextWarden never reads password or protected fields."
        case .unsupportedField: "This field does not provide the information TextWarden needs."
        case .unsupportedApplication: "TextWarden is not used in this app."
        case .noEditableField: "Move the cursor to an editable text field to start checking."
        }
    }

    /// Short status used in the fixed-width menu-bar menu.
    var menuMessage: String {
        switch self {
        case .permission: "Permission needed"
        case .globalPause: "Paused"
        case .appPause: "Paused in this app"
        case .siteDisabled: "Disabled on this website"
        case .consentRequired: "Choose how TextWarden works here"
        case .secureField: "Protected field"
        case .unsupportedField: "Unsupported text field"
        case .unsupportedApplication: "Not used in this app"
        case .noEditableField: "No editable text field"
        }
    }
}

struct CapabilitySet: OptionSet, Codable, Equatable {
    let rawValue: Int

    static let textReading = CapabilitySet(rawValue: 1 << 0)
    static let grammar = CapabilitySet(rawValue: 1 << 1)
    static let style = CapabilitySet(rawValue: 1 << 2)
    static let inlinePositioning = CapabilitySet(rawValue: 1 << 3)
    static let safeReplacement = CapabilitySet(rawValue: 1 << 4)

    static let full: CapabilitySet = [.textReading, .grammar, .style, .inlinePositioning, .safeReplacement]
    static let indicatorOnly: CapabilitySet = [.textReading, .grammar]

    var supportLabel: String {
        if contains(.inlinePositioning), contains(.safeReplacement) {
            return "Full support"
        }
        if contains(.textReading), contains(.grammar) {
            return contains(.inlinePositioning) ? "Limited support" : "Indicator only"
        }
        return "Unavailable"
    }
}

enum RecoveryAction: String, Codable, Equatable {
    case grantPermission
    case resume
    case enable
    case retry
    case resetIndicatorPosition
    case openSettings
    case copyDiagnostics
    case reportCompatibility
    case trySafely
    case keepPaused
}

enum RuntimeFieldCondition: Equatable {
    case editable
    case secure
    case unsupported
}

/// Text-free inputs used to choose one user-visible runtime state. Production monitoring and
/// deterministic AX fixtures both use this policy so their safety priority cannot drift apart.
struct RuntimeHealthConditions: Equatable {
    var applicationSupported = true
    var permissionGranted = true
    var globalPaused = false
    var applicationPaused = false
    var applicationDisabled = false
    var siteDisabled = false
    var consentGranted = true
    var fieldCondition: RuntimeFieldCondition = .editable
    var axOutcome: AXOperationOutcome = .success
    var geometryReliable = true
    var replacementVerifiable = true
    var availableCapabilities: CapabilitySet = .full
    var availableAction: RecoveryAction?
}

struct RuntimeHealthDecision: Equatable {
    let state: CheckingState
    let reason: InactiveReason?
    let capabilities: CapabilitySet
    let action: RecoveryAction?

    var allowsMonitoring: Bool {
        state == .active || state == .limited
    }
}

enum RuntimeHealthPolicy {
    static func evaluate(_ conditions: RuntimeHealthConditions) -> RuntimeHealthDecision {
        // Intentionally ignored applications never enter the external AX pipeline.
        guard conditions.applicationSupported else {
            return inactive(reason: .unsupportedApplication)
        }

        // User-facing priority: permission, pause, consent, protected/unsupported field,
        // recovery, then the available capability level.
        if !conditions.permissionGranted || conditions.axOutcome == .permissionDenied {
            return inactive(reason: .permission, action: .grantPermission)
        }
        if conditions.globalPaused {
            return inactive(reason: .globalPause, action: .resume)
        }
        if conditions.applicationPaused {
            return inactive(reason: .appPause, action: .resume)
        }
        if conditions.applicationDisabled {
            return inactive(reason: .appPause, action: .enable)
        }
        if conditions.siteDisabled {
            return inactive(reason: .siteDisabled, action: .enable)
        }
        if !conditions.consentGranted {
            return inactive(reason: .consentRequired, action: .trySafely)
        }
        if conditions.fieldCondition == .secure {
            return inactive(reason: .secureField)
        }
        if conditions.fieldCondition == .unsupported
            || conditions.axOutcome == .unsupported
            || conditions.axOutcome == .invalidValue
        {
            return inactive(reason: .unsupportedField, action: .retry)
        }
        if conditions.axOutcome == .timeout
            || conditions.axOutcome == .unavailable
            || conditions.axOutcome == .invalidElement
        {
            return RuntimeHealthDecision(
                state: .recovering,
                reason: nil,
                capabilities: [],
                action: .retry
            )
        }

        var capabilities = conditions.availableCapabilities
        if !conditions.geometryReliable {
            capabilities.remove(.inlinePositioning)
        }
        if !conditions.replacementVerifiable {
            capabilities.remove(.safeReplacement)
        }

        return RuntimeHealthDecision(
            state: capabilities == .full ? .active : .limited,
            reason: nil,
            capabilities: capabilities,
            action: conditions.availableAction
        )
    }

    private static func inactive(
        reason: InactiveReason,
        action: RecoveryAction? = nil
    ) -> RuntimeHealthDecision {
        RuntimeHealthDecision(
            state: .inactive,
            reason: reason,
            capabilities: [],
            action: action
        )
    }
}

struct RuntimeHealthSnapshot: Equatable {
    let state: CheckingState
    let reason: InactiveReason?
    let capabilities: CapabilitySet
    let applicationName: String?
    let bundleIdentifier: String?
    let lastSuccessfulCheck: Date?
    let action: RecoveryAction?

    static let idle = RuntimeHealthSnapshot(
        state: .inactive,
        reason: .noEditableField,
        capabilities: [],
        applicationName: nil,
        bundleIdentifier: nil,
        lastSuccessfulCheck: nil,
        action: nil
    )

    var title: String {
        switch state {
        case .active:
            capabilities.supportLabel
        case .limited:
            capabilities.supportLabel
        case .recovering:
            "Recovering"
        case .inactive:
            reason?.displayMessage ?? "TextWarden is paused."
        }
    }

    var menuTitle: String {
        switch state {
        case .active, .limited:
            capabilities.supportLabel
        case .recovering:
            "Recovering"
        case .inactive:
            reason?.menuMessage ?? "Paused"
        }
    }

    /// The preference scope a resume action should change.
    /// The runtime reason determines the scope; unrelated pause settings stay untouched.
    var resumeScope: PauseScope? {
        switch reason {
        case .globalPause:
            return .global
        case .appPause:
            guard let bundleIdentifier else { return nil }
            return .application(bundleIdentifier)
        case .permission, .siteDisabled, .consentRequired, .secureField,
             .unsupportedField, .unsupportedApplication, .noEditableField, nil:
            return nil
        }
    }
}

/// Holds operational state only. It deliberately never stores captured text or suggestion content.
@MainActor
final class RuntimeHealthStore: ObservableObject {
    static let shared = RuntimeHealthStore()

    @Published private(set) var snapshot: RuntimeHealthSnapshot = .idle

    private init() {}

    func update(
        state: CheckingState,
        reason: InactiveReason? = nil,
        capabilities: CapabilitySet = [],
        context: ApplicationContext? = nil,
        action: RecoveryAction? = nil,
        successfulAt: Date? = nil
    ) {
        snapshot = RuntimeHealthSnapshot(
            state: state,
            reason: reason,
            capabilities: capabilities,
            applicationName: context?.applicationName,
            bundleIdentifier: context?.bundleIdentifier,
            lastSuccessfulCheck: successfulAt ?? (
                context?.bundleIdentifier == snapshot.bundleIdentifier ? snapshot.lastSuccessfulCheck : nil
            ),
            action: action
        )
    }

    func update(_ decision: RuntimeHealthDecision, context: ApplicationContext?) {
        update(
            state: decision.state,
            reason: decision.reason,
            capabilities: decision.capabilities,
            context: context,
            action: decision.action
        )
    }

    func recordSuccessfulCheck(for context: ApplicationContext, capabilities: CapabilitySet) {
        update(
            state: capabilities == .full ? .active : .limited,
            capabilities: capabilities,
            context: context,
            successfulAt: Date()
        )
    }
}
