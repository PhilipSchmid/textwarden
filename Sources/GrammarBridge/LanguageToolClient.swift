//
//  LanguageToolClient.swift
//  TextWarden
//
//  Optional client for a LanguageTool-compatible HTTP endpoint on this Mac.
//
//  TextWarden never bundles, downloads, or launches LanguageTool. This talks to
//  a server the user already runs, it is disabled by default, and the endpoint
//  is restricted to loopback so the text being checked never leaves the device.
//  Anything speaking LanguageTool's /v2/check contract works, including a local
//  proxy that merges in further sources before replying.
//

import Foundation

/// Connection settings for an optional LanguageTool-compatible endpoint.
struct LanguageToolConfiguration: Sendable, Equatable {
    /// Base URL of the server. Always loopback; see `isLoopback(_:)`.
    let endpoint: URL

    /// Language code sent with each request. `auto` defers to the server.
    let language: String

    /// Base allowance for a response before the request is abandoned.
    ///
    /// This is the floor, not the whole story: the allowance grows with the
    /// text, because a chapter legitimately takes a server longer than a
    /// sentence. See `timeout(forCharacters:)`.
    let timeout: TimeInterval

    /// Longest text, in characters, that is worth sending.
    ///
    /// Harper reads the whole document in process; this source re-sends it over
    /// HTTP after every pause in typing, so the cost grows with the document
    /// while the benefit does not. Above the limit the request is skipped and
    /// Harper's results stand on their own.
    let characterLimit: Int

    /// Largest reply worth decoding.
    ///
    /// The request timeout bounds how long a transfer may take and the
    /// character limit bounds what is sent, but neither bounds what comes
    /// back. A server answering quickly with an enormous body would otherwise
    /// be decoded in full before anything could reject it.
    static let maximumResponseBytes = 4 * 1024 * 1024

    /// Most matches worth converting from one reply.
    ///
    /// The overlay hides underlines past `maxErrorsForUnderlines`, two orders
    /// of magnitude below this, so nothing a user can see is lost. It caps the
    /// per-match conversion and the merge, both of which run on the main actor.
    static let maximumMatches = 2000

    static let defaultEndpointString = "http://localhost:8081"
    static let defaultLanguage = "auto"
    /// Allowance for a short passage. A local server answers a sentence in
    /// tens of milliseconds, so anything near this already means trouble.
    static let defaultTimeout: TimeInterval = 4.0

    /// Characters of text that buy one further second of patience.
    static let charactersPerAdditionalSecond = 5000.0

    /// Ceiling on the grown allowance, so a pathological server cannot hold a
    /// request for as long as the character limit would otherwise permit.
    static let maximumTimeout: TimeInterval = 15.0

    /// Hard ceiling on a single request, start to finish.
    ///
    /// `URLRequest.timeoutInterval` is an inactivity timeout: it restarts every
    /// time a byte arrives, so a server that answers slowly enough can hold a
    /// request open indefinitely without ever tripping it. This is the deadline
    /// that actually bounds one exchange, and it sits above `maximumTimeout`
    /// so that it only catches the trickling case the other cannot.
    static let resourceTimeout: TimeInterval = 20.0

    /// LanguageTool's own hosted API refuses longer texts, and a self-hosted
    /// server slows noticeably well before this, so it is a sane starting point
    /// rather than a hard constraint.
    static let defaultCharacterLimit = 20000

    /// Bounds for a user-supplied limit. Below the floor the source would never
    /// fire on real writing; above the ceiling the request costs more than the
    /// results are worth.
    static let characterLimitRange = 1000 ... 1_000_000

