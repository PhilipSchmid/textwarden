//
//  ContentParserFactory.swift
//  TextWarden
//
//  Factory for creating app-specific content parsers.
//  Uses AppRegistry as the source of truth for parser selection.
//

import Foundation

/// Factory for creating app-specific content parsers
final class ContentParserFactory {

    /// Shared singleton instance
    static let shared = ContentParserFactory()

    /// Parser instances by type
    private let parsersByType: [ParserType: ContentParser]

    /// Cached parsers by bundle ID for quick lookup
    private var parserCache: [String: ContentParser] = [:]

    private init() {
        // Initialize one instance of each parser type
        parsersByType = [
            .generic: GenericContentParser(bundleIdentifier: "default"),
            .slack: SlackContentParser(),
            .browser: BrowserContentParser(bundleIdentifier: "browser"),
            .notion: NotionContentParser(bundleIdentifier: "notion"),
            .terminal: TerminalContentParser(bundleIdentifier: "terminal"),
            .teams: TeamsContentParser(),
            .mail: MailContentParser(),
            .word: WordContentParser(),
            .powerpoint: PowerPointContentParser()
        ]

        Logger.info("ContentParserFactory: Initialized with \(parsersByType.count) parser types", category: Logger.analysis)
    }

    /// Get parser for a bundle identifier
    /// Uses AppRegistry to determine the correct parser type
    func parser(for bundleID: String) -> ContentParser {
        // Check cache first
        if let cached = parserCache[bundleID] {
            // For generic parser, update the current bundle ID for config lookups
            if let genericParser = cached as? GenericContentParser {
                genericParser.setCurrentBundleID(bundleID)
            }
            return cached
        }

        // Get configuration from registry
        let config = AppRegistry.shared.configuration(for: bundleID)

        // Get parser for the configured type
        let parser: ContentParser
        if let typeParser = parsersByType[config.parserType] {
            parser = typeParser
        } else {
            // Generic parser is always present by construction
            guard let genericParser = parsersByType[.generic] else {
                fatalError("ContentParserFactory: Generic parser missing - this should never happen")
            }
            parser = genericParser
        }

        // For generic parser, set the current bundle ID for config lookups
        if let genericParser = parser as? GenericContentParser {
            genericParser.setCurrentBundleID(bundleID)
        }

        // Cache for next lookup
        parserCache[bundleID] = parser

        Logger.debug("ContentParserFactory: Using \(config.parserType) parser for \(bundleID)", category: Logger.analysis)
        return parser
    }

    /// Get configuration for a bundle identifier
    /// Convenience method to access AppRegistry
    func configuration(for bundleID: String) -> AppConfiguration {
        return AppRegistry.shared.configuration(for: bundleID)
    }

    /// Check if a specific (non-generic) parser is configured for a bundle ID
    func hasSpecificParser(for bundleID: String) -> Bool {
        return AppRegistry.shared.hasConfiguration(for: bundleID)
    }

    /// Get list of all bundle IDs with specific configurations
    var supportedBundleIdentifiers: [String] {
        return AppRegistry.shared.allConfigurations.flatMap { Array($0.bundleIDs) }
    }

    /// Clear parser cache (useful for testing)
    func clearCache() {
        parserCache.removeAll()
    }
}
