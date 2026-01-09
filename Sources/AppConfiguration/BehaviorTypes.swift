//
//  BehaviorTypes.swift
//  TextWarden
//
//  Value types for app-specific overlay behavior configuration.
//  Used by AppBehavior protocol implementations.
//

import CoreGraphics
import Foundation

// MARK: - Underline Visibility

/// Configuration for when and how to show underlines
struct UnderlineVisibilityBehavior: Equatable {
    /// Delay after text detection before showing underlines
    let showDelay: TimeInterval

    /// How to validate underline bounds before showing
    let boundsValidation: BoundsValidation

    /// Whether to show underlines during active typing
    let showDuringTyping: Bool

    /// Minimum text length required to show underlines
    let minimumTextLength: Int

    /// How to validate bounds before rendering
    enum BoundsValidation: Equatable {
        /// No validation - show underlines at any position
        case none
        /// Require origin.x >= 0 and origin.y >= 0
        case requirePositiveOrigin
        /// Require bounds to be within visible screen area
        case requireWithinScreen
        /// Wait for bounds to stabilize before showing
        case requireStable(stabilizationDelay: TimeInterval)
    }
}

// MARK: - Popover Behavior

/// Configuration for popover appearance and interaction
struct PopoverBehavior: Equatable {
    /// Delay before showing popover on hover
    let hoverDelay: TimeInterval

    /// Auto-hide timeout (0 = never auto-hide)
    let autoHideTimeout: TimeInterval

    /// Whether popover should hide when scrolling starts
    let hideOnScroll: Bool

    /// Whether popover should hide when window loses focus
    let hideOnWindowDeactivate: Bool

    /// Preferred direction to open popover
    let preferredDirection: PopoverDirection

    /// Whether to detect and avoid native popovers
    let detectNativePopovers: Bool

    /// App-specific native popover detection (nil if not needed)
    let nativePopoverDetection: NativePopoverDetection?

    /// Direction to open popover relative to anchor
    enum PopoverDirection: Equatable {
        case above
        case below
        case left
        case right
    }

    /// Configuration for detecting app's native popovers
    struct NativePopoverDetection: Equatable {
        /// Pattern to match in window title (nil = don't check)
        let windowTitlePattern: String?
        /// Pattern to match in window role (nil = don't check)
        let windowRolePattern: String?
        /// Whether to hide our popover when native is detected
        let hideWhenDetected: Bool
    }
}

// MARK: - Scroll Behavior

/// Configuration for scroll-related overlay behavior
struct ScrollBehavior: Equatable {
    /// Whether to hide overlays when scrolling starts
    let hideOnScrollStart: Bool

    /// Delay before re-showing overlays after scroll ends
    let reshowDelay: TimeInterval

    /// Whether this app sends reliable scroll events
    let hasReliableScrollEvents: Bool

    /// Fallback method when scroll events are unreliable
    let fallbackDetection: ScrollFallbackDetection

    /// Fallback scroll detection method
    enum ScrollFallbackDetection: Equatable {
        /// No fallback - rely on scroll events only
        case none
        /// Detect scroll by monitoring bounds movement
        case boundsMovement(threshold: CGFloat)
        /// Periodically check bounds position
        case periodicBoundsCheck(interval: TimeInterval)
    }
}

// MARK: - Mouse Behavior

/// Configuration for mouse-related overlay behavior
struct MouseBehavior: Equatable {
    /// Whether mouse movement should affect overlay visibility
    let hideOnMouseMovement: Bool

    /// Distance threshold for "significant" mouse movement
    let movementThreshold: CGFloat

    /// Whether clicking outside should dismiss overlays
    let dismissOnClickOutside: Bool

    /// Whether to track mouse for hover detection
    let enableHoverDetection: Bool
}

// MARK: - Coordinate System Behavior

/// Configuration for coordinate system handling
struct CoordinateSystemBehavior: Equatable {
    /// Coordinate system the app uses for AX values
    let axCoordinateSystem: AXCoordinateSystem

    /// Line height compensation to apply
    let lineHeightCompensation: LineHeightCompensation

