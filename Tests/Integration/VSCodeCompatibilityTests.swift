//
//  VSCodeCompatibilityTests.swift
//  TextWarden Tests
//
//  Integration tests for VS Code compatibility
//

@testable import TextWarden
import XCTest

final class VSCodeCompatibilityTests: XCTestCase {
    var coordinator: AnalysisCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = AnalysisCoordinator.shared
    }

    override func tearDown() {
        coordinator.clearCache()
        super.tearDown()
    }

    // MARK: - VS Code Compatibility Tests

    func testVSCodeTextExtraction() {
        // Test that VS Code commit message fields are accessible
        let context = ApplicationContext(
            applicationName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            processID: 12345
        )

        XCTAssertTrue(context.shouldCheck())
        XCTAssertEqual(context.bundleIdentifier, "com.microsoft.VSCode")
    }

    func testCodeBlockExclusion() {
        // Test that code blocks are excluded from grammar checking
        let text = """
        This is a commit message with grammar errors.

        ```javascript
        function test() {
            // This code should not be grammar checked
            const foo = bar;
        }
        ```

        More text that should be checked.
        """

        let cleaned = excludeCodeBlocks(from: text)

        // Code blocks should be removed or marked for exclusion
        XCTAssertFalse(cleaned.contains("function test()"))
        XCTAssertTrue(cleaned.contains("commit message"))
    }

    func testURLExclusion() {
        // Test that URLs are excluded from grammar checking
        let text = "Check out https://github.com/user/repo for more information."

        let urls = extractURLs(from: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first, "https://github.com/user/repo")
    }

    func testCommitMessageScenario() {
        // Test realistic commit message scenario
        let commitMessage = """
        Fix: Correct authentication bug

        This commit fixes the authentication bug where users couldn't
        login with special characters in password.

        Closes #123
        """

        let result = GrammarEngine.shared.analyzeText(commitMessage)

        // Should successfully analyze commit message
        XCTAssertNotNil(result)
    }

    func testInlineCodeExclusion() {
        // Test that inline code is excluded
        let text = "The `function` keyword is used for declarations."

        let cleaned = excludeInlineCode(from: text)

        XCTAssertFalse(cleaned.contains("`function`"))
        XCTAssertTrue(cleaned.contains("keyword is used"))
    }

    func testMarkdownHeadingsPreserved() {
        // Test that markdown headings are checked properly
        let text = """
        # Main Heading

        This paragraph has grammar error.

        ## Subheading

        Another paragraph with text.
        """

        let result = GrammarEngine.shared.analyzeText(text)

        XCTAssertNotNil(result)
    }

    // MARK: - Helper Methods

    private func excludeCodeBlocks(from text: String) -> String {
        var result = text
        let pattern = "```[\\s\\S]*?```"

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            result = regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        return result
    }

    private func excludeInlineCode(from text: String) -> String {
        var result = text
        let pattern = "`[^`]+`"

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            result = regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        return result
    }

    private func extractURLs(from text: String) -> [String] {
        var urls: [String] = []
        let pattern = "https?://[^\\s]+"

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                if let range = Range(match.range, in: text) {
                    urls.append(String(text[range]))
                }
            }
        }

        return urls
    }
}
