//
//  TextGenerationPopover.swift
//  TextWarden
//
//  Popover for AI text generation using Apple Intelligence
//

import AppKit
import Combine
import SwiftUI

// MARK: - Text Input Panel

/// Custom NSPanel that CAN become key window to allow text input
/// Unlike NonActivatingPanel, this panel accepts keyboard focus for text editing
class TextInputPanel: NSPanel {
    override var canBecomeKey: Bool {
        true // Allow keyboard input
    }

    override var canBecomeMain: Bool {
        false // Don't become main window
    }

    /// Handle keyboard shortcuts (Cmd+A, Cmd+C, Cmd+V, Cmd+X, Cmd+Z) that don't work
    /// in non-activating panels because the app's main menu isn't connected
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle command key combinations
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        // Get the key character
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        // Handle standard edit commands by forwarding to first responder
        switch characters {
        case "a":
            // Select All
            if let responder = firstResponder {
                responder.selectAll(nil)
                return true
            }
        case "c":
            // Copy
            if let responder = firstResponder, responder.responds(to: #selector(NSText.copy(_:))) {
                responder.perform(#selector(NSText.copy(_:)), with: nil)
                return true
            }
        case "v":
            // Paste
            if let responder = firstResponder, responder.responds(to: #selector(NSText.paste(_:))) {
                responder.perform(#selector(NSText.paste(_:)), with: nil)
                return true
            }
        case "x":
            // Cut
            if let responder = firstResponder, responder.responds(to: #selector(NSText.cut(_:))) {
                responder.perform(#selector(NSText.cut(_:)), with: nil)
                return true
            }
        case "z":
            // Undo/Redo (Cmd+Z or Cmd+Shift+Z)
            if let responder = firstResponder {
                if event.modifierFlags.contains(.shift) {
                    // Redo
                    if responder.responds(to: Selector(("redo:"))) {
                        responder.perform(Selector(("redo:")), with: nil)
                        return true
                    }
                } else {
                    // Undo
                    responder.undoManager?.undo()
                    return true
                }
            }
        default:
            break
        }

        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Text Generation Popover Manager

/// Manages the text generation popover window
@MainActor
class TextGenerationPopover: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = TextGenerationPopover()

    // MARK: - Properties

    /// The popover panel (read-only access for hit testing)
    private(set) var panel: TextInputPanel?

    /// Timer for delayed hiding
    private var hideTimer: Timer?

    /// Event monitor for mouse clicks outside popover
    private var clickOutsideMonitor: Any?

    /// Current instruction input
    @Published var instruction: String = "" {
        didSet { if instruction != oldValue { discardGeneration() } }
    }

    /// Selected writing style
    @Published var selectedStyle: WritingStyle = .default {
        didSet { if selectedStyle != oldValue { discardGeneration() } }
    }

    /// Whether generation is in progress
    @Published var isGenerating: Bool = false

    /// Context from the document
    @Published var context: GenerationContext = .empty {
        didSet { if context != oldValue { discardGeneration() } }
    }

    /// Error message to display (if any)
    @Published var errorMessage: String?

    /// Generated results (multiple for "try another")
    @Published var generatedResults: [String] = []

    /// Current result index
    @Published var currentResultIndex: Int = 0

    /// Current generated result
    var generatedResult: String? {
        guard !generatedResults.isEmpty, currentResultIndex < generatedResults.count else { return nil }
        return generatedResults[currentResultIndex]
    }

    private var generationTask: Task<Void, Never>?
    private var generationID = UUID()

    // MARK: - Session Persistence

    /// Last used instruction (persisted across popover open/close)
    private var lastInstruction: String = ""

    /// Last used style
    private var lastStyle: WritingStyle = .default

    // MARK: - Callbacks

    /// Called when user requests text generation
    /// Parameters: instruction, style, context, variationSeed (nil for first generation, UInt64 for retries)
    var onGenerate: ((String, WritingStyle, GenerationContext, UInt64?) async throws -> String)?

    /// Called when user wants to insert generated text
    var onInsertText: ((String) -> Void)?

    // MARK: - Visibility

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Initialization

    override private init() {
        super.init()
    }

    // MARK: - Show/Hide

    /// Stored open direction from indicator - used for positioning
    private var openDirection: PopoverOpenDirection = .top

    /// Whether the popover was opened from the capsule indicator (persists until manually dismissed)
    @Published private(set) var openedFromIndicator: Bool = false

    /// Show the text generation popover
    /// - Parameters:
    ///   - position: Screen position to anchor the popover
    ///   - direction: Preferred direction for popover to open
    ///   - context: Generation context with text information
    ///   - fromIndicator: If true, popover persists until manually dismissed (opened from capsule)
    func show(at position: CGPoint, direction: PopoverOpenDirection = .top, context: GenerationContext, fromIndicator: Bool = false) {
        Logger.debug("TextGenerationPopover: show at \(position), direction: \(direction), fromIndicator: \(fromIndicator)", category: Logger.ui)

        // Don't show popover if a modal dialog is open (e.g., Print dialog, Save sheet)
        if ModalDialogDetector.isModalDialogPresent() {
            Logger.debug("TextGenerationPopover: Not showing - modal dialog is open", category: Logger.ui)
            return
        }

        // Close other popovers first
        SuggestionPopover.shared.hide()
        ReadabilityPopover.shared.hide()

        // Keep the instruction, never a result from a previous editor/session.
        discardGeneration()
        instruction = lastInstruction
        self.context = context
        isGenerating = false
        errorMessage = nil

        // Store open direction and indicator flag
        openDirection = direction
        openedFromIndicator = fromIndicator

        // Retain the last instruction's style; Clear resets to the configured preference.
        if lastInstruction.isEmpty {
            // Fresh session: use preference
            let styleName = UserPreferences.shared.selectedWritingStyle
            selectedStyle = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default
        } else {
            // Preserve the style paired with the retained instruction.
            selectedStyle = lastStyle
        }

        if panel == nil {
            createPanel()
        }

        rebuildContentView()

        // Position panel using explicit direction
        positionPanel(at: position)

        // Make panel visible and key so text input works
        panel?.orderFrontRegardless()
        panel?.makeKey()

        setupClickOutsideMonitor()
    }

    /// Position panel using anchor-based positioning with automatic direction flipping
    /// The anchor point represents where the popover's nearest edge should align
    private func positionPanel(at anchorPoint: CGPoint) {
        guard let panel else { return }

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) }) ?? NSScreen.main
        guard let screen else { return }

        let (origin, usedDirection) = PopoverPositioner.positionFromAnchor(
            at: anchorPoint,
            panelSize: panel.frame.size,
            direction: openDirection,
            constraintFrame: screen.visibleFrame
        )

        Logger.debug("TextGenerationPopover: positioning - requested: \(openDirection), used: \(usedDirection), origin: \(origin)", category: Logger.ui)
        panel.setFrameOrigin(origin)
    }