    /// Build a configuration, rejecting anything that is not a loopback URL.
    ///
    /// Restricting to loopback is what keeps the product's privacy promise
    /// intact: traffic to 127.0.0.0/8, ::1, or localhost never leaves the Mac.
    /// It also sidesteps App Transport Security, which exempts loopback but
    /// would block cleartext to a LAN or remote host.
    init?(
        endpointString: String,
        language: String,
        timeout: TimeInterval,
        characterLimit: Int = defaultCharacterLimit
    ) {
        guard let endpoint = URL(string: endpointString),
              let scheme = endpoint.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = endpoint.host,
              Self.isLoopback(host)
        else {
            return nil
        }
        self.endpoint = endpoint
        self.language = language.isEmpty ? Self.defaultLanguage : language
        self.timeout = timeout
        // Clamped rather than rejected: the limit arrives from a text field the
        // user is still typing in, and a half-entered number should not switch
        // the whole source off.
        self.characterLimit = min(max(characterLimit, Self.characterLimitRange.lowerBound), Self.characterLimitRange.upperBound)
    }

    /// Loopback by literal form only. A name that merely *resolves* to loopback
    /// is not accepted, because that resolution can change between checks.
    static func isLoopback(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        // RFC 6761 reserves localhost and anything under it for the loopback.
        if normalized == "localhost" || normalized.hasSuffix(".localhost") {
            return true
        }

        // IPv6 loopback, with or without a zone identifier.
        if normalized == "::1" || normalized.hasPrefix("::1%") {
            return true
        }

        // The whole 127.0.0.0/8 block, not just 127.0.0.1.
        let octets = normalized.split(separator: ".", omittingEmptySubsequences: false)
        if octets.count == 4, octets[0] == "127" {
            return octets.allSatisfy { UInt8($0) != nil }
        }

        return false
    }

    /// Allowance for a request carrying `characters` of text.
    ///
    /// A fixed timeout has to be either too tight for a long document or too
    /// loose for a sentence. This grows with the text and stops at
    /// `maximumTimeout`.
    func timeout(forCharacters characters: Int) -> TimeInterval {
        let grown = timeout + Double(characters) / Self.charactersPerAdditionalSecond
        return min(grown, Self.maximumTimeout)
    }

    /// The URL to POST to, tolerating an endpoint that already names the path.
    ///
    /// LanguageTool's own documentation shows the full `/v2/check` URL, so a
    /// user pasting it must not end up requesting `/v2/check/v2/check`.
    var checkURL: URL {
        var base = endpoint
        base = URL(string: base.absoluteString.split(separator: "?").first.map(String.init) ?? base.absoluteString) ?? base
        let path = base.path.lowercased()
        if path.hasSuffix("/v2/check") {
            return base
        }
        return base.appendingPathComponent("v2/check")
    }
}

/// Failure modes for an external check. All of them are non-fatal: the caller
/// keeps the results it already has.
enum LanguageToolError: Error {
    case transport(Error)
    case badStatus(Int)
    case decoding(Error)
    /// Text longer than the configured limit; nothing was sent.
    case textTooLong(characters: Int, limit: Int)
    /// A recent failure against this endpoint is still being waited out.
    case cooldown
    /// Superseded by a newer analysis before the reply arrived.
    case cancelled
    /// Reply larger than `LanguageToolConfiguration.maximumResponseBytes`.
    case responseTooLarge(bytes: Int)
    /// The server answered with a redirect, which is never followed.
    case redirectRefused
}

// MARK: - Wire Format

/// One match from `/v2/check`.
struct LanguageToolMatch: Decodable {
    struct Replacement: Decodable {
        let value: String
    }

    struct Rule: Decodable {
        struct Category: Decodable {
            let id: String
        }

        let id: String
        let category: Category
        /// Internationalization Tag Set classification, set per rule. Optional
        /// because custom and older rules omit it.
        let issueType: String?
    }

    let message: String
    /// Offset in UTF-16 code units, because the server is Java.
    let offset: Int
    /// Length in UTF-16 code units.
    let length: Int
    let replacements: [Replacement]
    let rule: Rule
}

/// Response envelope. A single unexpected match is skipped rather than failing
/// the whole reply, since any LanguageTool-compatible proxy may add fields.
struct LanguageToolResponse: Decodable {
    let matches: [LanguageToolMatch]

