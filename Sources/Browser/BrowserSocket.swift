import Darwin
import Foundation
import Security

/// A bounded, per-user Unix socket. No HTTP port or page-accessible endpoint.
enum BrowserSocket {
    static func address(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw BrowserWireError.invalidMessage
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            target.copyBytes(from: bytes)
        }
        return address
    }

    static func connect(path: String = BrowserWire.socketPath) throws -> Int32 {
        var address = try address(path: path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw BrowserWireError.disconnected }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, trustedPeer(descriptor, identifiers: ["io.textwarden.TextWarden"]) else {
            Darwin.close(descriptor)
            throw BrowserWireError.disconnected
        }
        configure(descriptor)
        return descriptor
    }

    static func sameUser(_ descriptor: Int32) -> Bool {
        var user: uid_t = 0
        var group: gid_t = 0
        return getpeereid(descriptor, &user, &group) == 0 && user == getuid()
    }

    static func trustedPeer(_ descriptor: Int32, identifiers: [String]) -> Bool {
        guard sameUser(descriptor), !identifiers.isEmpty else { return false }
        // The kernel audit token binds the signature check to this connection, avoiding PID reuse.
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout.size(ofValue: token))
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0,
              length == MemoryLayout.size(ofValue: token) else { return false }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return false }
        // Identifiers are internal constants, never values supplied by the peer.
        let identity = identifiers.map { "identifier \"\($0)\"" }.joined(separator: " or ")
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"KSW8RTNTKJ\" and (\(identity))"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    static func configure(_ descriptor: Int32) {
        // Darwin inherits the listener's nonblocking mode; our background reader waits for frames.
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) }
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
    }

    static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw BrowserWireError.disconnected }
                offset += count
            }
        }
    }
}
