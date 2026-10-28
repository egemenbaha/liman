import Foundation
import NashiCore

@main struct SetupLimanTools {
    static func main() async throws {
        let token = CancellationToken()
        // Log stage names only; no URLs, environment or user file paths.
        let report: @Sendable (Double?, String) -> Void = { fraction, message in
            if fraction == nil || fraction == 1 { print(message) }
        }
        try await ExternalToolSetup.installMedia(token: token, progress: report)
        try await ExternalToolSetup.installOffice(token: token, progress: report)
        guard ExternalToolSetup.status.ready else { throw NashiError.failed("Tool installation is incomplete.") }
        print("All media and office tools are ready.")
    }
}
