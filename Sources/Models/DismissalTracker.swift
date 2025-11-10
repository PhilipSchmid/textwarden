//
//  DismissalTracker.swift
//  Gnau
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

        let gnauDir = appSupport.appendingPathComponent("Gnau")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: gnauDir,
            withIntermediateDirectories: true
        )

        fileURL = gnauDir.appendingPathComponent("dismissal-patterns.json")

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

        print("📝 DismissalTracker: Saved \(patterns.count) patterns to \(fileURL.path)")
    }

    /// Load patterns from JSON file
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("📝 DismissalTracker: No existing file, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let file = try decoder.decode(DismissalPatternsFile.self, from: data)

            // Validate version
            guard file.version == 1 else {
                print("⚠️ DismissalTracker: Unsupported version \(file.version)")
                return
            }

            patterns = file.patterns
            print("📝 DismissalTracker: Loaded \(patterns.count) patterns from \(fileURL.path)")

        } catch {
            print("❌ DismissalTracker: Failed to load: \(error)")
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
