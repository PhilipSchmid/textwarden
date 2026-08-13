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
        var conditions = RuntimeHealthConditions()

        for event in scenario.events {
            switch event.kind {
            case .permission:
                conditions.permissionGranted = event.value == "granted"
            case .globalPause:
                conditions.globalPaused = event.value == "paused"
            case .appPause:
                conditions.applicationPaused = event.value == "paused"
            case .siteDisabled:
                conditions.siteDisabled = event.value == "disabled"
            case .consent:
                conditions.consentGranted = event.value == "granted"
            case .axOutcome:
                conditions.axOutcome = AXOperationOutcome(rawValue: event.value) ?? .unavailable
            case .geometry:
                conditions.geometryReliable = event.value == "reliable"
            case .replacement:
                conditions.replacementVerifiable = event.value == "verifiable"
            case .focusChanged, .processChanged:
                // Focus and process transitions invalidate the real AX element before a fresh
                // evaluation. The fixture keeps the resulting capability decision deterministic.
                continue
            }
        }

        conditions.fieldCondition = switch scenario.field {
        case .secure:
            .secure
        case .unsupported:
            .unsupported
        case .native, .richText, .web:
            .editable
        }

        let decision = RuntimeHealthPolicy.evaluate(conditions)
        return AXScenario.ExpectedHealth(
            state: decision.state,
            reason: decision.reason,
            capabilities: decision.capabilities,
            action: decision.action
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
