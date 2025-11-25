//
//  SuggestionPopover.swift
//  TextWarden
//
//  Displays grammar error suggestions in a popover near the cursor
//

import SwiftUI
import AppKit
import Combine
import ApplicationServices

/// Custom NSPanel subclass that prevents becoming key window
/// This is CRITICAL to prevent TextWarden from stealing focus from other apps
class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }
}

/// Manages the suggestion popover window
class SuggestionPopover: NSObject, ObservableObject {
    static let shared = SuggestionPopover()

    /// The popover panel
    private var panel: NonActivatingPanel?

    /// Timer for delayed hiding
    private var hideTimer: Timer?

    /// Event monitor for mouse clicks outside popover
    private var clickOutsideMonitor: Any?

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

    /// Callback when mouse enters popover (for cancelling delayed switches)
    var onMouseEntered: (() -> Void)?

    /// Check if popover is currently visible
    var isVisible: Bool {
        return panel?.isVisible == true && currentError != nil
    }

    private override init() {
        super.init()
    }

    /// Log to file for debugging (same as TextWardenApp)
    private func logToFile(_ message: String) {
        let logPath = "/tmp/textwarden-debug.log"
        let timestamp = Date()
        let logMessage = "[\(timestamp)] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    /// Show popover with error at cursor position
    /// - Parameters:
    ///   - error: The error to display
    ///   - allErrors: All errors for context
    ///   - position: Screen position for the popover
    ///   - constrainToWindow: Optional window frame to constrain popover positioning (keeps popover inside app window)
    func show(error: GrammarErrorModel, allErrors: [GrammarErrorModel], at position: CGPoint, constrainToWindow: CGRect? = nil) {
        // DEBUG: Log activation policy BEFORE showing
        Logger.debug("SuggestionPopover.show() - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)

        self.currentError = error
        self.allErrors = allErrors
        self.currentIndex = allErrors.firstIndex(where: { $0.start == error.start && $0.end == error.end }) ?? 0

        if panel == nil {
            createPanel()
        } else {
            if let trackingView = panel?.contentView as? PopoverTrackingView,
               let hostingView = trackingView.subviews.first as? NSHostingView<PopoverContentView> {
                // Force layout update
                hostingView.invalidateIntrinsicContentSize()
                hostingView.needsLayout = true
                hostingView.layoutSubtreeIfNeeded()

                let fittingSize = hostingView.fittingSize
                let width = min(max(fittingSize.width, 300), 450)  // Match frame constraints - reduced from 600 to prevent cutoffs
                let height = fittingSize.height

                hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
                trackingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
                panel?.setContentSize(NSSize(width: width, height: height))

                print("📐 Popover: Updated size to \(width) x \(height) (fitting: \(fittingSize))")
            }
        }

        // Position near cursor (with optional window constraint)
        positionPanel(at: position, constrainToWindow: constrainToWindow)

        // Use order(.above) instead of orderFrontRegardless() to prevent focus stealing
        panel?.order(.above, relativeTo: 0)

        // DEBUG: Log activation policy AFTER showing
        Logger.debug("SuggestionPopover.show() - AFTER order(.above) - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)

        setupClickOutsideMonitor()
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
        Logger.debug("SuggestionPopover.performHide() - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)

        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }

        panel?.orderOut(nil)
        currentError = nil
        allErrors = []
        currentIndex = 0
        hideTimer = nil

        // NOTE: We do NOT restore focus because our panels are .nonactivatingPanel
        // They never steal focus in the first place, so there's nothing to restore.
        // When the user clicks elsewhere, the click naturally activates the clicked app.
        // Any attempt to call activate() would FIGHT with the app's natural activation,
        // causing delays and making apps temporarily unclickable (especially on macOS 14+
        // where activateIgnoringOtherApps is deprecated and ignored).

        Logger.debug("SuggestionPopover.performHide() - AFTER - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)
    }

    /// Hide popover immediately
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        performHide()
    }

    /// Setup click outside monitor to close popover when user clicks elsewhere
    private func setupClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Use GLOBAL monitor to detect ALL clicks (including in other apps like Chrome)
        // When user clicks outside, hide the popover
        // The click will naturally activate the clicked app (we can't prevent event propagation)
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }

            Logger.debug("Popover: Global click detected - hiding popover", category: Logger.ui)

            // CRITICAL: Cancel any pending auto-hide timer
            self.hideTimer?.invalidate()
            self.hideTimer = nil

            self.hide()
        }
    }

