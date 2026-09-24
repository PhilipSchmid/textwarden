import Darwin
@testable import TextWarden
import XCTest

final class BrowserMessageTests: XCTestCase {
    func testBrowserViewportUsesScrollContainerInsteadOfDocumentHeight() {
        let window = CGRect(x: 864, y: 33, width: 864, height: 1084)
        let viewport = CGRect(x: 864, y: 85, width: 864, height: 1032)
        for document in [CGRect(x: 864, y: 85, width: 864, height: 2168),
                         CGRect(x: 864, y: -915, width: 864, height: 2168),
                         CGRect(x: 864, y: 85, width: 864, height: 300)]
        {
            XCTAssertEqual(AccessibilityBridge.browserViewportFrame(webArea: document, scrollArea: viewport, window: window), viewport)
        }
        XCTAssertEqual(AccessibilityBridge.browserViewportFrame(webArea: viewport, scrollArea: nil, window: window), viewport)
        XCTAssertNil(AccessibilityBridge.browserViewportFrame(webArea: .zero, scrollArea: nil, window: window))
    }

    func testSelectionChangesPreserveWholeEditorStyleChecks() {
        let selection = BrowserMessage(kind: "selection", session: "editor", revision: 1, start: 3, end: 3)
        let style = BrowserMessage(kind: "snapshot", session: "editor", revision: 1)
        XCTAssertFalse(style.isInvalidated(bySelection: selection))
        var changedText = selection
        changedText.revision = 2
        XCTAssertTrue(style.isInvalidated(bySelection: changedText))
        for kind in ["compose", "rewrite", "readability"] {
            let target = BrowserMessage(kind: kind, session: "editor", revision: 1, start: 0, end: 3)
            XCTAssertTrue(target.isInvalidated(bySelection: selection))
            var unchanged = selection
            unchanged.start = 0
            XCTAssertFalse(target.isInvalidated(bySelection: unchanged))
            unchanged.session = "other-editor"
            XCTAssertFalse(target.isInvalidated(bySelection: unchanged))
        }
    }

    func testSameUserDoesNotAuthorizeAnUnrecognizedPeer() {
        var pair: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { pair.forEach { Darwin.close($0) } }
        XCTAssertTrue(BrowserSocket.sameUser(pair[0]))
        XCTAssertFalse(BrowserSocket.trustedPeer(pair[0], identifiers: ["io.textwarden.unrecognized-helper"]))
        XCTAssertFalse(BrowserSocket.trustedPeer(-1, identifiers: ["io.textwarden.TextWarden"]))
    }

    @MainActor
    func testIndicatorAnchorsOpenInwardAndValidateBounds() throws {
        let viewport = CGRect(x: -1200, y: 100, width: 1000, height: 800)
        for (edge, expected, direction) in [
            ("right", CGPoint(x: -325, y: 700), PopoverOpenDirection.left),
            ("left", CGPoint(x: -235, y: 700), PopoverOpenDirection.right),
            ("top", CGPoint(x: -280, y: 635), PopoverOpenDirection.bottom),
            ("bottom", CGPoint(x: -280, y: 765), PopoverOpenDirection.top),
        ] {
            let geometry = BrowserIndicatorGeometry(x: 0.9, y: 0.2, width: 0.04, height: 0.1, edge: edge)
            let anchor = BrowserIntegration.indicatorAnchor(geometry, viewport: viewport)
            XCTAssertEqual(anchor.point, expected)
            XCTAssertEqual(anchor.direction, direction)
            var packet = try BrowserWire.encode(BrowserMessage(kind: "show", indicator: geometry))
            XCTAssertEqual(try BrowserWire.takeMessage(from: &packet)?.indicator?.edge, edge)
        }
        for x in [-0.1, 1.0, Double.infinity, .nan] {
            XCTAssertThrowsError(try BrowserIndicatorGeometry(x: x, y: 0, width: 0.1, height: 0.1, edge: "right").validate())
        }
        XCTAssertThrowsError(try BrowserIndicatorGeometry(x: 0, y: 0, width: 0.1, height: 0.1, edge: "outside").validate())
    }

    func testBrowserPageAddressCannotSpoofItsOriginOrCarrySecrets() throws {
        var message = BrowserMessage(kind: "configuration", session: UUID().uuidString, origin: "http://localhost:8766", pageURL: "http://localhost:8766/Editor", action: "pausePageRule")
        XCTAssertNoThrow(try BrowserWire.encode(message))
        for page in ["http://localhost:8767/Editor", "http://localhost:8766/Editor?token=secret", "http://user:secret@localhost:8766/Editor", "file:///private/test"] {
            message.pageURL = page
            XCTAssertThrowsError(try BrowserWire.encode(message))
        }
    }

