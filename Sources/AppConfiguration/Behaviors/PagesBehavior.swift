//
//  PagesBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Apple Pages.
//
//  Pages-specific characteristics:
//  - Native macOS app with AXTextArea
//  - Rich text support
//  - AXBoundsForRange works reliably
//  - Browser-style replacement needed (AXSetValue doesn't work)
//

import Foundation

/// Complete behavior specification for Apple Pages
struct PagesBehavior: AppBehavior {
    let bundleIdentifier = "com.apple.iWork.Pages"
    let displayName = "Apple Pages"

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
    ]

    let usesUTF16TextIndices = false
}
