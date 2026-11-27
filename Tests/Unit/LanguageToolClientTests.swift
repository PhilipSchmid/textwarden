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

    // MARK: - Issue Type Fallback

    /// LanguageTool's category identifiers are open-ended; `issueType` is set
    /// per rule and classifies many matches that would otherwise land in
    /// Miscellaneous.
    func testIssueTypeClassifiesRulesWithAnUnrecognisedCategory() {
        XCTAssertEqual(
            LanguageToolClient.category(forCategory: "SOME_CUSTOM_PACK", issueType: "misspelling"),
            "Spelling"
        )
        XCTAssertEqual(
            LanguageToolClient.category(forCategory: "SOME_CUSTOM_PACK", issueType: "duplication"),
            "Repetition"
        )
        XCTAssertEqual(
            LanguageToolClient.category(forCategory: "SOME_CUSTOM_PACK", issueType: "non-conformance"),
            "Nonstandard"
        )
    }

    /// The documented category table is authoritative; issueType only fills the
    /// gap it leaves, so a known category must never be overridden.
    func testIssueTypeDoesNotOverrideAKnownCategory() {
        XCTAssertEqual(
            LanguageToolClient.category(forCategory: "REDUNDANCY", issueType: "misspelling"),
            "Redundancy"
        )
        XCTAssertEqual(
            LanguageToolClient.category(forCategory: "TYPOS", issueType: "style"),
            "Spelling"
        )
    }

    func testUnknownCategoryWithoutIssueTypeStaysMiscellaneous() {
        XCTAssertEqual(LanguageToolClient.category(forCategory: "WHATEVER", issueType: nil), "Miscellaneous")
        XCTAssertEqual(LanguageToolClient.category(forCategory: "WHATEVER", issueType: ""), "Miscellaneous")
    }

    func testEveryIssueTypeMappingIsAKnownCategory() {
        let samples = [
            "misspelling", "grammar", "terminology", "typographical", "whitespace",
            "formatting", "duplication", "style", "register", "locale-violation",
            "locale-specific-content", "non-conformance", "uncategorized",
            "MISSPELLING", "something-new",
        ]

        for sample in samples {
            let mapped = LanguageToolClient.category(forIssueType: sample)
            XCTAssertTrue(
                UserPreferences.allCategories.contains(mapped),
                "\(sample) mapped to unknown category \(mapped)"
            )
        }
    }

    func testIssueTypeSurvivesDecoding() throws {
        let payload = """
        {"message":"Problem","offset":0,"length":3,"replacements":[],\
        "rule":{"id":"CUSTOM_1","category":{"id":"CUSTOM_PACK"},"issueType":"duplication"}}
        """
        let errors = try convert(payload, in: "the the cat")
        XCTAssertEqual(errors.first?.category, "Repetition")
        XCTAssertEqual(errors.first?.severity, .info)
    }

    // MARK: - Timeout

    /// A fixed allowance is either too tight for a document or too loose for a
    /// sentence, so it grows with the text and then stops.
    func testTimeoutGrowsWithTheTextAndIsCapped() throws {
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(
                endpointString: "http://localhost:8081",
                language: "auto",
                timeout: LanguageToolConfiguration.defaultTimeout
            )
        )

        XCTAssertEqual(configuration.timeout(forCharacters: 0), LanguageToolConfiguration.defaultTimeout)
        XCTAssertEqual(
            configuration.timeout(forCharacters: 20000),
            LanguageToolConfiguration.defaultTimeout + 4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            configuration.timeout(forCharacters: 100_000_000),
            LanguageToolConfiguration.maximumTimeout
        )
    }

    func testRequestCarriesTheGrownTimeout() throws {
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(
                endpointString: "http://localhost:8081",
                language: "auto",
                timeout: LanguageToolConfiguration.defaultTimeout
            )
        )
        let request = LanguageToolClient.makeRequest(
            text: String(repeating: "a", count: 10000),
            configuration: configuration
        )

        XCTAssertEqual(request.timeoutInterval, LanguageToolConfiguration.defaultTimeout + 2, accuracy: 0.001)
    }

    /// The inactivity timeout restarts whenever a byte arrives, so the session
    /// needs a total deadline above it to catch a server that trickles.
    func testResourceCeilingSitsAboveTheGrownTimeout() {
        XCTAssertGreaterThan(
            LanguageToolConfiguration.resourceTimeout,
            LanguageToolConfiguration.maximumTimeout
        )
    }

    // MARK: - Character Limit

    func testCharacterLimitIsClampedIntoRange() throws {
        let tooSmall = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2, characterLimit: 1)
        )
        XCTAssertEqual(tooSmall.characterLimit, LanguageToolConfiguration.characterLimitRange.lowerBound)

        let tooLarge = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2, characterLimit: .max)
        )
        XCTAssertEqual(tooLarge.characterLimit, LanguageToolConfiguration.characterLimitRange.upperBound)

        let inRange = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2, characterLimit: 5000)
        )
        XCTAssertEqual(inRange.characterLimit, 5000)
    }

    /// The point of the limit is to avoid the round trip, not to discard the
    /// reply after paying for it.
    func testTextAboveTheLimitIsNeverSent() async throws {
        let client = StubbedClient.makeSucceeding()
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2, characterLimit: 1000)
        )

        do {
            _ = try await client.check(text: String(repeating: "a", count: 1001), configuration: configuration)
            XCTFail("Expected textTooLong")
        } catch let LanguageToolError.textTooLong(characters, limit) {
            XCTAssertEqual(characters, 1001)
            XCTAssertEqual(limit, 1000)
        }

        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }

    /// A success against one server must not clear a different server's
    /// cooldown. The user can change the address while a slow check is still
    /// running, and the old server answering says nothing about the new one.
    func testSuccessAgainstOneEndpointLeavesAnotherEndpointsCooldownIntact() async throws {
        let client = StubbedClient.make()
        let downEndpoint = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://127.0.0.2:8081", language: "auto", timeout: 2)
        )
        let liveEndpoint = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2)
        )

        StubURLProtocol.handler = { request in
            if request.url?.host == "127.0.0.2" {
                throw URLError(.cannotConnectToHost)
            }
            return (StubURLProtocol.okResponse(for: request.url?.absoluteString ?? ""), Data(#"{"matches":[]}"#.utf8))
        }

        do {
            _ = try await client.check(text: "She dont like it.", configuration: downEndpoint)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.transport {}

        // Succeeds, and must leave the other server's cooldown alone.
        _ = try await client.check(text: "She dont like it.", configuration: liveEndpoint)

        do {
            _ = try await client.check(text: "She dont like it.", configuration: downEndpoint)
            XCTFail("Expected the cooldown on the unreachable server to still apply")
        } catch LanguageToolError.cooldown {}
    }

    // MARK: - Response Bounds

    /// The request timeout bounds the transfer and the character limit bounds
    /// what is sent. Neither bounds what comes back, so a fast enormous reply
    /// would otherwise be decoded in full.
    func testAnOversizedReplyIsRejectedWithoutDecoding() async throws {
        let client = StubbedClient.make()
        StubURLProtocol.handler = { request in
            let padding = String(repeating: "x", count: LanguageToolConfiguration.maximumResponseBytes + 1)
            let body = "{\"matches\":[],\"padding\":\"\(padding)\"}"
            return (StubURLProtocol.okResponse(for: request.url?.absoluteString ?? ""), Data(body.utf8))
        }
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2)
        )

        do {
            _ = try await client.check(text: "She dont like it.", configuration: configuration)
            XCTFail("Expected responseTooLarge")
        } catch let LanguageToolError.responseTooLarge(bytes) {
            XCTAssertGreaterThan(bytes, LanguageToolConfiguration.maximumResponseBytes)
        }
    }

    /// Conversion runs per match and the merge runs on the main actor, so a
    /// reply with far more matches than anyone can see is capped first.
    func testMatchesBeyondTheCapAreNotConverted() throws {
        let overflow = LanguageToolConfiguration.maximumMatches + 50
        let text = String(repeating: "a b ", count: overflow)
        let matchesJSON = (0 ..< overflow).map { index in
            """
            {"message":"m","offset":\(index * 4),"length":1,"replacements":[],\
            "rule":{"id":"R","category":{"id":"GRAMMAR"},"issueType":"grammar"}}
            """
        }.joined(separator: ",")

        let body = "{\"matches\":[\(matchesJSON)]}"
        let converted = try LanguageToolClient.convert(responseData: Data(body.utf8), in: text)

        XCTAssertLessThanOrEqual(converted.count, LanguageToolConfiguration.maximumMatches)
    }

    /// Each endpoint keeps its own cooldown, so a failure against one server
    /// cannot stand in for, or erase, another server's.
    func testEachEndpointKeepsItsOwnCooldown() async throws {
        let client = StubbedClient.makeFailing()
        let first = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://127.0.0.2:8081", language: "auto", timeout: 2)
        )
        let second = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://127.0.0.3:8081", language: "auto", timeout: 2)
        )

        do {
            _ = try await client.check(text: "She dont like it.", configuration: first)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.transport {}

        // The second endpoint has no history, so it must still be attempted
        // rather than inherit the first endpoint's cooldown.
        do {
            _ = try await client.check(text: "She dont like it.", configuration: second)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.transport {}

        XCTAssertEqual(StubURLProtocol.requestCount, 2, "Both endpoints were tried")
    }

    // MARK: - Redirects

    /// The loopback check runs once, against the configured address. If a
    /// redirect were followed, a server could name any host and URLSession
    /// would resend the document body there, so the promise that the text
    /// never leaves the Mac would hold only for cooperating servers.
    func testRedirectIsNotFollowedAndTheBodyNeverReachesTheTarget() async throws {
        let client = StubbedClient.makeSucceeding()
        StubURLProtocol.redirectTo = "https://example.com/v2/check"
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2)
        )

        do {
            _ = try await client.check(text: "She dont like it.", configuration: configuration)
            XCTFail("Expected the redirect to be refused")
        } catch LanguageToolError.redirectRefused {}

        XCTAssertEqual(StubURLProtocol.requestCount, 1, "The redirect target must never be requested")
        XCTAssertFalse(
            StubURLProtocol.attemptedURLs.contains { $0.contains("example.com") },
            "Document text was sent off the loopback: \(StubURLProtocol.attemptedURLs)"
        )
    }

    // MARK: - Failure Cooldown

    func testFailureStartsACooldownThatSuppressesTheNextCheck() async throws {
        let client = StubbedClient.makeFailing()
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2)
        )

        do {
            _ = try await client.check(text: "She dont like it.", configuration: configuration)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.transport {}

        do {
            _ = try await client.check(text: "She dont like it.", configuration: configuration)
            XCTFail("Expected cooldown")
        } catch LanguageToolError.cooldown {}

        // One attempt, not two: the second never reached the network.
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    /// Test Connection is how a user confirms they have just fixed the server,
    /// so it must not replay the failure from before they fixed it.
    func testCooldownIsBypassedForADeliberateCheck() async throws {
        let client = StubbedClient.makeFailing()
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2)
        )

        do {
            _ = try await client.check(text: "She dont like it.", configuration: configuration)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.transport {}

        do {
            _ = try await client.check(text: "She dont like it.", configuration: configuration, respectCooldown: false)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.cooldown {
            XCTFail("Deliberate check must not be suppressed by the cooldown")
        } catch LanguageToolError.transport {}

        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    /// Pointing TextWarden at a different server is a deliberate act and has to
    /// take effect at once rather than after the wait.
    func testCooldownDoesNotCarryToADifferentEndpoint() async throws {
        let client = StubbedClient.makeFailing()
        let first = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2)
        )
        let second = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8082", language: "auto", timeout: 2)
        )

        do {
            _ = try await client.check(text: "She dont like it.", configuration: first)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.transport {}

        do {
            _ = try await client.check(text: "She dont like it.", configuration: second)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.cooldown {
            XCTFail("A different endpoint must be tried, not suppressed")
        } catch LanguageToolError.transport {}

        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testSuccessClearsAnEarlierCooldown() async throws {
        let client = StubbedClient.makeFailing()
        let configuration = try XCTUnwrap(
            LanguageToolConfiguration(endpointString: "http://localhost:8081", language: "auto", timeout: 2)
        )

        do {
            _ = try await client.check(text: "She dont like it.", configuration: configuration)
            XCTFail("Expected transport failure")
        } catch LanguageToolError.transport {}

        StubURLProtocol.handler = { _ in
            (StubURLProtocol.okResponse(for: "http://localhost:8081"), Data(#"{"matches":[]}"#.utf8))
        }

        let results = try await client.check(
            text: "She dont like it.",
            configuration: configuration,
            respectCooldown: false
        )
        XCTAssertTrue(results.isEmpty)

        // Cleared by the success, so an ordinary check goes through again.
        let afterRecovery = try await client.check(text: "She dont like it.", configuration: configuration)
        XCTAssertTrue(afterRecovery.isEmpty)
        XCTAssertEqual(StubURLProtocol.requestCount, 3)
    }
}

// MARK: - Network Stub

/// Builds `LanguageToolClient` instances whose requests are served by
/// `StubURLProtocol` rather than a real server.
private enum StubbedClient {
    static func make() -> LanguageToolClient {
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return LanguageToolClient(session: URLSession(configuration: configuration))
    }

    static func makeFailing() -> LanguageToolClient {
        let client = make()
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        return client
    }

    static func makeSucceeding() -> LanguageToolClient {
        let client = make()
        StubURLProtocol.handler = { request in
            (StubURLProtocol.okResponse(for: request.url?.absoluteString ?? ""), Data(#"{"matches":[]}"#.utf8))
        }
        return client
    }
}

private class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestCount = 0
    /// Every URL the session actually attempted, in order.
    nonisolated(unsafe) static var attemptedURLs: [String] = []
    /// When set, the first attempt answers with a redirect to this URL.
    nonisolated(unsafe) static var redirectTo: String?

    static func reset() {
        handler = nil
        requestCount = 0
        attemptedURLs = []
        redirectTo = nil
    }

    static func redirectResponse(from urlString: String, to target: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: urlString) ?? URL(fileURLWithPath: "/"),
            statusCode: 307,
            httpVersion: nil,
            headerFields: ["Location": target]
        ) ?? HTTPURLResponse()
    }

    static func okResponse(for urlString: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: urlString) ?? URL(fileURLWithPath: "/"),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ) ?? HTTPURLResponse()
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        Self.attemptedURLs.append(request.url?.absoluteString ?? "")

        // Offer the session a redirect the way a real server would, so the
        // delegate that refuses it is exercised rather than bypassed.
        if let target = Self.redirectTo, let targetURL = URL(string: target) {
            Self.redirectTo = nil
            let response = Self.redirectResponse(from: request.url?.absoluteString ?? "", to: target)
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: targetURL), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
