//
//  WordBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Microsoft Word.
//
//  Word-specific characteristics:
//  - Native macOS app (Cocoa/AppKit)
//  - AXBoundsForRange works reliably (v16.104+)
//  - Flat AXTextArea (no child elements)
//  - Browser-style replacement needed
//

import Foundation

/// Complete behavior specification for Microsoft Word
struct WordBehavior: AppBehavior {
    let bundleIdentifier = "com.microsoft.Word"
    let displayName = "Microsoft Word"

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
        .hasCustomElementFinder,
    ]

    let usesUTF16TextIndices = false
}
