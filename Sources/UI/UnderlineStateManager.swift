//
//  UnderlineStateManager.swift
//  TextWarden
//
//  Unified state manager for all underline types.
//  Ensures consistency between grammar, style, and readability underlines.
//
//  Design principles:
//  1. Single source of truth - all underline state owned by this manager
//  2. Atomic updates - all state changes happen together
//  3. Invariant enforcement - automatically maintain consistency
//  4. Observable changes - notify view when state changes
//

import CoreGraphics
import Foundation

// MARK: - UnderlineState

/// Immutable snapshot of all underline state.
/// Guarantees internal consistency through construction and validation.
struct UnderlineState {
    /// Grammar error underlines (red wavy)
    let grammarUnderlines: [ErrorUnderline]

    /// Style suggestion underlines (purple dotted)
    let styleUnderlines: [StyleUnderline]

    /// Readability underlines for complex sentences (violet dashed)
    let readabilityUnderlines: [ReadabilityUnderline]

    /// Index of currently hovered grammar underline
    let hoveredGrammarIndex: Int?

    /// Index of currently hovered style underline
    let hoveredStyleIndex: Int?

    /// Index of currently hovered readability underline
    let hoveredReadabilityIndex: Int?

    /// Index of locked highlight (persists while popover is open)
    let lockedHighlightIndex: Int?

    /// Empty state - guaranteed consistent
    static let empty = UnderlineState(
        grammarUnderlines: [],
        styleUnderlines: [],
        readabilityUnderlines: [],
        hoveredGrammarIndex: nil,
        hoveredStyleIndex: nil,
        hoveredReadabilityIndex: nil,
        lockedHighlightIndex: nil
    )

    // MARK: - Computed Properties

    /// Whether there are any underlines to display
    var hasContent: Bool {
        !grammarUnderlines.isEmpty || !styleUnderlines.isEmpty || !readabilityUnderlines.isEmpty
    }

    /// Currently hovered grammar underline (if any)
    var hoveredGrammarUnderline: ErrorUnderline? {
        guard let index = hoveredGrammarIndex,
              grammarUnderlines.indices.contains(index)
        else { return nil }
        return grammarUnderlines[index]
    }

    /// Currently hovered style underline (if any)
    var hoveredStyleUnderline: StyleUnderline? {
        guard let index = hoveredStyleIndex,
              styleUnderlines.indices.contains(index)
        else { return nil }
        return styleUnderlines[index]
    }

    /// Currently hovered readability underline (if any)
    var hoveredReadabilityUnderline: ReadabilityUnderline? {
        guard let index = hoveredReadabilityIndex,
              readabilityUnderlines.indices.contains(index)
        else { return nil }
        return readabilityUnderlines[index]
    }

    /// Locked highlight underline (if any)
    var lockedHighlightUnderline: ErrorUnderline? {
        guard let index = lockedHighlightIndex,
              grammarUnderlines.indices.contains(index)
        else { return nil }
        return grammarUnderlines[index]
    }

    // MARK: - Validation

    /// Validates that all invariants hold.
    /// Call in DEBUG builds to catch inconsistencies early.
    func validateInvariants() -> Bool {
        // Hover indices must be valid or nil
        if let idx = hoveredGrammarIndex, !grammarUnderlines.indices.contains(idx) {
            Logger.error("UnderlineState: Invalid hoveredGrammarIndex \(idx) for \(grammarUnderlines.count) underlines", category: Logger.ui)
            return false
        }
        if let idx = hoveredStyleIndex, !styleUnderlines.indices.contains(idx) {
            Logger.error("UnderlineState: Invalid hoveredStyleIndex \(idx) for \(styleUnderlines.count) underlines", category: Logger.ui)
            return false
        }
        if let idx = hoveredReadabilityIndex, !readabilityUnderlines.indices.contains(idx) {
            Logger.error("UnderlineState: Invalid hoveredReadabilityIndex \(idx) for \(readabilityUnderlines.count) underlines", category: Logger.ui)
            return false
        }
        if let idx = lockedHighlightIndex, !grammarUnderlines.indices.contains(idx) {
            Logger.error("UnderlineState: Invalid lockedHighlightIndex \(idx) for \(grammarUnderlines.count) underlines", category: Logger.ui)
            return false
        }
        return true
    }

