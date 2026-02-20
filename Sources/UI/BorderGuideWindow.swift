import AppKit

/// Border guide window that shows the valid placement area during indicator dragging
/// The placement area is ~86pt wide band around the window edge
class BorderGuideWindow: NSPanel {
    private var borderView: GradientBorderView?

    /// Border width in points
    static let borderWidth: CGFloat = 100.0

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupBorderView()
    }

    private func setupBorderView() {
        let view = GradientBorderView()
        view.borderColor = Self.themeBasedColor()
        view.borderWidth = Self.borderWidth
        contentView = view
        borderView = view
    }

    /// Get color based on the current overlay theme preference
    /// Uses colors that contrast with typical window backgrounds while staying elegant
    private static func themeBasedColor() -> NSColor {
        let overlayTheme = UserPreferences.shared.overlayTheme

        let isDark: Bool = switch overlayTheme {
        case "Light":
            false
        case "Dark":
            true
        default: // "System"
            UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }

        if isDark {
            // Dark mode: Lighter gray to contrast with dark window backgrounds
            // Subtle warm tint for elegance
            return NSColor(hue: 30 / 360, saturation: 0.03, brightness: 0.45, alpha: 1.0)
        } else {
            // Light mode: Darker gray to contrast with light window backgrounds
            // Subtle cool tint matching popover style
            return NSColor(hue: 220 / 360, saturation: 0.04, brightness: 0.75, alpha: 1.0)
        }
    }

    /// Show border around the specified frame using theme-based color
    func showBorder(around frame: CGRect, color: NSColor? = nil) {
        Logger.debug("BorderGuideWindow.showBorder: Received frame = \(frame)", category: Logger.ui)

        // No need to expand frame - the gradient is drawn inward
        setFrame(frame, display: true)

        // Use provided color or theme-based color
        borderView?.borderColor = color ?? Self.themeBasedColor()
        borderView?.borderWidth = Self.borderWidth

        Logger.debug("BorderGuideWindow.showBorder: After setFrame, self.frame = \(self.frame)", category: Logger.ui)

        if let view = borderView {
            view.setNeedsDisplay(view.bounds)
            view.display()
        }
        orderFront(nil)

        Logger.debug("BorderGuideWindow: Window ordered front, isVisible=\(isVisible), level=\(level.rawValue)", category: Logger.ui)
    }

    func updateColor(_ color: NSColor) {
        borderView?.borderColor = color
        borderView?.needsDisplay = true
    }

    func hide() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Custom view that draws a gradient border band around the window edge
/// Solid color at the outer edge, fading to transparent toward the center
/// Uses rounded rectangles matching macOS window corner radius
private class GradientBorderView: NSView {
    var borderColor: NSColor = .gray {
        didSet {
            needsDisplay = true
        }
    }

    var borderWidth: CGFloat = 43.0 {
        didSet {
            needsDisplay = true
        }
    }

    /// Get macOS window corner radius based on OS version
    /// Note: Deployment target is macOS 14+, so we use the larger corner radius
    private var windowCornerRadius: CGFloat {
        // macOS 14+ (Sonoma/Sequoia) uses ~12pt corners
        12.0
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            Logger.debug("GradientBorderView.draw() - NO CONTEXT!", category: Logger.ui)
            return
        }

        let outerAlpha: CGFloat = 0.7
        let cornerRadius = windowCornerRadius

        // Get color components
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        borderColor.usingColorSpace(.deviceRGB)?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Draw the gradient border using concentric rounded rectangles
        // This creates a smooth fade from edge to center while respecting corner radius
        let steps = 100 // High number of steps for smooth gradient without visible banding
        let stepSize = borderWidth / CGFloat(steps)

        for i in 0 ..< steps {
            let inset = CGFloat(i) * stepSize
            let progress = CGFloat(i) / CGFloat(steps - 1)
            let currentAlpha = outerAlpha * (1.0 - progress) // Fade from outerAlpha to 0

            // Calculate corner radius for this step (shrinks as we go inward)
            let currentCornerRadius = max(0, cornerRadius - inset)

            // Create rounded rectangle path for this step
            let stepRect = bounds.insetBy(dx: inset, dy: inset)
            let path = CGPath(roundedRect: stepRect, cornerWidth: currentCornerRadius, cornerHeight: currentCornerRadius, transform: nil)

            // Create inner path for the next step (to create a ring)
            let innerInset = inset + stepSize
            let innerCornerRadius = max(0, cornerRadius - innerInset)
            let innerRect = bounds.insetBy(dx: innerInset, dy: innerInset)
            let innerPath = CGPath(roundedRect: innerRect, cornerWidth: innerCornerRadius, cornerHeight: innerCornerRadius, transform: nil)

            // Draw the ring between outer and inner paths
            context.saveGState()

            // Add outer path
            context.addPath(path)
            // Add inner path (will be subtracted due to even-odd rule)
            context.addPath(innerPath)

            // Use even-odd fill rule to create a ring
            context.clip(using: .evenOdd)

            // Fill with current alpha
            if let fillColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                       components: [red, green, blue, currentAlpha])
            {
                context.setFillColor(fillColor)
            }
            context.fill(bounds)

            context.restoreGState()
        }

        Logger.debug("GradientBorderView.draw() called - bounds: \(bounds), borderWidth: \(borderWidth), cornerRadius: \(cornerRadius)", category: Logger.ui)
    }
}
