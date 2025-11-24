import AppKit

/// Border guide window that shows the target window bounds during indicator dragging
class BorderGuideWindow: NSPanel {
    private var borderView: BorderView?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupBorderView()
    }

    private func setupBorderView() {
        let view = BorderView()
        view.borderColor = .systemRed
        self.contentView = view
        self.borderView = view
    }

    /// Show border around the specified frame with optional color
    func showBorder(around frame: CGRect, color: NSColor = .systemBlue) {
        Logger.debug("BorderGuideWindow.showBorder: Received frame = \(frame)", category: Logger.ui)

        let strokeWidth: CGFloat = 4.0
        let expandedFrame = frame.insetBy(dx: -strokeWidth, dy: -strokeWidth)

        setFrame(expandedFrame, display: true)
        borderView?.borderColor = color

        Logger.debug("BorderGuideWindow.showBorder: After setFrame, self.frame = \(self.frame)", category: Logger.ui)

        borderView?.setNeedsDisplay(borderView!.bounds)
        borderView?.display()
        orderFront(nil)

        Logger.debug("BorderGuideWindow: After orderFront, forcing another display", category: Logger.ui)
        borderView?.display()

        Logger.debug("BorderGuideWindow: Window ordered front, isVisible=\(isVisible), level=\(level.rawValue)", category: Logger.ui)
    }

    func updateColor(_ color: NSColor) {
        borderView?.borderColor = color
        borderView?.needsDisplay = true
    }

    func hide() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private class BorderView: NSView {
    var borderColor: NSColor = .systemRed {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            Logger.debug("BorderView.draw() - NO CONTEXT!", category: Logger.ui)
            return
        }

        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(5.0)
        context.stroke(bounds.insetBy(dx: 2.5, dy: 2.5))

        Logger.debug("BorderView.draw() called - bounds: \(bounds), color: \(borderColor)", category: Logger.ui)
    }
}
