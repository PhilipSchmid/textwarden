//
//  E2EStateSnapshot.swift
//  TextWarden
//
//  Privacy-safe runtime state for opt-in macOS end-to-end testing.
//

import AppKit
import Foundation

/// Text-free state used by external macOS test drivers to distinguish host-app behavior
/// from TextWarden analysis and presentation behavior.
struct E2EStateSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let capturedAt: Date
    let textWardenProcessID: Int32
    let state: State

    struct State: Codable, Equatable {
        let activeApplication: Application?
        let monitoredApplication: Application?
        let monitoredElement: Element?
        let analysis: Analysis
        let presentation: Presentation
        let replacement: Replacement
        let events: Events
        let runtimeHealth: RuntimeHealth
    }

    struct Application: Codable, Equatable {
        let bundleIdentifier: String
        let processID: Int32
        let applicationName: String

        init(_ context: ApplicationContext) {
            bundleIdentifier = context.bundleIdentifier
            processID = context.processID
            applicationName = context.applicationName
        }
    }

    struct Element: Codable, Equatable {
        let identity: String
        let role: String?
    }

    struct Analysis: Codable, Equatable {
        let generation: UInt64
        let segmentLength: Int?
        let segmentStart: Int?
        let segmentEnd: Int?
        let lastAnalyzedAt: Date?
        let grammarErrors: [GrammarError]
        let styleSuggestionCount: Int
        let hasReadabilityResult: Bool
    }

    struct GrammarError: Codable, Equatable {
        let start: Int
        let end: Int
        let category: String
    }

    struct Presentation: Codable, Equatable {
        let overlayState: String
        let overlayVisible: Bool
        let overlayAlpha: Double
        let overlayFrame: Frame
        let grammarUnderlineCount: Int
        let grammarUnderlineHitPoints: [Point]
        let styleUnderlineCount: Int
        let readabilityUnderlineCount: Int
        let indicatorVisible: Bool
        let indicatorFrame: Frame
        let indicatorGrammarErrorCount: Int
        let indicatorStyleSuggestionCount: Int
        let suggestionPopoverVisible: Bool
        let suggestionPopoverRange: Range?
        let readabilityPopoverVisible: Bool
        let textGenerationPopoverVisible: Bool
        let geometry: Geometry
        let hiddenDueToScroll: Bool
        let hiddenDueToMovement: Bool
        let hiddenDueToWindowOffScreen: Bool
    }

    struct Frame: Codable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ frame: CGRect) {
            x = frame.origin.x
            y = frame.origin.y
            width = frame.size.width
            height = frame.size.height
        }
    }

    struct Point: Codable, Equatable {
        let x: Double
        let y: Double

        init(_ point: CGPoint) {
            x = point.x
            y = point.y
        }
    }

    struct Range: Codable, Equatable {
        let start: Int
        let end: Int
    }

    struct Geometry: Codable, Equatable {
        let strategy: String?
        let minimumConfidence: Double?
        let failureReason: String?
    }

    struct Replacement: Codable, Equatable {
        let isApplying: Bool
        let isInGracePeriod: Bool
        let lastReplacementAt: Date?
        let focusBounceCompletedAt: Date?
    }

    struct Events: Codable, Equatable {
        let lastAccessibilityEvent: String?
        let lastAccessibilityEventAt: Date?
        let lastAccessibilityEventElementRole: String?
        let lastPointerEvent: String?
        let lastPointerEventAt: Date?
        let lastOverlayEvent: String?
        let lastOverlayEventAt: Date?
    }

    struct RuntimeHealth: Codable, Equatable {
        let state: String
        let reason: String?
        let capabilities: Int
        let supportLabel: String
        let lastSuccessfulCheck: Date?
    }
}

/// Publishes a deduplicated snapshot only when explicitly enabled for a test launch.
@MainActor
final class E2EStateReporter: NSObject {
    static let environmentKey = "TEXTWARDEN_E2E_STATE"
    static let fileName = "textwarden-e2e-state.json"

    static let isEnabled = ProcessInfo.processInfo.environment[environmentKey] == "1"

    static var defaultFileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private let fileURL: URL
    private let stateProvider: @MainActor () -> E2EStateSnapshot.State?
    private var timer: Timer?
    private var lastState: E2EStateSnapshot.State?
    private var didLogWriteFailure = false

    private init(
        fileURL: URL,
        stateProvider: @escaping @MainActor () -> E2EStateSnapshot.State?
    ) {
        self.fileURL = fileURL
        self.stateProvider = stateProvider
        super.init()
    }

    static func startIfEnabled(
        stateProvider: @escaping @MainActor () -> E2EStateSnapshot.State?
    ) -> E2EStateReporter? {
        guard isEnabled else { return nil }

        let reporter = E2EStateReporter(fileURL: defaultFileURL, stateProvider: stateProvider)
        reporter.start()
        return reporter
    }

