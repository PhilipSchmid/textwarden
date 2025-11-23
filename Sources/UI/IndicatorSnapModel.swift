import Foundation
import AppKit

/// Snap position for error indicator
/// Defines where the indicator can be positioned relative to the target window
struct IndicatorSnapPosition: Equatable, Hashable {
    enum Edge: String {
        case top
        case bottom
        case left
        case right
    }

    enum Alignment: String {
        case start
        case center
        case end
    }

    let edge: Edge
    let alignment: Alignment

    /// Maps to UserPreferences position string
    var preferenceKey: String {
        switch (edge, alignment) {
        case (.top, .start): return "Top Left"
        case (.top, .end): return "Top Right"
        case (.left, .center): return "Center Left"
        case (.right, .center): return "Center Right"
        case (.bottom, .start): return "Bottom Left"
        case (.bottom, .end): return "Bottom Right"
        default: return "Bottom Right"
        }
    }

    /// Create from preference key
    static func from(preferenceKey: String) -> IndicatorSnapPosition? {
        switch preferenceKey {
        case "Top Left": return IndicatorSnapPosition(edge: .top, alignment: .start)
        case "Top Right": return IndicatorSnapPosition(edge: .top, alignment: .end)
        case "Center Left": return IndicatorSnapPosition(edge: .left, alignment: .center)
        case "Center Right": return IndicatorSnapPosition(edge: .right, alignment: .center)
        case "Bottom Left": return IndicatorSnapPosition(edge: .bottom, alignment: .start)
        case "Bottom Right": return IndicatorSnapPosition(edge: .bottom, alignment: .end)
        default: return nil
        }
    }
}

/// Model for snapping indicator to window positions
/// Calculates snap points and finds nearest position
class IndicatorSnapModel {

    /// Calculate snap position from current point
    /// Returns the nearest valid snap position and its coordinates
    static func snapToNearest(
        currentPoint: CGPoint,
        within bounds: CGRect,
        indicatorSize: CGFloat = 40,
        padding: CGFloat = 10
    ) -> (position: CGPoint, snapPosition: IndicatorSnapPosition) {

        // Define all 6 snap positions
        let positions: [(CGPoint, IndicatorSnapPosition)] = [
            // Top Left
            (CGPoint(x: bounds.minX + padding, y: bounds.maxY - indicatorSize - padding),
             IndicatorSnapPosition(edge: .top, alignment: .start)),

            // Top Right
            (CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.maxY - indicatorSize - padding),
             IndicatorSnapPosition(edge: .top, alignment: .end)),

            // Center Left
            (CGPoint(x: bounds.minX + padding, y: bounds.midY - indicatorSize / 2),
             IndicatorSnapPosition(edge: .left, alignment: .center)),

            // Center Right
            (CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.midY - indicatorSize / 2),
             IndicatorSnapPosition(edge: .right, alignment: .center)),

            // Bottom Left
            (CGPoint(x: bounds.minX + padding, y: bounds.minY + padding),
             IndicatorSnapPosition(edge: .bottom, alignment: .start)),

            // Bottom Right
            (CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.minY + padding),
             IndicatorSnapPosition(edge: .bottom, alignment: .end))
        ]

        // Find closest position
        let closest = positions.min { pos1, pos2 in
            distance(currentPoint, pos1.0) < distance(currentPoint, pos2.0)
        }!

        return closest
    }

    /// Get specific snap position coordinates
    static func position(
        for snapPosition: IndicatorSnapPosition,
        within bounds: CGRect,
        indicatorSize: CGFloat = 40,
        padding: CGFloat = 10
    ) -> CGPoint {

        switch (snapPosition.edge, snapPosition.alignment) {
        case (.top, .start):
            return CGPoint(x: bounds.minX + padding, y: bounds.maxY - indicatorSize - padding)

        case (.top, .end):
            return CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.maxY - indicatorSize - padding)

        case (.left, .center):
            return CGPoint(x: bounds.minX + padding, y: bounds.midY - indicatorSize / 2)

        case (.right, .center):
            return CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.midY - indicatorSize / 2)

        case (.bottom, .start):
            return CGPoint(x: bounds.minX + padding, y: bounds.minY + padding)

        case (.bottom, .end):
            return CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.minY + padding)

        default:
            // Default to bottom right
            return CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.minY + padding)
        }
    }

    /// Get all valid snap positions for a window frame
    /// Useful for debugging or showing snap guides
    static func allSnapPositions(
        for bounds: CGRect,
        indicatorSize: CGFloat = 40,
        padding: CGFloat = 10
    ) -> [IndicatorSnapPosition: CGPoint] {

        var positions: [IndicatorSnapPosition: CGPoint] = [:]

        let allSnapPositions: [IndicatorSnapPosition] = [
            IndicatorSnapPosition(edge: .top, alignment: .start),
            IndicatorSnapPosition(edge: .top, alignment: .end),
            IndicatorSnapPosition(edge: .left, alignment: .center),
            IndicatorSnapPosition(edge: .right, alignment: .center),
            IndicatorSnapPosition(edge: .bottom, alignment: .start),
            IndicatorSnapPosition(edge: .bottom, alignment: .end)
        ]

        for snapPos in allSnapPositions {
            positions[snapPos] = position(
                for: snapPos,
                within: bounds,
                indicatorSize: indicatorSize,
                padding: padding
            )
        }

        return positions
    }

    /// Calculate distance between two points
    private static func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }

    /// Check if a point is within snapping threshold of any snap position
    /// Returns the snap position if within threshold, nil otherwise
    static func snapPositionNear(
        point: CGPoint,
        within bounds: CGRect,
        indicatorSize: CGFloat = 40,
        padding: CGFloat = 10,
        threshold: CGFloat = 50
    ) -> IndicatorSnapPosition? {

        let (nearestPoint, snapPosition) = snapToNearest(
            currentPoint: point,
            within: bounds,
            indicatorSize: indicatorSize,
            padding: padding
        )

        let dist = distance(point, nearestPoint)
        return dist <= threshold ? snapPosition : nil
    }
}
