//
//  ClaudeBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Claude Desktop.
//
//  Claude-specific characteristics:
//  - Electron/Chromium-based
//  - Selection-based positioning works well
//  - Plain text input (no rich formatting)
//  - Requires typing pause for accurate analysis
//

import Foundation

/// Complete behavior specification for Claude Desktop
struct ClaudeBehavior: AppBehavior {
    let bundleIdentifier = "com.anthropic.claudefordesktop"
    let displayName = "Claude"

    let underlineVisibility = UnderlineVisibilityBehavior(
        showDelay: 0.1,
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
        boundsStabilizationDelay: 0.2,
        windowChangeGracePeriod: 1.0,
        boundsValidationInterval: 0.3
    )

    let knownQuirks: Set<AppQuirk> = [
        .chromiumEmojiWidthBug,
        .webBasedRendering,
        .requiresBrowserStyleReplacement,
        .requiresFullReanalysisAfterReplacement,
    ]

    let usesUTF16TextIndices = true
}
