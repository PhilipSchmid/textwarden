//
//  ReadabilityPopover.swift
//  TextWarden
//
//  Popover for displaying Flesch Reading Ease score and interpretation
//

import AppKit
import Combine
import SwiftUI

// MARK: - Readability Popover Manager

/// Manages the readability score popover window
@MainActor
class ReadabilityPopover: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = ReadabilityPopover()

    // MARK: - Properties

    /// The popover panel
    private var panel: NSPanel?

    /// Timer for delayed hiding
    private var hideTimer: Timer?

    /// Event monitor for mouse clicks outside popover
    private var clickOutsideMonitor: Any?

    /// Current readability result
    @Published var result: ReadabilityResult?

    /// Current sentence-level analysis (optional, when feature is enabled)
    @Published var analysis: TextReadabilityAnalysis?

    /// Stored open direction from indicator
    private var openDirection: PopoverOpenDirection = .top

    // MARK: - Visibility

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Initialization

    override private init() {
        super.init()
    }

    // MARK: - Show/Hide

    /// Show the readability popover
    func show(at position: CGPoint, direction: PopoverOpenDirection = .top, result: ReadabilityResult, analysis: TextReadabilityAnalysis? = nil) {
        Logger.debug("ReadabilityPopover: show at \(position), direction: \(direction), score: \(result.displayScore)", category: Logger.ui)

        self.result = result
        self.analysis = analysis
        openDirection = direction

        if panel == nil {
            createPanel()
        }

        // Rebuild content first to get actual size
        rebuildContentView()

        // Position panel with actual content size
        positionPanel(at: position)

        // Make panel visible
        panel?.orderFrontRegardless()

        setupClickOutsideMonitor()
    }

    /// Position panel using anchor-based positioning with automatic direction flipping
    private func positionPanel(at anchorPoint: CGPoint) {
        guard let panel else { return }

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) }) ?? NSScreen.main
        guard let screen else { return }

        let panelSize = panel.frame.size
        let constraintFrame = screen.visibleFrame
        let padding: CGFloat = 20

        // Calculate origin for requested direction
        func originFor(direction: PopoverOpenDirection) -> CGPoint {
            switch direction {
            case .left:
                CGPoint(x: anchorPoint.x - panelSize.width, y: anchorPoint.y - panelSize.height / 2)
            case .right:
                CGPoint(x: anchorPoint.x, y: anchorPoint.y - panelSize.height / 2)
            case .top:
                CGPoint(x: anchorPoint.x - panelSize.width / 2, y: anchorPoint.y)
            case .bottom:
                CGPoint(x: anchorPoint.x - panelSize.width / 2, y: anchorPoint.y - panelSize.height)
            }
        }

        // Check if origin fits within screen bounds
        func fitsScreen(origin: CGPoint) -> Bool {
            let minX = constraintFrame.minX + padding
            let maxX = constraintFrame.maxX - panelSize.width - padding
            let minY = constraintFrame.minY + padding
            let maxY = constraintFrame.maxY - panelSize.height - padding
            return origin.x >= minX && origin.x <= maxX && origin.y >= minY && origin.y <= maxY
        }

        // Opposite direction for fallback
        func oppositeDirection(_ dir: PopoverOpenDirection) -> PopoverOpenDirection {
            switch dir {
            case .left: .right
            case .right: .left
            case .top: .bottom
            case .bottom: .top
            }
        }

        // Try requested direction first
        var origin = originFor(direction: openDirection)
        var usedDirection = openDirection

        // If doesn't fit, try opposite direction
        if !fitsScreen(origin: origin) {
            let oppositeDir = oppositeDirection(openDirection)
            let oppositeOrigin = originFor(direction: oppositeDir)
            if fitsScreen(origin: oppositeOrigin) {
                origin = oppositeOrigin
                usedDirection = oppositeDir
            }
        }

        // Final clamp to ensure it stays on screen
        origin.x = max(constraintFrame.minX + padding, min(origin.x, constraintFrame.maxX - panelSize.width - padding))
        origin.y = max(constraintFrame.minY + padding, min(origin.y, constraintFrame.maxY - panelSize.height - padding))

        Logger.debug("ReadabilityPopover: positioning - requested: \(openDirection), used: \(usedDirection), origin: \(origin)", category: Logger.ui)
        panel.setFrameOrigin(origin)
    }

    /// Hide the popover
    func hide() {
        Logger.debug("ReadabilityPopover: hide", category: Logger.ui)

        hideTimer?.invalidate()
        hideTimer = nil
        removeClickOutsideMonitor()
        panel?.orderOut(nil)
    }

    /// Schedule hiding after delay
    func scheduleHide(delay: TimeInterval = 0.3) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
    }

    /// Cancel any scheduled hide
    func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Panel Creation

    private let panelWidth: CGFloat = 280
    private let panelHeight: CGFloat = 300

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        self.panel = panel
    }

    private func rebuildContentView() {
        guard let panel else { return }

        let contentView = ReadabilityPopoverContentView(popover: self)
        let hostingView = NSHostingView(rootView: contentView)

        // Let the hosting view calculate its intrinsic size
        let fittingSize = hostingView.fittingSize
        let actualHeight = min(fittingSize.height, 500) // Cap at 500pt max

        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: actualHeight)
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: panelWidth, height: actualHeight))
    }

    // MARK: - Event Handling

    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel else { return event }

            // Check if click is outside the panel
            let clickLocation = event.locationInWindow
            if event.window == panel {
                // Click is in the panel window
                return event
            }

            // Convert to screen coordinates for proper comparison
            if let windowFrame = event.window?.frame {
                let screenLocation = CGPoint(
                    x: windowFrame.origin.x + clickLocation.x,
                    y: windowFrame.origin.y + clickLocation.y
                )

                if !panel.frame.contains(screenLocation) {
                    hide()
                }
            } else {
                // No window means click is somewhere else
                hide()
            }

            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}