    // MARK: - State Transformations

    /// Creates a new state with updated hover index for grammar underlines
    func withHoveredGrammarIndex(_ index: Int?) -> UnderlineState {
        UnderlineState(
            grammarUnderlines: grammarUnderlines,
            styleUnderlines: styleUnderlines,
            readabilityUnderlines: readabilityUnderlines,
            hoveredGrammarIndex: index,
            hoveredStyleIndex: hoveredStyleIndex,
            hoveredReadabilityIndex: hoveredReadabilityIndex,
            lockedHighlightIndex: lockedHighlightIndex
        )
    }

    /// Creates a new state with updated hover index for style underlines
    func withHoveredStyleIndex(_ index: Int?) -> UnderlineState {
        UnderlineState(
            grammarUnderlines: grammarUnderlines,
            styleUnderlines: styleUnderlines,
            readabilityUnderlines: readabilityUnderlines,
            hoveredGrammarIndex: hoveredGrammarIndex,
            hoveredStyleIndex: index,
            hoveredReadabilityIndex: hoveredReadabilityIndex,
            lockedHighlightIndex: lockedHighlightIndex
        )
    }

    /// Creates a new state with updated hover index for readability underlines
    func withHoveredReadabilityIndex(_ index: Int?) -> UnderlineState {
        UnderlineState(
            grammarUnderlines: grammarUnderlines,
            styleUnderlines: styleUnderlines,
            readabilityUnderlines: readabilityUnderlines,
            hoveredGrammarIndex: hoveredGrammarIndex,
            hoveredStyleIndex: hoveredStyleIndex,
            hoveredReadabilityIndex: index,
            lockedHighlightIndex: lockedHighlightIndex
        )
    }

    /// Creates a new state with updated locked highlight index
    func withLockedHighlightIndex(_ index: Int?) -> UnderlineState {
        UnderlineState(
            grammarUnderlines: grammarUnderlines,
            styleUnderlines: styleUnderlines,
            readabilityUnderlines: readabilityUnderlines,
            hoveredGrammarIndex: hoveredGrammarIndex,
            hoveredStyleIndex: hoveredStyleIndex,
            hoveredReadabilityIndex: hoveredReadabilityIndex,
            lockedHighlightIndex: index
        )
    }

    /// Creates a new state with grammar underlines cleared but preserving readability
    func withGrammarUnderlinesCleared() -> UnderlineState {
        UnderlineState(
            grammarUnderlines: [],
            styleUnderlines: [],
            readabilityUnderlines: readabilityUnderlines,
            hoveredGrammarIndex: nil,
            hoveredStyleIndex: nil,
            hoveredReadabilityIndex: hoveredReadabilityIndex,
            lockedHighlightIndex: nil
        )
    }

    /// Creates a new state with readability underlines cleared but preserving grammar
    func withReadabilityUnderlinesCleared() -> UnderlineState {
        UnderlineState(
            grammarUnderlines: grammarUnderlines,
            styleUnderlines: styleUnderlines,
            readabilityUnderlines: [],
            hoveredGrammarIndex: hoveredGrammarIndex,
            hoveredStyleIndex: hoveredStyleIndex,
            hoveredReadabilityIndex: nil,
            lockedHighlightIndex: lockedHighlightIndex
        )
    }
}

// MARK: - UnderlineStateManager

/// Manages all underline state with guaranteed consistency.
/// This is the single source of truth for underline visibility and hover state.
///
/// Usage:
/// ```swift
/// let manager = UnderlineStateManager()
/// manager.onStateChanged = { state in
///     underlineView.applyState(state)
/// }
///
/// // Update all underlines atomically
/// manager.updateAll(
///     grammarUnderlines: buildGrammarUnderlines(from: errors),
///     styleUnderlines: buildStyleUnderlines(from: suggestions),
///     readabilityUnderlines: buildReadabilityUnderlines(from: analysis)
/// )
///
/// // Update hover state
/// manager.setHoveredGrammarIndex(2)
/// ```
final class UnderlineStateManager {
    // MARK: - Properties

    /// Current state - always consistent
    private(set) var currentState: UnderlineState = .empty

    /// Callback when state changes
    var onStateChanged: ((UnderlineState) -> Void)?

    // MARK: - Public API - Atomic Updates

