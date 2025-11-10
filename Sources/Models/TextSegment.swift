//
//  TextSegment.swift
//  Gnau
//
//  Model representing a segment of text with metadata
//

import Foundation

/// Represents a segment of text being monitored for grammar checking
struct TextSegment {
    /// The actual text content
    let content: String

    /// Starting character index in the full document
    let startIndex: Int

    /// Ending character index in the full document
    let endIndex: Int

    /// Application context where this text exists
    let context: ApplicationContext

    /// Timestamp when this segment was captured
    let timestamp: Date

    /// Unique identifier for this text segment
    let id: UUID

    /// Initialize a text segment
    init(
        content: String,
        startIndex: Int,
        endIndex: Int,
        context: ApplicationContext,
        timestamp: Date = Date(),
        id: UUID = UUID()
    ) {
        self.content = content
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.context = context
        self.timestamp = timestamp
        self.id = id
    }

    /// Length of the text segment
    var length: Int {
        content.count
    }

    /// Check if this segment overlaps with another
    func overlaps(with other: TextSegment) -> Bool {
        guard context.bundleIdentifier == other.context.bundleIdentifier else {
            return false
        }

        let thisRange = startIndex..<endIndex
        let otherRange = other.startIndex..<other.endIndex

        return thisRange.overlaps(otherRange)
    }

    /// Create a new segment with updated content
    func with(content: String) -> TextSegment {
        TextSegment(
            content: content,
            startIndex: startIndex,
            endIndex: startIndex + content.count,
            context: context,
            timestamp: Date(),
            id: UUID()
        )
    }
}

// MARK: - Equatable

extension TextSegment: Equatable {
    static func == (lhs: TextSegment, rhs: TextSegment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension TextSegment: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CustomStringConvertible

extension TextSegment: CustomStringConvertible {
    var description: String {
        "\(context.applicationName): \"\(content.prefix(50))...\" [\(startIndex):\(endIndex)]"
    }
}
