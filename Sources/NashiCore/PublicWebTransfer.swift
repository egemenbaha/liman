import Foundation

/// Each hop runs curl with one checked numeric address, normal TLS hostname
/// verification, no proxies/configuration and no automatic redirects. A new
/// process per hop prevents connection reuse from bypassing the address policy.
enum PublicWebTransfer {
    static func arguments(for url: URL, address: String, head: Bool) throws -> [String] {
        _ = try PublicWebPolicy.validate(url)
        guard PublicWebPolicy.isPublicAddress(address) else { throw PublicWebPolicy.refused() }
        let host = url.host!, port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
        let numeric = address.contains(":") ? "[\(address)]" : address
        return ["--disable", "--silent", "--show-error", "--globoff", "--include",
                "--http1.1", "--proxy", "", "--noproxy", "*", "--proto", "=http,https",
                "--connect-timeout", "15", "--max-time", head ? "30" : "21600",
                "--speed-limit", "1", "--speed-time", "45",
                "--resolve", "\(host):\(port):\(numeric)"] + (head ? ["--head"] : []) + ["--url", url.absoluteString]
    }

    static func fetch(_ initial: URL, to file: URL, head: Bool = false, maximumBytes: Int64,
                      token: CancellationToken, progress: @escaping ProgressHandler = { _, _ in }) throws -> HTTPURLResponse {
        var url = initial
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: file) } }
        for hop in 0...5 {
            try token.check()
            let address = try PublicWebPolicy.pinnedAddress(for: url)
            let collector = try ResponseCollector(url: url, file: file, maximumBytes: maximumBytes, head: head, progress: progress)
            do {
                try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/curl"), try arguments(for: url, address: address, head: head),
                                      token: token, outputSink: { try collector.append($0) }, timeout: head ? 35 : 21605)
            } catch {
                try? collector.close()
                // Avoid echoing signed source URLs or curl diagnostics to the UI.
                try token.check()
                throw NashiError.failed("The public media transfer failed or exceeded its safety limits.")
            }
            try collector.close()
            guard let response = collector.response else { throw NashiError.failed("The server returned no HTTP response.") }
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location") else { throw PublicWebPolicy.refused() }
                url = try PublicWebPolicy.redirected(from: url, location: location, count: hop)
                continue
            }
            completed = true
            return response
        }
        throw PublicWebPolicy.refused()
    }

    static func fetchAsync(_ url: URL, to file: URL, head: Bool = false, maximumBytes: Int64,
                           token: CancellationToken, progress: @escaping ProgressHandler = { _, _ in }) async throws -> HTTPURLResponse {
        try await withTaskCancellationHandler {
            try await Task.detached { try fetch(url, to: file, head: head, maximumBytes: maximumBytes, token: token, progress: progress) }.value
        } onCancel: { token.cancel() }
    }

    /// The byte cap applies to bytes actually received, even without a declared
    /// length. Headers and informational responses share a separate 64 KiB cap.
    final class ResponseCollector: @unchecked Sendable {
        private let url: URL, handle: FileHandle, maximumBytes: Int64, head: Bool, progress: ProgressHandler
        private var pending = Data(), headerBytes = 0, received: Int64 = 0
        private(set) var response: HTTPURLResponse?

        init(url: URL, file: URL, maximumBytes: Int64, head: Bool = false, progress: @escaping ProgressHandler = { _, _ in }) throws {
            self.url = url; self.maximumBytes = maximumBytes; self.head = head; self.progress = progress
            guard maximumBytes >= 0 else { throw PublicWebPolicy.refused() }
            // Caller supplies a new path inside an owner-only staging directory.
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw NashiError.failed("Cannot create the private download file.")
            }
            handle = try FileHandle(forWritingTo: file)
        }
        func append(_ bytes: Data) throws {
            if response != nil { try writeBody(bytes); return }
            pending.append(bytes)
            while let end = pending.range(of: Data([13, 10, 13, 10])) {
                let header = pending[..<end.lowerBound]
                headerBytes += header.count + 4
                guard headerBytes <= 65536 else { throw PublicWebPolicy.refused() }
                let lines = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
                let statusLine = lines[0].split(separator: " ")
                guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/"), let status = Int(statusLine[1]),
                      (100...599).contains(status), status != 101 else { throw PublicWebPolicy.refused() }
                var fields: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw PublicWebPolicy.refused() }
                    let name = String(line[..<colon]).lowercased()
                    guard fields[name] == nil || !["location", "content-length", "transfer-encoding"].contains(name) else { throw PublicWebPolicy.refused() }
                    fields[name] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                pending.removeSubrange(..<end.upperBound)
                if status < 200 { continue }
                guard let parsed = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields) else { throw PublicWebPolicy.refused() }
                response = parsed
                if !head, parsed.expectedContentLength > maximumBytes { throw PublicWebPolicy.refused() }
                let body = pending; pending.removeAll(); try writeBody(body); return
            }
            guard headerBytes + pending.count <= 65536 else { throw PublicWebPolicy.refused() }
        }
        private func writeBody(_ bytes: Data) throws {
            guard !head || bytes.isEmpty else { throw PublicWebPolicy.refused() }
            let limit = response.map { (300...399).contains($0.statusCode) ? min(maximumBytes, 65536) : maximumBytes } ?? maximumBytes
            guard Int64(bytes.count) <= limit - received else { throw PublicWebPolicy.refused() }
            try handle.write(contentsOf: bytes); received += Int64(bytes.count)
            let expected = response?.expectedContentLength ?? -1
            progress(expected > 0 ? min(1, Double(received) / Double(expected)) : OperationProgress.indeterminate,
                     "Downloading · \(ByteCountFormatter.string(fromByteCount: received, countStyle: .file))")
        }
        func close() throws { try handle.close() }
        deinit { try? handle.close() }
    }
}
