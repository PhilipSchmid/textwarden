//
//  DismissalTracker.swift
//  TextWarden
//
//  Tracks dismissed grammar rule patterns (T101, T108)
//

import Foundation

/// Tracks dismissed grammar rules with JSON persistence
class DismissalTracker {
    static let shared = DismissalTracker()

    private let fileURL: URL
    private(set) var patterns: [String: DismissalPattern] = [:]

    private init() {
        // Setup file URL in Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let textWardenDir = appSupport.appendingPathComponent("TextWarden")

        try? FileManager.default.createDirectory(
            at: textWardenDir,
            withIntermediateDirectories: true
        )

        fileURL = textWardenDir.appendingPathComponent("dismissal-patterns.json")

        // Load existing patterns
        load()
    }

    // MARK: - Public Methods

    /// Record a dismissal for a rule
    func recordDismissal(for ruleId: String, permanent: Bool = false) {
        if var pattern = patterns[ruleId] {
            pattern.dismissCount += 1
            pattern.lastDismissed = Date()
            if permanent {
                pattern.isPermanentlyIgnored = true
            }
            patterns[ruleId] = pattern
        } else {
            patterns[ruleId] = DismissalPattern(
                ruleId: ruleId,
                dismissCount: 1,
                lastDismissed: Date(),
                isPermanentlyIgnored: permanent
            )
        }

        try? save()
    }

    /// Check if a rule is permanently ignored
    func isPermanentlyIgnored(_ ruleId: String) -> Bool {
        return patterns[ruleId]?.isPermanentlyIgnored ?? false
    }

    /// Re-enable a previously ignored rule
    func reEnableRule(_ ruleId: String) {
        if var pattern = patterns[ruleId] {
            pattern.isPermanentlyIgnored = false
            patterns[ruleId] = pattern
            try? save()
        }
    }

    /// Get all permanently ignored rules
    func getPermanentlyIgnoredRules() -> [String] {
        return patterns.values
            .filter { $0.isPermanentlyIgnored }
            .map { $0.ruleId }
    }

    /// Clear all dismissal patterns
    func clearAll() {
        patterns.removeAll()
        try? save()
    }

    // MARK: - Persistence (T108)

    /// Save patterns to JSON file
    private func save() throws {
        let file = DismissalPatternsFile(
            version: 1,
            patterns: patterns
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)

        Logger.debug("DismissalTracker: Saved \(patterns.count) patterns", category: Logger.general)
    }

    /// Load patterns from JSON file
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Logger.debug("DismissalTracker: No existing file, starting fresh", category: Logger.general)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let file = try decoder.decode(DismissalPatternsFile.self, from: data)

            // Validate version
            guard file.version == 1 else {
                Logger.warning("DismissalTracker: Unsupported version \(file.version)", category: Logger.general)
                return
            }

            patterns = file.patterns
            Logger.debug("DismissalTracker: Loaded \(patterns.count) patterns", category: Logger.general)

        } catch {
            Logger.error("DismissalTracker: Failed to load", error: error, category: Logger.general)
        }
    }
}

// MARK: - Data Types

/// JSON file structure for dismissal patterns
struct DismissalPatternsFile: Codable {
    let version: Int
    let patterns: [String: DismissalPattern]
}

/// Pattern tracking for a dismissed grammar rule
struct DismissalPattern: Codable {
    let ruleId: String
    var dismissCount: Int
    var lastDismissed: Date
    var isPermanentlyIgnored: Bool
}