    /// Update all underlines atomically.
    /// This is the primary method for updating underline state.
    /// Preserves hover/lock indices if they're still valid after the update.
    ///
    /// - Parameters:
    ///   - grammarUnderlines: New grammar error underlines
    ///   - styleUnderlines: New style suggestion underlines
    ///   - readabilityUnderlines: New readability underlines
    func updateAll(
        grammarUnderlines: [ErrorUnderline],
        styleUnderlines: [StyleUnderline],
        readabilityUnderlines: [ReadabilityUnderline]
    ) {
        // Preserve hover/lock indices if still valid
        let hoveredGrammarIndex = preserveIndexIfValid(
            currentState.hoveredGrammarIndex,
            newCount: grammarUnderlines.count
        )
        let hoveredStyleIndex = preserveIndexIfValid(
            currentState.hoveredStyleIndex,
            newCount: styleUnderlines.count
        )
        let hoveredReadabilityIndex = preserveIndexIfValid(
            currentState.hoveredReadabilityIndex,
            newCount: readabilityUnderlines.count
        )
        let lockedHighlightIndex = preserveIndexIfValid(
            currentState.lockedHighlightIndex,
            newCount: grammarUnderlines.count
        )

        let newState = UnderlineState(
            grammarUnderlines: grammarUnderlines,
            styleUnderlines: styleUnderlines,
            readabilityUnderlines: readabilityUnderlines,
            hoveredGrammarIndex: hoveredGrammarIndex,
            hoveredStyleIndex: hoveredStyleIndex,
            hoveredReadabilityIndex: hoveredReadabilityIndex,
            lockedHighlightIndex: lockedHighlightIndex
        )

        applyState(newState)
    }

    /// Clear all state - equivalent to hiding all underlines
    func clear() {
        applyState(.empty)
    }

    /// Clear only grammar underlines, preserving readability underlines
    func clearGrammarUnderlines() {
        applyState(currentState.withGrammarUnderlinesCleared())
    }

    /// Clear only readability underlines, preserving grammar underlines
    func clearReadabilityUnderlines() {
        applyState(currentState.withReadabilityUnderlinesCleared())
    }

    // MARK: - Public API - Hover State

    /// Update hover state for grammar underlines
    /// - Parameter index: Index of hovered underline, or nil to clear hover
    func setHoveredGrammarIndex(_ index: Int?) {
        guard currentState.hoveredGrammarIndex != index else { return }

        // Validate index
        if let idx = index, !currentState.grammarUnderlines.indices.contains(idx) {
            Logger.warning("UnderlineStateManager: Invalid grammar hover index \(idx), ignoring", category: Logger.ui)
            return
        }

        applyState(currentState.withHoveredGrammarIndex(index))
    }

    /// Update hover state for style underlines
    /// - Parameter index: Index of hovered underline, or nil to clear hover
    func setHoveredStyleIndex(_ index: Int?) {
        guard currentState.hoveredStyleIndex != index else { return }

        // Validate index
        if let idx = index, !currentState.styleUnderlines.indices.contains(idx) {
            Logger.warning("UnderlineStateManager: Invalid style hover index \(idx), ignoring", category: Logger.ui)
            return
        }

        applyState(currentState.withHoveredStyleIndex(index))
    }

    /// Update hover state for readability underlines
    /// - Parameter index: Index of hovered underline, or nil to clear hover
    func setHoveredReadabilityIndex(_ index: Int?) {
        guard currentState.hoveredReadabilityIndex != index else { return }

        // Validate index
        if let idx = index, !currentState.readabilityUnderlines.indices.contains(idx) {
            Logger.warning("UnderlineStateManager: Invalid readability hover index \(idx), ignoring", category: Logger.ui)
            return
        }

        applyState(currentState.withHoveredReadabilityIndex(index))
    }

    /// Clear all hover states
    func clearHoverState() {
        if currentState.hoveredGrammarIndex == nil,
           currentState.hoveredStyleIndex == nil,
           currentState.hoveredReadabilityIndex == nil
        {
            return // Already clear
        }

        let newState = UnderlineState(
            grammarUnderlines: currentState.grammarUnderlines,
            styleUnderlines: currentState.styleUnderlines,
            readabilityUnderlines: currentState.readabilityUnderlines,
            hoveredGrammarIndex: nil,
            hoveredStyleIndex: nil,
            hoveredReadabilityIndex: nil,
            lockedHighlightIndex: currentState.lockedHighlightIndex
        )
        applyState(newState)
    }

