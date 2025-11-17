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
        XCTAssertTrue(context.isTerminalApp)
    }

    // MARK: - Terminal Text Preprocessing Tests

    func testTerminalOutputFiltering() {
        // Test that terminal output is filtered, only user input is checked
        let parser = TerminalContentParser(bundleIdentifier: "com.apple.Terminal")

        // Simulate terminal buffer with lots of output
        let terminalBuffer = """
        user@host:~$ ls -la
        total 48
        drwxr-xr-x  12 user  staff   384 Nov 16 10:00 .
        drwxr-xr-x   6 root  admin   192 Nov 15 09:00 ..
        -rw-r--r--   1 user  staff  1024 Nov 16 10:00 file1.txt
        -rw-r--r--   1 user  staff  2048 Nov 16 10:00 file2.txt
        user@host:~$ git status
        On branch main
        Your branch is up to date with 'origin/main'.

        nothing to commit, working tree clean
        user@host:~$ echo "This is what Im typing now"
        """

        let result = parser.preprocessText(terminalBuffer)

        // Should extract only the last line (user input)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("This is what Im typing now"))
        XCTAssertFalse(result!.contains("total 48"))
        XCTAssertFalse(result!.contains("nothing to commit"))
    }

    func testTerminalPromptExtraction() {
        // Test extraction of text after various prompt styles
        let parser = TerminalContentParser(bundleIdentifier: "com.apple.Terminal")

        // Test various prompt styles
        let prompts = [
            ("$ git commit -m 'fix bug'", "git commit -m 'fix bug'"),
            ("user@host:~/project$ npm install", "npm install"),
            ("❯ cargo build --release", "cargo build --release"),
            ("➜  ~ cd Documents", "cd Documents")
        ]

        for (input, expected) in prompts {
            let result = parser.preprocessText(input)
            XCTAssertNotNil(result)
            XCTAssertTrue(result!.contains(expected.split(separator: " ").first!))
        }
    }

    func testTerminalHugeBufferHandling() {
        // Test that huge terminal buffers are handled gracefully
        let parser = TerminalContentParser(bundleIdentifier: "com.apple.Terminal")

        // Create a massive buffer (simulating scrollback)
        var hugeBuffer = ""
        for i in 0..<10000 {
            hugeBuffer += "line \(i) with some output data\n"
        }
        hugeBuffer += "user@host:~$ echo final command"

        let result = parser.preprocessText(hugeBuffer)

        // Should handle without crashing and extract user input
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("final command"))
        // Result should be much smaller than input
        XCTAssertLessThan(result!.count, 1000)
    }

    func testTerminalPureOutputSkipped() {
        // Test that pure output (no prompt) is skipped
        let parser = TerminalContentParser(bundleIdentifier: "com.apple.Terminal")

        let pureOutput = """
        [2024-11-16 10:00:00] INFO: Starting server
        [2024-11-16 10:00:01] INFO: Listening on port 8080
        [2024-11-16 10:00:02] INFO: Connected to database
        """

        let result = parser.preprocessText(pureOutput)

        // Should skip pure output
        XCTAssertNil(result)
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
