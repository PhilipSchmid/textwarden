//
//  OverlayStateMachine.swift
//  TextWarden
//
//  Centralized state machine for overlay visibility.
//  Replaces scattered boolean flags with explicit states and transitions.
//
//  Design principle: One state at a time. Events trigger transitions.
//  Each transition consults the app's behavior for app-specific rules.
//

import Foundation

// MARK: - Overlay State Machine

/// Centralized state machine for overlay visibility.
///
/// Replaces scattered boolean flags (isHiddenDueToScroll, isHiddenDueToMovement, etc.)
/// with explicit states and transitions. This eliminates impossible state combinations
/// and makes debugging easier.
///
/// Usage:
/// ```swift
/// let stateMachine = OverlayStateMachine()
/// stateMachine.delegate = self
/// stateMachine.configure(for: "com.tinyspeck.slackmacgap")
///
/// // Handle events
/// stateMachine.handle(.scrollStarted)
/// stateMachine.handle(.scrollEnded)
/// ```
final class OverlayStateMachine {
    // MARK: - Types

    /// All possible states of the overlay system
    enum State: Equatable, CustomStringConvertible {
        /// No text being monitored, overlays hidden
        case idle

        /// Text detected, analysis in progress
        case analyzing

        /// Underlines visible, no popover showing
        case showingUnderlines

        /// Popover visible for an error
        case showingPopover(PopoverType)

        /// Temporarily hidden due to scrolling
        case hiddenDueToScroll

        /// Temporarily hidden due to window movement
        case hiddenDueToMovement

        /// Hidden because app's native popover is showing
        case hiddenDueToNativePopover

        /// Hidden because a modal dialog is present
        /// NOTE: This state is currently unused by design. Modal dialogs appear at a higher
        /// window level than overlays, naturally obscuring them. When the modal closes,
        /// overlays become immediately visible without needing explicit restore logic.
        /// Using this state would cause unnecessary hide/restore cycles with potential flashing.
        case hiddenDueToModal

        var description: String {
            switch self {
            case .idle: "idle"
            case .analyzing: "analyzing"
            case .showingUnderlines: "showingUnderlines"
            case let .showingPopover(type): "showingPopover(\(type))"
            case .hiddenDueToScroll: "hiddenDueToScroll"
            case .hiddenDueToMovement: "hiddenDueToMovement"
            case .hiddenDueToNativePopover: "hiddenDueToNativePopover"
            case .hiddenDueToModal: "hiddenDueToModal"
            }
        }
    }

    /// Types of popovers that can be shown
    enum PopoverType: Equatable, CustomStringConvertible {
        case suggestion(errorIndex: Int)
        case readability
        case textGeneration
        case style

        var description: String {
            switch self {
            case let .suggestion(index): "suggestion(\(index))"
            case .readability: "readability"
            case .textGeneration: "textGeneration"
            case .style: "style"
            }
        }
    }

    /// Events that trigger state transitions
    enum Event: CustomStringConvertible {
        // Analysis events
        case textDetected(text: String, bundleID: String)
        case analysisCompleted(hasErrors: Bool)
        case analysisCleared

        // Mouse/hover events
        case mouseEnteredUnderline(errorIndex: Int)
        case mouseExitedUnderline
        case mouseEnteredPopover
        case mouseExitedPopover
        case popoverActionSelected
        case clickedOutside

        // Window events
        case scrollStarted
        case scrollEnded
        case windowMoveStarted
        case windowMoveEnded
        case windowDeactivated
        case windowActivated

        // External events
        case nativePopoverDetected
        case nativePopoverDismissed
        case modalDialogDetected
        case modalDialogDismissed

