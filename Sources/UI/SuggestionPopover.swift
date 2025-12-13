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

/// Mode for the popover - determines which content is shown
enum PopoverMode {
    case grammarError
    case styleSuggestion
}

/// Unified item that can hold either a grammar error or style suggestion
enum PopoverItem {
    case grammar(GrammarErrorModel)
    case style(StyleSuggestionModel)

    /// Start position for sorting
    var startPosition: Int {
        switch self {
        case .grammar(let error): return error.start
        case .style(let suggestion): return suggestion.originalStart
        }
    }
}

/// Manages the suggestion popover window
@MainActor
class SuggestionPopover: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = SuggestionPopover()

    // MARK: - Properties

    /// The popover panel
    private var panel: NonActivatingPanel?

    /// Timer for delayed hiding
    private var hideTimer: Timer?

    /// Event monitor for mouse clicks outside popover
    private var clickOutsideMonitor: Any?

    /// Current mode (grammar or style)
    @Published private(set) var mode: PopoverMode = .grammarError

    /// Current error being displayed (grammar mode)
    @Published private(set) var currentError: GrammarErrorModel?

    /// All errors for context (grammar mode)
    @Published var allErrors: [GrammarErrorModel] = []

    /// Current error index (grammar mode)
    @Published var currentIndex: Int = 0

    /// Source text for error context display
    @Published var sourceText: String = ""

    /// Current style suggestion being displayed (style mode)
    @Published private(set) var currentStyleSuggestion: StyleSuggestionModel?

    /// All style suggestions for context (style mode)
    @Published var allStyleSuggestions: [StyleSuggestionModel] = []

    /// Current style suggestion index (style mode)
    @Published var currentStyleIndex: Int = 0

    /// Unified index for cycling through all items (grammar errors + style suggestions)
    @Published var unifiedIndex: Int = 0

    /// Flag to prevent rapid-fire suggestion applications (race condition protection)
    @Published var isProcessing: Bool = false

    /// Counter to force SwiftUI view identity reset on rebuild
    /// Incrementing this causes SwiftUI to treat the view as completely new
    @Published var rebuildCounter: Int = 0

    /// All unified items (grammar errors + style suggestions) sorted by position
    var unifiedItems: [PopoverItem] {
        var items: [PopoverItem] = []
        items.append(contentsOf: allErrors.map { .grammar($0) })
        items.append(contentsOf: allStyleSuggestions.map { .style($0) })
        return items.sorted { $0.startPosition < $1.startPosition }
    }

    /// Total count of all items (grammar + style)
    var totalItemCount: Int {
        return allErrors.count + allStyleSuggestions.count
    }

    /// Callback for applying suggestion (grammar mode)
    /// The completion handler should be called when the replacement is done
    var onApplySuggestion: ((GrammarErrorModel, String, @escaping () -> Void) -> Void)?

    /// Callback for accepting style suggestion (style mode)
    var onAcceptStyleSuggestion: ((StyleSuggestionModel) -> Void)?

    /// Callback for rejecting style suggestion (style mode)
    var onRejectStyleSuggestion: ((StyleSuggestionModel, SuggestionRejectionCategory) -> Void)?

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

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    deinit {
        // Clean up event monitor to prevent memory leaks
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hideTimer?.invalidate()
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

    // MARK: - Show Methods

    /// Show popover with error at cursor position
    /// - Parameters:
    ///   - error: The error to display
    ///   - allErrors: All errors for context
    ///   - position: Screen position for the popover
    ///   - constrainToWindow: Optional window frame to constrain popover positioning (keeps popover inside app window)
    ///   - sourceText: Source text for context display
    func show(error: GrammarErrorModel, allErrors: [GrammarErrorModel], at position: CGPoint, constrainToWindow: CGRect? = nil, sourceText: String = "") {
        // DEBUG: Log activation policy BEFORE showing
        Logger.debug("SuggestionPopover.show() - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)

        self.mode = .grammarError
        self.allErrors = allErrors
        self.sourceText = sourceText

        // Find the matching error in allErrors to get the most up-to-date version
        // This ensures AI-enhanced errors (with suggestions) are used even if the overlay
        // passed an older version of the error
        let matchingError = allErrors.first(where: { $0.start == error.start && $0.end == error.end && $0.lintId == error.lintId })
        self.currentError = matchingError ?? error
        self.currentIndex = allErrors.firstIndex(where: { $0.start == error.start && $0.end == error.end }) ?? 0

        // Clear style data
        self.currentStyleSuggestion = nil
        self.allStyleSuggestions = []
        self.currentStyleIndex = 0

        showPanelAtPosition(position, constrainToWindow: constrainToWindow)
    }

    /// Show popover with style suggestion at position
    /// - Parameters:
    ///   - suggestion: The style suggestion to display
    ///   - allSuggestions: All style suggestions for context
    ///   - position: Screen position for the popover
    ///   - constrainToWindow: Optional window frame to constrain popover positioning
    func show(styleSuggestion suggestion: StyleSuggestionModel, allSuggestions: [StyleSuggestionModel], at position: CGPoint, constrainToWindow: CGRect? = nil) {
        Logger.debug("SuggestionPopover.show(styleSuggestion:) - showing style suggestion", category: Logger.ui)

        self.mode = .styleSuggestion
        self.currentStyleSuggestion = suggestion
        self.allStyleSuggestions = allSuggestions
        self.currentStyleIndex = allSuggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0

        // Clear grammar data
        self.currentError = nil
        self.allErrors = []
        self.currentIndex = 0

        showPanelAtPosition(position, constrainToWindow: constrainToWindow)
    }

    /// Show popover with style suggestion while keeping existing grammar errors for unified cycling
    /// - Parameters:
    ///   - suggestion: The style suggestion to display
    ///   - allSuggestions: All style suggestions for context
    ///   - existingErrors: Grammar errors to keep for unified cycling
    ///   - position: Screen position for the popover
    ///   - constrainToWindow: Optional window frame to constrain popover positioning
    func showStyleWithExistingErrors(suggestion: StyleSuggestionModel, allSuggestions: [StyleSuggestionModel], existingErrors: [GrammarErrorModel], at position: CGPoint, constrainToWindow: CGRect? = nil) {
        Logger.debug("SuggestionPopover.showStyleWithExistingErrors - showing style suggestion with \(existingErrors.count) grammar errors", category: Logger.ui)

        self.mode = .styleSuggestion
        self.currentStyleSuggestion = suggestion
        self.allStyleSuggestions = allSuggestions
        self.currentStyleIndex = allSuggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0

        // Keep existing grammar errors for unified cycling
        self.currentError = nil
        self.allErrors = existingErrors
        // currentIndex stays as it was

        // Update unified index
        updateUnifiedIndexForCurrentItem()

        showPanelAtPosition(position, constrainToWindow: constrainToWindow)
    }

    /// Common panel display logic
    private func showPanelAtPosition(_ position: CGPoint, constrainToWindow: CGRect?) {
        // Always recreate panel to ensure correct content view for current mode
        if panel != nil {
            panel?.orderOut(nil)
            panel = nil
        }
        createPanel()

        // Position near cursor (with optional window constraint)
        positionPanel(at: position, constrainToWindow: constrainToWindow)

        // Use order(.above) instead of orderFrontRegardless() to prevent focus stealing
        panel?.order(.above, relativeTo: 0)

        // DEBUG: Log activation policy AFTER showing
        Logger.debug("SuggestionPopover.showPanelAtPosition() - AFTER order(.above) - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)

        setupClickOutsideMonitor()

        // CRITICAL: Resize panel after SwiftUI has had time to layout the new content
        // This fixes border/corner issues when message text causes size changes
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.shortDelay) { [weak self] in
            self?.rebuildContentView()
        }
    }

    // MARK: - Hide Methods

    /// Schedule hiding of popover with a delay
    func scheduleHide() {
        // Cancel any existing timer
        hideTimer?.invalidate()

        // Schedule hide after 2 seconds delay (gives user time to move mouse into popover)
        // Increased from 1s to 2s for better UX - some apps have less stable mouse tracking
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performHide()
            }
        }
    }

    /// Cancel scheduled hide
    func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    /// Perform immediate hide
    private func performHide() {
        Logger.trace("SuggestionPopover.performHide() - BEFORE - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)

        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }

        panel?.orderOut(nil)

        // Clear grammar data
        currentError = nil
        allErrors = []
        currentIndex = 0

        // Clear style data
        currentStyleSuggestion = nil
        allStyleSuggestions = []
        currentStyleIndex = 0

        hideTimer = nil

        // NOTE: We do NOT restore focus because our panels are .nonactivatingPanel
        // They never steal focus in the first place, so there's nothing to restore.
        // When the user clicks elsewhere, the click naturally activates the clicked app.
        // Any attempt to call activate() would FIGHT with the app's natural activation,
        // causing delays and making apps temporarily unclickable (especially on macOS 14+
        // where activateIgnoringOtherApps is deprecated and ignored).

        Logger.trace("SuggestionPopover.performHide() - AFTER - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)
    }

    /// Hide popover immediately
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        performHide()
    }

    // MARK: - Panel Management

    /// Setup click outside monitor to close popover when user clicks elsewhere
    private func setupClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Use GLOBAL monitor to detect ALL clicks (including in other apps like Chrome)
        // When user clicks outside, hide the popover
        // The click will naturally activate the clicked app (we can't prevent event propagation)
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let panel = self.panel else { return }

            // Check if click is inside the popover panel - if so, don't hide
            // Global events report screen coordinates, panel.frame is also in screen coords
            let clickLocation = event.locationInWindow
            // For global events, locationInWindow is actually screen coordinates
            let panelFrame = panel.frame

            if panelFrame.contains(clickLocation) {
                Logger.trace("Popover: Click inside popover - ignoring", category: Logger.ui)
                return
            }

            Logger.debug("Popover: Global click detected outside popover - hiding", category: Logger.ui)

            // CRITICAL: Cancel any pending auto-hide timer
            self.hideTimer?.invalidate()
            self.hideTimer = nil

            self.hide()
        }
    }

    /// Create the panel
    private func createPanel() {
        // Create appropriate content view based on mode
        let contentView = UnifiedPopoverContentView(popover: self)

        let hostingView = NSHostingView(rootView: contentView)
        // Force initial layout
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()

        // Let SwiftUI determine the size based on content
        let fittingSize = hostingView.fittingSize
        // Auto-scale: min 320px, max 550px width to accommodate longer messages and future LLM suggestions
        let width = min(max(fittingSize.width, 320), 550)
        // Auto-scale height with reasonable max to prevent massive popovers
        let height = min(fittingSize.height, 400)

        Logger.debug("Popover: Initial creation size: \(width) x \(height) (fitting: \(fittingSize))", category: Logger.ui)

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
        panel?.level = .popUpMenu + 1  // Above error overlay (.popUpMenu) so underlines don't cover popover
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.isMovableByWindowBackground = true
        panel?.title = mode == .grammarError ? "Grammar Suggestion" : "Style Suggestion"
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

        // CRITICAL: Set up window-level corner rounding
        // For borderless windows, we need to clip the content view's layer to rounded corners
        // This prevents the 90-degree corners from showing at the window edges
        trackingView.wantsLayer = true
        trackingView.layer?.cornerRadius = 10
        trackingView.layer?.masksToBounds = true

        // Handle close button
        panel?.standardWindowButton(.closeButton)?.target = self
        panel?.standardWindowButton(.closeButton)?.action = #selector(handleClose)
    }

    /// Position panel near cursor
    /// - Parameters:
    ///   - cursorPosition: The screen position for the popover
    ///   - constrainToWindow: Optional window frame to constrain positioning (keeps popover inside app window)
    private func positionPanel(at cursorPosition: CGPoint, constrainToWindow: CGRect? = nil) {
        guard let panel = panel else { return }

        // Find the screen containing the cursor position (important for multi-monitor setups)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPosition) }) ?? NSScreen.main
        guard let screen = screen else { return }

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
        let padding: CGFloat = 20  // General padding
        let verticalSpacing: CGFloat = 40  // Space between underline and popover
        let roomAbove = constraintFrame.maxY - cursorPosition.y
        let roomBelow = cursorPosition.y - constraintFrame.minY
        let roomLeft = cursorPosition.x - constraintFrame.minX
        let roomRight = constraintFrame.maxX - cursorPosition.x

        Logger.debug("Popover: Room - Above: \(roomAbove), Below: \(roomBelow), Left: \(roomLeft), Right: \(roomRight)", category: Logger.ui)

        // Dynamically adjust panel width if it would exceed available space
        var adjustedPanelSize = panelSize
        let totalHorizontalRoom = constraintFrame.width - padding * 2
        if panelSize.width > totalHorizontalRoom {
            adjustedPanelSize.width = max(320, totalHorizontalRoom)  // Minimum 320px, or available space

            Logger.debug("Popover: Reducing width from \(panelSize.width) to \(adjustedPanelSize.width) (available: \(totalHorizontalRoom))", category: Logger.ui)

            // Resize panel and content views
            if let trackingView = panel.contentView as? PopoverTrackingView,
               let hostingView = trackingView.subviews.first {
                hostingView.frame = NSRect(x: 0, y: 0, width: adjustedPanelSize.width, height: adjustedPanelSize.height)
                trackingView.frame = NSRect(x: 0, y: 0, width: adjustedPanelSize.width, height: adjustedPanelSize.height)
                panel.setContentSize(NSSize(width: adjustedPanelSize.width, height: adjustedPanelSize.height))
            }
        }

        // Determine vertical positioning
        // For underline hover, prefer BELOW so we don't cover the text being corrected
        var shouldPositionAbove: Bool
        switch preferences.suggestionPosition {
        case "Above":
            shouldPositionAbove = true
        case "Below":
            shouldPositionAbove = false
        default: // "Auto"
            // Prefer BELOW the underline to avoid covering the error
            // Only go above if there's no room below
            shouldPositionAbove = roomBelow < adjustedPanelSize.height + verticalSpacing + padding
            if shouldPositionAbove && roomAbove < adjustedPanelSize.height + verticalSpacing + padding {
                // Neither direction has enough room - choose the one with more space
                shouldPositionAbove = roomAbove > roomBelow
            }
        }

        Logger.debug("Popover: shouldPositionAbove: \(shouldPositionAbove)", category: Logger.ui)

        // Calculate vertical position with proper spacing
        var origin = CGPoint.zero
        if shouldPositionAbove {
            origin.y = cursorPosition.y + verticalSpacing
        } else {
            origin.y = cursorPosition.y - adjustedPanelSize.height - verticalSpacing
        }

        // Horizontal positioning: prefer CENTERED over the underline
        // Center the popover horizontally on the cursor position
        origin.x = cursorPosition.x - adjustedPanelSize.width / 2

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

    // MARK: - Navigation

    /// Navigate to next error
    func nextError() {
        guard !allErrors.isEmpty else { return }
        currentIndex = (currentIndex + 1) % allErrors.count
        currentError = allErrors[currentIndex]

        // Rebuild content view from scratch for clean rendering
        rebuildContentView()
    }

    /// Navigate to previous error
    func previousError() {
        guard !allErrors.isEmpty else { return }
        currentIndex = (currentIndex - 1 + allErrors.count) % allErrors.count
        currentError = allErrors[currentIndex]

        // Rebuild content view from scratch for clean rendering
        rebuildContentView()
    }

    /// Update errors list and refresh current error if it was updated (e.g., AI suggestion arrived)
    /// This is called when AI-enhanced errors are ready to replace the originals
    func updateErrors(_ updatedErrors: [GrammarErrorModel]) {
        guard isVisible, let current = currentError else { return }

        // Update the all errors list
        allErrors = updatedErrors

        // Check if the current error has been updated (same position, but new suggestions)
        if let updatedCurrent = updatedErrors.first(where: { $0.start == current.start && $0.end == current.end && $0.lintId == current.lintId }) {
            // Check if suggestions changed (AI suggestion arrived)
            if updatedCurrent.suggestions.count != current.suggestions.count {
                Logger.info("SuggestionPopover: Current error updated with new suggestions, rebuilding view", category: Logger.ui)
                currentError = updatedCurrent
                // Rebuild to show the new content (Before/After view instead of loading)
                rebuildContentView()
            }
        }
    }

    // MARK: - View Rebuild

    /// Rebuild the content view from scratch for clean rendering
    /// This ensures no artifacts when switching between errors of different sizes
    private func rebuildContentView() {
        guard let panel = panel,
              let trackingView = panel.contentView as? PopoverTrackingView else { return }

        // Increment counter to force SwiftUI to treat this as a completely new view
        // This prevents cached layout from LiquidGlass background
        rebuildCounter += 1

        // Remove old hosting view completely
        trackingView.subviews.forEach { $0.removeFromSuperview() }

        // Create fresh content view
        let contentView = UnifiedPopoverContentView(popover: self)
        let hostingView = NSHostingView(rootView: contentView)

        // KEY INSIGHT: Don't set frames manually. Let SwiftUI size itself naturally.
        // 1. Create hosting view with a large temporary frame so SwiftUI isn't constrained
        // 2. Add to hierarchy
        // 3. Let SwiftUI calculate its intrinsic size
        // 4. THEN resize everything to match

        // Step 1: Give hosting view plenty of room for initial layout
        hostingView.frame = NSRect(x: 0, y: 0, width: 550, height: 500)
        trackingView.frame = NSRect(x: 0, y: 0, width: 550, height: 500)

        // Step 2: Add to hierarchy
        trackingView.addSubview(hostingView)

        // Step 3: Force SwiftUI layout pass with unconstrained space
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        // Step 4: Get the ACTUAL size SwiftUI wants
        let fittingSize = hostingView.fittingSize
        let width = min(max(fittingSize.width, 320), 550)
        let height = min(fittingSize.height, 400)

        Logger.debug("Popover rebuildContentView: fittingSize=\(fittingSize), final=\(width)x\(height)", category: Logger.ui)

        // Step 5: Calculate panel position to keep TOP edge fixed
        let currentFrame = panel.frame
        let currentTop = currentFrame.origin.y + currentFrame.size.height
        let newOriginY = currentTop - height

        // Step 6: Resize panel to final size
        panel.setFrame(NSRect(x: currentFrame.origin.x, y: newOriginY, width: width, height: height), display: false, animate: false)

        // Step 7: NOW constrain views to final size (this triggers SwiftUI re-layout at correct size)
        trackingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.autoresizingMask = [.width, .height]

        // Step 8: Final layout pass at correct size
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        // Step 9: Force redraw
        panel.display()

        Logger.debug("Popover: Rebuilt content - \(width) x \(height)", category: Logger.ui)
    }

    // MARK: - Grammar Error Actions

    /// Apply suggestion
    func applySuggestion(_ suggestion: String) {
        guard let error = currentError else { return }

        // Prevent rapid-fire clicks - wait for previous replacement to complete
        guard !isProcessing else {
            Logger.debug("Popover: Ignoring click - still processing previous suggestion", category: Logger.ui)
            return
        }

        isProcessing = true

        // Calculate position shift for remaining errors (needed for completion handler)
        let originalLength = error.end - error.start
        let newLength = suggestion.count
        let lengthDelta = newLength - originalLength

        // Call the replacement with completion handler
        onApplySuggestion?(error, suggestion) { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                // Update sourceText to reflect the applied correction
                if !self.sourceText.isEmpty,
                   error.start < self.sourceText.count,
                   error.end <= self.sourceText.count {
                    let startIndex = self.sourceText.index(self.sourceText.startIndex, offsetBy: error.start)
                    let endIndex = self.sourceText.index(self.sourceText.startIndex, offsetBy: error.end)
                    self.sourceText.replaceSubrange(startIndex..<endIndex, with: suggestion)
                }

                // Move to next error or hide
                if self.allErrors.count > 1 {
                    // Remove the current error
                    self.allErrors.removeAll { $0.start == error.start && $0.end == error.end }

                    // Adjust positions of subsequent errors
                    self.allErrors = self.allErrors.map { err in
                        if err.start >= error.end {
                            return GrammarErrorModel(
                                start: err.start + lengthDelta,
                                end: err.end + lengthDelta,
                                message: err.message,
                                severity: err.severity,
                                category: err.category,
                                lintId: err.lintId,
                                suggestions: err.suggestions
                            )
                        }
                        return err
                    }

                    if self.currentIndex >= self.allErrors.count {
                        self.currentIndex = 0
                    }
                    self.currentError = self.allErrors.isEmpty ? nil : self.allErrors[self.currentIndex]

                    if self.currentError == nil {
                        self.hide()
                    } else {
                        self.rebuildContentView()
                    }
                } else {
                    self.hide()
                }

                self.isProcessing = false
            }
        }
    }

    /// Dismiss error for session
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
                DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.shortDelay) { [weak self] in
                    self?.rebuildContentView()
                }
            }
        } else {
            hide()
        }
    }

    /// Ignore rule permanently
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
                DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.shortDelay) { [weak self] in
                    self?.rebuildContentView()
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
                DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.shortDelay) { [weak self] in
                    self?.rebuildContentView()
                }
            }
        } else {
            hide()
        }
    }

    // MARK: - Style Suggestion Actions

    /// Accept current style suggestion
    func acceptStyleSuggestion() {
        guard let suggestion = currentStyleSuggestion else { return }

        onAcceptStyleSuggestion?(suggestion)
        PreferenceLearner.shared.recordAcceptance(suggestion)
        UserStatistics.shared.recordStyleAcceptance()

        // Move to next suggestion or hide
        moveToNextStyleSuggestion()
    }

    /// Reject current style suggestion with category
    func rejectStyleSuggestion(category: SuggestionRejectionCategory) {
        guard let suggestion = currentStyleSuggestion else { return }

        onRejectStyleSuggestion?(suggestion, category)
        PreferenceLearner.shared.recordRejection(suggestion, category: category)
        UserStatistics.shared.recordStyleRejection(category: category.rawValue)

        // Move to next suggestion or hide
        moveToNextStyleSuggestion()
    }

    /// Navigate to next style suggestion
    func nextStyleSuggestion() {
        guard !allStyleSuggestions.isEmpty,
              currentStyleIndex < allStyleSuggestions.count - 1 else { return }

        currentStyleIndex += 1
        currentStyleSuggestion = allStyleSuggestions[currentStyleIndex]

        // Rebuild panel for new content
        rebuildContentView()
    }

    /// Navigate to previous style suggestion
    func previousStyleSuggestion() {
        guard !allStyleSuggestions.isEmpty,
              currentStyleIndex > 0 else { return }

        currentStyleIndex -= 1
        currentStyleSuggestion = allStyleSuggestions[currentStyleIndex]

        // Rebuild panel for new content
        rebuildContentView()
    }

    /// Move to next style suggestion after accept/reject
    private func moveToNextStyleSuggestion() {
        guard let current = currentStyleSuggestion else {
            hide()
            return
        }

        // Remove current from list
        allStyleSuggestions.removeAll { $0.id == current.id }

        if allStyleSuggestions.isEmpty {
            hide()
        } else {
            // Adjust index if needed
            if currentStyleIndex >= allStyleSuggestions.count {
                currentStyleIndex = allStyleSuggestions.count - 1
            }
            currentStyleSuggestion = allStyleSuggestions[currentStyleIndex]

            // Rebuild panel for new content
            rebuildContentView()
        }
    }

    /// Show popover with both grammar errors and style suggestions for unified cycling
    /// - Parameters:
    ///   - errors: Grammar errors to display
    ///   - styleSuggestions: Style suggestions to display
    ///   - position: Screen position for the popover
    ///   - constrainToWindow: Optional window frame to constrain popover positioning
    ///   - sourceText: Source text for context display
    func showUnified(errors: [GrammarErrorModel], styleSuggestions: [StyleSuggestionModel], at position: CGPoint, constrainToWindow: CGRect? = nil, sourceText: String = "") {
        Logger.debug("SuggestionPopover.showUnified - errors=\(errors.count), styleSuggestions=\(styleSuggestions.count)", category: Logger.ui)

        // Store both collections for unified cycling
        self.allErrors = errors
        self.allStyleSuggestions = styleSuggestions
        self.sourceText = sourceText

        // Start at unified index 0 (first item sorted by position)
        self.unifiedIndex = 0

        // Determine which type of item comes first
        let items = unifiedItems
        guard !items.isEmpty else {
            Logger.debug("SuggestionPopover.showUnified - no items to show", category: Logger.ui)
            return
        }

        // Set mode and current item based on first unified item
        switch items[0] {
        case .grammar(let error):
            self.mode = .grammarError
            self.currentError = error
            self.currentStyleSuggestion = nil
            self.currentIndex = 0

        case .style(let suggestion):
            self.mode = .styleSuggestion
            self.currentStyleSuggestion = suggestion
            self.currentError = nil
            self.currentStyleIndex = 0
        }

        showPanelAtPosition(position, constrainToWindow: constrainToWindow)
    }

    // MARK: - Unified Navigation

    /// Navigate to the next item in the unified list (grammar errors + style suggestions)
    /// Wraps around to the first item when at the end
    func nextUnifiedItem() {
        let items = unifiedItems
        guard !items.isEmpty else { return }

        if unifiedIndex >= items.count - 1 {
            // Wrap around to beginning
            unifiedIndex = 0
        } else {
            unifiedIndex += 1
        }
        showUnifiedItem(at: unifiedIndex)
    }

    /// Navigate to the previous item in the unified list
    /// Wraps around to the last item when at the beginning
    func previousUnifiedItem() {
        let items = unifiedItems
        guard !items.isEmpty else { return }

        if unifiedIndex <= 0 {
            // Wrap around to end
            unifiedIndex = items.count - 1
        } else {
            unifiedIndex -= 1
        }
        showUnifiedItem(at: unifiedIndex)
    }

    /// Show the item at the given unified index
    private func showUnifiedItem(at index: Int) {
        let items = unifiedItems
        guard index >= 0 && index < items.count else { return }

        switch items[index] {
        case .grammar(let error):
            mode = .grammarError
            currentError = error
            currentStyleSuggestion = nil
            // Update currentIndex to match this error
            if let errorIndex = allErrors.firstIndex(where: { $0.start == error.start && $0.end == error.end }) {
                currentIndex = errorIndex
            }

        case .style(let suggestion):
            mode = .styleSuggestion
            currentStyleSuggestion = suggestion
            currentError = nil
            // Update currentStyleIndex to match this suggestion
            if let styleIndex = allStyleSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
                currentStyleIndex = styleIndex
            }
        }

        rebuildContentView()
    }

    /// Calculate the unified index for the currently displayed item
    func updateUnifiedIndexForCurrentItem() {
        let items = unifiedItems

        switch mode {
        case .grammarError:
            guard let error = currentError else { return }
            if let idx = items.firstIndex(where: {
                if case .grammar(let e) = $0 { return e.start == error.start && e.end == error.end }
                return false
            }) {
                unifiedIndex = idx
            }

        case .styleSuggestion:
            guard let suggestion = currentStyleSuggestion else { return }
            if let idx = items.firstIndex(where: {
                if case .style(let s) = $0 { return s.id == suggestion.id }
                return false
            }) {
                unifiedIndex = idx
            }
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
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return getCursorPosition(in: element)
        }

        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard boundsError == .success,
              let axValue = boundsValue,
              let rect = safeAXValueGetRect(axValue) else {
            return getCursorPosition(in: element)
        }

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

    /// Get cursor position from AX element
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
              let rect = safeAXValueGetRect(axValue) else {
            return fallbackCursorPosition()
        }

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

        // Make the tracking view transparent with rounded corners
        self.wantsLayer = true
        self.layer?.backgroundColor = .clear
        self.layer?.cornerRadius = 10
        self.layer?.masksToBounds = true

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
        Logger.trace("Popover: Tracking area set up with bounds: \(bounds)", category: Logger.ui)
    }

    override func mouseEntered(with event: NSEvent) {
        Logger.trace("Popover: Mouse ENTERED tracking view", category: Logger.ui)
        popover?.cancelHide()
        popover?.onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        Logger.trace("Popover: Mouse EXITED tracking view", category: Logger.ui)
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
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
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
            return
        }

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

        // Position tooltip below button, centered horizontally
        let tooltipX = buttonFrame.midX - (tooltipWidth / 2)
        let tooltipY = buttonFrame.minY - tooltipHeight - 8 // 8pt spacing below button

        let tooltipFrame = NSRect(x: tooltipX, y: tooltipY, width: tooltipWidth, height: tooltipHeight)

        panel.setFrame(tooltipFrame, display: true)
        panel.order(.above, relativeTo: 0)
    }

    /// Hide tooltip with optional delay
    func hide(after delay: TimeInterval = 0) {
        hideTimer?.invalidate()

        if delay > 0 {
            hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.panel?.orderOut(nil)
            }
        } else {
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
                if isHovering {
                    showTooltip(at: frame)
                }
            }
            .whenHovered { hovering in
                isHovering = hovering
                if !hovering {
                    TooltipPanel.shared.hide()
                }
            }
    }

    private func showTooltip(at frame: CGRect) {
        guard isHovering else { return }

        // Convert to screen coordinates (frame is already in global/screen coordinates)
        let screenFrame = frame
        let screenPosition = CGPoint(x: screenFrame.midX, y: screenFrame.minY)

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

// MARK: - Style Suggestion Content View

/// SwiftUI content view for style suggestions (used by unified popover)
struct StylePopoverContentView: View {
    @ObservedObject var popover: SuggestionPopover
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.colorScheme) var systemColorScheme

    /// Effective color scheme based on user preference (overlay theme for popovers)
    private var effectiveColorScheme: ColorScheme {
        switch preferences.overlayTheme {
        case "Light":
            return .light
        case "Dark":
            return .dark
        default:
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let suggestion = popover.currentStyleSuggestion {
                // Header with sparkle icon
                HStack(alignment: .top, spacing: 16) {
                    // Purple sparkle indicator for style
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 6, height: 6)
                        .padding(.top, 8)
                        .accessibilityHidden(true) // Decorative

                    VStack(alignment: .leading, spacing: 12) {
                        // Header label only (no navigation here)
                        Text("STYLE SUGGESTION")
                            .font(.system(size: baseTextSize * 0.85, weight: .semibold, design: .rounded))
                            .foregroundColor(colors.textSecondary)
                            .tracking(0.6)
                            .accessibilityAddTraits(.isHeader)

                        // Before/After diff view (no dark background)
                        VStack(alignment: .leading, spacing: 8) {
                            // Original text
                            HStack(alignment: .top, spacing: 8) {
                                Text("Before:")
                                    .font(.system(size: baseTextSize * 0.85, weight: .medium))
                                    .foregroundColor(colors.textSecondary)
                                    .frame(width: 50, alignment: .leading)
                                Text(suggestion.originalText)
                                    .font(.system(size: baseTextSize))
                                    .foregroundColor(.red.opacity(0.85))
                                    .strikethrough(true, color: .red)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Original text: \(suggestion.originalText)")

                            // Suggested text
                            HStack(alignment: .top, spacing: 8) {
                                Text("After:")
                                    .font(.system(size: baseTextSize * 0.85, weight: .medium))
                                    .foregroundColor(colors.textSecondary)
                                    .frame(width: 50, alignment: .leading)
                                Text(suggestion.suggestedText)
                                    .font(.system(size: baseTextSize))
                                    .foregroundColor(.green)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Suggested text: \(suggestion.suggestedText)")
                        }

                        // Explanation
                        Text(suggestion.explanation)
                            .font(.system(size: baseTextSize))
                            .foregroundColor(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Explanation: \(suggestion.explanation)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Close button - no VStack wrapper to prevent pushing content up
                    Button(action: { popover.hide() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(colors.backgroundRaised)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Close (⌥Esc)")
                    .accessibilityLabel("Close style suggestion")
                    .accessibilityHint("Double tap to close this suggestion")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 18)

                // Bottom action bar
                Divider()
                    .background(colors.border)

                HStack(spacing: 12) {
                    // Accept button - Purple accent
                    Button(action: { popover.acceptStyleSuggestion() }) {
                        Label("Accept", systemImage: "checkmark.circle.fill")
                            .font(.system(size: baseTextSize, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.purple)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Accept this suggestion")
                    .accessibilityLabel("Accept suggestion")
                    .accessibilityHint("Double tap to accept and apply this style suggestion")

                    // Reject menu
                    Menu {
                        ForEach(SuggestionRejectionCategory.allCases, id: \.self) { category in
                            Button(category.displayName) {
                                popover.rejectStyleSuggestion(category: category)
                            }
                        }
                    } label: {
                        Label("Reject", systemImage: "xmark.circle")
                            .font(.system(size: baseTextSize, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Reject suggestion")
                    .accessibilityHint("Double tap to choose a reason for rejecting this suggestion")

                    Spacer()

                    // Navigation (show when multiple items total - grammar errors + style suggestions)
                    if popover.totalItemCount > 1 {
                        Text("\(popover.unifiedIndex + 1) of \(popover.totalItemCount)")
                            .font(.system(size: baseTextSize * 0.85, weight: .semibold))
                            .foregroundColor(
                                Color(hue: 280/360, saturation: 0.65, brightness: effectiveColorScheme == .dark ? 0.80 : 0.50)
                            )
                            .accessibilityLabel("Suggestion \(popover.unifiedIndex + 1) of \(popover.totalItemCount)")

                        HStack(spacing: 6) {
                            Button(action: { popover.previousUnifiedItem() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(hue: 280/360, saturation: 0.70, brightness: effectiveColorScheme == .dark ? 0.60 : 0.55),
                                                Color(hue: 280/360, saturation: 0.75, brightness: effectiveColorScheme == .dark ? 0.50 : 0.48)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(6)
                                    .shadow(color: Color.purple.opacity(0.2), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .help("Previous")
                            .accessibilityLabel("Previous suggestion")
                            .accessibilityHint("Double tap to go to the previous suggestion")

                            Button(action: { popover.nextUnifiedItem() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(hue: 280/360, saturation: 0.70, brightness: effectiveColorScheme == .dark ? 0.60 : 0.55),
                                                Color(hue: 280/360, saturation: 0.75, brightness: effectiveColorScheme == .dark ? 0.50 : 0.48)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(6)
                                    .shadow(color: Color.purple.opacity(0.2), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .help("Next")
                            .accessibilityLabel("Next suggestion")
                            .accessibilityHint("Double tap to go to the next suggestion")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            } else {
                Text("No style suggestions to display")
                    .foregroundColor(colors.textSecondary)
                    .padding()
                    .accessibilityLabel("No style suggestions to display")
            }
        }
        // Apply Liquid Glass styling with purple tint (macOS 26-inspired)
        .liquidGlass(
            style: .regular,
            tint: .purple,
            cornerRadius: 14,
            opacity: preferences.suggestionOpacity
        )
        // Fixed width, vertical sizing to content
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .colorScheme(effectiveColorScheme)
    }

}

// MARK: - FlowLayout

/// A layout that arranges views horizontally and wraps to new lines when needed
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// Minimum width before wrapping - use a generous default to prevent premature wrapping
    /// 380px popover - 24px padding - 22px circle - 20px close button - 16px HStack spacing = ~298px available
    /// But we want more buffer, so use 350px to ensure 3 buttons fit on one line when possible
    var minWidthBeforeWrap: CGFloat = 350

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, position) in arrangement.positions.enumerated() {
            let subview = subviews[index]
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        // Use the proposed width if available, otherwise use a generous minimum
        // This prevents premature wrapping when parent doesn't pass width proposal
        let maxWidth = proposal.width ?? minWidthBeforeWrap
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to next line
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}
