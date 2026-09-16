import Darwin
import Foundation

/// Each connection has one reader and one serialized writer, both off the UI thread.
final class BrowserConnection: @unchecked Sendable {
    let id = UUID()
    @MainActor var browserBundleID: String?
    private let descriptor: Int32
    private let writer = DispatchQueue(label: "io.textwarden.browser.writer")
    private let lock = NSLock()
    private var closed = false

    init(descriptor: Int32) {
        self.descriptor = descriptor
        BrowserSocket.configure(descriptor)
    }

    func readMessages(onMessage: @escaping @Sendable (BrowserMessage) -> Void, onClose: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { close(); onClose() }
            guard BrowserSocket.trustedPeer(descriptor, identifiers: ["TextWardenBrowserHost", BrowserWire.safariExtensionID]) else {
                Logger.warning("Rejected an unauthenticated browser helper", category: Logger.general)
                return
            }
            var buffer = Data()
            var bytes = [UInt8](repeating: 0, count: 16384)
            do {
                while true {
                    let count = Darwin.read(descriptor, &bytes, bytes.count)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { return }
                    buffer.append(contentsOf: bytes.prefix(count))
                    while let message = try BrowserWire.takeMessage(from: &buffer) {
                        onMessage(message)
                    }
                    guard buffer.count <= BrowserWire.maximumLength + 4 else { return }
                }
            } catch {
                Logger.warning("Browser connection rejected an invalid message", category: Logger.general)
            }
        }
    }

    func send(_ message: BrowserMessage) {
        writer.async { [self] in
            lock.lock()
            let canWrite = !closed
            lock.unlock()
            guard canWrite else { return }
            do {
                try BrowserSocket.write(BrowserWire.encode(message), to: descriptor)
            } catch {
                shutdown(descriptor, SHUT_RDWR)
            }
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        shutdown(descriptor, SHUT_RDWR)
        // The descriptor stays owned until the reader exits; shutdown wakes a blocked read.
    }

    deinit { Darwin.close(descriptor) }
}
