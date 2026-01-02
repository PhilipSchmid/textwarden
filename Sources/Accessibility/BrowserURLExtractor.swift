//
//  BrowserURLExtractor.swift
//  TextWarden
//
//  Extracts the current URL from browser windows via Accessibility API
//

import AppKit
import Foundation

/// Extracts URLs from browser windows using the Accessibility API
class BrowserURLExtractor {
    static let shared = BrowserURLExtractor()

    private init() {}

    /// Extract the current URL from a browser application
    /// - Parameters:
    ///   - processID: The process ID of the browser
    ///   - bundleIdentifier: The bundle identifier of the browser
    /// - Returns: The current URL if found, nil otherwise
    func extractURL(processID: pid_t, bundleIdentifier: String) -> URL? {
        let appElement = AXUIElementCreateApplication(processID)

        // Try different extraction strategies based on browser
        if bundleIdentifier.contains("Safari") {
            return extractSafariURL(from: appElement)
        } else if isChromiumBased(bundleIdentifier) {
            return extractChromiumURL(from: appElement)
        } else if bundleIdentifier.contains("firefox") {
            return extractFirefoxURL(from: appElement)
        } else if bundleIdentifier.contains("thebrowser") { // Arc
            return extractArcURL(from: appElement)
        } else if bundleIdentifier.contains("Opera") {
            return extractChromiumURL(from: appElement) // Opera uses Chromium
        }

        // Fallback: try generic URL bar extraction
        return extractGenericURL(from: appElement)
    }

    /// Check if the browser is Chromium-based
    private func isChromiumBased(_ bundleIdentifier: String) -> Bool {
        let chromiumBrowsers = [
            "com.google.Chrome",
            "com.google.Chrome.beta",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "org.chromium.Chromium",
            "ai.perplexity.comet",
        ]
        return chromiumBrowsers.contains(bundleIdentifier)
    }

    // MARK: - Safari URL Extraction

    private func extractSafariURL(from appElement: AXUIElement) -> URL? {
        // Safari's URL is accessible via the focused window's document URL
        // or through the address bar text field

        // Strategy 1: Try to get URL from window's AXDocument attribute
        if let windows = getWindows(from: appElement) {
            for window in windows {
                // Try AXDocument first (most reliable for Safari)
                var documentValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, "AXDocument" as CFString, &documentValue) == .success,
                   let urlString = documentValue as? String,
                   let url = URL(string: urlString)
                {
                    Logger.debug("BrowserURLExtractor: Safari URL from AXDocument: \(url)", category: Logger.accessibility)
                    return url
                }
            }
        }

