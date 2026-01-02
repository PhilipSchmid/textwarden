//
//  GettingStartedTutorial.swift
//  TextWarden
//
//  Interactive tutorial showing how to use TextWarden's UI elements
//

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
            "Click the pen icon to compose with AI"
        case .rightClickIndicator:
            "Right-click the indicator for quick actions"
        case .complete:
            "Try it: Drag the indicator up and down"
        }
    }

    var hint: String {
        switch self {
        case .clickUnderline:
            "TextWarden underlines grammar errors as you type. Click any underline to see suggestions."
        case .clickStyleSection:
            "Apple Intelligence can rewrite your text for better clarity, tone, or style."
        case .clickComposeSection:
            "Use AI to compose new text from your instructions - perfect for starting drafts."
        case .rightClickIndicator:
            "Right-click for quick access to pause, settings, and app controls. Click anywhere on the menu to continue."
        case .complete:
            "In real use, drag the indicator to reposition it along any window edge. Click Continue when you're ready."
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

    // Text content that changes as user progresses
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

    // Which section to highlight in the indicator
    private var highlightedSection: IndicatorSection? {
        switch tutorialStep {
        case .clickStyleSection: .style
        case .clickComposeSection: .compose
        case .rightClickIndicator: nil // Right-click works anywhere, no specific section
        default: nil
        }
    }

    // Dynamic text display with optional underline
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
                        .offset(y: 75) // Position below the underline with more spacing
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

                // Interactive demo area
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        // Background text area at top
                        if tutorialStep == .complete {
                            // Complete step: Show window border demo with draggable indicator
                            TutorialDragDemo()
                        } else {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Dynamic text display with optional underline
                                    textDisplay
                                        .font(.system(size: 15))
                                }
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

                                // Indicator positioned to the right of text area
                                TutorialIndicatorInteractive(
                                    grammarCount: grammarCount,
                                    onGrammarClick: {}, // Not used in this flow
                                    onStyleClick: handleStyleClick,
                                    onComposeClick: handleComposeClick,
                                    onRightClick: handleIndicatorRightClick,
                                    isStyleClickEnabled: tutorialStep == .clickStyleSection,
                                    isComposeClickEnabled: tutorialStep == .clickComposeSection,
                                    isRightClickEnabled: tutorialStep == .rightClickIndicator,
                                    highlightedSection: highlightedSection
                                )
                                // Pointing arrows as overlay - don't affect layout
                                .overlay(alignment: .leading) {
                                    Group {
                                        if tutorialStep == .clickStyleSection, !showStylePopover {
                                            HStack(spacing: 4) {
                                                TutorialCallout(text: "Click sparkle")
                                                TutorialPointingArrow(direction: .right)
                                            }
                                            .offset(x: -130, y: 0) // Point at style section (middle)
                                        }

                                        if tutorialStep == .clickComposeSection, !showComposePopover {
                                            HStack(spacing: 4) {
                                                TutorialCallout(text: "Click pen")
                                                TutorialPointingArrow(direction: .right)
                                            }
                                            .offset(x: -115, y: 36) // Point at compose section (bottom)
                                        }

                                        if tutorialStep == .rightClickIndicator, !showContextMenu {
                                            HStack(spacing: 4) {
                                                TutorialCallout(text: "Right-click")
                                                TutorialPointingArrow(direction: .right)
                                            }
                                            .offset(x: -115, y: 0) // Point at center of capsule (right-click works anywhere)
                                        }
                                    }
                                }
                                .padding(.leading, 8)
                            }
                        }

                        Spacer()
                    }

                    // Grammar suggestion popover with external instruction
                    if showSuggestionPopover {
                        HStack(alignment: .center, spacing: 4) {
                            Spacer()

                            // External instruction with arrow (callout LEFT of arrow)
                            HStack(spacing: 4) {
                                TutorialCallout(text: "Click to apply")
                                TutorialPointingArrow(direction: .right)
                            }

                            TutorialSuggestionPopover(
                                suggestion: "receive",
                                onApply: {
                                    withAnimation {
                                        showSuggestionPopover = false
                                        grammarFixed = true
                                        tutorialStep = .clickStyleSection
                                    }
                                }
                            )
                            .padding(.trailing, 50)
                        }
                        .offset(y: 75)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Style suggestion popover with external instruction
                    if showStylePopover {
                        HStack(alignment: .center, spacing: 4) {
                            Spacer()

                            HStack(spacing: 4) {
                                TutorialCallout(text: "Accept to apply")
                                TutorialPointingArrow(direction: .right)
                            }

                            TutorialStylePopover(
                                originalText: "I wanted to receive your feedback.",
                                rewrittenText: "Thank you for your feedback.",
                                onApply: {
                                    withAnimation {
                                        showStylePopover = false
                                        styleApplied = true
                                        tutorialStep = .clickComposeSection
                                    }
                                }
                            )
                            .padding(.trailing, 50)
                        }
                        .offset(y: 50)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // AI Compose popover with external instruction
                    if showComposePopover {
                        HStack(alignment: .center, spacing: 4) {
                            Spacer()

                            HStack(spacing: 4) {
                                TutorialCallout(text: "Click Generate")
                                TutorialPointingArrow(direction: .right)
                            }

                            TutorialComposePopover(
                                onApply: {
                                    withAnimation {
                                        showComposePopover = false
                                        composeApplied = true
                                        tutorialStep = .rightClickIndicator
                                    }
                                }
                            )
                            .padding(.trailing, 50)
                        }
                        .offset(y: 50)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Context menu
                    if showContextMenu {
                        HStack {
                            Spacer()
                            TutorialContextMenu(
                                onDismiss: {
                                    withAnimation {
                                        showContextMenu = false
                                        tutorialStep = .complete
                                    }
                                }
                            )
                            .padding(.trailing, 50)
                        }
                        .offset(y: 20)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 300) // Increased to accommodate context menu
                .padding(.horizontal)

                // Hint text - positioned below demo area (hidden when context menu is open)
                // Extra top padding when compose popover is shown since it's taller
                if !showContextMenu {
                    Text(tutorialStep.hint)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, showComposePopover ? 80 : 16)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    // Only become the hit target for right-click events
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

    private var isDarkMode: Bool { colorScheme == .dark }

    private var grammarColor: Color { Color(red: 0.95, green: 0.35, blue: 0.25) }
    private var styleColor: Color {
        isDarkMode ? Color(red: 0.95, green: 0.3, blue: 0.75) : Color(red: 0.6, green: 0.2, blue: 0.85)
    }

    private var textGenColor: Color {
        isDarkMode ? Color(red: 0.3, green: 0.7, blue: 1.0) : Color(red: 0.15, green: 0.5, blue: 0.8)
    }

    private let sectionHeight: CGFloat = 36
    private let capsuleWidth: CGFloat = 36
    private let cornerRadius: CGFloat = 18

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
                Button(action: {}) {
                    Text("\(grammarCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(grammarColor)
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

                // Style section - clickable (middle - no rounded corners)
                Button(action: onStyleClick) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(styleColor.opacity(0.85))
                        .frame(width: capsuleWidth, height: sectionHeight)
                        .background(highlightedSection == .style ? styleColor.opacity(0.15) : Color.clear)
                }
                .buttonStyle(.plain)
                .disabled(!isStyleClickEnabled)

                // Compose section - clickable (bottom - rounded bottom corners)
                Button(action: onComposeClick) {
                    Image(systemName: "pencil.line")
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
            }

            // Separators
            VStack(spacing: 0) {
                Spacer().frame(height: sectionHeight)
                separatorColor.frame(width: capsuleWidth - 12, height: 0.5)
                Spacer().frame(height: sectionHeight)
                separatorColor.frame(width: capsuleWidth - 12, height: 0.5)
                Spacer().frame(height: sectionHeight)
            }

            // Border
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.12), lineWidth: 1)
        }
        .frame(width: capsuleWidth, height: sectionHeight * 3)
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
    let originalText: String
    let rewrittenText: String
    let onApply: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var isDarkMode: Bool { colorScheme == .dark }

    private var styleColor: Color {
        Color.purple
    }

    /// Build inline diff view showing removed (red strikethrough) and added (green) text
    private var inlineDiffText: Text {
        // Original: "I wanted to receive your feedback."
        // Suggested: "I would appreciate your feedback."
        // Diff: "I " + removed("wanted to receive") + added("would appreciate") + " your feedback."
        Text("I ")
            .foregroundColor(.primary) +
            Text("wanted to receive")
            .foregroundColor(.red)
            .strikethrough(true, color: .red) +
            Text(" ")
            .foregroundColor(.primary) +
            Text("would appreciate")
            .foregroundColor(.green) +
            Text(" your feedback.")
            .foregroundColor(.primary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(styleColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: styleColor.opacity(0.4), radius: 3, x: 0, y: 0)

                Text("Style suggestion")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))

                Spacer()

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Inline diff view
            inlineDiffText
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Accept button - matches real implementation style
            Button(action: onApply) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Accept")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(isHovered ? .white : styleColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? styleColor : styleColor.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .onHover { isHovered = $0 }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDarkMode ? Color(white: 0.16) : Color(white: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .frame(width: 280)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Tutorial Compose Popover

private struct TutorialComposePopover: View {
    let onApply: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var generateHovered = false

    private var isDarkMode: Bool { colorScheme == .dark }
    private var composeColor: Color { Color.blue }
    private var successColor: Color { Color.green }

    private var backgroundTop: Color {
        isDarkMode ? Color(white: 0.18) : Color(white: 0.99)
    }

    private var backgroundBottom: Color {
        isDarkMode ? Color(white: 0.14) : Color(white: 0.96)
    }

    private var elevatedBg: Color {
        isDarkMode ? Color(white: 0.22) : Color(white: 0.94)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(composeColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: composeColor.opacity(0.4), radius: 3)

                Text("AI Compose")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 18, height: 18)

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
            }

            // Instruction section
            VStack(alignment: .leading, spacing: 4) {
                Text("Instruction")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("Make it more professional and grateful")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(elevatedBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            }

            // Style chips
            VStack(alignment: .leading, spacing: 4) {
                Text("Style")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    TutorialStyleChip(text: "Default", isSelected: false, color: composeColor)
                    TutorialStyleChip(text: "Formal", isSelected: true, color: composeColor)
                    TutorialStyleChip(text: "Casual", isSelected: false, color: composeColor)
                    TutorialStyleChip(text: "Concise", isSelected: false, color: composeColor)
                }
            }

            // Generate button
            HStack {
                Spacer()
                Button(action: onApply) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text("Generate")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "return")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(generateHovered ? composeColor.opacity(0.8) : composeColor)
                    )
                }
                .buttonStyle(.plain)
                .onHover { generateHovered = $0 }
            }

            // Result section (empty state)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Result")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Copy and Try Another icons (disabled state)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))

                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }

                Text("Generated text will appear here")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(elevatedBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: {}) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(elevatedBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

                Button(action: {}) {
                    Text("Insert")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(successColor.opacity(0.5))
                )
                .disabled(true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [backgroundTop, backgroundBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .frame(width: 340)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Style Chip for Tutorial

private struct TutorialStyleChip: View {
    let text: String
    let isSelected: Bool
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }

    private var elevatedBg: Color {
        isDarkMode ? Color(white: 0.22) : Color(white: 0.94)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? color : elevatedBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? color : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }
}

// MARK: - Tutorial Suggestion Popover (matches PopoverContentView)

private struct TutorialSuggestionPopover: View {
    let suggestion: String
    let onApply: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with category and close button
            HStack(alignment: .center, spacing: 8) {
                // Red indicator dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.red.opacity(0.4), radius: 3)

                // Category label
                Text("Spelling mistake")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))

                Spacer()

                // Close button
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Suggestion button - highlight extends to popover edges on hover
            // contentShape ensures entire row is clickable, not just the text
            Button(action: onApply) {
                Text(suggestion)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovered ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isHovered ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }

            // Action bar
            HStack(spacing: 6) {
                // Ignore button
                TutorialActionButton(icon: "eye.slash", tooltip: "Ignore")

                // Ignore Rule button
                TutorialActionButton(icon: "nosign", tooltip: "Ignore rule")

                // Add to Dictionary
                TutorialActionButton(icon: "text.badge.plus", tooltip: "Add to dictionary")

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
                .fill(Color.primary.opacity(0.03))
            )
        }
        .background(
            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: isDarkMode
                                ? [Color(white: 0.18), Color(white: 0.14)]
                                : [Color(white: 0.99), Color(white: 0.96)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Subtle border
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.15),
                                Color.primary.opacity(0.05),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .frame(width: 200)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Tutorial Action Button with Tooltip

private struct TutorialActionButton: View {
    let icon: String
    let tooltip: String

    @State private var isHovered = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(width: 22, height: 22)
            .onHover { hovering in
                isHovered = hovering
                hoverTask?.cancel()

                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                        if !Task.isCancelled {
                            await MainActor.run { showTooltip = true }
                        }
                    }
                } else {
                    showTooltip = false
                }
            }
            .overlay(alignment: .top) {
                if showTooltip {
                    Text(tooltip)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.85))
                        )
                        .offset(y: -28)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(1000)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showTooltip)
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
                HStack(spacing: 4) {
                    TutorialCallout(text: "Global pause")
                    TutorialPointingArrow(direction: .right)
                }
                .offset(x: -140, y: 30)

                Spacer()

                // Points to "App XY" section
                HStack(spacing: 4) {
                    TutorialCallout(text: "Per-app pause")
                    TutorialPointingArrow(direction: .right)
                }
                .offset(x: -140, y: -50)
            }
        }
        // "Click to continue" instruction at bottom - styled like TutorialCallout
        .overlay(alignment: .bottom) {
            Text("Click anywhere to continue")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 4, y: 2)
                )
                .offset(y: 40)
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

