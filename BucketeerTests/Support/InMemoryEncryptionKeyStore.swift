//
//  InMemoryEncryptionKeyStore.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import Foundation
import BucketeerCore

/// Encryption key store that never touches SwiftData or the Keychain.
actor InMemoryEncryptionKeyStore: EncryptionKeyStoring {
    private var keys: [BucketEncryptionKey] = []
    private var material: [UUID: Data] = [:]
    private var failingLookups = 0
    private var failingDeletes = 0

    init(encryptedBuckets: [(accountID: UUID, bucket: String)] = []) {
        keys = encryptedBuckets.map { BucketEncryptionKey(label: "Key", accountID: $0.accountID, bucket: $0.bucket) }
        material = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, Data($0.id.uuidString.utf8.prefix(32))) })
    }

    func all() -> [BucketEncryptionKey] { keys }

    /// The next `count` lookups throw, like a locked Keychain.
    func failNextLookups(_ count: Int) {
        failingLookups = count
    }

    func key(accountID: UUID, bucket: String) throws -> BucketEncryptionKey? {
        if failingLookups > 0 {
            failingLookups -= 1
            throw CocoaError(.fileReadNoPermission)
        }
        return keys.first { $0.accountID == accountID && $0.bucket == bucket }
    }

    func create(label: String, accountID: UUID, bucket: String) -> BucketEncryptionKey {
        let key = BucketEncryptionKey(label: label, accountID: accountID, bucket: bucket)
        keys.append(key)
        material[key.id] = Data(key.id.uuidString.utf8.prefix(32))
        return key
    }

    func copyForReassignment(_ key: BucketEncryptionKey, to accountID: UUID) throws -> BucketEncryptionKey {
        guard !keys.contains(where: { $0.accountID == accountID && $0.bucket == key.bucket }) else {
            throw EncryptionKeyReassignmentError.conflict
        }
        let replacement = BucketEncryptionKey(
            label: key.label, accountID: accountID, bucket: key.bucket, createdAt: key.createdAt
        )
        material[replacement.id] = try keyMaterial(id: key.id)
        keys.append(replacement)
        return replacement
    }

    func keyMaterial(id: UUID) throws -> Data {
        guard let bytes = material[id] else { throw EncryptionError.noKeyForBucket }
        return bytes
    }

    func failNextDeletes(_ count: Int) {
        failingDeletes = count
    }

    func delete(id: UUID) throws {
        material.removeValue(forKey: id)
        if failingDeletes > 0 {
            failingDeletes -= 1
            // Model a metadata failure after the Keychain bytes are gone.
            throw CocoaError(.fileWriteNoPermission)
        }
        keys.removeAll { $0.id == id }
    }
}
