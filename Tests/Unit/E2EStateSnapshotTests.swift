//
//  E2EStateSnapshotTests.swift
//  TextWardenTests
//

@testable import TextWarden
import XCTest

final class E2EStateSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsWithoutTextBearingFields() throws {
        let snapshot = E2EStateSnapshot(
            schemaVersion: 1,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000.123),
            textWardenProcessID: 123,
            state: .init(
                activeApplication: .init(
                    ApplicationContext(
                        bundleIdentifier: "com.apple.mail",
                        processID: 456,
                        applicationName: "Mail"
                    )
                ),
                monitoredApplication: nil,
                monitoredElement: .init(identity: "abc123", role: "AXTextArea"),
                analysis: .init(
                    generation: 7,
                    segmentLength: 42,
                    segmentStart: 0,
                    segmentEnd: 42,
                    lastAnalyzedAt: Date(timeIntervalSince1970: 1_700_000_001),
                    grammarErrors: [.init(start: 5, end: 9, category: "Spelling")],
                    styleSuggestionCount: 0,
                    hasReadabilityResult: false
                ),
                presentation: .init(
                    overlayState: "showingUnderlines",
                    overlayVisible: true,
                    overlayAlpha: 1,
                    overlayFrame: .init(CGRect(x: 10, y: 20, width: 300, height: 100)),
                    grammarUnderlineCount: 1,
                    grammarUnderlineHitPoints: [.init(CGPoint(x: 25, y: 30))],
                    styleUnderlineCount: 0,
                    readabilityUnderlineCount: 0,
                    indicatorVisible: true,
                    indicatorGrammarErrorCount: 1,
                    indicatorStyleSuggestionCount: 0,
                    suggestionPopoverVisible: false,
                    suggestionPopoverRange: nil,
                    readabilityPopoverVisible: false,
                    textGenerationPopoverVisible: false,
                    geometry: .init(strategy: "MailStrategy", minimumConfidence: 1, failureReason: nil),
                    hiddenDueToScroll: false,
                    hiddenDueToMovement: false,
                    hiddenDueToWindowOffScreen: false
                ),
                replacement: .init(
                    isApplying: false,
                    isInGracePeriod: false,
                    lastReplacementAt: nil,
                    focusBounceCompletedAt: nil
                ),
                events: .init(
                    lastAccessibilityEvent: "AXValueChanged",
                    lastAccessibilityEventAt: Date(timeIntervalSince1970: 1_700_000_002),
                    lastAccessibilityEventElementRole: "AXTextArea",
                    lastPointerEvent: "leftMouseDown",
                    lastPointerEventAt: Date(timeIntervalSince1970: 1_700_000_002),
                    lastOverlayEvent: "analysisCompleted(hasErrors:true)",
                    lastOverlayEventAt: Date(timeIntervalSince1970: 1_700_000_003)
                ),
                runtimeHealth: .init(
                    state: "limited",
                    reason: nil,
                    capabilities: 15,
                    supportLabel: "Limited support",
                    lastSuccessfulCheck: Date(timeIntervalSince1970: 1_700_000_004)
                )
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("\"content\""))
        XCTAssertFalse(json.contains("\"sourceText\""))
        XCTAssertFalse(json.contains("\"lintID\""))
        XCTAssertFalse(json.contains("\"message\""))
        XCTAssertFalse(json.contains("\"suggestions\""))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        XCTAssertEqual(try decoder.decode(E2EStateSnapshot.self, from: data), snapshot)
    }

    func testWriterCreatesOwnerOnlyFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("state.json")
        let snapshot = E2EStateSnapshot(
            schemaVersion: 1,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000.123),
            textWardenProcessID: 123,
            state: .init(
                activeApplication: nil,
                monitoredApplication: nil,
                monitoredElement: nil,
                analysis: .init(
                    generation: 0,
                    segmentLength: nil,
                    segmentStart: nil,
                    segmentEnd: nil,
                    lastAnalyzedAt: nil,
                    grammarErrors: [],
                    styleSuggestionCount: 0,
                    hasReadabilityResult: false
                ),
                presentation: .init(
                    overlayState: "idle",
                    overlayVisible: false,
                    overlayAlpha: 1,
                    overlayFrame: .init(.zero),
                    grammarUnderlineCount: 0,
                    grammarUnderlineHitPoints: [],
                    styleUnderlineCount: 0,
                    readabilityUnderlineCount: 0,
                    indicatorVisible: false,
                    indicatorGrammarErrorCount: 0,
                    indicatorStyleSuggestionCount: 0,
                    suggestionPopoverVisible: false,
                    suggestionPopoverRange: nil,
                    readabilityPopoverVisible: false,
                    textGenerationPopoverVisible: false,
                    geometry: .init(strategy: nil, minimumConfidence: nil, failureReason: nil),
                    hiddenDueToScroll: false,
                    hiddenDueToMovement: false,
                    hiddenDueToWindowOffScreen: false
                ),
                replacement: .init(
                    isApplying: false,
                    isInGracePeriod: false,
                    lastReplacementAt: nil,
                    focusBounceCompletedAt: nil
                ),
                events: .init(
                    lastAccessibilityEvent: nil,
                    lastAccessibilityEventAt: nil,
                    lastAccessibilityEventElementRole: nil,
                    lastPointerEvent: nil,
                    lastPointerEventAt: nil,
                    lastOverlayEvent: nil,
                    lastOverlayEventAt: nil
                ),
                runtimeHealth: .init(
                    state: "inactive",
                    reason: "noEditableField",
                    capabilities: 0,
                    supportLabel: "Unavailable",
                    lastSuccessfulCheck: nil
                )
            )
        )

        try E2EStateReporter.write(snapshot, to: fileURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
        XCTAssertEqual(json["capturedAt"] as? NSNumber, NSNumber(value: 1_700_000_000_123))
    }
}
