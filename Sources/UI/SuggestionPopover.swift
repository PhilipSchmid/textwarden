//
//  SuggestionPopover.swift
//  Gnau
//
//  Displays grammar error suggestions in a popover near the cursor
//

import SwiftUI
import AppKit
import Combine
import ApplicationServices

/// Manages the suggestion popover window
class SuggestionPopover: NSObject, ObservableObject {
    static let shared = SuggestionPopover()

    /// The popover panel
    private var panel: NSPanel?

    /// Timer for delayed hiding
    private var hideTimer: Timer?

    /// Current error being displayed
    @Published private(set) var currentError: GrammarErrorModel?

    /// All errors for context
    @Published var allErrors: [GrammarErrorModel] = []

    /// Current error index
    @Published var currentIndex: Int = 0

    /// Callback for applying suggestion
    var onApplySuggestion: ((GrammarErrorModel, String) -> Void)?

    /// Callback for dismissing error
    var onDismissError: ((GrammarErrorModel) -> Void)?

    /// Callback for ignoring rule
    var onIgnoreRule: ((String) -> Void)?

    private override init() {
        super.init()
    }

    /// Show popover with error at cursor position
    func show(error: GrammarErrorModel, allErrors: [GrammarErrorModel], at position: CGPoint) {
        self.currentError = error
        self.allErrors = allErrors
        self.currentIndex = allErrors.firstIndex(where: { $0.start == error.start && $0.end == error.end }) ?? 0

        // Create or update panel
        if panel == nil {
            createPanel()
        }

        // Position near cursor
        positionPanel(at: position)

        // Show panel
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    /// Schedule hiding of popover with a delay
    func scheduleHide() {
        // Cancel any existing timer
        hideTimer?.invalidate()

        // Schedule hide after 300ms delay
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.performHide()
        }
    }

    /// Cancel scheduled hide
    func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    /// Perform immediate hide
    private func performHide() {
        panel?.orderOut(nil)
        currentError = nil
        allErrors = []
        currentIndex = 0
        hideTimer = nil
    }

    /// Hide popover immediately
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        performHide()
    }

    /// Create the panel
    private func createPanel() {
        let contentView = PopoverContentView(popover: self)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 250)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 250),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel?.contentView = hostingView
        panel?.isFloatingPanel = true
        panel?.level = .floating
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.isMovableByWindowBackground = true
        panel?.title = "Grammar Suggestion"
        panel?.titlebarAppearsTransparent = false
        panel?.backgroundColor = .windowBackgroundColor

        // Handle close button
        panel?.standardWindowButton(.closeButton)?.target = self
        panel?.standardWindowButton(.closeButton)?.action = #selector(handleClose)

        // Setup mouse tracking
        if let contentView = panel?.contentView {
            let trackingArea = NSTrackingArea(
                rect: contentView.bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            contentView.addTrackingArea(trackingArea)
        }
    }

    /// Mouse entered the popover - cancel hiding
    func mouseEntered(with event: NSEvent) {
        cancelHide()
    }

    /// Mouse exited the popover - schedule hiding
    func mouseExited(with event: NSEvent) {
        scheduleHide()
    }

    /// Position panel near cursor (T042)
    private func positionPanel(at cursorPosition: CGPoint) {
        guard let panel = panel, let screen = NSScreen.main else { return }

        print("📍 Popover: Input cursor position (screen): \(cursorPosition)")

        let panelSize = panel.frame.size
        let preferences = UserPreferences.shared
        var origin = cursorPosition

        // Offset horizontally
        origin.x += 5

        // Determine vertical positioning based on user preference
        let shouldPositionAbove: Bool
        switch preferences.suggestionPosition {
        case "Above":
            shouldPositionAbove = true
        case "Below":
            shouldPositionAbove = false
        default: // "Auto"
            // Auto: position below if there's room, otherwise above
            let roomBelow = cursorPosition.y - panelSize.height - 5 >= screen.visibleFrame.minY
            shouldPositionAbove = !roomBelow
        }

        if shouldPositionAbove {
            origin.y = cursorPosition.y + 5 // Above
        } else {
            origin.y = cursorPosition.y - panelSize.height - 5 // Below
        }

        print("📍 Popover: After offset, before bounds check: \(origin)")

        // Ensure panel stays on screen
        let screenFrame = screen.visibleFrame
        print("📍 Popover: Screen visible frame: \(screenFrame)")

        // Adjust horizontal position
        if origin.x + panelSize.width > screenFrame.maxX {
            origin.x = screenFrame.maxX - panelSize.width - 10
        }
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + 10
        }

        // Adjust vertical position to stay on screen
        if origin.y < screenFrame.minY {
            origin.y = screenFrame.minY + 5
        }
        if origin.y + panelSize.height > screenFrame.maxY {
            origin.y = screenFrame.maxY - panelSize.height - 5
        }

        print("✅ Popover: Final position: \(origin)")
        panel.setFrameOrigin(origin)
    }

    /// Handle close button
    @objc private func handleClose() {
        hide()
    }

    /// Navigate to next error (T047)
    func nextError() {
        guard !allErrors.isEmpty else { return }
        currentIndex = (currentIndex + 1) % allErrors.count
        currentError = allErrors[currentIndex]
    }

    /// Navigate to previous error (T047)
    func previousError() {
        guard !allErrors.isEmpty else { return }
        currentIndex = (currentIndex - 1 + allErrors.count) % allErrors.count
        currentError = allErrors[currentIndex]
    }

    /// Apply suggestion (T044)
    func applySuggestion(_ suggestion: String) {
        guard let error = currentError else { return }
        onApplySuggestion?(error, suggestion)

        // Move to next error or hide
        if allErrors.count > 1 {
            // Remove applied error
            allErrors.removeAll { $0.start == error.start && $0.end == error.end }
            if currentIndex >= allErrors.count {
                currentIndex = 0
            }
            currentError = allErrors.isEmpty ? nil : allErrors[currentIndex]

            if currentError == nil {
                hide()
            }
        } else {
            hide()
        }
    }

    /// Dismiss error for session (T045, T048)
    func dismissError() {
        guard let error = currentError else { return }
        onDismissError?(error)

        // Move to next error or hide
        if allErrors.count > 1 {
            allErrors.removeAll { $0.start == error.start && $0.end == error.end }
            if currentIndex >= allErrors.count {
                currentIndex = 0
            }
            currentError = allErrors.isEmpty ? nil : allErrors[currentIndex]

            if currentError == nil {
                hide()
            }
        } else {
            hide()
        }
    }

    /// Ignore rule permanently (T046, T050)
    func ignoreRule() {
        guard let error = currentError else { return }
        onIgnoreRule?(error.lintId)

        // Move to next error or hide
        if allErrors.count > 1 {
            allErrors.removeAll { $0.lintId == error.lintId }
            if currentIndex >= allErrors.count {
                currentIndex = 0
            }
            currentError = allErrors.isEmpty ? nil : allErrors[currentIndex]

            if currentError == nil {
                hide()
            }
        } else {
            hide()
        }
    }
}

