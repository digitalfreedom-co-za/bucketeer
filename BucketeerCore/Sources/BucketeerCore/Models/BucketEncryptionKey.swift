//
//  BucketEncryptionKey.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation

/// Metadata about one bring-your-own-key (BYOK) bucket-protection
/// key. Phase 13.15. The actual 256-bit key material lives in the
/// macOS Keychain — never in this struct — so leaking a snapshot to
/// the UI never leaks the secret.
public struct BucketEncryptionKey: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Display label the user types when creating the key, e.g.
    /// "Photos archive 2026". Free-form text.
    public var label: String
    /// Bucket the key is registered against. One key per bucket in
    /// v1; rotation lands in a later phase as a "previous keys"
    /// list.
    public let accountID: UUID
    public let bucket: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        accountID: UUID,
        bucket: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.accountID = accountID
        self.bucket = bucket
        self.createdAt = createdAt
    }
}