    /// Create the panel
    private func createPanel() {
        let contentView = PopoverContentView(popover: self)

        let hostingView = NSHostingView(rootView: contentView)
        // Force initial layout
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()

        // Let SwiftUI determine the size based on content
        let fittingSize = hostingView.fittingSize
        let width = min(max(fittingSize.width, 300), 450)  // Match frame constraints - reduced from 600 to prevent cutoffs
        let height = fittingSize.height

        print("📐 Popover: Initial creation size: \(width) x \(height) (fitting: \(fittingSize))")

        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let trackingView = PopoverTrackingView(popover: self)
        trackingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        trackingView.addSubview(hostingView)
        hostingView.frame = trackingView.bounds
        hostingView.autoresizingMask = [.width, .height]

        panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel?.contentView = trackingView
        panel?.isFloatingPanel = true
        panel?.level = .popUpMenu  // Use popUpMenu level - these never activate the app
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.isMovableByWindowBackground = true
        panel?.title = "Grammar Suggestion"
        panel?.titlebarAppearsTransparent = false
        // Make panel background transparent so SwiftUI content's opacity works
        panel?.backgroundColor = .clear
        panel?.isOpaque = false
        // CRITICAL: Prevent this panel from affecting app activation
        panel?.hidesOnDeactivate = false
        panel?.worksWhenModal = false
        // CRITICAL: This makes the panel resist becoming the key window
        // According to Stack Overflow, this is essential for truly non-activating behavior
        panel?.becomesKeyOnlyIfNeeded = true

        // Handle close button
        panel?.standardWindowButton(.closeButton)?.target = self
        panel?.standardWindowButton(.closeButton)?.action = #selector(handleClose)
    }

