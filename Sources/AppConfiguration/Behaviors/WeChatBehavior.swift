import Foundation

struct WeChatBehavior: AppBehavior {
    let bundleIdentifier = "com.tencent.xinWeChat"
    let displayName = "WeChat"

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
        movementThreshold: 50,
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

    let knownQuirks: Set<AppQuirk> = [.requiresBrowserStyleReplacement, .requiresUnchangedTextBeforePaste]
    let usesUTF16TextIndices = true
}
