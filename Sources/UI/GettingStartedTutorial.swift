//
//  GettingStartedTutorial.swift
//  TextWarden
//
//  Interactive tutorial showing how to use TextWarden's UI elements
//

import KeyboardShortcuts
import SwiftUI

// MARK: - Tutorial Step

enum TutorialStep: Int, CaseIterable {
    case clickUnderline // Step 1: Grammar - click underlined word
    case clickStyleSection // Step 2: Style - click style section
    case clickComposeSection // Step 3: AI Compose - click compose section
    case rightClickIndicator // Step 4: Right-click for menu
    case complete

    var instruction: String {
        switch self {
        case .clickUnderline:
            "Click the underlined word to see a grammar suggestion"
        case .clickStyleSection:
            "Click the sparkle icon for style suggestions"
        case .clickComposeSection:
            "Click the Compose icon to write with AI"
        case .rightClickIndicator:
            "Right-click the indicator for quick actions"
        case .complete:
            "Try it: Drag the indicator up and down"
        }
    }

    var hint: String {
        switch self {
        case .clickUnderline:
            "Red underlines mark spelling and grammar issues. Click one to review a correction, then apply it without leaving your editor."
        case .clickStyleSection:
            "Purple suggestions use Apple Intelligence to improve clarity, tone, or style. Review the rewrite, then choose Accept to apply it."
        case .clickComposeSection:
            "AI Compose can start a draft or rewrite selected text. Describe the change, choose a tone, select Generate, review the result, then Insert it."
        case .rightClickIndicator:
            "Right-click the control for pause, settings, and app-specific options. Click anywhere on the menu to continue to positioning."
        case .complete:
            "Drag the control to any window edge. It rotates on top and bottom edges and remembers its position. Click Continue when you're ready."
        }
    }
}

// MARK: - Getting Started Tutorial View

struct GettingStartedTutorialView: View {
    let onSkip: () -> Void
    let onComplete: () -> Void
    let onBackToOnboarding: (() -> Void)? // Go back to previous onboarding step

    @State private var tutorialStep: TutorialStep = .clickUnderline
    @State private var showSuggestionPopover = false
    @State private var showStylePopover = false
    @State private var showComposePopover = false
    @State private var showContextMenu = false
    @State private var pulseUnderline = true
    @State private var grammarFixed = false
    @State private var styleApplied = false
    @State private var composeApplied = false

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    /// Text content that changes as user progresses
    private var displayedText: String {
        if composeApplied {
            "I would greatly appreciate your detailed feedback."
        } else if styleApplied {
            "I would appreciate your feedback."
        } else if grammarFixed {
            "I wanted to receive your feedback."
        } else {
            "I wanted to recieve your feedback."
        }
    }

    private var grammarCount: Int {
        grammarFixed ? 0 : 1
    }

    /// Which section to highlight in the indicator
    private var highlightedSection: IndicatorSection? {
        switch tutorialStep {
        case .clickStyleSection: .style
        case .clickComposeSection: .compose
        case .rightClickIndicator: nil // Right-click works anywhere, no specific section
        default: nil
        }
    }

    /// Dynamic text display with optional underline
    @ViewBuilder
    private var textDisplay: some View {
        if !grammarFixed {
            // Show text with underlined "recieve"
            HStack(spacing: 0) {
                Text("I wanted to ")
                    .foregroundColor(.primary)

                Button(action: handleUnderlineClick) {
                    Text("recieve")
                        .foregroundColor(.primary)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.red)
                                .frame(height: 2)
                                .offset(y: 3)
                                .opacity(pulseUnderline && tutorialStep == .clickUnderline ? 1 : 0.7)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseUnderline)
                        }
                }
                .buttonStyle(.plain)
                .disabled(tutorialStep != .clickUnderline)
                // Arrow overlay - positioned relative to "recieve" button so it's always centered
                .overlay(alignment: .bottom) {
                    if tutorialStep == .clickUnderline, !showSuggestionPopover {
                        VStack(spacing: 4) {
                            TutorialPointingArrow(direction: .up)
                            TutorialCallout(text: "Click underline")
                        }
                        .fixedSize()
                        .frame(height: 0, alignment: .top)
                        .offset(y: tutorialCalloutTargetGap)
                    }
                }

