//
//  S3ClientFactory.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
@preconcurrency import SotoS3

/// Builds and caches Soto `S3` clients per account. Each cached entry
/// owns its own `AWSClient` so that connection pools stay scoped to
/// the credentials currently in use. `invalidate(accountID:)` is called
/// whenever credentials change or the account is deleted.
///
/// As in `AzureCredentialsCache`, entries carry the `CredentialsRevision`
/// they were built at (changes made by the other process) and a
/// per-account generation discards lookups an invalidation overtook.
public actor S3ClientFactory {
    private let keychainStore: any KeychainStoring
    private let revision: CredentialsRevision?

    private struct Cached {
        let awsClient: AWSClient
        let s3: S3
        let revision: Int
    }

    private var cache: [UUID: Cached] = [:]
    private var generations: [UUID: Int] = [:]

    public init(keychainStore: any KeychainStoring, revision: CredentialsRevision? = nil) {
        self.keychainStore = keychainStore
        self.revision = revision
    }

    // MARK: - Public

    public func client(for account: S3Account) async throws -> S3 {
        while true {
            let currentRevision = revision?.current(for: account.id) ?? 0
            if let cached = cache[account.id] {
                if cached.revision == currentRevision { return cached.s3 }
                await invalidate(accountID: account.id)
                continue
            }
            let generation = generations[account.id, default: 0]
            let credentials = try await keychainStore.load(for: account.id)
            // Invalidated while the Keychain answered: these credentials
            // may be the ones just replaced.
            guard generations[account.id, default: 0] == generation else { continue }
            // Actor reentrancy: another concurrent `client(for:)` call may
            // have populated the cache while we were awaiting the
            // Keychain. Re-check before constructing a duplicate
            // AWSClient (which would otherwise leak — Soto requires
            // explicit shutdown).
            if let cached = cache[account.id], cached.revision == currentRevision {
                return cached.s3
            }
            return makeClient(for: account, credentials: credentials, revision: currentRevision)
        }
    }

    private func makeClient(for account: S3Account, credentials: AccountCredentials, revision: Int) -> S3 {
        let awsClient = AWSClient(
            credentialProvider: .static(
                accessKeyId: credentials.accessKey,
                secretAccessKey: credentials.secretKey,
                sessionToken: credentials.sessionToken
            )
        )
        let endpoint = Self.endpoint(for: account)
        let region = Region(rawValue: account.region)
        // Soto 7 defaults to path-style for non-AWS endpoints and
        // virtual-host for amazonaws.com URLs. We opt into virtual-host
        // for the other providers that publish virtual-host endpoints
        // (Civo, R2, B2, Wasabi, DO Spaces).
        let options: AWSServiceConfig.Options = account.usesPathStyle
            ? []
            : .s3ForceVirtualHost
        let s3 = S3(
            client: awsClient,
            region: region,
            endpoint: endpoint.absoluteString,
            options: options
        )
        cache[account.id] = Cached(awsClient: awsClient, s3: s3, revision: revision)
        return s3
    }

    public func invalidate(accountID: UUID) async {
        generations[accountID, default: 0] += 1
        guard let cached = cache.removeValue(forKey: accountID) else { return }
        try? await cached.awsClient.shutdown()
    }

    public func shutdownAll() async {
        // Snapshot + clear BEFORE the awaits: shutdown() suspends, and
        // a concurrent client(for:) could insert a fresh entry during
        // the loop — removeAll() at the end would then drop an
        // un-shut-down AWSClient (Soto leak) and the values iterator
        // would observe mutation mid-walk.
        let snapshot = Array(cache.values)
        cache.removeAll()
        for cached in snapshot {
            try? await cached.awsClient.shutdown()
        }
    }

    /// One-shot credential validation. Builds a throwaway `AWSClient`
    /// with the supplied credentials, calls `listBuckets`, then shuts
    /// the client down. The cache is never touched so this never
    /// pollutes the live state for an existing account.
    public static func testConnection(
        for account: S3Account,
        credentials: AccountCredentials
    ) async throws {
        let awsClient = AWSClient(
            credentialProvider: .static(
                accessKeyId: credentials.accessKey,
                secretAccessKey: credentials.secretKey,
                sessionToken: credentials.sessionToken
            )
        )
        do {
            let endpoint = Self.endpoint(for: account)
            let region = Region(rawValue: account.region)
            let options: AWSServiceConfig.Options = account.usesPathStyle
                ? []
                : .s3ForceVirtualHost
            let s3 = S3(
                client: awsClient,
                region: region,
                endpoint: endpoint.absoluteString,
                options: options
            )
            _ = try await s3.listBuckets()
            try await awsClient.shutdown()
        } catch {
            try? await awsClient.shutdown()
            throw error
        }
    }

    // MARK: - Endpoint construction

    /// Provider-specific endpoint URL. Pure function — same input, same
    /// output. Mirrored in tests and in the design spec.
    public static func endpoint(for account: S3Account) -> URL {
        switch account.provider {
        case .awsS3:
            return URL(string: "https://s3.\(account.region).amazonaws.com")!
        case .civo:
            return URL(string: "https://objectstore.\(account.region).civo.com")!
        case .cloudflareR2:
            let id = account.accountID ?? "missing-account-id"
            return URL(string: "https://\(id).r2.cloudflarestorage.com")!
        case .backblazeB2:
            return URL(string: "https://s3.\(account.region).backblazeb2.com")!
        case .wasabi:
            return URL(string: "https://s3.\(account.region).wasabisys.com")!
        case .digitalOceanSpaces:
            return URL(string: "https://\(account.region).digitaloceanspaces.com")!
        case .storj:
            return URL(string: "https://gateway.storjshare.io")!
        case .azureBlob:
            // Azure traffic never routes through S3ClientFactory; this case
            // satisfies Swift's exhaustiveness requirement only.
            let accountName = account.accountID ?? "unknown"
            return account.endpointOverride
                ?? URL(string: "https://\(accountName).blob.core.windows.net")!
        case .custom:
            return account.endpointOverride
                ?? URL(string: "https://localhost")!
        }
    }
}