    /// Hide the popover
    func hide() {
        Logger.debug("TextGenerationPopover: hide", category: Logger.ui)

        // Save current state for next session
        lastInstruction = instruction
        lastStyle = selectedStyle
        discardGeneration()

        hideTimer?.invalidate()
        hideTimer = nil
        openedFromIndicator = false
        removeClickOutsideMonitor()
        panel?.orderOut(nil)
    }

    /// Clear the instruction, results, and retained session state.
    /// Also resets the style to the user's configured preference
    func clear() {
        Logger.debug("TextGenerationPopover: clear", category: Logger.ui)

        // Clear current state
        instruction = ""
        generatedResults = []
        currentResultIndex = 0
        errorMessage = nil

        // Clear persisted session state
        lastInstruction = ""

        // Reset style to user's preference
        let styleName = UserPreferences.shared.selectedWritingStyle
        selectedStyle = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default
        lastStyle = selectedStyle

        discardGeneration()

        // Rebuild the view to reflect the cleared state
        rebuildContentView()
    }

    /// Schedule hiding after delay
    /// Does nothing if popover was opened from indicator (must be manually dismissed)
    func scheduleHide(delay: TimeInterval = TimingConstants.popoverAutoHide) {
        // Don't auto-hide while generating or showing results
        guard !isGenerating, generatedResults.isEmpty else { return }

        // Don't auto-hide popovers opened from indicator
        guard !openedFromIndicator else {
            Logger.trace("TextGenerationPopover: skipping scheduleHide - opened from indicator", category: Logger.ui)
            return
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
    }

    /// Cancel any scheduled hide
    func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Panel Creation

    private let panelWidth: CGFloat = 400
    private let panelHeightBase: CGFloat = 520 // Without selected text
    private let panelHeightWithSelection: CGFloat = 650 // Extra space for selected text + quick actions

    /// Current panel height based on context
    private var currentPanelHeight: CGFloat {
        if let selected = context.selectedText, !selected.isEmpty {
            return panelHeightWithSelection
        }
        return panelHeightBase
    }

    private func createPanel() {
        let height = currentPanelHeight
        let contentView = TextGenerationContentView(popover: self)
        let hostingView = FirstMouseHostingView(rootView: contentView)

        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)

        let trackingView = TextGenTrackingView(popover: self)
        trackingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
        trackingView.addSubview(hostingView)
        hostingView.frame = trackingView.bounds
        hostingView.autoresizingMask = [.width, .height]

        panel = TextInputPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel?.contentView = trackingView
        panel?.isFloatingPanel = true
        panel?.level = .popUpMenu + 1
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.isMovableByWindowBackground = false
        panel?.backgroundColor = .clear
        panel?.isOpaque = false
        panel?.hasShadow = true
        panel?.hidesOnDeactivate = false

        // Make the panel accept keyboard input
        panel?.becomesKeyOnlyIfNeeded = false
    }

