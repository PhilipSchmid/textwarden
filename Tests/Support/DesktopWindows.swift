import XCTest

/// Call before creating a visible window or changing shared preferences for a presentation test.
func requireDesktopWindows(capturing screenshotVariable: String? = nil) throws {
    let environment = ProcessInfo.processInfo.environment
    if let screenshotVariable, let path = environment[screenshotVariable], !path.isEmpty { return }
    try XCTSkipUnless(environment["TEXTWARDEN_TEST_DESKTOP"] == "1", "Opens windows on the active desktop. Run make test-desktop to include this check.")
}
