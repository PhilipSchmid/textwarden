import AppKit
import Foundation

/// Stores and retrieves indicator positions per application
/// Positions are stored as percentages (0.0-1.0) of window bounds
/// to handle window resizing gracefully
class IndicatorPositionStore {
    static let shared = IndicatorPositionStore()

    private let defaults = UserDefaults.standard
    private let positionsKey = "com.textwarden.indicatorPositions"

    private init() {}

    /// Stored position as percentages of window bounds
    struct PercentagePosition: Codable {
        let xPercent: Double // 0.0-1.0 from left edge
        let yPercent: Double // 0.0-1.0 from bottom edge

        /// Convert to absolute position within given bounds (square indicator)
        func toAbsolute(in bounds: CGRect, indicatorSize: CGFloat) -> CGPoint {
            toAbsolute(in: bounds, width: indicatorSize, height: indicatorSize)
        }

        /// Convert to absolute position within given bounds (rectangular indicator)
        func toAbsolute(in bounds: CGRect, width: CGFloat, height: CGFloat) -> CGPoint {
            let x = bounds.minX + (bounds.width - width) * xPercent
            let y = bounds.minY + (bounds.height - height) * yPercent
            return CGPoint(x: x, y: y)
        }

        /// Create from absolute position within bounds (square indicator)
        static func from(
            absolutePosition: CGPoint,
            in bounds: CGRect,
            indicatorSize: CGFloat
        ) -> PercentagePosition {
            from(absolutePosition: absolutePosition, in: bounds, width: indicatorSize, height: indicatorSize)
        }

        /// Create from absolute position within bounds (rectangular indicator)
        static func from(
            absolutePosition: CGPoint,
            in bounds: CGRect,
            width: CGFloat,
            height: CGFloat
        ) -> PercentagePosition {
            // Calculate position as percentage of available space
            let xPercent = (absolutePosition.x - bounds.minX) / (bounds.width - width)
            let yPercent = (absolutePosition.y - bounds.minY) / (bounds.height - height)

            // Clamp to 0.0-1.0 range
            let clampedX = max(0.0, min(1.0, xPercent))
            let clampedY = max(0.0, min(1.0, yPercent))

            return PercentagePosition(xPercent: clampedX, yPercent: clampedY)
        }
    }

    /// Get stored position for an application
    /// Returns nil if no position is stored for this app
    func getPosition(for bundleIdentifier: String) -> PercentagePosition? {
        guard let data = defaults.dictionary(forKey: positionsKey),
              let positionData = data[bundleIdentifier] as? Data
        else {
            Logger.debug("IndicatorPositionStore: No stored position for \(bundleIdentifier)", category: Logger.ui)
            return nil
        }

        do {
            let position = try JSONDecoder().decode(PercentagePosition.self, from: positionData)
            Logger.debug("IndicatorPositionStore: Loaded position for \(bundleIdentifier): x=\(position.xPercent), y=\(position.yPercent)", category: Logger.ui)
            return position
        } catch {
            Logger.debug("IndicatorPositionStore: Failed to decode position for \(bundleIdentifier): \(error)", category: Logger.ui)
            return nil
        }
    }

    /// Save position for an application
    func savePosition(_ position: PercentagePosition, for bundleIdentifier: String) {
        var positions = defaults.dictionary(forKey: positionsKey) ?? [:]

        do {
            let data = try JSONEncoder().encode(position)
            positions[bundleIdentifier] = data
            defaults.set(positions, forKey: positionsKey)
            defaults.synchronize()

            Logger.debug("IndicatorPositionStore: Saved position for \(bundleIdentifier): x=\(position.xPercent), y=\(position.yPercent)", category: Logger.ui)
        } catch {
            Logger.debug("IndicatorPositionStore: Failed to encode position for \(bundleIdentifier): \(error)", category: Logger.ui)
        }
    }

    /// Clear position for an application
    func clearPosition(for bundleIdentifier: String) {
        var positions = defaults.dictionary(forKey: positionsKey) ?? [:]
        positions.removeValue(forKey: bundleIdentifier)
        defaults.set(positions, forKey: positionsKey)
        defaults.synchronize()

        Logger.debug("IndicatorPositionStore: Cleared position for \(bundleIdentifier)", category: Logger.ui)
    }

    /// Clear all stored positions
    func clearAll() {
        defaults.removeObject(forKey: positionsKey)
        defaults.synchronize()

        Logger.debug("IndicatorPositionStore: Cleared all positions", category: Logger.ui)
    }

    /// Get the default position from UserPreferences as percentage
    /// Converts the snap position to percentage coordinates
    @MainActor
    func getDefaultPosition() -> PercentagePosition {
        let position = UserPreferences.shared.indicatorPosition

        // Convert snap position names to percentage coordinates
        switch position {
        case "Top Left":
            return PercentagePosition(xPercent: 0.0, yPercent: 1.0)
        case "Top Right":
            return PercentagePosition(xPercent: 1.0, yPercent: 1.0)
        case "Center Left":
            return PercentagePosition(xPercent: 0.0, yPercent: 0.5)
        case "Center Right":
            return PercentagePosition(xPercent: 1.0, yPercent: 0.5)
        case "Bottom Left":
            return PercentagePosition(xPercent: 0.0, yPercent: 0.0)
        case "Bottom Right":
            return PercentagePosition(xPercent: 1.0, yPercent: 0.0)
        default:
            // Default to bottom right
            return PercentagePosition(xPercent: 1.0, yPercent: 0.0)
        }
    }
}
