//
//  NotionBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Notion.
//
//  Notion-specific characteristics:
//  - Electron/Chromium-based with block-based editor
//  - ~50% virtualized blocks (only visible content in DOM)
//  - Batches AX notifications (needs keyboard detection)
//  - Has RELIABLE scroll events (unlike Slack)
//  - Different timing needs than other Electron apps
//

import Foundation

/// Complete behavior specification for Notion
struct NotionBehavior: AppBehavior {
    let bundleIdentifier = "notion.id"
    let displayName = "Notion"

    let underlineVisibility = UnderlineVisibilityBehavior(
        showDelay: 0.15,
        boundsValidation: .requireStable(stabilizationDelay: 0.25),
        showDuringTyping: false,
        minimumTextLength: 1
    )

    let popoverBehavior = PopoverBehavior(
        hoverDelay: 0.3,
        autoHideTimeout: 3.0,
        hideOnScroll: true, // Notion HAS reliable scroll events
        hideOnWindowDeactivate: true,
        preferredDirection: .above,
        detectNativePopovers: false,
        nativePopoverDetection: nil
    )

    let scrollBehavior = ScrollBehavior(
        hideOnScrollStart: true, // ENABLED - Notion has reliable scroll events
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
        lineHeightCompensation: .percentage(multiplier: 1.1)
    )

    let timingProfile = TimingProfile(
        analysisDebounce: 1.0,
        boundsStabilizationDelay: 0.25,
        windowChangeGracePeriod: 1.0,
        boundsValidationInterval: 0.3
    )

    let knownQuirks: Set<AppQuirk> = [
        .chromiumEmojiWidthBug,
        .virtualizedText(visibilityPercentage: 50),
        .webBasedRendering,
        .batchedAXNotifications,
        .requiresBrowserStyleReplacement,
        .requiresFullReanalysisAfterReplacement,
    ]

    let usesUTF16TextIndices = true
}
