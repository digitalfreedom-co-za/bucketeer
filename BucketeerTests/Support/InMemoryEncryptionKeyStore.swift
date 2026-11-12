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
    private var failingLookups = 0

    init(encryptedBuckets: [(accountID: UUID, bucket: String)] = []) {
        keys = encryptedBuckets.map { BucketEncryptionKey(label: "Key", accountID: $0.accountID, bucket: $0.bucket) }
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
        return key
    }

    func keyMaterial(id: UUID) -> Data { Data(count: 32) }

    func delete(id: UUID) {
        keys.removeAll { $0.id == id }
    }
}
