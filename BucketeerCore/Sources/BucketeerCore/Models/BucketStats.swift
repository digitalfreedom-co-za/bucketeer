//
//  BucketStats.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Sendable aggregate snapshot of a bucket. Built by
/// `BucketStatsCollector` and surfaced to the UI as
/// `BucketDashboardViewModel.stats`. Phase 13.5.
///
/// The collector walks pages up to `pageCap` to keep the dashboard
/// responsive even on huge buckets — if `truncated` is `true` the
/// dashboard shows a "showing first N objects" hint so the user
/// knows the totals are partial.
public struct BucketStats: Hashable, Sendable {
    public let bucket: String
    public let objectCount: Int
    public let folderCount: Int
    public let totalBytes: Int64
    public let largestObjects: [LargestEntry]
    public let lastModifiedAt: Date?
    public let truncated: Bool
    public let pagesWalked: Int
    public let collectedAt: Date

    public struct LargestEntry: Hashable, Sendable, Identifiable {
        public let key: String
        public let size: Int64
        public var id: String { key }
        public init(key: String, size: Int64) {
            self.key = key
            self.size = size
        }
    }

    public init(
        bucket: String,
        objectCount: Int,
        folderCount: Int,
        totalBytes: Int64,
        largestObjects: [LargestEntry],
        lastModifiedAt: Date?,
        truncated: Bool,
        pagesWalked: Int,
        collectedAt: Date = Date()
    ) {
        self.bucket = bucket
        self.objectCount = objectCount
        self.folderCount = folderCount
        self.totalBytes = totalBytes
        self.largestObjects = largestObjects
        self.lastModifiedAt = lastModifiedAt
        self.truncated = truncated
        self.pagesWalked = pagesWalked
        self.collectedAt = collectedAt
    }
}