// MARK: - Readability Popover Content View

struct ReadabilityPopoverContentView: View {
    @ObservedObject var popover: ReadabilityPopover
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.colorScheme) var systemColorScheme

    /// Effective color scheme based on user preference
    private var effectiveColorScheme: ColorScheme {
        switch preferences.overlayTheme {
        case "Light":
            .light
        case "Dark":
            .dark
        default:
            systemColorScheme
        }
    }

    /// App color scheme
    private var colors: AppColors {
        AppColors(for: effectiveColorScheme)
    }

    /// Base text size from preferences
    private var baseTextSize: CGFloat {
        CGFloat(preferences.suggestionTextSize)
    }

    /// Score color that's audience-relative when analysis is available
    private func scoreColor(for result: ReadabilityResult) -> NSColor {
        if let analysis = popover.analysis {
            return result.colorForAudience(analysis.targetAudience)
        }
        return result.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let result = popover.result {
                // Header with title and close button
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 14))
                        .foregroundColor(Color(scoreColor(for: result)))

                    Text("Readability Score")
                        .font(.system(size: baseTextSize * 0.9, weight: .semibold))
                        .foregroundColor(colors.textPrimary.opacity(0.85))

                    Spacer()

                    Button(action: { popover.hide() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(colors.textTertiary)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(colors.backgroundRaised.opacity(0.01))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Score display
                HStack(spacing: 12) {
                    // Large score number
                    Text("\(result.displayScore)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(Color(scoreColor(for: result)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.label)
                            .font(.system(size: baseTextSize, weight: .semibold))
                            .foregroundColor(colors.textPrimary)

                        Text("Flesch Reading Ease")
                            .font(.system(size: baseTextSize * 0.8))
                            .foregroundColor(colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                Divider()
                    .padding(.horizontal, 12)

                // Target Audience (if analysis available)
                if let analysis = popover.analysis {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "person.2")
                                .font(.system(size: 11))
                                .foregroundColor(colors.textSecondary)
                            Text("For: \(analysis.targetAudience.displayName)")
                                .font(.system(size: baseTextSize * 0.85, weight: .medium))
                                .foregroundColor(colors.textPrimary)
                            Text("(\(analysis.targetAudience.audienceDescription))")
                                .font(.system(size: baseTextSize * 0.8))
                                .foregroundColor(colors.textTertiary)
                        }

                        if analysis.complexSentenceCount > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.purple)
                                Text("\(analysis.complexSentenceCount) sentence\(analysis.complexSentenceCount == 1 ? "" : "s") may be too complex")
                                    .font(.system(size: baseTextSize * 0.85))
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    Divider()
                        .padding(.horizontal, 12)
                }

                // Interpretation
                Text(result.interpretation)
                    .font(.system(size: baseTextSize * 0.9))
                    .foregroundColor(colors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .fixedSize(horizontal: false, vertical: true)

                // Improvement tips (if score < 60)
                if result.displayScore < 60, !result.improvementTips.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tips to improve:")
                            .font(.system(size: baseTextSize * 0.85, weight: .medium))
                            .foregroundColor(colors.textPrimary)

                        ForEach(result.improvementTips.prefix(3), id: \.self) { tip in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundColor(colors.textSecondary)
                                Text(tip)
                                    .font(.system(size: baseTextSize * 0.85))
                                    .foregroundColor(colors.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                // Score legend
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .padding(.horizontal, 12)

                    ScoreLegendView(
                        colors: colors,
                        fontSize: baseTextSize * 0.75,
                        targetAudience: popover.analysis?.targetAudience
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

            } else {
                Text("No readability data")
                    .foregroundColor(colors.textSecondary)
                    .padding()
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [colors.backgroundGradientTop, colors.backgroundGradientBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                colors.border.opacity(0.5),
                                colors.border.opacity(0.2),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .colorScheme(effectiveColorScheme)
    }
}

// MARK: - Score Legend View

struct ScoreLegendView: View {
    let colors: AppColors
    let fontSize: CGFloat
    let targetAudience: TargetAudience?

    /// Generate audience-relative legend items based on the threshold
    private var legendItems: [(range: String, label: String, color: NSColor)] {
        guard let audience = targetAudience else {
            // Fallback to default ranges if no audience specified
            return [
                ("70+", "Easy to read", .systemGreen),
                ("50-69", "Moderate", .systemYellow),
                ("30-49", "Difficult", .systemOrange),
                ("0-29", "Very difficult", .systemRed),
            ]
        }

        let threshold = Int(audience.minimumFleschScore)

        return [
            ("\(threshold + 10)+", "Excellent", .systemGreen),
            ("\(threshold)-\(threshold + 9)", "Meeting target", .systemYellow),
            ("\(threshold - 10)-\(threshold - 1)", "Slightly complex", .systemOrange),
            ("<\(threshold - 10)", "Too complex", .systemRed),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(legendItems, id: \.range) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(item.color))
                        .frame(width: 6, height: 6)

                    Text(item.range)
                        .font(.system(size: fontSize, weight: .medium).monospacedDigit())
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 50, alignment: .leading)

                    Text(item.label)
                        .font(.system(size: fontSize))
                        .foregroundColor(colors.textTertiary)
                }
            }
        }
    }
}
