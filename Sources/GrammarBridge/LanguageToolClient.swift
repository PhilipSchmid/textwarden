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

    /// Ceiling on how long a response may take before the result is dropped.
    let timeout: TimeInterval

    static let defaultEndpointString = "http://localhost:8081"
    static let defaultLanguage = "auto"
    static let defaultTimeout: TimeInterval = 2.0

    /// Build a configuration, rejecting anything that is not a loopback URL.
    ///
    /// Restricting to loopback is what keeps the product's privacy promise
    /// intact: traffic to 127.0.0.0/8, ::1, or localhost never leaves the Mac.
    /// It also sidesteps App Transport Security, which exempts loopback but
    /// would block cleartext to a LAN or remote host.
    init?(endpointString: String, language: String, timeout: TimeInterval) {
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

// MARK: - Client

/// Sends text to a LanguageTool-compatible server and converts the reply into
/// the same `GrammarErrorModel` values the Rust engine produces.
final class LanguageToolClient: Sendable {
    /// Namespace for rule identifiers so dismissals cannot collide with Harper's.
    static let lintIdPrefix = "LanguageTool"

    /// Shared instance, so the connection pool is reused across analyses.
    static let shared = LanguageToolClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Check `text` and return errors in TextWarden's own model.
    func check(text: String, configuration: LanguageToolConfiguration) async throws -> [GrammarErrorModel] {
        guard !text.isEmpty else { return [] }

        let request = Self.makeRequest(text: text, configuration: configuration)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LanguageToolError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw LanguageToolError.badStatus(http.statusCode)
        }

        return try Self.convert(responseData: data, in: text)
    }

    // MARK: - Request

    static func makeRequest(text: String, configuration: LanguageToolConfiguration) -> URLRequest {
        var request = URLRequest(url: configuration.checkURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
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
        return convert(matches: decoded.matches, in: text)
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

            return GrammarErrorModel(
                start: start,
                end: end,
                message: match.message,
                severity: severity(forCategory: match.rule.category.id),
                category: category(forLanguageToolCategory: match.rule.category.id),
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

    /// LanguageTool has no severity field, so derive one from the category.
    static func severity(forCategory id: String) -> GrammarErrorSeverity {
        switch category(forLanguageToolCategory: id) {
        case "Spelling", "Grammar": .error
        case "Style", "Redundancy", "Repetition", "Regionalism": .info
        default: .warning
        }
    }
}
