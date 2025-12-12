//
//  StyleSuggestionPopover.swift
//  TextWarden
//
//  Popover for displaying style suggestions with diff view and actions
//

import SwiftUI
import AppKit
import Combine

/// Popover for style suggestions with accept/reject actions
class StyleSuggestionPopover: ObservableObject {

    /// Shared singleton instance
    static let shared = StyleSuggestionPopover()

    /// The current suggestion being displayed
    @Published private(set) var currentSuggestion: StyleSuggestionModel?

    /// All style suggestions for navigation
    private var allSuggestions: [StyleSuggestionModel] = []

    /// The popover panel (using NonActivatingPanel for proper window behavior)
    private var popoverPanel: NonActivatingPanel?

    /// Timer for delayed hiding
    private var hideTimer: Timer?

    /// Event monitor for mouse clicks outside popover
    private var clickOutsideMonitor: Any?

    /// Callback when suggestion is accepted
    var onAccept: ((StyleSuggestionModel) -> Void)?

    /// Callback when suggestion is rejected
    var onReject: ((StyleSuggestionModel, SuggestionRejectionCategory) -> Void)?

    /// Callback when popover is dismissed
    var onDismiss: (() -> Void)?

    /// Track whether the current suggestion was acted upon (accepted/rejected)
    /// Used to detect "ignored" suggestions when popover is dismissed without action
    private var currentSuggestionActedUpon: Bool = false

    /// Counter to force SwiftUI view identity reset on content update
    private var rebuildCounter: Int = 0

    private init() {}

    // MARK: - Show/Hide

    /// Show the popover for a style suggestion
    func show(
        suggestion: StyleSuggestionModel,
        allSuggestions: [StyleSuggestionModel] = [],
        at position: CGPoint,
        constrainToWindow windowFrame: CGRect? = nil
    ) {
        self.currentSuggestion = suggestion
        self.allSuggestions = allSuggestions.isEmpty ? [suggestion] : allSuggestions
        self.currentSuggestionActedUpon = false  // Reset for new suggestion

        // Create or update popover panel
        if popoverPanel == nil {
            createPopoverPanel()
        }

        updateContent()
        positionPopover(at: position, constrainTo: windowFrame)

        // Use order(.above) instead of orderFront() to prevent focus stealing
        popoverPanel?.order(.above, relativeTo: 0)

        // Setup click outside monitor to close when clicking elsewhere
        setupClickOutsideMonitor()
    }

    /// Hide the popover
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil

        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }

        // Record as ignored if there was a suggestion that wasn't acted upon
        if currentSuggestion != nil && !currentSuggestionActedUpon {
            UserStatistics.shared.recordStyleIgnored()
        }

        popoverPanel?.orderOut(nil)
        currentSuggestion = nil
        currentSuggestionActedUpon = false
    }

    /// Schedule delayed hide (for mouse tracking)
    func scheduleHide(after delay: TimeInterval = TimingConstants.popoverAutoHide) {
        // Cancel any existing timer
        hideTimer?.invalidate()

        // Schedule hide after delay (gives user time to move mouse into popover)
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Only hide if mouse is not over the popover
            if let panel = self.popoverPanel,
               !panel.frame.contains(NSEvent.mouseLocation) {
                self.hide()
            }
        }
    }

    /// Cancel any pending hide
    func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    /// Setup click outside monitor to close popover when user clicks elsewhere
    private func setupClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Use GLOBAL monitor to detect ALL clicks (including in other apps)
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self else { return }

            Logger.debug("StyleSuggestionPopover: Global click detected - hiding popover", category: Logger.ui)

            // Cancel any pending auto-hide timer
            self.hideTimer?.invalidate()
            self.hideTimer = nil

            self.hide()
            self.onDismiss?()
        }
    }

    // MARK: - Private Methods

    private func createPopoverPanel() {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu + 1  // Above error overlay (.popUpMenu) so underlines don't cover popover
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // CRITICAL: Prevent this panel from affecting app activation
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = false
        // This makes the panel resist becoming the key window
        panel.becomesKeyOnlyIfNeeded = true

        popoverPanel = panel
    }

    private func updateContent() {
        guard let suggestion = currentSuggestion,
              let panel = popoverPanel else { return }

        // Increment counter to force SwiftUI to treat this as a completely new view
        rebuildCounter += 1

        let contentView = StyleSuggestionPopoverContent(
            suggestion: suggestion,
            suggestionIndex: allSuggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0,
            totalSuggestions: allSuggestions.count,
            onAccept: { [weak self] in
                self?.acceptSuggestion()
            },
            onReject: { [weak self] category in
                self?.rejectSuggestion(category: category)
            },
            onPrevious: { [weak self] in
                self?.showPreviousSuggestion()
            },
            onNext: { [weak self] in
                self?.showNextSuggestion()
            },
            onDismiss: { [weak self] in
                self?.hide()
                self?.onDismiss?()
            }
        )
        // Wrap with id() to force complete re-layout
        .id(rebuildCounter)

        let hostingView = NSHostingView(rootView: contentView)

        // Step 1: Give hosting view plenty of room for initial layout
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)

        // Step 2: Set as content view
        panel.contentView = hostingView

        // Step 3: Force SwiftUI layout pass
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        // Step 4: Get the ACTUAL size SwiftUI wants
        let fittingSize = hostingView.fittingSize
        let width = min(max(fittingSize.width, 320), 450)
        let height = min(fittingSize.height, 400)

        // Step 5: Calculate panel position to keep TOP edge fixed
        let currentFrame = panel.frame
        let currentTop = currentFrame.origin.y + currentFrame.size.height
        let newOriginY = currentTop - height

        // Step 6: Resize panel to final size
        panel.setFrame(NSRect(x: currentFrame.origin.x, y: newOriginY, width: width, height: height), display: false, animate: false)

        // Step 7: Constrain hosting view to final size
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        // Step 8: Final layout pass and redraw
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        panel.display()
    }

    private func positionPopover(at position: CGPoint, constrainTo windowFrame: CGRect?) {
        guard let window = popoverPanel else { return }

        var frame = window.frame
        frame.origin.x = position.x - frame.width / 2
        frame.origin.y = position.y + 10 // Below the underline

        // Constrain to window bounds if provided
        if let bounds = windowFrame {
            if frame.maxX > bounds.maxX {
                frame.origin.x = bounds.maxX - frame.width - 10
            }
            if frame.minX < bounds.minX {
                frame.origin.x = bounds.minX + 10
            }
            if frame.minY < bounds.minY {
                frame.origin.y = position.y - frame.height - 10 // Show above instead
            }
        }

        window.setFrameOrigin(frame.origin)
    }

    // MARK: - Actions

    private func acceptSuggestion() {
        guard let suggestion = currentSuggestion else { return }

        currentSuggestionActedUpon = true  // Mark as acted upon before any hide
        onAccept?(suggestion)
        PreferenceLearner.shared.recordAcceptance(suggestion)
        UserStatistics.shared.recordStyleAcceptance()

        // Move to next suggestion or hide
        if let nextIndex = allSuggestions.firstIndex(where: { $0.id == suggestion.id }).map({ $0 + 1 }),
           nextIndex < allSuggestions.count {
            currentSuggestion = allSuggestions[nextIndex]
            updateContent()
        } else {
            hide()
        }
    }

    private func rejectSuggestion(category: SuggestionRejectionCategory) {
        guard let suggestion = currentSuggestion else { return }

        currentSuggestionActedUpon = true  // Mark as acted upon before any hide
        onReject?(suggestion, category)
        PreferenceLearner.shared.recordRejection(suggestion, category: category)
        UserStatistics.shared.recordStyleRejection(category: category.rawValue)

        // Move to next suggestion or hide
        if let nextIndex = allSuggestions.firstIndex(where: { $0.id == suggestion.id }).map({ $0 + 1 }),
           nextIndex < allSuggestions.count {
            currentSuggestion = allSuggestions[nextIndex]
            updateContent()
        } else {
            hide()
        }
    }

    private func showPreviousSuggestion() {
        guard let current = currentSuggestion,
              let currentIndex = allSuggestions.firstIndex(where: { $0.id == current.id }),
              currentIndex > 0 else { return }

        currentSuggestion = allSuggestions[currentIndex - 1]
        updateContent()
    }

    private func showNextSuggestion() {
        guard let current = currentSuggestion,
              let currentIndex = allSuggestions.firstIndex(where: { $0.id == current.id }),
              currentIndex < allSuggestions.count - 1 else { return }

        currentSuggestion = allSuggestions[currentIndex + 1]
        updateContent()
    }
}

