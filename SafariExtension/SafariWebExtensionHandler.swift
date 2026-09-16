import AppKit
import Darwin
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let request = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
              let client = request["client"] as? String, UUID(uuidString: client) != nil
        else { context.completeRequest(returningItems: nil); return }
        // Safari supplies the profile, never JavaScript. Replies return only to that request.
        let profile = (item.userInfo?[SFExtensionProfileKey] as? UUID)?.uuidString ?? "default"
        SafariBridge.shared.handle(request, key: profile + ":" + client) { payload in
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: payload]
            context.completeRequest(returningItems: [response])
        }
    }
}

private final class SafariBridge: @unchecked Sendable {
    static let shared = SafariBridge()
    private let queue = DispatchQueue(label: "io.textwarden.safari.bridge")
    private var channels: [String: Channel] = [:]
    private var timer: DispatchSourceTimer?

    private final class Channel: @unchecked Sendable {
        let socket: Int32
        var messages: [[String: Any]] = []
        var bytes = 0
        var touched = Date()
        var poll: (([String: Any]) -> Void)?
        var pollID: UUID?
        init(_ socket: Int32) {
            self.socket = socket
        }

        deinit { Darwin.close(socket) }
    }

    private init() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for (key, channel) in channels where Date().timeIntervalSince(channel.touched) > 30 {
                close(key)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func handle(_ request: [String: Any], key: String, reply: @escaping ([String: Any]) -> Void) {
        queue.async { [self] in
            do {
                if request["action"] as? String == "close" { close(key); reply(["ok": true]); return }
                if request["action"] as? String == "poll" {
                    guard let channel = channels[key], channel.poll == nil else { throw BrowserWireError.disconnected }
                    channel.touched = Date()
                    if !channel.messages.isEmpty { reply(drain(channel)); return }
                    let id = UUID()
                    channel.poll = reply; channel.pollID = id
                    queue.asyncAfter(deadline: .now() + 4) { [weak self, weak channel] in
                        guard let self, let channel, channel.pollID == id else { return }
                        flush(channel)
                    }
                    return
                }
                guard request["action"] as? String == "send", let object = request["message"] as? [String: Any] else { throw BrowserWireError.invalidMessage }
                let data = try JSONSerialization.data(withJSONObject: object)
                guard data.count <= BrowserWire.maximumLength else { throw BrowserWireError.oversizedMessage }
                var message = try JSONDecoder().decode(BrowserMessage.self, from: data)
                message.browserBundleID = "com.apple.Safari"
                try message.validate()
                let channel: Channel
                if let existing = channels[key] { channel = existing }
                else {
                    guard channels.count < 8, message.kind == "configuration", ["status", "connect"].contains(message.action),
                          let directory = BrowserWire.safariDirectory else { throw BrowserWireError.invalidMessage }
                    if message.action == "connect" {
                        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                        guard Bundle(url: app)?.bundleIdentifier == "io.textwarden.TextWarden" else { throw BrowserWireError.invalidMessage }
                        DispatchQueue.main.async {
                            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
                            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                        }
                    }
                    let path = directory.appendingPathComponent("bridge.sock").path
                    var descriptor: Int32?
                    let deadline = Date().addingTimeInterval(message.action == "connect" ? 5 : 0)
                    repeat {
                        descriptor = try? BrowserSocket.connect(path: path)
                        if descriptor == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
                    } while descriptor == nil && Date() < deadline
                    guard let descriptor else {
                        throw BrowserWireError.disconnected
                    }
                    channel = Channel(descriptor); channels[key] = channel
                    read(channel, key: key)
                }
                channel.touched = Date()
                try BrowserSocket.write(BrowserWire.encode(message), to: channel.socket)
                reply(["ok": true])
            } catch { close(key); reply(["error": "Mac app unavailable"]) }
        }
    }

    private func read(_ channel: Channel, key: String) {
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { queue.async { [self] in if channels[key] === channel { close(key) } } }
            var buffer = Data(), bytes = [UInt8](repeating: 0, count: 16384)
            do {
                while true {
                    let count = Darwin.read(channel.socket, &bytes, bytes.count)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { return }
                    buffer.append(contentsOf: bytes.prefix(count))
                    while let message = try BrowserWire.takeMessage(from: &buffer) {
                        let encoded = try JSONEncoder().encode(message)
                        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }
                        queue.sync {
                            guard channels[key] === channel else { return }
                            guard channel.messages.count < 64, channel.bytes + encoded.count <= BrowserWire.maximumLength else { close(key); return }
                            channel.messages.append(object); channel.bytes += encoded.count
                            if channel.poll != nil { flush(channel) }
                        }
                    }
                }
            } catch { /* Invalid frames close only this profile's connection; never log editor text. */ }
        }
    }

    private func drain(_ channel: Channel) -> [String: Any] {
        let messages = channel.messages
        channel.messages.removeAll(); channel.bytes = 0
        return ["messages": messages]
    }

    private func flush(_ channel: Channel) {
        let reply = channel.poll
        channel.poll = nil; channel.pollID = nil
        reply?(drain(channel))
    }

    private func close(_ key: String) {
        guard let channel = channels.removeValue(forKey: key) else { return }
        shutdown(channel.socket, SHUT_RDWR)
        channel.poll?(["error": "Mac app unavailable"])
        channel.poll = nil; channel.pollID = nil
    }
}
