//
//  SketchPadEditor.swift
//  TextWarden
//
//  SwiftUI TextEditor wrapper for rich text editing with underline overlay
//  Uses macOS 26 TextEditor with AttributedString support
//

import AppKit
import STTextView
import SwiftUI

/// SwiftUI editor view with markdown editing and custom underlines
struct SketchPadEditor: View {
    @ObservedObject var viewModel: SketchPadViewModel

    /// Top padding for the text content area (breathing room below toolbar)
    private let topPadding: CGFloat = 12
    /// Horizontal padding for elegant text margins
    private let horizontalPadding: CGFloat = 16

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main text editor using STTextView for markdown editing
            STTextViewWrapper(viewModel: viewModel)
                .padding(.top, topPadding)
                .padding(.horizontal, horizontalPadding)

            // Underline overlay (when we have layout info)
            // IMPORTANT: Hit testing disabled so clicks pass through to text view for selection
            // Hover tracking is handled via NSTrackingArea on the Coordinator
            if viewModel.stLayoutInfo != nil {
                UnderlineOverlayView(
                    underlines: viewModel.underlineRects,
                    onHover: { _ in },
                    highlightedUnderlineId: viewModel.selectedInsightId
                )
                .padding(.top, topPadding)
                .padding(.horizontal, horizontalPadding)
                .allowsHitTesting(false)
            }

            // Edge fade indicators to show there's more content
            EdgeFadeIndicators(
                hasContentRight: viewModel.hasContentRight,
                hasContentBottom: viewModel.hasContentBottom
            )
            .allowsHitTesting(false)
        }
        // Update underlines when grammar errors change
        .onChange(of: viewModel.grammarErrors.count) { _, _ in
            viewModel.updateUnderlineRects()
        }
        .onChange(of: viewModel.styleSuggestions.count) { _, _ in
            viewModel.updateUnderlineRects()
        }
    }
}

// MARK: - Edge Fade Indicators

/// Subtle gradient fades at edges to indicate more content beyond visible area
private struct EdgeFadeIndicators: View {
    let hasContentRight: Bool
    let hasContentBottom: Bool

    /// Width of the fade gradient
    private let fadeWidth: CGFloat = 32

    var body: some View {
        ZStack {
            // Right edge fade (when content extends to the right)
            if hasContentRight {
                HStack {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(nsColor: .textBackgroundColor).opacity(0), location: 0),
                            .init(color: Color(nsColor: .textBackgroundColor).opacity(0.7), location: 0.5),
                            .init(color: Color(nsColor: .textBackgroundColor), location: 1.0),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: fadeWidth)
                }
            }

            // Bottom edge fade (when content extends below)
            if hasContentBottom {
                VStack {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(nsColor: .textBackgroundColor).opacity(0), location: 0),
                            .init(color: Color(nsColor: .textBackgroundColor).opacity(0.7), location: 0.5),
                            .init(color: Color(nsColor: .textBackgroundColor), location: 1.0),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: fadeWidth)
                }
            }
        }
    }
}

/// Controller for showing popovers using AppKit's NSPopover
/// Uses the same coordinate system as the underline rect calculations
@MainActor
class SketchPopoverController: NSObject, NSPopoverDelegate {
    static let shared = SketchPopoverController()

    private var popover: NSPopover?
    private var currentBaseUnderlineId: String? // Base ID without line index suffix
    private var hideTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private weak var currentView: NSView?
    private var currentUnderline: SketchUnderlineRect?
    private weak var currentViewModel: SketchPadViewModel?

    // Pending switch mechanism - delays switching to a new underline when a popover is already shown
    // This gives users time to move their mouse from underline to popover without accidentally switching
    private var pendingSwitchTimer: Timer?
    private var pendingUnderline: SketchUnderlineRect?
    private weak var pendingView: NSView?
    private weak var pendingViewModel: SketchPadViewModel?

    // Show delay mechanism - prevents accidental popover triggers during fast mouse movement
    private var showDelayTimer: Timer?
    private var pendingShowUnderline: SketchUnderlineRect?
    private weak var pendingShowView: NSView?
    private weak var pendingShowViewModel: SketchPadViewModel?

    /// Grace period before switching to a new underline (300ms)
    private let switchGracePeriod: TimeInterval = 0.3

