//
//  AzureCredentialsCache.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// Mirrors the role of `S3ClientFactory` for the Azure family. Caches
/// the resolved signer per `account.id` so the Keychain is hit at most
/// once per process for a given account. Invalidated whenever an
/// account is edited or deleted so credential rotation propagates
/// immediately.
///
/// Each entry remembers the `CredentialsRevision` it was built at, so a
/// change made by the host reaches the extension's cache too; a
/// per-account generation discards lookups that were in flight when
/// the account was invalidated.
public actor AzureCredentialsCache {
    private let keychainStore: any KeychainStoring
    private let revision: CredentialsRevision?
    private struct Entry {
        let signer: AzureSharedKeySigner
        let revision: Int
    }
    private var cache: [UUID: Entry] = [:]
    private var generations: [UUID: Int] = [:]

    public init(keychainStore: any KeychainStoring, revision: CredentialsRevision? = nil) {
        self.keychainStore = keychainStore
        self.revision = revision
    }

    /// Returns a signer for the supplied account. The Azure credential
    /// layout in `AccountCredentials`:
    ///   - `accessKey`  → storage account name
    ///   - `secretKey`  → base64 account key
    ///   - `sessionToken` is unused for Shared Key auth (reserved for
    ///     SAS in v1.1).
    func signer(for account: S3Account) async throws -> AzureSharedKeySigner {
        while true {
            let currentRevision = revision?.current(for: account.id) ?? 0
            if let cached = cache[account.id], cached.revision == currentRevision { return cached.signer }
            let generation = generations[account.id, default: 0]
            let credentials = try await keychainStore.load(for: account.id)
            // Invalidated while the Keychain answered: these
            // credentials may be the ones just replaced.
            guard generations[account.id, default: 0] == generation,
                  revision?.current(for: account.id) ?? 0 == currentRevision
            else { continue }
            // Actor reentrancy guard — mirrors the pattern in S3ClientFactory.
            if let cached = cache[account.id], cached.revision == currentRevision { return cached.signer }
            guard let signer = Self.makeSigner(account: account, credentials: credentials) else {
                throw BucketeerError.authenticationFailed
            }
            cache[account.id] = Entry(signer: signer, revision: currentRevision)
            return signer
        }
    }

    /// One-shot signer for the connection-test flow. Doesn't touch the
    /// cache so a successful test against credentials a user is *trying*
    /// to enter doesn't poison the live cache for an existing account.
    /// Prefers the explicit accountID on the S3Account model (set by the
    /// Add/Edit sheet for Azure) over the Keychain copy — it survives
    /// even if the Keychain entry was created before we added the
    /// accountID duplication.
    static func makeSigner(
        account: S3Account,
        credentials: AccountCredentials
    ) -> AzureSharedKeySigner? {
        let accountName = account.accountID?.isEmpty == false
            ? account.accountID!
            : credentials.accessKey
        return AzureSharedKeySigner(
            accountName: accountName,
            base64AccountKey: credentials.secretKey
        )
    }

    public func invalidate(accountID: UUID) async {
        cache.removeValue(forKey: accountID)
        generations[accountID, default: 0] += 1
    }

    /// Raw account-name + base64-key tuple. Used by the SAS-builder
    /// path (Phase 9.9) which signs a different StringToSign layout
    /// than the request signer and therefore can't reuse the cached
    /// `AzureSharedKeySigner` instance. Goes through the Keychain on
    /// every call — presigned URL generation isn't a hot path and
    /// the data is too small to bother caching twice.
    public struct RawCredentials: Sendable {
        public let accountName: String
        public let base64AccountKey: String
    }

    func rawCredentials(for account: S3Account) async throws -> RawCredentials {
        let credentials = try await keychainStore.load(for: account.id)
        let accountName = account.accountID?.isEmpty == false
            ? account.accountID!
            : credentials.accessKey
        return RawCredentials(
            accountName: accountName,
            base64AccountKey: credentials.secretKey
        )
    }
}