        var description: String {
            switch self {
            case .textDetected: "textDetected"
            case let .analysisCompleted(hasErrors): "analysisCompleted(hasErrors:\(hasErrors))"
            case .analysisCleared: "analysisCleared"
            case let .mouseEnteredUnderline(index): "mouseEnteredUnderline(\(index))"
            case .mouseExitedUnderline: "mouseExitedUnderline"
            case .mouseEnteredPopover: "mouseEnteredPopover"
            case .mouseExitedPopover: "mouseExitedPopover"
            case .popoverActionSelected: "popoverActionSelected"
            case .clickedOutside: "clickedOutside"
            case .scrollStarted: "scrollStarted"
            case .scrollEnded: "scrollEnded"
            case .windowMoveStarted: "windowMoveStarted"
            case .windowMoveEnded: "windowMoveEnded"
            case .windowDeactivated: "windowDeactivated"
            case .windowActivated: "windowActivated"
            case .nativePopoverDetected: "nativePopoverDetected"
            case .nativePopoverDismissed: "nativePopoverDismissed"
            case .modalDialogDetected: "modalDialogDetected"
            case .modalDialogDismissed: "modalDialogDismissed"
            }
        }
    }

    // MARK: - Properties

    /// Current state (read-only externally)
    private(set) var currentState: State = .idle

    /// Current app behavior
    private var currentBehavior: AppBehavior?

    /// Timer for delayed re-show after scroll
    private var reshowTimer: Timer?

    /// Delegate for state change notifications
    weak var delegate: OverlayStateMachineDelegate?

    // MARK: - Configuration

    /// Configure the state machine for a specific app
    func configure(for bundleIdentifier: String) {
        currentBehavior = AppBehaviorRegistry.shared.behavior(for: bundleIdentifier)
        Logger.debug(
            "OverlayStateMachine configured for \(bundleIdentifier)",
            category: Logger.ui
        )
    }

    // MARK: - Event Handling

    /// Handle an event and transition to appropriate state
    func handle(_ event: Event) {
        let previousState = currentState
        let newState = nextState(for: event)

        guard newState != previousState else {
            Logger.trace(
                "State unchanged: \(currentState) [event: \(event)]",
                category: Logger.ui
            )
            return
        }

        Logger.debug(
            "State transition: \(previousState) → \(newState) [event: \(event)]",
            category: Logger.ui
        )

        // Exit actions for previous state
        performExitActions(for: previousState)

        // Update state
        currentState = newState

        // Entry actions for new state
        performEntryActions(for: newState)

        // Notify delegate
        delegate?.stateMachine(self, didTransitionFrom: previousState, to: newState, event: event)
    }

    // MARK: - State Transition Logic

    private func nextState(for event: Event) -> State {
        guard let behavior = currentBehavior else {
            // No behavior configured - stay in idle
            return .idle
        }

        switch (currentState, event) {
        // MARK: From idle

        case (.idle, .textDetected):
            return .analyzing

        // MARK: From analyzing
        case let (.analyzing, .analysisCompleted(hasErrors)) where hasErrors:
            return .showingUnderlines
        case (.analyzing, .analysisCompleted):
            return .idle
        case (.analyzing, .analysisCleared):
            return .idle

        // MARK: From showingUnderlines
        case let (.showingUnderlines, .mouseEnteredUnderline(index)):
            return .showingPopover(.suggestion(errorIndex: index))
        case (.showingUnderlines, .scrollStarted) where behavior.scrollBehavior.hideOnScrollStart:
            return .hiddenDueToScroll
        case (.showingUnderlines, .windowMoveStarted):
            return .hiddenDueToMovement
        case (.showingUnderlines, .nativePopoverDetected) where behavior.popoverBehavior.detectNativePopovers:
            return .hiddenDueToNativePopover
        case (.showingUnderlines, .modalDialogDetected):
            return .hiddenDueToModal
        case (.showingUnderlines, .analysisCleared):
            return .idle
        case (.showingUnderlines, .windowDeactivated) where behavior.popoverBehavior.hideOnWindowDeactivate:
            return .hiddenDueToScroll // Reuse scroll-hidden state

        // MARK: From showingPopover
        case (.showingPopover, .mouseExitedPopover):
            return .showingUnderlines
        case (.showingPopover, .popoverActionSelected):
            return .analyzing // Re-analyze after fix applied
        case (.showingPopover, .clickedOutside) where behavior.mouseBehavior.dismissOnClickOutside:
            return .showingUnderlines
        case (.showingPopover, .scrollStarted) where behavior.popoverBehavior.hideOnScroll:
            return .hiddenDueToScroll
        case (.showingPopover, .windowDeactivated) where behavior.popoverBehavior.hideOnWindowDeactivate:
            return .hiddenDueToScroll
        case (.showingPopover, .windowMoveStarted):
            return .hiddenDueToMovement
        case (.showingPopover, .nativePopoverDetected) where behavior.popoverBehavior.detectNativePopovers:
            return .hiddenDueToNativePopover
        case (.showingPopover, .modalDialogDetected):
            return .hiddenDueToModal
        case (.showingPopover, .analysisCleared):
            return .idle

        // MARK: From hiddenDueToScroll
        case (.hiddenDueToScroll, .scrollEnded):
            scheduleReshow(delay: behavior.scrollBehavior.reshowDelay)
            return .showingUnderlines
        case (.hiddenDueToScroll, .windowActivated):
            return .showingUnderlines
        case (.hiddenDueToScroll, .analysisCleared):
            return .idle

        // MARK: From hiddenDueToMovement
        case (.hiddenDueToMovement, .windowMoveEnded):
            return .showingUnderlines
        case (.hiddenDueToMovement, .analysisCleared):
            return .idle

        // MARK: From hiddenDueToNativePopover
        case (.hiddenDueToNativePopover, .nativePopoverDismissed):
            return .showingUnderlines
        case (.hiddenDueToNativePopover, .analysisCleared):
            return .idle

        // MARK: From hiddenDueToModal
        case (.hiddenDueToModal, .modalDialogDismissed):
            return .showingUnderlines
        case (.hiddenDueToModal, .analysisCleared):
            return .idle

        // MARK: Default - no transition
        default:
            return currentState
        }
    }

