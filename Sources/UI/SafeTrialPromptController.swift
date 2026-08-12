//
//  SafeTrialPromptController.swift
//  TextWarden
//
//  A contextual consent prompt for applications TextWarden has not verified yet.
//

import AppKit
import SwiftUI

@MainActor
final class SafeTrialPromptController: NSObject, NSPopoverDelegate {
    static let shared = SafeTrialPromptController()

    private static let contentSize = NSSize(width: 336, height: 122)
    static let fallbackCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .stationary,
        .fullScreenAuxiliary,
        .ignoresCycle,
    ]
    static let fallbackWindowLevel = NSWindow.Level.popUpMenu + 1

    private var popover: NSPopover?
    private var fallbackPanel: NSPanel?
    private weak var anchorButton: NSStatusBarButton?
    private var pendingContext: ApplicationContext?
    private var automaticallyPresentedApplications: Set<String> = []
    private var anchorMonitor: Timer?

    override private init() {}

    func present(for context: ApplicationContext, relativeTo button: NSStatusBarButton) {
        guard !automaticallyPresentedApplications.contains(context.bundleIdentifier) else { return }

        if pendingContext?.bundleIdentifier == context.bundleIdentifier,
           popover?.isShown == true || fallbackPanel?.isVisible == true
        {
            return
        }

        dismiss()
        automaticallyPresentedApplications.insert(context.bundleIdentifier)
        pendingContext = context
        anchorButton = button

        if isUsableAnchor(button) {
            showPopover(for: context, relativeTo: button)
        } else {
            showFallbackPanel(for: context)
        }
    }

    /// Menu-bar managers may temporarily move the real status item on screen when a proxy is
    /// clicked. If that happens, continue the same choice as a native anchored popover.
    func handleStatusItemClick(_ button: NSStatusBarButton) -> Bool {
        if popover?.isShown == true {
            dismiss()
            return true
        }

        guard fallbackPanel != nil,
              let context = pendingContext,
              isUsableAnchor(button)
        else {
            return false
        }

        showPopover(for: context, relativeTo: button)
        return true
    }

    static func isUsableAnchorFrame(
        _ anchorFrame: NSRect,
        screenFrame: NSRect,
        visibleFrame: NSRect
    ) -> Bool {
        guard anchorFrame.width >= 8, anchorFrame.height >= 8 else { return false }

        let intersection = anchorFrame.intersection(screenFrame)
        guard !intersection.isNull,
              intersection.width >= anchorFrame.width * 0.9,
              intersection.height >= anchorFrame.height * 0.9
        else {
            return false
        }

        // A genuine status item sits inside the menu-bar strip above the screen's
        // visible content. Menu-bar managers often park the original item offscreen
        // and draw a proxy in a separate panel; that original view is not a safe anchor.
        return anchorFrame.midY >= visibleFrame.maxY - 2
            && anchorFrame.maxY <= screenFrame.maxY + 1
    }

    func dismiss() {
        closePopover()
        closeFallbackPanel()
        clearPresentation()
    }

    func popoverDidClose(_: Notification) {
        clearPresentation()
    }

    private func keepPaused() {
        guard let context = pendingContext else { return }
        UserPreferences.shared.declineSafeTrial(for: context.bundleIdentifier)
        UserPreferences.shared.setPauseDuration(.indefinite, for: .application(context.bundleIdentifier))
        RuntimeHealthStore.shared.update(
            state: .inactive,
            reason: .appPause,
            context: context,
            action: .resume
        )
        dismiss()
    }

    private func clearPresentation() {
        anchorMonitor?.invalidate()
        anchorMonitor = nil
        anchorButton?.highlight(false)
        anchorButton = nil
        pendingContext = nil
        popover = nil
        fallbackPanel = nil
    }

    private func showPopover(for context: ApplicationContext, relativeTo button: NSStatusBarButton) {
        closeFallbackPanel()
        anchorMonitor?.invalidate()
        anchorMonitor = nil

        let popover = NSPopover()
        popover.contentSize = Self.contentSize
        popover.contentViewController = NSHostingController(
            rootView: promptView(for: context, showsPanelBackground: false)
        )
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self

        self.popover = popover
        anchorButton = button
        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showFallbackPanel(for context: ApplicationContext) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = Self.fallbackWindowLevel
        panel.collectionBehavior = Self.fallbackCollectionBehavior
        panel.contentViewController = NSHostingController(
            rootView: promptView(for: context, showsPanelBackground: true)
        )

        fallbackPanel = panel
        positionFallbackPanel(panel, for: context)
        panel.orderFrontRegardless()
        startAnchorMonitoring()

        Logger.info(
            "Showing safe-trial choice beside \(context.applicationName) because the TextWarden menu-bar item is hidden",
            category: Logger.ui
        )
    }

    private func promptView(
        for context: ApplicationContext,
        showsPanelBackground: Bool
    ) -> SafeTrialPromptView {
        SafeTrialPromptView(
            applicationName: context.applicationName,
            applicationIcon: NSRunningApplication(processIdentifier: context.processID)?.icon,
            showsPanelBackground: showsPanelBackground,
            onTry: { [weak self] in
                guard let self, let context = pendingContext else { return }
                AnalysisCoordinator.shared.startSafeTrial(for: context.bundleIdentifier)
                dismiss()
            },
            onKeepPaused: { [weak self] in
                self?.keepPaused()
            }
        )
    }

    private func startAnchorMonitoring() {
        anchorMonitor?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFallbackPresentation()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        anchorMonitor = timer
    }

    private func refreshFallbackPresentation() {
        guard let context = pendingContext,
              let panel = fallbackPanel
        else {
            return
        }

        if let button = anchorButton, isUsableAnchor(button) {
            showPopover(for: context, relativeTo: button)
            return
        }

        positionFallbackPanel(panel, for: context)
        let targetIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID
        if targetIsFrontmost, !panel.isVisible {
            panel.orderFrontRegardless()
        } else if !targetIsFrontmost, panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func positionFallbackPanel(_ panel: NSPanel, for context: ApplicationContext) {
        guard let quartzFrame = CGWindowHelper.getFrontmostWindowBounds(for: context.processID),
              let primaryScreen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint.zero) }) ?? NSScreen.screens.first
        else {
            positionAtVisibleScreenCorner(panel)
            return
        }

        let targetFrame = Self.cocoaFrame(fromQuartzFrame: quartzFrame, primaryScreenMaxY: primaryScreen.frame.maxY)
        guard let screen = NSScreen.screens.max(by: {
            $0.frame.intersection(targetFrame).area < $1.frame.intersection(targetFrame).area
        }) else {
            positionAtVisibleScreenCorner(panel)
            return
        }

        let origin = Self.fallbackPanelOrigin(
            panelSize: panel.frame.size,
            targetWindowFrame: targetFrame,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrameOrigin(origin)
    }

    static func cocoaFrame(fromQuartzFrame frame: NSRect, primaryScreenMaxY: CGFloat) -> NSRect {
        NSRect(
            x: frame.minX,
            y: primaryScreenMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func fallbackPanelOrigin(
        panelSize: NSSize,
        targetWindowFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSPoint {
        let inset: CGFloat = 16
        let edgeInset: CGFloat = 12
        let target = targetWindowFrame.intersection(visibleFrame)
        let reference = target.isNull ? visibleFrame : target

        let proposedX = reference.maxX - panelSize.width - inset
        let proposedY = reference.maxY - panelSize.height - inset
        return NSPoint(
            x: min(
                max(proposedX, visibleFrame.minX + edgeInset),
                visibleFrame.maxX - panelSize.width - edgeInset
            ),
            y: min(
                max(proposedY, visibleFrame.minY + edgeInset),
                visibleFrame.maxY - panelSize.height - edgeInset
            )
        )
    }

    private func positionAtVisibleScreenCorner(_ panel: NSPanel) {
        guard let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame else { return }
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.maxX - panel.frame.width - 16,
                y: visibleFrame.maxY - panel.frame.height - 16
            )
        )
    }

    private func closePopover() {
        let popover = popover
        popover?.delegate = nil
        popover?.close()
        self.popover = nil
    }

    private func closeFallbackPanel() {
        fallbackPanel?.close()
        fallbackPanel = nil
    }

    private func isUsableAnchor(_ button: NSStatusBarButton) -> Bool {
        guard !button.isHidden,
              button.alphaValue > 0.01,
              let window = button.window,
              window.isVisible,
              let screen = window.screen
        else {
            return false
        }

        let frameInWindow = button.convert(button.bounds, to: nil)
        let frameOnScreen = window.convertToScreen(frameInWindow)
        return Self.isUsableAnchorFrame(
            frameOnScreen,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }
}

private struct SafeTrialPromptView: View {
    let applicationName: String
    let applicationIcon: NSImage?
    let showsPanelBackground: Bool
    let onTry: () -> Void
    let onKeepPaused: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            applicationIdentity

            VStack(alignment: .leading, spacing: 0) {
                Text("Try TextWarden in \(applicationName)?")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text("\(applicationName) hasn’t been verified yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "checkmark.shield")
                        .frame(width: 15)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Indicator and copy-only fixes")
                            .foregroundStyle(.primary)
                        Text("Underlines and direct edits stay off")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                .padding(.top, 7)

                HStack(spacing: 8) {
                    Spacer()
                    Button("Keep Paused", action: onKeepPaused)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    Button("Try Safely", action: onTry)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
                .padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.init(top: 8, leading: 11, bottom: 7, trailing: 10))
        .frame(width: 336, height: 122, alignment: .topLeading)
        .background {
            if showsPanelBackground {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                }
            } else {
                // Native popovers remain translucent, but this semantic surface tint keeps
                // their content legible over both bright and dark windows.
                Color(nsColor: .windowBackgroundColor).opacity(0.86)
            }
        }
        .overlay {
            if showsPanelBackground {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var applicationIdentity: some View {
        if let applicationIcon {
            Image(nsImage: applicationIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        isNull ? 0 : width * height
    }
}
