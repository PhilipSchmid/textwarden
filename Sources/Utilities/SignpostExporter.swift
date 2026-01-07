//
//  SignpostExporter.swift
//  TextWarden
//
//  Exports signpost data from OSLogStore for diagnostics
//

import Foundation
import OSLog

// MARK: - Signpost Entry

/// A single signpost entry for export
struct SignpostEntry: Codable {
    let date: Date
    let category: String
    let name: String
    let type: String
}

// MARK: - Signpost Exporter

/// Exports signpost data from the system log store for diagnostics
enum SignpostExporter {
    /// Export recent signpost entries as JSON-serializable data
    /// - Parameter since: The start date for signpost collection (defaults to last hour)
    /// - Returns: Array of signpost entries
    static func exportRecentSignposts(since: Date = Date().addingTimeInterval(-3600)) -> [SignpostEntry] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: since)

            let entries = try store.getEntries(
                at: position,
                matching: NSPredicate(format: "subsystem == %@", "io.textwarden.TextWarden")
            )

            var signposts: [SignpostEntry] = []
            for entry in entries {
                if let signpost = entry as? OSLogEntrySignpost {
                    signposts.append(SignpostEntry(
                        date: signpost.date,
                        category: signpost.category,
                        name: signpost.composedMessage,
                        type: String(describing: signpost.signpostType)
                    ))
                }
            }
            return signposts
        } catch {
            Logger.warning("Failed to export signposts: \(error)", category: Logger.performance)
            return []
        }
    }
}
