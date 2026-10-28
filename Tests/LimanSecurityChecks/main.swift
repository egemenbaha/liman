import Foundation
import Darwin
@testable import NashiCore

var passed = 0
func check(_ name: String, _ body: () throws -> Bool) throws {
    guard try body() else { throw NSError(domain: "LimanSecurity", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
    passed += 1; print("PASS \(name)")
}
func rejects(_ body: () throws -> Void) -> Bool {
    do { try body(); return false } catch { return true }
}
let fm = FileManager.default
let base = try OutputFiles.temporaryDirectory()
defer { try? fm.removeItem(at: base) }
let web = URL(string: "https://example.org/media")!
for host in ["127.0.0.1", "127.1", "2130706433", "0x7f000001", "0177.0.0.1", "0.0.0.0", "10.1.1.1", "172.16.1.1", "192.168.1.1", "169.254.169.254", "100.64.0.1", "192.0.2.1", "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255", "[::1]", "[::]", "[::ffff:127.0.0.1]", "[fc00::1]", "[fe80::1]", "[64:ff9b::7f00:1]", "[2002:7f00:1::1]", "[2001:db8::1]", "[fe80::1%25en0]", "localhost", "host.local", "host.local.", "printer", "host.home.arpa"] {
    try check("refuse host \(host)") { rejects { _ = try WebDownloadEngine.link("http://\(host)/a") } }
}
for address in ["8.8.8.8", "1.1.1.1", "93.184.215.14", "2606:4700:4700::1111", "2001:4860:4860::8888"] {
    try check("allow global \(address)") { PublicWebPolicy.isPublicAddress(address) }
}
try check("mixed DNS answer refused") { rejects { _ = try PublicWebPolicy.pinnedAddress(for: web) { _ in ["8.8.8.8", "127.0.0.1"] } } }
try check("empty DNS answer refused") { rejects { _ = try PublicWebPolicy.pinnedAddress(for: web) { _ in [] } } }
try check("DNS failure is closed") { rejects { _ = try PublicWebPolicy.pinnedAddress(for: web) { _ in throw PublicWebPolicy.refused() } } }
var resolutions = 0
let pinned = try PublicWebPolicy.pinnedAddress(for: web) { _ in resolutions += 1; return resolutions == 1 ? ["8.8.8.8"] : ["127.0.0.1"] }
let args = try PublicWebTransfer.arguments(for: web, address: pinned, head: false)
try check("validated address pinned without second DNS lookup") { resolutions == 1 && args.contains("example.org:443:8.8.8.8") }
try check("curl config proxies redirects globbing disabled") { args.first == "--disable" && args.contains("--globoff") && args.contains("--noproxy") && !args.contains("--location") && !args.contains("--insecure") && args.suffix(2) == ["--url", web.absoluteString] }
try check("TLS hostname preserved") { args.last == web.absoluteString }
try check("IPv6 pinned") { try PublicWebTransfer.arguments(for: web, address: "2606:4700::1111", head: false).contains("example.org:443:[2606:4700::1111]") }
for location in ["http://example.org/a", "https://127.0.0.1/a", "file:///etc/passwd", "https://u:p@example.org", "https://example.org/\nX"] {
    try check("unsafe redirect refused \(location.debugDescription)") { rejects { _ = try PublicWebPolicy.redirected(from: web, location: location, count: 0) } }
}
try check("relative redirect preserved") { try PublicWebPolicy.redirected(from: web, location: "/next", count: 0).absoluteString == "https://example.org/next" }
try check("redirect loop bounded") { rejects { _ = try PublicWebPolicy.redirected(from: web, location: "/next", count: 5) } }
let redirect = try PublicWebPolicy.redirected(from: web, location: "https://other.example.org/next", count: 0)
try check("redirect DNS checked again") { rejects { _ = try PublicWebPolicy.pinnedAddress(for: redirect) { _ in ["10.0.0.1"] } } }
let output = base.appendingPathComponent("body")
let collector = try PublicWebTransfer.ResponseCollector(url: web, file: output, maximumBytes: 4)
try collector.append(Data("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Type: image/png\r\n".utf8))
try collector.append(Data("\r\nab".utf8)); try collector.append(Data("cd".utf8))
try check("actual streamed cap before disk write") { rejects { try collector.append(Data("e".utf8)) } }
try collector.close()
try check("body intact and capped") { try Data(contentsOf: output) == Data("abcd".utf8) && collector.response?.mimeType == "image/png" }
for (name, header) in [("header cap", String(repeating: "X", count: 65537)), ("declared size", "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n"), ("duplicate redirect", "HTTP/1.1 302 Found\r\nLocation: /a\r\nlocation: /b\r\n\r\n")] {
    let c = try PublicWebTransfer.ResponseCollector(url: web, file: base.appendingPathComponent(UUID().uuidString), maximumBytes: 4)
    try check(name) { rejects { try c.append(Data(header.utf8)) } }; try c.close()
}
let head = try PublicWebTransfer.ResponseCollector(url: web, file: base.appendingPathComponent("head"), maximumBytes: 0, head: true)
try head.append(Data("HTTP/1.1 200 OK\r\nContent-Length: 200000000\r\n\r\n".utf8)); try head.close()
try check("HEAD may describe a large file") { head.response?.expectedContentLength == 200000000 }
try check("private temporary folder") { try (fm.attributesOfItem(atPath: base.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700 }
try check("private downloaded file") { try (fm.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600 }
let environment = ProcessRunner.safeEnvironment(["HOME": base.path, "LANG": "C", "GH_TOKEN": "fixture", "DYLD_INSERT_LIBRARIES": "fixture", "PYTHONPATH": "fixture", "HTTPS_PROXY": "fixture", "PATH": "/untrusted"])
try check("child environment excludes credentials and injection") { environment == ["HOME": base.path, "LANG": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"] }
let literal = "$(touch SHOULD_NOT_EXIST); `id`"
try check("process uses literal argv") { try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", literal]).text == literal }
try check("stdin is closed") { try ProcessRunner.run(URL(fileURLWithPath: "/bin/cat"), [], timeout: 1).output.isEmpty }
let started = Date()
try check("process timeout") { rejects { _ = try ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 0.1) } && Date().timeIntervalSince(started) < 3 }
try check("stream sink can stop a process") { rejects { _ = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/yes"), [], outputSink: { _ in throw PublicWebPolicy.refused() }, timeout: 3) } }
for path in ["../outside", "/absolute", "C:\\escape", "a\\..\\outside", "a/../../outside", String(repeating: "a/", count: 65) + "file", String(repeating: "x", count: 4097)] {
    try check("archive path refused \(path.prefix(35))") { rejects { _ = try ArchiveCodec.safeURL(path, inside: base) } }
}
let source = base.appendingPathComponent("source")
try fm.createDirectory(at: source, withIntermediateDirectories: false)
try Data(repeating: 65, count: 100_000).write(to: source.appendingPathComponent("data.txt"))
try fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: source.appendingPathComponent("data.txt").path)
let archive = base.appendingPathComponent("fixture.zip")
try ArchiveCodec.create(from: source, at: archive, format: "zip", token: .init())
try check("archive actual byte cap") { rejects { try ArchiveCodec.extract(archive, into: base.appendingPathComponent("small"), token: .init(), limits: .init(maximumBytes: 10)) } }
try check("archive ratio cap") { rejects { try ArchiveCodec.extract(archive, into: base.appendingPathComponent("ratio"), token: .init(), limits: .init(maximumExpansionRatio: 2, ratioGraceBytes: 0)) } }
try check("archive invalid limits refused") { rejects { try ArchiveCodec.extract(archive, into: base.appendingPathComponent("bad"), token: .init(), limits: .init(maximumEntries: 0)) } }
let extracted = base.appendingPathComponent("normal")
try ArchiveCodec.extract(archive, into: extracted, token: .init())
try check("ordinary archive retains content") { try Data(contentsOf: extracted.appendingPathComponent("data.txt")) == Data(repeating: 65, count: 100_000) }
try check("archive cannot grant group or world permissions") { try (fm.attributesOfItem(atPath: extracted.appendingPathComponent("data.txt").path)[.posixPermissions] as? NSNumber)?.intValue == 0o700 }
let root = base.appendingPathComponent("alias-root")
try fm.createDirectory(at: root, withIntermediateDirectories: false)
try fm.createSymbolicLink(at: root.appendingPathComponent("data.txt"), withDestinationURL: output)
try check("archive refuses existing symlink") { rejects { try ArchiveCodec.extract(archive, into: root, token: .init()) } }
try check("symlink target intact") { try Data(contentsOf: output) == Data("abcd".utf8) }
let diagnostics = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/perl"), ["-e", "print STDERR 'x' x 200000"], timeout: 5)
try check("stderr drained with bounded retention") { diagnostics.errorOutput.count == 65536 }
let fixtures = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LIMAN_FIXTURES"]!)
for name in ["traversal.zip", "absolute.zip", "backslash.zip"] {
    try check("real malicious archive refused \(name)") {
        rejects { try ArchiveCodec.extract(fixtures.appendingPathComponent(name), into: base.appendingPathComponent(name), token: .init()) }
    }
}
try check("real archive entry count limited") {
    rejects { try ArchiveCodec.extract(fixtures.appendingPathComponent("entries.zip"), into: base.appendingPathComponent("entries"), token: .init(), limits: .init(maximumEntries: 1)) }
}
try check("failed extraction has no outside write") { !fm.fileExists(atPath: base.appendingPathComponent("escaped.txt").path) }
let hashFixture = base.appendingPathComponent("checksum")
try Data("abc".utf8).write(to: hashFixture)
let knownHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
try ExternalToolSetup.verify(hashFixture, digest: knownHash)
try check("known SHA256 accepted") { true }
try Data("abd".utf8).write(to: hashFixture)
try check("tampered runtime checksum refused") { rejects { try ExternalToolSetup.verify(hashFixture, digest: knownHash) } }
// Optional public internet smoke test, never a local-server bypass of policy.
if ProcessInfo.processInfo.environment["LIMAN_LIVE_TEST"] == "1" {
    let live = base.appendingPathComponent("live")
    let response = try PublicWebTransfer.fetch(URL(string: "https://example.com/")!, to: live, maximumBytes: 1_000_000, token: .init())
    try check("live pinned HTTPS and body") { try response.statusCode == 200 && Data(contentsOf: live).count > 0 }
}
print("\(passed) security checks passed")
