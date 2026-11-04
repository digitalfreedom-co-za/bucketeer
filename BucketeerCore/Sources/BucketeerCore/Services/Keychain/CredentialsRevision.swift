//
//  CredentialsRevision.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation

/// Per-account counter in the App Group defaults that the host bumps
/// whenever an account's credentials or settings change. The File
/// Provider extension holds its own credential caches; comparing the
/// revision a cache entry was built at with the current one lets it
/// notice changes made in the host process.
public struct CredentialsRevision: Sendable {
    private let suiteName: String

    public init(suiteName: String) {
        self.suiteName = suiteName
    }

    /// The shared revision of host and extension.
    public static let appGroup = CredentialsRevision(suiteName: AppEnvironment.appGroupIdentifier)

    public func current(for accountID: UUID) -> Int {
        defaults?.integer(forKey: key(for: accountID)) ?? 0
    }

    /// Only the host writes, so read-modify-write needs no lock.
    public func bump(for accountID: UUID) {
        defaults?.set(current(for: accountID) + 1, forKey: key(for: accountID))
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    private func key(for accountID: UUID) -> String {
        "credentialsRevision.\(accountID.uuidString)"
    }
}
