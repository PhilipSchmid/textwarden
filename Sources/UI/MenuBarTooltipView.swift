//
//  MenuBarTooltipView.swift
//  TextWarden
//
//  Tooltip shown once after onboarding to help users find the menu bar icon
//

import AppKit
import SwiftUI

// MARK: - Menu Bar Tooltip View

/// A tooltip view with an arrow pointing up to the menu bar icon
struct MenuBarTooltipView: View {
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.98)
    }

    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color(white: 0.7) : Color(white: 0.4)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Arrow pointing up
            Triangle()
                .fill(backgroundColor)
                .frame(width: 20, height: 10)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: -1)

            // Main content
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image("TextWardenLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TextWarden is ready!")
                            .font(.headline)
                            .foregroundColor(textColor)
                        Text("Running in the background")
                            .font(.subheadline)
                            .foregroundColor(secondaryTextColor)
                    }
                }

                Text("TextWarden now runs silently in the background, checking your writing as you type. Click this menu bar icon anytime to:")
                    .font(.callout)
                    .foregroundColor(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    BulletPoint(text: "Pause or resume checking globally", colorScheme: colorScheme)
                    BulletPoint(text: "Control checking per application", colorScheme: colorScheme)
                    BulletPoint(text: "Open settings and view statistics", colorScheme: colorScheme)
                }

                Button(action: onDismiss) {
                    Text("Got it!")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(16)
            .background(backgroundColor)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .frame(width: 280)
    }
}

// MARK: - Helper Views

/// Triangle shape for the arrow
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Bullet point row
private struct BulletPoint: View {
    let text: String
    let colorScheme: ColorScheme

    private var textColor: Color {
        colorScheme == .dark ? Color(white: 0.85) : Color(white: 0.25)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            Text(text)
                .font(.callout)
                .foregroundColor(textColor)
        }
    }
}

// MARK: - Window Controller

/// Window controller for showing the menu bar tooltip
@MainActor
class MenuBarTooltipWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<MenuBarTooltipView>?
    private var clickMonitor: Any?

    /// Show the tooltip below the menu bar button
    /// - Parameter buttonFrame: The frame of the menu bar button in screen coordinates
    func showTooltip(near buttonFrame: NSRect) {
        // Don't show if already shown
        guard !UserPreferences.shared.hasShownMenuBarTooltip else {
            Logger.debug("Menu bar tooltip already shown, skipping", category: Logger.ui)
            return
        }

        // Dismiss any existing window
        dismissTooltip()

        let tooltipView = MenuBarTooltipView(
            onDismiss: { [weak self] in
                self?.dismissTooltip()
            }
        )

        hostingController = NSHostingController(rootView: tooltipView)

        // Create the window
        let window = NSWindow(contentViewController: hostingController!)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.hasShadow = false // We use SwiftUI shadow instead

        // Make the hosting view transparent
        if let hostingView = hostingController?.view {
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear
        }

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = .clear

        // Position below the menu bar button, centered on the button
        if let contentSize = hostingController?.view.fittingSize {
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let x = buttonFrame.midX - contentSize.width / 2
            let y = buttonFrame.minY - contentSize.height - 4

            // Ensure it stays on screen
            let adjustedX = max(screenFrame.minX + 10, min(x, screenFrame.maxX - contentSize.width - 10))
            let adjustedY = max(screenFrame.minY + 10, y)

            window.setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
        }

        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Mark as shown immediately
        UserPreferences.shared.hasShownMenuBarTooltip = true
        Logger.info("Showing menu bar tooltip after onboarding", category: Logger.ui)

        // Close when clicking outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window else { return }

            let clickLocation = event.locationInWindow
            let windowFrame = window.frame

            if !windowFrame.contains(clickLocation) {
                dismissTooltip()
            }
        }

        // Also close on local mouse events (clicks inside the app but outside tooltip)
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window else { return event }

            let clickLocationInScreen = NSEvent.mouseLocation
            let windowFrame = window.frame

            if !windowFrame.contains(clickLocationInScreen) {
                dismissTooltip()
            }
            return event
        }

        // Store local monitor reference for cleanup (using runtime association)
        objc_setAssociatedObject(self, "localMonitor", localMonitor, .OBJC_ASSOCIATION_RETAIN)
    }

    func dismissTooltip() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }

        if let localMonitor = objc_getAssociatedObject(self, "localMonitor") {
            NSEvent.removeMonitor(localMonitor)
            objc_setAssociatedObject(self, "localMonitor", nil, .OBJC_ASSOCIATION_RETAIN)
        }

        window?.close()
        window = nil
        hostingController = nil
    }
}
