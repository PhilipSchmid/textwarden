//
//  WebExBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Cisco WebEx.
//
//  WebEx-specific characteristics:
//  - Native macOS app with Cocoa text views
//  - Standard AX APIs work reliably
//  - Requires typing pause
//  - Standard text replacement works
//

import Foundation

/// Complete behavior specification for Cisco WebEx
struct WebExBehavior: AppBehavior {
    let bundleIdentifier = "Cisco-Systems.Spark"
    let displayName = "Cisco WebEx"

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
        analysisDebounce: 0.5, // Typing pause needed
        boundsStabilizationDelay: 0.1,
        windowChangeGracePeriod: 0.3,
        boundsValidationInterval: 0.5
    )

    let knownQuirks: Set<AppQuirk> = []

    let usesUTF16TextIndices = false
}