    override private init() {
        super.init()
    }

    /// Extract base ID from underline ID (removes line index suffix like "-0", "-1", etc.)
    /// This allows treating multi-line underline segments as the same underline
    private func baseId(from id: String) -> String {
        // IDs are like "123-456-grammar-0" or "123-456-style-2"
        // Extract everything before the last dash-number suffix
        if let lastDashIndex = id.lastIndex(of: "-"),
           let suffix = Int(String(id[id.index(after: lastDashIndex)...]))
        {
            // It ends with a number, strip it
            _ = suffix // silence unused warning
            return String(id[..<lastDashIndex])
        }
        return id
    }

    /// Show popover for an underline - works with any NSView (NSTextView, STTextView, etc.)
    /// For multi-line underlines, shows popover at the bottom-most line segment
    func show(for underline: SketchUnderlineRect, in view: NSView?, viewModel: SketchPadViewModel) {
        guard let view else { return }

        // Cancel any pending hide
        cancelHide()

        let newBaseId = baseId(from: underline.id)

        // Don't re-show if we're already showing for the same base underline
        // This prevents flickering when hovering over different lines of the same underline
        if currentBaseUnderlineId == newBaseId, popover?.isShown == true {
            // Cancel any pending hide timer and pending switch since we're still on the same underline
            cancelHide()
            cancelPendingSwitch()
            return
        }

        // If a popover is already showing, delay the switch to give user time to reach it
        // This prevents accidentally switching when moving mouse from underline to popover
        if popover?.isShown == true {
            schedulePendingSwitch(for: underline, in: view, viewModel: viewModel)
            return
        }

        // Check if we're already waiting to show this underline
        let pendingShowBaseId = pendingShowUnderline.map { baseId(from: $0.id) }
        if pendingShowBaseId == newBaseId {
            // Already waiting to show this underline, do nothing
            return
        }

        // No popover showing - schedule delayed show to prevent accidental triggers
        scheduleDelayedShow(for: underline, in: view, viewModel: viewModel)
    }

