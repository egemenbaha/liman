import Foundation
@testable import NashiUpdates

@main struct UpdateChecks {
    final class NoCredentials: UpdateCredentialStore, @unchecked Sendable {
        var calls = 0
        func token(for repository: GitHubRepository) throws -> String { calls += 1; throw UpdateCredentialError.missing }
        func save(_ token: String, for repository: GitHubRepository) throws { calls += 1 }
        func remove(for repository: GitHubRepository) throws { calls += 1 }
    }
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ name: String, _ value: Bool) throws {
            guard value else { throw NSError(domain: "LimanUpdates", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            passed += 1; print("PASS \(name)")
        }
        func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
        let info: [String: Any] = ["SUFeedURL": "https://updates.example.com/appcast.xml", "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(), "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true]
        _ = try UpdateConfiguration(info: info)
        try check("valid pinned signing configuration retained", true)
        try check("missing signing key refused", rejects { _ = try UpdateConfiguration(info: [:]) })
        for flag in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"] {
            var altered = info; altered[flag] = false
            try check("required \(flag)", rejects { _ = try UpdateConfiguration(info: altered) })
        }
        for feed in ["http://updates.example.com/feed", "file:///tmp/feed", "https://u:p@example.com/feed", "https://example.com/feed#fragment"] {
            var altered = info; altered["SUFeedURL"] = feed
            try check("unsafe update feed rejected", rejects { _ = try UpdateConfiguration(info: altered) })
        }
        for key in ["invalid", Data(repeating: 1, count: 31).base64EncodedString(), Data(repeating: 1, count: 64).base64EncodedString()] {
            var altered = info; altered["SUPublicEDKey"] = key
            try check("malformed signing key rejected", rejects { _ = try UpdateConfiguration(info: altered) })
        }
        let suite = "Liman.SecurityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("orkunisitmak/nashi-app", forKey: "TangerineUpdateGitHubRepository")
        defaults.set(true, forKey: "TangerineUpdateGitHubSavedToken")
        let credentials = NoCredentials()
        let updater = AppUpdater(credentials: credentials, defaults: defaults)
        updater.start(); updater.setAutomaticChecks(true); updater.checkForUpdates()
        try check("default fork does not restore upstream identity", updater.repository == nil && !updater.hasSavedToken)
        try check("default fork update and connection controls disabled", !updater.canCheckForUpdates && !updater.isConfigured && !updater.canChangeConnection && !updater.automaticallyChecksForUpdates)
        var refused = false
        do { try await updater.connectGitHub(repository: "example/repo", token: "fixture", requiresToken: true) } catch { refused = true }
        try check("local fork refuses connection before credential access", refused && credentials.calls == 0)
        try check("existing preference not deleted", defaults.string(forKey: "TangerineUpdateGitHubRepository") == "orkunisitmak/nashi-app")
        print("\(passed) update checks passed (policy/configuration; no signed release installed)")
    }
}
