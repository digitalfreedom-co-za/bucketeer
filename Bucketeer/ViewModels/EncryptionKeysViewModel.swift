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
    var keys: [BucketEncryptionKey] = []
    var accounts: [S3Account] = []
    var error: BucketeerError?

    private var accountsLoaded = false

    private let keyStore: any EncryptionKeyStoring
    private let accountStore: any AccountStoring
    private let gate: BucketEncryptionGate
    private let mountController: MountController
    /// Where the File Provider extension looks up encrypted buckets.
    /// Nil when the App Group container is unavailable (unsigned
    /// builds), where the extension cannot run either.
    private let encryptedBucketListURL: URL?

    init(
        keyStore: any EncryptionKeyStoring,
        accountStore: any AccountStoring,
        gate: BucketEncryptionGate,
        mountController: MountController,
        encryptedBucketListURL: URL?
    ) {
        self.keyStore = keyStore
        self.accountStore = accountStore
        self.gate = gate
        self.mountController = mountController
        self.encryptedBucketListURL = encryptedBucketListURL
    }

    /// Also mirrors the key list for the File Provider extension, so
    /// every create, delete and launch refreshes it.
    func reload() async {
        accountsLoaded = false
        do {
            keys = try await keyStore.all()
            if let encryptedBucketListURL {
                try EncryptedBucketList.write(keys, to: encryptedBucketListURL)
            }
            accounts = try await accountStore.all()
            accountsLoaded = true
            error = nil
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    /// Refuses buckets mounted in Finder: the File Provider extension
    /// writes raw bytes, so Finder copies would stay unencrypted.
    func create(label: String, account: S3Account, bucket: String) async {
        do {
            try await mountController.whileUnmounted(account: account, bucket: bucket) {
                _ = try await keyStore.create(label: label, accountID: account.id, bucket: bucket)
            }
            await gate.invalidate(accountID: account.id, bucket: bucket)
            await reload()
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
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
            return error == nil
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
            default:
                self.error = error as? BucketeerError ?? .unknown(message: error.localizedDescription)
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

    /// Drives UI hints only; `MountController.mount` re-checks the key
    /// store itself, so a stale list cannot let a mount through.
    func isEncrypted(accountID: UUID, bucket: String) -> Bool {
        keys.contains { $0.accountID == accountID && $0.bucket == bucket }
    }

    /// Resolve an account UUID back to a display name for the list.
    func accountName(for id: UUID) -> String {
        guard accountsLoaded else { return id.uuidString }
        return accounts.first(where: { $0.id == id })?.name ?? String(localized: "encryption.account.deleted")
    }
}
