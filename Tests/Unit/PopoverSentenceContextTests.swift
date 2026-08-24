//
//  PopoverSentenceContextTests.swift
//  TextWardenTests
//

@testable import TextWarden
import XCTest

final class PopoverSentenceContextTests: XCTestCase {
    func testSentenceEndIgnoresPunctuationInsideMarkdownLinkURLs() throws {
        let text = "I definately decided to use [quickwit-oss/whichlang](https://github.com/quickwit-oss/whichlang) over [greyblake/whatlang-rs](https://github.com/greyblake/whatlang-rs)."
        let errorRange = try XCTUnwrap(text.range(of: "definately"))

        let sentenceEnd = SentenceContextView.sentenceEnd(
            in: text,
            startingAt: errorRange.lowerBound
        )

        XCTAssertEqual(String(text[..<sentenceEnd]), text)
    }

    func testSentenceEndStopsBeforeTheNextSentence() throws {
        let firstSentence = "A typoo appears before https://github.com/example/repository."
        let text = "\(firstSentence) Another sentence follows."
        let errorRange = try XCTUnwrap(text.range(of: "typoo"))

        let sentenceEnd = SentenceContextView.sentenceEnd(
            in: text,
            startingAt: errorRange.lowerBound
        )

        XCTAssertEqual(String(text[..<sentenceEnd]), firstSentence)
    }

    func testSentenceEndIgnoresQueryPunctuationInsideURLs() throws {
        let firstSentence = "A typoo points to https://example.com/search?q=all!active."
        let text = "\(firstSentence) Another sentence follows."
        let errorRange = try XCTUnwrap(text.range(of: "typoo"))

        let sentenceEnd = SentenceContextView.sentenceEnd(
            in: text,
            startingAt: errorRange.lowerBound
        )

        XCTAssertEqual(String(text[..<sentenceEnd]), firstSentence)
    }
}
