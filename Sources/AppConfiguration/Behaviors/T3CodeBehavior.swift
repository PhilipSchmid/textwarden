import Foundation

struct T3CodeBehavior: AppBehavior {
    let bundleIdentifier = "com.t3tools.t3code"
    let displayName = "T3 Code"

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
        hasReliableScrollEvents: false,
        fallbackDetection: .periodicBoundsCheck(interval: TimingConstants.textValidationInterval)
    )

    let mouseBehavior = MouseBehavior(
        hideOnMouseMovement: false,
        movementThreshold: 50,
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
        .webBasedRendering,
        .unreliableScrollEvents,
        .requiresBrowserStyleReplacement,
        .requiresUnchangedTextBeforePaste,
        .clearsEmptyDraftImmediately,
    ]
    let usesUTF16TextIndices = true
}