    private func rebuildContentView() {
        guard let panel,
              let trackingView = panel.contentView as? TextGenTrackingView else { return }

        trackingView.subviews.forEach { $0.removeFromSuperview() }

        let height = currentPanelHeight
        let contentView = TextGenerationContentView(popover: self)
        let hostingView = FirstMouseHostingView(rootView: contentView)

        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
        trackingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
        trackingView.addSubview(hostingView)
        hostingView.autoresizingMask = [.width, .height]

        panel.setContentSize(NSSize(width: panelWidth, height: height))
    }

    // MARK: - Click Outside Monitor

    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let panel else { return }

            let clickLocation = event.locationInWindow
            let panelFrame = panel.frame

            if !panelFrame.contains(clickLocation) {
                Logger.debug("TextGenerationPopover: Click outside - hiding", category: Logger.ui)
                hide()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Actions

    private var retryAttemptCounter: UInt64 = 0

    /// Results belong to the exact request and must not survive edited inputs or a closed panel.
    private func discardGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationID = UUID()
        isGenerating = false
        generatedResults = []
        currentResultIndex = 0
        errorMessage = nil
    }

    func generate() {
        startGeneration(variationSeed: nil)
    }

    func tryAnother() {
        guard !isGenerating else { return }
        if currentResultIndex < generatedResults.count - 1 {
            currentResultIndex += 1
            return
        }
        retryAttemptCounter &+= 1
        // The installed Foundation Models runtime rejects large seeds despite the UInt64 API.
        startGeneration(variationSeed: retryAttemptCounter & 0x7FFF_FFFF)
    }

    private func startGeneration(variationSeed: UInt64?) {
        guard !isGenerating else { return }
        let requestInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestInstruction.isEmpty else {
            errorMessage = "Please enter an instruction"
            return
        }
        do { try GenerationContext.validateSelection(context.selectedText) } catch {
            errorMessage = FoundationModelsError.safeMessage(for: error)
            return
        }
        guard let onGenerate else { return }
        let requestStyle = selectedStyle
        let requestContext = context
        let id = UUID()
        generationID = id
        if variationSeed == nil {
            generatedResults = []
            currentResultIndex = 0
        }
        isGenerating = true
        errorMessage = nil
        generationTask = Task { @MainActor in
            defer {
                if generationID == id {
                    isGenerating = false
                    generationTask = nil
                }
            }
            do {
                let result = try await onGenerate(requestInstruction, requestStyle, requestContext, variationSeed)
                guard !Task.isCancelled, generationID == id else { return }
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = "No text returned. Please try again."
                    return
                }
                if result == requestContext.selectedText {
                    errorMessage = "No changes suggested. Try another instruction or add the details you want included."
                    return
                }
                if generatedResults.contains(result) {
                    errorMessage = "No new variation. Try another instruction or style."
                } else {
                    generatedResults.append(result)
                }
                currentResultIndex = generatedResults.firstIndex(of: result) ?? 0
            } catch {
                guard !Task.isCancelled, generationID == id else { return }
                Logger.error("TextGenerationPopover: Generation failed", category: Logger.ui)
                errorMessage = FoundationModelsError.safeMessage(for: error)
            }
        }
    }

    /// Copy current result to clipboard
    func copyToClipboard() {
        guard let result = generatedResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        Logger.debug("TextGenerationPopover: Copied to clipboard", category: Logger.ui)
    }

    /// Insert the generated text
    func insertGeneratedText() {
        guard !isGenerating, let result = generatedResult else { return }
        onInsertText?(result)
        hide()
    }

    /// Cancel and close
    func cancel() {
        hide()
    }
}

