//
//  ContentParserFactory.swift
//  TextWarden
//
//  Factory for creating app-specific content parsers
//  Extensible architecture for adding new app support
//

import Foundation

/// Factory for creating app-specific content parsers
class ContentParserFactory {
    /// Shared singleton instance
    static let shared = ContentParserFactory()

    /// Registry of parsers by bundle identifier
    private var parsers: [String: ContentParser] = [:]

    private init() {
        // Register known parsers
        registerParser(SlackContentParser())

        // Register terminal parsers for all supported terminal apps
        for (bundleID, _) in TerminalContentParser.supportedTerminals {
            registerParser(TerminalContentParser(bundleIdentifier: bundleID))
        }

        // Register browser parsers for all supported browsers
        for bundleID in BrowserContentParser.supportedBrowsers {
            registerParser(BrowserContentParser(bundleIdentifier: bundleID))
        }

        // Future parsers to add:
        // registerParser(DiscordContentParser())
        // registerParser(VSCodeContentParser())
        // registerParser(WordContentParser())
        // registerParser(MailContentParser())
        // registerParser(OutlookContentParser())
        // registerParser(NotionContentParser())
        // registerParser(ObsidianContentParser())
        // registerParser(PagesContentParser())
    }

    /// Register a content parser
    /// - Parameter parser: The parser to register
    func registerParser(_ parser: ContentParser) {
        parsers[parser.bundleIdentifier] = parser
        Logger.info("ContentParserFactory: Registered parser '\(parser.parserName)' for \(parser.bundleIdentifier)")
    }

    /// Get parser for a bundle identifier
    /// - Parameter bundleID: Bundle identifier of the application
    /// - Returns: App-specific parser or generic fallback
    func parser(for bundleID: String) -> ContentParser {
        if let parser = parsers[bundleID] {
            Logger.debug("ContentParserFactory: Using \(parser.parserName) parser for \(bundleID)")
            return parser
        }

        Logger.debug("ContentParserFactory: Using generic parser for \(bundleID)")
        return GenericContentParser(bundleIdentifier: bundleID)
    }

    /// Get list of supported bundle identifiers
    var supportedBundleIdentifiers: [String] {
        return Array(parsers.keys)
    }

    /// Check if a specific parser is registered for a bundle ID
    func hasSpecificParser(for bundleID: String) -> Bool {
        return parsers[bundleID] != nil
    }
}
