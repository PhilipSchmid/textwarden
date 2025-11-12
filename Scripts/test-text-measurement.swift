#!/usr/bin/env swift

import Foundation
import AppKit

// Test text measurement for Slack
let testText = "Blub"
let fontSize: CGFloat = 15.0

let font = NSFont.systemFont(ofSize: fontSize)
let attributes: [NSAttributedString.Key: Any] = [.font: font]

let measuredWidth = (testText as NSString).size(withAttributes: attributes).width

print("Text: '\(testText)'")
print("Font: System \(fontSize)pt")
print("Measured width: \(measuredWidth)px")
print("")
print("With 1.15x multiplier: \(measuredWidth * 1.15)px")
print("Without multiplier: \(measuredWidth)px")
