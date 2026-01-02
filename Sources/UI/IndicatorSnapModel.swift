import AppKit
import Foundation

/// Snap position for error indicator
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

    var preferenceKey: String {
        switch (edge, alignment) {
        case (.top, .start): "Top Left"
        case (.top, .end): "Top Right"
        case (.left, .center): "Center Left"
        case (.right, .center): "Center Right"
        case (.bottom, .start): "Bottom Left"
        case (.bottom, .end): "Bottom Right"
        default: "Bottom Right"
        }
    }

    static func from(preferenceKey: String) -> IndicatorSnapPosition? {
        switch preferenceKey {
        case "Top Left": IndicatorSnapPosition(edge: .top, alignment: .start)
        case "Top Right": IndicatorSnapPosition(edge: .top, alignment: .end)
        case "Center Left": IndicatorSnapPosition(edge: .left, alignment: .center)
        case "Center Right": IndicatorSnapPosition(edge: .right, alignment: .center)
        case "Bottom Left": IndicatorSnapPosition(edge: .bottom, alignment: .start)
        case "Bottom Right": IndicatorSnapPosition(edge: .bottom, alignment: .end)
        default: nil
        }
    }
}

/// Model for snapping indicator to window positions
class IndicatorSnapModel {
    static func snapToNearest(
        currentPoint: CGPoint,
        within bounds: CGRect,
        indicatorSize: CGFloat = 40,
        padding: CGFloat = 10
    ) -> (position: CGPoint, snapPosition: IndicatorSnapPosition) {
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
             IndicatorSnapPosition(edge: .bottom, alignment: .end)),
        ]

        // Array is always non-empty, but guard against nil for safety
        guard let closest = positions.min(by: { pos1, pos2 in
            distance(currentPoint, pos1.0) < distance(currentPoint, pos2.0)
        }) else {
            // Fallback to first position if somehow empty
            return positions[0]
        }

        return closest
    }

    static func position(
        for snapPosition: IndicatorSnapPosition,
        within bounds: CGRect,
        indicatorSize: CGFloat = 40,
        padding: CGFloat = 10
    ) -> CGPoint {
        switch (snapPosition.edge, snapPosition.alignment) {
        case (.top, .start):
            CGPoint(x: bounds.minX + padding, y: bounds.maxY - indicatorSize - padding)

        case (.top, .end):
            CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.maxY - indicatorSize - padding)

        case (.left, .center):
            CGPoint(x: bounds.minX + padding, y: bounds.midY - indicatorSize / 2)

        case (.right, .center):
            CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.midY - indicatorSize / 2)

        case (.bottom, .start):
            CGPoint(x: bounds.minX + padding, y: bounds.minY + padding)

        case (.bottom, .end):
            CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.minY + padding)

        default:
            CGPoint(x: bounds.maxX - indicatorSize - padding, y: bounds.minY + padding)
        }
    }

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
            IndicatorSnapPosition(edge: .bottom, alignment: .end),
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

    private static func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }

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