    /// Schedule a delayed show for an underline (prevents accidental triggers during fast mouse movement)
    private func scheduleDelayedShow(for underline: SketchUnderlineRect, in view: NSView, viewModel: SketchPadViewModel) {
        // Cancel any existing pending show
        cancelPendingShow()

        // Store the pending show info
        pendingShowUnderline = underline
        pendingShowView = view
        pendingShowViewModel = viewModel

        // Start the show delay timer
        showDelayTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.popoverShowDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performDelayedShow()
            }
        }
    }

    /// Perform the delayed show (called when show delay timer fires)
    private func performDelayedShow() {
        guard let underline = pendingShowUnderline,
              let view = pendingShowView,
              let viewModel = pendingShowViewModel
        else {
            cancelPendingShow()
            return
        }

        // Clear pending state
        cancelPendingShow()

        // Show the popover
        showImmediately(for: underline, in: view, viewModel: viewModel)
    }

    /// Cancel any pending show
    private func cancelPendingShow() {
        showDelayTimer?.invalidate()
        showDelayTimer = nil
        pendingShowUnderline = nil
        pendingShowView = nil
        pendingShowViewModel = nil
    }

    /// Schedule a pending switch to a new underline with a grace period
    private func schedulePendingSwitch(for underline: SketchUnderlineRect, in view: NSView, viewModel: SketchPadViewModel) {
        // Cancel any existing pending switch
        cancelPendingSwitch()

        // Store the pending underline info
        pendingUnderline = underline
        pendingView = view
        pendingViewModel = viewModel

        // Start the grace period timer
        pendingSwitchTimer = Timer.scheduledTimer(withTimeInterval: switchGracePeriod, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performPendingSwitch()
            }
        }
    }

    /// Perform the pending switch (called when grace period expires)
    private func performPendingSwitch() {
        guard let underline = pendingUnderline,
              let view = pendingView,
              let viewModel = pendingViewModel
        else {
            cancelPendingSwitch()
            return
        }

        // Clear pending state
        cancelPendingSwitch()

        // Close current popover and show the new one
        closeImmediately()
        showImmediately(for: underline, in: view, viewModel: viewModel)
    }

    /// Cancel any pending switch (called when user reaches current popover)
    private func cancelPendingSwitch() {
        pendingSwitchTimer?.invalidate()
        pendingSwitchTimer = nil
        pendingUnderline = nil
        pendingView = nil
        pendingViewModel = nil
    }

    /// Show popover immediately (internal helper)
    private func showImmediately(for underline: SketchUnderlineRect, in view: NSView, viewModel: SketchPadViewModel) {
        let newBaseId = baseId(from: underline.id)

        currentBaseUnderlineId = newBaseId
        currentView = view
        currentUnderline = underline
        currentViewModel = viewModel

        // For multi-line underlines, find all segments and use the bottom-most one for positioning
        let allSegments = viewModel.underlineRects.filter { baseId(from: $0.id) == newBaseId }
        let bottomSegment = allSegments.max(by: { $0.rect.maxY < $1.rect.maxY }) ?? underline

        // Create popover content with hover tracking (use original underline for data, bottom segment for position)
        let contentView = SketchPopoverContentWrapper(
            underline: underline,
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.closeImmediately()
            },
            onMouseEnter: { [weak self] in
                self?.cancelHide()
            },
            onMouseExit: { [weak self] in
                self?.scheduleHide()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame.size = hostingController.sizeThatFits(in: CGSize(width: 350, height: 200))

        let popover = NSPopover()
        popover.contentViewController = hostingController
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self

        // Show popover at the BOTTOM segment of multi-line underlines
        // This prevents the popover from covering the rest of the text
        popover.show(relativeTo: bottomSegment.rect, of: view, preferredEdge: .maxY)

        self.popover = popover
    }

    /// Schedule hiding with a delay (gives user time to move mouse to popover)
    func scheduleHide() {
        // Cancel any pending show - mouse left before delay completed
        cancelPendingShow()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.popoverAutoHide, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeImmediately()
            }
        }
    }

    /// Cancel scheduled hide (when mouse enters popover)
    /// Also cancels any pending switch to a different underline
    func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
        // User reached the popover, cancel any pending switch to a different underline
        cancelPendingSwitch()
    }

    /// Close popover when hover ends (with delay)
    func close() {
        scheduleHide()
    }

    /// Close popover immediately
    func closeImmediately() {
        cancelHide()
        cancelPendingShow()
        popover?.close()
        popover = nil
        currentBaseUnderlineId = nil
        currentView = nil
        currentUnderline = nil
        currentViewModel = nil
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_: Notification) {
        Task { @MainActor [weak self] in
            self?.currentBaseUnderlineId = nil
        }
    }
}

/// Wrapper view that adds mouse tracking to the popover content
struct SketchPopoverContentWrapper: View {
    let underline: SketchUnderlineRect
    @ObservedObject var viewModel: SketchPadViewModel
    let onDismiss: () -> Void
    let onMouseEnter: () -> Void
    let onMouseExit: () -> Void

    var body: some View {
        SketchUnderlinePopoverContent(
            underline: underline,
            viewModel: viewModel,
            onDismiss: onDismiss
        )
        .onHover { isHovering in
            if isHovering {
                onMouseEnter()
            } else {
                onMouseExit()
            }
        }
    }
}

// MARK: - Underline Popover Content

/// SwiftUI view for underline suggestion popover - routes to grammar or style view
struct SketchUnderlinePopoverContent: View {
    let underline: SketchUnderlineRect
    @ObservedObject var viewModel: SketchPadViewModel
    var onDismiss: (() -> Void)?

    var body: some View {
        switch underline.category {
        case .grammar:
            SketchGrammarPopoverContent(
                underline: underline,
                viewModel: viewModel,
                onDismiss: onDismiss
            )
        case .style, .readability:
            SketchStylePopoverContent(
                underline: underline,
                viewModel: viewModel,
                onDismiss: onDismiss
            )
        }
    }
}

// MARK: - Grammar Popover Content

/// Popover content for grammar/spelling errors
private struct SketchGrammarPopoverContent: View {
    let underline: SketchUnderlineRect
    @ObservedObject var viewModel: SketchPadViewModel
    var onDismiss: (() -> Void)?

    @ObservedObject private var preferences = UserPreferences.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var hoveredSuggestion: String?

