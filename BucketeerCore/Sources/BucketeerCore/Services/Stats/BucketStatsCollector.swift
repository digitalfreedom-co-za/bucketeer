//
//  BucketStatsCollector.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Walks every object page of a bucket and produces a
/// `BucketStats` snapshot. Phase 13.5.
///
/// The collector deliberately walks from the bucket root with an
/// empty prefix to capture every key, but accepts a `pageCap` so
/// truly huge buckets don't hang the dashboard. When the cap is hit
/// the resulting `BucketStats.truncated` is `true` and the UI shows
/// a hint that the totals are partial.
public struct BucketStatsCollector: Sendable {
    public let browser: any S3Browsing
    /// Hard ceiling on pages walked. Defaults to 100 pages × 1000
    /// objects = 100 000 objects, which covers the vast majority of
    /// buckets without burning serious wall-clock on the dashboard.
    public let pageCap: Int
    /// How many largest objects to remember. 10 is plenty for the
    /// "what's hogging the space?" question.
    public let largestKeep: Int

    public init(browser: any S3Browsing, pageCap: Int = 100, largestKeep: Int = 10) {
        self.browser = browser
        self.pageCap = pageCap
        self.largestKeep = largestKeep
    }

    public func collect(account: S3Account, bucket: String) async throws -> BucketStats {
        var objectCount = 0
        var folderCount = 0
        var totalBytes: Int64 = 0
        var lastModified: Date?
        var largest: [(key: String, size: Int64)] = []
        largest.reserveCapacity(largestKeep + 1)
        var continuation: String? = nil
        var pages = 0
        var truncated = false

        repeat {
            try Task.checkCancellation()
            let page = try await browser.listObjects(
                account: account,
                bucket: bucket,
                prefix: "",
                continuationToken: continuation
            )
            pages += 1
            for object in page.objects {
                if object.isFolder {
                    folderCount += 1
                    continue
                }
                objectCount += 1
                totalBytes += object.size
                if lastModified == nil || object.lastModified > (lastModified ?? .distantPast) {
                    lastModified = object.lastModified
                }
                Self.insertLargest(
                    &largest,
                    key: object.key,
                    size: object.size,
                    keep: largestKeep
                )
            }
            continuation = page.continuationToken
            if !page.hasMore { break }
            if pages >= pageCap {
                truncated = true
                break
            }
        } while continuation != nil

        return BucketStats(
            bucket: bucket,
            objectCount: objectCount,
            folderCount: folderCount,
            totalBytes: totalBytes,
            largestObjects: largest.map { BucketStats.LargestEntry(key: $0.key, size: $0.size) },
            lastModifiedAt: lastModified,
            truncated: truncated,
            pagesWalked: pages
        )
    }

    /// Maintain a descending-size top-N list with a single linear
    /// pass per object — cheaper than a heap for `largestKeep == 10`.
    static func insertLargest(
        _ buffer: inout [(key: String, size: Int64)],
        key: String,
        size: Int64,
        keep: Int
    ) {
        if buffer.count < keep {
            buffer.append((key, size))
            buffer.sort { $0.size > $1.size }
            return
        }
        guard let smallest = buffer.last, size > smallest.size else { return }
        buffer.removeLast()
        buffer.append((key, size))
        buffer.sort { $0.size > $1.size }
    }
}
