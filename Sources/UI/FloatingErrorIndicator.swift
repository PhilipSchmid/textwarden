//
//  FloatingErrorIndicator.swift
//  TextWarden
//
//  Floating error indicator
//  Shows a small circular badge in the bottom-right corner of text fields
//
//  Related files:
//  - Indicator/IndicatorTypes.swift - Enums and type definitions
//  - Indicator/CapsuleStateManager.swift - State management for capsule sections
//

import Cocoa
import AppKit
import Combine

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

    /// Custom view for drawing the circular indicator (grammar-only mode)
    private var indicatorView: IndicatorView?

    /// Custom view for drawing the capsule indicator (grammar + style mode)
    private var capsuleIndicatorView: CapsuleIndicatorView?

    /// State manager for capsule indicator sections
    private let capsuleStateManager = CapsuleStateManager()

    /// Current indicator shape
    private var currentShape: IndicatorShape = .circle

    /// Border guide window for drag feedback
    private let borderGuide = BorderGuideWindow()

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Callback to request style analysis from AnalysisCoordinator
    var onRequestStyleCheck: (() -> Void)?

    // MARK: - Initialization

    private init() {
        let size = UIConstants.indicatorSize
        let initialFrame = NSRect(x: 0, y: 0, width: size, height: size)

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

        // Observe global pause state changes to hide indicator when globally paused
        UserPreferences.shared.$pauseDuration
            .dropFirst()  // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDuration in
                guard let self = self else { return }

                if newDuration == .indefinite {
                    Logger.debug("FloatingErrorIndicator: Global pause set to indefinite - hiding indicator", category: Logger.ui)
                    self.hide()
                    SuggestionPopover.shared.hide()
                }
            }
            .store(in: &cancellables)

        // Observe style checking preference changes to switch indicator shape
        UserPreferences.shared.$enableStyleChecking
            .dropFirst()  // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enableStyleChecking in
                guard let self = self else { return }

                let newShape: IndicatorShape = enableStyleChecking ? .capsule : .circle
                if newShape != self.currentShape {
                    Logger.debug("FloatingErrorIndicator: Style checking changed to \(enableStyleChecking) - transitioning to \(newShape)", category: Logger.ui)
                    self.transitionToShape(newShape)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Shape Transition

    /// Transition to the specified indicator shape
    private func transitionToShape(_ shape: IndicatorShape) {
        guard shape != currentShape else { return }

        Logger.debug("FloatingErrorIndicator: Transitioning from \(currentShape) to \(shape)", category: Logger.ui)

        // Hide popover during transition
        SuggestionPopover.shared.hide()

        // Remove current view
        indicatorView?.removeFromSuperview()
        capsuleIndicatorView?.removeFromSuperview()

        currentShape = shape

        // Create and setup new view
        switch shape {
        case .circle:
            setupCircularIndicator()
        case .capsule:
            setupCapsuleIndicator()
        }

        // Resize window for new shape
        resizeWindowForCurrentShape()

        // Reposition if visible
        if isVisible, let element = monitoredElement {
            positionIndicator(for: element)
        }
    }

    /// Setup the circular indicator view
    private func setupCircularIndicator() {
        let size = UIConstants.indicatorSize
        let frame = NSRect(x: 0, y: 0, width: size, height: size)

        let view = IndicatorView(frame: frame)
        view.onClicked = { [weak self] in
            self?.togglePopover()
        }
        view.onHover = { [weak self] isHovering in
            guard UserPreferences.shared.enableHoverPopover else { return }
            if isHovering {
                self?.showErrors()
            } else {
                SuggestionPopover.shared.scheduleHide()
            }
        }
        view.onDragStart = { [weak self] in
            self?.handleDragStart()
        }
        view.onDragEnd = { [weak self] finalPosition in
            self?.handleDragEndWithPosition(finalPosition)
        }
        view.onRightClicked = { [weak self] event in
            self?.showContextMenu(with: event)
        }

        self.indicatorView = view
        self.contentView = view
        self.capsuleIndicatorView = nil
    }

    /// Setup the capsule indicator view
    private func setupCapsuleIndicator() {
        let width = capsuleStateManager.capsuleWidth
        let height = capsuleStateManager.capsuleHeight

        let frame = NSRect(x: 0, y: 0, width: width, height: height)

        let view = CapsuleIndicatorView(frame: frame)
        view.orientation = capsuleStateManager.capsuleOrientation
        view.onSectionClicked = { [weak self] sectionType in
            self?.handleSectionClicked(sectionType)
        }
        view.onHover = { [weak self] sectionType in
            guard UserPreferences.shared.enableHoverPopover else { return }
            if let section = sectionType {
                self?.showSectionPopover(section)
            } else {
                // Hide both popovers when hover ends
                SuggestionPopover.shared.scheduleHide()
                TextGenerationPopover.shared.scheduleHide()
            }
        }
        view.onDragStart = { [weak self] in
            self?.handleDragStart()
        }
        view.onDragMove = { [weak self] currentPosition in
            self?.handleDragMove(at: currentPosition)
        }
        view.onDragEnd = { [weak self] finalPosition in
            self?.handleDragEndWithPosition(finalPosition)
        }
        view.onRightClicked = { [weak self] event in
            self?.showContextMenu(with: event)
        }

        // Set initial sections
        updateCapsuleSections()
        view.sections = capsuleStateManager.visibleSections

        self.capsuleIndicatorView = view
        self.contentView = view
        self.indicatorView = nil
    }

    /// Resize the window for the current shape
    private func resizeWindowForCurrentShape() {
        let newSize: NSSize
        switch currentShape {
        case .circle:
            newSize = NSSize(width: UIConstants.indicatorSize, height: UIConstants.indicatorSize)
        case .capsule:
            let width = capsuleStateManager.capsuleWidth
            let height = capsuleStateManager.capsuleHeight
            newSize = NSSize(width: width, height: height)
            // Update orientation on the view
            capsuleIndicatorView?.orientation = capsuleStateManager.capsuleOrientation
        }

        var newFrame = frame
        newFrame.size = newSize
        setFrame(newFrame, display: true)
    }

    /// Handle drag start (shared between circular and capsule)
    private func handleDragStart() {
        Logger.debug("onDragStart triggered!", category: Logger.ui)

        SuggestionPopover.shared.hide()

        // Enlarge indicator to show it's being dragged
        // Use the VIEW's current orientation, not preference-based dimensions
        let currentFrame = self.frame
        let normalWidth: CGFloat
        let normalHeight: CGFloat

        if currentShape == .circle {
            normalWidth = UIConstants.indicatorSize
            normalHeight = UIConstants.indicatorSize
        } else if let viewOrientation = capsuleIndicatorView?.orientation {
            let sectionCount = CGFloat(max(capsuleStateManager.visibleSections.count, 1))
            switch viewOrientation {
            case .vertical:
                normalWidth = UIConstants.capsuleWidth
                normalHeight = sectionCount * UIConstants.capsuleSectionHeight
            case .horizontal:
                normalWidth = sectionCount * UIConstants.capsuleSectionHeight
                normalHeight = UIConstants.capsuleSectionHeight
            }
        } else {
            normalWidth = UIConstants.indicatorSize
            normalHeight = UIConstants.indicatorSize
        }

        let enlargeAmount: CGFloat = 5.0  // Enlarge by 5pt in each dimension

        // Adjust origin to keep indicator centered while enlarging
        let newFrame = NSRect(
            x: currentFrame.origin.x - enlargeAmount / 2,
            y: currentFrame.origin.y - enlargeAmount / 2,
            width: normalWidth + enlargeAmount,
            height: normalHeight + enlargeAmount
        )
        self.setFrame(newFrame, display: true)

        self.alphaValue = 0.85
        self.orderFrontRegardless()
        self.level = .popUpMenu + 2

        if let element = self.monitoredElement,
           let windowFrame = self.getVisibleWindowFrame(for: element) {
            self.borderGuide.showBorder(around: windowFrame)
        }
    }

    /// Handle drag movement - orientation is determined at drag end, not during drag
    /// This avoids visual glitches from orientation/size mismatches during movement
    private func handleDragMove(at currentPosition: CGPoint) {
        // Intentionally empty - orientation change happens at drag end in handleDragEnd
        // This callback exists for future use if needed (e.g., edge proximity feedback)
    }

    /// Handle drag end (shared between circular and capsule)
    private func handleDragEndWithPosition(_ finalPosition: CGPoint) {
        // Restore visual state
        self.alphaValue = 1.0
        self.level = .popUpMenu + 1
        self.borderGuide.hide()

        // Use the drop position directly (finalPosition is the frame origin during drag)
        // This preserves the edge position where the user dropped the indicator
        let dropX = finalPosition.x
        let dropY = finalPosition.y

        // For capsules, determine final orientation FIRST based on drop position relative to monitored window
        if currentShape == .capsule,
           let element = monitoredElement,
           let windowFrame = getVisibleWindowFrame(for: element) {
            // Use center of current frame for orientation calculation
            let centerX = dropX + frame.width / 2
            let centerY = dropY + frame.height / 2
            let xPercent = (centerX - windowFrame.minX) / windowFrame.width
            let yPercent = (centerY - windowFrame.minY) / windowFrame.height
            let percentPos = IndicatorPositionStore.PercentagePosition(xPercent: xPercent, yPercent: yPercent)
            let targetOrientation = CapsuleStateManager.orientationFromPercentagePosition(percentPos)

            Logger.debug("FloatingErrorIndicator: Drop position x=\(xPercent), y=\(yPercent) → orientation=\(targetOrientation)", category: Logger.ui)

            // Update orientation on view BEFORE calculating dimensions
            capsuleIndicatorView?.orientation = targetOrientation
        }

        // Now calculate dimensions based on the FINAL orientation
        let normalWidth: CGFloat
        let normalHeight: CGFloat

        if currentShape == .circle {
            normalWidth = UIConstants.indicatorSize
            normalHeight = UIConstants.indicatorSize
        } else if let viewOrientation = capsuleIndicatorView?.orientation {
            let sectionCount = CGFloat(max(capsuleStateManager.visibleSections.count, 1))
            switch viewOrientation {
            case .vertical:
                normalWidth = UIConstants.capsuleWidth
                normalHeight = sectionCount * UIConstants.capsuleSectionHeight
            case .horizontal:
                normalWidth = sectionCount * UIConstants.capsuleSectionHeight
                normalHeight = UIConstants.capsuleSectionHeight
            }
        } else {
            normalWidth = UIConstants.indicatorSize
            normalHeight = UIConstants.indicatorSize
        }

        // Calculate size delta from enlarged drag frame to normal size
        let sizeDeltaX = frame.width - normalWidth
        let sizeDeltaY = frame.height - normalHeight

        // Position frame at drop location, adjusting for size change to keep center stable
        let newFrame = NSRect(
            x: dropX + sizeDeltaX / 2,
            y: dropY + sizeDeltaY / 2,
            width: normalWidth,
            height: normalHeight
        )
        self.setFrame(newFrame, display: true)

        // Handle snap positioning and save (no more orientation changes here)
        self.handleDragEnd(at: newFrame.origin)
    }

    /// Update capsule sections based on current errors and style suggestions
    private func updateCapsuleSections() {
        capsuleStateManager.updateGrammar(errors: errors)
        capsuleStateManager.updateStyle(suggestions: styleSuggestions, isLoading: false)
        capsuleStateManager.updateTextGeneration(isGenerating: false)
    }

    /// Handle section click in capsule mode
    private func handleSectionClicked(_ sectionType: CapsuleSectionType) {
        Logger.debug("FloatingErrorIndicator: Section clicked: \(sectionType)", category: Logger.ui)

        switch sectionType {
        case .grammar:
            showGrammarPopover()
        case .style:
            showStylePopover()
        case .textGeneration:
            showTextGenerationPopover()
        }
    }

    /// Show popover for specific section
    private func showSectionPopover(_ sectionType: CapsuleSectionType) {
        switch sectionType {
        case .grammar:
            showGrammarPopover()
        case .style:
            showStylePopover()
        case .textGeneration:
            showTextGenerationPopover()
        }
    }

    /// Show grammar-only popover
    private func showGrammarPopover() {
        Logger.debug("FloatingErrorIndicator: showGrammarPopover - errors=\(errors.count)", category: Logger.ui)

        // Close other popovers first
        TextGenerationPopover.shared.hide()

        let indicatorFrame = frame
        let anchor = calculatePopoverAnchor(for: indicatorFrame)
        let windowFrame: CGRect? = monitoredElement.flatMap { getVisibleWindowFrame(for: $0) }

        SuggestionPopover.shared.showUnified(
            errors: errors,
            styleSuggestions: [],  // Grammar only
            at: anchor.anchorPoint,
            openDirection: anchor.edge,
            constrainToWindow: windowFrame,
            sourceText: sourceText
        )
    }

    /// Show style-only popover, or trigger style check if no suggestions yet
    private func showStylePopover() {
        Logger.debug("FloatingErrorIndicator: showStylePopover - styleSuggestions=\(styleSuggestions.count)", category: Logger.ui)

        // Close other popovers first
        TextGenerationPopover.shared.hide()

        // If no style suggestions yet and not currently loading, trigger a style check
        if styleSuggestions.isEmpty && capsuleStateManager.styleState.displayState != .styleLoading {
            Logger.debug("FloatingErrorIndicator: No style suggestions, requesting style check", category: Logger.ui)
            setStyleLoading(true)
            onRequestStyleCheck?()
            return
        }

        // Show popover with existing suggestions (or empty if still loading)
        let indicatorFrame = frame
        let anchor = calculatePopoverAnchor(for: indicatorFrame)
        let windowFrame: CGRect? = monitoredElement.flatMap { getVisibleWindowFrame(for: $0) }

        SuggestionPopover.shared.showUnified(
            errors: [],  // Style only
            styleSuggestions: styleSuggestions,
            at: anchor.anchorPoint,
            openDirection: anchor.edge,
            constrainToWindow: windowFrame,
            sourceText: sourceText
        )
    }

    /// Set style section loading state
    func setStyleLoading(_ loading: Bool) {
        Logger.debug("FloatingErrorIndicator: setStyleLoading(\(loading)), capsuleIndicatorView=\(capsuleIndicatorView != nil)", category: Logger.ui)
        if loading {
            capsuleStateManager.styleState.displayState = .styleLoading
            capsuleStateManager.styleState.ringColor = .purple
        } else if styleSuggestions.isEmpty {
            capsuleStateManager.styleState.displayState = .styleIdle
            capsuleStateManager.styleState.ringColor = .purple
        } else {
            capsuleStateManager.styleState.displayState = .styleCount(styleSuggestions.count)
            capsuleStateManager.styleState.ringColor = .purple
        }
        let visibleSections = capsuleStateManager.visibleSections
        Logger.debug("FloatingErrorIndicator: Updating capsule with \(visibleSections.count) sections, styleState=\(capsuleStateManager.styleState.displayState)", category: Logger.ui)
        capsuleIndicatorView?.sections = visibleSections
        capsuleIndicatorView?.needsDisplay = true
    }

    /// Callback to get generation context from AnalysisCoordinator
    var onRequestGenerationContext: (() -> GenerationContext)?

    /// Show text generation popover
    private func showTextGenerationPopover() {
        Logger.debug("FloatingErrorIndicator: Showing text generation popover", category: Logger.ui)

        // Close other popovers first
        SuggestionPopover.shared.hide()

        // Get context from AnalysisCoordinator
        let context = onRequestGenerationContext?() ?? .empty

        // Calculate popover position (same logic as grammar/style popovers)
        let indicatorFrame = frame
        let anchor = calculatePopoverAnchor(for: indicatorFrame)

        // Show the popover with explicit direction
        TextGenerationPopover.shared.show(at: anchor.anchorPoint, direction: anchor.edge, context: context)
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

        // Skip showing indicator when globally paused indefinitely
        if UserPreferences.shared.pauseDuration == .indefinite {
            Logger.debug("FloatingErrorIndicator: Skipping - globally paused indefinitely", category: Logger.ui)
            return
        }

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

        // Determine expected shape based on style checking preference
        let styleCheckingEnabled = UserPreferences.shared.enableStyleChecking
        let alwaysShowIndicator = UserPreferences.shared.alwaysShowCapsule
        let expectedShape: IndicatorShape = styleCheckingEnabled ? .capsule : .circle

        // Hide indicator only if:
        // - Mode is empty (no errors/suggestions) AND
        // - Always show indicator is off
        // When alwaysShowIndicator is on, show indicator with success state (green checkmark)
        guard !mode.isEmpty || alwaysShowIndicator else {
            Logger.debug("FloatingErrorIndicator: No errors or suggestions, hiding", category: Logger.ui)
            hide()
            return
        }

        // Ensure correct shape is active
        if currentShape != expectedShape {
            transitionToShape(expectedShape)
        }

        // Configure indicator view based on mode and shape
        if currentShape == .capsule {
            // Capsule mode - update sections
            updateCapsuleSections()
            capsuleIndicatorView?.sections = capsuleStateManager.visibleSections
            capsuleIndicatorView?.needsDisplay = true
        } else {
            // Circular mode
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
        }

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

        // Skip showing indicator when globally paused indefinitely
        if UserPreferences.shared.pauseDuration == .indefinite {
            Logger.debug("FloatingErrorIndicator: Skipping - globally paused indefinitely", category: Logger.ui)
            return
        }

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

        // Calculate dimensions based on shape and ACTUAL position-based orientation
        let indicatorWidth: CGFloat
        let indicatorHeight: CGFloat

        if currentShape == .capsule {
            // Determine orientation from actual stored/resolved position
            let orientation = CapsuleStateManager.orientationFromPercentagePosition(resolvedPosition)
            capsuleIndicatorView?.orientation = orientation

            let sectionCount = CGFloat(max(capsuleStateManager.visibleSections.count, 1))
            switch orientation {
            case .vertical:
                indicatorWidth = UIConstants.capsuleWidth
                indicatorHeight = sectionCount * UIConstants.capsuleSectionHeight
            case .horizontal:
                indicatorWidth = sectionCount * UIConstants.capsuleSectionHeight
                indicatorHeight = UIConstants.capsuleSectionHeight
            }
        } else {
            indicatorWidth = UIConstants.indicatorSize
            indicatorHeight = UIConstants.indicatorSize
        }

        // Convert percentage to absolute position (use width for X, height for Y)
        let position = resolvedPosition.toAbsolute(in: visibleFrame, width: indicatorWidth, height: indicatorHeight)
        let finalFrame = NSRect(x: position.x, y: position.y, width: indicatorWidth, height: indicatorHeight)

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

        // Skip showing indicator when globally paused indefinitely
        if UserPreferences.shared.pauseDuration == .indefinite {
            Logger.debug("FloatingErrorIndicator: Skipping - globally paused indefinitely", category: Logger.ui)
            return
        }

        self.monitoredElement = element
        self.context = context

        // Ensure correct shape is active
        let expectedShape: IndicatorShape = UserPreferences.shared.enableStyleChecking ? .capsule : .circle
        if currentShape != expectedShape {
            transitionToShape(expectedShape)
        }

        if currentShape == .capsule {
            // Capsule mode - update style section to show loading
            capsuleStateManager.updateStyle(suggestions: [], isLoading: true)
            capsuleStateManager.updateTextGeneration(isGenerating: false)
            capsuleIndicatorView?.sections = capsuleStateManager.visibleSections
            capsuleIndicatorView?.needsDisplay = true
        } else {
            // Circular mode - show spinning indicator
            indicatorView?.displayMode = .spinning
            indicatorView?.ringColor = .purple
            indicatorView?.needsDisplay = true
        }

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

        // Update capsule state to clear loading indicator
        if currentShape == .capsule {
            setStyleLoading(false)
        }

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

        // Calculate actual indicator dimensions based on shape and orientation
        let indicatorWidth: CGFloat
        let indicatorHeight: CGFloat

        if currentShape == .circle {
            indicatorWidth = UIConstants.indicatorSize
            indicatorHeight = UIConstants.indicatorSize
        } else if let viewOrientation = capsuleIndicatorView?.orientation {
            let sectionCount = CGFloat(max(capsuleStateManager.visibleSections.count, 1))
            switch viewOrientation {
            case .vertical:
                indicatorWidth = UIConstants.capsuleWidth
                indicatorHeight = sectionCount * UIConstants.capsuleSectionHeight
            case .horizontal:
                indicatorWidth = sectionCount * UIConstants.capsuleSectionHeight
                indicatorHeight = UIConstants.capsuleSectionHeight
            }
        } else {
            indicatorWidth = UIConstants.indicatorSize
            indicatorHeight = UIConstants.indicatorSize
        }

        // Snap position to valid border area
        let snappedPosition = snapToBorderArea(
            position: finalPosition,
            windowFrame: windowFrame,
            indicatorWidth: indicatorWidth,
            indicatorHeight: indicatorHeight
        )

        // Convert absolute position to percentage (use width for X, height for Y)
        let percentagePos = IndicatorPositionStore.PercentagePosition.from(
            absolutePosition: snappedPosition,
            in: windowFrame,
            width: indicatorWidth,
            height: indicatorHeight
        )

        // Save position for this application
        IndicatorPositionStore.shared.savePosition(percentagePos, for: bundleID)

        Logger.debug("FloatingErrorIndicator: Saved position for \(bundleID) at x=\(percentagePos.xPercent), y=\(percentagePos.yPercent)", category: Logger.ui)

        // Apply snapped position if different from original
        if snappedPosition != finalPosition {
            Logger.debug("FloatingErrorIndicator: Snapping from \(finalPosition) to \(snappedPosition)", category: Logger.ui)
            let snappedFrame = NSRect(x: snappedPosition.x, y: snappedPosition.y, width: indicatorWidth, height: indicatorHeight)
            setFrame(snappedFrame, display: true, animate: true)
        }
    }

    /// Snap a position to the valid border area (1.5cm band around window edge)
    /// If the position is outside the window or in the center, snaps to closest valid position
    private func snapToBorderArea(position: CGPoint, windowFrame: CGRect, indicatorWidth: CGFloat, indicatorHeight: CGFloat) -> CGPoint {
        let borderWidth = BorderGuideWindow.borderWidth

        // First, clamp position to be within the window bounds (use actual width for X, height for Y)
        var snappedX = max(windowFrame.minX, min(position.x, windowFrame.maxX - indicatorWidth))
        var snappedY = max(windowFrame.minY, min(position.y, windowFrame.maxY - indicatorHeight))

        // Define the valid border area (within borderWidth of any edge)
        let innerRect = windowFrame.insetBy(dx: borderWidth, dy: borderWidth)

        // Check if the indicator center is in the "forbidden" center zone
        let indicatorCenterX = snappedX + indicatorWidth / 2
        let indicatorCenterY = snappedY + indicatorHeight / 2

        // If the indicator is fully within the inner (forbidden) zone, snap to closest edge
        if innerRect.contains(CGPoint(x: indicatorCenterX, y: indicatorCenterY)) {
            // Calculate distances to each edge of the valid border area
            let distToLeft = indicatorCenterX - windowFrame.minX
            let distToRight = windowFrame.maxX - indicatorCenterX
            let distToBottom = indicatorCenterY - windowFrame.minY
            let distToTop = windowFrame.maxY - indicatorCenterY

            let minDist = min(distToLeft, distToRight, distToBottom, distToTop)

            // Snap to the closest edge (use correct dimension for each edge)
            if minDist == distToLeft {
                snappedX = windowFrame.minX
            } else if minDist == distToRight {
                snappedX = windowFrame.maxX - indicatorWidth
            } else if minDist == distToBottom {
                snappedY = windowFrame.minY
            } else {
                snappedY = windowFrame.maxY - indicatorHeight
            }

            Logger.debug("FloatingErrorIndicator: Snapped to closest edge (minDist=\(minDist))", category: Logger.ui)
        }

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

        // Calculate dimensions based on shape and ACTUAL position-based orientation
        let indicatorWidth: CGFloat
        let indicatorHeight: CGFloat

        if currentShape == .capsule {
            // Determine orientation from actual stored/resolved position
            let orientation = CapsuleStateManager.orientationFromPercentagePosition(resolvedPosition)
            capsuleIndicatorView?.orientation = orientation

            let sectionCount = CGFloat(max(capsuleStateManager.visibleSections.count, 1))
            switch orientation {
            case .vertical:
                indicatorWidth = UIConstants.capsuleWidth
                indicatorHeight = sectionCount * UIConstants.capsuleSectionHeight
            case .horizontal:
                indicatorWidth = sectionCount * UIConstants.capsuleSectionHeight
                indicatorHeight = UIConstants.capsuleSectionHeight
            }
        } else {
            indicatorWidth = UIConstants.indicatorSize
            indicatorHeight = UIConstants.indicatorSize
        }

        // Convert percentage to absolute position (use width for X, height for Y)
        let position = resolvedPosition.toAbsolute(in: visibleFrame, width: indicatorWidth, height: indicatorHeight)
        let finalFrame = NSRect(x: position.x, y: position.y, width: indicatorWidth, height: indicatorHeight)

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

    /// Show grammar suggestions popover from keyboard shortcut
    @discardableResult
    func showGrammarPopoverFromKeyboard() -> Bool {
        guard isVisible else {
            Logger.debug("FloatingErrorIndicator: showGrammarPopoverFromKeyboard - indicator not visible", category: Logger.ui)
            return false
        }

        Logger.debug("FloatingErrorIndicator: showGrammarPopoverFromKeyboard - showing grammar popover", category: Logger.ui)
        showGrammarPopover()
        return true
    }

    /// Show style suggestions popover from keyboard shortcut
    /// If no style suggestions available, triggers a style check
    @discardableResult
    func showStylePopoverFromKeyboard() -> Bool {
        guard isVisible else {
            Logger.debug("FloatingErrorIndicator: showStylePopoverFromKeyboard - indicator not visible", category: Logger.ui)
            return false
        }

        Logger.debug("FloatingErrorIndicator: showStylePopoverFromKeyboard - showing style popover", category: Logger.ui)
        showStylePopover()
        return true
    }

    /// Show AI Compose popover from keyboard shortcut
    @discardableResult
    func showAIComposeFromKeyboard() -> Bool {
        guard isVisible else {
            Logger.debug("FloatingErrorIndicator: showAIComposeFromKeyboard - indicator not visible", category: Logger.ui)
            return false
        }

        Logger.debug("FloatingErrorIndicator: showAIComposeFromKeyboard - showing AI compose popover", category: Logger.ui)
        showTextGenerationPopover()
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

    /// Popover anchor information for consistent positioning
    struct PopoverAnchor {
        let anchorPoint: CGPoint  // The edge point of the indicator where popover should align
        let edge: PopoverOpenDirection  // Which edge of the indicator the popover opens from
    }

    /// Calculate popover anchor point and edge for consistent positioning
    /// Uses the stored percentage position to determine which edge the indicator is on (same as CapsuleStateManager)
    private func calculatePopoverAnchor(for indicatorFrame: CGRect) -> PopoverAnchor {
        // Get stored percentage position for current app
        let pos: IndicatorPositionStore.PercentagePosition
        if let bundleID = context?.bundleIdentifier,
           let storedPos = IndicatorPositionStore.shared.getPosition(for: bundleID) {
            pos = storedPos
        } else {
            pos = IndicatorPositionStore.shared.getDefaultPosition()
        }

        // Use same threshold as CapsuleStateManager for consistency
        let sideEdgeThreshold: CGFloat = 0.15
        let topBottomThreshold: CGFloat = 0.12

        let isOnLeftEdge = pos.xPercent < sideEdgeThreshold
        let isOnRightEdge = pos.xPercent > (1.0 - sideEdgeThreshold)
        let isOnTopEdge = pos.yPercent > (1.0 - topBottomThreshold)
        let isOnBottomEdge = pos.yPercent < topBottomThreshold

        Logger.debug("calculatePopoverAnchor: x=\(pos.xPercent), y=\(pos.yPercent) → L=\(isOnLeftEdge), R=\(isOnRightEdge), T=\(isOnTopEdge), B=\(isOnBottomEdge)", category: Logger.ui)

        // Return anchor point at the indicator edge where popover should open from
        let spacing: CGFloat = 25  // Gap between indicator and popover

        // Priority: right/left edges first (since vertical capsule), then top/bottom
        if isOnRightEdge {
            // Indicator on right edge → popover opens to the left
            Logger.debug("calculatePopoverAnchor: isOnRightEdge → .left", category: Logger.ui)
            return PopoverAnchor(
                anchorPoint: CGPoint(x: indicatorFrame.minX - spacing, y: indicatorFrame.midY),
                edge: .left
            )
        } else if isOnLeftEdge {
            // Indicator on left edge → popover opens to the right
            Logger.debug("calculatePopoverAnchor: isOnLeftEdge → .right", category: Logger.ui)
            return PopoverAnchor(
                anchorPoint: CGPoint(x: indicatorFrame.maxX + spacing, y: indicatorFrame.midY),
                edge: .right
            )
        } else if isOnTopEdge {
            // Indicator at top → popover opens below
            Logger.debug("calculatePopoverAnchor: isOnTopEdge → .bottom", category: Logger.ui)
            return PopoverAnchor(
                anchorPoint: CGPoint(x: indicatorFrame.midX, y: indicatorFrame.minY - spacing),
                edge: .bottom
            )
        } else if isOnBottomEdge {
            // Indicator at bottom → popover opens above
            Logger.debug("calculatePopoverAnchor: isOnBottomEdge → .top", category: Logger.ui)
            return PopoverAnchor(
                anchorPoint: CGPoint(x: indicatorFrame.midX, y: indicatorFrame.maxY + spacing),
                edge: .top
            )
        } else {
            // Default: popover opens to the left (most common for right-side indicator)
            Logger.debug("calculatePopoverAnchor: no edge detected → default .left", category: Logger.ui)
            return PopoverAnchor(
                anchorPoint: CGPoint(x: indicatorFrame.minX - spacing, y: indicatorFrame.midY),
                edge: .left
            )
        }
    }

    /// Legacy method for backward compatibility - converts anchor to center position
    private func calculatePopoverPosition(for indicatorFrame: CGRect) -> CGPoint {
        let anchor = calculatePopoverAnchor(for: indicatorFrame)
        // Return anchor point - popovers will position themselves relative to this
        return anchor.anchorPoint
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

        // Show menu at mouse location - use whichever view is active
        let targetView: NSView?
        if let capsuleView = capsuleIndicatorView {
            targetView = capsuleView
        } else {
            targetView = indicatorView
        }
        guard let view = targetView else { return }
        let locationInView = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: locationInView, in: view)
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

// MARK: - Capsule Indicator View

/// Custom view that draws a capsule-shaped indicator with multiple sections
private class CapsuleIndicatorView: NSView {

    // MARK: - Properties

    var sections: [CapsuleSectionState] = [] {
        didSet {
            updateSpinningAnimation()
            needsDisplay = true
        }
    }

    var orientation: CapsuleOrientation = .vertical {
        didSet {
            needsDisplay = true
        }
    }

    var onSectionClicked: ((CapsuleSectionType) -> Void)?
    var onRightClicked: ((NSEvent) -> Void)?
    var onHover: ((CapsuleSectionType?) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?

    private var hoveredSection: CapsuleSectionType?
    private var hoverTimer: Timer?
    private var hoverPopoverActive = false
    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var spinningTimer: Timer?
    private var spinningAngle: CGFloat = 0
    private var themeObserver: Any?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
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

    private func updateSpinningAnimation() {
        let hasSpinning = sections.contains { section in
            if case .styleLoading = section.displayState { return true }
            if case .textGenActive = section.displayState { return true }
            return false
        }

        if hasSpinning {
            startSpinning()
        } else {
            stopSpinning()
        }
    }

    private func startSpinning() {
        guard spinningTimer == nil else { return }
        spinningTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.animationFrameInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.spinningAngle -= 0.08
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

    // MARK: - Section Geometry

    /// Get the frame for a section at the given index
    func sectionFrame(at index: Int) -> CGRect {
        let sectionSize = UIConstants.capsuleSectionHeight
        let spacing = UIConstants.capsuleSectionSpacing

        switch orientation {
        case .vertical:
            // Sections stacked from top to bottom
            // In Cocoa coordinates, y=0 is at the bottom, so we need to calculate from top
            let yFromTop = CGFloat(index) * (sectionSize + spacing)
            let y = bounds.height - yFromTop - sectionSize
            return CGRect(x: 0, y: y, width: bounds.width, height: sectionSize)

        case .horizontal:
            // Sections arranged from left to right
            let x = CGFloat(index) * (sectionSize + spacing)
            return CGRect(x: x, y: 0, width: sectionSize, height: bounds.height)
        }
    }

    /// Determine which section is at the given point
    func sectionAtPoint(_ point: CGPoint) -> CapsuleSectionType? {
        for (index, section) in sections.enumerated() {
            let frame = sectionFrame(at: index)
            if frame.contains(point) {
                return section.type
            }
        }
        return nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !sections.isEmpty else { return }

        let isDarkMode = determineDarkMode()

        // Single section - draw as circle (like IndicatorView)
        if sections.count == 1 {
            drawCircularIndicator(isDarkMode: isDarkMode)
            return
        }

        // Multiple sections - draw as capsule
        drawCapsuleIndicator(isDarkMode: isDarkMode)
    }

    /// Draw circular indicator (same as IndicatorView)
    private func drawCircularIndicator(isDarkMode: Bool) {
        guard let section = sections.first else { return }

        let backgroundRect = bounds.insetBy(dx: 5, dy: 5)
        let backgroundPath = NSBezierPath(ovalIn: backgroundRect)

        // Draw shadow
        drawShadow(path: backgroundPath, isDarkMode: isDarkMode)

        // Draw glass background
        drawGlassBackground(path: backgroundPath, rect: backgroundRect, isDarkMode: isDarkMode)

        // Draw ring
        if case .styleLoading = section.displayState {
            drawSpinningRing(rect: backgroundRect, color: section.ringColor, isDarkMode: isDarkMode)
        } else {
            drawRing(rect: backgroundRect, color: section.ringColor, isHovered: section.isHovered)
        }

        // Draw content
        drawSectionContent(section, in: backgroundRect, isDarkMode: isDarkMode)
    }

    /// Draw capsule-shaped indicator with multiple sections - unified elegant design
    private func drawCapsuleIndicator(isDarkMode: Bool) {
        let cornerRadius = UIConstants.capsuleCornerRadius
        let capsuleRect = bounds.insetBy(dx: 2, dy: 2)
        let capsulePath = NSBezierPath(roundedRect: capsuleRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // Draw shadow for entire capsule
        drawShadow(path: capsulePath, isDarkMode: isDarkMode)

        // Draw unified glass background
        NSGraphicsContext.saveGraphicsState()
        capsulePath.addClip()

        let glassBaseColor = isDarkMode
            ? NSColor(white: 0.15, alpha: 1.0)
            : NSColor(white: 0.97, alpha: 1.0)
        glassBaseColor.setFill()
        NSBezierPath.fill(capsuleRect)

        // Subtle top highlight for depth
        let highlightGradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(isDarkMode ? 0.12 : 0.4),
            NSColor.white.withAlphaComponent(0.0)
        ])
        highlightGradient?.draw(in: capsuleRect, angle: 90)

        NSGraphicsContext.restoreGraphicsState()

        // Draw subtle separator lines between sections
        if sections.count > 1 {
            let separatorColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.15)
                : NSColor.black.withAlphaComponent(0.1)
            separatorColor.setStroke()

            let sectionSize = UIConstants.capsuleSectionHeight
            let spacing = UIConstants.capsuleSectionSpacing

            // Draw a separator after each section except the last
            for i in 0..<(sections.count - 1) {
                let separatorPath = NSBezierPath()

                switch orientation {
                case .vertical:
                    // Horizontal separator line between sections
                    // Sections are drawn from top to bottom, so separator is below each section
                    let yFromTop = CGFloat(i + 1) * (sectionSize + spacing) - spacing / 2
                    let separatorY = capsuleRect.maxY - yFromTop
                    separatorPath.move(to: CGPoint(x: capsuleRect.minX + 6, y: separatorY))
                    separatorPath.line(to: CGPoint(x: capsuleRect.maxX - 6, y: separatorY))
                case .horizontal:
                    // Vertical separator line between sections
                    let separatorX = capsuleRect.minX + CGFloat(i + 1) * (sectionSize + spacing) - spacing / 2
                    separatorPath.move(to: CGPoint(x: separatorX, y: capsuleRect.minY + 6))
                    separatorPath.line(to: CGPoint(x: separatorX, y: capsuleRect.maxY - 6))
                }

                separatorPath.lineWidth = 0.5
                separatorPath.stroke()
            }
        }

        // Draw subtle neutral border
        let hasHover = sections.contains { $0.isHovered }
        let borderColor = isDarkMode
            ? NSColor.white.withAlphaComponent(hasHover ? 0.3 : 0.2)
            : NSColor.black.withAlphaComponent(hasHover ? 0.2 : 0.12)
        borderColor.setStroke()
        capsulePath.lineWidth = hasHover ? 1.5 : 1.0
        capsulePath.stroke()

        // Draw content for each section
        for (index, section) in sections.enumerated() {
            let contentRect = sectionFrame(at: index)
            drawSectionContent(section, in: contentRect, isDarkMode: isDarkMode)
        }
    }

    /// Create a path with different corner radii for top and bottom
    private func roundedRectPath(_ rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()

        // Start at bottom-left, going clockwise
        path.move(to: CGPoint(x: rect.minX + bottomRadius, y: rect.minY))

        // Bottom edge to bottom-right corner
        path.line(to: CGPoint(x: rect.maxX - bottomRadius, y: rect.minY))
        path.appendArc(withCenter: CGPoint(x: rect.maxX - bottomRadius, y: rect.minY + bottomRadius),
                       radius: bottomRadius, startAngle: 270, endAngle: 0, clockwise: false)

        // Right edge to top-right corner
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - topRadius))
        path.appendArc(withCenter: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - topRadius),
                       radius: topRadius, startAngle: 0, endAngle: 90, clockwise: false)

        // Top edge to top-left corner
        path.line(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY))
        path.appendArc(withCenter: CGPoint(x: rect.minX + topRadius, y: rect.maxY - topRadius),
                       radius: topRadius, startAngle: 90, endAngle: 180, clockwise: false)

        // Left edge to bottom-left corner
        path.line(to: CGPoint(x: rect.minX, y: rect.minY + bottomRadius))
        path.appendArc(withCenter: CGPoint(x: rect.minX + bottomRadius, y: rect.minY + bottomRadius),
                       radius: bottomRadius, startAngle: 180, endAngle: 270, clockwise: false)

        path.close()
        return path
    }

    // MARK: - Drawing Helpers

    private func determineDarkMode() -> Bool {
        switch UserPreferences.shared.overlayTheme {
        case "Light": return false
        case "Dark": return true
        default: return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
    }

    private func drawShadow(path: NSBezierPath, isDarkMode: Bool) {
        NSGraphicsContext.saveGraphicsState()

        let shadowColor = NSColor.black.withAlphaComponent(isDarkMode ? 0.35 : 0.2)
        let shadow = NSShadow()
        shadow.shadowColor = shadowColor
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 3
        shadow.set()

        NSColor.clear.setFill()
        path.fill()

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGlassBackground(path: NSBezierPath, rect: CGRect, isDarkMode: Bool) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let glassBaseColor = isDarkMode
            ? NSColor(white: 0.18, alpha: 1.0)
            : NSColor(white: 0.96, alpha: 1.0)
        glassBaseColor.setFill()
        NSBezierPath.fill(rect)

        let highlightGradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(isDarkMode ? 0.1 : 0.3),
            NSColor.white.withAlphaComponent(0.0)
        ])
        highlightGradient?.draw(in: rect, angle: 90)

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawRing(rect: CGRect, color: NSColor, isHovered: Bool) {
        let ringPath = NSBezierPath(ovalIn: rect)
        let adjustedColor = isHovered ? color.withAlphaComponent(1.0) : color
        adjustedColor.setStroke()
        ringPath.lineWidth = isHovered ? 3.0 : 2.5
        ringPath.stroke()

        // Inner glow
        let innerGlowPath = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
        color.withAlphaComponent(0.25).setStroke()
        innerGlowPath.lineWidth = 0.75
        innerGlowPath.stroke()
    }

    private func drawSpinningRing(rect: CGRect, color: NSColor, isDarkMode: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        // Background ring
        let backgroundRing = NSBezierPath()
        backgroundRing.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        color.withAlphaComponent(0.15).setStroke()
        backgroundRing.lineWidth = 2.5
        backgroundRing.stroke()

        // Animated arc
        let arcLength: CGFloat = 90
        let startAngleDegrees = spinningAngle * 180 / .pi
        let endAngleDegrees = startAngleDegrees + arcLength

        let spinningArc = NSBezierPath()
        spinningArc.appendArc(withCenter: center, radius: radius, startAngle: startAngleDegrees, endAngle: endAngleDegrees, clockwise: false)
        color.setStroke()
        spinningArc.lineWidth = 2.5
        spinningArc.lineCapStyle = .round
        spinningArc.stroke()
    }

    private func drawSpinningRingForSection(path: NSBezierPath, rect: CGRect, color: NSColor, isDarkMode: Bool) {
        // Background ring
        color.withAlphaComponent(0.15).setStroke()
        path.lineWidth = 2.5
        path.stroke()

        // For sections, we'll draw a partial animated border
        // This is simplified - full implementation would track arc position
        color.setStroke()
        path.lineWidth = 2.5
        path.stroke()
    }

    // MARK: - Content Drawing

    /// Distinct color palette for clear visual differentiation
    private var grammarIconColor: NSColor {
        // Warm red-orange for grammar errors - clearly different from purple/blue
        NSColor(red: 0.95, green: 0.35, blue: 0.25, alpha: 1.0)
    }

    private func styleIconColor(isDarkMode: Bool) -> NSColor {
        if isDarkMode {
            // Vibrant magenta for dark mode - high contrast
            return NSColor(red: 0.95, green: 0.3, blue: 0.75, alpha: 1.0)
        } else {
            // Deep violet for light mode - distinct from red and blue
            return NSColor(red: 0.6, green: 0.2, blue: 0.85, alpha: 1.0)
        }
    }

    private func textGenIconColor(isDarkMode: Bool) -> NSColor {
        if isDarkMode {
            // Bright cyan-blue for dark mode - clearly different from magenta
            return NSColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        } else {
            // Deep teal-blue for light mode - distinct from violet
            return NSColor(red: 0.15, green: 0.5, blue: 0.8, alpha: 1.0)
        }
    }

    private var successColor: NSColor {
        // Soft teal - for success checkmarks
        NSColor(red: 0.35, green: 0.65, blue: 0.6, alpha: 1.0)
    }

    private func drawSectionContent(_ section: CapsuleSectionState, in rect: CGRect, isDarkMode: Bool) {
        switch section.displayState {
        case .grammarCount(let count):
            drawCount(count, in: rect, isDarkMode: isDarkMode, color: grammarIconColor)
        case .grammarSuccess:
            drawCheckmark(in: rect, color: successColor)
        case .styleIdle:
            drawSparkle(in: rect, color: styleIconColor(isDarkMode: isDarkMode).withAlphaComponent(0.85))  // Ready state, slightly dimmed
        case .styleLoading:
            drawLoadingSpinner(in: rect, color: styleIconColor(isDarkMode: isDarkMode))
        case .styleCount(let count):
            drawCount(count, in: rect, isDarkMode: isDarkMode, color: styleIconColor(isDarkMode: isDarkMode))
        case .styleSuccess:
            drawCheckmark(in: rect, color: successColor)
        case .textGenIdle:
            drawPenIcon(in: rect)
        case .textGenActive:
            drawPenIcon(in: rect)
        case .hidden:
            break
        }
    }

    private func drawCount(_ count: Int, in rect: CGRect, isDarkMode: Bool, color: NSColor? = nil) {
        let textColor = color ?? (isDarkMode ? NSColor.white : NSColor.black)
        let countString = count > 9 ? "9+" : "\(count)"
        let fontSize: CGFloat = count > 9 ? 10 : 12

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: textColor
        ]
        let textSize = (countString as NSString).size(withAttributes: attributes)

        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        (countString as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawCheckmark(in rect: CGRect, color: NSColor) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        guard let checkmarkImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Success")?
            .withSymbolConfiguration(symbolConfig) else { return }

        let tintedImage = NSImage(size: checkmarkImage.size, flipped: false) { drawRect in
            checkmarkImage.draw(in: drawRect)
            color.set()
            drawRect.fill(using: .sourceAtop)
            return true
        }

        let imageSize = tintedImage.size
        let x = rect.midX - imageSize.width / 2
        let y = rect.midY - imageSize.height / 2

        tintedImage.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height),
                         from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    /// Draw a simple loading spinner within a section
    private func drawLoadingSpinner(in rect: CGRect, color: NSColor) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 6.0  // Small spinner radius

        // Draw background arc (dimmed)
        let backgroundArc = NSBezierPath()
        backgroundArc.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        color.withAlphaComponent(0.2).setStroke()
        backgroundArc.lineWidth = 2.0
        backgroundArc.stroke()

        // Draw spinning arc (partial circle)
        // Convert radians to degrees (spinningAngle is updated in radians)
        let startAngleDegrees = spinningAngle * 180 / .pi
        let spinnerArc = NSBezierPath()
        spinnerArc.appendArc(withCenter: center, radius: radius, startAngle: startAngleDegrees, endAngle: startAngleDegrees + 90)
        color.setStroke()
        spinnerArc.lineWidth = 2.0
        spinnerArc.lineCapStyle = .round
        spinnerArc.stroke()
    }

    private func drawSparkle(in rect: CGRect, color: NSColor) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        guard let sparkleImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Style")?
            .withSymbolConfiguration(symbolConfig) else { return }

        let tintedImage = NSImage(size: sparkleImage.size, flipped: false) { drawRect in
            sparkleImage.draw(in: drawRect)
            color.set()
            drawRect.fill(using: .sourceAtop)
            return true
        }

        let imageSize = tintedImage.size
        let x = rect.midX - imageSize.width / 2
        let y = rect.midY - imageSize.height / 2

        tintedImage.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height),
                         from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    private func drawPenIcon(in rect: CGRect) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        guard let penImage = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "Generate")?
            .withSymbolConfiguration(symbolConfig) else { return }

        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let iconColor = textGenIconColor(isDarkMode: isDarkMode)
        let tintedImage = NSImage(size: penImage.size, flipped: false) { drawRect in
            penImage.draw(in: drawRect)
            iconColor.set()
            drawRect.fill(using: .sourceAtop)
            return true
        }

        let imageSize = tintedImage.size
        let x = rect.midX - imageSize.width / 2
        let y = rect.midY - imageSize.height / 2

        tintedImage.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height),
                         from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }

        if !isDragging {
            isDragging = true
            NSCursor.closedHand.push()
            onDragStart?()
        }

        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - dragStartPoint.x
        let deltaY = currentPoint.y - dragStartPoint.y

        var newOrigin = window.frame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        window.setFrameOrigin(newOrigin)
        window.orderFrontRegardless()

        // Notify about position during drag for dynamic orientation updates
        onDragMove?(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            // Click - determine which section was clicked
            let locationInView = convert(event.locationInWindow, from: nil)
            Logger.debug("CapsuleIndicatorView: mouseUp at \(locationInView), bounds=\(bounds)", category: Logger.ui)
            if let section = sectionAtPoint(locationInView) {
                Logger.debug("CapsuleIndicatorView: Section detected: \(section)", category: Logger.ui)
                onSectionClicked?(section)
            } else {
                Logger.debug("CapsuleIndicatorView: No section detected at point", category: Logger.ui)
            }
            return
        }

        isDragging = false
        NSCursor.pop()

        if let window = window {
            onDragEnd?(window.frame.origin)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClicked?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        let section = sectionAtPoint(locationInView)

        if section != hoveredSection {
            let previousSection = hoveredSection
            hoveredSection = section

            // Update section hover states
            for i in 0..<sections.count {
                sections[i].isHovered = sections[i].type == section
            }

            needsDisplay = true

            // If a hover popover is active, immediately switch to the new section's popover
            // Also switch if any popover is currently visible (from click)
            if hoverPopoverActive || SuggestionPopover.shared.isVisible || TextGenerationPopover.shared.isVisible {
                if previousSection != nil && section != nil {
                    onHover?(section)
                }
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if !isDragging {
            NSCursor.openHand.push()
        }

        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.hoverDelay, repeats: false) { [weak self] _ in
            self?.hoverPopoverActive = true
            self?.onHover?(self?.hoveredSection)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            NSCursor.pop()
        }

        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverPopoverActive = false

        hoveredSection = nil
        for i in 0..<sections.count {
            sections[i].isHovered = false
        }
        needsDisplay = true

        onHover?(nil)
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}