    private var effectiveColorScheme: ColorScheme {
        switch preferences.overlayTheme {
        case "Light": .light
        case "Dark": .dark
        default: systemColorScheme
        }
    }

    private var colors: AppColors {
        AppColors(for: effectiveColorScheme)
    }

    private var baseTextSize: CGFloat {
        CGFloat(preferences.suggestionTextSize)
    }

    private var captionTextSize: CGFloat {
        baseTextSize * 0.85
    }

    /// Valid suggestions (non-empty)
    private var validSuggestions: [String] {
        underline.suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with category and close button
            HStack(alignment: .center, spacing: 8) {
                // Category indicator dot with subtle glow
                Circle()
                    .fill(colors.categoryColor(for: categoryName))
                    .frame(width: 8, height: 8)
                    .shadow(color: colors.categoryColor(for: categoryName).opacity(0.4), radius: 3, x: 0, y: 0)

                // Category label
                Text(categoryLabel)
                    .font(.system(size: captionTextSize, weight: .semibold))
                    .foregroundColor(colors.textPrimary.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                // Close button
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(colors.textTertiary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(colors.backgroundRaised.opacity(0.01))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Content area - suggestions or message
            VStack(alignment: .leading, spacing: 2) {
                if !validSuggestions.isEmpty {
                    // Clickable suggestions with hover effect
                    ForEach(Array(validSuggestions.prefix(5).enumerated()), id: \.offset) { _, suggestion in
                        Button(action: { applySuggestion(suggestion) }) {
                            Text(suggestion)
                                .font(.system(size: baseTextSize, weight: .medium))
                                .foregroundColor(colors.link)
                                .underline(
                                    hoveredSuggestion != suggestion,
                                    pattern: .dot,
                                    color: colors.linkSubtle
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(hoveredSuggestion == suggestion ? colors.link.opacity(0.15) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredSuggestion = isHovered ? suggestion : nil
                            }
                        }
                    }
                } else {
                    // No suggestions - show the error message
                    Text(underline.message)
                        .font(.system(size: baseTextSize - 1))
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
            }

            // Action bar with icon buttons
            HStack(spacing: 6) {
                // Ignore button
                Button(action: { ignoreSuggestion() }) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Ignore this suggestion")

                // Ignore Rule button (only for grammar errors with lintId)
                if underline.lintId != nil {
                    Button(action: { ignoreRule() }) {
                        Image(systemName: "nosign")
                            .font(.system(size: 12))
                            .foregroundColor(colors.textSecondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Ignore this rule")
                }

                // Add to Dictionary (for spelling only)
                if underline.category == .grammar, categoryName.lowercased() == "spelling" {
                    Button(action: { addToDictionary() }) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 12))
                            .foregroundColor(colors.textSecondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Add to dictionary")
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 0
                )
                .fill(colors.backgroundElevated.opacity(0.5))
            )
        }
        // Tahoe-style background
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [colors.backgroundGradientTop, colors.backgroundGradientBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                colors.border.opacity(0.5),
                                colors.border.opacity(0.2),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .frame(width: 240)
        .fixedSize(horizontal: false, vertical: true)
        .colorScheme(effectiveColorScheme)
    }

    // MARK: - Helpers

    private var categoryName: String {
        switch underline.category {
        case .grammar: "Spelling"
        case .style: "Style"
        case .readability: "Readability"
        }
    }

    private var categoryLabel: String {
        switch underline.category {
        case .grammar: "Spelling"
        case .style: "Style suggestion"
        case .readability: "Readability"
        }
    }

    private func dismiss() {
        onDismiss?()
    }

    private func applySuggestion(_ suggestion: String) {
        viewModel.applySuggestionFromPopover(suggestion, for: underline)
        dismiss()
    }

    private func ignoreSuggestion() {
        viewModel.ignoreUnderline(underline)
        dismiss()
    }

    private func ignoreRule() {
        if let lintId = underline.lintId {
            viewModel.ignoreRuleFromPopover(lintId: lintId)
        }
        ignoreSuggestion()
    }

    private func addToDictionary() {
        viewModel.addToDictionaryFromPopover(word: underline.originalText)
        ignoreSuggestion()
    }
}

// MARK: - Style Popover Content

/// Rich popover content for style/readability suggestions with diff visualization
private struct SketchStylePopoverContent: View {
    let underline: SketchUnderlineRect
    @ObservedObject var viewModel: SketchPadViewModel
    var onDismiss: (() -> Void)?

    @ObservedObject private var preferences = UserPreferences.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var isRegenerating = false
    @State private var hoveredButton: String?

    private var effectiveColorScheme: ColorScheme {
        switch preferences.overlayTheme {
        case "Light": .light
        case "Dark": .dark
        default: systemColorScheme
        }
    }

    private var colors: AppColors {
        AppColors(for: effectiveColorScheme)
    }

    private var baseTextSize: CGFloat {
        CGFloat(preferences.suggestionTextSize)
    }

    private var captionTextSize: CGFloat {
        baseTextSize * 0.85
    }

    /// Find the associated style suggestion model
    private var suggestion: StyleSuggestionModel? {
        viewModel.findStyleSuggestion(for: underline)
    }

    /// Category color based on type
    private var categoryColor: Color {
        underline.category == .style ? .purple : .blue
    }

    /// Category label
    private var categoryLabel: String {
        underline.category == .style ? "Style suggestion" : "Readability"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with category and close button
            HStack(alignment: .center, spacing: 8) {
                // Category indicator dot with subtle glow
                Circle()
                    .fill(categoryColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: categoryColor.opacity(0.4), radius: 3, x: 0, y: 0)

                // Category label
                Text(categoryLabel)
                    .font(.system(size: captionTextSize, weight: .semibold))
                    .foregroundColor(colors.textPrimary.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                // Close button
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(colors.textTertiary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(colors.backgroundRaised.opacity(0.01))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Diff visualization
            if let suggestion, !suggestion.diff.isEmpty {
                CompactDiffView(
                    original: suggestion.originalText,
                    suggested: suggestion.suggestedText,
                    diff: suggestion.diff
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else if let suggestion, !suggestion.suggestedText.isEmpty {
                // Fallback: simple before/after if no diff available
                BeforeAfterView(
                    original: underline.originalText,
                    suggested: suggestion.suggestedText
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Explanation message - use live suggestion data so it updates after regeneration
            Text(suggestion?.explanation ?? underline.message)
                .font(.system(size: baseTextSize - 1))
                .foregroundColor(colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .fixedSize(horizontal: false, vertical: true)

            // Action bar: Accept / Reject / Regenerate
            HStack(spacing: 8) {
                // Accept button (green)
                Button(action: { acceptSuggestion() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
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

                // Dismiss button (subtle)
                Button(action: { rejectSuggestion() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Dismiss")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(hoveredButton == "reject" ? .white : colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredButton == "reject" ? Color.secondary : colors.backgroundElevated)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredButton = hovering ? "reject" : nil
                    }
                }

                Spacer()

                // Regenerate button (purple sparkle)
                Button(action: { regenerateSuggestion() }) {
                    Group {
                        if isRegenerating {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.system(size: 11))
                        }
                    }
                    .foregroundColor(hoveredButton == "regenerate" ? .white : categoryColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredButton == "regenerate" ? categoryColor : categoryColor.opacity(0.15))
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 0
                )
                .fill(colors.backgroundElevated.opacity(0.5))
            )
        }
        // Tahoe-style background
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [colors.backgroundGradientTop, colors.backgroundGradientBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                categoryColor.opacity(0.3),
                                colors.border.opacity(0.2),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .colorScheme(effectiveColorScheme)
    }

    // MARK: - Actions

    private func dismiss() {
        onDismiss?()
    }

    private func acceptSuggestion() {
        guard let suggestion else {
            // Fallback: use underline data
            viewModel.applySuggestionFromPopover(underline.suggestions.first ?? "", for: underline)
            dismiss()
            return
        }
        viewModel.acceptStyleSuggestion(suggestion)
        dismiss()
    }

    private func rejectSuggestion() {
        guard let suggestion else {
            viewModel.ignoreUnderline(underline)
            dismiss()
            return
        }
        viewModel.rejectStyleSuggestion(suggestion)
        dismiss()
    }

    private func regenerateSuggestion() {
        guard let suggestion else { return }

        isRegenerating = true
        Task {
            _ = await viewModel.regenerateStyleSuggestion(suggestion)
            await MainActor.run {
                isRegenerating = false
            }
        }
    }
}
