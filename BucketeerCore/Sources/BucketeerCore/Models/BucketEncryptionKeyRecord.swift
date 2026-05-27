//
//  BucketEncryptionKeyRecord.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import SwiftData

/// SwiftData metadata for a `BucketEncryptionKey`. Phase 13.15. The
/// 256-bit symmetric key itself lives in the Keychain, addressed by
/// the same `id` — see `EncryptionKeychain`. This record stores only
/// the human-readable bits the UI needs to render the key list.
@Model
public final class BucketEncryptionKeyRecord {
    @Attribute(.unique) public var id: UUID
    public var label: String
    public var accountID: UUID
    public var bucket: String
    public var createdAt: Date

    public init(key: BucketEncryptionKey) {
        self.id = key.id
        self.label = key.label
        self.accountID = key.accountID
        self.bucket = key.bucket
        self.createdAt = key.createdAt
    }

    public var snapshot: BucketEncryptionKey {
        BucketEncryptionKey(
            id: id,
            label: label,
            accountID: accountID,
            bucket: bucket,
            createdAt: createdAt
        )
    }
}
