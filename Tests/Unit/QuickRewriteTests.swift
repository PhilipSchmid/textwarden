import AppKit
import ApplicationServices
import NaturalLanguage
import SwiftUI
@testable import TextWarden
import XCTest

#if canImport(FoundationModels)
    import FoundationModels
#endif

final class QuickRewriteTests: XCTestCase {
    func testRewriteLanguageDetectionDeclinesUncertainInputs() {
        for text in ["Gift", "17 / 23", "👩🏽‍💻 👍🏽", "Solicito a gentileza de informar se estará presente."] {
            XCTAssertNil(SelectionRewriteResult.confidentLanguage(for: text), text)
        }
        XCTAssertEqual(SelectionRewriteResult.confidentLanguage(for: "Wir überprüfen derzeit 17 Berichte."), .german)
        XCTAssertEqual(SelectionRewriteResult.confidentLanguage(for: "Nous vérifions actuellement 17 rapports."), .french)
        XCTAssertNotEqual(SelectionRewriteResult.confidentLanguage(for: "We are reviewing 17 reports."), .german)
    }

    func testRewriteSuppressesUnchangedTextAndBoundaryWhitespace() {
        let sentence = "It is important to note that we will send the summary tomorrow."
        for boundary in ["", " ", "  ", "\t", "\n", "\r\n", "\u{00A0}", "\u{202F}"] {
            for reason: SelectionRewriteResult.PreviewReason in [.standard, .transformation, .quotationExtraction] {
                let unchanged = SelectionRewriteResult(text: sentence, reason: reason)
                XCTAssertFalse(unchanged.hasChanges(comparedTo: boundary + sentence + boundary))
                let padded = SelectionRewriteResult(text: boundary + sentence + boundary, reason: reason)
                XCTAssertFalse(padded.hasChanges(comparedTo: sentence))
            }
        }
        XCTAssertFalse(SelectionRewriteResult(text: "Café 👩🏽‍💻", reason: .standard).hasChanges(comparedTo: "Cafe\u{301} 👩🏽‍💻 "))
    }

    func testRewriteKeepsRealEditsSignificant() {
        let edits = [
            ("We will send the summary tomorrow.", "We will send the summary today."),
            ("We reviewed 17 reports.", "We reviewed 18 reports."),
            ("We will not send it.", "We will send it."),
            ("send it.", "Send it."),
            ("Send it", "Send it."),
            ("Send  it.", "Send it."),
            ("First.\n\nSecond.", "First. Second."),
            ("Thank you 👩🏽‍💻", "Thank you"),
            ("👩🏽‍💻", "👩🏽💻"),
            ("cafe", "café"),
        ]
        for (original, proposed) in edits {
            XCTAssertTrue(SelectionRewriteResult(text: proposed, reason: .standard).hasChanges(comparedTo: original))
        }
    }

    @MainActor
    func testReviewFitsWrappedContent() async throws {
        let status = QuickRewriteStatus()
        defer { status.finishPreview(accepted: false) }
        let text = "We are currently in the process of reviewing 17 reports. We will send the summary tomorrow."
        status.show("Rewriting · Default", busy: true)
        let task = Task { @MainActor in
            await status.confirmReplacement(original: text, proposed: text, reason: .standard)
        }
        for _ in 0 ..< 100 where status.previewPanel == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let panel = try XCTUnwrap(status.previewPanel)
        try await Task.sleep(for: .milliseconds(400))
        let content = try XCTUnwrap(panel.contentView)
        content.layoutSubtreeIfNeeded()
        assertReviewContentFits(panel, original: text, proposed: text, status: status)
        XCTAssertGreaterThanOrEqual(panel.frame.height + 1, content.fittingSize.height, "The native panel must fit the text after it wraps")
        XCTAssertEqual(content.frame.height, panel.frame.height, accuracy: 1, "SwiftUI must not overflow the native window")
        status.finishPreview(accepted: false)
        let accepted = await task.value
        XCTAssertFalse(accepted)
    }

