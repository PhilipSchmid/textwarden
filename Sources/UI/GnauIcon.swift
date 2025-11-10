//
//  GnauIcon.swift
//  Gnau
//
//  Custom menu bar icon for Gnau grammar checker
//

import Cocoa

struct GnauIcon {
    /// Create the Gnau menu bar icon
    /// A pencil drawing a curved line, representing grammar checking
    static func create(size: NSSize = NSSize(width: 22, height: 22)) -> NSImage {
        let image = NSImage(size: size)

        image.lockFocus()

        // Set up graphics context
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw curved line (the text being checked)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3, y: 16))
        path.curve(
            to: NSPoint(x: 13, y: 13),
            controlPoint1: NSPoint(x: 6, y: 11),
            controlPoint2: NSPoint(x: 10, y: 11)
        )
        path.curve(
            to: NSPoint(x: 19, y: 12),
            controlPoint1: NSPoint(x: 15, y: 15),
            controlPoint2: NSPoint(x: 17, y: 15)
        )

        NSColor.black.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        // Draw pencil
        context.saveGState()
        context.translateBy(x: 14, y: 8)
        context.rotate(by: -30 * .pi / 180)

        // Pencil body
        let pencilBody = NSBezierPath(rect: NSRect(x: 0, y: 2, width: 6, height: 3))
        NSColor.black.setFill()
        pencilBody.fill()

        // Pencil tip
        let pencilTip = NSBezierPath()
        pencilTip.move(to: NSPoint(x: 0, y: 2.5))
        pencilTip.line(to: NSPoint(x: 0, y: 4.5))
        pencilTip.line(to: NSPoint(x: -2, y: 3.5))
        pencilTip.close()
        pencilTip.fill()

        // Eraser (slightly lighter)
        let eraser = NSBezierPath(rect: NSRect(x: 6, y: 2, width: 1.5, height: 3))
        NSColor.black.withAlphaComponent(0.7).setFill()
        eraser.fill()

        context.restoreGState()

        // Small checkmark (subtle quality indicator)
        let checkmark = NSBezierPath()
        checkmark.move(to: NSPoint(x: 18, y: 17))
        checkmark.line(to: NSPoint(x: 19.5, y: 18.5))
        checkmark.line(to: NSPoint(x: 22, y: 15.5))

        NSColor.black.withAlphaComponent(0.6).setStroke()
        checkmark.lineWidth = 1.2
        checkmark.stroke()

        image.unlockFocus()

        // Mark as template so macOS will adjust it for light/dark mode
        image.isTemplate = true

        return image
    }

    /// Create app icon (color version for About panel, etc.)
    static func createAppIcon(size: NSSize = NSSize(width: 256, height: 256)) -> NSImage {
        let image = NSImage(size: size)

        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let scale = size.width / 22.0

        context.setLineWidth(1.5 * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw curved line in blue
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3 * scale, y: 16 * scale))
        path.curve(
            to: NSPoint(x: 13 * scale, y: 13 * scale),
            controlPoint1: NSPoint(x: 6 * scale, y: 11 * scale),
            controlPoint2: NSPoint(x: 10 * scale, y: 11 * scale)
        )
        path.curve(
            to: NSPoint(x: 19 * scale, y: 12 * scale),
            controlPoint1: NSPoint(x: 15 * scale, y: 15 * scale),
            controlPoint2: NSPoint(x: 17 * scale, y: 15 * scale)
        )

        NSColor(red: 0.29, green: 0.56, blue: 0.89, alpha: 1.0).setStroke() // #4A90E2
        path.lineWidth = 1.5 * scale
        path.stroke()

        // Draw pencil in color
        context.saveGState()
        context.translateBy(x: 14 * scale, y: 8 * scale)
        context.rotate(by: -30 * .pi / 180)

        // Pencil wood body
        let pencilBody = NSBezierPath(rect: NSRect(x: 0, y: 2 * scale, width: 6 * scale, height: 3 * scale))
        NSColor(red: 0.96, green: 0.64, blue: 0.38, alpha: 1.0).setFill() // #F4A460
        pencilBody.fill()

        // Pencil tip
        let pencilTip = NSBezierPath()
        pencilTip.move(to: NSPoint(x: 0, y: 2.5 * scale))
        pencilTip.line(to: NSPoint(x: 0, y: 4.5 * scale))
        pencilTip.line(to: NSPoint(x: -2 * scale, y: 3.5 * scale))
        pencilTip.close()
        NSColor(red: 0.82, green: 0.41, blue: 0.12, alpha: 1.0).setFill() // #D2691E
        pencilTip.fill()

        // Graphite tip
        let graphite = NSBezierPath()
        graphite.move(to: NSPoint(x: -2 * scale, y: 3 * scale))
        graphite.line(to: NSPoint(x: -2 * scale, y: 4 * scale))
        graphite.line(to: NSPoint(x: -3 * scale, y: 3.5 * scale))
        graphite.close()
        NSColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1.0).setFill() // #2C2C2C
        graphite.fill()

        // Eraser
        let eraser = NSBezierPath(rect: NSRect(x: 6 * scale, y: 2 * scale, width: 1.5 * scale, height: 3 * scale))
        NSColor(red: 0.91, green: 0.12, blue: 0.39, alpha: 1.0).setFill() // #E91E63
        eraser.fill()

        context.restoreGState()

        image.unlockFocus()

        return image
    }
}