    private enum CodingKeys: String, CodingKey {
        case matches
    }

    private struct Skippable: Decodable {
        let match: LanguageToolMatch?

        init(from decoder: Decoder) throws {
            match = try? LanguageToolMatch(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let skippable = try container.decode([Skippable].self, forKey: .matches)
        matches = skippable.compactMap(\.match)
    }
}

// MARK: - Failure Cooldown

/// Remembers a recent failure so a server that is not running costs one timeout
/// rather than one per pause in typing.
///
/// Keyed by endpoint, because pointing TextWarden at a different server is a
/// deliberate act that must take effect at once rather than after the wait.
/// Tracks, per endpoint, how long to leave a failing server alone.
///
/// Keyed by endpoint rather than holding a single slot: requests against the
/// old and new addresses overlap whenever the user edits the setting while a
/// check is running, and whichever finishes last must not speak for the other.
private actor FailureCooldown {
    private var expiries: [URL: Date] = [:]

    func isActive(for endpoint: URL, now: Date = Date()) -> Bool {
        guard let expiry = expiries[endpoint] else { return false }
        guard now < expiry else {
            expiries[endpoint] = nil
            return false
        }
        return true
    }

    func recordFailure(for endpoint: URL, duration: TimeInterval, now: Date = Date()) {
        // Expired entries are dropped on the way past, so editing the address
        // repeatedly cannot accumulate them.
        expiries = expiries.filter { $0.value > now }
        expiries[endpoint] = now.addingTimeInterval(duration)
    }

    /// Clears the cooldown for one endpoint. A check against a server that
    /// works says nothing about a different server that is still down.
    func clear(for endpoint: URL) {
        expiries[endpoint] = nil
    }
}

// MARK: - Client

/// Sends text to a LanguageTool-compatible server and converts the reply into
/// the same `GrammarErrorModel` values the Rust engine produces.
final class LanguageToolClient: Sendable {
    /// Namespace for rule identifiers so dismissals cannot collide with Harper's.
    static let lintIdPrefix = "LanguageTool"

    /// Shared instance, so the connection pool is reused across analyses.
    static let shared = LanguageToolClient()

    private let session: URLSession
    private let cooldown = FailureCooldown()

    /// Refuses every redirect.
    ///
    /// The loopback guarantee is enforced once, against the address the user
    /// configured. URLSession follows redirects by default, so a server
    /// answering 3xx could otherwise have the document body resent to any host
    /// it named, defeating that check entirely. Passing nil to the completion
    /// handler ends the task with the redirect response rather than following
    /// it. Stateless, so sharing one instance across tasks is safe.
    private final class RedirectRefusing: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest _: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private static let redirectRefusing = RedirectRefusing()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForResource = LanguageToolConfiguration.resourceTimeout
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            // No proxy, ever. A session inherits the system proxy settings, so
            // a configured HTTP proxy without a bypass entry for the loopback
            // would receive the cleartext POST before the request ever reached
            // the local server. The loopback check would then be guarding an
            // address the body never travelled to.
            configuration.connectionProxyDictionary = [:]
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Check `text` and return errors in TextWarden's own model.
    ///
    /// - Parameter respectCooldown: Pass `false` for a deliberate user action,
    ///   such as Test Connection, which must reach a server the user has just
    ///   fixed rather than report the failure that is still being waited out.
    func check(
        text: String,
        configuration: LanguageToolConfiguration,
        respectCooldown: Bool = true
    ) async throws -> [GrammarErrorModel] {
        guard !text.isEmpty else { return [] }

        // Counted before anything is encoded or sent, so an oversized document
        // costs one length check rather than a round trip.
        let characters = text.count
        guard characters <= configuration.characterLimit else {
            throw LanguageToolError.textTooLong(characters: characters, limit: configuration.characterLimit)
        }

        let endpoint = configuration.checkURL
        if respectCooldown, await cooldown.isActive(for: endpoint) {
            throw LanguageToolError.cooldown
        }

        let request = Self.makeRequest(text: text, configuration: configuration)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: Self.redirectRefusing)
        } catch {
            // Being superseded says nothing about the server, so it must not
            // start a cooldown that would suppress the next real check.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw LanguageToolError.cancelled
            }
            await cooldown.recordFailure(for: endpoint, duration: TimingConstants.externalGrammarSourceFailureCooldown)
            throw LanguageToolError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            await cooldown.recordFailure(for: endpoint, duration: TimingConstants.externalGrammarSourceFailureCooldown)
            // A 3xx reached here only because the redirect was refused, so say
            // that rather than reporting a status the user cannot act on.
            if (300 ..< 400).contains(http.statusCode) {
                throw LanguageToolError.redirectRefused
            }
            throw LanguageToolError.badStatus(http.statusCode)
        }

