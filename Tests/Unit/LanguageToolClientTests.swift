@testable import TextWarden
import XCTest

final class LanguageToolClientTests: XCTestCase {
    private func json(_ matches: String) -> Data {
        Data("{\"matches\":[\(matches)]}".utf8)
    }

    private func match(
        offset: Int,
        length: Int,
        rule: String = "EXAMPLE_RULE",
        category: String = "GRAMMAR",
        replacements: [String] = []
    ) -> String {
        let values = replacements.map { "{\"value\":\"\($0)\"}" }.joined(separator: ",")
        return """
        {"message":"Possible problem","offset":\(offset),"length":\(length),\
        "replacements":[\(values)],"rule":{"id":"\(rule)","category":{"id":"\(category)"}}}
        """
    }

    private func convert(_ matches: String, in text: String) throws -> [GrammarErrorModel] {
        try LanguageToolClient.convert(responseData: json(matches), in: text)
    }

    // MARK: - Endpoint Restriction

    /// Loopback is what keeps "your writing never leaves your Mac" true, so the
    /// restriction is enforced in the model rather than only hinted at in the UI.
    func testLoopbackHostsAreAccepted() {
        for host in [
            "http://localhost:8081",
            "https://localhost:8081",
            "http://127.0.0.1:8081",
            "http://127.1.2.3:8081",
            "http://lt.localhost:8081",
            "http://[::1]:8081",
        ] {
            XCTAssertNotNil(
                LanguageToolConfiguration(endpointString: host, language: "auto", timeout: 2),
                "\(host) should be accepted"
            )
        }
    }

    func testNonLoopbackHostsAreRejected() {
        for host in [
            "https://api.languagetool.org",
            "http://192.168.1.10:8081",
            "http://10.0.0.5:8081",
            "http://example.com",
            "http://127.0.0.1.example.com",
            "http://notlocalhost",
            "http://localhost.example.com",
            "file:///etc/passwd",
            "not a url",
        ] {
            XCTAssertNil(
                LanguageToolConfiguration(endpointString: host, language: "auto", timeout: 2),
                "\(host) should be rejected"
            )
        }
    }

