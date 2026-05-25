//
//  EncryptionKeyStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import Security
import CryptoKit
import SwiftData

/// SwiftData + Keychain backed `EncryptionKeyStoring`. Phase 13.15.
///
/// Two storage layers — metadata in the host's
/// `BucketeerEncryptionKeys.store` SwiftData container, raw 32-byte
/// keys in the macOS Keychain under
/// `AppEnvironment.keychainServiceEncryption`. Every code path that
/// writes one writes the other in the same async function so callers
/// can never observe a partial state.
///
/// The store deliberately does **not** expose the raw key as a
/// `SymmetricKey` — callers wrap the returned `Data` themselves at
/// the use site so the type-system pressure to keep keys in scope
/// stays where the cryptographic work happens.
@ModelActor
public actor EncryptionKeyStore: EncryptionKeyStoring {
    /// Single-byte keychain key account derived from the metadata
    /// UUID. We avoid hashing for traceability — copy / paste from
    /// Keychain Access maps directly back to a SwiftData record.
    private func keychainAccount(for id: UUID) -> String { id.uuidString }

    public func all() async throws -> [BucketEncryptionKey] {
        do {
            let descriptor = FetchDescriptor<BucketEncryptionKeyRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(\.snapshot)
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func key(accountID: UUID, bucket: String) async throws -> BucketEncryptionKey? {
        do {
            let descriptor = FetchDescriptor<BucketEncryptionKeyRecord>(
                predicate: #Predicate {
                    $0.accountID == accountID && $0.bucket == bucket
                }
            )
            return try modelContext.fetch(descriptor).first?.snapshot
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func create(
        label: String,
        accountID: UUID,
        bucket: String
    ) async throws -> BucketEncryptionKey {
        // Refuse to overwrite an existing key on the same bucket —
        // rotation lands in a future phase as an explicit action.
        if let existing = try await key(accountID: accountID, bucket: bucket) {
            throw BucketeerError.unknown(
                message: "Bucket \(bucket) already has key \"\(existing.label)\"."
            )
        }
        let key = SymmetricKey(size: .bits256)
        let rawBytes = key.withUnsafeBytes { Data($0) }
        let metadata = BucketEncryptionKey(
            label: label,
            accountID: accountID,
            bucket: bucket
        )
        try writeKeychain(id: metadata.id, bytes: rawBytes)
        do {
            modelContext.insert(BucketEncryptionKeyRecord(key: metadata))
            try modelContext.save()
        } catch {
            // Roll back the Keychain entry so we never leak orphan
            // key bytes when the SwiftData write fails.
            try? deleteKeychain(id: metadata.id)
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
        return metadata
    }

    public func keyMaterial(id: UUID) async throws -> Data {
        let bytes = try readKeychain(id: id)
        // Codex audit fix (medium #2): every key in this store is an
        // AES-256 symmetric key — anything that isn't 32 bytes is a
        // corrupted / tampered Keychain item and must not be handed
        // to CryptoKit, which would silently key under it.
        guard bytes.count == 32 else {
            throw BucketeerError.unknown(
                message: "Encryption key on disk is not 32 bytes (got \(bytes.count))."
            )
        }
        return bytes
    }

    public func delete(id: UUID) async throws {
        // Codex audit fix (low #2): delete the Keychain bytes
        // *before* the SwiftData metadata. A Keychain failure here
        // throws; we never end up with raw key material on disk that
        // has no visible record pointing at it. Metadata-without-
        // key is harmless (the snapshot view shows a stale entry the
        // user can re-delete); key-without-metadata is a real
        // forensic-recovery hazard.
        try deleteKeychain(id: id)
        do {
            let descriptor = FetchDescriptor<BucketEncryptionKeyRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try modelContext.fetch(descriptor).first {
                modelContext.delete(record)
                try modelContext.save()
            }
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    // MARK: - Keychain helpers

    private func writeKeychain(id: UUID, bytes: Data) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppEnvironment.keychainServiceEncryption,
            kSecAttrAccount as String: keychainAccount(for: id),
            kSecValueData as String: bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw BucketeerError.keychainFailure(status: status)
        }
        _ = query.removeValue(forKey: kSecValueData as String)
    }

    private func readKeychain(id: UUID) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppEnvironment.keychainServiceEncryption,
            kSecAttrAccount as String: keychainAccount(for: id),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            throw EncryptionError.noKeyForBucket
        }
        if status != errSecSuccess {
            throw BucketeerError.keychainFailure(status: status)
        }
        guard let data = item as? Data else {
            throw BucketeerError.keychainFailure(status: errSecInternalError)
        }
        return data
    }

    private func deleteKeychain(id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppEnvironment.keychainServiceEncryption,
            kSecAttrAccount as String: keychainAccount(for: id)
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw BucketeerError.keychainFailure(status: status)
        }
    }
}
