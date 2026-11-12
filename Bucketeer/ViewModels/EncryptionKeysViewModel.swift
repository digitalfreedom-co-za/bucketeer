//
//  EncryptionKeysViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import BucketeerCore

/// Drives the Settings → Encryption tab. Phase 13.15. Lists every
/// per-bucket BYOK key + lets the user create or delete one.
@MainActor
@Observable
final class EncryptionKeysViewModel {
    var keys: [BucketEncryptionKey] = [] {
        didSet { encryptedBuckets = Set(keys.map { EncryptedBucket(accountID: $0.accountID, bucket: $0.bucket) }) }
    }
    var accounts: [S3Account] = []
    var error: BucketeerError?

    private var accountsLoaded = false

    private struct EncryptedBucket: Hashable {
        let accountID: UUID
        let bucket: String
    }

    /// Rebuilt whenever `keys` changes, so badges in the bucket grid,
    /// the browser toolbar and the upload flow cost one hash lookup.
    private var encryptedBuckets: Set<EncryptedBucket> = []

    private let keyStore: any EncryptionKeyStoring
    private let accountStore: any AccountStoring
    private let s3Browser: any S3Browsing
    private let gate: BucketEncryptionGate
    private let mountController: MountController
    /// Where the File Provider extension looks up encrypted buckets.
    /// Nil when the App Group container is unavailable (unsigned
    /// builds), where the extension cannot run either.
    private let encryptedBucketListURL: URL?

    init(
        keyStore: any EncryptionKeyStoring,
        accountStore: any AccountStoring,
        s3Browser: any S3Browsing,
        gate: BucketEncryptionGate,
        mountController: MountController,
        encryptedBucketListURL: URL?
    ) {
        self.keyStore = keyStore
        self.accountStore = accountStore
        self.s3Browser = s3Browser
        self.gate = gate
        self.mountController = mountController
        self.encryptedBucketListURL = encryptedBucketListURL
    }

    /// Also mirrors the key list for the File Provider extension, so
    /// every create, delete and launch refreshes it. Failures show
    /// through `error`.
    func reload() async {
        // `refresh` has already published its failure through `error`.
        try? await refresh()
    }

    /// Throwing variant of `reload` for callers that must not report
    /// success when the list or the mirror is stale.
    private func refresh() async throws {
        do {
            keys = try await keyStore.all()
            if let encryptedBucketListURL {
                try EncryptedBucketList.write(keys, to: encryptedBucketListURL)
            }
            accounts = try await accountStore.all()
            accountsLoaded = true
            error = nil
        } catch {
            accountsLoaded = false
            let failure = Self.bucketeerError(error)
            self.error = failure
            throw failure
        }
    }

    /// Feeds the key editor's bucket picker, so a key is only created
    /// for a bucket the account can actually see.
    func bucketNames(for account: S3Account) async throws -> [String] {
        try await s3Browser.listBuckets(account: account).map(\.name)
    }

    /// Confirms that a manually entered bucket exists and the account
    /// can read it, so a typo cannot get a key while the real bucket
    /// stays in plaintext. One listing page serves as the probe.
    func verifyBucket(_ bucket: String, account: S3Account) async throws {
        do {
            _ = try await s3Browser.listObjects(account: account, bucket: bucket, prefix: "", continuationToken: nil)
        } catch BucketeerError.bucketNotFound {
            throw BucketVerificationError.notFound
        } catch {
            let reason = Self.bucketeerError(error).errorDescription ?? error.localizedDescription
            throw BucketVerificationError.unverifiable(reason: reason)
        }
    }

    /// Refuses buckets mounted in Finder: the File Provider extension
    /// writes raw bytes, so Finder copies would stay unencrypted.
    /// Throws instead of setting `error`, so the editor stays open and
    /// shows the failure itself.
    func create(label: String, account: S3Account, bucket: String) async throws {
        guard !isEncrypted(accountID: account.id, bucket: bucket) else {
            throw BucketeerError.unknown(message: String(localized: "encryption.editor.bucketHasKey"))
        }
        do {
            try await mountController.whileUnmounted(account: account, bucket: bucket) {
                _ = try await keyStore.create(label: label, accountID: account.id, bucket: bucket)
            }
        } catch {
            throw Self.bucketeerError(error)
        }
        try await finishCreation(account: account, bucket: bucket)
    }

    /// Second half of `create`, once the key is stored. Throws
    /// `EncryptionKeyRefreshError` when the list or the File Provider
    /// mirror cannot be refreshed, so the editor retries this step
    /// instead of creating the key again.
    func finishCreation(account: S3Account, bucket: String) async throws {
        await gate.invalidate(accountID: account.id, bucket: bucket)
        do {
            try await refresh()
        } catch {
            throw EncryptionKeyRefreshError(reason: Self.bucketeerError(error).errorDescription ?? "\(error)")
        }
    }

