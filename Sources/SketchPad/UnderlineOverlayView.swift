//
//  UnderlineOverlayView.swift
//  TextWarden
//
//  SwiftUI Canvas overlay for custom underline rendering
//  Renders grammar (solid red), style (dotted purple), and readability (dashed purple) underlines
//

import SwiftUI

/// Underline type matching the existing SketchUnderlineType
enum SketchUnderlineCategory {
    case grammar // Red solid line
    case style // Purple dotted line
    case readability // Purple dashed line

    var color: Color {
        switch self {
        case .grammar:
            .red
        case .style, .readability:
            .purple
        }
    }

    var nsColor: NSColor {
        switch self {
        case .grammar:
            .systemRed
        case .style, .readability:
            .systemPurple
        }
    }
}

/// A positioned underline with its screen rect
struct SketchUnderlineRect: Identifiable, Equatable {
    let id: String
    let rect: CGRect
    let category: SketchUnderlineCategory
    let message: String
    /// Range in UTF-16 code units (for NSTextView/STTextView text operations)
    let range: NSRange
    /// Range in Unicode scalar indices (for matching with Harper's grammar errors)
    let scalarRange: NSRange
    /// Suggestions for fixing the issue (clickable options)
    let suggestions: [String]
    /// Original text that has the issue
    let originalText: String
    /// Lint ID for "ignore rule" functionality
    let lintId: String?

    // MARK: - Hit Testing

    /// Padding around the underline rect for hit testing
    private static let hitTestPaddingX: CGFloat = 2
    private static let hitTestPaddingY: CGFloat = 4
    private static let hitTestOffsetY: CGFloat = 4

    /// Expanded rect for hit testing (easier to target with mouse)
    var hitTestRect: CGRect {
        rect.insetBy(dx: -Self.hitTestPaddingX, dy: -Self.hitTestPaddingY)
            .offsetBy(dx: 0, dy: Self.hitTestOffsetY)
    }

    static func == (lhs: SketchUnderlineRect, rhs: SketchUnderlineRect) -> Bool {
        lhs.id == rhs.id && lhs.rect == rhs.rect
    }
}

/// SwiftUI Canvas overlay for custom underline rendering
struct UnderlineOverlayView: View {
    /// Underlines to render
    let underlines: [SketchUnderlineRect]

    /// Callback when hovering over an underline
    let onHover: (SketchUnderlineRect?) -> Void

    /// ID of underline to highlight (from selection or hover)
    let highlightedUnderlineId: String?

    /// Currently hovered underline (for hit testing)
    @State private var hoveredUnderline: SketchUnderlineRect?

    /// Underline thickness from preferences
    @ObservedObject private var preferences = UserPreferences.shared

    /// Environment color scheme for adaptive highlight colors
    @Environment(\.colorScheme) private var colorScheme

    /// Underlines sorted for proper z-ordering (grammar on top)
    private var sortedUnderlines: [SketchUnderlineRect] {
        // Draw style/readability first, then grammar on top
        underlines.sorted { lhs, rhs in
            // Grammar should be drawn last (higher priority)
            if lhs.category == .grammar, rhs.category != .grammar {
                return false // lhs (grammar) goes after rhs
            }
            if lhs.category != .grammar, rhs.category == .grammar {
                return true // lhs (non-grammar) goes before rhs
            }
            return false // maintain order for same category
        }
    }

    /// Extract base ID from underline ID (removes line index suffix like "-0", "-1", etc.)
    private func baseId(from id: String) -> String {
        if let lastDashIndex = id.lastIndex(of: "-"),
           let suffix = Int(String(id[id.index(after: lastDashIndex)...]))
        {
            _ = suffix
            return String(id[..<lastDashIndex])
        }
        return id
    }

    /// All underlines to highlight (all segments of the same base underline)
    private var highlightedUnderlines: [SketchUnderlineRect] {
        // Get base ID from hover or selection
        // Note: hoveredUnderline.id has the line index suffix (e.g., "uuid-0")
        // but highlightedUnderlineId is already the base ID from UnifiedSuggestion (e.g., "uuid" or "lintId-start-end")
        let activeBaseId: String? = if let hovered = hoveredUnderline {
            baseId(from: hovered.id)
        } else if let selectedId = highlightedUnderlineId {
            // The selectedId from insights is already the base ID - don't process it further
            selectedId
        } else {
            nil
        }

        guard let targetBaseId = activeBaseId else { return [] }

        // Return ALL underline segments with the same base ID
        return underlines.filter { baseId(from: $0.id) == targetBaseId }
    }

