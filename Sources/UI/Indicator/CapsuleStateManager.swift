//
//  CapsuleStateManager.swift
//  TextWarden
//
//  Manages state for all sections of the capsule indicator
//

import Cocoa

/// Manages state for all sections of the capsule indicator (3-section design)
/// Sections: Grammar | Style+Clarity | Text Generation
@MainActor
class CapsuleStateManager {
    var grammarState: CapsuleSectionState
    var styleClarityState: CapsuleSectionState
    var textGenState: CapsuleSectionState
    var hoveredSection: CapsuleSectionType?

    /// Current readability score for badge display (nil if no score)
    private var currentReadabilityScore: Int?

    init() {
        grammarState = CapsuleSectionState(type: .grammar)
        styleClarityState = CapsuleSectionState(type: .styleClarity)
        textGenState = CapsuleSectionState(type: .textGeneration)
    }

    /// Current indicator shape based on style checking preference
    var indicatorShape: IndicatorShape {
        UserPreferences.shared.enableStyleChecking ? .capsule : .circle
    }

    /// Current capsule orientation based on indicator position
    /// This is the default orientation from preferences; actual orientation should be determined
    /// from the real indicator position relative to window bounds
    var capsuleOrientation: CapsuleOrientation {
        CapsuleOrientation.from(position: UserPreferences.shared.indicatorPosition)
    }

    /// Determine orientation from percentage position
    /// Returns vertical for side edges (left/right), horizontal for top/bottom edges
    static func orientationFromPercentagePosition(_ pos: IndicatorPositionStore.PercentagePosition) -> CapsuleOrientation {
        // Use 15% threshold for edge detection to be more forgiving
        let sideEdgeThreshold: CGFloat = 0.15
        let topBottomThreshold: CGFloat = 0.12

        let isOnLeftEdge = pos.xPercent < sideEdgeThreshold
        let isOnRightEdge = pos.xPercent > (1.0 - sideEdgeThreshold)
        let isOnTopEdge = pos.yPercent > (1.0 - topBottomThreshold)
        let isOnBottomEdge = pos.yPercent < topBottomThreshold

        Logger.debug("CapsuleStateManager: Position x=\(pos.xPercent), y=\(pos.yPercent) → left=\(isOnLeftEdge), right=\(isOnRightEdge), top=\(isOnTopEdge), bottom=\(isOnBottomEdge)", category: Logger.ui)

        // If on left or right edge, use vertical orientation
        if isOnLeftEdge || isOnRightEdge {
            return .vertical
        }
        // If on top or bottom edge, use horizontal orientation
        if isOnTopEdge || isOnBottomEdge {
            return .horizontal
        }
        // Default to vertical for corner cases
        return .vertical
    }

    /// Get all visible sections in display order (top to bottom)
    /// Order: Grammar | Style+Clarity | Text Generation
    var visibleSections: [CapsuleSectionState] {
        var sections: [CapsuleSectionState] = []

        // Grammar section is always visible when there are errors or as success state
        if grammarState.displayState != .hidden {
            sections.append(grammarState)
        }

        // Style+Clarity section is visible when style checking is enabled
        if styleClarityState.displayState != .hidden {
            sections.append(styleClarityState)
        }

        // Text generation section
        if textGenState.displayState != .hidden {
            sections.append(textGenState)
        }

        return sections
    }

    /// Calculate total height of the capsule indicator based on orientation
    var capsuleHeight: CGFloat {
        let sections = visibleSections
        guard sections.count > 1 else {
            // Single section - use circle size
            return UIConstants.indicatorSize
        }

        switch capsuleOrientation {
        case .vertical:
            // Multiple sections stacked vertically
            let sectionCount = CGFloat(sections.count)
            let totalHeight = (sectionCount * UIConstants.capsuleSectionHeight) +
                ((sectionCount - 1) * UIConstants.capsuleSectionSpacing)
            return totalHeight
        case .horizontal:
            // Fixed height for horizontal capsule
            return UIConstants.capsuleSectionHeight
        }
    }

