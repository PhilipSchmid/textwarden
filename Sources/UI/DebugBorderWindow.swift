//
//  DebugBorderWindow.swift
//  TextWarden
//
//  Debug visualization for element bounds during development
//

import AppKit

/// Debug window that draws a colored border around an area
/// Used during development to visualize element bounds
class DebugBorderWindow: NSPanel {
    static var debugWindows: [DebugBorderWindow] = []

    init(frame: NSRect, color: NSColor, label: String) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        hasShadow = false

        let borderView = DebugBorderView(color: color, label: label)
        contentView = borderView

        orderFront(nil)
        DebugBorderWindow.debugWindows.append(self)
    }

    static func clearAll() {
        for window in debugWindows {
            window.close()
        }
        debugWindows.removeAll()
    }
}

class DebugBorderView: NSView {
    let borderColor: NSColor
    let label: String

    init(color: NSColor, label: String) {
        borderColor = color
        self.label = label
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw thick border only (no fill)
        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(5.0)
        context.stroke(bounds.insetBy(dx: 2.5, dy: 2.5))

        // Draw label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: borderColor,
        ]
        let labelStr = label as NSString
        let textSize = labelStr.size(withAttributes: attrs)

        // Position blue box label (CGWindow coords) in top right, others in top left
        let xPosition: CGFloat = if label.contains("CGWindow") {
            bounds.width - textSize.width - 10
        } else {
            10
        }

        labelStr.draw(at: NSPoint(x: xPosition, y: bounds.height - 30), withAttributes: attrs)
    }
}
