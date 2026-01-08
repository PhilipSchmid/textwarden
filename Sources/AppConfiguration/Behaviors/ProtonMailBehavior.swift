//
//  ProtonMailBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Proton Mail.
//
//  Proton Mail-specific characteristics:
//  - Electron-based with good AX support
//  - Child AXStaticText elements per paragraph
//  - Tree traversal with UTF-16 emoji handling
//  - Rich text email composer
//

import Foundation

/// Complete behavior specification for Proton Mail
struct ProtonMailBehavior: AppBehavior {
    let bundleIdentifier = "ch.protonmail.desktop"
    let displayName = "Proton Mail"

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
        analysisDebounce: 1.0, // Chromium apps need longer debounce
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
