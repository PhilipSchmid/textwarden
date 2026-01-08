//
//  DefaultBehavior.swift
//  TextWarden
//
//  Default behavior for unknown/unsupported applications.
//
//  This is used as a fallback when no specific behavior is registered.
//  Settings are conservative - they should work reasonably well for
//  most apps without causing issues.
//

import Foundation

/// Default behavior for unknown applications
struct DefaultBehavior: AppBehavior {
    let bundleIdentifier: String
    var displayName: String { "Unknown App" }

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
        hasReliableScrollEvents: false, // Conservative - assume unreliable
        fallbackDetection: .boundsMovement(threshold: 10.0)
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
        analysisDebounce: 0.5, // Conservative debounce
        boundsStabilizationDelay: 0.2,
        windowChangeGracePeriod: 0.5,
        boundsValidationInterval: 0.3
    )

    let knownQuirks: Set<AppQuirk> = []

    let usesUTF16TextIndices = false
}