                Text(" your feedback.")
                    .foregroundColor(.primary)
            }
        } else {
            Text(displayedText)
                .foregroundColor(.primary)
        }
    }

    enum IndicatorSection {
        case grammar, style, compose
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            VStack(spacing: 16) {
                // Header
                Text("Try It Out")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Progress indicator - 5 steps now
                HStack(spacing: 6) {
                    ForEach(0 ..< 5) { index in
                        Circle()
                            .fill(index <= tutorialStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                // Instruction
                Text(tutorialStep.instruction)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .padding(.top, 8)

                VStack(spacing: 14) {
                    if tutorialStep == .complete {
                        TutorialDragDemo()
                            .frame(maxHeight: .infinity)
                    } else {
                        textDemo

                        HStack(spacing: 24) {
                            activePopover
                            tutorialIndicator
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    tutorialTip
                }
                .frame(height: 540)
                .padding(.horizontal)
            }
            .padding(.top)

            Spacer(minLength: 0)

            // Footer matching OnboardingView style exactly
            Divider()

            HStack {
                // Back button (shown after first step)
                if canGoBack {
                    Button("Back") {
                        goBack()
                    }
                    .keyboardShortcut(.escape)
                }

                Spacer()

                // Skip button only shown while tutorial is in progress
                if tutorialStep != .complete {
                    Button("Skip Tutorial") {
                        onSkip()
                    }
                    .buttonStyle(.bordered)
                }

                if tutorialStep == .complete {
                    Button("Continue") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var textDemo: some View {
        textDisplay
            .font(.system(size: 15))
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }

    private var tutorialIndicator: some View {
        TutorialIndicatorInteractive(
            grammarCount: grammarCount,
            onGrammarClick: {},
            onStyleClick: handleStyleClick,
            onComposeClick: handleComposeClick,
            onRightClick: handleIndicatorRightClick,
            isStyleClickEnabled: tutorialStep == .clickStyleSection,
            isComposeClickEnabled: tutorialStep == .clickComposeSection,
            isRightClickEnabled: tutorialStep == .rightClickIndicator,
            highlightedSection: highlightedSection
        )
        .overlay(alignment: .leading) {
            Group {
                if tutorialStep == .clickStyleSection, !showStylePopover {
                    TutorialRightCallout(text: "Click Style")
                }

                if tutorialStep == .clickComposeSection, !showComposePopover {
                    TutorialRightCallout(text: "Click Compose")
                        .offset(y: UIConstants.capsuleSectionHeight)
                }

                if tutorialStep == .rightClickIndicator, !showContextMenu {
                    TutorialRightCallout(text: "Right-click")
                }
            }
        }
    }

    @ViewBuilder
    private var activePopover: some View {
        if showSuggestionPopover {
            TutorialSuggestionPopover(
                suggestion: "receive",
                onApply: {
                    withAnimation {
                        showSuggestionPopover = false
                        grammarFixed = true
                        tutorialStep = .clickStyleSection
                    }
                },
                onClose: {
                    withAnimation { showSuggestionPopover = false }
                }
            )
            .transition(.scale.combined(with: .opacity))
        } else if showStylePopover {
            TutorialStylePopover(
                onApply: {
                    withAnimation {
                        showStylePopover = false
                        styleApplied = true
                        tutorialStep = .clickComposeSection
                    }
                },
                onClose: {
                    withAnimation { showStylePopover = false }
                }
            )
            .transition(.scale.combined(with: .opacity))
        } else if showComposePopover {
            TutorialComposePopover(
                onApply: {
                    withAnimation {
                        showComposePopover = false
                        composeApplied = true
                        tutorialStep = .rightClickIndicator
                    }
                },
                onClose: {
                    withAnimation { showComposePopover = false }
                }
            )
            .transition(.scale.combined(with: .opacity))
        } else if showContextMenu {
            TutorialContextMenu(
                onDismiss: {
                    withAnimation {
                        showContextMenu = false
                        tutorialStep = .complete
                    }
                }
            )
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var tutorialTip: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.accentColor)

            Text(tutorialStep.hint)
                .foregroundColor(AppColors(for: colorScheme).textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 520, minHeight: 62, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors(for: colorScheme).backgroundElevated.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors(for: colorScheme).border, lineWidth: 0.5)
        )
    }

    /// Whether the back button should be shown
    private var canGoBack: Bool {
        // Show back button if we can go to previous tutorial step OR back to onboarding
        tutorialStep != .complete && (tutorialStep != .clickUnderline || onBackToOnboarding != nil)
    }

    /// Go back to previous tutorial step or to onboarding
    private func goBack() {
        withAnimation {
            // Close any open popovers
            showSuggestionPopover = false
            showStylePopover = false
            showComposePopover = false
            showContextMenu = false

            switch tutorialStep {
            case .clickUnderline:
                // Go back to previous onboarding step if available
                onBackToOnboarding?()
            case .clickStyleSection:
                grammarFixed = false
                tutorialStep = .clickUnderline
            case .clickComposeSection:
                styleApplied = false
                tutorialStep = .clickStyleSection
            case .rightClickIndicator:
                composeApplied = false
                tutorialStep = .clickComposeSection
            case .complete:
                break // Can't go back from complete
            }
        }
    }

    private func handleUnderlineClick() {
        guard tutorialStep == .clickUnderline else { return }
        withAnimation(.spring(response: 0.3)) {
            showSuggestionPopover = true
            pulseUnderline = false
        }
    }

    private func handleStyleClick() {
        guard tutorialStep == .clickStyleSection else { return }
        withAnimation(.spring(response: 0.3)) {
            showStylePopover = true
        }
    }

    private func handleComposeClick() {
        guard tutorialStep == .clickComposeSection else { return }
        withAnimation(.spring(response: 0.3)) {
            showComposePopover = true
        }
    }

    private func handleIndicatorRightClick() {
        guard tutorialStep == .rightClickIndicator else { return }
        withAnimation(.spring(response: 0.3)) {
            showContextMenu = true
        }
    }
}

// MARK: - Right-Clickable Area (NSViewRepresentable for proper right-click)

private struct RightClickableArea: NSViewRepresentable {
    let onLeftClick: (() -> Void)?
    let onRightClick: (() -> Void)?

    func makeNSView(context _: Context) -> RightClickView {
        let view = RightClickView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context _: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
    }
}

private class RightClickView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override func mouseDown(with _: NSEvent) {
        if let handler = onLeftClick {
            handler()
        }
        // Always pass left clicks through - don't block SwiftUI buttons
        // Note: We don't call super here because we want SwiftUI to handle it
    }

    override func rightMouseDown(with event: NSEvent) {
        if let handler = onRightClick {
            handler()
        } else {
            super.rightMouseDown(with: event)
        }
    }

    /// Only become the hit target for right-click events
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        onRightClick != nil
    }
}

// MARK: - Interactive Tutorial Indicator with Section Clicks

private struct TutorialIndicatorInteractive: View {
    let grammarCount: Int
    let onGrammarClick: () -> Void
    let onStyleClick: () -> Void
    let onComposeClick: () -> Void
    let onRightClick: () -> Void
    let isStyleClickEnabled: Bool
    let isComposeClickEnabled: Bool
    let isRightClickEnabled: Bool
    let highlightedSection: GettingStartedTutorialView.IndicatorSection?

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var grammarColor: Color {
        AppColors(for: colorScheme).error
    }

    private var styleColor: Color {
        AppColors(for: colorScheme).style
    }

    private var textGenColor: Color {
        AppColors(for: colorScheme).primary
    }

    private var successColor: Color {
        Color(nsColor: .systemGreen)
    }

    private let sectionHeight = UIConstants.capsuleSectionHeight
    private let capsuleWidth = UIConstants.capsuleWidth
    private let cornerRadius = UIConstants.capsuleCornerRadius
    private let sectionCount: CGFloat = 3

    private var separatorColor: Color {
        isDarkMode ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    var body: some View {
        ZStack {
            // Glass background
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isDarkMode ? Color(white: 0.15) : Color(white: 0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDarkMode ? 0.12 : 0.4), Color.white.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                )

            // Clickable sections
            VStack(spacing: 0) {
                // Grammar section (top - rounded top corners)
                Button(action: onGrammarClick) {
                    Group {
                        if grammarCount > 0 {
                            Text("\(grammarCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(grammarColor)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(successColor)
                        }
                    }
                    .frame(width: capsuleWidth, height: sectionHeight)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: cornerRadius
                        )
                        .fill(highlightedSection == .grammar ? grammarColor.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Grammar issues")

                // Style section - clickable (middle - no rounded corners)
                Button(action: onStyleClick) {
                    Label("Style suggestions", systemImage: "sparkles")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(styleColor.opacity(0.85))
                        .frame(width: capsuleWidth, height: sectionHeight)
                        .background(highlightedSection == .style ? styleColor.opacity(0.15) : Color.clear)
                }
                .buttonStyle(.plain)
                .disabled(!isStyleClickEnabled)
                .accessibilityLabel("Style suggestions")

                // Compose section - clickable (bottom - rounded bottom corners)
                Button(action: onComposeClick) {
                    Label("Open AI Compose", systemImage: UIConstants.composeIconName)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textGenColor)
                        .frame(width: capsuleWidth, height: sectionHeight)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: cornerRadius,
                                bottomTrailingRadius: cornerRadius,
                                topTrailingRadius: 0
                            )
                            .fill(highlightedSection == .compose ? textGenColor.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isComposeClickEnabled)
                .accessibilityLabel("Open AI Compose")
            }

            // Separators - positioned at section boundaries (2 separators for 3 sections)
            VStack(spacing: 0) {
                Color.clear.frame(height: sectionHeight - 0.25)
                separatorColor.frame(width: capsuleWidth - 12, height: 0.5)
                Color.clear.frame(height: sectionHeight - 0.5)
                separatorColor.frame(width: capsuleWidth - 12, height: 0.5)
                Color.clear.frame(height: sectionHeight - 0.25)
            }

            // Border
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.12), lineWidth: 1)
        }
        .frame(width: capsuleWidth, height: sectionHeight * sectionCount)
        .shadow(color: .black.opacity(isDarkMode ? 0.35 : 0.2), radius: 3, y: 2)
        .overlay {
            // Only add the right-click overlay when actually needed
            // This prevents it from blocking left clicks on SwiftUI buttons
            if isRightClickEnabled {
                RightClickableArea(onLeftClick: nil, onRightClick: onRightClick)
            }
        }
    }
}

// MARK: - Tutorial Style Popover

private struct TutorialStylePopover: View {
    let onApply: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var colors: AppColors {
        AppColors(for: colorScheme)
    }

    /// Build inline diff view showing removed (red strikethrough) and added (green) text
    private var inlineDiffText: Text {
        // Original: "I wanted to receive your feedback."
        // Suggested: "I would appreciate your feedback."
        // Diff: "I " + removed("wanted to receive") + added("would appreciate") + " your feedback."
        Text("I ")
            .foregroundColor(colors.textPrimary) +
            Text("wanted to receive")
            .foregroundColor(colors.error)
            .strikethrough(true, color: colors.error) +
            Text(" ")
            .foregroundColor(colors.textPrimary) +
            Text("would appreciate")
            .foregroundColor(colors.success) +
            Text(" your feedback.")
            .foregroundColor(colors.textPrimary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WritingAssistantHeader(
                title: "Style suggestion",
                accentColor: colors.style,
                colors: colors,
                textSize: 12,
                closeAccessibilityLabel: "Close style suggestion",
                onClose: onClose
            )

            inlineDiffText
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                Button(action: onApply) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Accept")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(colors.style)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colors.style.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) {
                    TutorialRightCallout(text: "Accept to apply")
                }

                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("Reject")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textSecondary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text("Retry")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(colors.backgroundElevated.opacity(0.5))
        }
        .frame(width: 300)
        .writingAssistantSurface(colors: colors)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Tutorial Compose Popover

private struct TutorialComposePopover: View {
    let onApply: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedStyle: WritingStyle = .formal
    @State private var generatedText: String?

    private var colors: AppColors {
        AppColors(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WritingAssistantHeader(
                title: "AI Compose",
                accentColor: colors.primary,
                colors: colors,
                textSize: 12,
                badge: "On-device",
                closeAccessibilityLabel: "Close AI Compose",
                onClose: onClose
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("What should change?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.textSecondary)

                Text("Make it more professional and grateful")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 56, alignment: .topLeading)
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(colors.backgroundElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(colors.border, lineWidth: 0.5)
                    )

                Text("Style")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.textSecondary)

                Picker("Style", selection: $selectedStyle) {
                    ForEach(WritingStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                HStack {
                    Spacer()
                    Button(action: {
                        generatedText = "I would greatly appreciate your detailed feedback."
                    }) {
                        Image(systemName: "sparkles")
                        Text("Generate")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(colors.primary)
                    .overlay(alignment: .leading) {
                        if generatedText == nil {
                            TutorialRightCallout(text: "Click Generate")
                        }
                    }
                }

                Text("Result")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.textSecondary)

                Text(generatedText ?? "Generated text will appear here")
                    .font(.system(size: 12))
                    .foregroundColor(generatedText == nil ? colors.textTertiary : colors.textPrimary)
                    .italic(generatedText == nil)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colors.backgroundElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(colors.border, lineWidth: 0.5)
                    )

                HStack(spacing: 8) {
                    Button(action: onClose) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(action: onApply) {
                        Text("Insert")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(colors.primary)
                    .controlSize(.large)
                    .disabled(generatedText == nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 400)
        .writingAssistantSurface(colors: colors)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Tutorial Suggestion Popover (matches PopoverContentView)

private struct TutorialSuggestionPopover: View {
    let suggestion: String
    let onApply: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var isHovered = false

    private var colors: AppColors {
        AppColors(for: colorScheme)
    }

    private var shortcutDescription: String? {
        guard preferences.keyboardShortcutsEnabled,
              let shortcut = KeyboardShortcuts.getShortcut(for: .applySuggestion1)
        else {
            return nil
        }
        return shortcut.description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WritingAssistantHeader(
                title: "Spelling mistake",
                accentColor: colors.error,
                colors: colors,
                textSize: 12,
                closeAccessibilityLabel: "Close spelling suggestion",
                onClose: onClose
            )

            Button(action: onApply) {
                HStack {
                    Text(suggestion)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.link)
                    Spacer()
                    if let shortcutDescription {
                        Text(shortcutDescription)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(colors.textTertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isHovered ? colors.primarySubtle : Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .overlay(alignment: .leading) {
                TutorialRightCallout(text: "Click to apply")
            }

            HStack {
                Label("More", systemImage: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(colors.backgroundElevated.opacity(0.5))
        }
        .frame(width: 240)
        .writingAssistantSurface(colors: colors)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Tutorial Context Menu (matches actual indicator right-click menu style)

private struct TutorialContextMenu: View {
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredItem: String?

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        // The actual menu - callouts are in overlay so they don't affect layout
        VStack(alignment: .leading, spacing: 2) {
            // Global Grammar Checking header
            Text("Grammar Checking:")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Global options
            TutorialMenuItem(
                text: "Active",
                isChecked: true,
                isHovered: hoveredItem == "active",
                onHover: { hoveredItem = $0 ? "active" : nil }
            )

            TutorialMenuItem(
                text: "Paused for 1 Hour",
                isChecked: false,
                isHovered: hoveredItem == "1hour",
                onHover: { hoveredItem = $0 ? "1hour" : nil }
            )

            TutorialMenuItem(
                text: "Paused for 24 Hours",
                isChecked: false,
                isHovered: hoveredItem == "24hours",
                onHover: { hoveredItem = $0 ? "24hours" : nil }
            )

            TutorialMenuItem(
                text: "Paused Until Resumed",
                isChecked: false,
                isHovered: hoveredItem == "indefinite",
                onHover: { hoveredItem = $0 ? "indefinite" : nil }
            )

            Divider()
                .padding(.vertical, 4)
                .padding(.horizontal, 8)

            // App-specific header
            Text("App XY:")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            TutorialMenuItem(
                text: "Active",
                isChecked: true,
                isHovered: hoveredItem == "appActive",
                onHover: { hoveredItem = $0 ? "appActive" : nil }
            )

            TutorialMenuItem(
                text: "Paused for 1 Hour",
                isChecked: false,
                isHovered: hoveredItem == "app1hour",
                onHover: { hoveredItem = $0 ? "app1hour" : nil }
            )

            TutorialMenuItem(
                text: "Paused for 24 Hours",
                isChecked: false,
                isHovered: hoveredItem == "app24hours",
                onHover: { hoveredItem = $0 ? "app24hours" : nil }
            )

            TutorialMenuItem(
                text: "Paused Until Resumed",
                isChecked: false,
                isHovered: hoveredItem == "appIndefinite",
                onHover: { hoveredItem = $0 ? "appIndefinite" : nil }
            )

            Divider()
                .padding(.vertical, 4)
                .padding(.horizontal, 8)

            TutorialMenuItem(
                text: "Preferences",
                isChecked: false,
                isHovered: hoveredItem == "prefs",
                onHover: { hoveredItem = $0 ? "prefs" : nil }
            )
        }
        .padding(.vertical, 4)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDarkMode ? Color(NSColor.windowBackgroundColor) : Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        // Instruction callouts as overlay - don't affect menu layout
        .overlay(alignment: .leading) {
            VStack(alignment: .trailing, spacing: 0) {
                // Points to "Grammar Checking" section
                TutorialRightCallout(text: "Global pause")
                    .offset(y: 30)

                Spacer()

                // Points to "App XY" section
                TutorialRightCallout(text: "Per-app pause")
                    .offset(y: -50)
            }
        }
        .onTapGesture {
            onDismiss()
        }
    }
}

private struct TutorialMenuItem: View {
    let text: String
    let isChecked: Bool
    var hasShortcut: String?
    let isHovered: Bool
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Checkmark space
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }

            Text(text)
                .font(.system(size: 13))

            Spacer()

            if let shortcut = hasShortcut {
                Text("⌘\(shortcut)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.accentColor : Color.clear)
                .padding(.horizontal, 4)
        )
        .foregroundColor(isHovered ? .white : .primary)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
    }
}

// MARK: - Tutorial Callout

private let tutorialCalloutTargetGap: CGFloat = 8

private struct TutorialCallout: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, y: 2)
            )
            .fixedSize()
    }
}

private struct TutorialRightCallout: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            TutorialCallout(text: text)
            TutorialPointingArrow(direction: .right)
        }
        .fixedSize()
        .frame(width: 0, alignment: .trailing)
        .offset(x: -tutorialCalloutTargetGap)
    }
}

// MARK: - Animated Pointing Arrow

private struct TutorialPointingArrow: View {
    enum Direction {
        case up // Points up at target above
        case down // Points down at target below
        case left // Points left at target to the left
        case right // Points right at target to the right
    }

    let direction: Direction

    @State private var isAnimating = false

    init(direction: Direction = .up) {
        self.direction = direction
    }

    var body: some View {
        ZStack {
            // Subtle glow behind arrow
            ArrowShape(direction: direction)
                .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .blur(radius: 3)

            // Main arrow with gradient
            ArrowShape(direction: direction)
                .stroke(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: gradientStart,
                        endPoint: gradientEnd
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
        }
        .frame(width: 28, height: 32)
        .offset(x: animationOffsetX, y: animationOffsetY)
        .animation(
            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }

    private var animationOffsetX: CGFloat {
        switch direction {
        case .left: isAnimating ? -4 : 0
        case .right: isAnimating ? 4 : 0
        case .up, .down: 0
        }
    }

    private var animationOffsetY: CGFloat {
        switch direction {
        case .up: isAnimating ? -4 : 0
        case .down: isAnimating ? 4 : 0
        case .left, .right: 0
        }
    }

    private var gradientStart: UnitPoint {
        switch direction {
        case .up: .bottom
        case .down: .top
        case .left: .trailing
        case .right: .leading
        }
    }

    private var gradientEnd: UnitPoint {
        switch direction {
        case .up: .top
        case .down: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }
}

/// Clean arrow shape with 90-degree angles
private struct ArrowShape: Shape {
    let direction: TutorialPointingArrow.Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let centerX = rect.midX
        let centerY = rect.midY
        let topY = rect.minY + 4
        let bottomY = rect.maxY - 4
        let leftX = rect.minX + 4
        let rightX = rect.maxX - 4

        switch direction {
        case .up:
            // Arrow pointing up: vertical line with arrowhead
            path.move(to: CGPoint(x: centerX, y: bottomY))
            path.addLine(to: CGPoint(x: centerX, y: topY))
            path.move(to: CGPoint(x: centerX - 7, y: topY + 8))
            path.addLine(to: CGPoint(x: centerX, y: topY))
            path.addLine(to: CGPoint(x: centerX + 7, y: topY + 8))

        case .down:
            // Arrow pointing down: vertical line with arrowhead
            path.move(to: CGPoint(x: centerX, y: topY))
            path.addLine(to: CGPoint(x: centerX, y: bottomY))
            path.move(to: CGPoint(x: centerX - 7, y: bottomY - 8))
            path.addLine(to: CGPoint(x: centerX, y: bottomY))
            path.addLine(to: CGPoint(x: centerX + 7, y: bottomY - 8))

        case .left:
            // Arrow pointing left: horizontal line with arrowhead
            path.move(to: CGPoint(x: rightX, y: centerY))
            path.addLine(to: CGPoint(x: leftX, y: centerY))
            path.move(to: CGPoint(x: leftX + 8, y: centerY - 7))
            path.addLine(to: CGPoint(x: leftX, y: centerY))
            path.addLine(to: CGPoint(x: leftX + 8, y: centerY + 7))

        case .right:
            // Arrow pointing right: horizontal line with arrowhead
            path.move(to: CGPoint(x: leftX, y: centerY))
            path.addLine(to: CGPoint(x: rightX, y: centerY))
            path.move(to: CGPoint(x: rightX - 8, y: centerY - 7))
            path.addLine(to: CGPoint(x: rightX, y: centerY))
            path.addLine(to: CGPoint(x: rightX - 8, y: centerY + 7))
        }

        return path
    }
}

// MARK: - Tutorial Drag Demo (shows indicator positioning on window borders)

private struct TutorialDragDemo: View {
    enum Edge {
        case top, bottom, left, right

        var isHorizontal: Bool {
            self == .top || self == .bottom
        }
    }

    @State private var currentEdge: Edge = .right
    @State private var edgePosition: CGFloat = 0.3 // 0-1 position along the edge
    @State private var isDragging = false
    @State private var hasInteracted = false

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private let indicatorLength = UIConstants.capsuleSectionHeight * 3
    private let indicatorThickness = UIConstants.capsuleWidth
    private let windowHeight: CGFloat = 200
    private let borderGuideWidth = UIConstants.borderGuideWidth
    private let edgePadding: CGFloat = 4

    /// Border guide color - subtle gray matching real implementation
    private var borderGuideColor: Color {
        isDarkMode
            ? Color(hue: 30 / 360, saturation: 0.03, brightness: 0.45) // Warm gray for dark
            : Color(hue: 220 / 360, saturation: 0.04, brightness: 0.75) // Cool gray for light
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Window content area
                VStack(alignment: .leading, spacing: 12) {
                    // Simulated title bar
                    HStack(spacing: 8) {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 12, height: 12)
                        Circle().fill(Color.yellow.opacity(0.8)).frame(width: 12, height: 12)
                        Circle().fill(Color.green.opacity(0.8)).frame(width: 12, height: 12)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    // Simulated content
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 16)
                            .frame(maxWidth: 200)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 16)
                            .frame(maxWidth: 280)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 16)
                            .frame(maxWidth: 150)
                    }
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

                // Border guides on all edges - gradient fading inward (like real implementation)
                // Only show when dragging
                if isDragging {
                    // Right edge gradient
                    HStack {
                        Spacer()
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        borderGuideColor.opacity(currentEdge == .right ? 0.7 : 0.4),
                                        borderGuideColor.opacity(0),
                                    ],
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )
                            )
                            .frame(width: borderGuideWidth)
                    }

                    // Left edge gradient
                    HStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        borderGuideColor.opacity(currentEdge == .left ? 0.7 : 0.4),
                                        borderGuideColor.opacity(0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: borderGuideWidth)
                        Spacer()
                    }

                    // Top edge gradient
                    VStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        borderGuideColor.opacity(currentEdge == .top ? 0.7 : 0.4),
                                        borderGuideColor.opacity(0),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: borderGuideWidth)
                        Spacer()
                    }

                    // Bottom edge gradient
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        borderGuideColor.opacity(currentEdge == .bottom ? 0.7 : 0.4),
                                        borderGuideColor.opacity(0),
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: borderGuideWidth)
                    }
                }

                // Draggable indicator
                TutorialIndicatorDraggable(isDragging: isDragging, isHorizontal: currentEdge.isHorizontal)
                    .position(indicatorPosition(in: geometry.size))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                hasInteracted = true
                                updatePosition(from: value.location, in: geometry.size)
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                    .animation(.easeInOut(duration: 0.2), value: currentEdge)

                // "Drag me" hint
                if !hasInteracted {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Text("Drag to any edge!")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.15))
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDragging)
        }
        .frame(height: windowHeight)
        .padding(.horizontal)
    }

    private func indicatorPosition(in size: CGSize) -> CGPoint {
        let length = indicatorLength
        let thickness = indicatorThickness

        switch currentEdge {
        case .right:
            let availableHeight = size.height - length - edgePadding * 2
            let y = edgePadding + length / 2 + availableHeight * edgePosition
            return CGPoint(x: size.width - thickness / 2, y: y)
        case .left:
            let availableHeight = size.height - length - edgePadding * 2
            let y = edgePadding + length / 2 + availableHeight * edgePosition
            return CGPoint(x: thickness / 2, y: y)
        case .top:
            let availableWidth = size.width - length - edgePadding * 2
            let x = edgePadding + length / 2 + availableWidth * edgePosition
            return CGPoint(x: x, y: thickness / 2)
        case .bottom:
            let availableWidth = size.width - length - edgePadding * 2
            let x = edgePadding + length / 2 + availableWidth * edgePosition
            return CGPoint(x: x, y: size.height - thickness / 2)
        }
    }

    private func updatePosition(from location: CGPoint, in size: CGSize) {
        // Determine which edge is closest
        let distToRight = size.width - location.x
        let distToLeft = location.x
        let distToTop = location.y
        let distToBottom = size.height - location.y

        let minDist = min(distToRight, distToLeft, distToTop, distToBottom)
        let edgeThreshold: CGFloat = 60 // Snap to edge when within this distance

        // Only change edge if clearly closer to a different edge
        if minDist < edgeThreshold {
            let newEdge: Edge = if minDist == distToRight {
                .right
            } else if minDist == distToLeft {
                .left
            } else if minDist == distToTop {
                .top
            } else {
                .bottom
            }

            if newEdge != currentEdge {
                currentEdge = newEdge
            }
        }

        // Update position along the current edge
        let length = indicatorLength
        switch currentEdge {
        case .right, .left:
            let availableHeight = size.height - length - edgePadding * 2
            let relativeY = location.y - edgePadding - length / 2
            edgePosition = max(0, min(1, relativeY / availableHeight))
        case .top, .bottom:
            let availableWidth = size.width - length - edgePadding * 2
            let relativeX = location.x - edgePadding - length / 2
            edgePosition = max(0, min(1, relativeX / availableWidth))
        }
    }
}

