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

    private let keyStore: any EncryptionKeyStoring
    private let accountStore: any AccountStoring
    private let gate: BucketEncryptionGate

    init(
        keyStore: any EncryptionKeyStoring,
        accountStore: any AccountStoring,
        gate: BucketEncryptionGate
    ) {
        self.keyStore = keyStore
        self.accountStore = accountStore
        self.gate = gate
    }

    func reload() async {
        do {
            keys = try await keyStore.all()
            accounts = try await accountStore.all()
            error = nil
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func create(label: String, account: S3Account, bucket: String) async {
        do {
            _ = try await keyStore.create(label: label, accountID: account.id, bucket: bucket)
            await gate.invalidate(accountID: account.id, bucket: bucket)
            await reload()
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
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

    /// Resolve an account UUID back to a display name for the list.
    func accountName(for id: UUID) -> String {
        accounts.first(where: { $0.id == id })?.name ?? "(unknown)"
    }
}
