#!/usr/bin/env swift

import Foundation
import AppKit

// Test different font possibilities for Slack
let testStrings = [
    "Blub. This is a test Message",
    "Blub",
    ". This is a test Message"
]

let fonts: [(String, NSFont)] = [
    ("System 15pt", NSFont.systemFont(ofSize: 15.0)),
    ("System 14pt", NSFont.systemFont(ofSize: 14.0)),
    ("Helvetica 15pt", NSFont(name: "Helvetica", size: 15.0)!),
    ("Slack-Lato 15pt", NSFont(name: "Lato", size: 15.0) ?? NSFont.systemFont(ofSize: 15.0)),
    ("-apple-system 15pt", NSFont(name: "-apple-system", size: 15.0) ?? NSFont.systemFont(ofSize: 15.0))
]

for (name, font) in fonts {
    print("\n\(name):")
    let attributes: [NSAttributedString.Key: Any] = [.font: font]

    for text in testStrings {
        let width = (text as NSString).size(withAttributes: attributes).width
        print("  '\(text)': \(String(format: "%.2f", width))px")
    }
}

// Also test with tracking/kerning
print("\n\nWith tracking adjustments:")
let baseFont = NSFont.systemFont(ofSize: 15.0)
for tracking in [0.0, -0.5, 0.5, 1.0] {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .kern: tracking
    ]
    let width = ("Blub. This is a test Message" as NSString).size(withAttributes: attributes).width
    print("  Tracking \(tracking): \(String(format: "%.2f", width))px")
}
