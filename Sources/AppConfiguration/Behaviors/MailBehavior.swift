//
//  MailBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Apple Mail.
//
//  Mail-specific characteristics:
//  - Native macOS app with WebKit compose view
//  - Focus bounces during paste operations
//  - Uses WebKit TextMarker APIs for selection
//  - Sends AX notifications promptly
//

import Foundation

/// Complete behavior specification for Apple Mail
struct MailBehavior: AppBehavior {
    let bundleIdentifier = "com.apple.mail"
    let displayName = "Apple Mail"

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
        analysisDebounce: 0.5,
        boundsStabilizationDelay: 0.15,
        windowChangeGracePeriod: 0.5,
        boundsValidationInterval: 0.3
    )

    let knownQuirks: Set<AppQuirk> = [
        .focusBouncesDuringPaste,
        .requiresBrowserStyleReplacement,
        .requiresFullReanalysisAfterReplacement,
        .usesMailReplaceRangeAPI,
    ]

    let usesUTF16TextIndices = true
}