    private func start() {
        publishIfChanged()

        let timer = Timer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(handleTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Logger.info("E2E state reporting enabled at \(fileURL.path)", category: Logger.lifecycle)
    }

    @objc private func handleTimer() {
        publishIfChanged()
    }

    private func publishIfChanged() {
        guard let state = stateProvider(), state != lastState else { return }

        let snapshot = E2EStateSnapshot(
            schemaVersion: 1,
            capturedAt: Date(),
            textWardenProcessID: ProcessInfo.processInfo.processIdentifier,
            state: state
        )

        do {
            try Self.write(snapshot, to: fileURL)
            lastState = state
            didLogWriteFailure = false
        } catch {
            if !didLogWriteFailure {
                Logger.error("Failed to publish E2E state: \(error.localizedDescription)", category: Logger.errors)
                didLogWriteFailure = true
            }
        }
    }

    nonisolated static func write(_ snapshot: E2EStateSnapshot, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    deinit {
        timer?.invalidate()
    }
}

extension AnalysisCoordinator {
    func makeE2EState() -> E2EStateSnapshot.State {
        let segment = currentSegment
        let activeApplication = applicationTracker.activeApplication.map(E2EStateSnapshot.Application.init)
        let monitoredApplication = monitoredContext.map(E2EStateSnapshot.Application.init)
        let monitoredElement = textMonitor.monitoredElement.map { element in
            E2EStateSnapshot.Element(
                identity: String(CFHash(element), radix: 16),
                role: textMonitor.monitoredElementRole
            )
        }
        let health = RuntimeHealthStore.shared.snapshot
        let visiblePopoverError = suggestionPopover.isVisible ? suggestionPopover.currentError : nil

        return E2EStateSnapshot.State(
            activeApplication: activeApplication,
            monitoredApplication: monitoredApplication,
            monitoredElement: monitoredElement,
            analysis: .init(
                generation: grammarAnalysisGeneration,
                segmentLength: segment?.length,
                segmentStart: segment?.startIndex,
                segmentEnd: segment?.endIndex,
                lastAnalyzedAt: segment?.timestamp,
                grammarErrors: currentErrors.map {
                    .init(start: $0.start, end: $0.end, category: $0.category)
                },
                styleSuggestionCount: currentStyleSuggestions.count,
                hasReadabilityResult: currentReadabilityResult != nil
            ),
            presentation: .init(
                overlayState: overlayStateMachine.currentState.description,
                overlayVisible: errorOverlay.diagnosticIsVisible,
                overlayAlpha: errorOverlay.alphaValue,
                overlayFrame: .init(errorOverlay.frame),
                grammarUnderlineCount: errorOverlay.grammarUnderlineCount,
                grammarUnderlineHitPoints: errorOverlay.diagnosticGrammarUnderlineHitPoints.map(E2EStateSnapshot.Point.init),
                styleUnderlineCount: errorOverlay.styleUnderlineCount,
                readabilityUnderlineCount: errorOverlay.readabilityUnderlineCount,
                indicatorVisible: floatingIndicator.isVisible,
                indicatorFrame: .init(CoordinateMapper.toQuartzCoordinates(floatingIndicator.frame)),
                indicatorGrammarErrorCount: floatingIndicator.diagnosticGrammarErrorCount,
                indicatorStyleSuggestionCount: floatingIndicator.diagnosticStyleSuggestionCount,
                suggestionPopoverVisible: suggestionPopover.isVisible,
                suggestionPopoverRange: visiblePopoverError.map { .init(start: $0.start, end: $0.end) },
                readabilityPopoverVisible: ReadabilityPopover.shared.isVisible,
                textGenerationPopoverVisible: TextGenerationPopover.shared.isVisible,
                geometry: .init(
                    strategy: errorOverlay.lastGeometryStrategy,
                    minimumConfidence: errorOverlay.lastGeometryConfidence,
                    failureReason: errorOverlay.lastGeometryFailureReason
                ),
                hiddenDueToScroll: overlaysHiddenDueToScroll,
                hiddenDueToMovement: overlaysHiddenDueToMovement,
                hiddenDueToWindowOffScreen: overlaysHiddenDueToWindowOffScreen
            ),
            replacement: .init(
                isApplying: isApplyingReplacement,
                isInGracePeriod: isInReplacementMode,
                lastReplacementAt: lastReplacementTime,
                focusBounceCompletedAt: replacementCompletedAt
            ),
            events: .init(
                lastAccessibilityEvent: textMonitor.lastAccessibilityEvent,
                lastAccessibilityEventAt: textMonitor.lastAccessibilityEventAt,
                lastAccessibilityEventElementRole: textMonitor.lastAccessibilityEventElementRole,
                lastPointerEvent: errorOverlay.lastPointerEvent,
                lastPointerEventAt: errorOverlay.lastPointerEventAt,
                lastOverlayEvent: overlayStateMachine.lastEvent,
                lastOverlayEventAt: overlayStateMachine.lastEventAt
            ),
            runtimeHealth: .init(
                state: health.state.rawValue,
                reason: health.reason?.rawValue,
                capabilities: health.capabilities.rawValue,
                supportLabel: health.capabilities.supportLabel,
                lastSuccessfulCheck: health.lastSuccessfulCheck
            )
        )
    }
}
