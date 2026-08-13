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

    func testAtomicReservationBoundsGlobalConcurrency() throws {
        let watchdog = AXWatchdog.shared
        let prefix = "io.textwarden.tests.ax-watchdog.global.\(UUID().uuidString)"
        var tokens: [AXCallToken] = []
        defer { tokens.forEach(watchdog.endCall) }

        for index in 0 ..< 4 {
            let token = try XCTUnwrap(
                watchdog.tryBeginCall(bundleID: "\(prefix).\(index)", attribute: "call")
            )
            tokens.append(token)
        }

        XCTAssertNil(watchdog.tryBeginCall(bundleID: "\(prefix).overflow", attribute: "call"))
    }

    func testLateCompletionCannotClearNewerCall() throws {
        let bundleID = "io.textwarden.tests.ax-watchdog.late.\(UUID().uuidString)"
        let watchdog = AXWatchdog.shared

        let first = try XCTUnwrap(watchdog.tryBeginCall(bundleID: bundleID, attribute: "first"))
        watchdog.endCall(first)

        let second = try XCTUnwrap(watchdog.tryBeginCall(bundleID: bundleID, attribute: "second"))
        watchdog.endCall(first)
        XCTAssertNil(watchdog.tryBeginCall(bundleID: bundleID, attribute: "third"))
        watchdog.endCall(second)
    }

    func testAXClientPerformsAndReleasesAtomicTransaction() throws {
        let bundleID = "io.textwarden.tests.ax-client.\(UUID().uuidString)"
        let watchdog = AXWatchdog.shared

        let execution = try XCTUnwrap(
            AXClient.perform(bundleID: bundleID, attribute: "outer") {
                watchdog.tryBeginCall(bundleID: bundleID, attribute: "nested")
            }
        )
        XCTAssertNil(execution.value)

        let next = try XCTUnwrap(watchdog.tryBeginCall(bundleID: bundleID, attribute: "next"))
        watchdog.endCall(next)
    }

    func testAXClientHelpersReuseOneLogicalProcessSlot() throws {
        let bundleID = "io.textwarden.tests.ax-client.reentrant.\(UUID().uuidString)"

        let outer = try XCTUnwrap(
            AXClient.perform(bundleID: bundleID, attribute: "parser") {
                AXClient.perform(bundleID: bundleID, attribute: "frame") { 42 }
            }
        )

        XCTAssertEqual(outer.value?.value, 42)
        let next = try XCTUnwrap(
            AXWatchdog.shared.tryBeginCall(bundleID: bundleID, attribute: "next")
        )
        AXWatchdog.shared.endCall(next)
    }
}
