//
//  ChatGPTBehavior.swift
//  TextWarden
//
//  Complete behavior specification for ChatGPT Desktop.
//
//  ChatGPT-specific characteristics:
//  - Electron/Chromium-based
//  - RangeBounds strategy works well
//  - Batches AX notifications (needs keyboard detection)
//

import Foundation

/// Complete behavior specification for ChatGPT Desktop
struct ChatGPTBehavior: AppBehavior {
    let bundleIdentifier = "com.openai.chat"
    let displayName = "ChatGPT"

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
        .batchedAXNotifications,
        .requiresBrowserStyleReplacement,
        .requiresFullReanalysisAfterReplacement,
    ]

    let usesUTF16TextIndices = true
}