    /// Coordinate system used by Accessibility API
    enum AXCoordinateSystem: Equatable {
        /// Standard AX coordinates (origin at top-left of primary screen)
        case quartzTopLeft
        /// Cocoa coordinates (origin at bottom-left)
        case cocoaBottomLeft
        /// Y-axis is inverted relative to Quartz
        case flipped
    }

    /// Compensation for line height differences
    enum LineHeightCompensation: Equatable {
        /// No compensation
        case none
        /// Fixed point adjustment
        case fixed(points: CGFloat)
        /// Percentage multiplier
        case percentage(multiplier: CGFloat)
        /// Auto-detect from font metrics
        case detectFromFont
    }
}

// MARK: - Timing Profile

/// Timing profile for debouncing and delays
struct TimingProfile: Equatable {
    /// Debounce interval for analysis triggers
    let analysisDebounce: TimeInterval

    /// How long to wait for AX bounds to stabilize
    let boundsStabilizationDelay: TimeInterval

    /// Grace period after window resize/move
    let windowChangeGracePeriod: TimeInterval

    /// Interval for periodic bounds validation
    let boundsValidationInterval: TimeInterval
}

// MARK: - App Quirks

/// Known quirks/bugs that require special handling
enum AppQuirk: Hashable {
    /// Chromium apps have emoji width measurement bugs
    case chromiumEmojiWidthBug

    /// App uses virtualized text (only visible text in DOM/view)
    case virtualizedText(visibilityPercentage: Int)

    /// App returns negative X coordinates for some elements
    case negativeXCoordinates

    /// App's AX bounds become invalid after sidebar toggle
    case boundsInvalidAfterSidebarToggle

    /// App has native popover that conflicts with ours
    case hasConflictingNativePopover

    /// App's scroll events are unreliable
    case unreliableScrollEvents

    /// App uses web-based text rendering (affects font metrics)
    case webBasedRendering

    /// App returns frame (0,0) for off-screen elements
    case zeroFrameForOffscreen

    /// App batches AX notifications instead of sending immediately
    case batchedAXNotifications

    /// App requires keyboard-based text replacement
    case requiresBrowserStyleReplacement

    /// App has focus bounce during paste operations
    case focusBouncesDuringPaste

    /// App has text marker index offset (invisible characters)
    case textMarkerIndexOffset

    /// App requires full re-analysis after text replacement
    case requiresFullReanalysisAfterReplacement

    /// App requires focus+select+paste replacement (Office-style)
    /// Used by apps where AXSetValue doesn't work and we need to:
    /// 1) Focus element, 2) Set selection, 3) Activate app, 4) Paste via keyboard
    case requiresFocusPasteReplacement

    /// App uses WebKit's AXReplaceRangeWithText API (Apple Mail)
    case usesMailReplaceRangeAPI

    /// App has Slack-style format-preserving replacement via Quill Delta
    case hasSlackFormatPreservingReplacement

    /// App requires selection validation before paste to prevent wrong placement
    /// Used for apps with virtualized content where errors may scroll out of view
    case requiresSelectionValidationBeforePaste

    /// App requires direct keyboard typing at position 0 to avoid paragraph creation bugs
    /// Used for Chromium contenteditable apps that create new paragraphs when pasting at start
    case requiresDirectTypingAtPosition0

    /// App has focus bounce behavior where clicking in editable areas temporarily focuses non-editable elements
    /// TextMonitor should preserve existing monitored element when focus bounces to non-editable element
    case hasFocusBounceProtection

    /// App needs custom element finding logic via its ContentParser
    /// TextMonitor should use the app's ContentParser to find the correct element to monitor
    case hasCustomElementFinder

    /// App needs special handling for scroll events in AnalysisCoordinator (Slack-specific)
    case requiresCustomScrollHandling

    /// App has formatting toolbar near compose field that should be included in hover detection
    case hasFormattingToolbarNearCompose

    /// App has unstable text retrieval where AX may return slightly different text each time
    /// This causes false "text changed" detection in periodic text validation.
    /// Skip text validation for these apps to prevent flickering.
    case hasUnstableTextRetrieval
}
