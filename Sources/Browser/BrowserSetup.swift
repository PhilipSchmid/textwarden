import CryptoKit
import Foundation

enum BrowserSetup {
    static func extensionFolder(for browser: String) -> URL? {
        let folder = ["org.mozilla.firefox", "app.zen-browser.zen"].contains(browser) ? "BrowserExtension-Firefox" : "BrowserExtension"
        return Bundle.main.resourceURL?.appendingPathComponent(folder, isDirectory: true)
    }

    static func extensionID(in app: URL) throws -> String {
        let manifest = app.appendingPathComponent("Contents/Resources/BrowserExtension/manifest.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any]
        guard let key = object?["key"] as? String, key.utf8.count <= 4096,
              let data = Data(base64Encoded: key), !data.isEmpty
        else { throw CocoaError(.fileReadCorruptFile) }
        // Chrome maps the first 128 bits of the public-key hash to letters a–p.
        let letters = Array("abcdefghijklmnop")
        return SHA256.hash(data: data).prefix(16).map { byte in
            String(letters[Int(byte >> 4)]) + String(letters[Int(byte & 15)])
        }.joined()
    }

    static func register(support: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"), app: URL = Bundle.main.bundleURL) throws {
        let identifier = try extensionID(in: app)
        let manager = FileManager.default
        let helper = app.appendingPathComponent("Contents/MacOS/TextWardenBrowserHost")
        guard manager.isExecutableFile(atPath: helper.path) else { throw CocoaError(.fileNoSuchFile) }
        let extensionManifest = app.appendingPathComponent("Contents/Resources/BrowserExtension-Firefox/manifest.json")
        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: extensionManifest)) as? [String: Any]
        let browserSettings = settings?["browser_specific_settings"] as? [String: Any]
        let gecko = browserSettings?["gecko"] as? [String: Any]
        guard gecko?["id"] as? String == BrowserWire.geckoExtensionID else { throw CocoaError(.fileReadCorruptFile) }
        let bridge = support.appendingPathComponent("TextWarden/BrowserBridge", isDirectory: true)
        let hosts = ["Google/Chrome", "BraveSoftware/Brave-Browser", "Mozilla", "zen"].map {
            support.appendingPathComponent($0 + "/NativeMessagingHosts", isDirectory: true)
        }
        for directory in [bridge] + hosts {
            if let attributes = try? manager.attributesOfItem(atPath: directory.path) {
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw CocoaError(.fileWriteNoPermission) }
            }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bridge.path)
        let identity = bridge.appendingPathComponent("extension-id")
        let manifests = hosts.map { $0.appendingPathComponent("io.textwarden.browser.json") }
        for file in [identity] + manifests {
            if let attributes = try? manager.attributesOfItem(atPath: file.path) {
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileWriteNoPermission) }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "name": "io.textwarden.browser",
            "description": "TextWarden local browser connection",
            "path": helper.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(identifier)/"],
        ], options: [.prettyPrinted, .sortedKeys])
        let geckoData = try JSONSerialization.data(withJSONObject: [
            "name": "io.textwarden.browser",
            "description": "TextWarden local browser connection",
            "path": helper.path,
            "type": "stdio",
            "allowed_extensions": [BrowserWire.geckoExtensionID],
        ], options: [.prettyPrinted, .sortedKeys])
        // Refresh moved/updated app paths without rewriting unchanged registration on every launch.
        for (index, manifest) in manifests.enumerated() {
            let registration = index < 2 ? data : geckoData
            if (try? Data(contentsOf: manifest)) != registration { try registration.write(to: manifest, options: .atomic) }
        }
        let identityData = Data((identifier + "\n").utf8)
        if (try? Data(contentsOf: identity)) != identityData { try identityData.write(to: identity, options: .atomic) }
        for file in [identity] + manifests {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
}
