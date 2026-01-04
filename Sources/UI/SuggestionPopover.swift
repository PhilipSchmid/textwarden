//
//  SuggestionPopover.swift
//  TextWarden
//
//  Displays grammar error suggestions in a popover near the cursor
//

import AppKit
import ApplicationServices
import Combine
import KeyboardShortcuts
import SwiftUI

/// Custom NSPanel subclass that prevents becoming key window
/// This is CRITICAL to prevent TextWarden from stealing focus from other apps
class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
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
        case let .grammar(error): error.start
        case let .style(suggestion): suggestion.originalStart
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

    /// Time when popover was hidden by outside click (used to debounce underline clicks)
    var lastClickOutsideHideTime: Date?

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

    /// Flag to prevent sync during navigation (prevents race condition with rebuildContentView)
    private var isNavigating: Bool = false

    /// Counter to force SwiftUI view identity reset on rebuild
    /// Incrementing this causes SwiftUI to treat the view as completely new
    @Published var rebuildCounter: Int = 0

    /// Flag to indicate popover was opened from indicator click (not hover)
    /// When true, the popover persists until explicitly dismissed and shows navigation controls
    @Published private(set) var openedFromIndicator: Bool = false

    /// Status message to display briefly (e.g., when an action fails)
    @Published var statusMessage: String?

    /// Timer for auto-hiding status message
    private var statusMessageTimer: Timer?

    /// All unified items (grammar errors + style suggestions) sorted by position
    var unifiedItems: [PopoverItem] {
        var items: [PopoverItem] = []
        items.append(contentsOf: allErrors.map { .grammar($0) })
        items.append(contentsOf: allStyleSuggestions.map { .style($0) })
        return items.sorted { $0.startPosition < $1.startPosition }
    }

    /// Total count of all items (grammar + style)
    var totalItemCount: Int {
        allErrors.count + allStyleSuggestions.count
    }

    /// Callback for applying suggestion (grammar mode)
    var onApplySuggestion: ((GrammarErrorModel, String) async -> Void)?

    /// Callback for accepting style suggestion (style mode)
    var onAcceptStyleSuggestion: ((StyleSuggestionModel) -> Void)?

    /// Callback for rejecting style suggestion (style mode)
    var onRejectStyleSuggestion: ((StyleSuggestionModel, SuggestionRejectionCategory) -> Void)?

    /// Callback for regenerating style suggestion (to get alternative)
    var onRegenerateStyleSuggestion: ((StyleSuggestionModel) async -> StyleSuggestionModel?)?

    /// Flag indicating style suggestion is being regenerated
    @Published var isRegenerating: Bool = false

    /// Flag indicating on-demand simplification is being generated
    @Published var isGeneratingSimplification: Bool = false

    /// Track regeneration count per suggestion (keyed by suggestion ID) - for logging only
    var regenerationCounts: [String: Int] = [:]

    /// Callback for dismissing error
    var onDismissError: ((GrammarErrorModel) -> Void)?

    /// Callback for ignoring rule
    var onIgnoreRule: ((String) -> Void)?

    /// Callback for adding word to dictionary
    var onAddToDictionary: ((GrammarErrorModel) -> Void)?

    /// Callback when mouse enters popover (for cancelling delayed switches)
    var onMouseEntered: (() -> Void)?

    /// Callback when popover is hidden (for clearing locked highlight)
    var onPopoverHidden: (() -> Void)?

    /// Callback when current error changes (for updating locked highlight)
    var onCurrentErrorChanged: ((GrammarErrorModel?) -> Void)?

    /// Check if popover is currently visible
    var isVisible: Bool {
        panel?.isVisible == true && (currentError != nil || currentStyleSuggestion != nil)
    }

    /// Check if a screen point is within the popover's frame
    func containsPoint(_ screenPoint: CGPoint) -> Bool {
        guard isVisible, let panel else { return false }
        return panel.frame.contains(screenPoint)
    }

    // MARK: - Initialization

    override private init() {
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

        // Mark as hover-triggered - popover auto-hides when mouse leaves
        openedFromIndicator = false

        mode = .grammarError
        self.allErrors = allErrors
        self.sourceText = sourceText

        // Find the matching error in allErrors to get the most up-to-date version
        // This ensures AI-enhanced errors (with suggestions) are used even if the overlay
        // passed an older version of the error
        let matchingError = allErrors.first(where: { $0.start == error.start && $0.end == error.end && $0.lintId == error.lintId })
        currentError = matchingError ?? error
        currentIndex = allErrors.firstIndex(where: { $0.start == error.start && $0.end == error.end }) ?? 0

        // Clear style data
        currentStyleSuggestion = nil
        allStyleSuggestions = []
        currentStyleIndex = 0

        // Notify about current error change (for locked highlight)
        onCurrentErrorChanged?(currentError)

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

        // Mark as hover-triggered - popover auto-hides when mouse leaves
        openedFromIndicator = false

        mode = .styleSuggestion
        currentStyleSuggestion = suggestion
        allStyleSuggestions = allSuggestions
        currentStyleIndex = allSuggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0

        // Clear grammar data
        currentError = nil
        allErrors = []
        currentIndex = 0

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

        mode = .styleSuggestion
        currentStyleSuggestion = suggestion
        allStyleSuggestions = allSuggestions
        currentStyleIndex = allSuggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0

        // Keep existing grammar errors for unified cycling
        currentError = nil
        allErrors = existingErrors
        // currentIndex stays as it was

        // Update unified index
        updateUnifiedIndexForCurrentItem()

        showPanelAtPosition(position, constrainToWindow: constrainToWindow)
    }

    /// Common panel display logic
    private func showPanelAtPosition(_ position: CGPoint, constrainToWindow: CGRect?) {
        // Close other popovers first
        TextGenerationPopover.shared.hide()
        ReadabilityPopover.shared.hide()

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

        // Enable popover keyboard shortcuts (Tab to accept, etc.)
        // These are disabled globally and only active when popover is visible
        KeyboardShortcuts.Name.enablePopoverShortcuts()

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
        // Don't auto-hide popovers opened from the indicator
        // They should stay visible until explicitly dismissed (click outside, X button, etc.)
        guard !openedFromIndicator else {
            Logger.debug("Popover: Skipping auto-hide - opened from indicator", category: Logger.ui)
            return
        }

        // Cancel any existing timer
        hideTimer?.invalidate()

        // Schedule hide after delay (gives user time to move mouse into popover)
        hideTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.popoverAutoHide, repeats: false) { [weak self] _ in
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

        // Disable popover keyboard shortcuts so they don't intercept keypresses globally
        // (Tab should work normally in other apps when popover is hidden)
        KeyboardShortcuts.Name.disablePopoverShortcuts()

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

        // Reset indicator flag
        openedFromIndicator = false

        hideTimer = nil

        // NOTE: We do NOT restore focus because our panels are .nonactivatingPanel
        // They never steal focus in the first place, so there's nothing to restore.
        // When the user clicks elsewhere, the click naturally activates the clicked app.
        // Any attempt to call activate() would FIGHT with the app's natural activation,
        // causing delays and making apps temporarily unclickable (especially on macOS 14+
        // where activateIgnoringOtherApps is deprecated and ignored).

        // Notify that popover was hidden (for clearing locked highlight)
        onPopoverHidden?()

        Logger.trace("SuggestionPopover.performHide() - AFTER - ActivationPolicy: \(NSApp.activationPolicy().rawValue), isActive: \(NSApp.isActive)", category: Logger.ui)
    }

    /// Hide popover immediately
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        isGeneratingSimplification = false // Reset loading state
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
            guard let self, let panel else { return }

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
            hideTimer?.invalidate()
            hideTimer = nil

            // Record the time so ErrorOverlay click handler can debounce
            lastClickOutsideHideTime = Date()

            hide()
        }
    }

    /// Create the panel
    private func createPanel() {
        // Create appropriate content view based on mode
        let contentView = UnifiedPopoverContentView(popover: self)

        // Use FirstMouseHostingView to ensure buttons work immediately in non-activating panel
        let hostingView = FirstMouseHostingView(rootView: contentView)
        // Force initial layout
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()

        // Let SwiftUI determine the size based on content
        let fittingSize = hostingView.fittingSize
        // Auto-scale: min 380px, max 550px width to accommodate buttons and style suggestions
        let width = min(max(fittingSize.width, 380), 550)
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
        panel?.level = .popUpMenu + 1 // Above error overlay (.popUpMenu) so underlines don't cover popover
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.isMovableByWindowBackground = true
        panel?.title = mode == .grammarError ? "Grammar Suggestion" : "Style Suggestion"
        panel?.titlebarAppearsTransparent = false
        // Make panel background transparent so SwiftUI content's opacity works
        panel?.backgroundColor = .clear
        panel?.isOpaque = false
        panel?.hasShadow = true // System shadow (SwiftUI shadow gets clipped by masksToBounds)
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
    ///   - cursorPosition: The screen position for the popover (anchor point when from indicator)
    ///   - constrainToWindow: Optional window frame to constrain positioning (keeps popover inside app window)
    private func positionPanel(at cursorPosition: CGPoint, constrainToWindow: CGRect? = nil) {
        guard let panel else { return }

        // Find the screen containing the cursor position (important for multi-monitor setups)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPosition) }) ?? NSScreen.main
        guard let screen else { return }

        Logger.debug("Popover: Input cursor position (screen): \(cursorPosition)", category: Logger.ui)

        let panelSize = panel.frame.size
        let padding: CGFloat = 20

        // Use constrainToWindow if provided, otherwise use screen frame
        let constraintFrame = constrainToWindow ?? screen.visibleFrame

        // When opened from indicator, use anchor-based positioning for consistency
        if openedFromIndicator {
            positionPanelFromIndicator(at: cursorPosition, panelSize: panelSize, constraintFrame: constraintFrame, padding: padding)
            return
        }

        // For underline hovers, use the original positioning logic
        let preferences = UserPreferences.shared
        let verticalSpacing: CGFloat = 25

        Logger.debug("Popover: Panel size: \(panelSize), Constraint frame: \(constraintFrame)", category: Logger.ui)

        // Calculate available space in all directions
        let roomAbove = constraintFrame.maxY - cursorPosition.y
        let roomBelow = cursorPosition.y - constraintFrame.minY

        // Dynamically adjust panel width if it would exceed available space
        var adjustedPanelSize = panelSize
        let totalHorizontalRoom = constraintFrame.width - padding * 2
        if panelSize.width > totalHorizontalRoom {
            adjustedPanelSize.width = max(320, totalHorizontalRoom)

            if let trackingView = panel.contentView as? PopoverTrackingView,
               let hostingView = trackingView.subviews.first
            {
                hostingView.frame = NSRect(x: 0, y: 0, width: adjustedPanelSize.width, height: adjustedPanelSize.height)
                trackingView.frame = NSRect(x: 0, y: 0, width: adjustedPanelSize.width, height: adjustedPanelSize.height)
                panel.setContentSize(NSSize(width: adjustedPanelSize.width, height: adjustedPanelSize.height))
            }
        }

        // Determine vertical positioning - prefer BELOW for underline hovers
        var shouldPositionAbove: Bool
        switch preferences.suggestionPosition {
        case "Above":
            shouldPositionAbove = true
        case "Below":
            shouldPositionAbove = false
        default:
            shouldPositionAbove = roomBelow < adjustedPanelSize.height + verticalSpacing + padding
            if shouldPositionAbove, roomAbove < adjustedPanelSize.height + verticalSpacing + padding {
                shouldPositionAbove = roomAbove > roomBelow
            }
        }

        var origin = CGPoint.zero
        if shouldPositionAbove {
            origin.y = cursorPosition.y + verticalSpacing
        } else {
            origin.y = cursorPosition.y - adjustedPanelSize.height - verticalSpacing
        }
        origin.x = cursorPosition.x - adjustedPanelSize.width / 2

        // Clamp to bounds
        origin.x = max(constraintFrame.minX + padding, min(origin.x, constraintFrame.maxX - adjustedPanelSize.width - padding))
        origin.y = max(constraintFrame.minY + padding, min(origin.y, constraintFrame.maxY - adjustedPanelSize.height - padding))

        Logger.debug("Popover: Final position: \(origin)", category: Logger.ui)
        panel.setFrameOrigin(origin)
    }

    /// Position panel using anchor-based positioning when opened from indicator
    /// This ensures consistent positioning with other indicator popovers (TextGenerationPopover)
    /// Includes automatic direction flipping when panel doesn't fit in the requested direction
    private func positionPanelFromIndicator(at anchorPoint: CGPoint, panelSize: NSSize, constraintFrame: CGRect, padding: CGFloat) {
        guard let panel else { return }

        // Calculate origin for a given direction
        func originFor(direction: PopoverOpenDirection) -> CGPoint {
            switch direction {
            case .left:
                CGPoint(x: anchorPoint.x - panelSize.width, y: anchorPoint.y - panelSize.height / 2)
            case .right:
                CGPoint(x: anchorPoint.x, y: anchorPoint.y - panelSize.height / 2)
            case .top:
                CGPoint(x: anchorPoint.x - panelSize.width / 2, y: anchorPoint.y)
            case .bottom:
                CGPoint(x: anchorPoint.x - panelSize.width / 2, y: anchorPoint.y - panelSize.height)
            }
        }

        // Check if origin fits within screen bounds
        func fitsScreen(origin: CGPoint) -> Bool {
            let minX = constraintFrame.minX + padding
            let maxX = constraintFrame.maxX - panelSize.width - padding
            let minY = constraintFrame.minY + padding
            let maxY = constraintFrame.maxY - panelSize.height - padding
            return origin.x >= minX && origin.x <= maxX && origin.y >= minY && origin.y <= maxY
        }

        // Get opposite direction for fallback
        func oppositeDirection(_ dir: PopoverOpenDirection) -> PopoverOpenDirection {
            switch dir {
            case .left: .right
            case .right: .left
            case .top: .bottom
            case .bottom: .top
            }
        }

        // Try requested direction first
        var origin = originFor(direction: indicatorOpenDirection)
        var usedDirection = indicatorOpenDirection

        // If doesn't fit, try opposite direction
        if !fitsScreen(origin: origin) {
            let oppositeDir = oppositeDirection(indicatorOpenDirection)
            let oppositeOrigin = originFor(direction: oppositeDir)
            if fitsScreen(origin: oppositeOrigin) {
                origin = oppositeOrigin
                usedDirection = oppositeDir
            }
        }

        // Final clamp to ensure it stays on screen
        origin.x = max(constraintFrame.minX + padding, min(origin.x, constraintFrame.maxX - panelSize.width - padding))
        origin.y = max(constraintFrame.minY + padding, min(origin.y, constraintFrame.maxY - panelSize.height - padding))

        Logger.debug("Popover: Indicator anchor positioning - requested: \(indicatorOpenDirection), used: \(usedDirection), final: \(origin)", category: Logger.ui)
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
        // Safe access with bounds check
        currentError = allErrors.indices.contains(currentIndex) ? allErrors[currentIndex] : nil

        // Notify about current error change (for locked highlight)
        onCurrentErrorChanged?(currentError)

        // Rebuild content view from scratch for clean rendering
        rebuildContentView()
    }

    /// Navigate to previous error
    func previousError() {
        guard !allErrors.isEmpty else { return }
        currentIndex = (currentIndex - 1 + allErrors.count) % allErrors.count
        // Safe access with bounds check
        currentError = allErrors.indices.contains(currentIndex) ? allErrors[currentIndex] : nil

        // Notify about current error change (for locked highlight)
        onCurrentErrorChanged?(currentError)

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

    /// Sync popover's errors with coordinator's currentErrors after replacement.
    /// The popover and coordinator adjust positions independently during replacement,
    /// which can cause them to get out of sync. This re-syncs by index.
    func syncErrorsAfterReplacement(_ coordinatorErrors: [GrammarErrorModel]) {
        guard isVisible else { return }

        allErrors = coordinatorErrors

        // Clamp index to valid range
        if currentIndex >= allErrors.count {
            currentIndex = max(0, allErrors.count - 1)
        }

        // Update current error to the one at the (possibly adjusted) index
        if allErrors.indices.contains(currentIndex) {
            let newCurrent = allErrors[currentIndex]
            if currentError?.start != newCurrent.start || currentError?.end != newCurrent.end {
                Logger.debug("SuggestionPopover: syncErrorsAfterReplacement - updated position from \(currentError?.start ?? -1)-\(currentError?.end ?? -1) to \(newCurrent.start)-\(newCurrent.end)", category: Logger.ui)
                currentError = newCurrent
                onCurrentErrorChanged?(currentError)
            }
        } else if allErrors.isEmpty {
            currentError = nil
            hide()
        }
    }

    // MARK: - View Rebuild

    /// Rebuild the content view from scratch for clean rendering
    /// This ensures no artifacts when switching between errors of different sizes
    private func rebuildContentView() {
        guard let panel,
              let trackingView = panel.contentView as? PopoverTrackingView else { return }

        // Increment counter to force SwiftUI to treat this as a completely new view
        // This prevents cached layout from LiquidGlass background
        rebuildCounter += 1

        // Remove old hosting view completely
        trackingView.subviews.forEach { $0.removeFromSuperview() }

        // Create fresh content view with FirstMouseHostingView for immediate button responsiveness
        let contentView = UnifiedPopoverContentView(popover: self)
        let hostingView = FirstMouseHostingView(rootView: contentView)

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
        let width = min(max(fittingSize.width, 380), 550)
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

    // MARK: - Status Messages

    /// Show a temporary status message in the popover
    /// - Parameters:
    ///   - message: The message to display
    ///   - duration: How long to show the message (default 3 seconds)
    func showStatusMessage(_ message: String, duration: TimeInterval = 3.0) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Cancel any existing timer
            statusMessageTimer?.invalidate()

            // Set the message
            statusMessage = message
            Logger.trace("Popover: Showing status message", category: Logger.ui)

            // Rebuild content to resize popover for the new message
            rebuildContentView()

            // Auto-hide after duration
            statusMessageTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.statusMessage = nil
                    // Rebuild again when message is hidden to shrink popover
                    self?.rebuildContentView()
                }
            }
        }
    }

    // MARK: - Error Synchronization

    /// Synchronize the popover's error and style suggestion lists with the canonical lists from the coordinator.
    /// Called after re-analysis to ensure the popover shows the correct counts.
    /// - Parameters:
    ///   - errors: The current canonical list of grammar errors
    ///   - styleSuggestions: The current canonical list of style suggestions
    func syncErrors(_ errors: [GrammarErrorModel], styleSuggestions: [StyleSuggestionModel] = []) {
        guard isVisible else { return }

        // Don't sync while actively processing a suggestion - the popover manages
        // its own state during apply/dismiss/ignore operations
        guard !isProcessing else {
            Logger.debug("Popover: Skipping sync while processing", category: Logger.ui)
            return
        }

        // Don't sync while navigating - prevents race condition
        guard !isNavigating else {
            Logger.debug("Popover: Skipping sync while navigating", category: Logger.ui)
            return
        }

        // Don't sync during replacement mode - syncErrorsAfterReplacement has already
        // updated the popover state, and re-analysis sync could reset it incorrectly
        guard !AnalysisCoordinator.shared.isInReplacementMode else {
            Logger.debug("Popover: Skipping sync during replacement mode", category: Logger.ui)
            return
        }

        let previousErrorCount = allErrors.count
        let previousStyleCount = allStyleSuggestions.count
        allErrors = errors
        allStyleSuggestions = styleSuggestions

        // Adjust currentIndex if needed
        if currentIndex >= allErrors.count {
            currentIndex = max(0, allErrors.count - 1)
        }

        // Update currentError if in grammar mode
        if mode == .grammarError {
            if allErrors.isEmpty, allStyleSuggestions.isEmpty {
                hide()
            } else if allErrors.isEmpty {
                // Switch to style mode if no errors left but style suggestions exist
                mode = .styleSuggestion
                currentError = nil
                currentStyleSuggestion = allStyleSuggestions.first
            } else {
                currentError = allErrors.indices.contains(currentIndex) ? allErrors[currentIndex] : allErrors.first
            }
        }

        let totalChanged = previousErrorCount != allErrors.count || previousStyleCount != allStyleSuggestions.count
        if totalChanged {
            Logger.debug("Popover: Synced items (errors: \(previousErrorCount) -> \(allErrors.count), style: \(previousStyleCount) -> \(allStyleSuggestions.count))", category: Logger.ui)
            rebuildContentView()
        }
    }

    // MARK: - Grammar Error Actions

    /// Apply suggestion
    func applySuggestion(_ suggestion: String) {
        Logger.debug("Popover: applySuggestion called", category: Logger.ui)

        // CRITICAL: Set lastReplacementTime IMMEDIATELY to prevent position refresh
        // The click that triggered this also triggers PositionRefreshCoordinator's mouse monitor,
        // and we need isInReplacementMode to be true BEFORE the refresh is scheduled
        AnalysisCoordinator.shared.lastReplacementTime = Date()

        guard let error = currentError else {
            Logger.debug("Popover: No currentError - cannot apply suggestion", category: Logger.ui)
            return
        }

        // Prevent rapid-fire clicks - wait for previous replacement to complete
        guard !isProcessing else {
            Logger.debug("Popover: Ignoring click - still processing previous suggestion", category: Logger.ui)
            return
        }

        Logger.debug("Popover: Applying suggestion for error at \(error.start)-\(error.end)", category: Logger.ui)

        isProcessing = true

        // Call the replacement asynchronously
        Task { @MainActor [weak self] in
            guard let self else { return }

            await onApplySuggestion?(error, suggestion)

            // NOTE: The coordinator's syncErrorsAfterReplacement has already:
            // 1. Updated allErrors with adjusted positions (error removed, positions shifted)
            // 2. Updated currentError to the next error
            // 3. Called onCurrentErrorChanged to update the highlight
            //
            // We should NOT adjust positions here as that would double-adjust them.
            // Just update the local sourceText and handle UI state.

            // Update sourceText to reflect the applied correction
            if !sourceText.isEmpty,
               error.start <= error.end,
               let startIndex = TextIndexConverter.scalarIndexToStringIndex(error.start, in: sourceText),
               let endIndex = TextIndexConverter.scalarIndexToStringIndex(error.end, in: sourceText),
               startIndex <= endIndex
            {
                sourceText.replaceSubrange(startIndex ..< endIndex, with: suggestion)
            }

            // Check if we should hide or continue showing
            if allErrors.isEmpty {
                hide()
            } else {
                // Rebuild to show the next error (currentError was already updated by syncErrorsAfterReplacement)
                rebuildContentView()
            }

            isProcessing = false
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
            // Safe access with bounds check
            currentError = allErrors.indices.contains(currentIndex) ? allErrors[currentIndex] : nil

            // Notify about current error change (for updating locked highlight)
            onCurrentErrorChanged?(currentError)

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
            // Safe access with bounds check
            currentError = allErrors.indices.contains(currentIndex) ? allErrors[currentIndex] : nil

            // Notify about current error change (for updating locked highlight)
            onCurrentErrorChanged?(currentError)

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

            // Notify about current error change (for updating locked highlight)
            onCurrentErrorChanged?(currentError)

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
        Logger.debug("Style popover: Accept clicked", category: Logger.ui)
        guard let suggestion = currentStyleSuggestion else { return }

        onAcceptStyleSuggestion?(suggestion)
        UserStatistics.shared.recordStyleAcceptance()

        // Move to next suggestion or hide
        moveToNextStyleSuggestion()
    }

    /// Reject current style suggestion with category
    func rejectStyleSuggestion(category: SuggestionRejectionCategory) {
        guard let suggestion = currentStyleSuggestion else { return }

        onRejectStyleSuggestion?(suggestion, category)
        UserStatistics.shared.recordStyleRejection(category: category.rawValue)

        // Move to next suggestion or hide
        moveToNextStyleSuggestion()
    }

    /// Regenerate current style suggestion to get an alternative
    func regenerateStyleSuggestion() {
        guard let suggestion = currentStyleSuggestion else { return }

        isRegenerating = true
        let currentCount = regenerationCounts[suggestion.id] ?? 0
        regenerationCounts[suggestion.id] = currentCount + 1
        Logger.debug("Style popover: Regenerating suggestion \(suggestion.id), attempt \(currentCount + 1)", category: Logger.ui)

        Task { @MainActor in
            if let newSuggestion = await onRegenerateStyleSuggestion?(suggestion) {
                // Replace current suggestion with new one in the list
                if let index = allStyleSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    allStyleSuggestions[index] = newSuggestion
                    currentStyleSuggestion = newSuggestion
                    // Transfer regeneration count to new suggestion
                    regenerationCounts[newSuggestion.id] = regenerationCounts[suggestion.id]
                    regenerationCounts.removeValue(forKey: suggestion.id)
                    // Use resize-only update to avoid visual flash
                    // SwiftUI will automatically update the view content since currentStyleSuggestion is @Published
                    resizePanelToFitContent()
                }
            }
            isRegenerating = false
        }
    }

    /// Resize panel to fit current content without destroying the view
    /// Used during regeneration to avoid visual flash from full rebuild
    private func resizePanelToFitContent() {
        guard let panel,
              let trackingView = panel.contentView as? PopoverTrackingView,
              let hostingView = trackingView.subviews.first
        else {
            Logger.debug("Popover: resizePanelToFitContent - guard failed, falling back to rebuild", category: Logger.ui)
            rebuildContentView()
            return
        }

        // Force SwiftUI layout pass
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        // Get the new size SwiftUI wants
        let fittingSize = hostingView.fittingSize
        let width = min(max(fittingSize.width, 380), 550)
        let height = min(fittingSize.height, 400)

        // Calculate new position keeping TOP edge fixed
        let currentFrame = panel.frame
        let currentTop = currentFrame.origin.y + currentFrame.size.height
        let newOriginY = currentTop - height

        // Resize panel smoothly
        panel.setFrame(NSRect(x: currentFrame.origin.x, y: newOriginY, width: width, height: height), display: true, animate: false)

        // Update views to match
        trackingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        Logger.debug("Popover: Resized to fit content - \(width) x \(height)", category: Logger.ui)
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

        // Reset loading state when switching suggestions
        isGeneratingSimplification = false

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
    /// Stored open direction from indicator - used for positioning from indicator clicks
    private var indicatorOpenDirection: PopoverOpenDirection = .top

    func showUnified(errors: [GrammarErrorModel], styleSuggestions: [StyleSuggestionModel], at position: CGPoint, openDirection: PopoverOpenDirection = .top, constrainToWindow: CGRect? = nil, sourceText: String = "") {
        let startTime = Date()
        Logger.info("SuggestionPopover.showUnified START - errors=\(errors.count), styleSuggestions=\(styleSuggestions.count)", category: Logger.ui)

        // Reset loading state when showing new unified view
        isGeneratingSimplification = false

        // Mark as opened from indicator - popover persists until explicitly dismissed
        openedFromIndicator = true

        // Store open direction for positioning
        indicatorOpenDirection = openDirection

        // Store both collections for unified cycling
        allErrors = errors
        allStyleSuggestions = styleSuggestions
        self.sourceText = sourceText

        // Start at unified index 0 (first item sorted by position)
        unifiedIndex = 0

        // Determine which type of item comes first
        let items = unifiedItems
        guard !items.isEmpty else {
            Logger.debug("SuggestionPopover.showUnified - no items to show", category: Logger.ui)
            return
        }

        // Set mode and current item based on first unified item
        switch items[0] {
        case let .grammar(error):
            mode = .grammarError
            currentError = error
            currentStyleSuggestion = nil
            currentIndex = 0
            // Notify about current error change (for locked highlight)
            onCurrentErrorChanged?(error)

        case let .style(suggestion):
            mode = .styleSuggestion
            currentStyleSuggestion = suggestion
            currentError = nil
            currentStyleIndex = 0
            // Clear locked highlight when showing style suggestion
            onCurrentErrorChanged?(nil)
        }

        showPanelAtPosition(position, constrainToWindow: constrainToWindow)

        let elapsed = Date().timeIntervalSince(startTime)
        Logger.info("SuggestionPopover.showUnified COMPLETE - took \(String(format: "%.3f", elapsed))s", category: Logger.ui)
    }

    // MARK: - Unified Navigation

    /// Navigate to the next item in the unified list (grammar errors + style suggestions)
    /// Wraps around to the first item when at the end
    func nextUnifiedItem() {
        // Prevent syncErrors() from modifying data during navigation
        isNavigating = true
        defer { isNavigating = false }

        let items = unifiedItems
        Logger.debug("Popover: nextUnifiedItem called, items.count=\(items.count), unifiedIndex=\(unifiedIndex)", category: Logger.ui)
        guard !items.isEmpty else {
            Logger.debug("Popover: nextUnifiedItem - no items, returning", category: Logger.ui)
            return
        }

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
        // Prevent syncErrors() from modifying data during navigation
        isNavigating = true
        defer { isNavigating = false }

        let items = unifiedItems
        Logger.debug("Popover: previousUnifiedItem called, items.count=\(items.count), unifiedIndex=\(unifiedIndex)", category: Logger.ui)
        guard !items.isEmpty else {
            Logger.debug("Popover: previousUnifiedItem - no items, returning", category: Logger.ui)
            return
        }

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
        guard index >= 0, index < items.count else {
            Logger.debug("Popover: showUnifiedItem - invalid index \(index), items.count=\(items.count)", category: Logger.ui)
            return
        }

        Logger.debug("Popover: showUnifiedItem at index \(index)", category: Logger.ui)

        switch items[index] {
        case let .grammar(error):
            mode = .grammarError
            currentError = error
            currentStyleSuggestion = nil
            // Update currentIndex to match this error
            if let errorIndex = allErrors.firstIndex(where: { $0.start == error.start && $0.end == error.end }) {
                currentIndex = errorIndex
            }
            Logger.debug("Popover: Switched to grammar error at \(error.start)-\(error.end), currentIndex=\(currentIndex)", category: Logger.ui)
            // Notify about current error change (for locked highlight)
            onCurrentErrorChanged?(error)

        case let .style(suggestion):
            mode = .styleSuggestion
            currentStyleSuggestion = suggestion
            currentError = nil
            // Update currentStyleIndex to match this suggestion
            if let styleIndex = allStyleSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
                currentStyleIndex = styleIndex
            }
            Logger.debug("Popover: Switched to style suggestion, currentStyleIndex=\(currentStyleIndex)", category: Logger.ui)
            // Clear locked highlight when showing style suggestion
            onCurrentErrorChanged?(nil)
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
                if case let .grammar(e) = $0 { return e.start == error.start && e.end == error.end }
                return false
            }) {
                unifiedIndex = idx
            }

        case .styleSuggestion:
            guard let suggestion = currentStyleSuggestion else { return }
            if let idx = items.firstIndex(where: {
                if case let .style(s) = $0 { return s.id == suggestion.id }
                return false
            }) {
                unifiedIndex = idx
            }
        }
    }
}