    // MARK: - Exit/Entry Actions

    private func performExitActions(for state: State) {
        switch state {
        case .showingPopover:
            delegate?.stateMachineShouldHidePopover(self)
        default:
            break
        }
    }

    private func performEntryActions(for state: State) {
        switch state {
        case .showingUnderlines:
            reshowTimer?.invalidate()
            reshowTimer = nil
            delegate?.stateMachineShouldShowUnderlines(self)

        case let .showingPopover(type):
            delegate?.stateMachineShouldShowPopover(self, type: type)

        case .hiddenDueToScroll, .hiddenDueToMovement, .hiddenDueToNativePopover, .hiddenDueToModal:
            delegate?.stateMachineShouldHideAllOverlays(self)

        case .idle:
            reshowTimer?.invalidate()
            reshowTimer = nil
            delegate?.stateMachineShouldHideAllOverlays(self)

        case .analyzing:
            // Analysis in progress - keep current visibility
            break
        }
    }

    // MARK: - Helpers

    private func scheduleReshow(delay: TimeInterval) {
        reshowTimer?.invalidate()
        reshowTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            // Timer just provides the delay - state transition already happened
            self?.reshowTimer = nil
        }
    }

    /// Reset to idle state (for testing or error recovery)
    func reset() {
        reshowTimer?.invalidate()
        reshowTimer = nil
        currentState = .idle
    }
}

// MARK: - Delegate Protocol

/// Delegate for overlay state machine events
protocol OverlayStateMachineDelegate: AnyObject {
    /// Called when state changes
    func stateMachine(
        _ machine: OverlayStateMachine,
        didTransitionFrom previousState: OverlayStateMachine.State,
        to newState: OverlayStateMachine.State,
        event: OverlayStateMachine.Event
    )

    /// Called when underlines should be shown
    func stateMachineShouldShowUnderlines(_ machine: OverlayStateMachine)

    /// Called when all overlays should be hidden
    func stateMachineShouldHideAllOverlays(_ machine: OverlayStateMachine)

    /// Called when popover should be shown
    func stateMachineShouldShowPopover(_ machine: OverlayStateMachine, type: OverlayStateMachine.PopoverType)

    /// Called when popover should be hidden
    func stateMachineShouldHidePopover(_ machine: OverlayStateMachine)
}