        guard data.count <= LanguageToolConfiguration.maximumResponseBytes else {
            await cooldown.recordFailure(for: endpoint, duration: TimingConstants.externalGrammarSourceFailureCooldown)
            throw LanguageToolError.responseTooLarge(bytes: data.count)
        }

        do {
            let errors = try Self.convert(responseData: data, in: text)
            await cooldown.clear(for: endpoint)
            return errors
        } catch {
            // A reply TextWarden cannot read means this endpoint is not
            // speaking the expected contract, which retrying will not change.
            await cooldown.recordFailure(for: endpoint, duration: TimingConstants.externalGrammarSourceFailureCooldown)
            throw error
        }
    }

    // MARK: - Request

    static func makeRequest(text: String, configuration: LanguageToolConfiguration) -> URLRequest {
        var request = URLRequest(url: configuration.checkURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout(forCharacters: text.count)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncodedBody([("text", text), ("language", configuration.language)])
        return request
    }

    /// Percent-encode a form body.
    ///
    /// `URLComponents` leaves `+` alone because it is legal in a query, but a
    /// form decoder reads `+` as a space. Encoding everything outside the RFC
    /// 3986 unreserved set keeps the server's view of the text identical to the
    /// user's; otherwise "C++" is analyzed as "C  " and the resulting match is
    /// mapped back onto text the server never saw.
    static func formEncodedBody(_ fields: [(String, String)]) -> Data? {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = fields.map { name, value in
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: unreserved) ?? name
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
            return "\(encodedName)=\(encodedValue)"
        }
        return encoded.joined(separator: "&").data(using: .utf8)
    }

    // MARK: - Conversion

    /// Decode a `/v2/check` reply and convert it to TextWarden's model.
    static func convert(responseData: Data, in text: String) throws -> [GrammarErrorModel] {
        let decoded: LanguageToolResponse
        do {
            decoded = try JSONDecoder().decode(LanguageToolResponse.self, from: responseData)
        } catch {
            throw LanguageToolError.decoding(error)
        }
        // Capped before conversion, which is per match and runs on the main
        // actor by the time the results are merged.
        return convert(matches: Array(decoded.matches.prefix(LanguageToolConfiguration.maximumMatches)), in: text)
    }

    /// Convert matches, dropping any whose range cannot be mapped safely onto
    /// the analyzed text.
    static func convert(matches: [LanguageToolMatch], in text: String) -> [GrammarErrorModel] {
        guard !matches.isEmpty else { return [] }
        let scalarByUTF16 = scalarOffsets(in: text)
        // Downstream positioning and replacement need Character boundaries, not
        // merely scalar ones, so a range splitting a grapheme is discarded here
        // rather than producing a suggestion that silently cannot be applied.
        let graphemeBoundaries = TextIndexConverter.stringIndicesByScalarOffset(in: text)

        return matches.compactMap { match in
            guard match.offset >= 0, match.length > 0 else { return nil }
            // Server-supplied integers: a sum that overflows would trap.
            let (utf16End, overflowed) = match.offset.addingReportingOverflow(match.length)
            guard !overflowed,
                  let start = scalarByUTF16[match.offset],
                  let end = scalarByUTF16[utf16End],
                  start < end,
                  graphemeBoundaries[start] != nil,
                  graphemeBoundaries[end] != nil
            else {
                return nil
            }

            let category = category(forCategory: match.rule.category.id, issueType: match.rule.issueType)

            return GrammarErrorModel(
                start: start,
                end: end,
                message: match.message,
                severity: severity(forTextWardenCategory: category),
                category: category,
                lintId: "\(lintIdPrefix)::\(match.rule.id)",
                suggestions: match.replacements.map(\.value)
            )
        }
    }

    /// Map every UTF-16 boundary in `text` to its Unicode scalar offset in one
    /// pass, so a response with many matches stays linear in the text length.
    private static func scalarOffsets(in text: String) -> [Int: Int] {
        var map = [0: 0]
        var utf16Offset = 0
        var scalarOffset = 0
        for scalar in text.unicodeScalars {
            utf16Offset += UTF16.width(scalar)
            scalarOffset += 1
            map[utf16Offset] = scalarOffset
        }
        return map
    }

    /// Fold LanguageTool's categories into the names TextWarden already shows,
    /// so existing per-category preferences keep working without migration.
    static func category(forLanguageToolCategory id: String) -> String {
        switch id.uppercased() {
        case "TYPOS", "MISSPELLING", "COMPOUNDING": "Spelling"
        case "GRAMMAR": "Grammar"
        case "PUNCTUATION": "Punctuation"
        case "TYPOGRAPHY": "Formatting"
        case "CASING": "Capitalization"
        case "CONFUSED_WORDS", "FALSE_FRIENDS", "COLLOCATIONS": "WordChoice"
        case "REDUNDANCY": "Redundancy"
        case "STYLE", "PLAIN_ENGLISH", "CREATIVE_WRITING": "Style"
        case "SEMANTICS", "IDIOMS": "Usage"
        case "REPETITIONS", "REPETITIONS_STYLE": "Repetition"
        case "REGIONALISMS": "Regionalism"
        case "NONSTANDARD_PHRASES", "BARBARISM": "Nonstandard"
        default: "Miscellaneous"
        }
    }

    /// Second signal for a rule whose category TextWarden does not recognise.
    ///
    /// `issueType` comes from the Internationalization Tag Set and is set per
    /// rule, so it frequently classifies a match that arrived under a custom or
    /// server-specific category grouping. Consulted only after the category map
    /// has declined, so the documented category behaviour never changes.
    static func category(forIssueType issueType: String) -> String {
        switch issueType.lowercased() {
        case "misspelling": "Spelling"
        case "grammar": "Grammar"
        case "terminology": "WordChoice"
        case "typographical", "whitespace", "formatting": "Formatting"
        case "duplication": "Repetition"
        case "style", "register": "Style"
        case "locale-violation", "locale-specific-content": "Regionalism"
        case "non-conformance": "Nonstandard"
        default: "Miscellaneous"
        }
    }

    /// Resolve one rule to a TextWarden category, category identifier first.
    static func category(forCategory id: String, issueType: String?) -> String {
        let mapped = category(forLanguageToolCategory: id)
        guard mapped == "Miscellaneous", let issueType, !issueType.isEmpty else { return mapped }
        return category(forIssueType: issueType)
    }

    /// LanguageTool has no severity field, so derive one from the category the
    /// match was folded into.
    static func severity(forTextWardenCategory category: String) -> GrammarErrorSeverity {
        switch category {
        case "Spelling", "Grammar": .error
        case "Style", "Redundancy", "Repetition", "Regionalism": .info
        default: .warning
        }
    }

    /// Severity for a LanguageTool category identifier.
    static func severity(forCategory id: String) -> GrammarErrorSeverity {
        severity(forTextWardenCategory: category(forLanguageToolCategory: id))
    }
}
