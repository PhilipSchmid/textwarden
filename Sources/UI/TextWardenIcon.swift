//
//  TextWardenIcon.swift
//  TextWarden
//
//  Custom menu bar icon for TextWarden grammar checker
//

import Cocoa

enum TextWardenIcon {
    /// A template lets macOS supply the right contrast, including when the menu is open.
    static func create(size: NSSize = NSSize(width: 22, height: 22)) -> NSImage {
        create(size: size, paused: false)
    }

    static func createPaused(size: NSSize = NSSize(width: 22, height: 22)) -> NSImage {
        create(size: size, paused: true)
    }

    private static func create(size: NSSize, paused: Bool) -> NSImage {
        let logo = NSImage(named: "FeatherLogo")
            ?? NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        let image = NSImage(size: size, flipped: false) { rect in
            logo?.draw(in: rect)
            if paused, let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.scaleBy(x: rect.width / 22, y: rect.height / 22)

                // Clear space around the bars keeps the pause distinct at menu-bar size.
                context.setBlendMode(.clear)
                context.addPath(CGPath(roundedRect: CGRect(x: 13, y: 0, width: 9, height: 9),
                                       cornerWidth: 2, cornerHeight: 2, transform: nil))
                context.fillPath()
                context.setBlendMode(.normal)
                context.setFillColor(NSColor.black.cgColor)
                for x in [15.0, 18.5] {
                    context.addPath(CGPath(roundedRect: CGRect(x: x, y: 1.5, width: 2, height: 6),
                                           cornerWidth: 0.75, cornerHeight: 0.75, transform: nil))
                    context.fillPath()
                }
                context.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        return image
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
