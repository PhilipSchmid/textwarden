//
//  FloatingTooltip.swift
//  TextWarden
//
//  Floating tooltip panel and modifiers for use in NSPanel/floating windows
//

import SwiftUI
import AppKit

// MARK: - Floating Tooltip Panel

/// Manages a separate floating NSPanel for tooltips that sits above the suggestion popover
/// This is required because nonactivatingPanel blocks native tooltip mechanisms
class TooltipPanel {
    static let shared = TooltipPanel()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    private init() {
        setupPanel()
    }

    private func setupPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel?.isOpaque = false
        panel?.backgroundColor = .clear
        panel?.hasShadow = true
        panel?.level = .floating + 10 // Higher than suggestion popover
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.ignoresMouseEvents = true // Let mouse events pass through
    }

    /// Show tooltip at specified screen position
    func show(_ text: String, at screenPosition: CGPoint, belowButton buttonFrame: CGRect) {
        guard let panel = panel else {
            return
        }

        // Cancel any pending hide
        hideTimer?.invalidate()
        hideTimer = nil

        let tooltipView = TooltipContentView(text: text)
        let hostingView = NSHostingView(rootView: tooltipView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 40)

        panel.contentView = hostingView

        // Measure actual tooltip size
        let fittingSize = hostingView.fittingSize
        let tooltipWidth = max(fittingSize.width, 100)
        let tooltipHeight = fittingSize.height

        // Position tooltip below button, centered horizontally
        let tooltipX = buttonFrame.midX - (tooltipWidth / 2)
        let tooltipY = buttonFrame.minY - tooltipHeight - 8 // 8pt spacing below button

        let tooltipFrame = NSRect(x: tooltipX, y: tooltipY, width: tooltipWidth, height: tooltipHeight)

        panel.setFrame(tooltipFrame, display: true)
        panel.order(.above, relativeTo: 0)
    }

    /// Hide tooltip with optional delay
    func hide(after delay: TimeInterval = 0) {
        hideTimer?.invalidate()
        hideTimer = nil

        if delay > 0 {
            hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.panel?.orderOut(nil)
            }
        } else {
            panel?.orderOut(nil)
        }
    }
}

// MARK: - Tooltip Content View

/// SwiftUI view for tooltip content
struct TooltipContentView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
            .fixedSize()
    }
}

// MARK: - Floating Tooltip Modifier

/// View modifier that shows tooltip in separate floating panel
struct FloatingTooltip: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: TooltipPositionKey.self,
                        value: geometry.frame(in: .global)
                    )
                }
            )
            .onPreferenceChange(TooltipPositionKey.self) { frame in
                if isHovering {
                    showTooltip(at: frame)
                }
            }
            .whenHovered { hovering in
                isHovering = hovering
                if !hovering {
                    TooltipPanel.shared.hide()
                }
            }
    }

    private func showTooltip(at frame: CGRect) {
        guard isHovering else { return }

        // Convert to screen coordinates (frame is already in global/screen coordinates)
        let screenFrame = frame
        let screenPosition = CGPoint(x: screenFrame.midX, y: screenFrame.minY)

        TooltipPanel.shared.show(text, at: screenPosition, belowButton: screenFrame)
    }
}

struct TooltipPositionKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    /// Add floating tooltip that works in NSPanel/floating windows
    func floatingTooltip(_ text: String) -> some View {
        modifier(FloatingTooltip(text: text))
    }
}
