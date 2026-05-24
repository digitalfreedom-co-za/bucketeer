//
//  AppIntentsBridge.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import BucketeerCore

/// Thin facade that App Intents call into. Phase 13.12. Centralises
/// "wait until the AppContainer is live, then do X" so each intent
/// stays focused on its declarative job.
///
/// The host launches via `AppContainer.shared = container` early in
/// `BucketeerApp.init`; intents that run cold-start poll briefly so
/// the wait is invisible to the user.
struct AppIntentsBridge: Sendable {
    static let shared = AppIntentsBridge()

    private init() {}

    /// Block until `AppContainer.shared` resolves or the timeout
    /// elapses. Default 5 s — enough for cold-launch on a healthy
    /// Mac, short enough that a wedged App still returns an error.
    func container(timeout: TimeInterval = 5.0) async throws -> AppContainer {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let container = await MainActor.run(body: { AppContainer.shared }) {
                return container
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100 ms
        }
        throw BucketeerError.unknown(
            message: "Bucketeer is not running — open the App and try again."
        )
    }

    /// Snapshot of every configured account, wrapped for the
    /// AppIntent runtime. Goes through the live `AccountStore` so
    /// changes the user makes in the App reflect in Shortcuts
    /// without any sync hop.
    func accounts() async throws -> [AccountEntity] {
        let container = try await container()
        let snapshots = try await container.accountStore.all()
        return snapshots.map(AccountEntity.init(account:))
    }

    /// Resolve an `AccountEntity` back into the live `S3Account`
    /// snapshot the services accept.
    func liveAccount(for entity: AccountEntity) async throws -> S3Account {
        let container = try await container()
        let all = try await container.accountStore.all()
        guard let match = all.first(where: { $0.id == entity.id }) else {
            throw BucketeerError.unknown(message: "Account is no longer configured.")
        }
        return match
    }
}
