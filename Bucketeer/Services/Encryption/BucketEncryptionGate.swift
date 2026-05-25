//
//  BucketEncryptionGate.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import CryptoKit
import BucketeerCore

/// Lookup wrapper around `EncryptionKeyStoring`. Phase 13.15.
/// `TransferManager` calls into the gate on every upload + download
/// to ask "do you have a key for this (account, bucket)?". When the
/// answer is yes the bytes are wrapped / unwrapped with
/// `BucketeerEnvelope` before / after the wire operation. The gate
/// returns `nil` for unprotected buckets — the transfer pipeline
/// then proceeds with plaintext bytes.
///
/// Caches recent lookups for 30 seconds so a multi-part upload
/// doesn't slam the SwiftData store with one query per part.
actor BucketEncryptionGate {
    private let keyStore: any EncryptionKeyStoring
    private struct CacheEntry {
        let key: SymmetricKey?
        let expiresAt: Date
    }
    private var cache: [String: CacheEntry] = [:]
    private let ttl: TimeInterval = 30

    init(keyStore: any EncryptionKeyStoring) {
        self.keyStore = keyStore
    }

    /// Return the symmetric key for the given bucket, or `nil`
    /// when the bucket is unprotected. Caches both positive and
    /// negative answers.
    func key(accountID: UUID, bucket: String) async -> SymmetricKey? {
        let cacheKey = "\(accountID.uuidString)|\(bucket)"
        if let entry = cache[cacheKey], entry.expiresAt > Date() {
            return entry.key
        }
        let resolved = await resolve(accountID: accountID, bucket: bucket)
        cache[cacheKey] = CacheEntry(key: resolved, expiresAt: Date().addingTimeInterval(ttl))
        return resolved
    }

    /// Invalidate the cache for one bucket — called after the user
    /// creates / deletes a key in the editor so the next transfer
    /// sees the change immediately rather than after the TTL.
    func invalidate(accountID: UUID, bucket: String) {
        cache.removeValue(forKey: "\(accountID.uuidString)|\(bucket)")
    }

    func invalidateAll() {
        cache.removeAll()
    }

    private func resolve(accountID: UUID, bucket: String) async -> SymmetricKey? {
        do {
            guard let meta = try await keyStore.key(accountID: accountID, bucket: bucket) else {
                return nil
            }
            let raw = try await keyStore.keyMaterial(id: meta.id)
            return SymmetricKey(data: raw)
        } catch {
            return nil
        }
    }
}
