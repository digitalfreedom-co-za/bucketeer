//
//  InMemoryS3Browser.swift
//  Bucketeer test support
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

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

    func fail(with error: BucketeerError?) {
        failure = error
    }

    func keys(in bucket: String) -> [String] {
        (buckets[bucket] ?? [:]).keys.sorted()
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
        guard let object = buckets[bucket]?[key] else { throw BucketeerError.objectNotFound(key: key) }
        return object
    }

    func delete(account: S3Account, bucket: String, keys: [String]) async throws {
        try check()
        for key in keys { buckets[bucket]?[key] = nil }
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