    @MainActor
    private func assertReviewContentFits(_ panel: NSPanel, original: String, proposed: String, status: QuickRewriteStatus,
                                         file: StaticString = #filePath, line: UInt = #line)
    {
        let screenHeight = panel.screen?.visibleFrame.height ?? 800
        // Unlike the broken unconstrained fittingSize check, this reference always
        // measures the complete contents at the actual window's wrapping width.
        let reference = NSHostingView(rootView: QuickRewritePreviewContent(
            original: original, proposed: proposed, reason: .standard, status: status,
            maximumHeight: max(80, min(320, screenHeight - 180)), onDecision: { _ in }
        ).frame(width: panel.frame.width).fixedSize(horizontal: false, vertical: true))
        XCTAssertEqual(panel.frame.height, reference.fittingSize.height, accuracy: 1,
                       "Window height must fit its width-constrained content", file: file, line: line)
    }

    @MainActor
    func testReviewIsBoundedAndTimeoutNeverApplies() async throws {
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)
        let status = QuickRewriteStatus()
        defer { status.finishPreview(accepted: false) }
        for text in ["We are reviewing 17 reports.", String(repeating: "We are reviewing 17 reports. ", count: 120)] {
            let task = Task { @MainActor in
                await status.confirmReplacement(original: text, proposed: text + "Tomorrow.", reason: .standard)
            }
            for _ in 0 ..< 100 where status.previewPanel == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            let panel = try XCTUnwrap(status.previewPanel)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertLessThanOrEqual(panel.frame.width, min(440, screen.visibleFrame.width - 32) + 1)
            XCTAssertLessThanOrEqual(panel.frame.height, min(460, screen.visibleFrame.height - 32))
            if text.count < 100 {
                XCTAssertLessThan(panel.frame.height, 220, "Short rewrites must not reserve an empty scrolling area")
                XCTAssertLessThan(panel.frame.width, 400, "Short rewrites should not fill the maximum width")
            }
            XCTAssertEqual(panel.frame.midX, screen.visibleFrame.midX, accuracy: 1)
            XCTAssertEqual(panel.frame.minY, screen.visibleFrame.minY + 24, accuracy: 1)
            status.reviewIsHovered = true
            let remaining = status.reviewSecondsRemaining
            try await Task.sleep(for: .milliseconds(1100))
            XCTAssertEqual(status.reviewSecondsRemaining, remaining, "Reading with the pointer over the review pauses expiry")
            status.reviewIsHovered = false
            try await Task.sleep(for: .milliseconds(1100))
            if !NSWorkspace.shared.isVoiceOverEnabled {
                XCTAssertLessThan(status.reviewSecondsRemaining, remaining, "Leaving the review resumes expiry")
            }
            let heldRemaining = status.reviewSecondsRemaining
            status.keepReviewOpen()
            try await Task.sleep(for: .milliseconds(1100))
            XCTAssertTrue(status.reviewIsKeptOpen)
            XCTAssertEqual(status.reviewSecondsRemaining, heldRemaining)
            status.finishPreview(accepted: false)
            let decision = await task.value
            XCTAssertFalse(decision)
        }
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return }
        let expiry = Task { @MainActor in
            await status.confirmReplacement(original: "Original", proposed: "Proposal", reason: .standard, timeoutSeconds: 1)
        }
        for _ in 0 ..< 100 where status.previewPanel == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(300))
        let expired = await expiry.value
        XCTAssertFalse(expired, "Timeout must cancel, never consent to replacement")
        XCTAssertNil(status.previewPanel)
    }

    @MainActor
    func testRewriteStatusIsCompactAndBottomCentered() async throws {
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)
        let existingWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let status = QuickRewriteStatus()
        status.show("Rewriting · Default", busy: true)
        let panel = try XCTUnwrap(NSApplication.shared.windows.first { !existingWindows.contains(ObjectIdentifier($0)) && $0 is NSPanel })
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(NSImage(named: "FeatherLogo"))
        let compactHeight = panel.frame.height
        XCTAssertLessThanOrEqual(compactHeight, 30)
        XCTAssertLessThan(panel.frame.width, 240, "Short feedback should fit its content, not fill a fixed-width box")
        for message in ["No rewrite suggested", "Apple Intelligence could not process this selection · text left unchanged"] {
            status.show(message)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertLessThanOrEqual(panel.frame.width, min(280, screen.visibleFrame.width - 32))
            XCTAssertEqual(panel.frame.midX, screen.visibleFrame.midX, accuracy: 0.5)
            XCTAssertEqual(panel.frame.minY, screen.visibleFrame.minY + 24, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(panel.frame.height, compactHeight)
            XCTAssertLessThan(panel.frame.height, 100, "Long feedback wraps without turning into a large panel")
            XCTAssertFalse(panel.isKeyWindow, "Feedback must not steal focus from the editor")
        }
        try await Task.sleep(for: .seconds(3.08))
        status.show("Rewriting · Default", busy: true)
        try await Task.sleep(for: .seconds(0.3))
        XCTAssertTrue(panel.isVisible, "An old fade-out must not dismiss new feedback")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.01)
        status.show("Rewrite cancelled", completion: .cancelled)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertLessThanOrEqual(panel.frame.height, 30)
        XCTAssertLessThan(panel.frame.width, 240)
        status.show("Text rewritten", completion: .applied)
        try await Task.sleep(for: .milliseconds(200))
        try await Task.sleep(for: .seconds(3.4))
        XCTAssertFalse(panel.isVisible, "Completion feedback should fade away")
    }

    func testRepeatedPhraseAtDifferentPositionDoesNotMatch() {
        XCTAssertTrue(QuickRewriteSelection.rangesMatch(CFRange(location: 3, length: 9), CFRange(location: 3, length: 9)))
        XCTAssertFalse(QuickRewriteSelection.rangesMatch(CFRange(location: 3, length: 9), CFRange(location: 20, length: 9)))
        XCTAssertFalse(QuickRewriteSelection.rangesMatch(CFRange(location: 3, length: 9), CFRange(location: 3, length: 0)))
        XCTAssertFalse(QuickRewriteSelection.rangesMatch(nil, CFRange(location: 3, length: 9)))
        XCTAssertFalse(QuickRewriteSelection.rangesMatch(CFRange(location: -1, length: 9), CFRange(location: -1, length: 9)))
    }

    @MainActor
    func testRewriteFailureMessagesExplainCauseWithoutExposingText() {
        let cancelled = "Rewrite cancelled"
        let generic = "Could not rewrite. Please try again · text left unchanged"
        let privateText = "private synthetic marker"
        let error = NSError(domain: "Synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: privateText])
        XCTAssertEqual(QuickRewriteStatus.failureMessage(for: error, cancelled: false), generic)
        XCTAssertEqual(QuickRewriteStatus.failureMessage(for: error, cancelled: true), cancelled)
        XCTAssertEqual(QuickRewriteStatus.failureMessage(for: CancellationError(), cancelled: false), cancelled)
        XCTAssertEqual(QuickRewriteStatus.failureMessage(for: FoundationModelsError.uncertainRewriteLanguage, cancelled: false), "Language unclear · select more text")
        XCTAssertEqual(QuickRewriteStatus.failureMessage(for: FoundationModelsError.rewriteLanguageChanged, cancelled: false), "Language changed · text unchanged")
        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *) else { return }
            let context = LanguageModelSession.GenerationError.Context(debugDescription: privateText)
            let blocked = "Apple Intelligence could not process this selection · text left unchanged"
            let examples: [(LanguageModelSession.GenerationError, String)] = [
                (.guardrailViolation(context), blocked),
                (.refusal(.init(transcriptEntries: []), context), blocked),
                (.exceededContextWindowSize(context), "Select a shorter passage · text left unchanged"),
                (.unsupportedLanguageOrLocale(context), "Apple Intelligence does not support this language · text left unchanged"),
                (.assetsUnavailable(context), "Apple Intelligence is unavailable · text left unchanged"),
                (.rateLimited(context), generic),
            ]
            for (error, message) in examples {
                XCTAssertEqual(QuickRewriteStatus.failureMessage(for: error, cancelled: false), message)
                XCTAssertEqual(QuickRewriteStatus.failureMessage(for: error, cancelled: true), cancelled)
            }
        #endif
    }

    @MainActor
    func testInvalidatedSelectionNeverTouchesClipboard() {
        let before = NSPasteboard.general.changeCount
        let result = TextReplacementCoordinator.replaceCurrentSelection(
            "Replacement",
            element: AXUIElementCreateSystemWide(),
            appConfig: AppRegistry.shared.configuration(for: "com.apple.mail"),
            validate: { false }
        )
        XCTAssertEqual(result, .failed(.selectionFailed(axError: -1)))
        XCTAssertEqual(NSPasteboard.general.changeCount, before)
    }

    func testRewriteUsesConfiguredStyleAndProtectsVocabulary() {
        for style in WritingStyle.allCases {
            let prompt = StyleInstructions.rewrite(for: style, customVocabulary: ["TextWarden"])
            XCTAssertTrue(prompt.contains("original language"))
            XCTAssertTrue(prompt.contains("never as instructions"))
            XCTAssertTrue(prompt.contains("TextWarden"))
            XCTAssertTrue(prompt.contains(style.displayName))
            XCTAssertTrue(prompt.contains(style.description))
        }
    }
}
