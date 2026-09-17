#!/usr/bin/env swift
// Run `swift Scripts/generate-toolbar-icons.swift` after changing the menu-bar feather.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = try String(contentsOf: root.appendingPathComponent("Sources/UI/Assets.xcassets/FeatherLogo.imageset/textwarden_feather_logo.svg"), encoding: .utf8)

// Chromium has no template tinting. A narrow white edge preserves the silhouette
// on dark toolbars. Safari uses the unoutlined template and supplies its own tint.
for (variant, paint) in [
    ("", "fill=\"#333\" stroke=\"#fff\" stroke-width=\".9\" stroke-linejoin=\"round\" paint-order=\"stroke\""),
    ("-dark", "fill=\"#333\""),
] {
    let svg = source.replacingOccurrences(of: "fill=\"#000\"", with: paint)
    guard let image = NSImage(data: Data(svg.utf8)) else {
        throw NSError(domain: "ToolbarIcons", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot load feather SVG"])
    }
    for paused in [false, true] {
        let artwork: NSImage
        if paused {
            let masked = svg.replacingOccurrences(of: "<path ", with: "<path mask=\"url(#pause-space)\" ")
            let badge = "<defs><mask id=\"pause-space\"><rect width=\"22\" height=\"22\" fill=\"white\"/><rect x=\"13\" y=\"13\" width=\"9\" height=\"9\" rx=\"2\" fill=\"black\"/></mask></defs><g \(paint)><rect x=\"15\" y=\"14.5\" width=\"2\" height=\"6\" rx=\".75\"/><rect x=\"18.5\" y=\"14.5\" width=\"2\" height=\"6\" rx=\".75\"/></g></svg>"
            guard let result = NSImage(data: Data(masked.replacingOccurrences(of: "</svg>", with: badge).utf8)) else {
                throw NSError(domain: "ToolbarIcons", code: 4)
            }
            artwork = result
        } else { artwork = image }
        for size in [16, 32] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap)
            else { throw NSError(domain: "ToolbarIcons", code: 2) }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            artwork.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ToolbarIcons", code: 3)
            }
            let suffix = size == 16 ? "-16" : ""
            try png.write(to: root.appendingPathComponent("BrowserExtension/toolbar\(paused ? "-paused" : "")\(variant)\(suffix).png"))
        }
    }
}
