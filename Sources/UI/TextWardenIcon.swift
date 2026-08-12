//
//  TextWardenIcon.swift
//  TextWarden
//
//  Custom menu bar icon for TextWarden grammar checker
//

import Cocoa

enum TextWardenIcon {
    /// Create the TextWarden menu bar icon (monochrome template for menu bar)
    static func create(size: NSSize = NSSize(width: 22, height: 22)) -> NSImage {
        // Load feather logo from asset catalog for menubar
        guard let logo = NSImage(named: "FeatherLogo") else {
            Logger.warning("FeatherLogo asset not found for menubar icon, using fallback", category: Logger.ui)
            return createFallbackMenuBarIcon(size: size)
        }

        let templateImage = NSImage(size: size)
        templateImage.lockFocus()

        // Draw the logo in black (will be adjusted by macOS for light/dark mode)
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()

            // Draw the logo scaled to fit
            logo.draw(in: NSRect(origin: .zero, size: size),
                      from: NSRect(origin: .zero, size: logo.size),
                      operation: .sourceOver,
                      fraction: 1.0)

            context.restoreGState()
        }

        templateImage.unlockFocus()

        // Mark as template so macOS will adjust it for light/dark mode
        templateImage.isTemplate = true

        return templateImage
    }

    /// Create a paused menu bar icon that keeps the feather recognizable.
    static func createPaused(size: NSSize = NSSize(width: 22, height: 22)) -> NSImage {
        // Load feather logo from asset catalog for menubar
        guard let logo = NSImage(named: "FeatherLogo") else {
            Logger.warning("FeatherLogo asset not found for menubar icon, using fallback", category: Logger.ui)
            return createFallbackMenuBarIconPaused(size: size)
        }

        let templateImage = NSImage(size: size)
        templateImage.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()

            // Lower both elements' emphasis while keeping the pause badge easy to recognize.
            logo.draw(in: NSRect(origin: .zero, size: size),
                      from: NSRect(origin: .zero, size: logo.size),
                      operation: .sourceOver,
                      fraction: 0.62)
            drawPauseBadge(in: context, size: size)

            context.restoreGState()
        }

        templateImage.unlockFocus()

        // Mark as template so macOS will adjust it for light/dark mode
        templateImage.isTemplate = true

        return templateImage
    }

    /// Fallback menubar icon if asset not found
    private static func createFallbackMenuBarIcon(size: NSSize) -> NSImage {
        let image = NSImage(size: size)

        image.lockFocus()

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

    /// Fallback paused menu bar icon when the feather asset is unavailable.
    private static func createFallbackMenuBarIconPaused(size: NSSize) -> NSImage {
        let baseImage = createFallbackMenuBarIcon(size: size)
        let image = NSImage(size: size)

        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        baseImage.draw(in: NSRect(origin: .zero, size: size),
                       from: NSRect(origin: .zero, size: baseImage.size),
                       operation: .sourceOver,
                       fraction: 0.62)
        drawPauseBadge(in: context, size: size)

        image.unlockFocus()

        // Mark as template so macOS will adjust it for light/dark mode
        image.isTemplate = true

        return image
    }

    /// Draw a softened pause badge with a small transparent separation ring.
    private static func drawPauseBadge(in context: CGContext, size: NSSize) {
        let diameter = max(7, min(size.width, size.height) * 0.39)
        let badgeRect = CGRect(
            x: size.width - diameter - 0.5,
            y: 0.5,
            width: diameter,
            height: diameter
        )
        let separationRect = badgeRect.insetBy(dx: -1, dy: -1)

        context.setBlendMode(.clear)
        context.fillEllipse(in: separationRect)

        context.setBlendMode(.normal)
        context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        context.fillEllipse(in: badgeRect)

        let barWidth = max(1, diameter * 0.14)
        let barHeight = diameter * 0.46
        let barGap = diameter * 0.12
        let centerX = badgeRect.midX
        let barY = badgeRect.midY - barHeight / 2

        context.setBlendMode(.clear)
        context.fill(CGRect(x: centerX - barGap - barWidth, y: barY, width: barWidth, height: barHeight))
        context.fill(CGRect(x: centerX + barGap, y: barY, width: barWidth, height: barHeight))
        context.setBlendMode(.normal)
    }

    /// Create app icon (color version for About panel, etc.) from asset catalog
    static func createAppIcon(size: NSSize = NSSize(width: 256, height: 256)) -> NSImage {
        // Load logo from asset catalog
        guard let logo = NSImage(named: "TextWardenLogo") else {
            Logger.warning("TextWardenLogo asset not found for app icon", category: Logger.ui)
            return createFallbackAppIcon(size: size)
        }

        // Resize logo to requested size
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        logo.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: logo.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        resizedImage.unlockFocus()

        return resizedImage
    }

    /// Fallback app icon if asset not found
    private static func createFallbackAppIcon(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        // Simple colored fallback
        if NSGraphicsContext.current?.cgContext != nil {
            let scale = size.width / 22.0
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3 * scale, y: 16 * scale))
            path.curve(to: NSPoint(x: 19 * scale, y: 12 * scale),
                       controlPoint1: NSPoint(x: 8 * scale, y: 11 * scale),
                       controlPoint2: NSPoint(x: 16 * scale, y: 15 * scale))
            NSColor.systemBlue.setStroke()
            path.lineWidth = 1.5 * scale
            path.stroke()
        }

        image.unlockFocus()
        return image
    }
}
