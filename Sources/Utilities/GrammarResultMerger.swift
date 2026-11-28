//
//  GrammarResultMerger.swift
//  TextWarden
//
//  Combines results from the in-process Harper engine with results from an
//  optional external LanguageTool-compatible source.
//

import Foundation

/// Merges grammar results from more than one engine into a single ordered list.
///
/// Harper wins every overlap. It has already seen the user's custom vocabulary,
/// enabled wordlists, and dialect, and the replacement path is built around its
/// ranges and casing rules. An external source that re-reports the same span
/// would otherwise draw a second underline over the first and push the result
/// count toward `UserPreferences.maxErrorsForUnderlines`, which hides underlines
/// entirely once it is exceeded.
///
/// The value of the external source is therefore the spans Harper said nothing
/// about: confused words, collocations, and the longer pattern rules.
enum GrammarResultMerger {
    /// Combine two result sets, preferring `primary` wherever spans overlap.
    ///
    /// - Parameters:
    ///   - primary: Results from the in-process engine.
    ///   - secondary: Results from the external source.
    /// - Returns: Ordered results with overlapping secondary entries removed.
    /// - Parameters:
    ///   - primary: Results from the in-process engine.
    ///   - secondary: Results from the external source.
    ///   - limit: Optional ceiling on the combined count, normally
    ///     `UserPreferences.maxErrorsForUnderlines`. Above that figure the
    ///     overlay hides every underline, so a late external addition could
    ///     make the marks the user was already reading disappear. Secondary
    ///     results are trimmed to keep the total within the ceiling; when the
    ///     primary set already exceeds it, nothing is trimmed, because the
    ///     underlines are hidden either way.
    static func merge(
        primary: [GrammarErrorModel],
        secondary: [GrammarErrorModel],
        limit: Int? = nil
    ) -> [GrammarErrorModel] {
        guard !secondary.isEmpty else { return sorted(primary) }
        guard !primary.isEmpty else {
            return sorted(trim(deduplicate(secondary), toTotalWith: 0, limit: limit))
        }

        let occupied = sorted(primary).map { ($0.start, $0.end) }
        // Harper's claim is settled before the external source's own overlaps
        // are collapsed. Doing it the other way round lets a result that is
        // about to lose to Harper first displace a neighbour Harper never
        // covered, so the merge would lose a span no engine objected to.
        let candidates = sorted(secondary)

        var kept: [GrammarErrorModel] = []
        kept.reserveCapacity(candidates.count)
        var cursor = 0

        for candidate in candidates {
            // Advance past primary spans that end before this candidate starts.
            while cursor < occupied.count, occupied[cursor].1 <= candidate.start {
                cursor += 1
            }
            // Any remaining span starting before the candidate ends overlaps it.
            let overlaps = cursor < occupied.count && occupied[cursor].0 < candidate.end
            if overlaps {
                continue
            }
            kept.append(candidate)
        }

        if kept.count != candidates.count {
            Logger.debug(
                "Merge dropped \(candidates.count - kept.count) overlapping external result(s)",
                category: Logger.analysis
            )
        }

        return sorted(primary + trim(deduplicate(kept), toTotalWith: primary.count, limit: limit))
    }

    /// Keep the earliest secondary results that fit under `limit`.
    ///
    /// Trimming happens before the user's category and vocabulary filters run,
    /// which may remove more results afterwards, so this errs toward keeping
    /// the total low rather than risking the ceiling being crossed.
    private static func trim(
        _ secondary: [GrammarErrorModel],
        toTotalWith primaryCount: Int,
        limit: Int?
    ) -> [GrammarErrorModel] {
        // `<=`, not `<`: the overlay hides underlines above the ceiling, not at
        // it, so a primary set sitting exactly on the ceiling has no room left.
        guard let limit, limit >= 0, primaryCount <= limit else { return secondary }
        let allowance = limit - primaryCount
        guard secondary.count > allowance else { return secondary }

        Logger.debug(
            "Merge trimmed \(secondary.count - allowance) external result(s) to stay within the underline ceiling",
            category: Logger.analysis
        )
        return Array(sorted(secondary).prefix(allowance))
    }

    /// Collapse a single source's own overlaps, keeping the earliest result.
    ///
    /// LanguageTool routinely reports more than one rule across the same span,
    /// such as a whitespace rule and a punctuation rule on one comma. Keeping
    /// both would draw two underlines on one span, which is exactly what the
    /// cross-engine rule above exists to prevent.
    private static func deduplicate(_ errors: [GrammarErrorModel]) -> [GrammarErrorModel] {
        var kept: [GrammarErrorModel] = []
        var seen = Set<String>()
        for error in sorted(errors) {
            guard seen.insert("\(error.start):\(error.end):\(error.lintId)").inserted else { continue }
            // Comparing against the last kept result is enough, and keeps a
            // large reply linear. The input is sorted by start and everything
            // kept is pairwise disjoint, so their ends increase too: anything
            // that clears the last one clears all of them.
            if let last = kept.last, last.start < error.end, error.start < last.end { continue }
            kept.append(error)
        }
        return kept
    }

    /// Stable ordering by position, so underlines and the popover list agree.
    private static func sorted(_ errors: [GrammarErrorModel]) -> [GrammarErrorModel] {
        errors.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
    }
}
