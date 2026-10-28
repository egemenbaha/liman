import Foundation
import Darwin

/// Public-media requests must never reach local, reserved or transition networks.
/// Resolution is injectable for deterministic tests; the transport must use the
/// returned numeric address, never resolve the hostname a second time.
enum PublicWebPolicy {
    typealias Resolver = (String) throws -> [String]

    static func validate(_ url: URL) throws -> String {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              var host = url.host?.lowercased(), !host.isEmpty,
              url.port == nil || (1...65535).contains(url.port!) else { throw refused() }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard !host.contains("%") else { throw refused() }
        while host.hasSuffix(".") { host.removeLast() }
        if numericBytes(host) != nil {
            guard isPublicAddress(host) else { throw refused() }
        } else {
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.count >= 2, host.utf8.count <= 253,
                  labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-" && $0.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 } }),
                  !["localhost", "local", "internal", "home.arpa", "test", "invalid"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { throw refused() }
        }
        return host
    }

    static func pinnedAddress(for url: URL, resolve: Resolver = systemResolve) throws -> String {
        let host = try validate(url)
        let addresses = try resolve(host)
        // Reject mixed public/private answers too; do not silently pick a safe one.
        guard !addresses.isEmpty, addresses.allSatisfy(isPublicAddress) else { throw refused() }
        return addresses[0]
    }

    static func redirected(from source: URL, location: String, count: Int) throws -> URL {
        guard count < 5, !location.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let next = URL(string: location, relativeTo: source)?.absoluteURL,
              !(source.scheme?.lowercased() == "https" && next.scheme?.lowercased() != "https") else { throw refused() }
        _ = try validate(next)
        return next
    }

    static func isPublicAddress(_ address: String) -> Bool {
        guard let bytes = numericBytes(address) else { return false }
        if bytes.count == 4 {
            let a = bytes[0], b = bytes[1], c = bytes[2]
            return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
                     (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254) ||
                     (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) ||
                     (a == 192 && b == 0 && (c == 0 || c == 2)) ||
                     (a == 192 && b == 88 && c == 99) || (a == 198 && (b == 18 || b == 19)) ||
                     (a == 198 && b == 51 && c == 100) || (a == 203 && b == 0 && c == 113))
        }
        // Only ordinary global unicast; deny mapped IPv4, NAT64, 6to4,
        // Teredo and other special-purpose prefixes without interpreting them.
        return bytes[0] & 0xe0 == 0x20 &&
            !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] < 2) &&
            !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8) &&
            !(bytes[0] == 0x20 && bytes[1] == 0x02) &&
            !(bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] & 0xf0 == 0)
    }

    private static func numericBytes(_ host: String) -> [UInt8]? {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_aton(host, &v4) == 1 { return withUnsafeBytes(of: &v4) { Array($0) } }
        if inet_pton(AF_INET6, host, &v6) == 1 { return withUnsafeBytes(of: &v6) { Array($0) } }
        return nil
    }

    static func systemResolve(_ host: String) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM; hints.ai_protocol = IPPROTO_TCP
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { throw refused() }
        defer { freeaddrinfo(first) }
        var addresses: [String] = [], current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { throw refused() }
            addresses.append(String(cString: buffer)); current = entry.pointee.ai_next
        }
        return addresses
    }

    static func refused() -> NashiError { .invalidInput("Only public internet media addresses are allowed. Local, reserved and unsafe redirect targets are blocked.") }
}
