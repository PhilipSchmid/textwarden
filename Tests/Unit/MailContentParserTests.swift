import AppKit
@testable import TextWarden
import XCTest

final class MailContentParserTests: XCTestCase {
    @MainActor
    func testLiveLargeDraftExtractionStaysBelowWatchdogLimit() throws {
        guard ProcessInfo.processInfo.environment["TEXTWARDEN_TEST_MAIL_LARGE_DRAFT"] == "1" else {
            throw XCTSkip("Prepare the recipient-free CPU large-errors Mail fixture and opt in")
        }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first)
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        XCTAssertEqual(AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused), .success)
        let raw = try XCTUnwrap(focused)
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return XCTFail("Mail has no focused accessibility element")
        }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        let expected = String(repeating: "This is a sentnce with a spelling mistke. ", count: 1300).trimmingCharacters(in: .whitespaces)
        let parser = MailContentParser()
        for _ in 0 ..< 3 {
            let start = ProcessInfo.processInfo.systemUptime
            let text = parser.extractText(from: element)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            XCTAssertEqual(text, expected)
            XCTAssertLessThan(elapsed, 0.5, "Extraction needs headroom below the 0.8s AX watchdog")
        }
    }

    func testLocalizedQuoteAttributionsKeepOnlyTheNewMessage() {
        let attributions = [
            "On Dec 14, 2025, John wrote:",
            "Am 14.12.2025 schrieb John:",
            "Le 14 déc. 2025, John a écrit :",
            "El 14 de diciembre, John escribió:",
            "Il 14 dic 2025 John ha scritto:",
            "Em 14 de dez, John escreveu:",
            "Op 14 dec 2025 schreef John:",
            "Den 14 dec 2025 skrev John:",
            "14 декабря 2025 John написал:",
            "14 Aralık 2025 tarihinde John yazdı:",
            "在 2025年12月14日 John 写道：",
            "2025年12月14日 John のメッセージ:",
            "2025년 John님이 작성:",
            "كتب John في 2025:",
            "Vào 14 tháng 12, John đã viết:",
            "14 दिसंबर को John ने लिखा:",
            "> Previous message",
            "-----Original Message-----",
            "Begin forwarded message:",
            "From: john@example.com",
            "Join Webex Meeting",
        ]
        for attribution in attributions {
            XCTAssertEqual(
                MailContentParser.stripQuotedContent(from: "New message.\n\n\(attribution)\nOld message."),
                "New message.", attribution
            )
        }
    }

    func testLongUnquotedLinesRemainIntactWithoutQuadraticScanning() {
        for repetitions in [4, 50, 1300] {
            let text = String(repeating: "We are reviewing the report tomorrow. ", count: repetitions)
            let started = ProcessInfo.processInfo.systemUptime
            let result = MailContentParser.stripQuotedContent(from: text)
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            XCTAssertEqual(result, text.trimmingCharacters(in: .whitespacesAndNewlines))
            // Generous CI ceiling that catches suffix-rescanning regressions.
            XCTAssertLessThan(elapsed, 2, "Quote stripping must not rescan every suffix of a long line")
        }
    }

    func testUnicodeAndBlankLinesBeforeQuoteKeepTheirOffsets() {
        XCTAssertEqual(
            MailContentParser.stripQuotedContent(from: "Hello 👋 café.\r\nSecond line.\r\n\r\n日期 John 写道：\r\nQuoted."),
            "Hello 👋 café.\n\nSecond line."
        )
        XCTAssertEqual(MailContentParser.stripQuotedContent(from: "普通文本没有引用标记。"), "普通文本没有引用标记。")
        XCTAssertEqual(MailContentParser.stripQuotedContent(from: ""), "")
    }
}