// MARK: - Tracking View

private class TextGenTrackingView: NSView {
    weak var popover: TextGenerationPopover?

    /// Track last size to avoid unnecessary tracking area updates during rebuild cycles
    private var lastTrackingSize: NSSize = .zero

    init(popover: TextGenerationPopover) {
        self.popover = popover
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        // Initial setup - will be properly configured in updateTrackingAreas()
        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        // Only update tracking areas if size actually changed significantly
        // This prevents unnecessary recreation during rebuild cycles
        if abs(newSize.width - lastTrackingSize.width) > 1 || abs(newSize.height - lastTrackingSize.height) > 1 {
            lastTrackingSize = newSize
            updateTrackingAreas()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }

        // Only add tracking area if we have valid bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with _: NSEvent) {
        popover?.cancelHide()
    }

    override func mouseExited(with _: NSEvent) {
        // Don't auto-hide while generating or showing results
        if popover?.isGenerating == false, popover?.generatedResults.isEmpty ?? true {
            popover?.scheduleHide(delay: 0.5)
        }
    }
}

// MARK: - SwiftUI Content View

struct TextGenerationContentView: View {
    @ObservedObject var popover: TextGenerationPopover
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.colorScheme) var systemColorScheme

    /// Effective color scheme based on user preference (overlay theme)
    private var effectiveColorScheme: ColorScheme {
        switch preferences.overlayTheme {
        case "Light":
            .light
        case "Dark":
            .dark
        default:
            systemColorScheme
        }
    }

    /// App color scheme
    private var colors: AppColors {
        AppColors(for: effectiveColorScheme)
    }

    /// Base text size from preferences
    private var baseTextSize: CGFloat {
        CGFloat(preferences.suggestionTextSize)
    }

    /// Whether there's selected text to work with
    private var hasSelectedText: Bool {
        if let selected = popover.context.selectedText, !selected.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            VStack(alignment: .leading, spacing: 12) {
                if hasSelectedText {
                    selectedTextSection
                    quickActionsSection
                }

                instructionSection
                stylePicker
                generateButton

                if let error = popover.errorMessage {
                    errorView(error)
                }

                resultSection
                actionButtons
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .writingAssistantSurface(colors: colors)
        .colorScheme(effectiveColorScheme)
    }

    // MARK: - Subviews

    /// Whether there's content to clear (instruction or results)
    private var hasClearableContent: Bool {
        !popover.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !popover.generatedResults.isEmpty
    }

    private var headerView: some View {
        WritingAssistantHeader(
            title: "AI Compose",
            accentColor: colors.primary,
            colors: colors,
            textSize: baseTextSize * 0.85,
            resetAction: hasClearableContent ? { popover.clear() } : nil,
            resetAccessibilityLabel: "Clear instruction and results",
            closeAccessibilityLabel: "Close AI Compose",
            onClose: { popover.cancel() }
        )
    }

    private var selectedTextSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Selected text")
                .font(.system(size: baseTextSize - 2, weight: .medium))
                .foregroundColor(colors.textSecondary)

            ScrollView {
                Text(popover.context.selectedText ?? "")
                    .font(.system(size: baseTextSize - 1))
                    .foregroundColor(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 60)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colors.backgroundElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(colors.border, lineWidth: 0.5)
            )
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start with")
                .font(.system(size: baseTextSize - 2, weight: .medium))
                .foregroundColor(colors.textSecondary)

            // Transformation actions only (style is controlled by style chips)
            HStack(spacing: 6) {
                quickActionButton("Shorter", icon: "arrow.down.right.and.arrow.up.left", instruction: "Make this text shorter and more concise")
                quickActionButton("More detail", icon: "arrow.up.left.and.arrow.down.right", instruction: GenerationContext.expansionInstruction)
                quickActionButton("Simpler", icon: "text.alignleft", instruction: "Simplify this text to make it easier to understand")
            }
        }
    }

    private func quickActionButton(_ title: String, icon: String, instruction: String) -> some View {
        Button(action: {
            popover.instruction = instruction
            popover.generate()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: baseTextSize - 2, weight: .medium))
            }
            .foregroundColor(popover.isGenerating ? colors.textTertiary : colors.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(popover.isGenerating)
        .accessibilityLabel("\(title) selected text")
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hasSelectedText ? "What should change?" : "What would you like to write?")
                .font(.system(size: baseTextSize - 2, weight: .medium))
                .foregroundColor(colors.textSecondary)

            if !hasSelectedText {
                Text("Draft from your instructions, or select text in your app to rewrite it.")
                    .font(.system(size: baseTextSize - 2))
                    .foregroundColor(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $popover.instruction)
                    .font(.system(size: baseTextSize))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 90)
                    .disabled(popover.isGenerating)
                    .onKeyPress(phases: .down) { press in
                        if press.key == .return, !press.modifiers.contains(.shift) {
                            popover.generate()
                            return .handled // Enter triggers Generate
                        }
                        return .ignored // Let other keys through (including Shift+Enter)
                    }

                if popover.instruction.isEmpty {
                    Text(hasSelectedText ? "Describe how to rewrite the selection" : "Describe what you want to write")
                        .font(.system(size: baseTextSize))
                        .foregroundColor(colors.textTertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(colors.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(colors.border, lineWidth: 0.5)
            )
        }
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style")
                .font(.system(size: baseTextSize - 2, weight: .medium))
                .foregroundColor(colors.textSecondary)

            Picker("Style", selection: $popover.selectedStyle) {
                ForEach(WritingStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .disabled(popover.isGenerating)
            .accessibilityLabel("Writing style")
        }
    }

    private var generateButton: some View {
        HStack {
            Spacer()

            Button(action: { popover.generate() }) {
                HStack(spacing: 4) {
                    if popover.isGenerating {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                    }
                    Text(popover.isGenerating ? "Generating..." : "Generate")
                        .font(.system(size: baseTextSize - 2, weight: .medium))
                    if !popover.isGenerating {
                        Image(systemName: "return")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.primary)
            .controlSize(.regular)
            .disabled(popover.isGenerating || popover.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint("Press Return to generate")
        }
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(colors.error)
                .font(.system(size: 10))

            Text(error)
                .font(.system(size: baseTextSize - 2))
                .foregroundColor(colors.error)
                .lineLimit(2)

            Spacer()
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Result")
                    .font(.system(size: baseTextSize - 2, weight: .medium))
                    .foregroundColor(colors.textSecondary)

                if !popover.generatedResults.isEmpty {
                    Text("(\(popover.currentResultIndex + 1)/\(popover.generatedResults.count))")
                        .font(.system(size: baseTextSize - 3))
                        .foregroundColor(colors.textTertiary)
                }

                Spacer()

                // Result action buttons
                if popover.generatedResult != nil {
                    HStack(spacing: 10) {
                        // Copy button
                        Button(action: { popover.copyToClipboard() }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundColor(colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")

                        // Try another button
                        Button(action: { popover.tryAnother() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13))
                                .foregroundColor(popover.isGenerating ? colors.textTertiary : colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(popover.isGenerating)
                        .help("Try another version")
                    }
                }
            }

            // Result text area
            ScrollView {
                if let result = popover.generatedResult {
                    Text(result)
                        .font(.system(size: baseTextSize - 1))
                        .foregroundColor(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else if popover.isGenerating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Generating...")
                            .font(.system(size: baseTextSize - 1))
                            .foregroundColor(colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("Generated text will appear here")
                        .font(.system(size: baseTextSize - 1))
                        .foregroundColor(colors.textTertiary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(height: 100)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(popover.generatedResult != nil ? colors.successSubtle : colors.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(colors.border, lineWidth: 0.5)
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Cancel button
            Button(action: { popover.cancel() }) {
                Text("Cancel")
                    .font(.system(size: baseTextSize - 1, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // Insert button
            Button(action: { popover.insertGeneratedText() }) {
                Text("Insert")
                    .font(.system(size: baseTextSize - 1, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.primary)
            .controlSize(.large)
            .disabled(popover.isGenerating || popover.generatedResult == nil)
        }
    }
}
