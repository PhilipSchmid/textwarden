//
//  UnderlineRenderer.swift
//  TextWarden
//
//  Handles drawing squiggly underlines for grammar errors.
//  Pure rendering logic - no state management, no event handling.
//

import AppKit
import Foundation

// MARK: - Underline Renderer

/// Renders squiggly underlines for grammar errors.
///
/// This class is responsible only for the visual rendering of underlines.
/// It does not manage visibility state or handle events.
///
/// Usage:
/// ```swift
/// let renderer = UnderlineRenderer()
/// renderer.render(errorBounds, in: underlineView)
/// ```
final class UnderlineRenderer {
    // MARK: - Types

    /// Represents a rendered underline
    struct RenderedUnderline {
        let path: NSBezierPath
        let color: NSColor
        let errorIndex: Int
        let bounds: CGRect
    }

    // MARK: - Properties

    /// Currently rendered underlines
    private(set) var underlines: [RenderedUnderline] = []

    /// Underline style configuration
    var amplitude: CGFloat = 2.0
    var wavelength: CGFloat = 4.0
    var lineWidth: CGFloat = 1.5

    // MARK: - Rendering

    /// Render underlines for the given error bounds
    /// - Parameters:
    ///   - errorBounds: Array of (errorIndex, bounds, severity) tuples
    ///   - view: The view to render into
    func render(
        _ errorBounds: [(index: Int, bounds: CGRect, severity: ErrorSeverity)],
        in view: NSView?
    ) {
        guard let view else { return }

        underlines = errorBounds.map { index, bounds, severity in
            let path = createSquigglyPath(for: bounds)
            let color = color(for: severity)
            return RenderedUnderline(
                path: path,
                color: color,
                errorIndex: index,
                bounds: bounds
            )
        }

        view.needsDisplay = true
    }

    /// Clear all underlines
    func clear() {
        underlines = []
    }

    /// Draw all underlines in the given context
    func draw(in context: CGContext) {
        for underline in underlines {
            context.saveGState()
            underline.color.setStroke()
            underline.path.lineWidth = lineWidth
            underline.path.stroke()
            context.restoreGState()
        }
    }

    // MARK: - Path Creation

    private func createSquigglyPath(for bounds: CGRect) -> NSBezierPath {
        let path = NSBezierPath()

        // Position just below the text baseline
        let y = bounds.maxY + 1

        guard bounds.width > 0 else { return path }

        path.move(to: NSPoint(x: bounds.minX, y: y))

        var x = bounds.minX
        var phase: CGFloat = 0

        while x < bounds.maxX {
            let nextX = min(x + wavelength / 2, bounds.maxX)
            let controlY = y + (phase.truncatingRemainder(dividingBy: 2) == 0 ? amplitude : -amplitude)

            path.curve(
                to: NSPoint(x: nextX, y: y),
                controlPoint1: NSPoint(x: x + wavelength / 4, y: controlY),
                controlPoint2: NSPoint(x: nextX - wavelength / 4, y: controlY)
            )

            x = nextX
            phase += 1
        }

        return path
    }

    // MARK: - Colors

    /// Severity level for styling
    enum ErrorSeverity {
        case error
        case warning
        case suggestion
    }

    private func color(for severity: ErrorSeverity) -> NSColor {
        switch severity {
        case .error:
            .systemRed
        case .warning:
            .systemOrange
        case .suggestion:
            .systemBlue
        }
    }

    // MARK: - Hit Testing

    /// Find the error index at the given point
    /// - Parameter point: Point in view coordinates
    /// - Returns: Error index if point is over an underline, nil otherwise
    func errorIndex(at point: CGPoint) -> Int? {
        // Expand the hit area vertically for easier clicking
        let hitPadding: CGFloat = 4.0

        for underline in underlines {
            let expandedBounds = underline.bounds.insetBy(dx: 0, dy: -hitPadding)
            if expandedBounds.contains(point) {
                return underline.errorIndex
            }
        }

        return nil
    }
}
