//
//  OutlookBehavior.swift
//  TextWarden
//
//  Complete behavior specification for Microsoft Outlook.
//
//  Outlook-specific characteristics:
//  - Native macOS app (Cocoa/AppKit)
//  - Handles both subject field and compose body
//  - Deferred text extraction (prevents Copilot freeze)
//  - Frame validation required (Copilot chat panel dynamic)
//  - Text marker index offset (invisible characters)
//

import Foundation

/// Complete behavior specification for Microsoft Outlook
struct OutlookBehavior: AppBehavior {
    let bundleIdentifier = "com.microsoft.Outlook"
    let displayName = "Microsoft Outlook"

    let underlineVisibility = UnderlineVisibilityBehavior(
        showDelay: 0.15,
        boundsValidation: .requireStable(stabilizationDelay: 0.2),
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
        fallbackDetection: .periodicBoundsCheck(interval: 0.5)
    )

    let mouseBehavior = MouseBehavior(
        hideOnMouseMovement: false,
        movementThreshold: 50.0,
        dismissOnClickOutside: true,
        enableHoverDetection: true
    )

    let coordinateSystem = CoordinateSystemBehavior(
        axCoordinateSystem: .quartzTopLeft,
        lineHeightCompensation: .percentage(multiplier: 1.5) // Aptos font renders wider
    )

    let timingProfile = TimingProfile(
        analysisDebounce: 0.5, // Longer debounce to prevent freeze with Copilot
        boundsStabilizationDelay: 0.2,
        windowChangeGracePeriod: 0.5,
        boundsValidationInterval: 0.3
    )

    let knownQuirks: Set<AppQuirk> = [
        .requiresBrowserStyleReplacement,
        .requiresFocusPasteReplacement,
        .textMarkerIndexOffset,
        .hasCustomElementFinder,
        .hasFocusBounceProtection,
    ]

    let usesUTF16TextIndices = false
}