// MARK: - Position Helper

extension SuggestionPopover {
    /// Position for error range in AX element
    static func errorPosition(in element: AXUIElement, for error: GrammarErrorModel) -> CGPoint? {
        let location = error.start
        let length = error.end - error.start

        var range = CFRange(location: location, length: max(1, length))
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return cursorPosition(in: element)
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
              let rect = safeAXValueGetRect(axValue)
        else {
            return cursorPosition(in: element)
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

    /// Cursor position from AX element
    static func cursorPosition(in element: AXUIElement) -> CGPoint? {
        // Try to get selected text range
        var rangeValue: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )

        guard rangeError == .success,
              let range = rangeValue
        else {
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
              let rect = safeAXValueGetRect(axValue)
        else {
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

// MARK: - First Mouse Hosting View

/// Custom NSHostingView that accepts first mouse clicks in non-activating panels.
/// Standard NSHostingView doesn't accept first mouse, causing SwiftUI buttons
/// to be unresponsive until the panel is clicked once to "activate" it.
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
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
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        setupTracking()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // CRITICAL: Accept first mouse click without requiring panel activation
    // This allows buttons to be clicked immediately in non-activating panels
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
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

    override func mouseEntered(with _: NSEvent) {
        Logger.trace("Popover: Mouse ENTERED tracking view", category: Logger.ui)
        popover?.cancelHide()
        popover?.onMouseEntered?()
    }

    override func mouseExited(with _: NSEvent) {
        Logger.trace("Popover: Mouse EXITED tracking view", category: Logger.ui)
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

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTracking() {
        // Use .activeAlways for NSPanel/floating windows
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .inVisibleRect,
            .activeAlways, // Critical for NSPanel
        ]

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )

        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with _: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with _: NSEvent) {
        onHoverChange?(false)
    }

    override func hitTest(_: NSPoint) -> NSView? {
        // Return nil to let clicks pass through to buttons below
        // But tracking areas still work because mouseEntered/mouseExited
        // are called before hitTest determines the event target
        nil
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

    func makeNSView(context _: Context) -> TransparentHoverView {
        let view = TransparentHoverView(frame: frame)
        view.onHoverChange = mouseIsInside
        return view
    }

    func updateNSView(_ nsView: TransparentHoverView, context _: Context) {
        nsView.onHoverChange = mouseIsInside
    }

    static func dismantleNSView(_ nsView: TransparentHoverView, coordinator _: Void) {
        nsView.trackingAreas.forEach { nsView.removeTrackingArea($0) }
    }
}

extension View {
    /// Reliable hover tracking that works in NSPanel/floating windows
    func whenHovered(_ mouseIsInside: @escaping (Bool) -> Void) -> some View {
        modifier(ReliableHoverModifier(mouseIsInside: mouseIsInside))
    }
}

// Tooltip views extracted to Sources/UI/Tooltip/FloatingTooltip.swift

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

    /// Accent color for the current suggestion type
    private var accentColor: Color {
        popover.currentStyleSuggestion?.isReadabilitySuggestion == true
            ? Color(nsColor: .systemPurple) // Violet for readability
            : Color.purple // Purple for style
    }

    /// Header text for the current suggestion type
    private var headerText: String {
        guard let suggestion = popover.currentStyleSuggestion else { return "Style suggestion" }
        if suggestion.isReadabilitySuggestion {
            // Info-only mode (no AI suggestion available)
            if suggestion.suggestedText.isEmpty {
                return "Complex Sentence"
            }
            if let audience = suggestion.targetAudience {
                return "Simplify for \(audience)"
            }
            return "Readability suggestion"
        }
        return "Style suggestion"
    }

    /// Whether this is an info-only readability display (no AI suggestion available)
    private var isInfoOnlyMode: Bool {
        guard let suggestion = popover.currentStyleSuggestion else { return false }
        return suggestion.isReadabilitySuggestion && suggestion.suggestedText.isEmpty && !popover.isGeneratingSimplification
    }

    /// Whether we're loading an AI simplification
    private var isLoadingSimplification: Bool {
        popover.isGeneratingSimplification
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let suggestion = popover.currentStyleSuggestion {
                // Header row with category and close button (Tahoe style)
                HStack(alignment: .center, spacing: 8) {
                    // Indicator dot with subtle glow (violet for readability, purple for style)
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: accentColor.opacity(0.4), radius: 3, x: 0, y: 0)
                        .accessibilityHidden(true)

                    // Header label
                    Text(headerText)
                        .font(.system(size: baseTextSize * 0.85, weight: .semibold))
                        .foregroundColor(colors.textPrimary.opacity(0.85))
                        .accessibilityAddTraits(.isHeader)

                    // Show readability score badge for readability suggestions
                    if suggestion.isReadabilitySuggestion, let score = suggestion.readabilityScore {
                        Text("Score: \(score)")
                            .font(.system(size: baseTextSize * 0.75, weight: .medium))
                            .foregroundColor(colors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(accentColor.opacity(0.15))
                            )
                    }

                    Spacer()

                    // Close button
                    Button(action: { popover.hide() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(colors.textTertiary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Close (⌥Esc)")
                    .accessibilityLabel("Close style suggestion")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Content area
                VStack(alignment: .leading, spacing: 10) {
                    if isLoadingSimplification {
                        // Loading state: show sentence with spinner
                        VStack(alignment: .leading, spacing: 8) {
                            // The complex sentence (italic, with quotes)
                            Text("\"\(suggestion.originalText)\"")
                                .font(.system(size: baseTextSize, design: .default).italic())
                                .foregroundColor(colors.textPrimary.opacity(0.85))
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)

                            // Loading indicator
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating simpler alternative...")
                                    .font(.system(size: baseTextSize * 0.9))
                                    .foregroundColor(colors.textSecondary)
                            }
                            .padding(.vertical, 8)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Generating simplification for: \(suggestion.originalText)")
                    } else if isInfoOnlyMode {
                        // Info-only mode: show sentence with complexity info (AI not available)
                        VStack(alignment: .leading, spacing: 8) {
                            // The complex sentence (italic, with quotes)
                            Text("\"\(suggestion.originalText)\"")
                                .font(.system(size: baseTextSize, design: .default).italic())
                                .foregroundColor(colors.textPrimary.opacity(0.85))
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)

                            // Explanation
                            Text(suggestion.explanation)
                                .font(.system(size: baseTextSize * 0.9))
                                .foregroundColor(colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            // Tip - AI not available
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.textTertiary)
                                Text("Apple Intelligence is required for simplification suggestions.")
                                    .font(.system(size: baseTextSize * 0.85))
                                    .foregroundColor(colors.textTertiary)
                            }
                            .padding(.top, 4)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Complex sentence: \(suggestion.originalText). \(suggestion.explanation)")
                    } else {
                        // Normal mode: show diff view
                        ScrollView {
                            if !suggestion.diff.isEmpty {
                                StyleDiffView(diff: suggestion.diff, showInline: true)
                                    .font(.system(size: baseTextSize))
                                    .textSelection(.enabled)
                            } else {
                                // Fallback for suggestions without diff data
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.originalText)
                                        .font(.system(size: baseTextSize))
                                        .foregroundColor(.red.opacity(0.85))
                                        .strikethrough(true, color: .red)
                                    Text(suggestion.suggestedText)
                                        .font(.system(size: baseTextSize))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Change from: \(suggestion.originalText), to: \(suggestion.suggestedText)")

                        // Explanation
                        Text(suggestion.explanation)
                            .font(.system(size: baseTextSize * 0.9))
                            .foregroundColor(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Explanation: \(suggestion.explanation)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                // Bottom action bar (Tahoe style with rounded bottom corners)
                // Hidden in info-only mode and loading mode (no suggestion to accept/reject yet)
                if !isInfoOnlyMode, !isLoadingSimplification {
                    HStack(spacing: 8) {
                        // Accept button - subtle style with accent color (purple for style, violet for readability)
                        Button(action: { popover.acceptStyleSuggestion() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Accept")
                                    .font(.system(size: baseTextSize * 0.9, weight: .medium))
                            }
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(accentColor.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Accept this suggestion")
                        .accessibilityLabel("Accept suggestion")

                        // Reject menu - subtle style
                        Menu {
                            ForEach(SuggestionRejectionCategory.allCases, id: \.self) { category in
                                Button(category.displayName) {
                                    popover.rejectStyleSuggestion(category: category)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Reject")
                                    .font(.system(size: baseTextSize * 0.9, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundColor(colors.textSecondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("Reject suggestion")

                        // Try Another button - regenerate style suggestion
                        Button(action: { popover.regenerateStyleSuggestion() }) {
                            HStack(spacing: 4) {
                                if popover.isRegenerating {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 11, height: 11)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                Text("Retry")
                                    .font(.system(size: baseTextSize * 0.9, weight: .medium))
                            }
                            .foregroundColor(colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .disabled(popover.isRegenerating)
                        .help("Generate alternative suggestion")
                        .accessibilityLabel("Retry suggestion")

                        Spacer()

                        // Navigation controls - only shown when popover opened from indicator
                        if popover.openedFromIndicator, popover.totalItemCount > 1 {
                            Text("\(popover.unifiedIndex + 1) of \(popover.totalItemCount)")
                                .font(.system(size: baseTextSize * 0.8))
                                .foregroundColor(colors.textSecondary)
                                .accessibilityLabel("Suggestion \(popover.unifiedIndex + 1) of \(popover.totalItemCount)")

                            HStack(spacing: 2) {
                                Button(action: {
                                    Logger.debug("Style popover: Previous button action", category: Logger.ui)
                                    popover.previousUnifiedItem()
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(colors.textSecondary)
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)
                                .keyboardShortcut(.upArrow, modifiers: [])
                                .hoverTooltip("Previous")

                                Button(action: {
                                    Logger.debug("Style popover: Next button action", category: Logger.ui)
                                    popover.nextUnifiedItem()
                                }) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(colors.textSecondary)
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)
                                .keyboardShortcut(.downArrow, modifiers: [])
                                .hoverTooltip("Next")
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
            } else {
                Text("No style suggestions to display")
                    .foregroundColor(colors.textSecondary)
                    .padding()
                    .accessibilityLabel("No style suggestions to display")
            }
        }
        // Tahoe-style background: subtle gradient with refined border
        .background(
            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [colors.backgroundGradientTop, colors.backgroundGradientBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Subtle inner border for definition
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
        // Fixed width, vertical sizing to content
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .colorScheme(effectiveColorScheme)
    }
}

// FlowLayout extracted to Sources/UI/Layout/FlowLayout.swift