    var body: some View {
        Canvas { context, _ in
            // Draw highlight background for all segments of the active underline
            for highlighted in highlightedUnderlines {
                drawHighlight(context: context, underline: highlighted)
            }

            // Draw underlines
            for underline in sortedUnderlines {
                drawUnderline(context: context, underline: underline)
            }
        }
        .allowsHitTesting(true)
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                // Find underline at this location
                let found = underlineAt(location)
                if found?.id != hoveredUnderline?.id {
                    hoveredUnderline = found
                    onHover(found)
                }
            case .ended:
                if hoveredUnderline != nil {
                    hoveredUnderline = nil
                    onHover(nil)
                }
            }
        }
    }

    // MARK: - Drawing

    /// Draw a semi-transparent background highlight for the active underline
    private func drawHighlight(context: GraphicsContext, underline: SketchUnderlineRect) {
        let rect = underline.rect

        // Create highlight rect that covers the text area
        // Expand vertically to cover the full line height
        let highlightRect = CGRect(
            x: rect.minX - 2,
            y: rect.minY,
            width: rect.width + 4,
            height: rect.height
        )

        // Use category color with adaptive opacity for light/dark mode
        let baseColor = underline.category.color
        let opacity: Double = colorScheme == .dark ? 0.25 : 0.15

        let highlightPath = RoundedRectangle(cornerRadius: 3)
            .path(in: highlightRect)

        context.fill(highlightPath, with: .color(baseColor.opacity(opacity)))
    }

    private func drawUnderline(context: GraphicsContext, underline: SketchUnderlineRect) {
        let rect = underline.rect
        let thickness = CGFloat(preferences.underlineThickness)
        // Position underline below the text
        // The rect from TextKit represents the line fragment, which may have extra height
        // Use origin.y (top of text) + a calculated baseline position
        // For a 16pt font, baseline is roughly at origin.y + 14pt (font size - descender)
        // Then add small offset for the underline below baseline
        let baselineFromTop: CGFloat = 14.0 // Approximate baseline position from top of line
        let underlineOffset: CGFloat = 2.0 + thickness / 2.0 // Small gap below baseline
        let y = rect.origin.y + baselineFromTop + underlineOffset

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))

        var strokeStyle = StrokeStyle(lineWidth: thickness)

        switch underline.category {
        case .grammar:
            // Solid line
            break
        case .style:
            // Dotted: 4pt dash, 3pt gap
            strokeStyle.dash = [4.0, 3.0]
        case .readability:
            // Dashed: 6pt dash, 4pt gap
            strokeStyle.dash = [6.0, 4.0]
        }

        context.stroke(path, with: .color(underline.category.color), style: strokeStyle)
    }

    // MARK: - Hit Testing

    private func underlineAt(_ point: CGPoint) -> SketchUnderlineRect? {
        // Find underline whose hit test rect contains the point
        for underline in underlines {
            if underline.hitTestRect.contains(point) {
                return underline
            }
        }
        return nil
    }
}

// MARK: - Underline Geometry Calculator

