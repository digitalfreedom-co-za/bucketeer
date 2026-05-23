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
public actor AzureCredentialsCache {
    private let keychainStore: any KeychainStoring
    private var cache: [UUID: AzureSharedKeySigner] = [:]

    public init(keychainStore: any KeychainStoring) {
        self.keychainStore = keychainStore
    }

    /// Returns a signer for the supplied account. The Azure credential
    /// layout in `AccountCredentials`:
    ///   - `accessKey`  → storage account name
    ///   - `secretKey`  → base64 account key
    ///   - `sessionToken` is unused for Shared Key auth (reserved for
    ///     SAS in v1.1).
    func signer(for account: S3Account) async throws -> AzureSharedKeySigner {
        if let cached = cache[account.id] { return cached }
        let credentials = try await keychainStore.load(for: account.id)
        // Actor reentrancy guard — mirrors the pattern in S3ClientFactory.
        if let cached = cache[account.id] { return cached }
        // Prefer the explicit accountID on the S3Account model (set by the
        // Add/Edit sheet for Azure) over the Keychain copy — it survives
        // even if the Keychain entry was created before we added the
        // accountID duplication.
        let accountName = account.accountID?.isEmpty == false
            ? account.accountID!
            : credentials.accessKey
        guard let signer = AzureSharedKeySigner(
            accountName: accountName,
            base64AccountKey: credentials.secretKey
        ) else {
            throw BucketeerError.authenticationFailed
        }
        cache[account.id] = signer
        return signer
    }

    /// One-shot signer for the connection-test flow. Doesn't touch the
    /// cache so a successful test against credentials a user is *trying*
    /// to enter doesn't poison the live cache for an existing account.
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
    }

    public func invalidateAll() async {
        cache.removeAll()
    }
}
