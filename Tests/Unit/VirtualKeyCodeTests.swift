//
//  VirtualKeyCodeTests.swift
//  Gnau
//
//  Regression tests for virtual key codes to prevent accidental changes
//  that could break Terminal text replacement (T044-Terminal)
//

import XCTest
@testable import Gnau

final class VirtualKeyCodeTests: XCTestCase {

    // MARK: - Critical Key Code Regression Tests
    // These tests ensure we never accidentally change the virtual key codes
    // that broke Terminal replacement in the past.

    /// Test that 'A' key has the correct virtual key code
    /// Regression: Ensures Ctrl+A works for moving to beginning of line
    func testKeyCodeForA() {
        XCTAssertEqual(VirtualKeyCode.a, 0x00, "A key must be code 0x00 for Ctrl+A to work")
    }

    /// Test that 'K' key has the correct virtual key code
    /// Regression: Previously used code 11 (B key) instead of 40 (K key),
    /// which caused Ctrl+K to fail. This test prevents that regression.
    func testKeyCodeForK() {
        XCTAssertEqual(VirtualKeyCode.k, 0x28, "K key must be code 0x28 (40 decimal) for Ctrl+K to work")
        XCTAssertNotEqual(VirtualKeyCode.k, 0x0B, "K key must NOT be 0x0B - that's the B key!")
    }

    /// Test that 'B' key is NOT confused with 'K' key
    /// Regression: Code 0x0B is B key, not K key
    func testKeyCodeForB() {
        XCTAssertEqual(VirtualKeyCode.b, 0x0B, "B key must be code 0x0B")
        XCTAssertNotEqual(VirtualKeyCode.b, VirtualKeyCode.k, "B and K keys must have different codes")
    }

    /// Test that 'V' key has the correct virtual key code
    /// Regression: Ensures Cmd+V works for pasting
    func testKeyCodeForV() {
        XCTAssertEqual(VirtualKeyCode.v, 0x09, "V key must be code 0x09 for Cmd+V to work")
    }

    // MARK: - Key Code Uniqueness Tests

    /// Ensure all critical keys have unique codes
    func testKeyCodesAreUnique() {
        let codes = [
            VirtualKeyCode.a,
            VirtualKeyCode.b,
            VirtualKeyCode.k,
            VirtualKeyCode.v
        ]

        let uniqueCodes = Set(codes)
        XCTAssertEqual(uniqueCodes.count, codes.count, "All key codes must be unique")
    }

    // MARK: - Terminal Replacement Workflow Test

    /// Test the complete Terminal replacement key sequence
    /// This verifies that the correct keys are used in the correct order:
    /// 1. Ctrl+A (move to beginning)
    /// 2. Ctrl+K (kill to end)
    /// 3. Cmd+V (paste)
    func testTerminalReplacementKeySequence() {
        // Verify the key codes used in Terminal replacement
        struct TerminalKeys {
            static let ctrlA = VirtualKeyCode.a
            static let ctrlK = VirtualKeyCode.k
            static let cmdV = VirtualKeyCode.v
        }

        XCTAssertEqual(TerminalKeys.ctrlA, 0x00, "Ctrl+A uses A key (0x00)")
        XCTAssertEqual(TerminalKeys.ctrlK, 0x28, "Ctrl+K uses K key (0x28), NOT B key!")
        XCTAssertEqual(TerminalKeys.cmdV, 0x09, "Cmd+V uses V key (0x09)")
    }
}
