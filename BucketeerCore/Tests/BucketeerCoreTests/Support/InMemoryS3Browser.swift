//
//  InMemoryS3Browser.swift
//  Bucketeer test support
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import CryptoKit
import Foundation
import BucketeerCore

/// In-memory `S3Browsing` with S3 listing semantics (one level per call,
/// common prefixes as folders, paged). Uses only BucketeerCore's public
/// API so the Core tests and the host test target can both compile it.
/// Never touches the network or a real account.
actor InMemoryS3Browser: S3Browsing {
    private var buckets: [String: [String: S3Object]] = [:]
    private let pageSize: Int
    /// Thrown by every call when set — drives error-state tests.
    private var failure: BucketeerError?
    private var holdsNextCopy = false
    private var heldCopy: CheckedContinuation<Void, Never>?
    private var revision = 0
    private var pendingRewrite: String?
    private var pendingPut: (trigger: String, key: String)?
    private var contents: [String: [String: Data]] = [:]

    init(pageSize: Int = 1_000) {
        self.pageSize = pageSize
    }

    /// Parks the next `copy` until `releaseHeldCopy()`, so a test can
    /// act while an operation is mid-flight.
    func holdNextCopy() {
        holdsNextCopy = true
    }

    var isHoldingCopy: Bool { heldCopy != nil }

    func releaseHeldCopy() {
        heldCopy?.resume()
        heldCopy = nil
    }

    func addBucket(_ name: String) {
        if buckets[name] == nil { buckets[name] = [:] }
    }

    func put(bucket: String, key: String, size: Int64 = 0, lastModified: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        buckets[bucket, default: [:]][key] = S3Object(
            key: key, size: size, lastModified: lastModified, etag: "etag-\(key)"
        )
    }

    /// Stores `data` under `key` like a PUT would, ETag = MD5 of the
    /// bytes (as S3 does for single-part uploads), honouring the
    /// precondition. Returns the new ETag.
    func write(bucket: String, key: String, data: Data, precondition: WritePrecondition?) throws -> String {
        let existing = buckets[bucket]?[key]
        switch precondition {
        case .ifAbsent where existing != nil:
            throw BucketeerError.preconditionFailed(key: key)
        case .ifMatch(let etag) where !ETag.matches(base: etag, current: existing?.etag):
            throw BucketeerError.preconditionFailed(key: key)
        default:
            break
        }
        let etag = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        buckets[bucket, default: [:]][key] = S3Object(
            key: key, size: Int64(data.count), lastModified: Date(timeIntervalSince1970: 1_800_000_000), etag: etag
        )
        contents[bucket, default: [:]][key] = data
        return etag
    }

    /// Bytes stored through `write`, while the object exists.
    func data(bucket: String, key: String) -> Data? {
        buckets[bucket]?[key] == nil ? nil : contents[bucket]?[key]
    }

    /// Every stored key, folder markers included.
    func storedKeys(in bucket: String) -> Set<String> {
        Set(buckets[bucket, default: [:]].keys)
    }

    /// Replaces the object's contents: same key and size, new ETag.
    func rewrite(bucket: String, key: String) {
        guard let object = buckets[bucket]?[key] else { return }
        revision += 1
        buckets[bucket]?[key] = S3Object(
            key: key, size: object.size, lastModified: object.lastModified, etag: "etag-\(key)-v\(revision)"
        )
    }

    /// Rewrites `key` just before the next HEAD of it, like a writer that
    /// lands after a listing but before the operation acting on it.
    func rewriteBeforeNextHead(of key: String) {
        pendingRewrite = key
    }

    /// Creates `key` (size 7) just before the next HEAD of `trigger`,
    /// like another client writing between a check and a write.
    func putBeforeNextHead(of trigger: String, key: String) {
        pendingPut = (trigger, key)
    }

    func fail(with error: BucketeerError?) {
        failure = error
    }

    // MARK: - S3Browsing

    func listBuckets(account: S3Account) async throws -> [S3Bucket] {
        try check()
        return buckets.keys.sorted().map {
            S3Bucket(name: $0, createdAt: Date(timeIntervalSince1970: 1_700_000_000), region: account.region)
        }
    }

    func listObjects(account: S3Account, bucket: String, prefix: String, continuationToken: String?) async throws -> S3Page {
        try check()
        guard let contents = buckets[bucket] else { throw BucketeerError.bucketNotFound(bucket) }
        var entries: [String: S3Object] = [:]
        for (key, object) in contents where key.hasPrefix(prefix) && key != prefix {
            let rest = key.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") {
                let folderKey = prefix + rest[...slash]
                entries[folderKey] = S3Object(
                    key: folderKey, size: 0, lastModified: .distantPast, etag: "", isFolder: true
                )
            } else {
                entries[key] = object
            }
        }
        let sorted = entries.values.sorted { $0.key < $1.key }
        let start = continuationToken.flatMap(Int.init) ?? 0
        let end = min(start + pageSize, sorted.count)
        let hasMore = end < sorted.count
        return S3Page(
            objects: Array(sorted[start..<end]),
            prefix: prefix,
            continuationToken: hasMore ? String(end) : nil,
            hasMore: hasMore
        )
    }

    func head(account: S3Account, bucket: String, key: String) async throws -> S3Object {
        try check()
        if pendingRewrite == key {
            pendingRewrite = nil
            rewrite(bucket: bucket, key: key)
        }
        if let put = pendingPut, put.trigger == key {
            pendingPut = nil
            self.put(bucket: bucket, key: put.key, size: 7)
        }
        guard let object = buckets[bucket]?[key] else { throw BucketeerError.objectNotFound(key: key) }
        return object
    }

    func delete(account: S3Account, bucket: String, keys: [String]) async throws {
        try check()
        for key in keys { buckets[bucket]?[key] = nil }
    }

    func delete(account: S3Account, bucket: String, key: String, ifMatch etag: String) async throws {
        try check()
        guard let object = buckets[bucket]?[key] else { throw BucketeerError.objectNotFound(key: key) }
        guard ETag.matches(base: etag, current: object.etag) else { throw BucketeerError.preconditionFailed(key: key) }
        buckets[bucket]?[key] = nil
    }

    func copy(account: S3Account, fromBucket: String, fromKey: String, toBucket: String, toKey: String, metadata: [String: String]?) async throws {
        try check()
        if holdsNextCopy {
            holdsNextCopy = false
            await withCheckedContinuation { heldCopy = $0 }
        }
        guard let source = buckets[fromBucket]?[fromKey] else { throw BucketeerError.objectNotFound(key: fromKey) }
        put(bucket: toBucket, key: toKey, size: source.size, lastModified: source.lastModified)
    }

    func copyIfAbsent(account: S3Account, bucket: String, fromKey: String, sourceETag: String, toKey: String) async throws {
        try check()
        guard let source = buckets[bucket]?[fromKey] else { throw BucketeerError.objectNotFound(key: fromKey) }
        guard ETag.matches(base: sourceETag, current: source.etag), buckets[bucket]?[toKey] == nil else {
            throw BucketeerError.preconditionFailed(key: toKey)
        }
        buckets[bucket]?[toKey] = S3Object(key: toKey, size: source.size, lastModified: source.lastModified, etag: source.etag)
        let bytes = contents[bucket]?[fromKey]
        contents[bucket]?[toKey] = bytes
    }

    func createFolder(account: S3Account, bucket: String, prefix: String) async throws {
        try check()
        put(bucket: bucket, key: prefix.hasSuffix("/") ? prefix : prefix + "/")
    }

    func presignedDownloadURL(account: S3Account, bucket: String, key: String, ttl: TimeInterval) async throws -> URL {
        try check()
        return URL(string: "https://demo.invalid/\(bucket)/\(key)?expires=\(Int(ttl))")!
    }

    func listVersions(account: S3Account, bucket: String, key: String) async throws -> [ObjectVersion] {
        try check()
        guard let object = buckets[bucket]?[key] else { return [] }
        return [
            ObjectVersion(key: key, versionId: "v2", isLatest: true, isDeleteMarker: false,
                          size: object.size, lastModified: object.lastModified, etag: object.etag, storageClass: "STANDARD"),
            ObjectVersion(key: key, versionId: "v1", isLatest: false, isDeleteMarker: false,
                          size: object.size / 2, lastModified: object.lastModified.addingTimeInterval(-86_400),
                          etag: "old", storageClass: "STANDARD")
        ]
    }

    func restoreVersion(account: S3Account, bucket: String, key: String, versionId: String) async throws {
        try check()
    }

    func deleteVersion(account: S3Account, bucket: String, key: String, versionId: String) async throws {
        try check()
    }

    func loadMetadata(account: S3Account, bucket: String, key: String) async throws -> ObjectMetadata {
        try check()
        return ObjectMetadata(contentType: "text/plain", cacheControl: "max-age=60",
                              userMetadata: ["owner": "demo"], tags: ["env": "demo"], storageClass: "STANDARD")
    }

    func saveMetadata(account: S3Account, bucket: String, key: String, metadata: ObjectMetadata) async throws {
        try check()
    }

    func loadInsights(account: S3Account, bucket: String) async throws -> BucketInsights {
        try check()
        return BucketInsights(bucket: bucket, lifecycleRules: [], corsRules: [], policyJSON: nil)
    }

    private func check() throws {
        if let failure { throw failure }
    }
}
