//
//  SketchDocumentStore.swift
//  TextWarden
//
//  Persistence layer for Sketch Pad documents
//

import Foundation

/// Manages persistence of Sketch Pad documents
/// Storage location: ~/Library/Application Support/TextWarden/Sketches/
@MainActor
class SketchDocumentStore {
    static let shared = SketchDocumentStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Directory where sketches are stored
    private var sketchesDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let textWardenDir = appSupport.appendingPathComponent("TextWarden", isDirectory: true)
        return textWardenDir.appendingPathComponent("Sketches", isDirectory: true)
    }

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Ensure directory exists
        ensureDirectoryExists()
    }

    /// Ensure the sketches directory exists
    private func ensureDirectoryExists() {
        do {
            try fileManager.createDirectory(at: sketchesDirectory, withIntermediateDirectories: true)
            Logger.debug("Sketches directory ready: \(sketchesDirectory.path)", category: Logger.general)
        } catch {
            Logger.error("Failed to create sketches directory: \(error.localizedDescription)", category: Logger.general)
        }
    }

    /// Load all documents, sorted by modification date (newest first)
    func loadAll() -> [SketchDocument] {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: sketchesDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )

            let documents: [SketchDocument] = contents.compactMap { url in
                guard url.pathExtension == "json" else { return nil }
                return loadDocument(at: url)
            }

            // Sort by modification date, newest first
            return documents.sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            Logger.warning("Failed to list sketches: \(error.localizedDescription)", category: Logger.general)
            return []
        }
    }

    /// Load a single document from a URL
    private func loadDocument(at url: URL) -> SketchDocument? {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(SketchDocument.self, from: data)
        } catch {
            Logger.warning("Failed to load sketch at \(url.lastPathComponent): \(error.localizedDescription)", category: Logger.general)
            return nil
        }
    }

    /// Save a document (creates or updates)
    func save(_ document: SketchDocument) async throws {
        let fileURL = sketchesDirectory.appendingPathComponent("\(document.id.uuidString).json")

        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)

        Logger.debug("Saved sketch: \(document.title) (\(document.id))", category: Logger.general)
    }

    /// Delete a document by ID
    func delete(_ id: UUID) async throws {
        let fileURL = sketchesDirectory.appendingPathComponent("\(id.uuidString).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            Logger.warning("Sketch file not found for deletion: \(id)", category: Logger.general)
            return
        }

        try fileManager.removeItem(at: fileURL)
        Logger.info("Deleted sketch: \(id)", category: Logger.general)
    }

    /// Check if a document exists
    func exists(_ id: UUID) -> Bool {
        let fileURL = sketchesDirectory.appendingPathComponent("\(id.uuidString).json")
        return fileManager.fileExists(atPath: fileURL.path)
    }
}