// Clean arrow shape with 90-degree angles
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

    private var isDarkMode: Bool { colorScheme == .dark }

    private let indicatorLength: CGFloat = 108 // Length along the edge
    private let indicatorThickness: CGFloat = 36 // Thickness perpendicular to edge
    private let windowHeight: CGFloat = 200
    private let borderGuideWidth: CGFloat = 40 // Wide gradient band like real implementation
    private let edgePadding: CGFloat = 4

    // Border guide color - subtle gray matching real implementation
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

    private var isDarkMode: Bool { colorScheme == .dark }

    private var grammarColor: Color { Color(red: 0.95, green: 0.35, blue: 0.25) }
    private var styleColor: Color {
        isDarkMode ? Color(red: 0.95, green: 0.3, blue: 0.75) : Color(red: 0.6, green: 0.2, blue: 0.85)
    }

    private var textGenColor: Color {
        isDarkMode ? Color(red: 0.3, green: 0.7, blue: 1.0) : Color(red: 0.15, green: 0.5, blue: 0.8)
    }

    private let sectionSize: CGFloat = 36
    private let cornerRadius: CGFloat = 18

    private var separatorColor: Color {
        isDarkMode ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    // Frame size depends on orientation
    private var frameWidth: CGFloat {
        isHorizontal ? sectionSize * 3 : sectionSize
    }

    private var frameHeight: CGFloat {
        isHorizontal ? sectionSize : sectionSize * 3
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
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(grammarColor)
                        .frame(width: sectionSize, height: sectionSize)

                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(styleColor.opacity(0.85))
                        .frame(width: sectionSize, height: sectionSize)

                    Image(systemName: "pencil.line")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textGenColor)
                        .frame(width: sectionSize, height: sectionSize)
                }

                // Horizontal separators
                HStack(spacing: 0) {
                    Spacer().frame(width: sectionSize)
                    separatorColor.frame(width: 0.5, height: sectionSize - 12)
                    Spacer().frame(width: sectionSize)
                    separatorColor.frame(width: 0.5, height: sectionSize - 12)
                    Spacer().frame(width: sectionSize)
                }
            } else {
                // Vertical layout for left/right edges
                VStack(spacing: 0) {
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(grammarColor)
                        .frame(width: sectionSize, height: sectionSize)

                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(styleColor.opacity(0.85))
                        .frame(width: sectionSize, height: sectionSize)

                    Image(systemName: "pencil.line")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textGenColor)
                        .frame(width: sectionSize, height: sectionSize)
                }

                // Vertical separators
                VStack(spacing: 0) {
                    Spacer().frame(height: sectionSize)
                    separatorColor.frame(width: sectionSize - 12, height: 0.5)
                    Spacer().frame(height: sectionSize)
                    separatorColor.frame(width: sectionSize - 12, height: 0.5)
                    Spacer().frame(height: sectionSize)
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
