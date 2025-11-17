//
//  TerminalContentParser.swift
//  Gnau
//
//  Terminal-specific content parser with intelligent text filtering
//  Prevents checking command output, only checks user input at the prompt
//

import Foundation
import AppKit

/// Terminal-specific content parser
/// Handles terminal apps to avoid checking massive output buffers
class TerminalContentParser: ContentParser {
    let bundleIdentifier: String
    let parserName: String

    /// Supported terminal apps
    static let supportedTerminals = [
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm2",
        "co.zeit.hyper": "Hyper",
        "dev.warp.Warp-Stable": "Warp",
        "org.alacritty": "Alacritty",
        "net.kovidgoyal.kitty": "Kitty",
        "com.github.wez.wezterm": "WezTerm",
        "io.github.rxhanson.Rectangle": "Rectangle", // Sometimes captures terminal text
    ]

    /// Offset of user input within the full terminal text
    /// Used to map error positions from preprocessed text to full text for replacement
    private(set) var userInputOffset: Int = 0

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
        self.parserName = Self.supportedTerminals[bundleIdentifier] ?? "Terminal"
    }

    func detectUIContext(element: AXUIElement) -> String? {
        return "terminal-prompt"
    }

    func estimatedFontSize(context: String?) -> CGFloat {
        // Terminals typically use monospace 12-13pt
        return 13.0
    }

    func spacingMultiplier(context: String?) -> CGFloat {
        // Monospace fonts have consistent spacing
        return 1.0
    }

    func horizontalPadding(context: String?) -> CGFloat {
        // Terminals usually have minimal padding
        return 5.0
    }

    func supports(bundleID: String) -> Bool {
        return Self.supportedTerminals.keys.contains(bundleID)
    }

    /// Disable visual underlines for terminals (positioning is unreliable)
    var disablesVisualUnderlines: Bool {
        return true
    }

    /// Return the offset where user input starts in the full terminal text
    /// This is used to map error positions from preprocessed text to full text during replacement
    var textReplacementOffset: Int {
        return userInputOffset
    }

    /// Override bounds adjustment to disable visual underlines in terminals
    /// Terminals have unreliable AX APIs and the preprocessed text doesn't match element positions
    /// Users can still access suggestions via keyboard shortcuts
    func adjustBounds(
        element: AXUIElement,
        errorRange: NSRange,
        textBeforeError: String,
        errorText: String,
        fullText: String
    ) -> AdjustedBounds? {
        // Return nil to disable visual underlines for terminals
        // The suggestion popover will still work via keyboard shortcuts
        Logger.debug("TerminalContentParser: Skipping visual underline (terminal apps use popover only)")
        return nil
    }

    /// Preprocess terminal text to extract only user input
    /// - Parameter text: Raw terminal buffer (can be huge with scrollback)
    /// - Returns: Filtered text containing only user input, or nil to skip
    func preprocessText(_ text: String) -> String? {
        // Skip empty text
        guard !text.isEmpty else { return nil }

        // Aggressive length limit for terminals (they can have 100k+ chars of scrollback)
        let maxTerminalLength = 5000
        if text.count > maxTerminalLength {
            Logger.info("TerminalContentParser: Text too long (\(text.count) chars), extracting last portion")
            // Take only the last N characters (most recent output + current prompt)
            let truncated = String(text.suffix(maxTerminalLength))
            return extractUserInput(from: truncated)
        }

        return extractUserInput(from: text)
    }

    /// Extract user input from terminal text
    /// Strategy: Find the last prompt and extract text after it
    private func extractUserInput(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)

        // Common shell prompt patterns
        let promptPatterns = [
            #"[\$%#>] "#,                    // Basic prompts: $ % # >
            #"[~\/\w-]+[\$%#>] "#,           // Path + prompt: ~/path$
            #"\w+@\w+.*?[\$%#>] "#,          // user@host$
            #"❯ "#,                           // Starship/modern prompts
            #"➜  "#,                          // Oh My Zsh
            #"λ "#,                           // Lambda prompt
        ]

        // Find the last line that looks like it has a prompt
        var lastPromptIndex = -1
        var promptRange: Range<String.Index>?

        for (index, line) in lines.enumerated().reversed() {
            // Skip empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }

            // Check if this line matches any prompt pattern
            for pattern in promptPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    lastPromptIndex = index
                    if let range = Range(match.range, in: line) {
                        promptRange = range
                        break
                    }
                }
            }

            if lastPromptIndex != -1 {
                break
            }
        }

        // If we found a prompt, extract text after it
        if lastPromptIndex != -1 {
            let promptLine = lines[lastPromptIndex]

            // Calculate offset: sum of all lines before the prompt line + prompt length
            var offset = 0
            for i in 0..<lastPromptIndex {
                offset += lines[i].count + 1  // +1 for newline
            }

            // Extract text after the prompt on the same line
            var userInput = ""
            if let range = promptRange {
                userInput = String(promptLine[range.upperBound...])
                // Add prompt length to offset
                offset += promptLine.distance(from: promptLine.startIndex, to: range.upperBound)
            } else {
                // Fallback: take everything after the first space
                if let firstSpace = promptLine.firstIndex(of: " ") {
                    userInput = String(promptLine[promptLine.index(after: firstSpace)...])
                    offset += promptLine.distance(from: promptLine.startIndex, to: promptLine.index(after: firstSpace))
                }
            }

            // Store the offset for use during text replacement
            self.userInputOffset = offset

            // Include any continuation lines (lines without prompts after the last prompt)
            if lastPromptIndex < lines.count - 1 {
                let continuationLines = lines[(lastPromptIndex + 1)...]
                for line in continuationLines {
                    // Only include if it doesn't look like output (no prompt pattern)
                    let hasPrompt = promptPatterns.contains { pattern in
                        (try? NSRegularExpression(pattern: pattern))?.firstMatch(
                            in: line,
                            range: NSRange(line.startIndex..., in: line)
                        ) != nil
                    }

                    if !hasPrompt && !line.isEmpty {
                        userInput += "\n" + line
                    }
                }
            }

            userInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)

            // Only return if we have meaningful input
            if userInput.count > 0 && userInput.count < 1000 {
                Logger.debug("TerminalContentParser: Extracted user input: \"\(userInput.prefix(100))...\" at offset \(self.userInputOffset)")
                return userInput
            }
        }

        // Fallback: If text is short enough and doesn't look like pure output, check it
        // This handles cases like git commit messages in nano/vim
        if text.count < 500 {
            // Check if text looks like command output (lots of special chars, numbers, paths)
            let outputIndicators = [
                #"^\s*\["#,           // Log lines
                #"^\s*\d+\s"#,        // Numbered lines
                #"^[rwx-]{10}"#,      // ls -l output
                #"^\S+:\s"#,          // Key: value output
            ]

            let looksLikeOutput = outputIndicators.contains { pattern in
                (try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines))?.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                ) != nil
            }

            if !looksLikeOutput {
                Logger.debug("TerminalContentParser: Short text without prompt, allowing: \"\(text.prefix(100))...\"")
                return text
            }
        }

        // Skip this text - it's likely just output
        Logger.debug("TerminalContentParser: Skipping terminal output")
        return nil
    }
}