    func testPauseAndPillPresentationValidation() throws {
        var message = BrowserMessage(kind: "configuration", session: UUID().uuidString, action: "globalPause", pause: "Paused for 1 Hour")
        XCTAssertNoThrow(try BrowserWire.encode(message))
        message.pause = "Forever"
        XCTAssertThrowsError(try BrowserWire.encode(message))
        message = BrowserMessage(kind: "result", presentation: BrowserPresentation(width: 36, sectionHeight: 36, cornerRadius: 12, hoverEnabled: true, hoverDelay: 0, styleEnabled: true, alwaysShow: true, grammarColor: "orange"))
        message.presentation?.styleCount = 2
        message.presentation?.styleLoading = true
        var packet = try BrowserWire.encode(message)
        let state = try BrowserWire.takeMessage(from: &packet)?.presentation
        XCTAssertEqual(state?.styleCount, 2)
        XCTAssertEqual(state?.styleLoading, true)
        message.presentation?.styleCount = -1
        XCTAssertThrowsError(try BrowserWire.encode(message))
        message.presentation = BrowserPresentation(width: 36, sectionHeight: 36, cornerRadius: 12, hoverEnabled: true, hoverDelay: -1, styleEnabled: true, alwaysShow: true, grammarColor: "orange")
        XCTAssertThrowsError(try BrowserWire.encode(message))
        message.presentation = BrowserPresentation(width: 1000, sectionHeight: 36, cornerRadius: 12, hoverEnabled: true, hoverDelay: 0, styleEnabled: true, alwaysShow: true, grammarColor: "orange")
        XCTAssertThrowsError(try BrowserWire.encode(message))
    }

    func testBrowserIdentityAllowsOnlySupportedBrowsers() throws {
        for browser in ["com.google.Chrome", "com.brave.Browser", "org.mozilla.firefox", "app.zen-browser.zen", "com.apple.Safari"] {
            var packet = try BrowserWire.encode(BrowserMessage(kind: "status", browserBundleID: browser))
            XCTAssertEqual(try BrowserWire.takeMessage(from: &packet)?.browserBundleID, browser)
        }
        XCTAssertThrowsError(try BrowserWire.encode(BrowserMessage(kind: "status", browserBundleID: "unknown.browser")))
    }

    func testPausedPageOwnershipCarriesNoEditorText() throws {
        var message = BrowserMessage(kind: "pausePage", session: UUID().uuidString, revision: 0, origin: "https://example.com")
        XCTAssertNoThrow(try BrowserWire.encode(message))
        message.text = "Private editor text"
        XCTAssertThrowsError(try BrowserWire.encode(message))
        message.text = nil
        message.origin = "file:///tmp"
        XCTAssertThrowsError(try BrowserWire.encode(message))
    }

    func testConfigurationAllowsOnlyKnownActionsAndOrigins() throws {
        var message = BrowserMessage(kind: "configuration", session: UUID().uuidString, origin: "https://example.com", action: "pauseSite")
        XCTAssertNoThrow(try BrowserWire.encode(message))
        message.action = "execute"
        XCTAssertThrowsError(try BrowserWire.encode(message))
        message.action = "resumeSite"
        message.origin = nil
        XCTAssertThrowsError(try BrowserWire.encode(message))
        for origin in ["file:///tmp", "https://example.com/private", "https://example.com?secret", "https://user:secret@example.com"] {
            message.origin = origin
            XCTAssertThrowsError(try BrowserWire.encode(message))
        }
        message.origin = nil
        message.action = "settings"
        XCTAssertNoThrow(try BrowserWire.encode(message))
    }

    func testBrowserPresentationSettingsAreBounded() throws {
        var message = BrowserMessage(kind: "result", showUnderlines: false, underlineThickness: 3)
        var packet = try BrowserWire.encode(message)
        let decoded = try XCTUnwrap(BrowserWire.takeMessage(from: &packet))
        XCTAssertEqual(decoded.showUnderlines, false)
        XCTAssertEqual(decoded.underlineThickness, 3)
        for thickness in [0.0, 6.0, .infinity, .nan] {
            message.underlineThickness = thickness
            XCTAssertThrowsError(try BrowserWire.encode(message))
        }
    }

