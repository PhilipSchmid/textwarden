//
//  SketchDocument.swift
//  TextWarden
//
//  Model representing a Sketch Pad document with markdown-based storage
//

import AppKit
import Foundation

/// A Sketch Pad document with title, content, and timestamps
/// Uses markdown for primary storage
struct SketchDocument: Identifiable, Codable {
    let id: UUID
    var title: String
    var markdown: String
    var createdAt: Date
    var modifiedAt: Date

    /// Get attributed content as NSAttributedString (renders markdown)
    var nsAttributedContent: NSAttributedString {
        MarkdownRenderer.render(markdown)
    }

    /// Plain text content
    var plainText: String {
        nsAttributedContent.string
    }

    /// Plain text preview for sidebar display
    var plainTextPreview: String {
        let text = plainText
        let preview = String(text.prefix(100))
        return preview.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Formatted timestamp for display
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: modifiedAt, relativeTo: Date())
    }
}