/// SwiftUI content view for popover (T043)
struct PopoverContentView: View {
    @ObservedObject var popover: SuggestionPopover
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.colorScheme) var systemColorScheme

    /// Effective color scheme based on user preference
    private var effectiveColorScheme: ColorScheme {
        switch preferences.suggestionTheme {
        case "Light":
            return .light
        case "Dark":
            return .dark
        default: // "System"
            return systemColorScheme
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = popover.currentError {
                // Header bar with severity and error type
                HStack(spacing: 8) {
                    severityIndicator(for: error.severity)
                        .accessibilityLabel(severityAccessibilityLabel(for: error.severity)) // T130

                    Text(error.severity.description)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .foregroundColor(severityColor(for: error.severity))
                    Spacer()

                    // Close button
                    Button(action: { popover.hide() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: []) // T124
                    .help("Close (Esc)")
                    .accessibilityLabel("Close suggestion popover") // T130
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(severityColor(for: error.severity).opacity(0.1))
                .accessibilityElement(children: .combine) // T121

                // Error message (T126: Dynamic Type support)
                Text(error.message)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Error: \(error.message)") // T121, T130

                // Suggestions section
                if !error.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestions:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        ForEach(Array(error.suggestions.prefix(3).enumerated()), id: \.offset) { index, suggestion in
                            Button(action: {
                                popover.applySuggestion(suggestion)
                            }) {
                                HStack {
                                    Text(suggestion)
                                        .font(.body) // T126: Respects Dynamic Type
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.turn.down.left")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command) // T124
                            .padding(.horizontal, 12)
                            .help("Apply suggestion (⌘\(index + 1))")
                            .accessibilityLabel("Apply suggestion: \(suggestion)") // T121, T130
                            .accessibilityHint("Double tap to apply this suggestion")
                        }
                    }
                    .padding(.bottom, 8)
                } else {
                    Text("No suggestions available")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityLabel("No suggestions available for this error") // T130
                }

                Divider()

                // Action bar (T124: Keyboard shortcuts)
                HStack(spacing: 12) {
                    Button(action: { popover.dismissError() }) {
                        Text("Ignore")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Ignore this error (Esc)")
                    .accessibilityLabel("Ignore this error") // T130
                    .accessibilityHint("This error will be hidden for this session")

                    Button(action: { popover.ignoreRule() }) {
                        Text("Ignore Rule")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Never show this rule again")
                    .accessibilityLabel("Ignore rule permanently") // T130
                    .accessibilityHint("This grammar rule will be permanently disabled")

                    Spacer()

                    // Navigation (T124: Keyboard navigation)
                    if popover.allErrors.count > 1 {
                        Text("\(popover.currentIndex + 1) of \(popover.allErrors.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Error \(popover.currentIndex + 1) of \(popover.allErrors.count)") // T130

                        HStack(spacing: 4) {
                            Button(action: { popover.previousError() }) {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.upArrow, modifiers: []) // T124
                            .help("Previous (↑)")
                            .accessibilityLabel("Previous error") // T130

                            Button(action: { popover.nextError() }) {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.downArrow, modifiers: []) // T124
                            .help("Next (↓)")
                            .accessibilityLabel("Next error") // T130
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                Text("No errors to display")
                    .foregroundColor(.secondary)
                    .padding()
                    .accessibilityLabel("No grammar errors to display") // T130
            }
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        .opacity(preferences.suggestionOpacity)
        .font(.system(size: CGFloat(preferences.suggestionTextSize)))
        .colorScheme(effectiveColorScheme)
        .accessibilityElement(children: .contain) // T121: VoiceOver container
    }

    /// Severity indicator with color (T043)
    @ViewBuilder
    private func severityIndicator(for severity: GrammarErrorSeverity) -> some View {
        let (color, icon) = severityStyle(for: severity)

        Image(systemName: icon)
            .foregroundColor(color)
            .font(.title3)
    }

    /// Get severity color and icon
    private func severityStyle(for severity: GrammarErrorSeverity) -> (Color, String) {
        switch severity {
        case .error:
            return (.red, "exclamationmark.circle.fill")
        case .warning:
            return (.orange, "exclamationmark.triangle.fill")
        case .info:
            return (.blue, "info.circle.fill")
        }
    }

    /// Get severity color only (T129: Color-blind friendly)
    private func severityColor(for severity: GrammarErrorSeverity) -> Color {
        switch severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }

    /// Get severity color for high contrast mode (T128)
    @ViewBuilder
    private func severityColorForContrast(for severity: GrammarErrorSeverity) -> some View {
        let baseColor = severityColor(for: severity)

        // In high contrast mode, increase color intensity
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            baseColor.brightness(-0.2)
        } else {
            baseColor
        }
    }

    /// Accessibility label for severity (T130)
    private func severityAccessibilityLabel(for severity: GrammarErrorSeverity) -> String {
        switch severity {
        case .error:
            return "Error: Critical grammar issue"
        case .warning:
            return "Warning: Grammar suggestion"
        case .info:
            return "Info: Style recommendation"
        }
    }
}

// MARK: - Position Helper

extension SuggestionPopover {
    /// Get position for error range in AX element
    static func getErrorPosition(in element: AXUIElement, for error: GrammarErrorModel) -> CGPoint? {
        // Create CFRange for the error location
        let location = error.start
        let length = error.end - error.start

        var range = CFRange(location: location, length: max(1, length))
        let rangeValue = AXValueCreate(.cfRange, &range)!

        // Get bounds for error range
        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard boundsError == .success,
              let axValue = boundsValue,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return getCursorPosition(in: element)
        }

        // Extract CGRect from AXValue
        var rect = CGRect.zero
        let success = AXValueGetValue(axValue as! AXValue, .cgRect, &rect)

        if success {
            // Return bottom-left corner (to position popup below error)
            return CGPoint(x: rect.origin.x, y: rect.origin.y)
        }

        return getCursorPosition(in: element)
    }

    /// Get cursor position from AX element (T042)
    static func getCursorPosition(in element: AXUIElement) -> CGPoint? {
        // Try to get selected text range
        var rangeValue: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )

        guard rangeError == .success,
              let range = rangeValue else {
            return nil
        }

        // Get bounds for selection
        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        )

        guard boundsError == .success,
              let axValue = boundsValue,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return fallbackCursorPosition()
        }

        // Extract CGRect from AXValue
        var rect = CGRect.zero
        let success = AXValueGetValue(axValue as! AXValue, .cgRect, &rect)

        if success {
            // Return bottom-left corner of selection
            return CGPoint(x: rect.origin.x, y: rect.origin.y)
        }

        return fallbackCursorPosition()
    }

    /// Fallback cursor position (center of screen)
    static func fallbackCursorPosition() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 400, y: 400)
        }

        let frame = screen.visibleFrame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}
