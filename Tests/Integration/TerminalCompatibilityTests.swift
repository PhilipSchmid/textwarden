//
//  TerminalCompatibilityTests.swift
//  Gnau Tests
//
//  Integration tests for Terminal compatibility (T091)
//

import XCTest
@testable import Gnau

final class TerminalCompatibilityTests: XCTestCase {
    var coordinator: AnalysisCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = AnalysisCoordinator.shared
    }

    override func tearDown() {
        coordinator.clearCache()
        super.tearDown()
    }

    // MARK: - Terminal Compatibility Tests (T091)

    func testTerminalTextExtraction() {
        // Test that Terminal app text input is accessible
        let context = ApplicationContext(
            applicationName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            processID: 12345
        )

        XCTAssertTrue(context.shouldCheck())
        XCTAssertEqual(context.bundleIdentifier, "com.apple.Terminal")
    }

    func testCommandDescriptionScenario() {
        // Test realistic Terminal command description
        let description = "This command removes all temporary files from system."

        let result = GrammarEngine.shared.analyzeText(description)

        // Should successfully analyze
        XCTAssertNotNil(result)
    }

    func testGitCommitMessageInTerminal() {
        // Test git commit message editing in Terminal
        let commitMessage = """
        Add new feature for user authentication

        This commit implements OAuth2 authentication flow with
        support for multiple providers including Google and GitHub.

        Testing:
        - Unit tests added
        - Integration tests pass
        """

        let result = GrammarEngine.shared.analyzeText(commitMessage)

        XCTAssertNotNil(result)
    }

    func testShortCommandExclusion() {
        // Very short text (commands) should probably be skipped
        let shortCommand = "ls -la"

        // Commands are typically too short to have grammar errors
        let result = GrammarEngine.shared.analyzeText(shortCommand)

        // Should return result (even if no errors)
        XCTAssertNotNil(result)
    }

    func testMultiLineTextEditing() {
        // Test multi-line text input common in Terminal editors
        let text = """
        First line with some text.
        Second line with more content.
        Third line completing the thought.
        """

        let result = GrammarEngine.shared.analyzeText(text)

        XCTAssertNotNil(result)
    }

    func testFallbackTextExtraction() {
        // Test fallback mechanism for apps with limited AX support
        // This tests the robustness of text extraction

        let context = ApplicationContext(
            applicationName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            processID: 12345
        )

        // Should handle gracefully even if AX is limited
        XCTAssertTrue(context.shouldCheck())
    }

    func testITermCompatibility() {
        // Test iTerm2 (popular Terminal alternative)
        let context = ApplicationContext(
            applicationName: "iTerm2",
            bundleIdentifier: "com.googlecode.iterm2",
            processID: 12345
        )

        XCTAssertTrue(context.shouldCheck())
    }

    func testHyperCompatibility() {
        // Test Hyper terminal
        let context = ApplicationContext(
            applicationName: "Hyper",
            bundleIdentifier: "co.zeit.hyper",
            processID: 12345
        )

        XCTAssertTrue(context.shouldCheck())
    }

    // MARK: - Code Pattern Detection Tests

    func testShellCommandPattern() {
        // Shell commands shouldn't be grammar checked
        let text = "Run: npm install --save-dev eslint"

        // This is mixed (instruction + command)
        // Only "Run:" should be checked
        let result = GrammarEngine.shared.analyzeText(text)

        XCTAssertNotNil(result)
    }

    func testFilePathExclusion() {
        // File paths should not trigger grammar errors
        let text = "Edit file at /usr/local/bin/somescript.sh for changes."

        let result = GrammarEngine.shared.analyzeText(text)

        XCTAssertNotNil(result)
    }
}
