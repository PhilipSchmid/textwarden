//
//  FloatingErrorIndicator.swift
//  TextWarden
//
//  Floating error indicator
//  Shows a small circular badge in the bottom-right corner of text fields
//

import Cocoa
import AppKit
import Combine

/// Display mode for the floating indicator
enum IndicatorMode {
    case errors([GrammarErrorModel])
    case styleSuggestions([StyleSuggestionModel])
    case both(errors: [GrammarErrorModel], styleSuggestions: [StyleSuggestionModel])

    var hasErrors: Bool {
        switch self {
        case .errors(let errors): return !errors.isEmpty
        case .styleSuggestions: return false
        case .both(let errors, _): return !errors.isEmpty
        }
    }

    var hasStyleSuggestions: Bool {
        switch self {
        case .errors: return false
        case .styleSuggestions(let suggestions): return !suggestions.isEmpty
        case .both(_, let suggestions): return !suggestions.isEmpty
        }
    }

    var isEmpty: Bool {
        switch self {
        case .errors(let errors): return errors.isEmpty
        case .styleSuggestions(let suggestions): return suggestions.isEmpty
        case .both(let errors, let suggestions): return errors.isEmpty && suggestions.isEmpty
        }
    }
}

/// Floating error indicator window
class FloatingErrorIndicator: NSPanel {

    // MARK: - Singleton

    /// Shared singleton instance
    static let shared = FloatingErrorIndicator()

    // MARK: - Properties

    /// Current display mode
    private var mode: IndicatorMode = .errors([])

    /// Current errors being displayed
    private var errors: [GrammarErrorModel] = []

    /// Current style suggestions being displayed
    private var styleSuggestions: [StyleSuggestionModel] = []

    /// Source text for error context display
    private var sourceText: String = ""

    /// Current monitored element
    private var monitoredElement: AXUIElement?

    /// Application context
    private var context: ApplicationContext?

    /// Custom view for drawing the indicator
    private var indicatorView: IndicatorView?

