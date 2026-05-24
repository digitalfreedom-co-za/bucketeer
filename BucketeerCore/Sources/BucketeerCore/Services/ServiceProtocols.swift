//
//  ServiceProtocols.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

// MARK: - KeychainStoring

/// Persists S3 credentials in the macOS Keychain access group shared
/// with the File Provider extension. The store knows nothing about
/// accounts beyond their `id`.
public protocol KeychainStoring: Sendable {
    func save(_ credentials: AccountCredentials, for accountID: UUID) async throws
    func load(for accountID: UUID) async throws -> AccountCredentials
    func delete(for accountID: UUID) async throws
}

// MARK: - AccountStoring

/// Persists non-secret account metadata. Backed by SwiftData inside the
/// App Group container.
public protocol AccountStoring: Sendable {
    func all() async throws -> [S3Account]
    func upsert(_ account: S3Account) async throws
    func delete(id: UUID) async throws
    func touchLastUsed(id: UUID) async throws
}

// MARK: - S3Browsing

/// One-shot S3 operations. Implementations build a `SotoS3.S3` per call
/// via `S3ClientFactory`, reusing the cached `AWSClient` for the account.
public protocol S3Browsing: Sendable {
    func listBuckets(account: S3Account) async throws -> [S3Bucket]
    func listObjects(
        account: S3Account,
        bucket: String,
        prefix: String,
        continuationToken: String?
    ) async throws -> S3Page
    func head(account: S3Account, bucket: String, key: String) async throws -> S3Object
    func delete(account: S3Account, bucket: String, keys: [String]) async throws
    func copy(
        account: S3Account,
        fromBucket: String,
        fromKey: String,
        toBucket: String,
        toKey: String,
        metadata: [String: String]?
    ) async throws
    func createFolder(account: S3Account, bucket: String, prefix: String) async throws

    /// Time-limited download URL the user can share without giving the
    /// recipient access to the credentials. S3 family signs via AWS
    /// Signature v4 (Soto `signURL`); Azure family issues a Service
    /// SAS token. The returned URL is anonymous-readable for the
    /// supplied TTL and then expires. Phase 9.9.
    func presignedDownloadURL(
        account: S3Account,
        bucket: String,
        key: String,
        ttl: TimeInterval
    ) async throws -> URL

    /// List every recorded version of an object on a versioning-
    /// enabled bucket. Implementations that don't speak version-aware
    /// listings throw `BucketeerError.featureNotSupported`. Phase 13.6.
    func listVersions(
        account: S3Account,
        bucket: String,
        key: String
    ) async throws -> [ObjectVersion]

    /// Restore the named version as the current state of the object.
    /// On the S3 family this is a `CopyObject` from the source
    /// version to itself; on Azure Blob this copies from the snapshot
    /// URL back onto the live blob. Phase 13.6.
    func restoreVersion(
        account: S3Account,
        bucket: String,
        key: String,
        versionId: String
    ) async throws

    /// Permanently delete one specific version (or delete marker) of
    /// an object. Bypasses the lifecycle rules. Phase 13.6.
    func deleteVersion(
        account: S3Account,
        bucket: String,
        key: String,
        versionId: String
    ) async throws

    /// Fetch the editable metadata + tags for one object. Phase 13.7.
    /// S3 backends combine HeadObject + GetObjectTagging; Azure
    /// combines Get Blob Properties + Get Blob Tags (when supported).
    func loadMetadata(
        account: S3Account,
        bucket: String,
        key: String
    ) async throws -> ObjectMetadata

    /// Persist an edited copy of `metadata`. Implementations decide
    /// which round-trips are needed (S3 typically: CopyObject with
    /// metadataDirective=replace + PutObjectTagging; Azure: Set Blob
    /// Metadata + Set Blob Tags). Phase 13.7.
    func saveMetadata(
        account: S3Account,
        bucket: String,
        key: String,
        metadata: ObjectMetadata
    ) async throws
}

// MARK: - AutoTagRuleStoring

