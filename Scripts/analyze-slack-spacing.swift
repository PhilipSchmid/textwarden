#!/usr/bin/env swift

import Foundation
import AppKit

// Data-driven analysis of Slack's text rendering
// Goal: Calculate the actual spacing multiplier from measurements

print("=== Slack Text Spacing Analysis ===\n")

// Test string from screenshot: "Blub. This is a test Message"
let testString = "Blub. This is a test Message"
let fontSize: CGFloat = 15.0

// NSFont measurement (what we currently use)
let font = NSFont.systemFont(ofSize: fontSize)
let attributes: [NSAttributedString.Key: Any] = [.font: font]
let nsFontWidth = (testString as NSString).size(withAttributes: attributes).width

print("Text: '\(testString)'")
print("Character count: \(testString.count)")
print("NSFont (15pt) measured width: \(String(format: "%.2f", nsFontWidth))px")
print("")

// From user feedback, we know:
// - 0.95x multiplier: positioning is CLOSE but slightly too far RIGHT
// - 0.93x multiplier: positioning is too far LEFT
// - Sweet spot is likely between 0.93 and 0.95

print("Calibration Results from Testing:")
print("  1.00x (no adjustment): Too far RIGHT by ~4 characters")
print("  0.95x: Close, but slightly too far RIGHT")
print("  0.93x: Too far LEFT")
print("  Optimal: Likely 0.94x")
print("")

// Let's reverse-engineer what this tells us about Slack's rendering:
let multipliers = [0.93, 0.94, 0.95]

print("Width Predictions:")
for mult in multipliers {
    let predictedWidth = nsFontWidth * mult
    let perCharDiff = (nsFontWidth - predictedWidth) / CGFloat(testString.count)
    print("  \(String(format: "%.2f", mult))x: \(String(format: "%.2f", predictedWidth))px (saves \(String(format: "%.2f", perCharDiff))px per char)")
}
print("")

// Key insight: Slack's Chromium renderer likely uses different text shaping
// than macOS's CoreText. Common causes:
print("Potential Root Causes:")
print("1. Letter-spacing CSS property (most likely)")
print("2. Font metrics differences (web font vs system font)")
print("3. Chromium text shaping vs CoreText")
print("4. Sub-pixel rendering differences")
print("")

// Let's also test common Slack fonts
print("Testing Different Font Candidates:")
let fontCandidates: [(String, NSFont)] = [
    ("System 15pt", NSFont.systemFont(ofSize: 15.0)),
    ("Helvetica 15pt", NSFont(name: "Helvetica", size: 15.0)!),
    ("Lato 15pt", NSFont(name: "Lato-Regular", size: 15.0) ?? NSFont.systemFont(ofSize: 15.0)),
    ("San Francisco 15pt", NSFont(name: "SFProText-Regular", size: 15.0) ?? NSFont.systemFont(ofSize: 15.0))
]

for (name, font) in fontCandidates {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let width = (testString as NSString).size(withAttributes: attrs).width
    let multiplier = width / nsFontWidth
    print("  \(name): \(String(format: "%.2f", width))px (×\(String(format: "%.3f", multiplier)) vs System)")
}
print("")

print("RECOMMENDATION:")
print("Use 0.94x multiplier as a data-driven middle ground between:")
print("  - 0.95x (too far right)")
print("  - 0.93x (too far left)")
print("")
print("This suggests Slack renders text ~6% narrower than NSFont measures,")
print("likely due to letter-spacing CSS or font substitution.")
