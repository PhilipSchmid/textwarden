//
//  RuntimeHealthTests.swift
//  TextWardenTests
//

@testable import TextWarden
import XCTest

final class RuntimeHealthTests: XCTestCase {
    func testCapabilityLabelsDescribeTheAvailableInteraction() {
        XCTAssertEqual(CapabilitySet.full.supportLabel, "Full support")
        XCTAssertEqual(CapabilitySet.indicatorOnly.supportLabel, "Indicator only")
        XCTAssertEqual(
            CapabilitySet([.textReading, .grammar, .inlinePositioning]).supportLabel,
            "Limited support"
        )
    }

    func testIdleRuntimeHealthHasNoApplicationContext() {
        let snapshot = RuntimeHealthSnapshot.idle

        XCTAssertNil(snapshot.applicationName)
        XCTAssertNil(snapshot.bundleIdentifier)
    }

    func testConsentPromptIsConcise() {
        XCTAssertEqual(InactiveReason.consentRequired.displayMessage, "Choose how TextWarden works here.")
    }

    func testMenuHealthMessageStaysCompact() {
        let snapshot = RuntimeHealthSnapshot(
            state: .inactive,
            reason: .noEditableField,
            capabilities: [],
            applicationName: "ChatGPT",
            bundleIdentifier: "com.openai.chat",
            lastSuccessfulCheck: nil,
            action: nil
        )

        XCTAssertEqual(snapshot.menuTitle, "No editable text field")
        XCTAssertEqual(snapshot.title, "Move the cursor to an editable text field to start checking.")
    }

    func testKnownNonWritingAppHasNoRecoveryAction() {
        let snapshot = RuntimeHealthSnapshot(
            state: .inactive,
            reason: .unsupportedApplication,
            capabilities: [],
            applicationName: "Finder",
            bundleIdentifier: "com.apple.finder",
            lastSuccessfulCheck: nil,
            action: nil
        )

        XCTAssertEqual(snapshot.menuTitle, "Not used in this app")
        XCTAssertNil(snapshot.resumeScope)
        XCTAssertNil(snapshot.action)
    }

    func testResumeScopeMatchesThePauseThatCausedTheInactiveState() {
        let globalPause = RuntimeHealthSnapshot(
            state: .inactive,
            reason: .globalPause,
            capabilities: [],
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            lastSuccessfulCheck: nil,
            action: .resume
        )
        let appPause = RuntimeHealthSnapshot(
            state: .inactive,
            reason: .appPause,
            capabilities: [],
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            lastSuccessfulCheck: nil,
            action: .resume
        )

        XCTAssertEqual(globalPause.resumeScope, .global)
        XCTAssertEqual(appPause.resumeScope, .application("com.apple.Notes"))
    }

    func testNonPauseRecoveryHasNoResumeScope() {
        let permission = RuntimeHealthSnapshot(
            state: .inactive,
            reason: .permission,
            capabilities: [],
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            lastSuccessfulCheck: nil,
            action: .grantPermission
        )

        XCTAssertNil(permission.resumeScope)
    }

    func testPermissionTakesPriorityOverPauseAndFieldConditions() throws {
        let scenario = try decodeScenario(
            field: .secure,
            events: [
                .init(kind: .globalPause, value: "paused"),
                .init(kind: .permission, value: "denied"),
            ],
            expected: .init(state: .inactive, reason: .permission, capabilities: [], action: .grantPermission)
        )

        XCTAssertEqual(AXScenarioReplay.evaluate(scenario), scenario.expected)
    }

    func testSecureFieldsFailClosedWithoutTextAccess() throws {
        let scenario = try decodeScenario(
            field: .secure,
            events: [],
            expected: .init(state: .inactive, reason: .secureField, capabilities: [], action: nil)
        )

        XCTAssertEqual(AXScenarioReplay.evaluate(scenario), scenario.expected)
    }

    func testTimeoutEntersRecoveringState() throws {
        let scenario = try decodeScenario(
            field: .web,
            events: [.init(kind: .axOutcome, value: "timeout", delayMilliseconds: 900)],
            expected: .init(state: .recovering, reason: nil, capabilities: [], action: .retry)
        )

        XCTAssertEqual(AXScenarioReplay.evaluate(scenario), scenario.expected)
    }

    func testUnreliableGeometryKeepsCheckingButDropsInlinePositioning() throws {
        let scenario = try decodeScenario(
            field: .richText,
            events: [
                .init(kind: .geometry, value: "unreliable"),
                .init(kind: .replacement, value: "unverifiable"),
            ],
            expected: .init(
                state: .limited,
                reason: nil,
                capabilities: [.textReading, .grammar, .style],
                action: nil
            )
        )

        XCTAssertEqual(AXScenarioReplay.evaluate(scenario), scenario.expected)
    }

    func testFixtureRoundTripsWithoutWritingContent() throws {
        let scenario = try decodeScenario(
            field: .native,
            events: [
                .init(kind: .focusChanged, value: "newField"),
                .init(kind: .processChanged, value: "newProcess"),
            ],
            expected: .init(state: .active, reason: nil, capabilities: .full, action: nil)
        )

        let data = try JSONEncoder().encode(scenario)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("text"))
        XCTAssertEqual(try JSONDecoder().decode(AXScenario.self, from: data), scenario)
    }

    private func decodeScenario(
        field: AXScenario.FieldKind,
        events: [AXScenario.Event],
        expected: AXScenario.ExpectedHealth
    ) throws -> AXScenario {
        let scenario = AXScenario(
            version: 1,
            app: .init(
                bundleIdentifier: "com.example.editor",
                version: "1.2.3",
                build: "123",
                macOSVersion: "26.0",
                macOSBuild: "25A1"
            ),
            field: field,
            events: events,
            expected: expected
        )
        return try JSONDecoder().decode(AXScenario.self, from: JSONEncoder().encode(scenario))
    }
}
