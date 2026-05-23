//
//  PreviewCache.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import CryptoKit

/// Disk-backed LRU cache for object previews. Sits between
/// `ObjectDetailView` / the system Quick Look panel and the underlying
/// object stores. Files are downloaded once per `(account, bucket, key,
/// etag)` tuple and re-served for the lifetime of the cache or until
/// they're evicted under the 2 GiB cap.
///
/// Threading: actor-isolated to keep the index consistent under
/// concurrent reads. File-IO inside is synchronous but bounded — the
/// active downloads dictionary keeps two requests for the same object
/// from racing each other.
actor PreviewCache {
    /// Auto-download threshold. Objects up to this size are fetched
    /// silently; larger objects require an explicit click in the UI.
    static let autoDownloadThreshold: Int64 = 50 * 1024 * 1024

    /// Total cache size cap before the LRU eviction kicks in.
    static let cacheSizeCap: Int64 = 2 * 1024 * 1024 * 1024 // 2 GiB

    /// On-disk root. Always inside the app sandbox temp dir so no
    /// entitlement is needed and the system can clean it up if disk is
    /// tight.
    private let root: URL

    /// In-process index. Lost on quit; rebuilt lazily on the next
    /// request for a hash that already exists on disk.
    private struct Entry {
        let url: URL
        var size: Int64
        var lastAccess: Date
    }
    private var entries: [String: Entry] = [:]

    /// Downloads currently in flight per cache hash. New callers for
    /// the same hash await the existing task rather than firing a
    /// duplicate fetch.
    private var inflight: [String: Task<URL, Error>] = [:]

    private let downloader: PreviewDownloader

    init(downloader: PreviewDownloader, root: URL? = nil) {
        self.downloader = downloader
        let dir = root ?? FileManager.default
            .temporaryDirectory
            .appending(path: "BucketeerPreviews", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        self.root = dir
    }

    // MARK: - Public API

    /// True when an object meets the auto-download threshold.
    nonisolated func qualifiesForAutoDownload(_ object: S3Object) -> Bool {
        object.size > 0 && object.size <= Self.autoDownloadThreshold
    }

    /// Cached file URL if present, otherwise nil. Updates the access
    /// timestamp on a hit so LRU eviction is meaningful.
    func cachedURL(
        account: S3Account,
        bucket: String,
        key: String,
        etag: String
    ) -> URL? {
        let hash = Self.hash(accountID: account.id, bucket: bucket, key: key, etag: etag)
        if let existing = entries[hash] {
            entries[hash]?.lastAccess = Date()
            return existing.url
        }
        let url = fileURL(for: hash)
        if FileManager.default.fileExists(atPath: url.path) {
            let size = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            entries[hash] = Entry(url: url, size: size, lastAccess: Date())
            return url
        }
        return nil
    }

    /// Returns the cached URL, downloading it on demand if necessary.
    /// Concurrent callers for the same key share a single in-flight
    /// download — the second caller awaits the first's result instead of
    /// pulling the object twice.
    func materialise(
        account: S3Account,
        bucket: String,
        object: S3Object
    ) async throws -> URL {
        let hash = Self.hash(
            accountID: account.id,
            bucket: bucket,
            key: object.key,
            etag: object.etag
        )
        if let cached = cachedURL(
            account: account,
            bucket: bucket,
            key: object.key,
            etag: object.etag
        ) {
            return cached
        }
        if let pending = inflight[hash] {
            return try await pending.value
        }
        let url = fileURL(for: hash)
        let downloader = self.downloader
        let task = Task { () throws -> URL in
            try? FileManager.default.removeItem(at: url)
            try await downloader.fetch(
                account: account,
                bucket: bucket,
                key: object.key,
                to: url
            )
            return url
        }
        inflight[hash] = task
        do {
            let result = try await task.value
            let size = (try? FileManager.default
                .attributesOfItem(atPath: result.path)[.size] as? NSNumber)?
                .int64Value ?? object.size
            entries[hash] = Entry(url: result, size: size, lastAccess: Date())
            inflight[hash] = nil
            evictIfNeeded()
            return result
        } catch {
            inflight[hash] = nil
            throw error
        }
    }

    /// Forget an object — used when the underlying object is renamed or
    /// deleted and the cached preview is no longer valid.
    func evict(account: S3Account, bucket: String, key: String, etag: String) {
        let hash = Self.hash(accountID: account.id, bucket: bucket, key: key, etag: etag)
        if let entry = entries.removeValue(forKey: hash) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    /// Empty the cache. Called from the Hardening phase when the user
    /// asks to free disk space.
    func clearAll() {
        for entry in entries.values {
            try? FileManager.default.removeItem(at: entry.url)
        }
        entries.removeAll()
    }

    // MARK: - LRU

    private func evictIfNeeded() {
        var total: Int64 = entries.values.reduce(0) { $0 + $1.size }
        guard total > Self.cacheSizeCap else { return }
        // Evict by oldest lastAccess until we're back under the cap.
        let ordered = entries
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (hash, entry) in ordered {
            try? FileManager.default.removeItem(at: entry.url)
            entries[hash] = nil
            total -= entry.size
            if total <= Self.cacheSizeCap { return }
        }
    }

    // MARK: - Keying

    /// Public so callers (e.g. ObjectDetailView's `task(id:)`) can build
    /// a deterministic identifier without going through the actor.
    nonisolated static func hash(
        accountID: UUID,
        bucket: String,
        key: String,
        etag: String
    ) -> String {
        let input = "\(accountID.uuidString)|\(bucket)|\(key)|\(etag)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(for hash: String) -> URL {
        // Use the SHA-256 prefix as a subdirectory to keep any single
        // directory under a few thousand files even for heavy users.
        let prefix = String(hash.prefix(2))
        let dir = root.appending(path: prefix, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir.appending(path: hash, directoryHint: .notDirectory)
    }
}
