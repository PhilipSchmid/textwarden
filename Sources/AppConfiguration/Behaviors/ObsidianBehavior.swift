import Foundation

struct ObsidianBehavior: AppBehavior {
    let bundleIdentifier = "md.obsidian"
    let displayName = "Obsidian"

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
        boundsStabilizationDelay: 0.2,
        windowChangeGracePeriod: 0.5,
        boundsValidationInterval: 0.3
    )

    let knownQuirks: Set<AppQuirk> = [
        .exposesViewportText,
        .webBasedRendering,
        .hasFocusBounceProtection,
        .requiresBrowserStyleReplacement,
    ]
    let usesUTF16TextIndices = true
}