// MARK: - SwiftUI Content View

struct StyleSuggestionPopoverContent: View {
    let suggestion: StyleSuggestionModel
    let suggestionIndex: Int
    let totalSuggestions: Int
    let onAccept: () -> Void
    let onReject: (SuggestionRejectionCategory) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onDismiss: () -> Void

    @State private var showRejectMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Style Suggestion")
                    .font(.headline)

                Spacer()

                if totalSuggestions > 1 {
                    HStack(spacing: 4) {
                        Button(action: onPrevious) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(suggestionIndex == 0)
                        .buttonStyle(.plain)

                        Text("\(suggestionIndex + 1)/\(totalSuggestions)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: onNext) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(suggestionIndex >= totalSuggestions - 1)
                        .buttonStyle(.plain)
                    }
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Diff view
            if !suggestion.diff.isEmpty {
                CompactDiffView(
                    original: suggestion.originalText,
                    suggested: suggestion.suggestedText,
                    diff: suggestion.diff
                )
            } else {
                BeforeAfterView(
                    original: suggestion.originalText,
                    suggested: suggestion.suggestedText
                )
            }

            // Explanation
            Text(suggestion.explanation)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button(action: onAccept) {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Menu {
                    ForEach(SuggestionRejectionCategory.allCases, id: \.self) { category in
                        Button(category.displayName) {
                            onReject(category)
                        }
                    }
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .menuStyle(.borderlessButton)

                Spacer()

                // Confidence indicator
                HStack(spacing: 4) {
                    Image(systemName: confidenceIcon)
                        .foregroundColor(confidenceColor)
                    Text("\(Int(suggestion.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        )
        .frame(width: 380)
    }

    private var confidenceIcon: String {
        if suggestion.confidence >= 0.9 {
            return "star.fill"
        } else if suggestion.confidence >= 0.7 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }

    private var confidenceColor: Color {
        if suggestion.confidence >= 0.9 {
            return .yellow
        } else if suggestion.confidence >= 0.7 {
            return .orange
        } else {
            return .secondary
        }
    }
}

#Preview {
    StyleSuggestionPopoverContent(
        suggestion: StyleSuggestionModel(
            id: "test",
            originalStart: 0,
            originalEnd: 20,
            originalText: "This is really good",
            suggestedText: "This is excellent",
            explanation: "Consider using a more specific word to convey your meaning.",
            confidence: 0.85,
            style: .default,
            diff: [
                DiffSegmentModel(text: "This is ", kind: .unchanged),
                DiffSegmentModel(text: "really good", kind: .removed),
                DiffSegmentModel(text: "excellent", kind: .added)
            ]
        ),
        suggestionIndex: 0,
        totalSuggestions: 3,
        onAccept: {},
        onReject: { _ in },
        onPrevious: {},
        onNext: {},
        onDismiss: {}
    )
    .padding()
}
