//
//  GeneratePresignedURLIntent.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import AppIntents
import BucketeerCore

/// "Generate a shareable URL for a Bucketeer object." Phase 13.12.
/// Returns a `URL` so Shortcuts can pipe it into Mail / Messages /
/// Notes / clipboard / etc.
struct GeneratePresignedURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate presigned URL"
    static let description = IntentDescription(
        "Builds a time-limited download URL for an object in one of your buckets."
    )

    @Parameter(title: "Account")
    var account: AccountEntity

    @Parameter(title: "Bucket")
    var bucket: String

    @Parameter(title: "Key")
    var key: String

    /// Time-to-live in **minutes**. Clamped between 1 and 10 080
    /// (1 week) — matches AWS Signature v4's hard upper bound.
    @Parameter(title: "TTL (minutes)", default: 60)
    var ttlMinutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Generate URL for \(\.$key) in \(\.$bucket) on \(\.$account)") {
            \.$ttlMinutes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<URL> {
        let container = try await AppIntentsBridge.shared.container()
        let live = try await AppIntentsBridge.shared.liveAccount(for: account)
        let clamped = max(1, min(ttlMinutes, 7 * 24 * 60))
        let url = try await container.s3Browser.presignedDownloadURL(
            account: live,
            bucket: bucket,
            key: key,
            ttl: TimeInterval(clamped * 60)
        )
        return .result(value: url)
    }
}
