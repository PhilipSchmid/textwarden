//
//  BrowserBehavior.swift
//  TextWarden
//
//  Base behavior for web browsers.
//
//  Browser-specific characteristics:
//  - Various rendering engines (WebKit, Blink, Gecko)
//  - Browser-style text replacement needed
//  - Child element traversal
//  - Fragile byte offsets
//
//  Note: Each browser bundle ID gets its own behavior instance
//  to maintain per-app isolation, but they share common settings.
//

import Foundation

/// Factory for creating browser-specific behaviors
enum BrowserBehaviorFactory {
    /// Browser bundle IDs
    static let browserBundleIDs: [String] = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Dev",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "company.thebrowser.Browser", // Arc
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.vivaldi.Vivaldi",
        "ai.perplexity.comet", // Perplexity Comet browser
    ]

    /// Create behaviors for all browsers
    static func createAllBrowserBehaviors() -> [AppBehavior] {
        browserBundleIDs.map { GenericBrowserBehavior(bundleIdentifier: $0) }
    }
}

/// Generic browser behavior - each browser gets its own instance
struct GenericBrowserBehavior: AppBehavior {
    let bundleIdentifier: String
    var displayName: String {
        switch bundleIdentifier {
        case "com.google.Chrome", "com.google.Chrome.canary": "Google Chrome"
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview": "Safari"
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition": "Firefox"
        case "com.microsoft.edgemac", "com.microsoft.edgemac.Dev": "Microsoft Edge"
        case "com.operasoftware.Opera", "com.operasoftware.OperaGX": "Opera"
        case "company.thebrowser.Browser": "Arc"
        case "com.brave.Browser", "com.brave.Browser.beta": "Brave"
        case "com.vivaldi.Vivaldi": "Vivaldi"
        case "ai.perplexity.comet": "Perplexity Comet"
        default: "Web Browser"
        }
    }

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
        .webBasedRendering,
        .requiresBrowserStyleReplacement,
        .requiresFullReanalysisAfterReplacement,
    ]

    let usesUTF16TextIndices = true
}
