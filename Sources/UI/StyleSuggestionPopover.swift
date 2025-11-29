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

    /// The popover window
    private var popoverWindow: NSWindow?

    /// Callback when suggestion is accepted
    var onAccept: ((StyleSuggestionModel) -> Void)?

    /// Callback when suggestion is rejected
    var onReject: ((StyleSuggestionModel, SuggestionRejectionCategory) -> Void)?

    /// Callback when popover is dismissed
    var onDismiss: (() -> Void)?

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

        // Create or update popover window
        if popoverWindow == nil {
            createPopoverWindow()
        }

        updateContent()
        positionPopover(at: position, constrainTo: windowFrame)
        popoverWindow?.orderFront(nil)
    }

    /// Hide the popover
    func hide() {
        popoverWindow?.orderOut(nil)
        currentSuggestion = nil
    }

    /// Schedule delayed hide (for mouse tracking)
    func scheduleHide(after delay: TimeInterval = 0.3) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            // Only hide if mouse is not over the popover
            if let window = self.popoverWindow,
               !window.frame.contains(NSEvent.mouseLocation) {
                self.hide()
            }
        }
    }

    /// Cancel any pending hide
    func cancelHide() {
        // In a full implementation, this would cancel the delayed hide timer
    }

    // MARK: - Private Methods

    private func createPopoverWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.hasShadow = true
        window.isMovableByWindowBackground = false

        popoverWindow = window
    }

    private func updateContent() {
        guard let suggestion = currentSuggestion else { return }

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

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)

        popoverWindow?.contentView = hostingView
        popoverWindow?.setContentSize(hostingView.fittingSize)
    }

    private func positionPopover(at position: CGPoint, constrainTo windowFrame: CGRect?) {
        guard let window = popoverWindow else { return }

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
