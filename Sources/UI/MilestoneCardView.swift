//
//  MilestoneCardView.swift
//  TextWarden
//
//  Celebratory card shown when a usage milestone is reached
//

import ConfettiSwiftUI
import Foundation
import SwiftUI

/// URLs for milestone card actions
private enum MilestoneURLs {
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/textwarden")!
}

// MARK: - Milestone Card View

/// Celebratory card view shown when a milestone is reached
struct MilestoneCardView: View {
    let milestone: Milestone
    let onDismiss: () -> Void
    let onSupport: () -> Void
    let onDisableForever: () -> Void

    @State private var confettiTrigger: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            VStack(spacing: 16) {
                // Header
                Text(milestone.headline)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 12)

                // TextWarden logo
                Image("TextWardenLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .shadow(color: .accentColor.opacity(0.3), radius: 10, x: 0, y: 0)

                // Milestone achievement
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text(milestone.emoji)
                            .font(.title2)
                        Text("\(milestone.threshold)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                        Text(milestone.type.label)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }

                    Text(milestone.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Divider()
                    .padding(.horizontal)

                // Support message
                VStack(spacing: 12) {
                    Text("Thank you for using TextWarden! 💜")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("If you find it helpful, please consider supporting future development.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    // Buy Me a Coffee button - same as About page
                    Button(action: onSupport) {
                        Image("BuyMeACoffeeButton")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }

                // Dismiss buttons
                VStack(spacing: 8) {
                    Button(action: onDismiss) {
                        Text("Maybe Later")
                    }
                    .buttonStyle(.bordered)

                    Button(action: onDisableForever) {
                        Text("Don't show milestone celebrations")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 12)
            }
            .padding(20)
            .frame(width: 300)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)

            // Confetti cannons from bottom corners
            HStack {
                // Bottom-left confetti cannon
                Color.clear
                    .frame(width: 1, height: 1)
                    .confettiCannon(
                        trigger: $confettiTrigger,
                        num: 40,
                        confettis: [.shape(.circle), .shape(.triangle), .shape(.square), .shape(.slimRectangle)],
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink],
                        confettiSize: 8,
                        rainHeight: 1000,
                        openingAngle: .degrees(50),
                        closingAngle: .degrees(70),
                        radius: 550,
                        repetitions: 2,
                        repetitionInterval: 0.5,
                        hapticFeedback: false
                    )

                Spacer()

                // Bottom-right confetti cannon
                Color.clear
                    .frame(width: 1, height: 1)
                    .confettiCannon(
                        trigger: $confettiTrigger,
                        num: 40,
                        confettis: [.shape(.circle), .shape(.triangle), .shape(.square), .shape(.slimRectangle)],
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink],
                        confettiSize: 8,
                        rainHeight: 1000,
                        openingAngle: .degrees(110),
                        closingAngle: .degrees(130),
                        radius: 550,
                        repetitions: 2,
                        repetitionInterval: 0.5,
                        hapticFeedback: false
                    )
            }
            .padding(.horizontal, 10)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            // Trigger confetti on appear
            confettiTrigger += 1
        }
        .background(Color.clear)
    }
}

/// Wrapper to ensure transparent background in NSHostingController
struct TransparentBackgroundView<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: Content

    func makeNSView(context _: Context) -> NSView {
        let hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        return hostingView
    }

    func updateNSView(_: NSView, context _: Context) {}
}

// MARK: - Window Controller

/// Window controller for showing the milestone card as a popover near the menu bar
@MainActor
class MilestoneCardWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<MilestoneCardView>?
    private var clickMonitor: Any?

    /// Show the milestone card near the menu bar button
    /// - Parameters:
    ///   - milestone: The milestone to celebrate
    ///   - buttonFrame: The frame of the menu bar button in screen coordinates
    ///   - isPreview: If true, dismissing won't mark the milestone as shown (for troubleshooting)
    func showMilestoneCard(_ milestone: Milestone, near buttonFrame: NSRect, isPreview: Bool = false) {
        // Dismiss any existing window
        dismissCard()

        let cardView = MilestoneCardView(
            milestone: milestone,
            onDismiss: { [weak self] in
                if !isPreview {
                    MilestoneManager.shared.dismissPendingMilestone()
                    UserStatistics.shared.milestoneDismissClicks += 1
                }
                self?.dismissCard()
            },
            onSupport: { [weak self] in
                NSWorkspace.shared.open(MilestoneURLs.buyMeACoffee)
                if !isPreview {
                    MilestoneManager.shared.dismissPendingMilestone()
                    UserStatistics.shared.milestoneSupportClicks += 1
                }
                self?.dismissCard()
            },
            onDisableForever: { [weak self] in
                MilestoneManager.shared.disableMilestonesForever()
                UserStatistics.shared.milestoneDisableClicks += 1
                self?.dismissCard()
            }
        )

        hostingController = NSHostingController(rootView: cardView)

        // Create the window
        let window = NSWindow(contentViewController: hostingController!)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.hasShadow = false // We'll use the SwiftUI shadow instead

        // Make the hosting view and its layer hierarchy transparent
        if let hostingView = hostingController?.view {
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear

            /// Also clear any sublayers that might have backgrounds
            func clearBackgrounds(in layer: CALayer) {
                layer.backgroundColor = .clear
                layer.sublayers?.forEach { clearBackgrounds(in: $0) }
            }
            if let layer = hostingView.layer {
                clearBackgrounds(in: layer)
            }
        }

        // Remove the default window content view background
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = .clear

        // Position below the menu bar button
        if let contentSize = hostingController?.view.fittingSize {
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let x = buttonFrame.midX - contentSize.width / 2
            let y = buttonFrame.minY - contentSize.height - 8

            // Ensure it stays on screen
            let adjustedX = max(screenFrame.minX + 10, min(x, screenFrame.maxX - contentSize.width - 10))
            let adjustedY = max(screenFrame.minY + 10, y)

            window.setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
        }

        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Close when clicking outside - use global mouse event monitor
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window else { return }

            // Check if click is outside the window
            let clickLocation = event.locationInWindow
            let windowFrame = window.frame

            // Convert click to screen coordinates (for global events, locationInWindow is in screen coordinates)
            if !windowFrame.contains(clickLocation) {
                Task { @MainActor in
                    self.dismissCard()
                }
            }
        }

        // Also close when window loses key status (e.g., user switches apps)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            let controller = self
            Task { @MainActor in
                controller?.dismissCard()
            }
        }
    }

    func dismissCard() {
        // Remove the click monitor
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }

        window?.close()
        window = nil
        hostingController = nil
    }
}

#Preview {
    MilestoneCardView(
        milestone: Milestone(type: .activeDays, threshold: 30),
        onDismiss: {},
        onSupport: {},
        onDisableForever: {}
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}
