import Foundation

/// Browser offsets are UTF-16. Never interpret them as Harper's scalar offsets.
struct BrowserMessage: Codable, Sendable {
    var version = 1
    let kind: String
    var session: String?
    var revision: Int?
    var origin: String?
    var pageURL: String?
    var pageEnabled: Bool?
    var text: String?
    var errorID: Int?
    var replacement: String?
    var start: Int?
    var end: Int?
    var errors: [BrowserIssue]?
    var status: String?
    var selectionRequired: Bool?
    var action: String?
    var showUnderlines: Bool?
    var underlineThickness: Double?

    var siteEnabled: Bool?
    var sitePausedUntil: Double?
    var siteInherited: Bool?
    var appPaused: Bool?
    var globalPaused: Bool?
    var theme: String?
    var checkingEnabled: Bool?

    var appVersion: String?
    var appBuild: String?
    var pause: String?
    var browserPause: String?
    var globalPause: String?
    var presentation: BrowserPresentation?
    var indicator: BrowserIndicatorGeometry?
    var browserBundleID: String?

    func isInvalidated(bySelection selection: BrowserMessage) -> Bool {
        guard selection.session == session else { return false }
        // Whole-editor style checks have no selection to preserve.
        return revision != selection.revision ||
            (start != nil && (start != selection.start || end != selection.end))
    }

    func validate() throws {
        guard version == 1,
              ["snapshot", "invalidate", "show", "applied", "release", "result", "replace", "status", "compose", "rewrite", "readability", "selection", "focus", "blur", "request", "configuration", "pausePage", "hoverEnd", "hoverKeep"].contains(kind),
              session.map({ UUID(uuidString: $0) != nil }) ?? true,
              revision.map({ $0 >= 0 }) ?? true,
              text.map({ $0.utf16.count <= 20000 }) ?? true,
              replacement.map({ $0.utf16.count <= 20000 }) ?? true,
              underlineThickness.map({ $0.isFinite && (1 ... 5).contains($0) }) ?? true
        else { throw BrowserWireError.invalidMessage }
        if kind == "configuration" {
            guard session != nil, let action,
                  ["status", "connect", "pausePageRule", "resumePage", "pauseSite", "resumeSite", "pauseBrowser", "resumeBrowser", "settings", "websites", "globalPause", "browserPause"].contains(action),
                  !["pauseSite", "resumeSite"].contains(action) || origin != nil
            else { throw BrowserWireError.invalidMessage }
        }
        if kind == "configuration", ["globalPause", "browserPause", "pauseSite"].contains(action), action != "pauseSite" || pause != nil {
            guard let pause, ["Active", "Paused for 1 Hour", "Paused for 24 Hours", "Paused Until Resumed"].contains(pause)
            else { throw BrowserWireError.invalidMessage }
        }
        try presentation?.validate()
        try indicator?.validate()
        if let browserBundleID, !BrowserWire.supportedBrowsers.contains(browserBundleID) {
            throw BrowserWireError.invalidMessage
        }
        if let pageURL {
            guard pageURL.utf8.count <= 8192, let page = URLComponents(string: pageURL),
                  ["http", "https"].contains(page.scheme), page.host != nil,
                  page.user == nil, page.password == nil, page.query == nil, page.fragment == nil,
                  let origin, let site = URLComponents(string: origin),
                  site.scheme == page.scheme, site.host == page.host, site.port == page.port
            else { throw BrowserWireError.invalidMessage }
        }
        if kind == "configuration", ["pausePageRule", "resumePage"].contains(action), pageURL == nil {
            throw BrowserWireError.invalidMessage
        }
        if kind == "pausePage" {
            guard session != nil, revision != nil, origin != nil, text == nil else { throw BrowserWireError.invalidMessage }
        }
        if ["configuration", "pausePage", "hoverEnd", "hoverKeep"].contains(kind), let origin {
            guard let url = URL(string: origin), ["https", "http"].contains(url.scheme), url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.isEmpty || url.path == "/"
            else { throw BrowserWireError.invalidMessage }
        }
        if ["snapshot", "compose", "rewrite", "readability"].contains(kind) {
            guard session != nil, revision != nil, text != nil,
                  let origin, let url = URL(string: origin),
                  ["https", "http"].contains(url.scheme), url.host != nil,
                  url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil,
                  url.path.isEmpty || url.path == "/"
            else { throw BrowserWireError.invalidMessage }
        }
        if ["compose", "rewrite", "readability", "selection"].contains(kind) {
            guard session != nil, revision != nil, let start, let end,
                  start >= 0, end >= start, end <= (text?.utf16.count ?? 20000)
            else { throw BrowserWireError.invalidMessage }
        }
    }
}