        // Strategy 2: Find the address bar and read its value
        if let urlString = findURLBarValue(in: appElement, identifiers: ["WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD", "AddressAndSearchField"]) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Safari URL from address bar: \(url)", category: Logger.accessibility)
                return url
            }
        }

        return nil
    }

    // MARK: - Chromium URL Extraction (Chrome, Edge, Brave, Vivaldi)

    private func extractChromiumURL(from appElement: AXUIElement) -> URL? {
        // Chromium browsers have an "omnibox" (address bar)
        // Try multiple strategies as Chrome's AX structure can vary

        // Strategy 1: Try to get AXURL from focused web area
        if let url = extractURLFromWebArea(from: appElement) {
            Logger.debug("BrowserURLExtractor: Chromium URL from web area: \(url)", category: Logger.accessibility)
            return url
        }

        // Strategy 2: Parse window title for URL (Chrome shows "Page Title - Google Chrome")
        // For GitHub it would be something like "Issues · user/repo - Google Chrome"
        // We can extract the domain from the title in some cases
        if let url = extractURLFromWindowTitle(from: appElement) {
            Logger.debug("BrowserURLExtractor: Chromium URL from window title: \(url)", category: Logger.accessibility)
            return url
        }

        // Strategy 3: Find the focused window and look for URL text field by identifiers
        if let urlString = findURLBarValue(in: appElement, identifiers: ["omnibox", "address", "urlbar", "locationbar"]) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Chromium URL from omnibox: \(url)", category: Logger.accessibility)
                return url
            }
        }

        // Strategy 4: Try to find toolbar and search for text fields there
        if let urlString = findURLInToolbar(from: appElement) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Chromium URL from toolbar: \(url)", category: Logger.accessibility)
                return url
            }
        }

        // Strategy 5: Search all text fields for URL-like content (most aggressive)
        if let urlString = findAnyURLTextField(from: appElement) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Chromium URL from text field scan: \(url)", category: Logger.accessibility)
                return url
            }
        }

        return nil
    }

    /// Extract URL from the web area element (works for some Chromium browsers)
    private func extractURLFromWebArea(from appElement: AXUIElement) -> URL? {
        guard let windows = getWindows(from: appElement) else { return nil }

        for window in windows {
            // Search for AXWebArea element
            if let url = findURLInWebArea(in: window, depth: 0, maxDepth: 10) {
                return url
            }
        }

        return nil
    }

    /// Recursively search for AXWebArea and extract URL
    private func findURLInWebArea(in element: AXUIElement, depth: Int, maxDepth: Int) -> URL? {
        guard depth < maxDepth else { return nil }

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        // Check if this is a web area
        if role == "AXWebArea" {
            // Try AXURL attribute
            var urlValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlValue) == .success,
               let urlString = urlValue as? String,
               let url = URL(string: urlString)
            {
                return url
            }

            // Try AXDocument attribute
            var docValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXDocument" as CFString, &docValue) == .success,
               let urlString = docValue as? String,
               let url = URL(string: urlString)
            {
                return url
            }
        }

        // Search children
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            if let url = findURLInWebArea(in: child, depth: depth + 1, maxDepth: maxDepth) {
                return url
            }
        }

        return nil
    }

    /// Extract URL from the window title (fallback for when other methods fail)
    private func extractURLFromWindowTitle(from appElement: AXUIElement) -> URL? {
        guard let windows = getWindows(from: appElement) else { return nil }

        for window in windows {
            // Check if this is the main/focused window
            var mainValue: CFTypeRef?
            let isMain = AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainValue) == .success &&
                (mainValue as? Bool) == true

            if !isMain { continue }

            // Get the window title
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let title = titleValue as? String
            else {
                continue
            }

            // Try to extract a URL or domain from the title
            // Common patterns:
            // - "github.com/user/repo - Google Chrome" (shows URL directly)
            // - "Page Title - Site Name - Google Chrome" (shows site name)

            // First, check if the title contains a URL-like pattern at the start
            let components = title.components(separatedBy: " - ")
            for component in components {
                let trimmed = component.trimmingCharacters(in: .whitespaces)
                if looksLikeURL(trimmed) {
                    if let url = parseURL(from: trimmed) {
                        return url
                    }
                }
            }

            // Try to find known domain patterns in the title
            // Map of title patterns to domains (handles cases like "GitHub" appearing as site name)
            let domainMappings: [(pattern: String, domain: String)] = [
                ("github.com", "github.com"),
                ("github", "github.com"), // Matches "... - GitHub" in title
                ("gitlab.com", "gitlab.com"),
                ("gitlab", "gitlab.com"),
                ("stackoverflow.com", "stackoverflow.com"),
                ("stack overflow", "stackoverflow.com"),
                ("google.com", "google.com"),
                ("twitter.com", "twitter.com"),
                ("x.com", "x.com"),
                ("facebook.com", "facebook.com"),
                ("linkedin.com", "linkedin.com"),
                ("linkedin", "linkedin.com"),
                ("reddit.com", "reddit.com"),
                ("reddit", "reddit.com"),
                ("youtube.com", "youtube.com"),
                ("youtube", "youtube.com"),
                ("amazon.com", "amazon.com"),
                ("wikipedia.org", "wikipedia.org"),
                ("wikipedia", "wikipedia.org"),
                ("medium.com", "medium.com"),
                ("notion.so", "notion.so"),
                ("notion", "notion.so"),
                ("slack.com", "slack.com"),
                ("slack", "slack.com"),
                ("trello.com", "trello.com"),
                ("jira", "atlassian.net"),
                ("confluence", "atlassian.net"),
                ("bitbucket", "bitbucket.org"),
                ("vercel.com", "vercel.com"),
                ("netlify.com", "netlify.com"),
                ("heroku.com", "heroku.com"),
                ("aws.amazon.com", "aws.amazon.com"),
                ("azure.microsoft.com", "azure.microsoft.com"),
                ("console.cloud.google.com", "console.cloud.google.com"),
            ]

            let lowercasedTitle = title.lowercased()
            for mapping in domainMappings {
                if lowercasedTitle.contains(mapping.pattern) {
                    return URL(string: "https://\(mapping.domain)")
                }
            }
        }

        return nil
    }

    /// Find any text field containing a URL (aggressive fallback)
    private func findAnyURLTextField(from appElement: AXUIElement) -> String? {
        guard let windows = getWindows(from: appElement) else { return nil }

        for window in windows {
            if let urlString = scanForURLTextField(in: window, depth: 0, maxDepth: 12) {
                return urlString
            }
        }

        return nil
    }

    /// Scan all elements for text fields containing URLs
    private func scanForURLTextField(in element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        // Check if this is any kind of text-holding element
        let isTextElement = role == kAXTextFieldRole as String ||
            role == kAXTextAreaRole as String ||
            role == "AXTextField" ||
            role == "AXComboBox" ||
            role == "AXStaticText"

        if isTextElement {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String,
               !value.isEmpty,
               looksLikeURL(value)
            {
                // Make sure it's not the content we're analyzing (should be short URL-like string)
                if value.count < 500 {
                    return value
                }
            }
        }

        // Search children
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            if let urlString = scanForURLTextField(in: child, depth: depth + 1, maxDepth: maxDepth) {
                return urlString
            }
        }

        return nil
    }

    // MARK: - Firefox URL Extraction

    private func extractFirefoxURL(from appElement: AXUIElement) -> URL? {
        // Firefox has a URL bar with different accessibility structure

        if let urlString = findURLBarValue(in: appElement, identifiers: ["urlbar", "urlbar-input", "identity-box"]) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Firefox URL: \(url)", category: Logger.accessibility)
                return url
            }
        }

        // Try toolbar approach
        if let urlString = findURLInToolbar(from: appElement) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Firefox URL from toolbar: \(url)", category: Logger.accessibility)
                return url
            }
        }

        return nil
    }

    // MARK: - Arc Browser URL Extraction

    private func extractArcURL(from appElement: AXUIElement) -> URL? {
        // Arc has a "unified field" for URL/search

        if let urlString = findURLBarValue(in: appElement, identifiers: ["unified", "address", "url"]) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Arc URL: \(url)", category: Logger.accessibility)
                return url
            }
        }

        return nil
    }

    // MARK: - Generic URL Extraction

    private func extractGenericURL(from appElement: AXUIElement) -> URL? {
        // Generic fallback: search for common URL bar patterns

        if let urlString = findURLBarValue(in: appElement, identifiers: ["url", "address", "location", "omnibox"]) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Generic URL: \(url)", category: Logger.accessibility)
                return url
            }
        }

        // Try toolbar approach as fallback
        if let urlString = findURLInToolbar(from: appElement) {
            if let url = parseURL(from: urlString) {
                Logger.debug("BrowserURLExtractor: Generic URL from toolbar: \(url)", category: Logger.accessibility)
                return url
            }
        }

        return nil
    }

    // MARK: - Helper Methods

    /// Get all windows from an application element
    private func getWindows(from appElement: AXUIElement) -> [AXUIElement]? {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return nil
        }
        return windows
    }

    /// Find a URL bar by searching for elements with matching identifiers
    private func findURLBarValue(in element: AXUIElement, identifiers: [String]) -> String? {
        // Get all windows
        guard let windows = getWindows(from: element) else { return nil }

        for window in windows {
            // Check if this is the focused window
            var focusedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXFocusedAttribute as CFString, &focusedValue) == .success,
               let isFocused = focusedValue as? Bool,
               !isFocused
            {
                // Skip non-focused windows for URL extraction
                // We want the URL from the active window
            }

            // Search for URL bar in this window
            if let urlString = searchForURLBar(in: window, identifiers: identifiers, depth: 0, maxDepth: 8) {
                return urlString
            }
        }

        return nil
    }

    /// Recursively search for a URL bar element
    private func searchForURLBar(in element: AXUIElement, identifiers: [String], depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }

        // Check this element's identifier and description
        var identifierValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)
        let identifier = (identifierValue as? String)?.lowercased() ?? ""

        var descriptionValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionValue)
        let description = (descriptionValue as? String)?.lowercased() ?? ""

        var roleDescValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescValue)
        let roleDesc = (roleDescValue as? String)?.lowercased() ?? ""

        // Check if this element matches URL bar patterns
        let combinedText = "\(identifier) \(description) \(roleDesc)"
        let isURLBar = identifiers.contains { keyword in
            combinedText.contains(keyword.lowercased())
        }

        // Also check for text field roles that might be URL bars
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        let isTextField = role == kAXTextFieldRole as String ||
            role == kAXTextAreaRole as String ||
            role == "AXTextField" ||
            role == "AXComboBox"

        if isURLBar, isTextField {
            // Try to get the value
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String,
               !value.isEmpty
            {
                // Validate it looks like a URL
                if looksLikeURL(value) {
                    return value
                }
            }
        }

        // Search children
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            if let urlString = searchForURLBar(in: child, identifiers: identifiers, depth: depth + 1, maxDepth: maxDepth) {
                return urlString
            }
        }

        return nil
    }

    /// Find URL in the toolbar area
    private func findURLInToolbar(from appElement: AXUIElement) -> String? {
        guard let windows = getWindows(from: appElement) else { return nil }

        for window in windows {
            // Look for toolbar element
            if let urlString = searchForURLInToolbar(in: window, depth: 0, maxDepth: 6) {
                return urlString
            }
        }

        return nil
    }

    /// Search for URL text field specifically within toolbar elements
    private func searchForURLInToolbar(in element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }

        // Check if this is a toolbar
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        let isToolbar = role == kAXToolbarRole as String || role == "AXToolbar"

        if isToolbar {
            // Search within toolbar for text fields that look like URL bars
            if let urlString = findFirstURLTextField(in: element, depth: 0, maxDepth: 4) {
                return urlString
            }
        }

        // Continue searching children
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            if let urlString = searchForURLInToolbar(in: child, depth: depth + 1, maxDepth: maxDepth) {
                return urlString
            }
        }

        return nil
    }

    /// Find the first text field that contains a URL-like value
    private func findFirstURLTextField(in element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        let isTextField = role == kAXTextFieldRole as String ||
            role == kAXTextAreaRole as String ||
            role == "AXTextField" ||
            role == "AXComboBox"

        if isTextField {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String,
               looksLikeURL(value)
            {
                return value
            }
        }

        // Search children
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            if let urlString = findFirstURLTextField(in: child, depth: depth + 1, maxDepth: maxDepth) {
                return urlString
            }
        }

        return nil
    }

    /// Check if a string looks like a URL
    private func looksLikeURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for common URL patterns
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return true
        }

        // Check for domain-like patterns (e.g., "github.com/...")
        let domainPattern = #"^[\w.-]+\.\w{2,}(/.*)?$"#
        if let regex = try? NSRegularExpression(pattern: domainPattern, options: .caseInsensitive) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        // Check for localhost
        if trimmed.hasPrefix("localhost") {
            return true
        }

        return false
    }

    /// Parse a URL string, adding scheme if necessary
    private func parseURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it already has a scheme, parse directly
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        // Add https:// for domain-like strings
        if looksLikeURL(trimmed) {
            return URL(string: "https://\(trimmed)")
        }

        return nil
    }
}
