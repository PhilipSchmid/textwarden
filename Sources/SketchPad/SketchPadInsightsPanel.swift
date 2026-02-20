//
//  SketchPadInsightsPanel.swift
//  TextWarden
//
//  Right panel showing readability score, insights, and AI assistant
//

import STTextView
import SwiftUI

/// Right panel for Sketch Pad with insights and AI assistant
struct SketchPadInsightsPanel: View {
    @ObservedObject var viewModel: SketchPadViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Fixed top section: Readability Score
            VStack(alignment: .leading, spacing: 0) {
                ReadabilityScoreSection(
                    documentResult: viewModel.readabilityResult,
                    selectionResult: viewModel.selectionReadabilityResult,
                    isShowingSelection: viewModel.isShowingSelectionReadability,
                    documentTips: viewModel.documentReadabilityTips,
                    selectionTips: viewModel.selectionReadabilityTips,
                    isLoadingTips: viewModel.isLoadingReadabilityTips
                )
                .padding(16)

                Divider()
            }
            .fixedSize(horizontal: false, vertical: true)

            // Expandable middle section: Insights (scrollable, fills available space)
            ScrollView {
                InsightsSection(
                    insights: viewModel.unifiedInsights,
                    dismissedCount: viewModel.dismissedSuggestionsCount,
                    isAnalyzingStyle: viewModel.isAnalyzingStyle,
                    selectedId: $viewModel.selectedInsightId,
                    onApply: { insight, suggestion in
                        viewModel.applyFix(for: insight, withSuggestion: suggestion)
                    },
                    onIgnore: { insight in
                        viewModel.ignoreSuggestion(insight)
                    },
                    onIgnoreRule: { insight in
                        viewModel.ignoreRule(for: insight)
                    },
                    onAddToDictionary: { insight in
                        viewModel.addToDictionary(for: insight)
                    },
                    onRegenerate: { insight in
                        await viewModel.regenerateStyleSuggestionFromInsight(insight)
                    },
                    onResetDismissed: {
                        viewModel.resetDismissedSuggestions()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: .infinity) // Expand to fill available space

            // Fixed bottom section: AI Assistant
            VStack(spacing: 0) {
                Divider()

                AIAssistantSection(viewModel: viewModel)
                    .padding(16)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Readability Score Section

private struct ReadabilityScoreSection: View {
    let documentResult: ReadabilityResult?
    let selectionResult: ReadabilityResult?
    let isShowingSelection: Bool
    let documentTips: [String]
    let selectionTips: [String]
    let isLoadingTips: Bool

    /// The result to display (selection takes priority when available)
    private var displayResult: ReadabilityResult? {
        isShowingSelection ? selectionResult : documentResult
    }

    /// The tips to display (selection takes priority when available)
    private var displayTips: [String] {
        isShowingSelection ? selectionTips : documentTips
    }

    /// Label indicating what the score represents
    private var scopeLabel: String {
        isShowingSelection ? "Selection" : "Document"
    }

    /// Tooltip explaining the Flesch Reading Ease algorithm
    private let algorithmTooltip = """
    Flesch Reading Ease Score (0-100)

    Based on sentence length and syllable count.
    Higher scores indicate easier text to read.

    Score Range → Target Audience
    ─────────────────────────────
    65+  Accessible (everyone)
    50+  General (average adult)
    40+  Professional (business)
    30+  Technical (specialized)
    20+  Academic (graduate-level)

    Your target audience setting determines
    which sentences are flagged as complex.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("READABILITY SCORE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .help(algorithmTooltip)

                Spacer()

                if let result = displayResult {
                    QualityBadge(score: result.score)
                }
            }

            if let result = displayResult {
                HStack(alignment: .center, spacing: 12) {
                    // Circular score indicator - compact size
                    CircularScoreView(score: Int(result.score))
                        .frame(width: 60, height: 60)

                    // Score description on the right, centered vertically
                    VStack(alignment: .leading, spacing: 2) {
                        // Scope label (Document/Selection)
                        HStack(spacing: 4) {
                            Text(scopeLabel)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(isShowingSelection ? .accentColor : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isShowingSelection ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                                )

                            Text(result.label)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }

                        Text(scoreDescription(for: result.score))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isShowingSelection)
                .animation(.easeInOut(duration: 0.2), value: result.score)

                // AI Insights section (auto-regenerates when text changes, like style suggestions)
                AIInsightsSection(
                    tips: displayTips,
                    isLoading: isLoadingTips,
                    score: result.score
                )
            } else {
                Text("Start typing to see readability analysis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func scoreDescription(for score: Double) -> String {
        switch score {
        case 80...:
            "Easy to read for most audiences"
        case 60 ..< 80:
            "Suitable for general audiences"
        case 40 ..< 60:
            "May require some effort to read"
        default:
            "Consider simplifying the text"
        }
    }
}

// MARK: - AI Insights Section

private struct AIInsightsSection: View {
    let tips: [String]
    let isLoading: Bool
    let score: Double

    /// Static fallback tips based on score (used when AI tips unavailable)
    private var staticTips: [String] {
        switch score {
        case 70...:
            [] // Good readability, no tips needed
        case 60 ..< 70:
            [
                "Consider breaking longer sentences into shorter ones",
                "Replace some complex words with simpler alternatives",
            ]
        case 50 ..< 60:
            [
                "Aim for sentences of 15-20 words",
                "Replace multi-syllable words where possible",
                "Break up long paragraphs",
            ]
        default:
            [
                "Use shorter, simpler sentences",
                "Replace jargon with everyday words",
                "Consider your target audience's reading level",
            ]
        }
    }

    /// Tips to display (AI tips if available, otherwise static)
    private var displayTips: [String] {
        tips.isEmpty ? staticTips : tips
    }

    /// Whether we're showing AI-generated tips
    private var isAIGenerated: Bool {
        !tips.isEmpty
    }

    /// Show "looks good" when score is good and no tips
    private var showLooksGood: Bool {
        !isLoading && displayTips.isEmpty && score >= 70
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Loading state - elegant card for readability analysis
            if isLoading {
                AnalyzingCard.readability
            } else if showLooksGood {
                // Good readability - show success message (matches Insights "Looking good!" card)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Looking good!")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("No readability issues found.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                        )
                )
            } else if !displayTips.isEmpty {
                // Header - unified style with different colors for AI vs static
                Label(
                    isAIGenerated ? "AI Insights" : "Tips",
                    systemImage: isAIGenerated ? "sparkles" : "lightbulb"
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isAIGenerated ? .purple : .orange)

                // Tips list - unified card style (full width to match other insight cards)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(displayTips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundColor(isAIGenerated ? .yellow : .orange)
                                .frame(width: 12, alignment: .center)
                                .padding(.top, 2)

                            Text(tip)
                                .font(.caption)
                                .foregroundColor(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isAIGenerated ? Color.purple.opacity(0.08) : Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    (isAIGenerated ? Color.purple : Color.orange).opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: displayTips.count)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Analyzing Card

/// Elegant loading card for AI analysis - configurable title and subtitle
private struct AnalyzingCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let colors: (primary: Color, secondary: Color)

    /// Readability analysis variant
    static var readability: AnalyzingCard {
        AnalyzingCard(
            title: "Analyzing readability",
            subtitle: "Building readability score...",
            icon: "text.magnifyingglass",
            colors: (.purple, .blue)
        )
    }

    /// Style/grammar analysis variant
    static var style: AnalyzingCard {
        AnalyzingCard(
            title: "Analyzing text style",
            subtitle: "Checking grammar and style...",
            icon: "sparkles",
            colors: (.purple, .blue)
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            // Animated icon
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(
                    LinearGradient(
                        colors: [colors.primary, colors.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            colors.primary.opacity(0.08),
                            colors.secondary.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            colors.primary.opacity(0.2),
                            colors.secondary.opacity(0.1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Quality Badge

private struct QualityBadge: View {
    let score: Double

    private var quality: (text: String, color: Color) {
        switch score {
        case 80...:
            ("EXCELLENT", .green)
        case 60 ..< 80:
            ("GOOD", .blue)
        case 40 ..< 60:
            ("FAIR", .orange)
        default:
            ("NEEDS WORK", .red)
        }
    }

    var body: some View {
        Text(quality.text)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(quality.color)
            .cornerRadius(4)
    }
}

// MARK: - Circular Score View

private struct CircularScoreView: View {
    let score: Int

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 5)

            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    scoreColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Score text
            Text("\(score)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
    }

    private var scoreColor: Color {
        switch score {
        case 80...:
            .green
        case 60 ..< 80:
            .blue
        case 40 ..< 60:
            .orange
        default:
            .red
        }
    }
}

// MARK: - Insights Section

private struct InsightsSection: View {
    let insights: [UnifiedSuggestion]
    let dismissedCount: Int
    let isAnalyzingStyle: Bool
    @Binding var selectedId: String?
    let onApply: (UnifiedSuggestion, String?) -> Void
    let onIgnore: (UnifiedSuggestion) -> Void
    let onIgnoreRule: (UnifiedSuggestion) -> Void
    let onAddToDictionary: (UnifiedSuggestion) -> Void
    let onRegenerate: (UnifiedSuggestion) async -> Void
    let onResetDismissed: () -> Void

    /// Create regenerate action for style/clarity insights, nil for others
    private func makeRegenerateAction(for insight: UnifiedSuggestion) -> (() async -> Void)? {
        guard insight.category == .style || insight.category == .clarity else {
            return nil
        }
        return { await onRegenerate(insight) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with count badge
            HStack {
                Text("INSIGHTS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                if !insights.isEmpty {
                    Text("\(insights.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(10)
                }
            }

            if !insights.isEmpty {
                // Show insights (even if style analysis is still running)
                // Insight cards (parent ScrollView handles scrolling)
                VStack(spacing: 8) {
                    // Show style analysis loading indicator at top when analyzing
                    if isAnalyzingStyle {
                        AnalyzingCard.style
                    }

                    ForEach(insights) { insight in
                        InsightCard(
                            insight: insight,
                            isSelected: selectedId == insight.id,
                            onSelect: { selectedId = insight.id },
                            onApply: { suggestion in onApply(insight, suggestion) },
                            onIgnore: { onIgnore(insight) },
                            onIgnoreRule: { onIgnoreRule(insight) },
                            onAddToDictionary: insight.category == .correctness ? { onAddToDictionary(insight) } : nil,
                            onRegenerate: makeRegenerateAction(for: insight)
                        )
                    }
                }
            } else if isAnalyzingStyle {
                // No insights yet, style analysis in progress - show beautiful card
                AnalyzingCard.style
            } else {
                // No insights and not analyzing - success state card
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(dismissedCount > 0 ? "All clear!" : "Looking good!")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(dismissedCount > 0
                                ? "You've addressed all the suggestions."
                                : "No issues found in your text.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                        )
                )
            }

            // Always show restore option when there are dismissed suggestions
            if dismissedCount > 0 {
                DismissedIndicator(count: dismissedCount, action: onResetDismissed)
            }
        }
    }
}

// MARK: - Dismissed Indicator

/// Elegant card-style indicator showing dismissed suggestions that can be restored
/// Matches the visual style of the "All clear!" card for consistency
private struct DismissedIndicator: View {
    let count: Int
    let action: () -> Void
    @State private var isHovering = false

    private var accentColor: Color {
        isHovering ? .accentColor : .secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Circular restore icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.1))
                        .frame(width: 24, height: 24)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(accentColor.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count) dismissed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accentColor.opacity(0.9))

                    Text("Click to restore")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor.opacity(0.6))
                }

                Spacer()

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accentColor.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.opacity(isHovering ? 0.08 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(accentColor.opacity(isHovering ? 0.25 : 0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Restore \(count) dismissed suggestion\(count == 1 ? "" : "s")")
    }
}

// MARK: - Insight Card

/// Card component for displaying insights in the sidebar
/// Compact design with left border indicator and inline suggestion display
private struct InsightCard: View {
    let insight: UnifiedSuggestion
    let isSelected: Bool
    let onSelect: () -> Void
    let onApply: (String?) -> Void // Pass specific suggestion text, nil for default
    let onIgnore: () -> Void
    let onIgnoreRule: () -> Void
    let onAddToDictionary: (() -> Void)?
    let onRegenerate: (() async -> Void)? // Optional regenerate for style suggestions

    @State private var showMoreMenu = false
    @State private var isRegenerating = false

    /// All available suggestions (primary + alternatives)
    private var allSuggestions: [String] {
        var suggestions: [String] = []
        if let primary = insight.suggestedText {
            suggestions.append(primary)
        }
        if let alternatives = insight.alternatives {
            for alt in alternatives where !suggestions.contains(alt) {
                suggestions.append(alt)
            }
        }
        return suggestions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Category indicator - left border bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(categoryColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    // Header: Category + Position
                    HStack {
                        Text(categoryLabel)
                            .font(.caption)
                            .fontWeight(.semibold)

                        Spacer()

                        Text("Pos \(insight.start)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Message
                    Text(insight.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Show suggestions - different layout for style vs grammar
                    if !allSuggestions.isEmpty {
                        if insight.category == .style || insight.category == .clarity {
                            // Style/clarity suggestions: diff display with accept/reject/regenerate buttons
                            StyleSuggestionContent(
                                insight: insight,
                                onApply: { onApply(allSuggestions.first) },
                                onReject: onIgnore,
                                onRegenerate: onRegenerate,
                                isRegenerating: $isRegenerating
                            )
                            .padding(.top, 4)
                        } else {
                            // Grammar suggestions: original layout with pills
                            VStack(alignment: .leading, spacing: 8) {
                                // Original text with arrow
                                HStack(spacing: 6) {
                                    Text(insight.originalText)
                                        .font(.system(size: 13, weight: .medium))
                                        .strikethrough()
                                        .foregroundColor(.red.opacity(0.8))
                                        .lineLimit(2)

                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }

                                // Suggestion buttons - styled as pill buttons
                                FlowLayout(spacing: 8) {
                                    ForEach(allSuggestions, id: \.self) { suggestion in
                                        SuggestionButton(text: suggestion) {
                                            onApply(suggestion)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    // Action bar - Dismiss (for grammar only) and More menu
                    // Style/clarity insights have their own dismiss button in StyleSuggestionContent
                    if insight.category == .correctness || hasSecondaryActions {
                        GrammarActionBar(
                            showDismiss: insight.category == .correctness,
                            showMoreMenu: hasSecondaryActions,
                            isMoreMenuExpanded: $showMoreMenu,
                            onDismiss: onIgnore
                        )
                        .padding(.top, 8)
                    }

                    // Dropdown menu panel (appears below buttons)
                    if showMoreMenu {
                        VStack(alignment: .leading, spacing: 0) {
                            if insight.lintId != nil {
                                MoreMenuRow(
                                    icon: "nosign",
                                    title: "Turn off suggestions like this"
                                ) {
                                    showMoreMenu = false
                                    onIgnoreRule()
                                }
                            }

                            if insight.category == .correctness, let addAction = onAddToDictionary {
                                MoreMenuRow(
                                    icon: "text.badge.plus",
                                    title: "Add to dictionary"
                                ) {
                                    showMoreMenu = false
                                    addAction()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    /// Whether the insight has secondary actions for the ellipsis menu
    private var hasSecondaryActions: Bool {
        // Has Ignore Rule option (grammar/spelling rules)
        if insight.lintId != nil { return true }
        // Has Add to Dictionary option (spelling)
        if insight.category == .correctness, onAddToDictionary != nil { return true }
        return false
    }

    private var categoryColor: Color {
        switch insight.category {
        case .correctness:
            .red
        case .style:
            .purple
        case .clarity:
            .blue
        }
    }

    private var categoryLabel: String {
        switch insight.category {
        case .correctness:
            "Spelling"
        case .style:
            "Style"
        case .clarity:
            "Clarity"
        }
    }
}

// MARK: - More Menu Row

/// Row item for the dropdown more menu
private struct MoreMenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Style Suggestion Content

/// Compact content view for style/clarity suggestions with diff display and action buttons
private struct StyleSuggestionContent: View {
    let insight: UnifiedSuggestion
    let onApply: () -> Void
    let onReject: () -> Void
    let onRegenerate: (() async -> Void)?
    @Binding var isRegenerating: Bool

    @State private var hoveredButton: String?

    /// Maximum characters to show before truncating
    private let maxDisplayChars = 80

    /// Truncate text with ellipsis if too long
    private func truncate(_ text: String) -> String {
        if text.count <= maxDisplayChars {
            return text
        }
        let index = text.index(text.startIndex, offsetBy: maxDisplayChars)
        return String(text[..<index]) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Diff display - use diff segments if available, otherwise simple before/after
            if let diff = insight.diff, !diff.isEmpty {
                // Use diff segments for proper highlighting
                CompactDiffView(
                    original: truncate(insight.originalText),
                    suggested: truncate(insight.suggestedText ?? ""),
                    diff: diff
                )
                .font(.system(size: 12))
            } else {
                // Fallback: simple before/after
                VStack(alignment: .leading, spacing: 4) {
                    // Original (red strikethrough)
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 10))
                            .padding(.top, 2)

                        Text(truncate(insight.originalText))
                            .font(.system(size: 12))
                            .strikethrough()
                            .foregroundColor(.red.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Suggested (green)
                    if let suggested = insight.suggestedText, !suggested.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                                .padding(.top, 2)

                            Text(truncate(suggested))
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Action buttons: Accept / Reject
            HStack(spacing: 8) {
                // Accept button
                Button(action: onApply) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Accept")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(hoveredButton == "accept" ? .white : .green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredButton == "accept" ? Color.green : Color.green.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredButton = hovering ? "accept" : nil
                    }
                }

                // Dismiss button
                Button(action: onReject) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Dismiss")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(hoveredButton == "reject" ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredButton == "reject" ? Color.secondary : Color.secondary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredButton = hovering ? "reject" : nil
                    }
                }

                Spacer()

                // Regenerate button (if available)
                if let onRegenerate {
                    Button {
                        isRegenerating = true
                        Task {
                            await onRegenerate()
                            await MainActor.run {
                                isRegenerating = false
                            }
                        }
                    } label: {
                        Group {
                            if isRegenerating {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.trianglehead.2.clockwise")
                                    .font(.system(size: 10))
                            }
                        }
                        .foregroundColor(hoveredButton == "regenerate" ? .white : .purple)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(hoveredButton == "regenerate" ? Color.purple : Color.purple.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRegenerating)
                    .help("Generate alternative suggestion")
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredButton = hovering ? "regenerate" : nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Suggestion Button

/// Styled button for applying a suggestion with hover effect
private struct SuggestionButton: View {
    let text: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text(text)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.accentColor : Color.accentColor.opacity(0.15))
            )
            .foregroundColor(isHovering ? .white : .accentColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Grammar Action Bar

/// Unified action bar for grammar/spelling suggestions matching the style suggestion design
private struct GrammarActionBar: View {
    let showDismiss: Bool
    let showMoreMenu: Bool
    @Binding var isMoreMenuExpanded: Bool
    let onDismiss: () -> Void

    @State private var hoveredButton: String?

    var body: some View {
        HStack(spacing: 8) {
            // Dismiss button - styled like style suggestions
            if showDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Dismiss")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(hoveredButton == "dismiss" ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredButton == "dismiss" ? Color.secondary : Color.secondary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredButton = hovering ? "dismiss" : nil
                    }
                }
            }

            Spacer()

            // More options button - circular like regenerate button
            if showMoreMenu {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isMoreMenuExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(hoveredButton == "more" || isMoreMenuExpanded ? .white : .secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(hoveredButton == "more" || isMoreMenuExpanded ? Color.secondary : Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredButton = hovering ? "more" : nil
                    }
                }
            }
        }
    }
}

// MARK: - AI Assistant Section

private struct AIAssistantSection: View {
    @ObservedObject var viewModel: SketchPadViewModel

    @State private var isProcessing = false

    // Quick Actions state
    @State private var loadingAction: WritingStyle?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingReplacementConfirmation = false
    @State private var pendingTone: WritingStyle?

    /// Fixed max height for the text editor - keeps Quick Actions visible
    private let maxEditorHeight: CGFloat = 80

    /// Binding to the view model's AI prompt (cached per document)
    private var aiPrompt: Binding<String> {
        Binding(
            get: { viewModel.aiAssistantPrompt },
            set: { viewModel.aiAssistantPrompt = $0 }
        )
    }

    /// Whether text is currently selected in the editor
    private var hasSelection: Bool {
        guard let stTextView = viewModel.stTextView else { return false }
        let selectedRanges = stTextView.textLayoutManager.textSelections.flatMap(\.textRanges)
        guard let firstRange = selectedRanges.first,
              let textContentStorage = stTextView.textContentManager as? NSTextContentStorage,
              let documentRange = textContentStorage.documentRange.location as NSTextLocation?
        else { return false }
        let startOffset = textContentStorage.offset(from: documentRange, to: firstRange.location)
        let endOffset = textContentStorage.offset(from: documentRange, to: firstRange.endLocation)
        return (endOffset - startOffset) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Assistant")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()
            }

            // Prompt input - auto-expanding text editor
            VStack(alignment: .leading, spacing: 8) {
                DynamicHeightTextEditor(
                    text: aiPrompt,
                    placeholder: "Ask AI to rewrite, shorten, expand...",
                    minHeight: 60,
                    maxHeight: maxEditorHeight,
                    onSubmit: {
                        if !aiPrompt.wrappedValue.isEmpty, !isProcessing {
                            Task {
                                await runCustomPrompt()
                            }
                        }
                    }
                )

                // Generate button
                Button {
                    Task {
                        await runCustomPrompt()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 14, height: 14)
                            Text("Generating...")
                        } else {
                            Image(systemName: "sparkles")
                            Text("Generate")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(aiPrompt.wrappedValue.isEmpty || isProcessing)
            }

            Divider()
                .padding(.vertical, 4)

            // Quick Actions - 2x2 grid layout
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    CompactToneButton(
                        title: "Professional",
                        icon: "briefcase",
                        tooltip: "Rewrite in a formal, professional tone",
                        isLoading: loadingAction == .formal
                    ) {
                        Task { await applyToneWithConfirmation(.formal) }
                    }
                    CompactToneButton(
                        title: "Friendly",
                        icon: "hand.wave",
                        tooltip: "Rewrite in a warm, conversational tone",
                        isLoading: loadingAction == .informal
                    ) {
                        Task { await applyToneWithConfirmation(.informal) }
                    }
                }
                HStack(spacing: 6) {
                    CompactToneButton(
                        title: "Concise",
                        icon: "arrow.down.left.and.arrow.up.right",
                        tooltip: "Shorten while keeping the main message",
                        isLoading: loadingAction == .concise
                    ) {
                        Task { await applyToneWithConfirmation(.concise) }
                    }
                    CompactToneButton(
                        title: "Refine",
                        icon: "wand.and.stars",
                        tooltip: "Improve clarity and flow",
                        isLoading: loadingAction == .default
                    ) {
                        Task { await applyToneWithConfirmation(.default) }
                    }
                }
            }

            // Status message feedback
            if let message = statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(statusIsError ? .orange : .green)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(statusIsError ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: statusMessage)
        .alert("Replace Entire Document?", isPresented: $showingReplacementConfirmation) {
            Button("Cancel", role: .cancel) { pendingTone = nil }
            Button("Replace") {
                if let tone = pendingTone {
                    Task { await applyTone(tone) }
                }
                pendingTone = nil
            }
        } message: {
            Text("No text is selected. This action may rewrite your entire document. You can undo this change.")
        }
    }

    private func runCustomPrompt() async {
        let promptText = aiPrompt.wrappedValue
        guard !promptText.isEmpty else { return }

        isProcessing = true
        defer { isProcessing = false }

        // Get text to process - can be empty for "generate from scratch" prompts
        let textToProcess = getTextToProcess()

        Logger.info("Running custom AI prompt on \(textToProcess.count) characters", category: Logger.ui)

        // Check macOS version and run AI generation
        if #available(macOS 26.0, *) {
            let fmEngine = FoundationModelsEngine()
            fmEngine.checkAvailability()

            guard fmEngine.status.isAvailable else {
                Logger.warning("Apple Intelligence not available: \(fmEngine.status.userMessage)", category: Logger.ui)
                return
            }

            do {
                // Create context - use .none source for empty documents (generate from scratch)
                let context = GenerationContext(
                    selectedText: textToProcess.isEmpty ? nil : textToProcess,
                    surroundingText: nil,
                    fullTextLength: viewModel.plainTextContent.count,
                    cursorPosition: nil,
                    source: textToProcess.isEmpty ? .none : .selection
                )

                // Convert display name to WritingStyle enum
                let styleName = UserPreferences.shared.selectedWritingStyle
                let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default

                // Instruction with limited formatting (plain text, headings, lists only)
                let enhancedInstruction = """
                \(promptText)

                FORMATTING: Output plain text only. You may use:
                - # headings for titles/sections (# for H1, ## for H2, ### for H3)
                - Bullet lists using - or *
                - Numbered lists using 1. 2. 3.
                Do NOT use **bold**, *italic*, `code`, or > quotes. Keep it simple.
                """

                let result = try await fmEngine.generateText(
                    instruction: enhancedInstruction,
                    context: context,
                    style: style
                )
                applyAIResult(result, useMarkdown: true)
                aiPrompt.wrappedValue = "" // Clear prompt after successful generation
            } catch {
                Logger.error("AI generation failed: \(error.localizedDescription)", category: Logger.ui)
            }
        } else {
            Logger.warning("AI Assistant requires macOS 26.0 or later", category: Logger.ui)
        }
    }

    /// Check if confirmation is needed and apply tone, or show confirmation dialog
    private func applyToneWithConfirmation(_ style: WritingStyle) async {
        // Check if we need confirmation: no selection AND document has > 100 characters
        let needsConfirmation = !hasSelection && viewModel.plainTextContent.count > 100

        if needsConfirmation {
            // Store the pending action and show confirmation
            pendingTone = style
            showingReplacementConfirmation = true
        } else {
            // Apply directly without confirmation
            await applyTone(style)
        }
    }

    /// Show status message that auto-dismisses
    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError

        // Auto-dismiss after delay
        let dismissDelay: UInt64 = isError ? 5_000_000_000 : 3_000_000_000 // 5s for errors, 3s for success
        Task {
            try? await Task.sleep(nanoseconds: dismissDelay)
            await MainActor.run {
                // Only clear if this is still the same message
                if statusMessage == message {
                    statusMessage = nil
                }
            }
        }
    }

    private func applyTone(_ style: WritingStyle) async {
        loadingAction = style
        defer { loadingAction = nil }

        let textToProcess = getTextToProcess()
        guard !textToProcess.isEmpty else {
            Logger.warning("No text to process for tone change", category: Logger.ui)
            showStatus("No text to process", isError: true)
            return
        }

        Logger.info("Applying tone '\(style)' to \(textToProcess.count) characters", category: Logger.ui)

        // Check macOS version and run tone transformation
        if #available(macOS 26.0, *) {
            let fmEngine = FoundationModelsEngine()
            fmEngine.checkAvailability()

            guard fmEngine.status.isAvailable else {
                Logger.warning("Apple Intelligence not available: \(fmEngine.status.userMessage)", category: Logger.ui)
                showStatus("Apple Intelligence is not available", isError: true)
                return
            }

            do {
                // Use generateText with a tone-specific instruction
                let instruction = toneInstruction(for: style)
                let context = GenerationContext(
                    selectedText: textToProcess,
                    surroundingText: nil,
                    fullTextLength: viewModel.plainTextContent.count,
                    cursorPosition: nil,
                    source: .selection
                )

                let result = try await fmEngine.generateText(
                    instruction: instruction,
                    context: context,
                    style: style
                )
                applyAIResult(result, useMarkdown: true)
                showStatus("Text updated successfully", isError: false)
            } catch {
                Logger.error("Tone transformation failed: \(error.localizedDescription)", category: Logger.ui)
                showStatus("Failed to transform text", isError: true)
            }
        } else {
            Logger.warning("AI Assistant requires macOS 26.0 or later", category: Logger.ui)
            showStatus("Requires macOS 26 or later", isError: true)
        }
    }

    /// Get instruction for tone transformation
    private func toneInstruction(for style: WritingStyle) -> String {
        let baseInstruction = switch style {
        case .formal:
            "Rewrite the following text in a more professional and formal tone. Keep the same meaning but use more formal language."
        case .informal:
            "Rewrite the following text in a friendly and casual tone. Keep the same meaning but make it more approachable."
        case .concise:
            "Rewrite the following text to be more concise. Remove unnecessary words and make it shorter while keeping the core message."
        default:
            "Refine the following text for clarity and flow. Fix any awkward phrasing without changing the overall tone."
        }

        // Add formatting guidance (plain text, headings, lists only)
        return """
        \(baseInstruction)

        FORMATTING: Output plain text only. You may use:
        - # headings for titles/sections
        - Bullet lists using - or *
        - Numbered lists using 1. 2. 3.
        Do NOT use **bold**, *italic*, `code`, or > quotes. Keep it simple.
        """
    }

    /// Get text to process - selected text if any, otherwise entire document
    private func getTextToProcess() -> String {
        guard let stTextView = viewModel.stTextView else {
            return viewModel.plainTextContent
        }

        let currentText = stTextView.text ?? ""
        let selectedRanges = stTextView.textLayoutManager.textSelections.flatMap(\.textRanges)

        if let firstRange = selectedRanges.first,
           let textContentStorage = stTextView.textContentManager as? NSTextContentStorage,
           let documentRange = textContentStorage.documentRange.location as NSTextLocation?
        {
            let startOffset = textContentStorage.offset(from: documentRange, to: firstRange.location)
            let endOffset = textContentStorage.offset(from: documentRange, to: firstRange.endLocation)
            let length = endOffset - startOffset

            if length > 0 {
                let startIndex = currentText.index(currentText.startIndex, offsetBy: startOffset)
                let endIndex = currentText.index(startIndex, offsetBy: length)
                return String(currentText[startIndex ..< endIndex])
            }
        }
        return currentText
    }

    /// Apply AI result - replace selected text or entire document
    /// - Parameters:
    ///   - result: The AI-generated text
    ///   - useMarkdown: Unused - kept for API compatibility (STTextView uses plain markdown text)
    private func applyAIResult(_ result: String, useMarkdown _: Bool = false) {
        guard let stTextView = viewModel.stTextView else {
            Logger.warning("No text view available to apply AI result", category: Logger.ui)
            return
        }
        applyAIResultToSTTextView(result, textView: stTextView)
    }

    /// Whitespace characters including NBSPs that AI models sometimes add
    private static let aiWhitespaceCharacters: CharacterSet = {
        var chars = CharacterSet.whitespacesAndNewlines
        if let nbsp = Unicode.Scalar(0x00A0) { chars.insert(nbsp) } // NBSP
        if let figureSpace = Unicode.Scalar(0x2007) { chars.insert(figureSpace) } // Figure space
        if let narrowNbsp = Unicode.Scalar(0x202F) { chars.insert(narrowNbsp) } // Narrow NBSP
        return chars
    }()

    /// Apply AI result to STTextView (plain markdown text)
    /// Uses insertText to properly register with the undo manager
    private func applyAIResultToSTTextView(_ result: String, textView: STTextView) {
        // Trim trailing whitespace including NBSPs that AI sometimes adds
        var trimmedResult = result
        while let last = trimmedResult.unicodeScalars.last, Self.aiWhitespaceCharacters.contains(last) {
            trimmedResult.removeLast()
        }

        let currentText = textView.text ?? ""
        let selectedRanges = textView.textLayoutManager.textSelections.flatMap(\.textRanges)

        // Determine the replacement range
        var replacementRange: NSRange

        // Get the first selection range
        if let firstRange = selectedRanges.first,
           let textContentStorage = textView.textContentManager as? NSTextContentStorage,
           let documentRange = textContentStorage.documentRange.location as NSTextLocation?
        {
            // Convert NSTextRange to NSRange
            let startOffset = textContentStorage.offset(from: documentRange, to: firstRange.location)
            let endOffset = textContentStorage.offset(from: documentRange, to: firstRange.endLocation)
            let selectedRange = NSRange(location: startOffset, length: endOffset - startOffset)

            if selectedRange.length > 0 {
                // Replace selected text
                replacementRange = selectedRange
            } else {
                // No selection - replace entire document
                replacementRange = NSRange(location: 0, length: currentText.utf16.count)
            }
        } else {
            // No selection info available, replace entire content
            replacementRange = NSRange(location: 0, length: currentText.utf16.count)
        }

        // Use insertText to properly register with the undo manager
        // This makes the change undoable with Cmd+Z
        textView.insertText(trimmedResult, replacementRange: replacementRange)

        // Sync to view model
        viewModel.plainTextContentInternal = textView.text ?? ""

        // Force the text view to refresh its display immediately
        textView.needsDisplay = true
        textView.needsLayout = true
        textView.layoutSubtreeIfNeeded()

        // Also invalidate the text layout to ensure proper rendering
        textView.textLayoutManager.textViewportLayoutController.layoutViewport()

        Logger.info("Applied AI result to STTextView (\(trimmedResult.count) characters)", category: Logger.ui)
    }
}

// MARK: - Compact Tone Button

/// Compact pill-style button for Quick Actions
private struct CompactToneButton: View {
    let title: String
    let icon: String
    let tooltip: String
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(isLoading ? "..." : title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .foregroundColor(isHovering ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help(tooltip)
    }
}

// MARK: - Dynamic Height Text Editor

/// A text editor that grows with content up to a maximum height, then scrolls
private struct DynamicHeightTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSubmit: () -> Void

    @State private var contentHeight: CGFloat = 0

    private var editorHeight: CGFloat {
        max(minHeight, min(contentHeight, maxHeight))
    }

    private var shouldScroll: Bool {
        contentHeight > maxHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollIndicators(shouldScroll ? .automatic : .hidden)
                .scrollDisabled(!shouldScroll)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(height: editorHeight)
                .background(
                    // Measure actual text content height
                    GeometryReader { outerGeometry in
                        Text(text.isEmpty ? " " : text)
                            .font(.body)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: outerGeometry.size.width - 16, alignment: .leading) // Match TextEditor padding
                            .padding(.vertical, 8)
                            .background(
                                GeometryReader { innerGeometry in
                                    Color.clear.preference(
                                        key: ContentHeightKey.self,
                                        value: innerGeometry.size.height
                                    )
                                }
                            )
                            .hidden()
                    }
                )
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    // Placeholder
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.leading, 13)
                            .padding(.top, 9)
                            .allowsHitTesting(false)
                    }
                }
                .onKeyPress(keys: [.return], phases: .down) { keyPress in
                    if keyPress.modifiers.contains(.shift) {
                        return .ignored
                    }
                    onSubmit()
                    return .handled
                }
        }
        .onPreferenceChange(ContentHeightKey.self) { height in
            contentHeight = height
        }
        .animation(.easeInOut(duration: 0.1), value: editorHeight)
    }
}

/// Preference key for measuring content height
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