    // MARK: - Public API - Locked Highlight

    /// Set locked highlight (persists during popover interaction)
    /// - Parameter index: Index of underline to highlight, or nil to clear
    func setLockedHighlightIndex(_ index: Int?) {
        guard currentState.lockedHighlightIndex != index else { return }

        // Validate index
        if let idx = index, !currentState.grammarUnderlines.indices.contains(idx) {
            Logger.warning("UnderlineStateManager: Invalid lock index \(idx), ignoring", category: Logger.ui)
            return
        }

        applyState(currentState.withLockedHighlightIndex(index))
    }

    /// Set locked highlight by finding the underline for a given error
    /// - Parameter error: The error to highlight
    func setLockedHighlight(for error: GrammarErrorModel?) {
        guard let error else {
            setLockedHighlightIndex(nil)
            return
        }

        // Find index of underline matching this error
        let index = currentState.grammarUnderlines.firstIndex { underline in
            underline.error.start == error.start && underline.error.end == error.end
        }
        setLockedHighlightIndex(index)
    }

    /// Clear locked highlight
    func clearLockedHighlight() {
        setLockedHighlightIndex(nil)
    }

    // MARK: - Public API - Queries

    /// Find grammar underline at a given point
    /// - Parameter point: Point in view coordinates
    /// - Returns: Index of underline at point, or nil
    func grammarUnderlineIndex(at point: CGPoint) -> Int? {
        for (index, underline) in currentState.grammarUnderlines.enumerated() {
            if underline.bounds.contains(point) {
                return index
            }
        }
        return nil
    }

    /// Find style underline at a given point
    /// - Parameter point: Point in view coordinates
    /// - Returns: Index of underline at point, or nil
    func styleUnderlineIndex(at point: CGPoint) -> Int? {
        for (index, underline) in currentState.styleUnderlines.enumerated() {
            if underline.bounds.contains(point) {
                return index
            }
        }
        return nil
    }

    /// Find readability underline at a given point
    /// - Parameter point: Point in view coordinates
    /// - Returns: Index of underline at point, or nil
    func readabilityUnderlineIndex(at point: CGPoint) -> Int? {
        for (index, underline) in currentState.readabilityUnderlines.enumerated() {
            if underline.bounds.contains(point) {
                return index
            }
        }
        return nil
    }

    // MARK: - Private Methods

    private func applyState(_ newState: UnderlineState) {
        #if DEBUG
            if !newState.validateInvariants() {
                assertionFailure("UnderlineState invariants violated!")
            }
        #endif

        // Check if state actually changed (compare counts and indices)
        let changed = !statesAreEquivalent(currentState, newState)
        currentState = newState

        if changed {
            Logger.trace(
                "UnderlineStateManager: State updated - grammar=\(newState.grammarUnderlines.count), style=\(newState.styleUnderlines.count), readability=\(newState.readabilityUnderlines.count)",
                category: Logger.ui
            )
            onStateChanged?(newState)
        }
    }

    /// Compare two states for equivalence (not full equality, just structural equivalence)
    private func statesAreEquivalent(_ lhs: UnderlineState, _ rhs: UnderlineState) -> Bool {
        // Compare counts
        guard lhs.grammarUnderlines.count == rhs.grammarUnderlines.count,
              lhs.styleUnderlines.count == rhs.styleUnderlines.count,
              lhs.readabilityUnderlines.count == rhs.readabilityUnderlines.count
        else { return false }

        // Compare hover/lock indices
        guard lhs.hoveredGrammarIndex == rhs.hoveredGrammarIndex,
              lhs.hoveredStyleIndex == rhs.hoveredStyleIndex,
              lhs.hoveredReadabilityIndex == rhs.hoveredReadabilityIndex,
              lhs.lockedHighlightIndex == rhs.lockedHighlightIndex
        else { return false }

        // For underline content, we trust that if counts match and indices match,
        // the content is likely the same (full equality would require Equatable conformance)
        return true
    }

    private func preserveIndexIfValid(_ index: Int?, newCount: Int) -> Int? {
        guard let idx = index, idx < newCount else { return nil }
        return idx
    }
}
