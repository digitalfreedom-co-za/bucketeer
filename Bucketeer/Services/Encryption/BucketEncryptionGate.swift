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
/// then proceeds with plaintext bytes — and throws when it cannot
/// tell.
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

    /// Return the symmetric key for the given bucket, or `nil` when the
    /// bucket is unprotected. Throws when the lookup itself fails (locked
    /// Keychain, store error): treating that as "unprotected" would
    /// upload plaintext into an encrypted bucket. Only definite answers
    /// are cached.
    func key(accountID: UUID, bucket: String) async throws -> SymmetricKey? {
        let cacheKey = "\(accountID.uuidString)|\(bucket)"
        if let entry = cache[cacheKey], entry.expiresAt > Date() {
            return entry.key
        }
        let resolved = try await resolve(accountID: accountID, bucket: bucket)
        cache[cacheKey] = CacheEntry(key: resolved, expiresAt: Date().addingTimeInterval(ttl))
        return resolved
    }

    /// Routing helper (server-side copy or not). A failed lookup counts
    /// as encrypted, so the caller takes the round-trip path, whose
    /// upload then fails visibly instead of copying around the gate.
    func isEncrypted(accountID: UUID, bucket: String) async -> Bool {
        do {
            return try await key(accountID: accountID, bucket: bucket) != nil
        } catch {
            return true
        }
    }

    /// Whether a provider-side copy keeps the bytes valid. A copy inside
    /// one bucket keeps the envelope under the same key; across buckets
    /// it is only safe when neither side is encrypted — otherwise the
    /// caller must download (decrypt) and upload (encrypt) instead.
    func allowsServerSideCopy(
        sourceAccountID: UUID,
        sourceBucket: String,
        destinationAccountID: UUID,
        destinationBucket: String
    ) async -> Bool {
        if sourceAccountID == destinationAccountID, sourceBucket == destinationBucket {
            return true
        }
        if await isEncrypted(accountID: sourceAccountID, bucket: sourceBucket) { return false }
        return await !isEncrypted(accountID: destinationAccountID, bucket: destinationBucket)
    }

    /// Invalidate the cache for one bucket — called after the user
    /// creates / deletes a key in the editor so the next transfer
    /// sees the change immediately rather than after the TTL.
    func invalidate(accountID: UUID, bucket: String) {
        cache.removeValue(forKey: "\(accountID.uuidString)|\(bucket)")
    }

    private func resolve(accountID: UUID, bucket: String) async throws -> SymmetricKey? {
        guard let meta = try await keyStore.key(accountID: accountID, bucket: bucket) else {
            return nil
        }
        return SymmetricKey(data: try await keyStore.keyMaterial(id: meta.id))
    }
}
