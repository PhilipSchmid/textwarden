//
//  PowerPointBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Microsoft PowerPoint.
//
//  PowerPoint-specific characteristics:
//  - Native macOS app (Cocoa/AppKit)
//  - Only Notes section is accessible via AX
//  - Slide text boxes NOT exposed via AX API
//  - Browser-style replacement needed
//

import Foundation

/// Complete behavior specification for Microsoft PowerPoint
struct PowerPointBehavior: AppBehavior {
    let bundleIdentifier = "com.microsoft.Powerpoint"
    let displayName = "Microsoft PowerPoint"

    let underlineVisibility = UnderlineVisibilityBehavior(
        showDelay: 0.1,
        boundsValidation: .requirePositiveOrigin,
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
        analysisDebounce: 0.3,
        boundsStabilizationDelay: 0.1,
        windowChangeGracePeriod: 0.3,
        boundsValidationInterval: 0.5
    )

    let knownQuirks: Set<AppQuirk> = [
        .requiresBrowserStyleReplacement,
        .requiresFocusPasteReplacement,
        .hasFocusBounceProtection,
    ]

    let usesUTF16TextIndices = false
}