    func testEmptyLanguageFallsBackToAuto() throws {
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "", timeout: 2)
        )
        XCTAssertEqual(configuration.language, LanguageToolConfiguration.defaultLanguage)
    }

    /// LanguageTool's own documentation shows the full /v2/check URL, so pasting
    /// it must not produce /v2/check/v2/check.
    func testCheckURLToleratesAFullyQualifiedEndpoint() throws {
        let bare = try XCTUnwrap(LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2))
        XCTAssertEqual(bare.checkURL.absoluteString, "http://localhost:8081/v2/check")

        let full = try XCTUnwrap(LanguageToolConfiguration(endpointString: "http://localhost:8081/v2/check", language: "auto", timeout: 2))
        XCTAssertEqual(full.checkURL.absoluteString, "http://localhost:8081/v2/check")

        let prefixed = try XCTUnwrap(LanguageToolConfiguration(endpointString: "http://localhost:8081/lt", language: "auto", timeout: 2))
        XCTAssertEqual(prefixed.checkURL.absoluteString, "http://localhost:8081/lt/v2/check")
    }

    // MARK: - Request Encoding

    /// URLComponents leaves "+" alone because it is legal in a query, but a form
    /// decoder reads it as a space. The server would then analyze text the user
    /// never typed while the offsets still lined up, so a suggestion could be
    /// applied to characters the server never saw.
    func testPlusSignSurvivesFormEncoding() throws {
        let body = try XCTUnwrap(LanguageToolClient.formEncodedBody([("text", "I use C++ at work")]))
        let encoded = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertFalse(encoded.contains("+"), "A literal + must not reach the server unescaped")
        XCTAssertTrue(encoded.contains("%2B%2B"))
    }

    func testReservedCharactersAreEscaped() throws {
        let body = try XCTUnwrap(LanguageToolClient.formEncodedBody([("text", "a&b=c%d e")]))
        let encoded = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertEqual(encoded, "text=a%26b%3Dc%25d%20e")
    }

    func testFieldsAreJoinedAndNamesEncoded() throws {
        let body = try XCTUnwrap(LanguageToolClient.formEncodedBody([("text", "hi"), ("language", "en-US")]))
        XCTAssertEqual(String(data: body, encoding: .utf8), "text=hi&language=en-US")
    }

    func testRequestTargetsCheckEndpointAsForm() throws {
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2)
        )
        let request = LanguageToolClient.makeRequest(text: "hi", configuration: configuration)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8081/v2/check")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
    }

    // MARK: - Offset Conversion

    func testUTF16OffsetsBecomeScalarOffsets() throws {
        let text = "😀 teh"
        let error = try XCTUnwrap(convert(match(offset: 3, length: 3), in: text).first)

        XCTAssertEqual(error.start, 2)
        XCTAssertEqual(error.end, 5)
        XCTAssertEqual(TextIndexConverter.extractErrorText(start: error.start, end: error.end, from: text), "teh")
    }

    func testOffsetsWithoutSurrogatePairsAreUnchanged() throws {
        let text = "I has a pen"
        let error = try XCTUnwrap(convert(match(offset: 2, length: 3), in: text).first)

        XCTAssertEqual(error.start, 2)
        XCTAssertEqual(error.end, 5)
    }

    func testMatchInsideSurrogatePairIsDropped() throws {
        XCTAssertTrue(try convert(match(offset: 1, length: 2), in: "😀 teh").isEmpty)
    }

    /// A range splitting a grapheme converts to a valid scalar offset but cannot
    /// be turned back into a String.Index, so it would show a suggestion that
    /// silently does nothing when clicked.
    func testMatchSplittingAGraphemeClusterIsDropped() throws {
        let text = "🇺🇸 teh"
        XCTAssertTrue(
            try convert(match(offset: 0, length: 2), in: text).isEmpty,
            "Half of a regional indicator pair is not an applicable range"
        )
    }

    func testMatchBeyondTextIsDropped() throws {
        XCTAssertTrue(try convert(match(offset: 10, length: 20), in: "short").isEmpty)
    }

    func testEmptyAndNegativeRangesAreDropped() throws {
        XCTAssertTrue(try convert(match(offset: 4, length: 0), in: "some text").isEmpty)
        XCTAssertTrue(try convert(match(offset: -1, length: 3), in: "some text").isEmpty)
    }

    /// A hostile or buggy server must not be able to trap the process on an
    /// integer overflow before the range is validated.
    func testOverflowingRangeIsDroppedWithoutTrapping() throws {
        let hostile = "{\"message\":\"m\",\"offset\":\(Int.max),\"length\":\(Int.max),\"replacements\":[],\"rule\":{\"id\":\"R\",\"category\":{\"id\":\"GRAMMAR\"}}}"
        XCTAssertTrue(try convert(hostile, in: "some text").isEmpty)
    }

    // MARK: - Decoding

    /// The header invites LanguageTool-compatible proxies, so one unexpected
    /// entry should not discard an otherwise usable reply.
    func testMalformedMatchDoesNotDiscardTheWholeResponse() throws {
        let mixed = "{\"unexpected\":true}," + match(offset: 2, length: 3)
        let converted = try convert(mixed, in: "I has a pen")

        XCTAssertEqual(converted.count, 1)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try LanguageToolClient.convert(responseData: Data("not json".utf8), in: "text"))
    }

    // MARK: - Rule Identity and Mapping

    func testRuleIdentifiersAreNamespaced() throws {
        let error = try XCTUnwrap(convert(match(offset: 2, length: 3, rule: "HE_VERB_AGR"), in: "I has a pen").first)
        XCTAssertEqual(error.lintId, "LanguageTool::HE_VERB_AGR")
    }

    /// Provenance reaches the UI through the lint ID namespace, so a result from
    /// the network is not presented as though the local engine produced it.
    func testExternalResultsAreLabelledAsLanguageTool() throws {
        let text = "I has a pen"
        let error = try XCTUnwrap(convert(match(offset: 2, length: 3), in: text).first)

        XCTAssertEqual(error.toUnifiedSuggestion(in: text).source, .languageTool)

        let harper = GrammarErrorModel(
            start: 2, end: 5, message: "m", severity: .error,
            category: "Grammar", lintId: "Grammar::subject_verb"
        )
        XCTAssertEqual(harper.toUnifiedSuggestion(in: text).source, .harper)
    }

    func testSuggestionsSurviveConversion() throws {
        let error = try XCTUnwrap(
            convert(match(offset: 2, length: 3, replacements: ["have", "had"]), in: "I has a pen").first
        )
        XCTAssertEqual(error.suggestions, ["have", "had"])
    }

    func testEveryMappedCategoryIsAKnownCategory() {
        let samples = [
            "TYPOS", "MISSPELLING", "COMPOUNDING", "GRAMMAR", "PUNCTUATION",
            "TYPOGRAPHY", "CASING", "CONFUSED_WORDS", "FALSE_FRIENDS",
            "COLLOCATIONS", "REDUNDANCY", "STYLE", "PLAIN_ENGLISH", "SEMANTICS",
            "IDIOMS", "REPETITIONS", "REGIONALISMS", "NONSTANDARD_PHRASES",
            "BARBARISM", "MISC", "SOMETHING_UNKNOWN", "typos",
        ]

        for sample in samples {
            let mapped = LanguageToolClient.category(forLanguageToolCategory: sample)
            XCTAssertTrue(
                UserPreferences.allCategories.contains(mapped),
                "\(sample) mapped to unknown category \(mapped)"
            )
        }
    }

    func testCategoryMappingHighlights() {
        XCTAssertEqual(LanguageToolClient.category(forLanguageToolCategory: "TYPOS"), "Spelling")
        XCTAssertEqual(LanguageToolClient.category(forLanguageToolCategory: "CONFUSED_WORDS"), "WordChoice")
        XCTAssertEqual(LanguageToolClient.category(forLanguageToolCategory: "CASING"), "Capitalization")
        XCTAssertEqual(LanguageToolClient.category(forLanguageToolCategory: "NOT_A_REAL_CATEGORY"), "Miscellaneous")
    }

    func testSeverityFollowsCategory() {
        XCTAssertEqual(LanguageToolClient.severity(forCategory: "TYPOS"), .error)
        XCTAssertEqual(LanguageToolClient.severity(forCategory: "STYLE"), .info)
        XCTAssertEqual(LanguageToolClient.severity(forCategory: "CASING"), .warning)
    }
}
