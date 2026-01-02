// StatisticsHelpers.swift
// Helper functions for statistical calculations

import Foundation

// MARK: - Array Extensions for Statistics

extension [Double] {
    /// Calculate mean (average) of array values
    func mean() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    /// Calculate median of array values
    /// Note: Array should be sorted before calling this
    func median() -> Double {
        guard !isEmpty else { return 0 }
        let sorted = sorted()
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            return sorted[sorted.count / 2]
        }
    }

    /// Calculate percentile (0-100) of array values
    /// Note: Array should be sorted before calling this
    func percentile(_ p: Double) -> Double {
        guard !isEmpty else { return 0 }
        guard p >= 0, p <= 100 else { return 0 }

        let sorted = sorted()
        let index = (p / 100.0) * Double(sorted.count - 1)
        let lower = Int(floor(index))
        let upper = Int(ceil(index))

        if lower == upper {
            return sorted[lower]
        }

        let weight = index - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}

extension [UInt64] {
    /// Calculate mean (average) of array values
    func mean() -> Double {
        guard !isEmpty else { return 0 }
        return Double(reduce(0, +)) / Double(count)
    }

    /// Calculate median of array values
    /// Note: Array should be sorted before calling this
    func median() -> UInt64 {
        guard !isEmpty else { return 0 }
        let sorted = sorted()
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            return sorted[sorted.count / 2]
        }
    }

    /// Calculate percentile (0-100) of array values
    /// Note: Array should be sorted before calling this
    func percentile(_ p: Double) -> UInt64 {
        guard !isEmpty else { return 0 }
        guard p >= 0, p <= 100 else { return 0 }

        let sorted = sorted()
        let index = (p / 100.0) * Double(sorted.count - 1)
        let lower = Int(floor(index))
        let upper = Int(ceil(index))

        if lower == upper {
            return sorted[lower]
        }

        let weight = index - Double(lower)
        return UInt64(
            Double(sorted[lower]) * (1 - weight) + Double(sorted[upper]) * weight
        )
    }
}
