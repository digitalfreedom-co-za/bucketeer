//
//  ListBucketsIntent.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import AppIntents
import BucketeerCore

/// "List the buckets in this Bucketeer account." Phase 13.12.
struct ListBucketsIntent: AppIntent {
    static let title: LocalizedStringResource = "List buckets"
    static let description = IntentDescription(
        "Returns every bucket the chosen Bucketeer account can see."
    )

    @Parameter(title: "Account")
    var account: AccountEntity

    static var parameterSummary: some ParameterSummary {
        Summary("List buckets in \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let container = try await AppIntentsBridge.shared.container()
        let live = try await AppIntentsBridge.shared.liveAccount(for: account)
        let buckets = try await container.s3Browser.listBuckets(account: live)
        return .result(value: buckets.map(\.name))
    }
}
