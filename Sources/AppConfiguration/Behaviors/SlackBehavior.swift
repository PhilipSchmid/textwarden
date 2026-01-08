//
//  SlackBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Slack.
//
//  Slack-specific characteristics:
//  - Electron/Chromium-based with Quill rich text editor
//  - Native popover detection needed (AXPopover role)
//  - Negative X coordinates can occur for some elements
//  - Scroll events are unreliable - use bounds movement detection
//  - Sends AX notifications immediately (no batching)
//

import Foundation

/// Complete behavior specification for Slack
struct SlackBehavior: AppBehavior {
    let bundleIdentifier = "com.tinyspeck.slackmacgap"
    let displayName = "Slack"

    let underlineVisibility = UnderlineVisibilityBehavior(
        showDelay: 0.1,
        boundsValidation: .requireWithinScreen,
        showDuringTyping: false,
        minimumTextLength: 1
    )

    let popoverBehavior = PopoverBehavior(
        hoverDelay: 0.3,
        autoHideTimeout: 3.0,
        hideOnScroll: false, // Slack scroll events unreliable
        hideOnWindowDeactivate: true,
        preferredDirection: .above,
        detectNativePopovers: true,
        nativePopoverDetection: PopoverBehavior.NativePopoverDetection(
            windowTitlePattern: nil,
            windowRolePattern: "AXPopover",
            hideWhenDetected: true
        )
    )

    let scrollBehavior = ScrollBehavior(
        hideOnScrollStart: false, // DISABLED - Slack scroll events unreliable
        reshowDelay: 0.5,
        hasReliableScrollEvents: false,
        fallbackDetection: .boundsMovement(threshold: 10.0)
    )

    let mouseBehavior = MouseBehavior(
        hideOnMouseMovement: false,
        movementThreshold: 50.0,
        dismissOnClickOutside: true,
        enableHoverDetection: true
    )

    let coordinateSystem = CoordinateSystemBehavior(
        axCoordinateSystem: .quartzTopLeft,
        lineHeightCompensation: .fixed(points: 2.0)
    )

    let timingProfile = TimingProfile(
        analysisDebounce: 1.0, // Chromium apps need longer debounce
        boundsStabilizationDelay: 0.25,
        windowChangeGracePeriod: 1.5,
        boundsValidationInterval: 0.5
    )

    let knownQuirks: Set<AppQuirk> = [
        .chromiumEmojiWidthBug,
        .negativeXCoordinates,
        .hasConflictingNativePopover,
        .unreliableScrollEvents,
        .webBasedRendering,
        .requiresBrowserStyleReplacement,
        .requiresFullReanalysisAfterReplacement,
        .hasSlackFormatPreservingReplacement,
        .requiresCustomScrollHandling,
        .hasFormattingToolbarNearCompose,
    ]

    let usesUTF16TextIndices = true
}
