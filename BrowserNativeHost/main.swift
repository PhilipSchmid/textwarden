import AppKit
import Darwin
import Foundation
import Security

// The browser starts this helper, never the UI application's executable.
// The browser manifest and this check both restrict the calling extension.
do {
    let parentPID = getppid()
    let browserTeams = ["com.google.Chrome": "EQHXZ8M8AV", "com.brave.Browser": "KL8N8XSYF4",
                        "org.mozilla.firefox": "43AQ936H96", "app.zen-browser.zen": "9V5K9TP787"]
    guard let browserBundleID = NSRunningApplication(processIdentifier: parentPID)?.bundleIdentifier,
          let team = browserTeams[browserBundleID]
    else { throw BrowserWireError.invalidMessage }
    // A bundle ID alone is forgeable. Verify the live parent, and reject reparenting during lookup.
    var parent: SecCode?
    var requirement: SecRequirement?
    let expression = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(browserBundleID)\""
    guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: parentPID] as CFDictionary, [], &parent) == errSecSuccess,
          let parent,
          SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
          let requirement, SecCodeCheckValidity(parent, [], requirement) == errSecSuccess,
          getppid() == parentPID else { throw BrowserWireError.invalidMessage }
    let identifier = try String(contentsOf: BrowserWire.directory.appendingPathComponent("extension-id"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard identifier.count == 32, identifier.allSatisfy({ ("a" ... "p").contains(String($0)) }),
          CommandLine.arguments.count >= 2
    else { exit(1) }
    if ["org.mozilla.firefox", "app.zen-browser.zen"].contains(browserBundleID) {
        guard CommandLine.arguments.count >= 3, CommandLine.arguments[2] == BrowserWire.geckoExtensionID else { exit(1) }
    } else {
        guard CommandLine.arguments[1] == "chrome-extension://\(identifier)/" else { exit(1) }
    }
    // The first bounded frame explicitly distinguishes user-opened connections from background recovery.
    var firstBuffer = Data()
    var firstMessage: BrowserMessage?
    while firstMessage == nil {
        var byte: UInt8 = 0
        guard Darwin.read(STDIN_FILENO, &byte, 1) == 1 else { throw BrowserWireError.disconnected }
        firstBuffer.append(byte)
        guard firstBuffer.count <= 4096 else { throw BrowserWireError.invalidMessage }
        firstMessage = try BrowserWire.takeMessage(from: &firstBuffer)
    }
    guard let firstMessage, firstMessage.kind == "configuration", ["status", "connect"].contains(firstMessage.action) else { throw BrowserWireError.invalidMessage }
    if firstMessage.kind == "configuration", firstMessage.action == "connect" {
        let app = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app", Bundle(url: app)?.bundleIdentifier == "io.textwarden.TextWarden" else { throw BrowserWireError.invalidMessage }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }
    var connected: Int32?
    let deadline = Date().addingTimeInterval(5)
    repeat {
        connected = try? BrowserSocket.connect()
        if connected == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    } while connected == nil && Date() < deadline
    guard let socket = connected else {
        throw BrowserWireError.disconnected
    }
    var handshake = firstMessage
    handshake.browserBundleID = browserBundleID
    try BrowserSocket.write(BrowserWire.encode(handshake), to: socket)
    let finished = DispatchSemaphore(value: 0)
    for (input, output) in [(STDIN_FILENO, socket), (socket, STDOUT_FILENO)] {
        DispatchQueue.global(qos: .userInitiated).async {
            defer { finished.signal() }
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 16384)
            do {
                while true {
                    let count = Darwin.read(input, &chunk, chunk.count)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { break }
                    buffer.append(contentsOf: chunk.prefix(count))
                    while var message = try BrowserWire.takeMessage(from: &buffer) {
                        if input == STDIN_FILENO { message.browserBundleID = browserBundleID }
                        try BrowserSocket.write(BrowserWire.encode(message), to: output)
                    }
                    guard buffer.count <= BrowserWire.maximumLength + 4 else { break }
                }
            } catch {
                // Never write diagnostics or monitored content to the native-message stream.
            }
        }
    }
    finished.wait()
    shutdown(socket, SHUT_RDWR)
    Darwin.close(socket)
} catch {
    exit(1)
}
