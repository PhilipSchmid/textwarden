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

    /// Event monitor for Escape key
    private var escapeKeyMonitor: Any?

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

    /// Callback for adding word to dictionary
    var onAddToDictionary: ((GrammarErrorModel) -> Void)?

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
        } else {
            // Update panel size for new content
            if let hostingView = panel?.contentView?.subviews.first as? NSHostingView<PopoverContentView> {
                let fittingSize = hostingView.fittingSize
                let width = max(fittingSize.width, 280)
                let height = fittingSize.height

                hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
                panel?.contentView?.frame = NSRect(x: 0, y: 0, width: width, height: height)
                panel?.setContentSize(NSSize(width: width, height: height))
            }
        }

        // Position near cursor
        positionPanel(at: position)

        // Show panel
        panel?.orderFrontRegardless()
        panel?.makeKey()

        // Set up Escape key monitor
        setupEscapeKeyMonitor()
    }

    /// Schedule hiding of popover with a delay
    func scheduleHide() {
        // Cancel any existing timer
        hideTimer?.invalidate()

        // Schedule hide after 1 second delay (gives user time to move mouse into popover)
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
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
        // Remove escape key monitor
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }

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

    /// Setup Escape key monitor to close popover
    private func setupEscapeKeyMonitor() {
        // Remove existing monitor if any
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Add GLOBAL event monitor for Escape key
        // Global monitors can intercept events even when our app isn't active
        // This is necessary because the panel is .nonactivatingPanel
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                print("⌨️ Popover: Escape key pressed - hiding popover")
                self?.hide()
            }
        }
    }

    /// Create the panel
    private func createPanel() {
        let contentView = PopoverContentView(popover: self)

        let hostingView = NSHostingView(rootView: contentView)
        // Let SwiftUI determine the size based on content
        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 280)
        let height = fittingSize.height

        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        // Create custom tracking view that forwards mouse events
        let trackingView = PopoverTrackingView(popover: self)
        trackingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        trackingView.addSubview(hostingView)
        hostingView.frame = trackingView.bounds
        hostingView.autoresizingMask = [.width, .height]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel?.contentView = trackingView
        panel?.isFloatingPanel = true
        panel?.level = .floating
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.isMovableByWindowBackground = true
        panel?.title = "Grammar Suggestion"
        panel?.titlebarAppearsTransparent = false
        // Make panel background transparent so SwiftUI content's opacity works
        panel?.backgroundColor = .clear
        panel?.isOpaque = false

        // Handle close button
        panel?.standardWindowButton(.closeButton)?.target = self
        panel?.standardWindowButton(.closeButton)?.action = #selector(handleClose)
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
            origin.y = cursorPosition.y + 10 // Above with spacing
        } else {
            origin.y = cursorPosition.y - panelSize.height - 10 // Below with spacing
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

    /// Add word to custom dictionary
    func addToDictionary() {
        guard let error = currentError else { return }
        onAddToDictionary?(error)

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

    /// Base text size from preferences
    private var baseTextSize: CGFloat {
        CGFloat(preferences.suggestionTextSize)
    }

    /// Caption text size (85% of base)
    private var captionTextSize: CGFloat {
        baseTextSize * 0.85
    }

    /// Body text size (100% of base)
    private var bodyTextSize: CGFloat {
        baseTextSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = popover.currentError {
                // Main content with severity dot and message
                HStack(alignment: .top, spacing: 12) {
                    // Category indicator dot (matches underline color)
                    Circle()
                        .fill(categoryColor(for: error.category))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                        .accessibilityLabel("Category: \(error.category)")

                    VStack(alignment: .leading, spacing: 10) {
                        // Category label (small, secondary)
                        Text(error.category.uppercased())
                            .font(.system(size: captionTextSize, weight: .medium))
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Category: \(error.category)")

                        // Error message (only show if no suggestions available)
                        if error.suggestions.isEmpty {
                            Text(error.message)
                                .font(.system(size: bodyTextSize))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Error: \(error.message)")
                        }

                        // Suggestions
                        if !error.suggestions.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(Array(error.suggestions.prefix(3).enumerated()), id: \.offset) { index, suggestion in
                                    Button(action: {
                                        popover.applySuggestion(suggestion)
                                    }) {
                                        Text(suggestion)
                                            .font(.system(size: bodyTextSize))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                                    .help("Apply suggestion (⌘\(index + 1))")
                                    .accessibilityLabel("Apply suggestion: \(suggestion)")
                                    .accessibilityHint("Double tap to apply this suggestion")
                                }
                            }
                        }
                    }

                    Spacer()

                    // Close button (minimal, top-right)
                    Button(action: { popover.hide() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Close (Esc)")
                    .accessibilityLabel("Close suggestion popover")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Bottom action bar (minimal)
                Divider()

                HStack(spacing: 12) {
                    // Ignore button (strikethrough eye icon)
                    Button(action: { popover.dismissError() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 28, height: 28)
                            Image(systemName: "eye.slash")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Ignore this error")  // Try standard .help() first

                    // Ignore Rule button (prohibition icon)
                    Button(action: { popover.ignoreRule() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 28, height: 28)
                            Image(systemName: "nosign")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Never show this rule again")  // Try standard .help() first

                    // Add to Dictionary button (plus icon, only for Spelling errors)
                    if error.category == "Spelling" {
                        Button(action: { popover.addToDictionary() }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Add this word to your personal dictionary")  // Try standard .help() first
                    }

                    Spacer()

                    // Navigation controls (only show when multiple errors)
                    if popover.allErrors.count > 1 {
                        Text("\(popover.currentIndex + 1) of \(popover.allErrors.count)")
                            .font(.system(size: captionTextSize))
                            .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Button(action: { popover.previousError() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.upArrow, modifiers: [])
                            .help("Previous (↑)")

                            Button(action: { popover.nextError() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.downArrow, modifiers: [])
                            .help("Next (↓)")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                Text("No errors to display")
                    .foregroundColor(.secondary)
                    .padding()
                    .accessibilityLabel("No grammar errors to display")
            }
        }
        .frame(minWidth: 280, maxWidth: 400)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            // Use white/black with alpha for proper transparency without gray tint
            Color(white: effectiveColorScheme == .dark ? 0.15 : 1.0, opacity: preferences.suggestionOpacity)
        )
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        .colorScheme(effectiveColorScheme)
        .accessibilityElement(children: .contain)
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

    /// Get category color matching the underline color
    private func categoryColor(for category: String) -> Color {
        // Match the color scheme from ErrorOverlayWindow.underlineColor()
        switch category {
        // Spelling and typos: Red (critical, obvious errors)
        case "Spelling", "Typo":
            return .red

        // Grammar and structure: Orange (grammatical correctness)
        case "Grammar", "Agreement", "BoundaryError", "Capitalization", "Nonstandard", "Punctuation":
            return .orange

        // Style and enhancement: Blue (style improvements)
        case "Style", "Enhancement", "WordChoice", "Readability", "Redundancy", "Formatting":
            return .blue

        // Usage and word choice issues: Purple
        case "Usage", "Eggcorn", "Malapropism", "Regionalism", "Repetition":
            return .purple

        // Miscellaneous: Gray (fallback)
        default:
            return .gray
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
            // CRITICAL: AX API returns coordinates in top-left origin system (Quartz)
            // NSWindow uses bottom-left origin (AppKit)
            // Must flip Y coordinate using screen height
            if let screenHeight = NSScreen.main?.frame.height {
                let flippedY = screenHeight - rect.origin.y - rect.height
                return CGPoint(x: rect.origin.x, y: flippedY)
            }

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
            // CRITICAL: AX API returns coordinates in top-left origin system (Quartz)
            // NSWindow uses bottom-left origin (AppKit)
            // Must flip Y coordinate using screen height
            if let screenHeight = NSScreen.main?.frame.height {
                let flippedY = screenHeight - rect.origin.y - rect.height
                return CGPoint(x: rect.origin.x, y: flippedY)
            }

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

// MARK: - Popover Tracking View

/// Custom view that properly handles mouse tracking for the popover
class PopoverTrackingView: NSView {
    weak var popover: SuggestionPopover?

    init(popover: SuggestionPopover) {
        self.popover = popover
        super.init(frame: .zero)

        // Make the tracking view transparent
        self.wantsLayer = true
        self.layer?.backgroundColor = .clear

        setupTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTracking() {
        // Use .activeAlways to always track mouse position
        // Use .inVisibleRect so tracking area auto-updates with view size
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        print("🎯 Popover: Tracking area set up with bounds: \(bounds)")
    }

    override func mouseEntered(with event: NSEvent) {
        print("🖱️ Popover: Mouse ENTERED tracking view")
        popover?.cancelHide()
    }

    override func mouseExited(with event: NSEvent) {
        print("🖱️ Popover: Mouse EXITED tracking view")
        // Schedule hide after 1 second when mouse leaves
        popover?.scheduleHide()
    }
}

// MARK: - Custom Tooltip

/// Custom tooltip view with elegant design and smooth animations
struct TooltipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize() // Allow tooltip to grow to fit content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            )
    }
}

// MARK: - Reliable Hover Tracking for NSPanel/Floating Windows

/// Transparent NSView that receives tracking events but lets clicks pass through
class TransparentHoverView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTracking() {
        // Use .activeAlways for NSPanel/floating windows
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .inVisibleRect,
            .activeAlways  // Critical for NSPanel
        ]

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )

        addTrackingArea(trackingArea)
        print("🎯 [Tooltip Debug] TransparentHoverView setup complete with bounds: \(bounds)")
    }

    override func mouseEntered(with event: NSEvent) {
        print("🖱️ [Tooltip Debug] TransparentHoverView.mouseEntered")
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        print("🖱️ [Tooltip Debug] TransparentHoverView.mouseExited")
        onHoverChange?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil to let clicks pass through to buttons below
        // But tracking areas still work because mouseEntered/mouseExited
        // are called before hitTest determines the event target
        return nil
    }
}

/// Reliable hover tracking using NSTrackingArea (fixes SwiftUI's broken .onHover in NSPanel)
/// Based on: https://gist.github.com/importRyan/c668904b0c5442b80b6f38a980595031
struct ReliableHoverModifier: ViewModifier {
    let mouseIsInside: (Bool) -> Void

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { proxy in
                ReliableHoverRepresentable(
                    mouseIsInside: mouseIsInside,
                    frame: proxy.frame(in: .local)
                )
            }
            // REMOVED: .allowsHitTesting(false) - this was preventing tracking areas from working
            // The overlay is transparent anyway, so it won't interfere with button clicks
        )
    }
}

struct ReliableHoverRepresentable: NSViewRepresentable {
    let mouseIsInside: (Bool) -> Void
    let frame: NSRect

    func makeNSView(context: Context) -> TransparentHoverView {
        let view = TransparentHoverView(frame: frame)
        view.onHoverChange = mouseIsInside
        print("🎯 [Tooltip Debug] Created TransparentHoverView with frame: \(frame)")
        return view
    }

    func updateNSView(_ nsView: TransparentHoverView, context: Context) {
        // Update callback in case it changed
        nsView.onHoverChange = mouseIsInside
    }

    static func dismantleNSView(_ nsView: TransparentHoverView, coordinator: Void) {
        nsView.trackingAreas.forEach { nsView.removeTrackingArea($0) }
    }
}

extension View {
    /// Reliable hover tracking that works in NSPanel/floating windows
    func whenHovered(_ mouseIsInside: @escaping (Bool) -> Void) -> some View {
        modifier(ReliableHoverModifier(mouseIsInside: mouseIsInside))
    }
}

// MARK: - Floating Tooltip Panel

/// Manages a separate floating NSPanel for tooltips that sits above the suggestion popover
/// This is required because nonactivatingPanel blocks native tooltip mechanisms
class TooltipPanel {
    static let shared = TooltipPanel()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    private init() {
        setupPanel()
    }

    private func setupPanel() {
        // Create floating tooltip panel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel?.isOpaque = false
        panel?.backgroundColor = .clear
        panel?.hasShadow = true
        panel?.level = .floating + 10 // Higher than suggestion popover
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.ignoresMouseEvents = true // Let mouse events pass through
    }

    /// Show tooltip at specified screen position
    func show(_ text: String, at screenPosition: CGPoint, belowButton buttonFrame: CGRect) {
        guard let panel = panel else {
            print("⚠️ [Tooltip Debug] TooltipPanel.show - panel is nil!")
            return
        }

        print("📍 [Tooltip Debug] TooltipPanel.show - text: '\(text)', position: \(screenPosition), buttonFrame: \(buttonFrame)")

        // Cancel any pending hide
        hideTimer?.invalidate()
        hideTimer = nil

        // Create tooltip content view
        let tooltipView = TooltipContentView(text: text)
        let hostingView = NSHostingView(rootView: tooltipView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 40)

        panel.contentView = hostingView

        // Measure actual tooltip size
        let fittingSize = hostingView.fittingSize
        let tooltipWidth = max(fittingSize.width, 100)
        let tooltipHeight = fittingSize.height

        print("📍 [Tooltip Debug] TooltipPanel.show - measured size: \(tooltipWidth) x \(tooltipHeight)")

        // Position tooltip below button, centered horizontally
        let tooltipX = buttonFrame.midX - (tooltipWidth / 2)
        let tooltipY = buttonFrame.minY - tooltipHeight - 8 // 8pt spacing below button

        let tooltipFrame = NSRect(x: tooltipX, y: tooltipY, width: tooltipWidth, height: tooltipHeight)
        print("📍 [Tooltip Debug] TooltipPanel.show - final frame: \(tooltipFrame)")

        panel.setFrame(tooltipFrame, display: true)

        // Show tooltip
        print("📍 [Tooltip Debug] TooltipPanel.show - calling orderFrontRegardless()")
        panel.orderFrontRegardless()
        print("📍 [Tooltip Debug] TooltipPanel.show - panel level: \(panel.level.rawValue), isVisible: \(panel.isVisible)")
    }

    /// Hide tooltip with optional delay
    func hide(after delay: TimeInterval = 0) {
        print("📍 [Tooltip Debug] TooltipPanel.hide - delay: \(delay)")
        hideTimer?.invalidate()

        if delay > 0 {
            hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                print("📍 [Tooltip Debug] TooltipPanel.hide - hiding panel after delay")
                self?.panel?.orderOut(nil)
            }
        } else {
            print("📍 [Tooltip Debug] TooltipPanel.hide - hiding panel immediately")
            panel?.orderOut(nil)
        }
    }
}

/// SwiftUI view for tooltip content
struct TooltipContentView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
            .fixedSize()
    }
}

// MARK: - Floating Tooltip Modifier

/// View modifier that shows tooltip in separate floating panel
struct FloatingTooltip: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: TooltipPositionKey.self,
                        value: geometry.frame(in: .global)
                    )
                }
            )
            .onPreferenceChange(TooltipPositionKey.self) { frame in
                print("💡 [Tooltip Debug] onPreferenceChange - frame: \(frame), isHovering: \(isHovering)")
                if isHovering {
                    showTooltip(at: frame)
                }
            }
            .whenHovered { hovering in
                print("💡 [Tooltip Debug] whenHovered callback - hovering: \(hovering), text: '\(text)'")
                isHovering = hovering
                if hovering {
                    // Will show tooltip via preference change
                    print("💡 [Tooltip Debug] Mouse entered - waiting for preference change to show tooltip")
                } else {
                    print("💡 [Tooltip Debug] Mouse exited - hiding tooltip")
                    TooltipPanel.shared.hide()
                }
            }
    }

    private func showTooltip(at frame: CGRect) {
        guard isHovering else {
            print("💡 [Tooltip Debug] showTooltip called but not hovering - skipping")
            return
        }

        // Convert to screen coordinates (frame is already in global/screen coordinates)
        let screenFrame = frame
        let screenPosition = CGPoint(x: screenFrame.midX, y: screenFrame.minY)

        print("💡 [Tooltip Debug] Showing tooltip '\(text)' at position: \(screenPosition), frame: \(screenFrame)")
        TooltipPanel.shared.show(text, at: screenPosition, belowButton: screenFrame)
    }
}

struct TooltipPositionKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    /// Add floating tooltip that works in NSPanel/floating windows
    func floatingTooltip(_ text: String) -> some View {
        modifier(FloatingTooltip(text: text))
    }
}