/// Helper to calculate underline rects from analysis results
@MainActor
enum UnderlineGeometryCalculator {
    /// Calculate underline rects for grammar errors and style suggestions using STTextView layout (TextKit 2)
    static func calculateRectsFromSTLayout(
        for errors: [GrammarErrorModel],
        styleSuggestions: [StyleSuggestionModel],
        using layoutInfo: STTextLayoutInfo,
        sourceText: String
    ) -> [SketchUnderlineRect] {
        var results: [SketchUnderlineRect] = []

        // Grammar errors
        for error in errors {
            // Validate that the error's position is within bounds
            guard error.end <= sourceText.unicodeScalars.count else {
                Logger.warning("Grammar error position out of bounds: \(error.start)-\(error.end) > \(sourceText.unicodeScalars.count)", category: Logger.analysis)
                continue
            }

            // Convert from Unicode scalar indices (Harper) to UTF-16 indices (STTextView)
            let scalarRange = NSRange(location: error.start, length: error.end - error.start)
            let range = TextIndexConverter.scalarToUTF16Range(scalarRange, in: sourceText)
            let rects = layoutInfo.rectsForRange(range)

            // Extract original text using scalar indices (Harper's indices)
            let originalText = TextIndexConverter.extractErrorText(
                start: error.start,
                end: error.end,
                from: sourceText
            ) ?? ""

            // Use ID format matching UnifiedSuggestion: "\(lintId)-\(start)-\(end)"
            // Append line index for multi-line underlines
            let baseId = "\(error.lintId)-\(error.start)-\(error.end)"
            for (index, rect) in rects.enumerated() {
                results.append(SketchUnderlineRect(
                    id: "\(baseId)-\(index)",
                    rect: rect,
                    category: .grammar,
                    message: error.message,
                    range: range,
                    scalarRange: scalarRange,
                    suggestions: error.suggestions,
                    originalText: originalText,
                    lintId: error.lintId
                ))
            }
        }

        // Style suggestions (these use scalar indices from Foundation Models)
        for suggestion in styleSuggestions {
            let scalarRange = NSRange(location: suggestion.originalStart, length: suggestion.originalEnd - suggestion.originalStart)

            // Validate that the suggestion's position is within bounds
            guard suggestion.originalEnd <= sourceText.unicodeScalars.count else {
                Logger.warning("Style suggestion position out of bounds: \(suggestion.originalStart)-\(suggestion.originalEnd) > \(sourceText.unicodeScalars.count)", category: Logger.analysis)
                continue
            }

            // Validate that the text at this position still matches the suggestion's original text
            // This catches stale suggestions from analysis that completed after text was modified
            let extractedText = TextIndexConverter.extractErrorText(
                start: suggestion.originalStart,
                end: suggestion.originalEnd,
                from: sourceText
            ) ?? ""
            if extractedText != suggestion.originalText {
                Logger.debug("Style suggestion text mismatch - expected '\(suggestion.originalText.prefix(30))...', found '\(extractedText.prefix(30))...' at position \(suggestion.originalStart)", category: Logger.analysis)
                continue
            }

            let range = TextIndexConverter.scalarToUTF16Range(scalarRange, in: sourceText)
            let rects = layoutInfo.rectsForRange(range)

            let category: SketchUnderlineCategory = suggestion.isReadabilitySuggestion ? .readability : .style

            // Use ID format matching UnifiedSuggestion: suggestion.id (UUID)
            // Append line index for multi-line underlines
            for (index, rect) in rects.enumerated() {
                results.append(SketchUnderlineRect(
                    id: "\(suggestion.id)-\(index)",
                    rect: rect,
                    category: category,
                    message: suggestion.explanation,
                    range: range,
                    scalarRange: scalarRange,
                    suggestions: suggestion.suggestedText.isEmpty ? [] : [suggestion.suggestedText],
                    originalText: suggestion.originalText,
                    lintId: nil
                ))
            }
        }

        return results
    }
}

// MARK: - Preview

#Preview {
    UnderlineOverlayView(
        underlines: [
            SketchUnderlineRect(
                id: "1",
                rect: CGRect(x: 50, y: 50, width: 100, height: 20),
                category: .grammar,
                message: "Grammar error",
                range: NSRange(location: 0, length: 10),
                scalarRange: NSRange(location: 0, length: 10),
                suggestions: ["suggestion1", "suggestion2"],
                originalText: "teh",
                lintId: nil
            ),
            SketchUnderlineRect(
                id: "2",
                rect: CGRect(x: 50, y: 100, width: 80, height: 20),
                category: .style,
                message: "Style suggestion",
                range: NSRange(location: 20, length: 8),
                scalarRange: NSRange(location: 20, length: 8),
                suggestions: ["improved text"],
                originalText: "original",
                lintId: nil
            ),
            SketchUnderlineRect(
                id: "3",
                rect: CGRect(x: 50, y: 150, width: 120, height: 20),
                category: .readability,
                message: "Readability issue",
                range: NSRange(location: 40, length: 12),
                scalarRange: NSRange(location: 40, length: 12),
                suggestions: [],
                originalText: "complex text",
                lintId: nil
            ),
        ],
        onHover: { _ in },
        highlightedUnderlineId: nil
    )
    .frame(width: 300, height: 200)
    .background(Color.white)
}
