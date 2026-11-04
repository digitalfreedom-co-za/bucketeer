//
//  CredentialCacheTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Credential caches must never hand out credentials older than the
/// last invalidation — neither from a lookup that was in flight when
/// the account changed, nor after another process changed it.
@Suite("Credential caches", .serialized)
struct CredentialCacheTests {

    private let account = S3Account(name: "Test", provider: .azureBlob, accountID: "teststorage")
    private static let oldKey = Data(repeating: 1, count: 32)
    private static let newKey = Data(repeating: 2, count: 32)

    @Test("An invalidation during a pending Azure lookup is not undone by its result")
    func azureLookupInFlightIsDiscarded() async throws {
        let keychain = GatedKeychain(secret: Self.oldKey)
        let cache = AzureCredentialsCache(keychainStore: keychain)
        let pending = Task { [account] in try await cache.signer(for: account) }
        await keychain.waitUntilHolding()

        await keychain.rotate(to: Self.newKey)
        await cache.invalidate(accountID: account.id)
        await keychain.release()

        #expect(try await pending.value.accountKeyData == Self.newKey)
        #expect(try await cache.signer(for: account).accountKeyData == Self.newKey)
    }

    @Test("An S3 client built from credentials loaded before an invalidation is not cached")
    func s3LookupInFlightIsDiscarded() async throws {
        let keychain = GatedKeychain(secret: Self.oldKey)
        let factory = S3ClientFactory(keychainStore: keychain)
        let s3Account = S3Account(name: "Test", provider: .awsS3)
        let pending = Task { try await factory.client(for: s3Account) }
        await keychain.waitUntilHolding()

        await factory.invalidate(accountID: s3Account.id)
        await keychain.release()
        _ = try await pending.value
        _ = try await factory.client(for: s3Account)

        // The pending lookup reloaded after the invalidation; the second
        // call is served from that fresh entry.
        #expect(await keychain.loads == 2)
        await factory.shutdownAll()
    }

    @Test("A credential revision bumped by another process makes the cache reload")
    func revisionBumpReloads() async throws {
        let suite = "BucketeerCoreTests.CredentialsRevision.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let keychain = GatedKeychain(secret: Self.oldKey, holds: false)
        let cache = AzureCredentialsCache(keychainStore: keychain, revision: CredentialsRevision(suiteName: suite))
        #expect(try await cache.signer(for: account).accountKeyData == Self.oldKey)

        await keychain.rotate(to: Self.newKey)
        CredentialsRevision(suiteName: suite).bump(for: account.id)

        #expect(try await cache.signer(for: account).accountKeyData == Self.newKey)
    }

    @Test("A revision bumped while the Keychain answers is not ignored by that lookup")
    func revisionBumpDuringLookupReloads() async throws {
        let suite = "BucketeerCoreTests.CredentialsRevision.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let keychain = GatedKeychain(secret: Self.oldKey)
        let cache = AzureCredentialsCache(keychainStore: keychain, revision: CredentialsRevision(suiteName: suite))
        let pending = Task { [account] in try await cache.signer(for: account) }
        await keychain.waitUntilHolding()

        await keychain.rotate(to: Self.newKey)
        CredentialsRevision(suiteName: suite).bump(for: account.id)
        await keychain.release()

        #expect(try await pending.value.accountKeyData == Self.newKey)
    }
}

/// Keychain double whose first `load` parks until `release()`, and
/// which answers with the secret it held when the load started.
private actor GatedKeychain: KeychainStoring {
    private var secret: Data
    private var holdsNext: Bool
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var loads = 0

    init(secret: Data, holds: Bool = true) {
        self.secret = secret
        self.holdsNext = holds
    }

    func rotate(to secret: Data) { self.secret = secret }

    func waitUntilHolding() async {
        while gate == nil { await Task.yield() }
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    func load(for accountID: UUID) async throws -> AccountCredentials {
        loads += 1
        let answer = AccountCredentials(accessKey: "teststorage", secretKey: secret.base64EncodedString())
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { gate = $0 }
        }
        return answer
    }

    func save(_ credentials: AccountCredentials, for accountID: UUID) async throws {}
    func delete(for accountID: UUID) async throws {}
}
