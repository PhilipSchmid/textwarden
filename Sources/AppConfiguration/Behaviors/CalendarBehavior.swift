//
//  CalendarBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Apple Calendar.
//
//  Calendar-specific characteristics:
//  - Native macOS app with Cocoa text fields
//  - Plain text event titles
//  - Standard AX APIs work reliably
//

import Foundation

/// Complete behavior specification for Apple Calendar
struct CalendarBehavior: AppBehavior {
    let bundleIdentifier = "com.apple.iCal"
    let displayName = "Apple Calendar"

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

    let knownQuirks: Set<AppQuirk> = []

    let usesUTF16TextIndices = false
}
