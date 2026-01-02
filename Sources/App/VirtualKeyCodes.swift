//
//  VirtualKeyCodes.swift
//  TextWarden
//
//  macOS Virtual Key Code Constants
//  Reference: /System/Library/Frameworks/Carbon.framework/.../HIToolbox.framework/.../Events.h
//

import CoreGraphics
import Foundation

/// Virtual key codes for keyboard simulation via CGEventCreateKeyboardEvent
/// These identify physical keys on the keyboard (ANSI US layout)
enum VirtualKeyCode {
    // MARK: - Letter Keys

    static let a: CGKeyCode = 0x00 // A key
    static let b: CGKeyCode = 0x0B // B key
    static let e: CGKeyCode = 0x0E // E key (14 decimal)
    static let k: CGKeyCode = 0x28 // K key (40 decimal)
    static let v: CGKeyCode = 0x09 // V key

    // MARK: - Special Keys

    static let `return`: CGKeyCode = 0x24
    static let tab: CGKeyCode = 0x30
    static let space: CGKeyCode = 0x31
    static let delete: CGKeyCode = 0x33
    static let escape: CGKeyCode = 0x35

    // MARK: - Arrow Keys

    static let leftArrow: CGKeyCode = 0x7B
    static let rightArrow: CGKeyCode = 0x7C
    static let downArrow: CGKeyCode = 0x7D
    static let upArrow: CGKeyCode = 0x7E
}

// MARK: - Helper Extensions

extension CGEventFlags {
    /// macOS Bug Workaround: Control modifier flag doesn't work in CGEventPost
    /// unless you also add SecondaryFn flag. This is a documented macOS bug.
    /// See: https://stackoverflow.com/questions/27484330/simulate-keypress-using-swift
    static func controlWithWorkaround() -> CGEventFlags {
        [.maskControl, .maskSecondaryFn]
    }
}