    /// Position panel near cursor (T042)
    /// - Parameters:
    ///   - cursorPosition: The screen position for the popover
    ///   - constrainToWindow: Optional window frame to constrain positioning (keeps popover inside app window)
    private func positionPanel(at cursorPosition: CGPoint, constrainToWindow: CGRect? = nil) {
        guard let panel = panel, let screen = NSScreen.main else { return }

        Logger.debug("Popover: Input cursor position (screen): \(cursorPosition)", category: Logger.ui)

        let panelSize = panel.frame.size
        let preferences = UserPreferences.shared

        // Use constrainToWindow if provided, otherwise use screen frame
        let constraintFrame = constrainToWindow ?? screen.visibleFrame

        if let windowFrame = constrainToWindow {
            Logger.debug("Popover: Using window constraint: \(windowFrame)", category: Logger.ui)
        } else {
            Logger.debug("Popover: Using screen frame: \(screen.visibleFrame)", category: Logger.ui)
        }

        Logger.debug("Popover: Panel size: \(panelSize), Constraint frame: \(constraintFrame)", category: Logger.ui)

        Logger.debug("Popover: Cursor position: \(cursorPosition)", category: Logger.ui)

        // Calculate available space in all directions
        let padding: CGFloat = 20  // Increased from 10 to give more breathing room
        let roomAbove = constraintFrame.maxY - cursorPosition.y
        let roomBelow = cursorPosition.y - constraintFrame.minY
        let roomLeft = cursorPosition.x - constraintFrame.minX
        let roomRight = constraintFrame.maxX - cursorPosition.x

        Logger.debug("Popover: Room - Above: \(roomAbove), Below: \(roomBelow), Left: \(roomLeft), Right: \(roomRight)", category: Logger.ui)

        // Dynamically adjust panel width if it would exceed available space
        var adjustedPanelSize = panelSize
        let maxAvailableWidth = max(roomLeft, roomRight) - padding * 3  // Extra padding for safety
        if panelSize.width > maxAvailableWidth {
            adjustedPanelSize.width = max(300, maxAvailableWidth)  // Minimum 300px, or available space

            Logger.debug("Popover: Reducing width from \(panelSize.width) to \(adjustedPanelSize.width) (available: \(maxAvailableWidth))", category: Logger.ui)

            // Resize panel and content views
            if let trackingView = panel.contentView as? PopoverTrackingView,
               let hostingView = trackingView.subviews.first as? NSHostingView<PopoverContentView> {
                hostingView.frame = NSRect(x: 0, y: 0, width: adjustedPanelSize.width, height: adjustedPanelSize.height)
                trackingView.frame = NSRect(x: 0, y: 0, width: adjustedPanelSize.width, height: adjustedPanelSize.height)
                panel.setContentSize(NSSize(width: adjustedPanelSize.width, height: adjustedPanelSize.height))
            }
        }

        // Determine vertical positioning
        var shouldPositionAbove: Bool
        switch preferences.suggestionPosition {
        case "Above":
            shouldPositionAbove = true
        case "Below":
            shouldPositionAbove = false
        default: // "Auto"
            // Prefer above for floating indicators, but only if there's enough room
            shouldPositionAbove = roomAbove >= adjustedPanelSize.height + padding * 2
            if !shouldPositionAbove && roomBelow < adjustedPanelSize.height + padding * 2 {
                // Neither direction has enough room - choose the one with more space
                shouldPositionAbove = roomAbove > roomBelow
            }
        }

        Logger.debug("Popover: shouldPositionAbove: \(shouldPositionAbove)", category: Logger.ui)

        // Calculate vertical position
        var origin = CGPoint.zero
        if shouldPositionAbove {
            origin.y = cursorPosition.y + padding
        } else {
            origin.y = cursorPosition.y - adjustedPanelSize.height - padding
        }

        // Determine horizontal positioning (prefer left for floating indicator at right edge)
        let shouldPositionLeft = roomLeft >= adjustedPanelSize.width + padding * 2
        if shouldPositionLeft {
            origin.x = cursorPosition.x - adjustedPanelSize.width - padding
        } else if roomRight >= adjustedPanelSize.width + padding * 2 {
            origin.x = cursorPosition.x + padding
        } else {
            // Neither side has enough room - center it as best we can
            origin.x = max(constraintFrame.minX + padding, min(cursorPosition.x - adjustedPanelSize.width / 2, constraintFrame.maxX - adjustedPanelSize.width - padding))
        }

        Logger.debug("Popover: Initial position: \(origin)", category: Logger.ui)

        // Final bounds check to ensure panel stays fully within constraint frame
        // Horizontal clamping - ensure popover stays within bounds
        if origin.x < constraintFrame.minX + padding {
            origin.x = constraintFrame.minX + padding
            Logger.debug("Popover: Clamped to minX: \(origin.x)", category: Logger.ui)
        }
        if origin.x + adjustedPanelSize.width > constraintFrame.maxX - padding {
            // Clamp to right edge, but don't push past left edge
            let rightClamped = constraintFrame.maxX - adjustedPanelSize.width - padding
            origin.x = max(constraintFrame.minX + padding, rightClamped)
            Logger.debug("Popover: Clamped to maxX: rightClamped=\(rightClamped), final=\(origin.x)", category: Logger.ui)
        }

        // Vertical clamping (ensure entire panel is visible)
        if origin.y < constraintFrame.minY + padding {
            origin.y = constraintFrame.minY + padding
            Logger.debug("Popover: Clamped to minY: \(origin.y)", category: Logger.ui)
        }
        if origin.y + adjustedPanelSize.height > constraintFrame.maxY - padding {
            origin.y = constraintFrame.maxY - adjustedPanelSize.height - padding
            Logger.debug("Popover: Clamped to maxY: \(origin.y)", category: Logger.ui)
        }

        Logger.debug("Popover: Final position: \(origin), will show at: (\(origin.x), \(origin.y)) to (\(origin.x + adjustedPanelSize.width), \(origin.y + adjustedPanelSize.height))", category: Logger.ui)
        panel.setFrameOrigin(origin)
    }

    /// Handle close button
    @objc private func handleClose() {
        hide()
    }

    /// Resize panel to fit current content
    private func resizePanel() {
        guard let panel = panel else { return }

        if let trackingView = panel.contentView as? PopoverTrackingView,
           let hostingView = trackingView.subviews.first as? NSHostingView<PopoverContentView> {

            // Force SwiftUI to recalculate size
            hostingView.invalidateIntrinsicContentSize()
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()

            let fittingSize = hostingView.fittingSize
            let width = min(max(fittingSize.width, 300), 450)  // Match frame constraints - reduced from 600 to prevent cutoffs
            let height = fittingSize.height

            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            trackingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

            let currentOrigin = panel.frame.origin

            // Resize panel while keeping same origin
            panel.setFrame(NSRect(x: currentOrigin.x, y: currentOrigin.y, width: width, height: height), display: true, animate: false)

            print("📐 Popover: Resized to \(width) x \(height) (fitting: \(fittingSize))")
        }
    }