    /// Border guide window for drag feedback
    private let borderGuide = BorderGuideWindow()

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 40, height: 40)

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Window configuration
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))  // Highest possible level
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let indicatorView = IndicatorView(frame: initialFrame)
        indicatorView.onClicked = { [weak self] in
            self?.togglePopover()
        }
        indicatorView.onHover = { [weak self] isHovering in
            // Only trigger hover behavior if hover popover is enabled
            guard UserPreferences.shared.enableHoverPopover else { return }
            if isHovering {
                self?.showErrors()
            } else {
                SuggestionPopover.shared.scheduleHide()
            }
        }
        indicatorView.onDragStart = { [weak self] in
            guard let self = self else { return }

            Logger.debug("onDragStart triggered!", category: Logger.ui)

            SuggestionPopover.shared.hide()

            // Enlarge indicator to show it's being dragged
            let currentFrame = self.frame
            let normalSize: CGFloat = UIConstants.indicatorSize
            let enlargedSize: CGFloat = UIConstants.indicatorDragSize
            let sizeDelta = enlargedSize - normalSize

            // Adjust origin to keep indicator centered while enlarging
            let newFrame = NSRect(
                x: currentFrame.origin.x - sizeDelta / 2,
                y: currentFrame.origin.y - sizeDelta / 2,
                width: enlargedSize,
                height: enlargedSize
            )
            self.setFrame(newFrame, display: true)

            // Ensure indicator stays visible and in front during drag
            self.alphaValue = 0.85  // Slightly transparent to see what's underneath
            self.orderFrontRegardless()
            self.level = .popUpMenu + 2  // Increase level during drag

            if let element = self.monitoredElement,
               let windowFrame = self.getVisibleWindowFrame(for: element) {
                Logger.debug("Showing border guide with frame: \(windowFrame)", category: Logger.ui)

                // Use theme-based color matching the popover background
                self.borderGuide.showBorder(around: windowFrame)
            } else {
                Logger.debug("Cannot show border guide - element=\(String(describing: self.monitoredElement))", category: Logger.ui)
            }
        }
        indicatorView.onDragEnd = { [weak self] finalPosition in
            guard let self = self else { return }

            // Restore normal size
            let normalSize: CGFloat = UIConstants.indicatorSize
            let enlargedSize: CGFloat = UIConstants.indicatorDragSize
            let sizeDelta = enlargedSize - normalSize

            // Adjust origin to keep indicator centered while shrinking back
            let newFrame = NSRect(
                x: finalPosition.x + sizeDelta / 2,
                y: finalPosition.y + sizeDelta / 2,
                width: normalSize,
                height: normalSize
            )
            self.setFrame(newFrame, display: true)

            // Restore normal appearance
            self.alphaValue = 1.0
            self.level = .popUpMenu + 1  // Restore original level

            self.borderGuide.hide()

            // Handle snap positioning with corrected position
            self.handleDragEnd(at: newFrame.origin)
        }
        indicatorView.onRightClicked = { [weak self] event in
            self?.showContextMenu(with: event)
        }
        self.indicatorView = indicatorView
        self.contentView = indicatorView

        // Listen to indicator position changes for immediate repositioning
        setupPositionObserver()
    }

    // CRITICAL: Prevent this window from stealing focus from other applications
    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }

    /// Setup observer for indicator position preference changes
    private func setupPositionObserver() {
        UserPreferences.shared.$indicatorPosition
            .dropFirst()  // Skip initial value
            .receive(on: DispatchQueue.main)  // Ensure UI updates on main thread
            .sink { [weak self] newPosition in
                guard let self = self else { return }

                // If indicator is currently visible with errors, reposition immediately
                if self.isVisible, let element = self.monitoredElement, !self.errors.isEmpty {
                    Logger.debug("FloatingErrorIndicator: Position changed to '\(newPosition)' - repositioning", category: Logger.ui)
                    self.positionIndicator(for: element)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Update indicator with errors and optional style suggestions
    func update(
        errors: [GrammarErrorModel],
        styleSuggestions: [StyleSuggestionModel] = [],
        element: AXUIElement,
        context: ApplicationContext?,
        sourceText: String = ""
    ) {
        Logger.debug("FloatingErrorIndicator: update() called with \(errors.count) errors, \(styleSuggestions.count) style suggestions", category: Logger.ui)

        // CRITICAL: Check watchdog BEFORE making any AX calls
        // Skip positioning if the app is blacklisted (AX API unresponsive)
        let bundleID = context?.bundleIdentifier ?? "unknown"
        if AXWatchdog.shared.shouldSkipCalls(for: bundleID) {
            Logger.debug("FloatingErrorIndicator: Skipping - watchdog active for \(bundleID)", category: Logger.ui)
            hide()
            return
        }

        self.errors = errors
        self.styleSuggestions = styleSuggestions
        self.monitoredElement = element
        self.context = context
        self.sourceText = sourceText

        // Determine mode based on what we have
        if !errors.isEmpty && !styleSuggestions.isEmpty {
            self.mode = .both(errors: errors, styleSuggestions: styleSuggestions)
        } else if !styleSuggestions.isEmpty {
            self.mode = .styleSuggestions(styleSuggestions)
        } else {
            self.mode = .errors(errors)
        }

        guard !mode.isEmpty else {
            Logger.debug("FloatingErrorIndicator: No errors or suggestions, hiding", category: Logger.ui)
            hide()
            return
        }

        // Configure indicator view based on mode
        if mode.hasStyleSuggestions && !mode.hasErrors {
            // Style suggestions only - show count with purple ring (same as grammar errors)
            indicatorView?.displayMode = .count(styleSuggestions.count)
            indicatorView?.ringColor = .purple
        } else if mode.hasErrors {
            // Errors present (possibly with style suggestions) - show error count
            indicatorView?.displayMode = .count(errors.count)
            indicatorView?.ringColor = colorForErrors(errors)
        }
        indicatorView?.needsDisplay = true

        // Position in bottom-right of text field
        positionIndicator(for: element)

        Logger.debug("FloatingErrorIndicator: Window level: \(self.level.rawValue), isVisible: \(isVisible)", category: Logger.ui)
        if !isVisible {
            Logger.debug("FloatingErrorIndicator: Calling order(.above)", category: Logger.ui)
            order(.above, relativeTo: 0)  // Show window without stealing focus
            Logger.debug("FloatingErrorIndicator: After order(.above), isVisible: \(isVisible)", category: Logger.ui)
        } else {
            Logger.debug("FloatingErrorIndicator: Window already visible", category: Logger.ui)
        }
    }

    /// Update indicator with errors using only context (no element required)
    /// Used when restoring from window minimize where element may not be available
    func updateWithContext(
        errors: [GrammarErrorModel],
        styleSuggestions: [StyleSuggestionModel] = [],
        context: ApplicationContext,
        sourceText: String = ""
    ) {
        Logger.debug("FloatingErrorIndicator: updateWithContext() called with \(errors.count) errors, \(styleSuggestions.count) style suggestions", category: Logger.ui)
        self.errors = errors
        self.styleSuggestions = styleSuggestions
        self.context = context
        self.sourceText = sourceText
        // Don't set monitoredElement - we don't have one

        // Determine mode based on what we have
        if !errors.isEmpty && !styleSuggestions.isEmpty {
            self.mode = .both(errors: errors, styleSuggestions: styleSuggestions)
        } else if !styleSuggestions.isEmpty {
            self.mode = .styleSuggestions(styleSuggestions)
        } else {
            self.mode = .errors(errors)
        }

        guard !mode.isEmpty else {
            Logger.debug("FloatingErrorIndicator: No errors or suggestions, hiding", category: Logger.ui)
            hide()
            return
        }

        // Configure indicator view based on mode
        if mode.hasStyleSuggestions && !mode.hasErrors {
            // Style suggestions only - show count with purple ring (same as grammar errors)
            indicatorView?.displayMode = .count(styleSuggestions.count)
            indicatorView?.ringColor = .purple
        } else if mode.hasErrors {
            indicatorView?.displayMode = .count(errors.count)
            indicatorView?.ringColor = colorForErrors(errors)
        }
        indicatorView?.needsDisplay = true

        // Position using PID from context (no element needed)
        positionIndicatorByPID(context.processID)

        Logger.debug("FloatingErrorIndicator: Window level: \(self.level.rawValue), isVisible: \(isVisible)", category: Logger.ui)
        if !isVisible {
            Logger.debug("FloatingErrorIndicator: Calling order(.above)", category: Logger.ui)
            order(.above, relativeTo: 0)  // Show window without stealing focus
            Logger.debug("FloatingErrorIndicator: After order(.above), isVisible: \(isVisible)", category: Logger.ui)
        } else {
            Logger.debug("FloatingErrorIndicator: Window already visible", category: Logger.ui)
        }
    }

    /// Position indicator using PID (when no element is available)
    private func positionIndicatorByPID(_ pid: pid_t) {
        guard let visibleFrame = getVisibleWindowFrameByPID(pid) else {
            Logger.debug("FloatingErrorIndicator: Failed to get visible window frame by PID, using screen corner", category: Logger.ui)
            positionInScreenCorner()
            return
        }

        Logger.debug("FloatingErrorIndicator: Using visible window frame (by PID): \(visibleFrame)", category: Logger.ui)

        let indicatorSize: CGFloat = UIConstants.indicatorSize

        // Check for per-app stored position first
        var percentagePos: IndicatorPositionStore.PercentagePosition?
        if let bundleID = context?.bundleIdentifier {
            percentagePos = IndicatorPositionStore.shared.getPosition(for: bundleID)
            if percentagePos != nil {
                Logger.debug("FloatingErrorIndicator: Using stored position for \(bundleID)", category: Logger.ui)
            }
        }

        // If no stored position, use default from preferences
        let resolvedPosition: IndicatorPositionStore.PercentagePosition
        if let existingPos = percentagePos {
            resolvedPosition = existingPos
        } else {
            resolvedPosition = IndicatorPositionStore.shared.getDefaultPosition()
            Logger.debug("FloatingErrorIndicator: Using default position from preferences", category: Logger.ui)
        }

        // Convert percentage to absolute position
        let position = resolvedPosition.toAbsolute(in: visibleFrame, indicatorSize: indicatorSize)
        let finalFrame = NSRect(x: position.x, y: position.y, width: indicatorSize, height: indicatorSize)

        Logger.debug("FloatingErrorIndicator: Positioning at \(finalFrame)", category: Logger.ui)
        setFrame(finalFrame, display: true)
    }

    /// Get visible window frame using PID directly (no element required)
    private func getVisibleWindowFrameByPID(_ pid: pid_t) -> CGRect? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            Logger.debug("FloatingErrorIndicator: Failed to get window list", category: Logger.ui)
            return nil
        }

        // Find the LARGEST window for this PID
        var bestWindow: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, area: CGFloat)?

        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == pid,
               let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {

                let x = boundsDict["X"] ?? 0
                let y = boundsDict["Y"] ?? 0
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0
                let area = width * height

                // Skip tiny windows (likely tooltips or popups)
                guard width >= UIConstants.minimumValidWindowSize && height >= UIConstants.minimumValidWindowSize else { continue }

                if bestWindow.map({ area > $0.area }) ?? true {
                    bestWindow = (x: x, y: y, width: width, height: height, area: area)
                }
            }
        }

        guard let best = bestWindow else {
            Logger.debug("FloatingErrorIndicator: No matching window found for PID \(pid)", category: Logger.ui)
            return nil
        }

        // Convert from CGWindow coordinates (y=0 at top) to Cocoa coordinates (y=0 at bottom)
        // Use PRIMARY screen height (the one with Cocoa frame origin at 0,0)
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        let screenHeight = primaryScreen?.frame.height ?? NSScreen.main?.frame.height ?? 0
        let cocoaY = screenHeight - best.y - best.height

        return CGRect(x: best.x, y: cocoaY, width: best.width, height: best.height)
    }

    /// Hide indicator
    func hide() {
        orderOut(nil)
        borderGuide.hide()
        errors = []
        styleSuggestions = []
        mode = .errors([])
        monitoredElement = nil
    }

    /// Show spinning indicator for style check in progress
    func showStyleCheckInProgress(element: AXUIElement, context: ApplicationContext?) {
        Logger.debug("FloatingErrorIndicator: showStyleCheckInProgress()", category: Logger.ui)
        self.monitoredElement = element
        self.context = context

        // Show spinning indicator with purple ring
        indicatorView?.displayMode = .spinning
        indicatorView?.ringColor = .purple
        indicatorView?.needsDisplay = true

        // Position indicator
        positionIndicator(for: element)

        if !isVisible {
            order(.above, relativeTo: 0)
        }
    }

    /// Update indicator to show style suggestions count (stops spinning)
    /// Note: This preserves existing grammar errors so they can be restored if style check has no findings
    func showStyleSuggestionsReady(count: Int, styleSuggestions: [StyleSuggestionModel]) {
        Logger.debug("FloatingErrorIndicator: showStyleSuggestionsReady(count: \(count)), existing errors: \(errors.count)", category: Logger.ui)
        self.styleSuggestions = styleSuggestions
        // Don't clear errors - preserve them for restoration if style check has no findings
        // self.errors = [] <- Removed to preserve existing grammar errors

        // Update mode based on what we have
        if count > 0 {
            self.mode = .styleSuggestions(styleSuggestions)
        }
        // If count == 0, mode will be updated in showStyleCheckComplete

        // Always show checkmark first to confirm completion
        showStyleCheckComplete(thenShowCount: count)
    }

    /// Show checkmark for style check completion, then transition or hide
    private func showStyleCheckComplete(thenShowCount count: Int) {
        // Cancel any pending hide operations
        styleCheckHideWorkItem?.cancel()

        // Show checkmark immediately
        indicatorView?.displayMode = .styleCheckComplete
        indicatorView?.ringColor = .purple
        indicatorView?.needsDisplay = true

        Logger.debug("FloatingErrorIndicator: Showing style check complete checkmark, existing errors: \(errors.count)", category: Logger.ui)

        // Determine what happens after checkmark display
        let hasStyleSuggestions = count > 0
        let hasGrammarErrors = !errors.isEmpty

        // Short delay for checkmark, then show results or restore errors or hide
        // Use 1 second if there are findings to show, 2 seconds if restoring errors, 3 seconds if hiding
        let delay: TimeInterval
        if hasStyleSuggestions {
            delay = 1.0
        } else if hasGrammarErrors {
            delay = 2.0  // Shorter delay when restoring grammar errors
        } else {
            delay = 3.0  // Longer delay before hiding (no findings at all)
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            if hasStyleSuggestions {
                // Transition to style suggestions count display
                Logger.debug("FloatingErrorIndicator: Transitioning to style count \(count)", category: Logger.ui)
                self.indicatorView?.displayMode = .count(count)
                self.indicatorView?.ringColor = .purple
                self.mode = .styleSuggestions(self.styleSuggestions)
                self.indicatorView?.needsDisplay = true
            } else if hasGrammarErrors {
                // No style suggestions, but we have grammar errors - restore error display
                Logger.debug("FloatingErrorIndicator: Restoring grammar errors display (\(self.errors.count) errors)", category: Logger.ui)
                self.styleSuggestions = []
                self.mode = .errors(self.errors)
                self.indicatorView?.displayMode = .count(self.errors.count)
                self.indicatorView?.ringColor = self.colorForErrors(self.errors)
                self.indicatorView?.needsDisplay = true
            } else {
                // No suggestions and no errors, hide the indicator
                Logger.debug("FloatingErrorIndicator: No suggestions or errors, hiding indicator", category: Logger.ui)
                self.hide()
            }
        }
        styleCheckHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Work item for delayed hide/transition (can be cancelled)
    private var styleCheckHideWorkItem: DispatchWorkItem?

    // MARK: - Drag & Drop Positioning

    /// Handle drag end with snap-back to valid border area
    private func handleDragEnd(at finalPosition: CGPoint) {
        guard let element = monitoredElement,
              let windowFrame = getVisibleWindowFrame(for: element),
              let bundleID = context?.bundleIdentifier else {
            Logger.debug("FloatingErrorIndicator: handleDragEnd - no window frame or bundle ID available", category: Logger.ui)
            return
        }

        let indicatorSize: CGFloat = UIConstants.indicatorSize

        // Snap position to valid border area
        let snappedPosition = snapToBorderArea(
            position: finalPosition,
            windowFrame: windowFrame,
            indicatorSize: indicatorSize
        )

        // Update the indicator position if it was snapped
        if snappedPosition != finalPosition {
            Logger.debug("FloatingErrorIndicator: Snapping from \(finalPosition) to \(snappedPosition)", category: Logger.ui)
            let snappedFrame = NSRect(x: snappedPosition.x, y: snappedPosition.y, width: indicatorSize, height: indicatorSize)
            setFrame(snappedFrame, display: true, animate: true)
        }

        // Convert absolute position to percentage
        let percentagePos = IndicatorPositionStore.PercentagePosition.from(
            absolutePosition: snappedPosition,
            in: windowFrame,
            indicatorSize: indicatorSize
        )

        // Save position for this application
        IndicatorPositionStore.shared.savePosition(percentagePos, for: bundleID)

        Logger.debug("FloatingErrorIndicator: Saved position for \(bundleID) at x=\(percentagePos.xPercent), y=\(percentagePos.yPercent)", category: Logger.ui)
    }

    /// Snap a position to the valid border area (1.5cm band around window edge)
    /// If the position is outside the window or in the center, snaps to closest valid position
    private func snapToBorderArea(position: CGPoint, windowFrame: CGRect, indicatorSize: CGFloat) -> CGPoint {
        let borderWidth = BorderGuideWindow.borderWidth

        // First, clamp position to be within the window bounds
        var snappedX = max(windowFrame.minX, min(position.x, windowFrame.maxX - indicatorSize))
        var snappedY = max(windowFrame.minY, min(position.y, windowFrame.maxY - indicatorSize))

        // Define the valid border area (within borderWidth of any edge)
        let innerRect = windowFrame.insetBy(dx: borderWidth, dy: borderWidth)

        // Check if the indicator center is in the "forbidden" center zone
        let indicatorCenterX = snappedX + indicatorSize / 2
        let indicatorCenterY = snappedY + indicatorSize / 2

        // If the indicator is fully within the inner (forbidden) zone, snap to closest edge
        if innerRect.contains(CGPoint(x: indicatorCenterX, y: indicatorCenterY)) {
            // Calculate distances to each edge of the valid border area
            let distToLeft = indicatorCenterX - windowFrame.minX
            let distToRight = windowFrame.maxX - indicatorCenterX
            let distToBottom = indicatorCenterY - windowFrame.minY
            let distToTop = windowFrame.maxY - indicatorCenterY

            let minDist = min(distToLeft, distToRight, distToBottom, distToTop)

            // Snap to the closest edge
            if minDist == distToLeft {
                snappedX = windowFrame.minX
            } else if minDist == distToRight {
                snappedX = windowFrame.maxX - indicatorSize
            } else if minDist == distToBottom {
                snappedY = windowFrame.minY
            } else {
                snappedY = windowFrame.maxY - indicatorSize
            }

            Logger.debug("FloatingErrorIndicator: Snapped to closest edge (minDist=\(minDist))", category: Logger.ui)
        }

        // Ensure the final position keeps the indicator within the border area
        // The indicator can be anywhere in the border band, not just on the edge
        // But it must have at least part of it within borderWidth of an edge

        return CGPoint(x: snappedX, y: snappedY)
    }

    /// Position indicator based on per-app stored position or user preference
    private func positionIndicator(for element: AXUIElement) {
        // Try to get the actual visible window frame
        guard let visibleFrame = getVisibleWindowFrame(for: element) else {
            Logger.debug("FloatingErrorIndicator: Failed to get visible window frame, using screen corner", category: Logger.ui)
            positionInScreenCorner()
            return
        }

        Logger.debug("FloatingErrorIndicator: Using visible window frame: \(visibleFrame)", category: Logger.ui)

        let indicatorSize: CGFloat = UIConstants.indicatorSize

        // Check for per-app stored position first
        var percentagePos: IndicatorPositionStore.PercentagePosition?
        if let bundleID = context?.bundleIdentifier {
            percentagePos = IndicatorPositionStore.shared.getPosition(for: bundleID)
            if percentagePos != nil {
                Logger.debug("FloatingErrorIndicator: Using stored position for \(bundleID)", category: Logger.ui)
            }
        }

        // If no stored position, use default from preferences
        let resolvedPosition: IndicatorPositionStore.PercentagePosition
        if let existingPos = percentagePos {
            resolvedPosition = existingPos
        } else {
            resolvedPosition = IndicatorPositionStore.shared.getDefaultPosition()
            Logger.debug("FloatingErrorIndicator: Using default position from preferences", category: Logger.ui)
        }

        // Convert percentage to absolute position
        let position = resolvedPosition.toAbsolute(in: visibleFrame, indicatorSize: indicatorSize)
        let finalFrame = NSRect(x: position.x, y: position.y, width: indicatorSize, height: indicatorSize)

        Logger.debug("FloatingErrorIndicator: Positioning at \(finalFrame)", category: Logger.ui)
        setFrame(finalFrame, display: true)
    }

    /// Calculate indicator position based on user preference
    private func calculatePosition(
        for position: String,
        in frame: CGRect,
        indicatorSize: CGFloat,
        padding: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        switch position {
        case "Top Left":
            return (frame.minX + padding, frame.maxY - indicatorSize - padding)
        case "Top Right":
            return (frame.maxX - indicatorSize - padding, frame.maxY - indicatorSize - padding)
        case "Center Left":
            return (frame.minX + padding, frame.midY - indicatorSize / 2)
        case "Center Right":
            return (frame.maxX - indicatorSize - padding, frame.midY - indicatorSize / 2)
        case "Bottom Left":
            return (frame.minX + padding, frame.minY + padding)
        case "Bottom Right":
            return (frame.maxX - indicatorSize - padding, frame.minY + padding)
        default:
            // Default to bottom right
            return (frame.maxX - indicatorSize - padding, frame.minY + padding)
        }
    }

    /// Fallback: position based on user preference using screen bounds
    private func positionInScreenCorner() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 10
        let indicatorSize: CGFloat = UIConstants.indicatorSize
        let position = UserPreferences.shared.indicatorPosition

        let (x, y) = calculatePosition(
            for: position,
            in: screenFrame,
            indicatorSize: indicatorSize,
            padding: padding
        )

        let finalFrame = NSRect(x: x, y: y, width: indicatorSize, height: indicatorSize)
        Logger.debug("FloatingErrorIndicator: Fallback positioning at screen corner: \(finalFrame)", category: Logger.ui)

        setFrame(finalFrame, display: true)
    }

    // MARK: - Window Frame Helpers

    /// Get the actual visible window frame using CGWindowListCopyWindowInfo
    /// This avoids the scrollback buffer issue with Terminal apps
    /// Uses element's kAXWindowAttribute to find the correct window (not largest)
    private func getVisibleWindowFrame(for element: AXUIElement) -> CGRect? {
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) != .success {
            Logger.debug("FloatingErrorIndicator: Failed to get PID from element", category: Logger.ui)
            return nil
        }

        // First, get the window frame from the element's kAXWindowAttribute
        // This ensures we get the CORRECT window (e.g., composition window, not main window)
        let elementWindowFrame = getWindowFrame(for: element)

        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            Logger.debug("FloatingErrorIndicator: Failed to get window list", category: Logger.ui)
            return nil
        }

        // If we have the element's window frame, find the matching CGWindow
        // Otherwise fall back to largest window for this PID
        var bestWindow: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, area: CGFloat)?
        var matchedWindow: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)?

        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == pid,
               let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] {

                // Extract bounds
                let x = boundsDict["X"] ?? 0
                let y = boundsDict["Y"] ?? 0
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0
                let area = width * height

                // Skip tiny windows (likely tooltips or popups)
                guard width >= UIConstants.minimumValidWindowSize && height >= UIConstants.minimumValidWindowSize else { continue }

                // If we have an element window frame, try to match it
                if let axFrame = elementWindowFrame {
                    // CGWindow uses top-left origin, AX uses bottom-left
                    // Compare position with some tolerance (window chrome can cause slight differences)
                    let tolerance: CGFloat = 50
                    let sizeMatch = abs(width - axFrame.width) < tolerance && abs(height - axFrame.height) < tolerance

                    if sizeMatch {
                        Logger.debug("FloatingErrorIndicator: Found matching window for element (size match: \(width)x\(height))", category: Logger.ui)
                        matchedWindow = (x: x, y: y, width: width, height: height)
                        break  // Found exact match, use it
                    }
                }

                // Keep track of the largest window as fallback
                if bestWindow.map({ area > $0.area }) ?? true {
                    bestWindow = (x: x, y: y, width: width, height: height, area: area)
                }
            }
        }

        // Prefer matched window (element's actual window), fall back to largest
        let windowToUse: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)
        if let matched = matchedWindow {
            Logger.debug("FloatingErrorIndicator: Using matched window (element's window)", category: Logger.ui)
            windowToUse = matched
        } else if let best = bestWindow {
            Logger.debug("FloatingErrorIndicator: No exact match, using largest window as fallback", category: Logger.ui)
            windowToUse = (x: best.x, y: best.y, width: best.width, height: best.height)
        } else {
            Logger.debug("FloatingErrorIndicator: No matching window found in window list", category: Logger.ui)
            return nil
        }

        let x = windowToUse.x
        let y = windowToUse.y
        let width = windowToUse.width
        let height = windowToUse.height

        // CGWindowListCopyWindowInfo returns coordinates with y=0 at TOP
        // NSScreen uses Cocoa coordinates with y=0 at BOTTOM
        // CRITICAL: Must find which screen the window is on for proper conversion

        // First, find which screen contains this window
        // We'll check which screen's bounds (in CGWindow coordinates) intersect with the window
        let windowCGRect = CGRect(x: x, y: y, width: width, height: height)
        // Use PRIMARY screen height (the one with Cocoa frame origin at 0,0)
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        let screenHeight = primaryScreen?.frame.height ?? NSScreen.main?.frame.height ?? 0

        var targetScreen: NSScreen?
        var maxIntersection: CGFloat = 0

        for screen in NSScreen.screens {
            // Convert this screen's Cocoa frame to CGWindow coordinates for comparison
            let cocoaFrame = screen.frame
            let cgY = screenHeight - cocoaFrame.maxY
            let cgScreenRect = CGRect(
                x: cocoaFrame.origin.x,
                y: cgY,
                width: cocoaFrame.width,
                height: cocoaFrame.height
            )

            // Check intersection
            let intersection = windowCGRect.intersection(cgScreenRect)
            let area = intersection.width * intersection.height

            if area > maxIntersection {
                maxIntersection = area
                targetScreen = screen
            }
        }

        // Use the screen we found (or fall back to main)
        guard let screen = targetScreen ?? NSScreen.main else {
            Logger.debug("FloatingErrorIndicator: No screen found", category: Logger.ui)
            return nil
        }

        // Convert from CGWindow coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
        let cocoaY = screenHeight - y - height

        let frame = NSRect(x: x, y: cocoaY, width: width, height: height)
        Logger.debug("FloatingErrorIndicator: Window on screen '\(screen.localizedName)' at \(screen.frame) - CGWindow: (\(x), \(y)), Cocoa: \(frame)", category: Logger.ui)

        // Note: Debug borders are now managed by AnalysisCoordinator.updateDebugBorders()
        // to show them always when enabled (not just when errors exist)

        return frame
    }

    /// Get the window frame for the given element (may include scrollback for terminals)
    /// Uses centralized AccessibilityBridge.getWindowFrame() helper
    private func getWindowFrame(for element: AXUIElement) -> CGRect? {
        return AccessibilityBridge.getWindowFrame(element)
    }

    // MARK: - Error Color Mapping

    /// Get color for errors based on severity
    private func colorForErrors(_ errors: [GrammarErrorModel]) -> NSColor {
        // Prioritize by severity: Spelling > Grammar > Style
        if errors.contains(where: { $0.category == "Spelling" || $0.category == "Typo" }) {
            return .systemRed
        } else if errors.contains(where: {
            $0.category == "Grammar" || $0.category == "Agreement" || $0.category == "Punctuation"
        }) {
            return .systemOrange
        } else {
            return .systemBlue
        }
    }

    // MARK: - Popover Display

    /// Show the suggestion popover from keyboard shortcut
    /// Returns true if popover was shown, false if no errors/suggestions available
    @discardableResult
    func showPopoverFromKeyboard() -> Bool {
        guard isVisible else {
            Logger.debug("FloatingErrorIndicator: showPopoverFromKeyboard - indicator not visible", category: Logger.ui)
            return false
        }

        guard !mode.isEmpty else {
            Logger.debug("FloatingErrorIndicator: showPopoverFromKeyboard - no errors or suggestions", category: Logger.ui)
            return false
        }

        Logger.debug("FloatingErrorIndicator: showPopoverFromKeyboard - showing popover", category: Logger.ui)
        showErrors()
        return true
    }

    /// Toggle popover visibility (show if hidden, hide if showing)
    private func togglePopover() {
        if SuggestionPopover.shared.isVisible {
            Logger.debug("FloatingErrorIndicator: togglePopover - hiding visible popover", category: Logger.ui)
            SuggestionPopover.shared.hide()
        } else {
            Logger.debug("FloatingErrorIndicator: togglePopover - showing popover", category: Logger.ui)
            showErrors()
        }
    }

    /// Show errors/suggestions popover
    private func showErrors() {
        Logger.debug("FloatingErrorIndicator: showErrors called - errors=\(errors.count), styleSuggestions=\(styleSuggestions.count)", category: Logger.ui)

        // Position popover inward from indicator based on position
        let indicatorFrame = frame
        let position = calculatePopoverPosition(for: indicatorFrame)

        // Get window frame for constraining popover position
        let windowFrame: CGRect? = monitoredElement.flatMap { getVisibleWindowFrame(for: $0) }

        // Always use showUnified() from indicator - this sets openedFromIndicator=true
        // which prevents auto-hide when mouse leaves the popover
        Logger.debug("FloatingErrorIndicator: Showing unified popover (errors=\(errors.count), styleSuggestions=\(styleSuggestions.count)) at \(position)", category: Logger.ui)
        SuggestionPopover.shared.showUnified(
            errors: errors,
            styleSuggestions: styleSuggestions,
            at: position,
            constrainToWindow: windowFrame,
            sourceText: sourceText
        )
    }

    /// Calculate popover position that points inward from the indicator
    private func calculatePopoverPosition(for indicatorFrame: CGRect) -> CGPoint {
        let indicatorPosition = UserPreferences.shared.indicatorPosition
        // Use larger spacing for left positions (to overcome popover's auto-positioning logic)
        // Use smaller spacing for right positions to match visual gap
        let leftSpacing: CGFloat = UIConstants.popoverLeftSpacing
        let rightSpacing: CGFloat = UIConstants.popoverRightSpacing

        // For indicator-triggered popover, position anchor closer to get popover near indicator
        // The SuggestionPopover will center horizontally and add vertical spacing
        switch indicatorPosition {
        case "Top Left":
            // Indicator at top-left → popover below-right of indicator
            return CGPoint(x: indicatorFrame.maxX + leftSpacing, y: indicatorFrame.minY)
        case "Top Right":
            // Indicator at top-right → popover below-left of indicator
            return CGPoint(x: indicatorFrame.minX - rightSpacing, y: indicatorFrame.minY)
        case "Center Left":
            // Indicator at center-left → popover to the right, vertically centered
            return CGPoint(x: indicatorFrame.maxX + leftSpacing, y: indicatorFrame.midY + 75)
        case "Center Right":
            // Indicator at center-right → popover to the left, vertically centered
            return CGPoint(x: indicatorFrame.minX - rightSpacing, y: indicatorFrame.midY + 75)
        case "Bottom Left":
            // Indicator at bottom-left → popover above-right of indicator
            return CGPoint(x: indicatorFrame.maxX + leftSpacing, y: indicatorFrame.maxY + 150)
        case "Bottom Right":
            // Indicator at bottom-right → popover above-left of indicator
            return CGPoint(x: indicatorFrame.minX - rightSpacing, y: indicatorFrame.maxY + 150)
        default:
            return CGPoint(x: indicatorFrame.midX, y: indicatorFrame.maxY + 10)
        }
    }

    // MARK: - Context Menu

    /// Show context menu for pause options
    private func showContextMenu(with event: NSEvent) {
        Logger.debug("FloatingErrorIndicator: showContextMenu", category: Logger.ui)

        // Hide suggestion popover when showing context menu
        SuggestionPopover.shared.hide()

        let menu = NSMenu()

        // Global pause options
        addGlobalPauseItems(to: menu)

        // App-specific pause options (if we have a context)
        if let ctx = context, ctx.bundleIdentifier != "io.textwarden.TextWarden" {
            menu.addItem(NSMenuItem.separator())
            addAppSpecificPauseItems(to: menu, context: ctx)
        }

        // Preferences
        menu.addItem(NSMenuItem.separator())
        let preferencesItem = NSMenuItem(
            title: "Preferences",
            action: #selector(openPreferences),
            keyEquivalent: ""
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        // Show menu at mouse location
        guard let indicatorView = indicatorView else { return }
        let locationInView = indicatorView.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: locationInView, in: indicatorView)
    }

    /// Add global pause menu items
    private func addGlobalPauseItems(to menu: NSMenu) {
        let preferences = UserPreferences.shared

        // Header
        let headerItem = NSMenuItem(title: "Grammar Checking:", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Active option
        let activeItem = NSMenuItem(
            title: "Active",
            action: #selector(setGlobalPauseActive),
            keyEquivalent: ""
        )
        activeItem.target = self
        activeItem.state = preferences.pauseDuration == .active ? .on : .off
        menu.addItem(activeItem)

        // Pause for 1 Hour
        let oneHourItem = NSMenuItem(
            title: "Paused for 1 Hour",
            action: #selector(setGlobalPauseOneHour),
            keyEquivalent: ""
        )
        oneHourItem.target = self
        oneHourItem.state = preferences.pauseDuration == .oneHour ? .on : .off
        menu.addItem(oneHourItem)

        // Pause for 24 Hours
        let twentyFourHoursItem = NSMenuItem(
            title: "Paused for 24 Hours",
            action: #selector(setGlobalPauseTwentyFourHours),
            keyEquivalent: ""
        )
        twentyFourHoursItem.target = self
        twentyFourHoursItem.state = preferences.pauseDuration == .twentyFourHours ? .on : .off
        menu.addItem(twentyFourHoursItem)

        // Pause Indefinitely
        let indefiniteItem = NSMenuItem(
            title: "Paused Until Resumed",
            action: #selector(setGlobalPauseIndefinite),
            keyEquivalent: ""
        )
        indefiniteItem.target = self
        indefiniteItem.state = preferences.pauseDuration == .indefinite ? .on : .off
        menu.addItem(indefiniteItem)

        // Show resume time if paused with duration
        if (preferences.pauseDuration == .oneHour || preferences.pauseDuration == .twentyFourHours),
           let until = preferences.pausedUntil {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeString = formatter.string(from: until)
            let resumeItem = NSMenuItem(title: "  Will resume at \(timeString)", action: nil, keyEquivalent: "")
            resumeItem.isEnabled = false
            menu.addItem(resumeItem)
        }
    }

    /// Add app-specific pause menu items
    private func addAppSpecificPauseItems(to menu: NSMenu, context: ApplicationContext) {
        let preferences = UserPreferences.shared
        let bundleID = context.bundleIdentifier
        let appName = context.applicationName

        // Header with app name
        let headerItem = NSMenuItem(title: "\(appName):", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let currentPause = preferences.getPauseDuration(for: bundleID)

        // Active for this app
        let activeItem = NSMenuItem(
            title: "Active",
            action: #selector(setAppPauseActive(_:)),
            keyEquivalent: ""
        )
        activeItem.target = self
        activeItem.representedObject = bundleID
        activeItem.state = currentPause == .active ? .on : .off
        menu.addItem(activeItem)

        // Pause for 1 Hour for this app
        let oneHourItem = NSMenuItem(
            title: "Paused for 1 Hour",
            action: #selector(setAppPauseOneHour(_:)),
            keyEquivalent: ""
        )
        oneHourItem.target = self
        oneHourItem.representedObject = bundleID
        oneHourItem.state = currentPause == .oneHour ? .on : .off
        menu.addItem(oneHourItem)

        // Pause for 24 Hours for this app
        let twentyFourHoursItem = NSMenuItem(
            title: "Paused for 24 Hours",
            action: #selector(setAppPauseTwentyFourHours(_:)),
            keyEquivalent: ""
        )
        twentyFourHoursItem.target = self
        twentyFourHoursItem.representedObject = bundleID
        twentyFourHoursItem.state = currentPause == .twentyFourHours ? .on : .off
        menu.addItem(twentyFourHoursItem)

        // Pause Indefinitely for this app
        let indefiniteItem = NSMenuItem(
            title: "Paused Until Resumed",
            action: #selector(setAppPauseIndefinite(_:)),
            keyEquivalent: ""
        )
        indefiniteItem.target = self
        indefiniteItem.representedObject = bundleID
        indefiniteItem.state = currentPause == .indefinite ? .on : .off
        menu.addItem(indefiniteItem)

        // Show resume time if paused with duration for this app
        if (currentPause == .oneHour || currentPause == .twentyFourHours),
           let until = preferences.getPausedUntil(for: bundleID) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeString = formatter.string(from: until)
            let resumeItem = NSMenuItem(title: "  Will resume at \(timeString)", action: nil, keyEquivalent: "")
            resumeItem.isEnabled = false
            menu.addItem(resumeItem)
        }
    }

    // MARK: - Global Pause Actions

    @objc private func setGlobalPauseActive() {
        UserPreferences.shared.pauseDuration = .active
        MenuBarController.shared?.setIconState(.active)
        // Trigger re-analysis to show errors immediately
        AnalysisCoordinator.shared.triggerReanalysis()
        Logger.debug("FloatingErrorIndicator: Grammar checking enabled globally", category: Logger.ui)
    }

    @objc private func setGlobalPauseOneHour() {
        setGlobalPause(.oneHour)
    }

    @objc private func setGlobalPauseTwentyFourHours() {
        setGlobalPause(.twentyFourHours)
    }

    @objc private func setGlobalPauseIndefinite() {
        setGlobalPause(.indefinite)
    }

    private func setGlobalPause(_ duration: PauseDuration) {
        UserPreferences.shared.pauseDuration = duration
        MenuBarController.shared?.setIconState(.inactive)
        // Hide all overlays immediately
        hide()
        SuggestionPopover.shared.hide()
        AnalysisCoordinator.shared.hideAllOverlays()
        Logger.debug("FloatingErrorIndicator: Grammar checking paused globally (\(duration.rawValue))", category: Logger.ui)
    }

    // MARK: - App-Specific Pause Actions

    @objc private func setAppPauseActive(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserPreferences.shared.setPauseDuration(for: bundleID, duration: .active)
        // Trigger re-analysis to show errors immediately
        AnalysisCoordinator.shared.triggerReanalysis()
        Logger.debug("FloatingErrorIndicator: Grammar checking enabled for \(bundleID)", category: Logger.ui)
    }

    @objc private func setAppPauseOneHour(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        setAppPause(for: bundleID, duration: .oneHour)
    }

    @objc private func setAppPauseTwentyFourHours(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        setAppPause(for: bundleID, duration: .twentyFourHours)
    }

    @objc private func setAppPauseIndefinite(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        setAppPause(for: bundleID, duration: .indefinite)
    }

    private func setAppPause(for bundleID: String, duration: PauseDuration) {
        UserPreferences.shared.setPauseDuration(for: bundleID, duration: duration)
        // Hide all overlays immediately for this app
        hide()
        SuggestionPopover.shared.hide()
        AnalysisCoordinator.shared.hideAllOverlays()
        Logger.debug("FloatingErrorIndicator: Grammar checking paused for \(bundleID) (\(duration.rawValue))", category: Logger.ui)
    }

    // MARK: - Preferences Action

    @objc private func openPreferences() {
        Logger.debug("FloatingErrorIndicator: openPreferences", category: Logger.ui)

        // Switch to regular mode temporarily
        NSApp.setActivationPolicy(.regular)

        // Use NSApp.sendAction to open settings
        NSApp.sendAction(#selector(AppDelegate.openSettingsWindow(selectedTab:)), to: nil, from: self)
    }
}

/// Display mode for the indicator view
enum IndicatorDisplayMode {
    case count(Int)
    case sparkle
    case sparkleWithCount(Int)
    case spinning
    case styleCheckComplete  // Checkmark to show style check finished successfully
}

/// Custom view for drawing the circular indicator
private class IndicatorView: NSView {

    // MARK: - Properties

    var displayMode: IndicatorDisplayMode = .count(0) {
        didSet {
            updateSpinningAnimation()
            needsDisplay = true
        }
    }
    var ringColor: NSColor = .systemRed
    var onClicked: (() -> Void)?
    var onRightClicked: ((NSEvent) -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?

    private var hoverTimer: Timer?
    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var isHovered = false
    private var spinningTimer: Timer?
    private var spinningAngle: CGFloat = 0
    private var themeObserver: Any?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)

        // Observe overlay theme changes to redraw
        themeObserver = UserPreferences.shared.$overlayTheme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        spinningTimer?.invalidate()
        hoverTimer?.invalidate()
        themeObserver = nil
    }

    // MARK: - Animation

    /// Start or stop spinning animation based on display mode
    private func updateSpinningAnimation() {
        switch displayMode {
        case .spinning:
            startSpinning()
        default:
            stopSpinning()
        }
    }

    private func startSpinning() {
        guard spinningTimer == nil else { return }
        spinningTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.animationFrameInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.spinningAngle -= 0.08  // Clockwise rotation (negative = clockwise in flipped coords)
            if self.spinningAngle <= -.pi * 2 {
                self.spinningAngle = 0
            }
            self.needsDisplay = true
        }
    }

    private func stopSpinning() {
        spinningTimer?.invalidate()
        spinningTimer = nil
        spinningAngle = 0
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Determine if dark mode based on overlay theme preference
        // Note: For "System" mode, we check the actual macOS system setting (not NSApp.effectiveAppearance)
        // because the app may have its own theme override via NSApp.appearance
        let isDarkMode: Bool = {
            switch UserPreferences.shared.overlayTheme {
            case "Light":
                return false
            case "Dark":
                return true
            default: // "System"
                // Query actual macOS system dark mode setting
                return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            }
        }()

        // MARK: - Define background circle (inset to leave room for ring stroke)
        let backgroundRect = bounds.insetBy(dx: 5, dy: 5)
        let backgroundPath = NSBezierPath(ovalIn: backgroundRect)

        // MARK: - Draw Drop Shadow (outside the ring only)
        // Use a slightly larger circle for shadow to ensure it appears behind the ring
        NSGraphicsContext.saveGraphicsState()

        let shadowColor = NSColor.black.withAlphaComponent(isDarkMode ? 0.35 : 0.2)
        let shadow = NSShadow()
        shadow.shadowColor = shadowColor
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 3  // Reduced to keep shadow within bounds
        shadow.set()

        // Draw shadow from a clear fill (shadow only, no visible fill)
        // This ensures shadow appears outside the circle without adding any background
        NSColor.clear.setFill()
        backgroundPath.fill()

        NSGraphicsContext.restoreGraphicsState()

        // MARK: - Glass Background (clipped to circle)
        NSGraphicsContext.saveGraphicsState()
        backgroundPath.addClip()

        // Base glass color - solid fill first
        let glassBaseColor = isDarkMode
            ? NSColor(white: 0.18, alpha: 1.0)
            : NSColor(white: 0.96, alpha: 1.0)
        glassBaseColor.setFill()
        NSBezierPath.fill(backgroundRect)

        // Inner highlight gradient (top to center, clipped to circle)
        let highlightGradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(isDarkMode ? 0.1 : 0.3),
            NSColor.white.withAlphaComponent(0.0)
        ])
        highlightGradient?.draw(in: backgroundRect, angle: 90)

        NSGraphicsContext.restoreGraphicsState()

        // MARK: - Colored Ring (drawn on top of glass background)
        switch displayMode {
        case .spinning:
            drawSpinningRing()
        default:
            let ringPath = NSBezierPath(ovalIn: backgroundRect)
            ringColor.setStroke()
            ringPath.lineWidth = 2.5
            ringPath.stroke()

            // Subtle inner glow on the ring
            let innerGlowPath = NSBezierPath(ovalIn: backgroundRect.insetBy(dx: 1.25, dy: 1.25))
            ringColor.withAlphaComponent(0.25).setStroke()
            innerGlowPath.lineWidth = 0.75
            innerGlowPath.stroke()
        }

        // MARK: - Subtle Border (glass edge, inside the ring)
        let borderPath = NSBezierPath(ovalIn: backgroundRect.insetBy(dx: 1.25, dy: 1.25))
        let borderColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.1)
            : NSColor.black.withAlphaComponent(0.06)
        borderColor.setStroke()
        borderPath.lineWidth = 0.5
        borderPath.stroke()

        // Draw content based on display mode
        switch displayMode {
        case .count(let count):
            drawErrorCount(count)
        case .sparkle:
            drawSparkleIcon()
        case .sparkleWithCount(let count):
            drawSparkleWithCount(count)
        case .spinning:
            drawSparkleIcon()
        case .styleCheckComplete:
            drawCheckmarkIcon()
        }
    }

    /// Draw spinning ring for style check loading state (Liquid Glass style)
    private func drawSpinningRing() {
        let backgroundRect = bounds.insetBy(dx: 5, dy: 5)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = backgroundRect.width / 2

        // Draw background ring (dimmed, glass-like)
        let backgroundRing = NSBezierPath()
        backgroundRing.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        ringColor.withAlphaComponent(0.15).setStroke()
        backgroundRing.lineWidth = 2.5
        backgroundRing.stroke()

        // Draw animated arc (spinning)
        let arcLength: CGFloat = 90  // 90 degree arc
        let startAngleDegrees = spinningAngle * 180 / .pi
        let endAngleDegrees = startAngleDegrees + arcLength

        // Main spinning arc
        let spinningArc = NSBezierPath()
        spinningArc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngleDegrees,
            endAngle: endAngleDegrees,
            clockwise: false
        )
        ringColor.setStroke()
        spinningArc.lineWidth = 2.5
        spinningArc.lineCapStyle = .round
        spinningArc.stroke()

        // Subtle inner glow on spinning arc
        let glowArc = NSBezierPath()
        glowArc.appendArc(
            withCenter: center,
            radius: radius - 1.25,
            startAngle: startAngleDegrees,
            endAngle: endAngleDegrees,
            clockwise: false
        )
        ringColor.withAlphaComponent(0.3).setStroke()
        glowArc.lineWidth = 0.75
        glowArc.lineCapStyle = .round
        glowArc.stroke()
    }

    /// Draw sparkle icon with count badge
    private func drawSparkleWithCount(_ count: Int) {
        // Draw sparkle icon (smaller to make room for count)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let sparkleImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Style Suggestions")?
            .withSymbolConfiguration(symbolConfig) {

            let tintedImage = NSImage(size: sparkleImage.size, flipped: false) { rect in
                sparkleImage.draw(in: rect)
                NSColor.purple.set()
                rect.fill(using: .sourceAtop)
                return true
            }

            let imageSize = tintedImage.size
            let x = (bounds.width - imageSize.width) / 2 - 4
            let y = (bounds.height - imageSize.height) / 2 + 3

            tintedImage.draw(
                in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }

        // Draw count in bottom-right corner (capped at 9+ for cleaner UX)
        let countString = count > 9 ? "9+" : "\(count)"
        let fontSize: CGFloat = count > 9 ? 9 : 11
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.purple
        ]
        let textSize = (countString as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: bounds.width - textSize.width - 6,
            y: 4,
            width: textSize.width,
            height: textSize.height
        )
        (countString as NSString).draw(in: textRect, withAttributes: attributes)
    }

    /// Draw error count text
    private func drawErrorCount(_ count: Int) {
        // Determine text color based on overlay theme (not app theme)
        // Note: For "System" mode, we check the actual macOS system setting
        // because the app may have its own theme override via NSApp.appearance
        let textColor: NSColor = {
            switch UserPreferences.shared.overlayTheme {
            case "Light":
                return NSColor.black
            case "Dark":
                return NSColor.white
            default: // "System"
                // Query actual macOS system dark mode setting
                let systemIsDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
                return systemIsDark ? NSColor.white : NSColor.black
            }
        }()

        // Cap display at 9+ for cleaner UX (avoids double/triple digit numbers)
        let countString = count > 9 ? "9+" : "\(count)"
        // Use slightly smaller font for "9+" to fit nicely
        let fontSize: CGFloat = count > 9 ? 12 : 14
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: textColor
        ]
        let textSize = (countString as NSString).size(withAttributes: attributes)

        // Position text precisely centered (no offset)
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (countString as NSString).draw(in: textRect, withAttributes: attributes)
    }

    /// Draw sparkle icon for style suggestions
    private func drawSparkleIcon() {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        guard let sparkleImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Style Suggestions")?
            .withSymbolConfiguration(symbolConfig) else {
            // Fallback to text if symbol not available
            drawFallbackSparkle()
            return
        }

        // Tint the image purple
        let tintedImage = NSImage(size: sparkleImage.size, flipped: false) { rect in
            sparkleImage.draw(in: rect)
            NSColor.purple.set()
            rect.fill(using: .sourceAtop)
            return true
        }

        // Center the image precisely
        let imageSize = tintedImage.size
        let x = (bounds.width - imageSize.width) / 2
        let y = (bounds.height - imageSize.height) / 2

        tintedImage.draw(
            in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    /// Fallback sparkle drawing if SF Symbol not available
    private func drawFallbackSparkle() {
        let sparkleString = "✨"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.purple
        ]
        let textSize = (sparkleString as NSString).size(withAttributes: attributes)

        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (sparkleString as NSString).draw(in: textRect, withAttributes: attributes)
    }

    /// Draw checkmark icon to indicate style check completed successfully
    private func drawCheckmarkIcon() {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard let checkmarkImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Style Check Complete")?
            .withSymbolConfiguration(symbolConfig) else {
            // Fallback to text if symbol not available
            let checkString = "✓"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.purple
            ]
            let textSize = (checkString as NSString).size(withAttributes: attributes)
            let textRect = NSRect(
                x: (bounds.width - textSize.width) / 2,
                y: (bounds.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (checkString as NSString).draw(in: textRect, withAttributes: attributes)
            return
        }

        // Tint the image purple
        let tintedImage = NSImage(size: checkmarkImage.size, flipped: false) { rect in
            checkmarkImage.draw(in: rect)
            NSColor.purple.set()
            rect.fill(using: .sourceAtop)
            return true
        }

        // Center the image precisely
        let imageSize = tintedImage.size
        let x = (bounds.width - imageSize.width) / 2
        let y = (bounds.height - imageSize.height) / 2

        tintedImage.draw(
            in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        Logger.debug("IndicatorView: mouseDown called at \(event.locationInWindow)", category: Logger.ui)

        // Just record start point - don't start drag yet
        // Drag will start on first mouseDragged event
        dragStartPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }

        // Start drag on first mouseDragged event (not on mouseDown)
        // This prevents showing border guide on simple clicks
        if !isDragging {
            isDragging = true

            // Change cursor to closed hand
            NSCursor.closedHand.push()

            // Notify drag start (shows border guide)
            onDragStart?()

            // Redraw to show dots instead of count
            needsDisplay = true
        }

        // Calculate delta from start point
        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - dragStartPoint.x
        let deltaY = currentPoint.y - dragStartPoint.y

        // Move window
        var newOrigin = window.frame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY

        window.setFrameOrigin(newOrigin)

        // Ensure window stays visible and in front during drag
        window.orderFrontRegardless()
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            // No drag happened - treat as a click
            onClicked?()
            return
        }

        isDragging = false
        NSCursor.pop()

        if let window = window {
            onDragEnd?(window.frame.origin)
        }

        // Redraw to show count instead of dots
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        Logger.debug("IndicatorView: rightMouseDown", category: Logger.ui)
        onRightClicked?(event)
    }

    override func mouseEntered(with event: NSEvent) {
        Logger.debug("IndicatorView: mouseEntered", category: Logger.ui)
        isHovered = true

        // Use open hand cursor to indicate draggability
        if !isDragging {
            NSCursor.openHand.push()
        }

        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.hoverDelay, repeats: false) { [weak self] _ in
            self?.onHover?(true)
        }

        // Redraw to update dot opacity
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        Logger.debug("IndicatorView: mouseExited", category: Logger.ui)
        isHovered = false

        if !isDragging {
            NSCursor.pop()
        }

        // Cancel hover timer if mouse exits before delay
        hoverTimer?.invalidate()
        hoverTimer = nil

        onHover?(false)

        // Redraw to update dot opacity
        needsDisplay = true
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}