/// Normalized viewport bounds avoid assuming browser zoom or display scale.
struct BrowserIndicatorGeometry: Codable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let edge: String

    func validate() throws {
        guard [x, y, width, height].allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }),
              width > 0, height > 0, x + width <= 1.001, y + height <= 1.001,
              ["left", "right", "top", "bottom"].contains(edge)
        else { throw BrowserWireError.invalidMessage }
    }
}

struct BrowserPresentation: Codable, Sendable {
    let width: Double
    let sectionHeight: Double
    let cornerRadius: Double
    let hoverEnabled: Bool
    let hoverDelay: Int
    let styleEnabled: Bool
    let alwaysShow: Bool
    let grammarColor: String
    var styleCount: Int?
    var styleLoading = false

    func validate() throws {
        guard width.isFinite, (16 ... 64).contains(width), sectionHeight.isFinite, (16 ... 64).contains(sectionHeight),
              cornerRadius.isFinite, (0 ... 32).contains(cornerRadius), (0 ... 10000).contains(hoverDelay),
              ["red", "orange", "blue", "green"].contains(grammarColor),
              styleCount.map({ (0 ... 20000).contains($0) }) ?? true
        else { throw BrowserWireError.invalidMessage }
    }
}

struct BrowserIssue: Codable, Sendable {
    let id: Int
    let start: Int
    let end: Int
    let message: String
    let suggestions: [String]
    var underlineColor: String?
    var highlightColor: String?
}

enum BrowserWireError: Error {
    case invalidMessage, oversizedMessage, disconnected
}

/// Chrome native messaging and the local socket use the same bounded framing.
enum BrowserWire {
    static let supportedBrowsers = ["com.google.Chrome", "com.brave.Browser", "org.mozilla.firefox", "app.zen-browser.zen", "com.apple.Safari"]
    static let safariExtensionID = "io.textwarden.TextWarden.BrowserExtension"
    static let safariGroupID = "KSW8RTNTKJ.io.textwarden.browser"
    static var safariDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: safariGroupID)
    }

    static let geckoExtensionID = "browser@textwarden.io"
    static let maximumLength = 1024 * 1024

    static func encode(_ message: BrowserMessage) throws -> Data {
        try message.validate()
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= maximumLength else { throw BrowserWireError.oversizedMessage }
        var length = UInt32(payload.count).littleEndian
        var packet = withUnsafeBytes(of: &length) { Data($0) }
        packet.append(payload)
        return packet
    }

    static func takeMessage(from buffer: inout Data) throws -> BrowserMessage? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        guard length > 0, length <= maximumLength else { throw BrowserWireError.oversizedMessage }
        guard buffer.count >= length + 4 else { return nil }
        let message = try JSONDecoder().decode(BrowserMessage.self, from: buffer.subdata(in: 4 ..< length + 4))
        try message.validate()
        buffer.removeSubrange(0 ..< length + 4)
        return message
    }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TextWarden/BrowserBridge", isDirectory: true)
    }

    static var socketPath: String {
        directory.appendingPathComponent("bridge.sock").path
    }
}