    func reassign(_ key: BucketEncryptionKey, to account: S3Account) async -> Bool {
        guard isOrphaned(key) else { return false }
        do {
            try await mountController.whileUnmounted(account: account, bucket: key.bucket) {
                _ = try await keyStore.reassign(key, to: account.id)
            }
            await gate.invalidate(accountID: key.accountID, bucket: key.bucket)
            await gate.invalidate(accountID: account.id, bucket: key.bucket)
            await reload()
            return true
        } catch {
            // A failed rollback can leave both entries. Refresh the
            // mirror and caches even when the move reports an error.
            await gate.invalidate(accountID: key.accountID, bucket: key.bucket)
            await gate.invalidate(accountID: account.id, bucket: key.bucket)
            await reload()
            switch error {
            case EncryptionKeyReassignmentError.conflict:
                self.error = .unknown(message: String(localized: "encryption.reassign.conflict"))
            case EncryptionKeyReassignmentError.verificationFailed:
                self.error = .unknown(message: String(localized: "encryption.reassign.verificationFailed"))
            case EncryptionKeyReassignmentError.rollbackFailed:
                self.error = .unknown(message: String(localized: "encryption.reassign.rollbackFailed"))
            case EncryptionKeyReassignmentError.sourceCleanupFailed:
                self.error = .unknown(message: String(localized: "encryption.reassign.sourceCleanupFailed"))
                return true
            default:
                self.error = Self.bucketeerError(error)
            }
            return false
        }
    }

    func keyCount(accountID: UUID) async throws -> Int {
        try await keyStore.all().filter { $0.accountID == accountID }.count
    }

    func isOrphaned(_ key: BucketEncryptionKey) -> Bool {
        accountsLoaded && !accounts.contains { $0.id == key.accountID }
    }

    func delete(_ key: BucketEncryptionKey) async {
        do {
            try await keyStore.delete(id: key.id)
            await gate.invalidate(accountID: key.accountID, bucket: key.bucket)
            await reload()
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    /// Drives UI hints only; `MountController.mount` and uploads
    /// re-check the key store themselves, so a stale list cannot let a
    /// mount or a plaintext upload through. Reads the in-memory list
    /// loaded by `reload`, never the Keychain.
    func isEncrypted(accountID: UUID, bucket: String) -> Bool {
        encryptedBuckets.contains(EncryptedBucket(accountID: accountID, bucket: bucket))
    }

    /// Resolve an account UUID back to a display name for the list.
    func accountName(for id: UUID) -> String {
        guard accountsLoaded else { return id.uuidString }
        return accounts.first(where: { $0.id == id })?.name ?? String(localized: "encryption.account.deleted")
    }

    private static func bucketeerError(_ error: any Error) -> BucketeerError {
        error as? BucketeerError ?? .unknown(message: error.localizedDescription)
    }
}

/// Why a manually entered bucket was refused before creating a key.
enum BucketVerificationError: LocalizedError, Equatable {
    case notFound
    /// Access, credential or network failure: existence is unknown.
    case unverifiable(reason: String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            String(localized: "encryption.editor.bucketNotFound")
        case .unverifiable(let reason):
            String(localized: "encryption.editor.bucketUnverifiable \(reason)")
        }
    }
}

/// The key is stored, but the key list or the File Provider mirror
/// could not be refreshed.
struct EncryptionKeyRefreshError: LocalizedError {
    let reason: String

    var errorDescription: String? {
        String(localized: "encryption.editor.keyCreatedRefreshFailed \(reason)")
    }
}

/// S3 general-purpose bucket naming rules for a manually entered
/// bucket: 3–63 characters of lowercase letters, digits, dots and
/// hyphens, starting and ending with a letter or digit, no adjacent
/// dots, not an IP address and none of the reserved prefixes and
/// suffixes.
enum S3BucketName {
    private static let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
    private static let edgeCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let lengthRange = 3...63
    private static let reservedPrefixes = ["xn--", "sthree-", "amzn-s3-demo-"]
    private static let reservedSuffixes = ["-s3alias", "--ol-s3", ".mrap", "--x-s3", "--table-s3"]

    static func isValid(_ name: String) -> Bool {
        guard lengthRange.contains(name.count),
              let first = name.first, let last = name.last
        else { return false }
        return name.allSatisfy(allowedCharacters.contains)
            && edgeCharacters.contains(first)
            && edgeCharacters.contains(last)
            && !name.contains("..")
            && !isIPAddress(name)
            && !reservedPrefixes.contains { name.hasPrefix($0) }
            && !reservedSuffixes.contains { name.hasSuffix($0) }
    }

    private static func isIPAddress(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}
