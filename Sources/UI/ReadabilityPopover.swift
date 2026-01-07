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

    /// The popover panel (read-only access for hit testing)
    private(set) var panel: NSPanel?

    /// Timer for delayed hiding
    private var hideTimer: Timer?

    /// Event monitor for mouse clicks outside popover
    private var clickOutsideMonitor: Any?

    /// Tracking view for hover detection
    private var trackingView: ReadabilityTrackingView?

    /// Callback when mouse enters popover
    var onMouseEntered: (() -> Void)?

    /// Callback when mouse exits popover
    var onMouseExited: (() -> Void)?

    /// Current readability result
    @Published var result: ReadabilityResult?

    /// Current sentence-level analysis (optional, when feature is enabled)
    @Published var analysis: TextReadabilityAnalysis?

    /// Stored open direction from indicator
    private var openDirection: PopoverOpenDirection = .top

    /// Whether the popover was opened from the capsule indicator (persists until manually dismissed)
    @Published private(set) var openedFromIndicator: Bool = false

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
    /// - Parameters:
    ///   - position: Screen position to anchor the popover
    ///   - direction: Preferred direction for popover to open
    ///   - result: The readability result to display
    ///   - analysis: Optional sentence-level analysis
    ///   - fromIndicator: If true, popover persists until manually dismissed (opened from capsule)
    func show(at position: CGPoint, direction: PopoverOpenDirection = .top, result: ReadabilityResult, analysis: TextReadabilityAnalysis? = nil, fromIndicator: Bool = false) {
        Logger.debug("ReadabilityPopover: show at \(position), direction: \(direction), score: \(result.displayScore), fromIndicator: \(fromIndicator)", category: Logger.ui)

        // Don't show popover if a modal dialog is open (e.g., Print dialog, Save sheet)
        if ModalDialogDetector.isModalDialogPresent() {
            Logger.debug("ReadabilityPopover: Not showing - modal dialog is open", category: Logger.ui)
            return
        }

        self.result = result
        self.analysis = analysis
        openDirection = direction
        openedFromIndicator = fromIndicator

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

        let (origin, usedDirection) = PopoverPositioner.positionFromAnchor(
            at: anchorPoint,
            panelSize: panel.frame.size,
            direction: openDirection,
            constraintFrame: screen.visibleFrame
        )

        Logger.debug("ReadabilityPopover: positioning - requested: \(openDirection), used: \(usedDirection), origin: \(origin)", category: Logger.ui)
        panel.setFrameOrigin(origin)
    }

    /// Hide the popover
    func hide() {
        Logger.debug("ReadabilityPopover: hide", category: Logger.ui)

        hideTimer?.invalidate()
        hideTimer = nil
        openedFromIndicator = false
        removeClickOutsideMonitor()
        panel?.orderOut(nil)
    }

    /// Schedule hiding after delay
    /// Does nothing if popover was opened from indicator (must be manually dismissed)
    func scheduleHide(delay: TimeInterval = TimingConstants.popoverAutoHide) {
        hideTimer?.invalidate()

        // Don't auto-hide popovers opened from indicator
        guard !openedFromIndicator else {
            Logger.trace("ReadabilityPopover: skipping scheduleHide - opened from indicator", category: Logger.ui)
            return
        }

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
        // Create tracking view for hover detection
        let tracking = ReadabilityTrackingView(popover: self)
        tracking.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        trackingView = tracking

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
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = tracking

        self.panel = panel
    }

    private func rebuildContentView() {
        guard let panel, let trackingView else { return }

        let contentView = ReadabilityPopoverContentView(popover: self)
        let hostingView = NSHostingView(rootView: contentView)

        // Let the hosting view calculate its intrinsic size
        let fittingSize = hostingView.fittingSize
        let actualHeight = min(fittingSize.height, 500) // Cap at 500pt max

        // Update tracking view and hosting view sizes
        trackingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: actualHeight)
        hostingView.frame = trackingView.bounds
        hostingView.autoresizingMask = [.width, .height]

        // Add hosting view as subview of tracking view
        trackingView.subviews.forEach { $0.removeFromSuperview() }
        trackingView.addSubview(hostingView)

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

// MARK: - Readability Tracking View

/// Custom view that handles mouse tracking for the readability popover
class ReadabilityTrackingView: NSView {
    weak var popover: ReadabilityPopover?

    /// Track last size to avoid unnecessary tracking area updates during rebuild cycles
    private var lastTrackingSize: NSSize = .zero

    init(popover: ReadabilityPopover) {
        self.popover = popover
        super.init(frame: .zero)

        // Make the tracking view transparent with rounded corners
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        setupTracking()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // CRITICAL: Accept first mouse click without requiring panel activation
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    private func setupTracking() {
        // Initial setup - will be properly configured in updateTrackingAreas()
        updateTrackingAreas()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        // Only update tracking areas if size actually changed significantly
        // This prevents unnecessary recreation during rebuild cycles
        if abs(newSize.width - lastTrackingSize.width) > 1 || abs(newSize.height - lastTrackingSize.height) > 1 {
            lastTrackingSize = newSize
            updateTrackingAreas()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }

        // Only add tracking area if we have valid bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with _: NSEvent) {
        Logger.trace("ReadabilityPopover: Mouse ENTERED tracking view", category: Logger.ui)
        popover?.cancelHide()
        popover?.onMouseEntered?()
    }

    override func mouseExited(with _: NSEvent) {
        Logger.trace("ReadabilityPopover: Mouse EXITED tracking view", category: Logger.ui)
        popover?.onMouseExited?()
        popover?.scheduleHide()
    }
}
