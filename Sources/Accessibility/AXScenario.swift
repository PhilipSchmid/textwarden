//
//  AXScenario.swift
//  TextWarden
//
//  Sanitized Accessibility fixtures for deterministic fallback and recovery testing.
//

import Foundation

/// A text-free accessibility replay fixture. It models only application capabilities, event timing,
/// and expected user-visible health so scenarios are safe to keep in source control.
struct AXScenario: Codable, Equatable {
    struct App: Codable, Equatable {
        let bundleIdentifier: String
        let version: String
        let build: String
        let macOSVersion: String
        let macOSBuild: String
    }

    enum FieldKind: String, Codable {
        case native
        case richText
        case web
        case secure
        case unsupported
    }

    enum EventKind: String, Codable {
        case permission
        case globalPause
        case appPause
        case siteDisabled
        case consent
        case axOutcome
        case geometry
        case replacement
        case focusChanged
        case processChanged
    }

    struct Event: Codable, Equatable {
        let kind: EventKind
        let value: String
        let delayMilliseconds: Int

        init(kind: EventKind, value: String, delayMilliseconds: Int = 0) {
            self.kind = kind
            self.value = value
            self.delayMilliseconds = delayMilliseconds
        }
    }

    struct ExpectedHealth: Codable, Equatable {
        let state: CheckingState
        let reason: InactiveReason?
        let capabilities: CapabilitySet
        let action: RecoveryAction?
    }

    let version: Int
    let app: App
    let field: FieldKind
    let events: [Event]
    let expected: ExpectedHealth
}

/// Deterministic fallback evaluator used by replay tests. It does not invoke Accessibility APIs and
/// deliberately contains no captured writing, ranges, or suggestion content.
enum AXScenarioReplay {
    static func evaluate(_ scenario: AXScenario) -> AXScenario.ExpectedHealth {
        var permissionGranted = true
        var globalPaused = false
        var appPaused = false
        var siteDisabled = false
        var consentGranted = true
        var outcome: AXOperationOutcome = .success
        var geometryReliable = true
        var replacementVerifiable = true

        for event in scenario.events {
            switch event.kind {
            case .permission:
                permissionGranted = event.value == "granted"
            case .globalPause:
                globalPaused = event.value == "paused"
            case .appPause:
                appPaused = event.value == "paused"
            case .siteDisabled:
                siteDisabled = event.value == "disabled"
            case .consent:
                consentGranted = event.value == "granted"
            case .axOutcome:
                outcome = AXOperationOutcome(rawValue: event.value) ?? .unavailable
            case .geometry:
                geometryReliable = event.value == "reliable"
            case .replacement:
                replacementVerifiable = event.value == "verifiable"
            case .focusChanged, .processChanged:
                // Focus and process transitions invalidate the real AX element before a fresh
                // evaluation. The fixture keeps the resulting capability decision deterministic.
                continue
            }
        }

        // The order matches RuntimeHealth's user-facing safety priority.
        if !permissionGranted {
            return expected(state: .inactive, reason: .permission, action: .grantPermission)
        }
        if globalPaused {
            return expected(state: .inactive, reason: .globalPause, action: .resume)
        }
        if appPaused {
            return expected(state: .inactive, reason: .appPause, action: .resume)
        }
        if siteDisabled {
            return expected(state: .inactive, reason: .siteDisabled, action: .enable)
        }
        if !consentGranted {
            return expected(state: .inactive, reason: .consentRequired, action: .trySafely)
        }
        if scenario.field == .secure {
            return expected(state: .inactive, reason: .secureField)
        }
        if scenario.field == .unsupported || outcome == .unsupported || outcome == .invalidValue {
            return expected(state: .inactive, reason: .unsupportedField, action: .retry)
        }
        if outcome == .permissionDenied {
            return expected(state: .inactive, reason: .permission, action: .grantPermission)
        }
        if outcome == .timeout || outcome == .unavailable || outcome == .invalidElement {
            return expected(state: .recovering, reason: nil, action: .retry)
        }

        var capabilities: CapabilitySet = [.textReading, .grammar, .style]
        if geometryReliable {
            capabilities.insert(.inlinePositioning)
        }
        if replacementVerifiable {
            capabilities.insert(.safeReplacement)
        }
        return expected(
            state: capabilities == .full ? .active : .limited,
            reason: nil,
            capabilities: capabilities,
            action: nil
        )
    }

    private static func expected(
        state: CheckingState,
        reason: InactiveReason?,
        capabilities: CapabilitySet = [],
        action: RecoveryAction? = nil
    ) -> AXScenario.ExpectedHealth {
        AXScenario.ExpectedHealth(
            state: state,
            reason: reason,
            capabilities: capabilities,
            action: action
        )
    }
}

private extension AXOperationOutcome {
    init?(rawValue: String) {
        switch rawValue {
        case "success": self = .success
        case "unsupported": self = .unsupported
        case "invalidElement": self = .invalidElement
        case "unavailable": self = .unavailable
        case "permissionDenied": self = .permissionDenied
        case "timeout": self = .timeout
        case "invalidValue": self = .invalidValue
        default: return nil
        }
    }
}