    /// Calculate total width of the capsule indicator based on orientation
    var capsuleWidth: CGFloat {
        let sections = visibleSections
        guard sections.count > 1 else {
            // Single section - use circle size
            return UIConstants.indicatorSize
        }

        switch capsuleOrientation {
        case .vertical:
            // Fixed width for vertical capsule
            return UIConstants.capsuleWidth
        case .horizontal:
            // Multiple sections arranged horizontally
            let sectionCount = CGFloat(sections.count)
            let totalWidth = (sectionCount * UIConstants.capsuleSectionHeight) + // Section size is square
                ((sectionCount - 1) * UIConstants.capsuleSectionSpacing)
            return totalWidth
        }
    }

    /// Update grammar section state based on errors
    func updateGrammar(errors: [GrammarErrorModel]) {
        if errors.isEmpty {
            // Show success state (green tick) instead of hiding
            grammarState.displayState = .grammarSuccess
            grammarState.ringColor = .systemGreen
        } else {
            grammarState.displayState = .grammarCount(errors.count)
            grammarState.ringColor = colorForErrors(errors)
        }
    }

    /// Update style+clarity section state based on suggestions and readability
    /// - Parameters:
    ///   - suggestions: Current style suggestions (includes readability suggestions)
    ///   - isLoading: Whether style check is in progress
    ///   - hasChecked: Whether a style check has been completed (show success only if checked with no findings)
    ///   - readabilityScore: Current readability score for badge display (nil if no score)
    func updateStyleClarity(suggestions: [StyleSuggestionModel], isLoading: Bool, hasChecked: Bool = false, readabilityScore: Int? = nil) {
        currentReadabilityScore = readabilityScore

        if isLoading {
            styleClarityState.displayState = .styleClarityLoading
            styleClarityState.ringColor = .purple
        } else if suggestions.isEmpty {
            if hasChecked {
                // Style check completed with no findings - show success
                styleClarityState.displayState = .styleClaritySuccess
                styleClarityState.ringColor = .purple
            } else {
                // No style check yet - show sparkle (ready state, no animation)
                styleClarityState.displayState = .styleClarityIdle
                styleClarityState.ringColor = .purple
            }
        } else {
            styleClarityState.displayState = .styleClarityCount(suggestions.count, readabilityScore)
            styleClarityState.ringColor = .purple
        }
    }

    /// Legacy: Update style section (delegates to updateStyleClarity)
    func updateStyle(suggestions: [StyleSuggestionModel], isLoading: Bool, hasChecked: Bool = false) {
        updateStyleClarity(suggestions: suggestions, isLoading: isLoading, hasChecked: hasChecked, readabilityScore: currentReadabilityScore)
    }

    /// Update text generation section state
    /// - Parameter isGenerating: Whether text generation is in progress
    func updateTextGeneration(isGenerating: Bool) {
        if isGenerating {
            textGenState.displayState = .textGenActive
            textGenState.ringColor = .systemBlue
        } else {
            // Always show idle state when style checking is enabled (text gen available)
            if UserPreferences.shared.enableStyleChecking {
                textGenState.displayState = .textGenIdle
                textGenState.ringColor = .systemBlue
            } else {
                textGenState.displayState = .hidden
            }
        }
    }

    /// Update readability score for badge display
    /// - Parameters:
    ///   - result: The readability calculation result, or nil if text is too short
    ///   - analysis: Optional sentence-level analysis with target audience info
    func updateReadability(result: ReadabilityResult?, analysis: TextReadabilityAnalysis? = nil) {
        guard UserPreferences.shared.readabilityEnabled else {
            currentReadabilityScore = nil
            return
        }

        if let result {
            currentReadabilityScore = result.displayScore
        } else {
            currentReadabilityScore = nil
        }
    }

    /// Set hover state for a section
    func setHovered(_ section: CapsuleSectionType?) {
        hoveredSection = section
        grammarState.isHovered = section == .grammar
        styleClarityState.isHovered = section == .styleClarity
        textGenState.isHovered = section == .textGeneration
    }

    /// Get color for grammar errors based on severity
    private func colorForErrors(_ errors: [GrammarErrorModel]) -> NSColor {
        if errors.contains(where: { $0.category == "Spelling" || $0.category == "Typo" }) {
            .systemRed
        } else if errors.contains(where: {
            $0.category == "Grammar" || $0.category == "Agreement" || $0.category == "Punctuation"
        }) {
            .systemOrange
        } else {
            .systemBlue
        }
    }
}
