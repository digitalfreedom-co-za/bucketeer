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
/// `SymmetricKey` is not Sendable on the Xcode 16.0 SDK. This box lets
/// the key leave `BucketEncryptionGate` and enter `TransferManager`.
struct SendableSymmetricKey: @unchecked Sendable {
    let key: SymmetricKey
}

actor BucketEncryptionGate {
    private let keyStore: any EncryptionKeyStoring
    private let confirmBackup: @MainActor @Sendable (BucketEncryptionKey) async -> Bool
    private struct CacheEntry {
        let key: SymmetricKey?
        let expiresAt: Date
    }
    private var cache: [String: CacheEntry] = [:]
    private var declinedBackups: [UUID: Date] = [:]
    private let declineTTL: TimeInterval = 60
    private var backupAuthorizations: [UUID: Task<Void, Error>] = [:]
    /// Bumped by `invalidate`; a lookup that started before an
    /// invalidation is discarded and repeated.
    private var generations: [String: Int] = [:]
    private let ttl: TimeInterval = 30

    init(keyStore: any EncryptionKeyStoring,
         confirmBackup: @escaping @MainActor @Sendable (BucketEncryptionKey) async -> Bool = { _ in false }) {
        self.keyStore = keyStore
        self.confirmBackup = confirmBackup
    }

    /// Return the symmetric key for the given bucket, or `nil` when the
    /// bucket is unprotected. Throws when the lookup itself fails (locked
    /// Keychain, store error): treating that as "unprotected" would
    /// upload plaintext into an encrypted bucket. Only definite answers
    /// are cached.
    func key(accountID: UUID, bucket: String) async throws -> SymmetricKey? {
        let cacheKey = Self.cacheKey(accountID: accountID, bucket: bucket)
        while true {
            if let entry = cache[cacheKey], entry.expiresAt > Date() {
                return entry.key
            }
            let generation = generations[cacheKey, default: 0]
            let resolved = try await resolve(accountID: accountID, bucket: bucket)
            // The key was created or deleted while the store answered:
            // that answer may describe the old state.
            guard generations[cacheKey, default: 0] == generation else { continue }
            cache[cacheKey] = CacheEntry(key: resolved, expiresAt: Date().addingTimeInterval(ttl))
            return resolved
        }
    }

    /// Same lookup as `key`, boxed so a TransferManager actor can await it.
    func sendableKey(accountID: UUID, bucket: String) async throws -> SendableSymmetricKey? {
        try await key(accountID: accountID, bucket: bucket).map(SendableSymmetricKey.init(key:))
    }

    /// Uploads bypass the read cache so backup consent is tied to the exact
    /// current key identity, including immediately after an import replacement.
    func uploadKey(accountID: UUID, bucket: String) async throws -> SendableSymmetricKey? {
        do {
            while let metadata = try await keyStore.key(accountID: accountID, bucket: bucket) {
                if !metadata.backupReady {
                    try await authorizeBackup(metadata)
                }
                try Task.checkCancellation()
                guard try await keyStore.key(accountID: accountID, bucket: bucket)?.id == metadata.id else { continue }
                return SendableSymmetricKey(key: SymmetricKey(data: try await keyStore.keyMaterial(id: metadata.id)))
            }
            return nil
        } catch is CancellationError {
            throw CancellationError()
        } catch EncryptionError.backupNotConfirmed {
            throw EncryptionError.backupNotConfirmed
        } catch EncryptionError.keyRemoved {
            throw EncryptionError.keyRemoved
        } catch {
            throw BucketeerError.unknown(message: String(localized: "encryption.error.lookupFailed \(error.localizedDescription)"))
        }
    }

    private func authorizeBackup(_ metadata: BucketEncryptionKey) async throws {
        declinedBackups = declinedBackups.filter { $0.value > Date() }
        if declinedBackups[metadata.id] != nil { throw EncryptionError.backupNotConfirmed }
        if let pending = backupAuthorizations[metadata.id] {
            try await pending.value
            return
        }
        let pending = Task {
            guard let current = try await keyStore.key(accountID: metadata.accountID, bucket: metadata.bucket),
                  current.id == metadata.id else { throw EncryptionError.keyRemoved }
            if current.backupReady { return }
            guard await confirmBackup(current) else {
                declinedBackups[current.id] = Date().addingTimeInterval(declineTTL)
                throw EncryptionError.backupNotConfirmed
            }
            try await keyStore.markBackupReady(id: current.id)
        }
        backupAuthorizations[metadata.id] = pending
        defer { backupAuthorizations.removeValue(forKey: metadata.id) }
        try await pending.value
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

    /// Key state of one bucket as far as routing can tell.
    enum KeyState: Sendable {
        case encrypted
        case plain
        /// The lookup failed (locked Keychain, store error).
        case unknown

        /// Whether uploads into a bucket in this state must be sealed.
        /// An unknown bucket may have a key, so it counts as keyed: the
        /// upload then fails instead of storing plaintext.
        var requiresEncryption: Bool { self != .plain }
    }

    /// Whether a copy from source to destination would decrypt encrypted
    /// objects and store the plaintext in a bucket without a key. Inside
    /// one bucket the envelope is kept. An unknown state counts against
    /// the user: an unreadable source may be encrypted, an unreadable
    /// destination may have no key.
    nonisolated static func isEncryptedToPlain(
        source: KeyState,
        destination: KeyState,
        sameBucket: Bool
    ) -> Bool {
        guard !sameBucket else { return false }
        return source != .plain && destination != .encrypted
    }

    /// Looks up both buckets and applies `isEncryptedToPlain`, for the
    /// UI to decide whether to ask before it starts a copy.
    func isEncryptedToPlain(
        sourceAccountID: UUID,
        sourceBucket: String,
        destinationAccountID: UUID,
        destinationBucket: String
    ) async -> Bool {
        await isEncryptedToPlain(
            sourceAccountID: sourceAccountID,
            sourceBucket: sourceBucket,
            destinationAccountID: destinationAccountID,
            destinationBucket: destinationBucket,
            destination: keyState(accountID: destinationAccountID, bucket: destinationBucket)
        )
    }

    /// Same check against a destination state the caller looked up once
    /// with `keyState`. Copy, drag and sync derive both the consent check
    /// and the uploads' `requiresEncryption` from that one state, so a
    /// lookup that fails once and succeeds later cannot skip both.
    func isEncryptedToPlain(
        sourceAccountID: UUID,
        sourceBucket: String,
        destinationAccountID: UUID,
        destinationBucket: String,
        destination: KeyState
    ) async -> Bool {
        let sameBucket = sourceAccountID == destinationAccountID && sourceBucket == destinationBucket
        guard !sameBucket else { return false }
        return await Self.isEncryptedToPlain(
            source: keyState(accountID: sourceAccountID, bucket: sourceBucket),
            destination: destination,
            sameBucket: false
        )
    }

    func keyState(accountID: UUID, bucket: String) async -> KeyState {
        do {
            return try await key(accountID: accountID, bucket: bucket) != nil ? .encrypted : .plain
        } catch {
            return .unknown
        }
    }

    /// Invalidate the cache for one bucket — called after the user
    /// creates / deletes a key in the editor so the next transfer
    /// sees the change immediately rather than after the TTL.
    func invalidate(accountID: UUID, bucket: String) {
        let cacheKey = Self.cacheKey(accountID: accountID, bucket: bucket)
        cache.removeValue(forKey: cacheKey)
        generations[cacheKey, default: 0] += 1
    }

    private static func cacheKey(accountID: UUID, bucket: String) -> String {
        "\(accountID.uuidString)|\(bucket)"
    }

    private func resolve(accountID: UUID, bucket: String) async throws -> SymmetricKey? {
        do {
            guard let meta = try await keyStore.key(accountID: accountID, bucket: bucket) else {
                return nil
            }
            return SymmetricKey(data: try await keyStore.keyMaterial(id: meta.id))
        } catch is CancellationError {
            throw CancellationError()
        } catch EncryptionError.keyRemoved {
            throw EncryptionError.keyRemoved
        } catch {
            throw BucketeerError.unknown(message: String(localized: "encryption.error.lookupFailed \(error.localizedDescription)"))
        }
    }
}