    func testBrowserRegistrationRestrictsIdentityAndRejectsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("app/Contents/MacOS/TextWardenBrowserHost")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let support = root.appendingPathComponent("support")
        let app = root.appendingPathComponent("app")
        let extensionManifest = app.appendingPathComponent("Contents/Resources/BrowserExtension/manifest.json")
        try FileManager.default.createDirectory(at: extensionManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertThrowsError(try BrowserSetup.register(support: support, app: app))
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("BrowserExtension/manifest.json")
        let geckoExtensionManifest = app.appendingPathComponent("Contents/Resources/BrowserExtension-Firefox/manifest.json")
        try FileManager.default.createDirectory(at: geckoExtensionManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: geckoExtensionManifest)
        var chromium = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
        chromium.removeValue(forKey: "browser_specific_settings")
        try JSONSerialization.data(withJSONObject: chromium).write(to: extensionManifest)
        let identifier = "cjihinlobjameeehbonjbheadlfmfnkk"
        XCTAssertEqual(try BrowserSetup.extensionID(in: app), identifier)
        try BrowserSetup.register(support: support, app: app)
        let manifest = support.appendingPathComponent("Google/Chrome/NativeMessagingHosts/io.textwarden.browser.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        XCTAssertEqual(json["allowed_origins"] as? [String], ["chrome-extension://\(identifier)/"])
        XCTAssertEqual(json["path"] as? String, helper.path)
        let braveManifest = support.appendingPathComponent("BraveSoftware/Brave-Browser/NativeMessagingHosts/io.textwarden.browser.json")
        XCTAssertEqual(try Data(contentsOf: braveManifest), try Data(contentsOf: manifest))
        for directory in ["Mozilla", "zen"] {
            let geckoManifest = support.appendingPathComponent("\(directory)/NativeMessagingHosts/io.textwarden.browser.json")
            let gecko = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: geckoManifest)) as? [String: Any])
            XCTAssertEqual(gecko["allowed_extensions"] as? [String], [BrowserWire.geckoExtensionID])
            XCTAssertNil(gecko["allowed_origins"])
            XCTAssertEqual(gecko["path"] as? String, helper.path)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: geckoManifest.path)[.posixPermissions] as? Int, 0o600)
        }
        let identity = support.appendingPathComponent("TextWarden/BrowserBridge/extension-id")
        XCTAssertEqual(try String(contentsOf: identity, encoding: .utf8), identifier + "\n")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: identity.path)[.posixPermissions] as? Int, 0o600)
        let modified = try FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date
        try BrowserSetup.register(support: support, app: app)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date, modified)
        // Upgrading from the preview repairs stale IDs and helper paths automatically.
        try Data("old registration".utf8).write(to: manifest)
        try Data("old extension".utf8).write(to: identity)
        try BrowserSetup.register(support: support, app: app)
        XCTAssertEqual(try String(contentsOf: identity, encoding: .utf8), identifier + "\n")
        let repaired = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        XCTAssertEqual(repaired["path"] as? String, helper.path)
        XCTAssertEqual(repaired["allowed_origins"] as? [String], ["chrome-extension://\(identifier)/"])
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: identity)
        XCTAssertThrowsError(try BrowserSetup.register(support: support, app: app))
    }

    func testSignedFirefoxExtensionMustBeARegularFile() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: app) }
        let extensionURL = app.appendingPathComponent("Contents/Resources/TextWarden-Browser-Extension-Firefox.xpi")
        try FileManager.default.createDirectory(at: extensionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertNil(BrowserSetup.signedFirefoxExtension(in: app))
        try Data("signed fixture".utf8).write(to: extensionURL)
        XCTAssertEqual(BrowserSetup.signedFirefoxExtension(in: app), extensionURL)
        try FileManager.default.removeItem(at: extensionURL)
        try FileManager.default.createSymbolicLink(at: extensionURL, withDestinationURL: extensionURL.deletingLastPathComponent())
        XCTAssertNil(BrowserSetup.signedFirefoxExtension(in: app))
    }

    func testWritingToolsRequireBoundedSelection() throws {
        for kind in ["compose", "rewrite", "readability"] {
            var message = BrowserMessage(kind: kind, session: UUID().uuidString, revision: 1,
                                         origin: "https://example.com", text: "A short passage.", start: 2, end: 7)
            XCTAssertNoThrow(try BrowserWire.encode(message))
            message.end = 99
            XCTAssertThrowsError(try BrowserWire.encode(message))
            message.end = 1
            XCTAssertThrowsError(try BrowserWire.encode(message))
            message.start = nil
            XCTAssertThrowsError(try BrowserWire.encode(message))
        }
    }

    func testAcceptedSocketUsesBlockingReader() {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        XCTAssertEqual(fcntl(descriptor, F_SETFL, O_NONBLOCK), 0)
        BrowserSocket.configure(descriptor)
        XCTAssertEqual(fcntl(descriptor, F_GETFL) & O_NONBLOCK, 0)
    }

    func testFramingAndValidation() throws {
        let message = BrowserMessage(kind: "snapshot", session: UUID().uuidString, revision: 2, origin: "https://example.com", text: "😀 We has a report.")
        let packet = try BrowserWire.encode(message)
        var buffer = Data(packet.prefix(3))
        XCTAssertNil(try BrowserWire.takeMessage(from: &buffer))
        buffer.append(packet.dropFirst(3))
        buffer.append(packet)
        XCTAssertEqual(try BrowserWire.takeMessage(from: &buffer)?.text, message.text)
        XCTAssertEqual(try BrowserWire.takeMessage(from: &buffer)?.revision, 2)
        XCTAssertTrue(buffer.isEmpty)

        var invalid = message
        invalid.version = 2
        XCTAssertThrowsError(try BrowserWire.encode(invalid))
        invalid = message
        invalid.origin = "file:///private/secret"
        XCTAssertThrowsError(try BrowserWire.encode(invalid))
        invalid = message
        invalid.text = String(repeating: "x", count: 20001)
        XCTAssertThrowsError(try BrowserWire.encode(invalid))
        var oversized = Data([255, 255, 255, 127])
        XCTAssertThrowsError(try BrowserWire.takeMessage(from: &oversized))
    }
}
