//
//  TrashedItem.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Whether the local trash kept a recoverable copy of the deleted
/// object. Drives the "Restore" affordance in the trash view —
/// `.cached` is the only state where Restore performs an actual
/// re-upload; the others surface a hint that the object is gone for
/// good unless the provider keeps versions.
public enum TrashCacheStatus: String, Codable, CaseIterable, Sendable {
    /// Cached-file download has not started yet. Transient state.
    case pending
    /// Local copy is on disk; Restore re-uploads it to the original
    /// location (or a chosen alternative).
    case cached
    /// Object exceeded the user-configured size cap; no local copy
    /// was kept. Restore is unavailable.
    case skippedTooLarge
    /// Caching was disabled in Settings; only the metadata is kept.
    case skippedDisabled
    /// Download attempt failed. Restore is unavailable.
    case failed
}

/// Sendable snapshot of one deleted-object record. Persisted via
/// `TrashRecord` and surfaced through `TrashStoring`. Phase 13.4.
///
/// The cached payload (when present) lives at the absolute file URL
/// `cachedFileURL` inside the App's sandbox Application Support
/// directory. The store owns the file's lifetime: it is removed on
/// `forget`, `restore`-after-success, or `purgeExpired`.
public struct TrashedItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let accountID: UUID
    public let accountName: String
    public let bucket: String
    public let key: String
    public let size: Int64
    public let contentType: String?
    public let etag: String?
    public let deletedAt: Date
    public let expiresAt: Date
    public var cacheStatus: TrashCacheStatus
    public var cachedFileName: String?

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        accountName: String,
        bucket: String,
        key: String,
        size: Int64,
        contentType: String?,
        etag: String?,
        deletedAt: Date = Date(),
        expiresAt: Date,
        cacheStatus: TrashCacheStatus = .pending,
        cachedFileName: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.accountName = accountName
        self.bucket = bucket
        self.key = key
        self.size = size
        self.contentType = contentType
        self.etag = etag
        self.deletedAt = deletedAt
        self.expiresAt = expiresAt
        self.cacheStatus = cacheStatus
        self.cachedFileName = cachedFileName
    }

    /// Convenience for the UI — the last path component of the key,
    /// suitable as a display name in the trash table.
    public var displayName: String {
        if let lastSlash = key.lastIndex(of: "/") {
            return String(key[key.index(after: lastSlash)...])
        }
        return key
    }
}