    /// Navigate to next error (T047)
    func nextError() {
        guard !allErrors.isEmpty else { return }
        currentIndex = (currentIndex + 1) % allErrors.count
        currentError = allErrors[currentIndex]

        // Resize panel after slight delay to let SwiftUI update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.resizePanel()
        }
    }

    /// Navigate to previous error (T047)
    func previousError() {
        guard !allErrors.isEmpty else { return }
        currentIndex = (currentIndex - 1 + allErrors.count) % allErrors.count
        currentError = allErrors[currentIndex]

        // Resize panel after slight delay to let SwiftUI update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.resizePanel()
        }
    }

    /// Apply suggestion (T044)
    func applySuggestion(_ suggestion: String) {
        guard let error = currentError else { return }
        onApplySuggestion?(error, suggestion)

        // Move to next error or hide
        if allErrors.count > 1 {
            allErrors.removeAll { $0.start == error.start && $0.end == error.end }
            if currentIndex >= allErrors.count {
                currentIndex = 0
            }
            currentError = allErrors.isEmpty ? nil : allErrors[currentIndex]

            if currentError == nil {
                hide()
            } else {
                // Resize panel after slight delay to let SwiftUI update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.resizePanel()
                }
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
            } else {
                // Resize panel after slight delay to let SwiftUI update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.resizePanel()
                }
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
            } else {
                // Resize panel after slight delay to let SwiftUI update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.resizePanel()
                }
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
            } else {
                // Resize panel after slight delay to let SwiftUI update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.resizePanel()
                }
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

    /// App color scheme
    private var colors: AppColors {
        AppColors(for: effectiveColorScheme)
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
                // Main content with category indicator and message
                HStack(alignment: .top, spacing: 16) {
                    // Subtle category indicator
                    Circle()
                        .fill(colors.categoryColor(for: error.category))
                        .frame(width: 6, height: 6)
                        .padding(.top, 8)
                        .accessibilityLabel("Category: \(error.category)")

                    VStack(alignment: .leading, spacing: 12) {
                        // Clean category label
                        Text(error.category.uppercased())
                            .font(.system(size: captionTextSize, weight: .semibold, design: .rounded))
                            .foregroundColor(colors.textSecondary)
                            .tracking(0.6)
                            .accessibilityLabel("Category: \(error.category)")

                        // Error message (only show if no suggestions available)
                        if error.suggestions.isEmpty {
                            Text(error.message)
                                .font(.system(size: bodyTextSize))
                                .foregroundColor(colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Error: \(error.message)")
                        }

                        // Clean blue suggestion buttons
                        if !error.suggestions.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(Array(error.suggestions.prefix(3).enumerated()), id: \.offset) { index, suggestion in
                                    Button(action: {
                                        popover.applySuggestion(suggestion)
                                    }) {
                                        Text(suggestion)
                                            .font(.system(size: bodyTextSize, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 7)
                                                    .fill(colors.primary)
                                            )
                                            .shadow(color: colors.primary.opacity(0.25), radius: 4, x: 0, y: 2)
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Clean close button
                    VStack {
                        Button(action: { popover.hide() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                                .frame(width: 20, height: 20)
                                .background(colors.backgroundRaised)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: .option)
                        .help("Close (⌥Esc)")
                        .accessibilityLabel("Close suggestion popover")

                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 18)

                // Bottom action bar with subtle border
                Divider()
                    .background(colors.border)

                HStack(spacing: 12) {
                    // Ignore button - Light blue accent
                    Button(action: { popover.dismissError() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(
                                    Color(
                                        hue: 215/360,
                                        saturation: 0.30,
                                        brightness: effectiveColorScheme == .dark ? 0.18 : 0.93
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(
                                            Color(hue: 215/360, saturation: 0.40, brightness: effectiveColorScheme == .dark ? 0.30 : 0.80),
                                            lineWidth: 1
                                        )
                                )
                                .frame(width: 34, height: 34)
                            Image(systemName: "eye.slash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(
                                    Color(hue: 215/360, saturation: 0.70, brightness: effectiveColorScheme == .dark ? 0.75 : 0.45)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Ignore this error")

                    // Ignore Rule button - Medium blue accent
                    Button(action: { popover.ignoreRule() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(
                                    Color(
                                        hue: 215/360,
                                        saturation: 0.35,
                                        brightness: effectiveColorScheme == .dark ? 0.20 : 0.91
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(
                                            Color(hue: 215/360, saturation: 0.45, brightness: effectiveColorScheme == .dark ? 0.35 : 0.75),
                                            lineWidth: 1
                                        )
                                )
                                .frame(width: 34, height: 34)
                            Image(systemName: "nosign")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(
                                    Color(hue: 215/360, saturation: 0.75, brightness: effectiveColorScheme == .dark ? 0.70 : 0.40)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Never show this rule again")

                    if error.category == "Spelling" {
                        Button(action: { popover.addToDictionary() }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(
                                        Color(
                                            hue: 215/360,
                                            saturation: 0.50,
                                            brightness: effectiveColorScheme == .dark ? 0.25 : 0.88
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(colors.primary.opacity(0.5), lineWidth: 1)
                                    )
                                    .frame(width: 34, height: 34)
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(colors.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Add this word to your personal dictionary")
                    }

                    Spacer()

                    // Navigation controls (only show when multiple errors)
                    if popover.allErrors.count > 1 {
                        Text("\(popover.currentIndex + 1) of \(popover.allErrors.count)")
                            .font(.system(size: captionTextSize, weight: .semibold))
                            .foregroundColor(
                                Color(hue: 215/360, saturation: 0.65, brightness: effectiveColorScheme == .dark ? 0.80 : 0.50)
                            )

                        HStack(spacing: 6) {
                            Button(action: { popover.previousError() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(hue: 215/360, saturation: 0.70, brightness: effectiveColorScheme == .dark ? 0.60 : 0.55),
                                                Color(hue: 215/360, saturation: 0.75, brightness: effectiveColorScheme == .dark ? 0.50 : 0.48)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(6)
                                    .shadow(color: colors.primary.opacity(0.2), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.upArrow, modifiers: [])
                            .help("Previous (↑)")

                            Button(action: { popover.nextError() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(hue: 215/360, saturation: 0.70, brightness: effectiveColorScheme == .dark ? 0.60 : 0.55),
                                                Color(hue: 215/360, saturation: 0.75, brightness: effectiveColorScheme == .dark ? 0.50 : 0.48)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(6)
                                    .shadow(color: colors.primary.opacity(0.2), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.downArrow, modifiers: [])
                            .help("Next (↓)")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            } else {
                Text("No errors to display")
                    .foregroundColor(colors.textSecondary)
                    .padding()
                    .accessibilityLabel("No grammar errors to display")
            }
        }
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                // Gradient background with blue tones
                LinearGradient(
                    colors: [
                        Color(
                            hue: 215/360,
                            saturation: effectiveColorScheme == .dark ? 0.12 : 0.08,
                            brightness: effectiveColorScheme == .dark ? 0.11 : 0.96
                        ),
                        Color(
                            hue: 215/360,
                            saturation: effectiveColorScheme == .dark ? 0.18 : 0.12,
                            brightness: effectiveColorScheme == .dark ? 0.09 : 0.94
                        )
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(preferences.suggestionOpacity)

                // Subtle blue accent glow in top-right corner
                RadialGradient(
                    colors: [
                        Color(hue: 215/360, saturation: 0.60, brightness: effectiveColorScheme == .dark ? 0.25 : 0.85).opacity(effectiveColorScheme == .dark ? 0.08 : 0.06),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 200
                )
            }
        )
        .overlay(
            // Border with blue gradient
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(hue: 215/360, saturation: 0.40, brightness: effectiveColorScheme == .dark ? 0.35 : 0.70).opacity(0.4),
                            Color(hue: 215/360, saturation: 0.30, brightness: effectiveColorScheme == .dark ? 0.25 : 0.80).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
        .cornerRadius(10)
        .shadow(color: colors.shadowColor, radius: 12, x: 0, y: 4)
        .shadow(color: Color(hue: 215/360, saturation: 0.60, brightness: 0.50).opacity(0.10), radius: 6, x: 0, y: 2)
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
        let location = error.start
        let length = error.end - error.start

        var range = CFRange(location: location, length: max(1, length))
        let rangeValue = AXValueCreate(.cfRange, &range)!

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
        popover?.onMouseEntered?()
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

        print("📍 [Tooltip Debug] TooltipPanel.show - calling order(.above)")
        panel.order(.above, relativeTo: 0)
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