// MARK: - Draggable Indicator for Tutorial (with drag state feedback)

private struct TutorialIndicatorDraggable: View {
    let isDragging: Bool
    let isHorizontal: Bool // true for top/bottom edges, false for left/right

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var styleColor: Color {
        AppColors(for: colorScheme).style
    }

    private var textGenColor: Color {
        AppColors(for: colorScheme).primary
    }

    private let sectionSize = UIConstants.capsuleSectionHeight
    private let sectionCount: CGFloat = 3
    private let cornerRadius = UIConstants.capsuleCornerRadius

    private var separatorColor: Color {
        isDarkMode ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    /// Frame size depends on orientation
    private var frameWidth: CGFloat {
        isHorizontal ? sectionSize * sectionCount : sectionSize
    }

    private var frameHeight: CGFloat {
        isHorizontal ? sectionSize : sectionSize * sectionCount
    }

    var body: some View {
        ZStack {
            // Glass background
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isDarkMode ? Color(white: 0.15) : Color(white: 0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDarkMode ? 0.12 : 0.4), Color.white.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                )

            // Sections - layout depends on orientation
            if isHorizontal {
                // Horizontal layout for top/bottom edges
                HStack(spacing: 0) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(nsColor: .systemGreen))
                        .frame(width: sectionSize, height: sectionSize)

                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(styleColor.opacity(0.85))
                        .frame(width: sectionSize, height: sectionSize)

                    Image(systemName: UIConstants.composeIconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textGenColor)
                        .frame(width: sectionSize, height: sectionSize)
                }

                // Horizontal separators - positioned at section boundaries (2 separators for 3 sections)
                HStack(spacing: 0) {
                    Color.clear.frame(width: sectionSize - 0.25)
                    separatorColor.frame(width: 0.5, height: sectionSize - 12)
                    Color.clear.frame(width: sectionSize - 0.5)
                    separatorColor.frame(width: 0.5, height: sectionSize - 12)
                    Color.clear.frame(width: sectionSize - 0.25)
                }
            } else {
                // Vertical layout for left/right edges
                VStack(spacing: 0) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(nsColor: .systemGreen))
                        .frame(width: sectionSize, height: sectionSize)

                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(styleColor.opacity(0.85))
                        .frame(width: sectionSize, height: sectionSize)

                    Image(systemName: UIConstants.composeIconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textGenColor)
                        .frame(width: sectionSize, height: sectionSize)
                }

                // Vertical separators - positioned at section boundaries (2 separators for 3 sections)
                VStack(spacing: 0) {
                    Color.clear.frame(height: sectionSize - 0.25)
                    separatorColor.frame(width: sectionSize - 12, height: 0.5)
                    Color.clear.frame(height: sectionSize - 0.5)
                    separatorColor.frame(width: sectionSize - 12, height: 0.5)
                    Color.clear.frame(height: sectionSize - 0.25)
                }
            }

            // Border
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(isDragging ? Color.accentColor : (isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.12)), lineWidth: isDragging ? 2 : 1)
        }
        .frame(width: frameWidth, height: frameHeight)
        .scaleEffect(isDragging ? 1.08 : 1.0)
        .shadow(color: .black.opacity(isDarkMode ? 0.35 : 0.2), radius: isDragging ? 8 : 3, y: isDragging ? 4 : 2)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: isHorizontal)
    }
}

// MARK: - Preview

#Preview {
    GettingStartedTutorialView(
        onSkip: {},
        onComplete: {},
        onBackToOnboarding: {}
    )
    .frame(width: 500, height: 500)
}
