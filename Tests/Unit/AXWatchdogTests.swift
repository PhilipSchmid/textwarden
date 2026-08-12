//
//  AXWatchdogTests.swift
//  TextWardenTests
//

@testable import TextWarden
import XCTest

final class AXWatchdogTests: XCTestCase {
    func testAtomicReservationAllowsOnlyOneCallPerProcess() throws {
        let bundleID = "io.textwarden.tests.ax-watchdog.\(UUID().uuidString)"
        let watchdog = AXWatchdog.shared

        let first = try XCTUnwrap(watchdog.tryBeginCall(bundleID: bundleID, attribute: "first"))
        XCTAssertNil(watchdog.tryBeginCall(bundleID: bundleID, attribute: "second"))

        watchdog.endCall(first)

        let next = try XCTUnwrap(watchdog.tryBeginCall(bundleID: bundleID, attribute: "next"))
        watchdog.endCall(next)
    }
}