/// Persistence boundary for the auto-tagging rule list. Phase 13.8.
/// Implementations live in a host-only SwiftData container — the
/// File Provider extension never needs rule visibility.
public protocol AutoTagRuleStoring: Sendable {
    func all() async throws -> [AutoTagRule]
    func upsert(_ rule: AutoTagRule) async throws
    func delete(id: UUID) async throws
}

// MARK: - ActivityLogging

/// Records audit-log entries for user-visible operations (uploads,
/// deletes, sync runs, signed URLs, …). Phase 13.1.
///
/// Recording is observation, not the operation itself — implementations
/// MUST NOT throw out of `record(_:)` and SHOULD swallow persistence
/// errors silently. Callers should never `try` the recording call. The
/// store self-purges entries older than `retentionDays` on every
/// `purgeExpired()` invocation, which the host triggers at launch.
public protocol ActivityLogging: Sendable {
    /// Persist one row. Best-effort: never throws, swallows storage
    /// errors so a write failure on the audit path cannot break the
    /// underlying operation the user actually asked for.
    func record(_ entry: ActivityEntry) async

    /// Most-recent first, hard-capped at `limit`.
    func recent(limit: Int) async throws -> [ActivityEntry]

    /// Free-text search + structural filters. All filters are AND-ed.
    /// `text` matches `bucket`, `key`, `accountName`, `syncJobName`,
    /// `message`, and `errorMessage` (case-insensitive substring).
    func search(
        text: String?,
        kinds: Set<ActivityKind>?,
        accountID: UUID?,
        limit: Int
    ) async throws -> [ActivityEntry]

    /// Delete every entry. UI calls this from a confirmation dialog.
    func deleteAll() async throws

    /// Drop entries older than `retentionDays`. Called once at launch.
    func purgeExpired(retentionDays: Int) async

    /// Total row count. Cheap — used in the UI footer.
    func count() async throws -> Int
}

// MARK: - TrashStoring

/// Local soft-delete bin for deleted objects. Phase 13.4.
///
/// The contract is intentionally narrow — the store keeps metadata +
/// (optionally) a cached payload for each deleted object so the user
/// can answer "wait, did I really mean to delete that?" without going
/// back to provider versioning. Implementations:
///
/// 1. MUST own the file lifecycle: every persisted record's payload
///    is removed when the record is forgotten, restored, or purged.
/// 2. MUST tolerate a missing payload on disk (e.g. user wiped the
///    sandbox); the record stays valid, `cacheStatus` flips to
///    `.failed`.
/// 3. MUST treat `record(...)` as non-throwing — soft-delete is
///    observation around the real delete and must not block it.
public protocol TrashStoring: Sendable {
    /// Persist a fresh trash entry. Returns the assigned record id
    /// so the caller can later attach a cached payload via
    /// `markCached(id:fileName:)`.
    func record(_ item: TrashedItem) async

    /// Mark an existing record as having a cached payload on disk.
    /// Idempotent; no-op if the record was forgotten in the meantime.
    func markCached(id: UUID, fileName: String) async

    /// Update the cache status of an existing record without writing
    /// a fileName (e.g. flip to `.skippedTooLarge` or `.failed`).
    func markStatus(id: UUID, status: TrashCacheStatus) async

    /// Most-recent-first list, hard-capped at `limit`.
    func recent(limit: Int) async throws -> [TrashedItem]

    /// Total row count (cheap; used in the trash window footer +
    /// menubar badge).
    func count() async throws -> Int

    /// Remove one record and its cached payload from disk.
    func forget(id: UUID) async throws

    /// Wipe every record and cached payload. UI calls this from a
    /// confirmation dialog.
    func empty() async throws

    /// Drop entries past their `expiresAt`. Called once at launch.
    func purgeExpired() async
}

// MARK: - Transferring

/// Long-running upload / download queue. Reports progress through an
/// `AsyncStream` so view models stay decoupled from the underlying task
/// graph.
public protocol Transferring: Sendable {
    @discardableResult
    func enqueueUpload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?
    ) async -> UUID

    @discardableResult
    func enqueueDownload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL
    ) async -> UUID

    func cancel(id: UUID) async

    /// Live snapshot stream of the current task list. Each yielded value
    /// is the complete state — consumers replace, not merge.
    var tasks: AsyncStream<[TransferTask]> { get }
}