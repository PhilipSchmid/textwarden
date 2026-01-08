//
//  TeamsBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Microsoft Teams.
//
//  Teams-specific characteristics:
//  - Electron/Chromium-based with WebView2 compose
//  - Child element traversal required (parent AXTextArea unreliable)
//  - Requires typing pause before querying AX tree
//  - Frame (0,0) returned for off-screen elements
//

import Foundation

/// Complete behavior specification for Microsoft Teams
struct TeamsBehavior: AppBehavior {
    let bundleIdentifier = "com.microsoft.teams2"
    let displayName = "Microsoft Teams"

    let underlineVisibility = UnderlineVisibilityBehavior(
        showDelay: 0.15,
        boundsValidation: .requireWithinScreen,
        showDuringTyping: false,
        minimumTextLength: 1
    )

    let popoverBehavior = PopoverBehavior(
        hoverDelay: 0.3,
        autoHideTimeout: 3.0,
        hideOnScroll: true,
        hideOnWindowDeactivate: true,
        preferredDirection: .above,
        detectNativePopovers: false,
        nativePopoverDetection: nil
    )

    let scrollBehavior = ScrollBehavior(
        hideOnScrollStart: true,
        reshowDelay: 0.3,
        hasReliableScrollEvents: true,
        fallbackDetection: .none
    )

    let mouseBehavior = MouseBehavior(
        hideOnMouseMovement: false,
        movementThreshold: 50.0,
        dismissOnClickOutside: true,
        enableHoverDetection: true
    )

    let coordinateSystem = CoordinateSystemBehavior(
        axCoordinateSystem: .quartzTopLeft,
        lineHeightCompensation: .none
    )

    let timingProfile = TimingProfile(
        analysisDebounce: 1.0,
        boundsStabilizationDelay: 0.25,
        windowChangeGracePeriod: 1.0,
        boundsValidationInterval: 0.3
    )

    let knownQuirks: Set<AppQuirk> = [
        .chromiumEmojiWidthBug,
        .webBasedRendering,
        .zeroFrameForOffscreen,
        .requiresBrowserStyleReplacement,
        .requiresFullReanalysisAfterReplacement,
        .requiresSelectionValidationBeforePaste,
    ]

    let usesUTF16TextIndices = true
}
